//
//  ImageToMLXArray.swift
//  Flux Demo
//
//  Created by Michael Yan on 7/16/25.
//

import CoreImage
import MLX

extension CGImage {
  nonisolated func toMLXArray(maximumEdge: Int? = nil) -> MLXArray? {
      // ensure the sizes ar multiples of 64 -- this doesn't worry about
      // the aspect ratio

      var width = self.width
      var height = self.height

      if let maximumEdge {
          func scale(_ edge: Int, _ maxEdge: Int) -> Int {
              Int(round(Float(maximumEdge) / Float(maxEdge) * Float(edge)))
          }

          // aspect fit inside the given maximum
          if width >= height {
              width = scale(width, self.width)
              height = scale(height, self.width)
          } else {
              width = scale(width, self.height)
              height = scale(height, self.height)
          }
      }

      // size must be multiples of 64 -- coerce without regard to aspect ratio
      width = width - width % 64
      height = height - height % 64

      var raster = Data(count: width * 4 * height)
      raster.withUnsafeMutableBytes { ptr in
          let cs = CGColorSpace(name: CGColorSpace.sRGB)!
          let context = CGContext(
              data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: cs,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  | CGBitmapInfo.byteOrder32Big.rawValue)!

          context.draw(
            self, in: CGRect(origin: .zero, size: .init(width: width, height: height)))
      }

      return MLXArray(raster, [height, width, 4], type: UInt8.self)[0..., 0..., ..<3]
  }
}
