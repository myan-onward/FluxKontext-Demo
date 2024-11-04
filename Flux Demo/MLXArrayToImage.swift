import CoreImage
import MLX

extension MLXArray {
  nonisolated func toCGImage() -> CGImage? {
    // Check for correct number of dimensions (should be 3: height, width, channels)
    guard shape.count == 3 else {
      print("Invalid dimensions: expected 3 (HxWxC), got \(shape.count)")
      return nil
    }
    // Check for correct number of channels (should be 3 for RGB)
    guard shape[2] == 3 else {
      print("Invalid number of channels: expected 3, got \(shape[2])")
      return nil
    }
    let width = shape[1]
    let height = shape[0]
    let bytesPerRow = width * 3
    let mlxData = asData()
    guard let provider = CGDataProvider(data: mlxData.data as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          )
    else {
      print("Failed to create CGImage")
      return nil
    }
    return cgImage
  }
}
