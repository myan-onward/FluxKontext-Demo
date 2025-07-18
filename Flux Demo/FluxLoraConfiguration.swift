//
//  FluxLoraConfiguration.swift
//  Flux Demo
//
//  Created by Michael Yan on 7/17/25.
//

public struct FluxLoraConfiguration: Sendable {
    public var id: String
    public var guidance: Float
    public var numInferenceSteps: Int
    
    public static let flux1TurboAlpha = FluxLoraConfiguration(
        id: "alimama-creative/FLUX.1-Turbo-Alpha",
        guidance: 3.5,
        numInferenceSteps: 8)
}
