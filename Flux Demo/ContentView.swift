import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var image: CGImage?
  @State private var promptText: String = ""
  @State private var generationManager = GenerationManager()
  @State private var showingSavePanel = false
  @State private var showingLoadPanel = false

  var generationManagerIsReady: Bool {
    switch generationManager.generationState {
      case .ready: true
      default: false
    }
  }

  private let verticalSpacing: CGFloat = 20
  private let bottomVStackHeight: CGFloat = 80

  enum Orientation {
    case landscape, portrait
  }

  // TODO: Make these adjustable
  @State var orientation: Orientation = .landscape
  @State var aspectRatio: Double = 4 / 3
  @State var longestSide: CGFloat = 800

  var imageSize: CGSize {
    switch orientation {
      case .landscape: .init(width: longestSide, height: longestSide / aspectRatio)
      case .portrait: .init(width: longestSide / aspectRatio, height: longestSide)
    }
  }

  var body: some View {
    VStack(spacing: verticalSpacing) {
      switch generationManager.generationState {
        case .ready, .generating:
          EmptyView()
        default:
          Text("This app downloads about 35 GB of model files and requires about 16 GB of free RAM.")
            .foregroundColor(.secondary)
      }

      // Image or placeholder
      VStack {
        if let cgImage = generationManager.generatedImage {
          Image(cgImage, scale: 1.0, label: Text(promptText))
            .resizable()
            .scaledToFit()
            .overlay(alignment: .topTrailing) {
              HStack {
                // Share button
                ShareLink(
                  item: Image(cgImage, scale: 1.0, label: Text(promptText)),
                  preview: SharePreview(
                    promptText,
                    image: Image(cgImage, scale: 1.0, label: Text(promptText))
                  )
                ) {
                  Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(generationManager.generationState == .generating)
                  
                // Save button
                Button(action: {
                  showingSavePanel = true
                }) {
                  Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(generationManager.generationState == .generating)
                .fileExporter(
                  isPresented: $showingSavePanel,
                  document: ImageDocument(image: cgImage),
                  contentType: .png,
                  defaultFilename: "Image.png"
                ) { result in
                  if case let .failure(error) = result {
                    print("Error saving file: \(error.localizedDescription)")
                  }
                }
              }
              .padding(8)
            }
        } else if case .generating = generationManager.generationState {
          Rectangle()
            .fill(Color.gray.opacity(0.2))
            .aspectRatio(imageSize.width / imageSize.height, contentMode: .fit)
        }
      }
      .animation(.easeInOut(duration: 0.3), value: generationManager.generatedImage)
      .transition(.opacity)

      VStack(spacing: verticalSpacing) {
        switch generationManager.generationState {
          case let .downloading(progress):
            VStack {
              ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)
              let progressString = String(format: "%.1f%%", progress * 100)
              Text("Downloading model: \(progressString)")
                .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
          case let .downloadFailed(error):
            VStack {
              Text("Download failed: \(error.localizedDescription)")
                .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
          case .loading:
            VStack {
              ProgressView()
              Text("Loading model...")
                .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
          case let .loadingFailed(error):
            VStack {
              Text("Loading model failed: \(error.localizedDescription)")
                .foregroundColor(.secondary)
            }
            .frame(maxHeight: .infinity)
          case .generating:
            VStack(spacing: verticalSpacing) {
              ProgressView()
              Text("Generating: step \(generationManager.currentStep) of \(generationManager.totalSteps)")
                .foregroundColor(.secondary)
            }
            .frame(height: bottomVStackHeight)
          case .ready:
            VStack(spacing: verticalSpacing) {
              HStack {
                  Button {
                      showingLoadPanel = true
                  } label: {
                      Image(systemName: "folder")
                      Text("Choose File...")
                  }
                  .fileImporter(isPresented: $showingLoadPanel, allowedContentTypes: [.png, .jpeg], allowsMultipleSelection: false) { result in
                      switch result {
                      case .success(let files):
                          files.forEach { file in
                              // gain access to the directory
                              let gotAccess = file.startAccessingSecurityScopedResource()
                              if !gotAccess { return }
                              
                              // access the directory URL
                              let pngData = try! Data(contentsOf: file.standardizedFileURL)
                              
                              // release access
                              file.stopAccessingSecurityScopedResource()
                              
                              // create and refresh image
                              var cgImage: CGImage!
                              if file.absoluteString.hasSuffix(".png") {
                                  cgImage = createCGImageFromPNGData(pngData: pngData)
                              } else if file.absoluteString.hasSuffix(".jpeg") || file.absoluteString.hasSuffix(".jpg") {
                                  cgImage = createCGImageFromJPEGData(jpegData: pngData)
                              }
                              image = cgImage
                              generationManager.generatedImage = cgImage
                          }
                      case .failure(let error):
                          print(error.localizedDescription)
                      }
                  }
                  
                TextField("Prompt", text: $promptText)
                  .onSubmit(submit)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
                  .frame(maxWidth: 300)
                Button(action: submit) {
                  Text("Generate")
                }
                .buttonStyle(.bordered)
                .disabled(promptText.isEmpty || !generationManagerIsReady)
              }
              if let generationTime = generationManager.generationTimeSeconds {
                Text(String(format: "Generation time: %.1f seconds", generationTime))
                  .foregroundColor(.secondary)
              }
            }
            .frame(maxHeight: generationManager.generatedImage == nil ? .infinity : nil)
            .frame(minHeight: bottomVStackHeight)
        }
      }
    }
    .padding()
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func submit() {
    Task {
      do {
          image = try await generationManager.generate(with: promptText, with: image!)
      } catch {
        print("Error during load: \(error.localizedDescription)")
      }
    }
  }
}

struct ImageDocument: FileDocument {
  enum ImageDocumentError: Error {
    case pngData
  }

  static var readableContentTypes: [UTType] { [.png] }

  let image: CGImage

  init(image: CGImage) {
    self.image = image
  }

  init(configuration _: ReadConfiguration) throws {
    fatalError("Reading not supported")
  }

  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    let ciImage = CIImage(cgImage: image)
    let context = CIContext(options: nil)
    guard let data = context.pngRepresentation(of: ciImage, format: .RGBA8, colorSpace: ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()) else {
      throw ImageDocumentError.pngData
    }
    return FileWrapper(regularFileWithContents: data)
  }
}
