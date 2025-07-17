//
//  DataToCGImage.swift
//  Flux Demo
//
//  Created by Michael Yan on 7/16/25.
//

import CoreGraphics
import Foundation

func createCGImageFromPNGData(pngData: Data) -> CGImage? {
    guard let provider = CGDataProvider(data: pngData as CFData) else {
        return nil
    }
    return CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

func resizeCGImage(image: CGImage, to newSize: CGSize) -> CGImage? {
    let context = CGContext(data: nil,
                            width: Int(newSize.width),
                            height: Int(newSize.height),
                            bitsPerComponent: image.bitsPerComponent,
                            bytesPerRow: 0,
                            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: image.bitmapInfo.rawValue)

    context?.draw(image, in: CGRect(origin: .zero, size: newSize))
    return context?.makeImage()
}

