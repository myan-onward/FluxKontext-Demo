//
//  DataToCGImage.swift
//  Flux Demo
//
//  Created by Michael Yan on 7/16/25.
//

import CoreGraphics
import Foundation

func createCGImageFromJPEGData(jpegData: Data) -> CGImage? {
    guard let provider = CGDataProvider(data: jpegData as CFData) else {
        return nil
    }
    return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

func createCGImageFromPNGData(pngData: Data) -> CGImage? {
    guard let provider = CGDataProvider(data: pngData as CFData) else {
        return nil
    }
    return CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}
