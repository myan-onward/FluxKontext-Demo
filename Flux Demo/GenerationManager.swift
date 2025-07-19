import FluxSwift
import MLX
import SwiftUI
import Hub

@globalActor actor GenerationActor {
  static let shared = GenerationActor()
}

@Observable
@GenerationActor
final class GenerationManager: Sendable {
  enum GenerationState: Equatable {
    case downloading(progress: Double)
    case downloadFailed(Error)
    case loading
    case loadingFailed(Error)
    case generating
    case ready

    static func == (lhs: GenerationState, rhs: GenerationState) -> Bool {
      switch (lhs, rhs) {
        case let (.downloading(l), .downloading(r)): l == r
        case let (.downloadFailed(l), .downloadFailed(r)),
             let (.loadingFailed(l), .loadingFailed(r)):
          l.localizedDescription == r.localizedDescription
        case (.loading, .loading),
             (.generating, .generating),
             (.ready, .ready): true
        default: false
      }
    }
  }

  @MainActor var generationState: GenerationState = .ready
  @MainActor var generatedImage: CGImage?
  @MainActor var generationTimeSeconds: Double?

  @MainActor var currentStep: Int = 0
  @MainActor var totalSteps: Int = 0
  
    let seed:UInt64 = 2

  private let config = FluxConfiguration.flux1KontextDev
    private let loraConfig = FluxLoraConfiguration.flux1TurboAlpha
    private var loadConfig = LoadConfiguration(float16: true, quantize: true)
  private var generator: KontextImageToImageGenerator?

  @MainActor init() {
    Task {
      await load()
    }
  }

  func load() async {
    await MainActor.run {
      generationState = .downloading(progress: 0.0)
    }
    do {
        try await config.download { @Sendable progress in
        Task { @MainActor in
          self.generationState = .downloading(progress: progress.fractionCompleted)
        }
      }
    } catch {
      await MainActor.run {
        generationState = .downloadFailed(error)
      }
    }
      loadConfig = LoadConfiguration(float16: true, quantize: true, loraPath: loraConfig.id)
      if let loraPath = loadConfig.loraPath {
        if !FileManager.default.fileExists(atPath: loraPath) {
            do {
                try await config.downloadLoraWeights(loadConfiguration: loadConfig) { @Sendable progress in
                    Task { @MainActor in
                      self.generationState = .downloading(progress: progress.fractionCompleted)
                    }
                }
            } catch {
                await MainActor.run {
                  generationState = .downloadFailed(error)
                }
            }
        }
      }
    do {
        generator = try config.kontextImageToImageGenerator(configuration: loadConfig)
    } catch {
      await MainActor.run {
        generationState = .loadingFailed(error)
      }
    }
    await MainActor.run {
      generationState = .ready
    }
  }

  private func unpackLatents(_ latents: MLXArray, height: Int, width: Int) -> MLXArray {
    let reshaped = latents.reshaped(1, height / 16, width / 16, 16, 2, 2)
    let transposed = reshaped.transposed(0, 1, 4, 2, 5, 3)
    return transposed.reshaped(1, height / 16 * 2, width / 16 * 2, 16)
  }

  enum GenerationError: Error {
    case decoding, noImage
  }

    func generate(with prompt: String, with image: CGImage) async throws -> CGImage {
    // Set up parameters
        let preferredKontextResolution = KontextUtilities.selectKontextResolution(width: image.width, height: image.height)
        let inferenceSteps = loadConfig.loraPath != nil ? loraConfig.numInferenceSteps : config.defaultParameters().numInferenceSteps
        let guidance = config.id == "kontext" ? 2.5 : config.defaultParameters().guidance  // per Black Forest Lab's sample code
        let shiftSigmas = config.id == "kontext" || config.id == "dev"
        var params: EvaluateParameters = EvaluateParameters(width: preferredKontextResolution.width, height: preferredKontextResolution.height, numInferenceSteps: inferenceSteps, guidance: guidance, seed: seed, prompt: prompt, shiftSigmas: shiftSigmas)
        params.seed = UInt64.random(in: 0..<UInt64.max)
        
    await MainActor.run {
      generatedImage = nil
      generationState = .generating
      generationTimeSeconds = nil
      currentStep = 0
      totalSteps = inferenceSteps + 1 // Add one, since last step is decoding
    }
    let startTime = CFAbsoluteTimeGetCurrent()
    defer {
      Task { @MainActor in
        generationState = .ready
        generationTimeSeconds = CFAbsoluteTimeGetCurrent() - startTime
      }
    }
        
        let inputArray = image.toMLXArray()
        let resized = KontextUtilities.resizeImage(inputArray!, targetWidth: params.width, targetHeight: params.height)
        let normalized = (resized.asType(.float32) / 255) * 2 - 1
        
    // Generate image latents
        var denoiser = generator?.generateKontextLatents(image: normalized, parameters: params)
    var lastXt: MLXArray!
        while let xt = denoiser?.next() {
      let currentStep = denoiser?.i ?? 0
      await MainActor.run {
        self.currentStep = currentStep
          generationTimeSeconds = CFAbsoluteTimeGetCurrent() - startTime
      }
        eval(xt)
      lastXt = xt
            
      // Intermediate update
      let unpackedLatents = unpackLatents(lastXt, height: params.height, width: params.width)
      if let decoded = generator?.decode(xt: unpackedLatents) {
        let imageData = decoded.squeezed()
        let raster = (imageData * 255).asType(.uint8)
        if let cgImage = raster.toCGImage() {
          await MainActor.run {
            generatedImage = cgImage
          }
        }
      }
    }
        
    // Decode latents to image
    let unpackedLatents = unpackLatents(lastXt, height: params.height, width: params.width)
    let decoded = generator?.decode(xt: unpackedLatents)
        
    // Process and save the image
    guard let decoded else {
      print("Error decoding image")
      throw GenerationError.decoding
    }
    let imageData = decoded.squeezed()
    let raster: MLXArray = (imageData * 255).asType(.uint8)
    if let cgImage = raster.toCGImage() {
      await MainActor.run {
        generatedImage = cgImage
      }
        return cgImage
    } else {
      throw GenerationError.noImage
    }
  }

  func decode(xt: MLXArray, imageSize: CGSize) -> MLXArray? {
    let unpackedLatents = unpackLatents(xt, height: Int(imageSize.height), width: Int(imageSize.width))
    return generator?.decode(xt: unpackedLatents)
  }
}
