import CoreML
import Foundation

nonisolated public struct SpiralModelPrediction: Sendable {
    public let label: String
    public let parkinsonProbability: Double
    public let classProbabilities: [String: Double]
}

nonisolated public enum SpiralPredictionError: Error {
    case missingLabel
    case missingProbabilities
}

nonisolated public final class SpiralModelPredictor: @unchecked Sendable {
    private let model: MLModel
    private let decisionThreshold: Double

    /// In an iPad app, pass the Xcode-generated model instance's `model` property.
    public init(model: MLModel, decisionThreshold: Double = 0.45) {
        precondition((0...1).contains(decisionThreshold))
        self.model = model
        self.decisionThreshold = decisionThreshold
    }

    public func predict(
        samples: [SpiralHandwritingSample]
    ) throws -> SpiralModelPrediction {
        let features = try SpiralFeatureExtractor.extract(from: samples)
        let provider = try MLDictionaryFeatureProvider(
            dictionary: features.mapValues { NSNumber(value: $0) }
        )
        let output = try model.prediction(from: provider)

        guard let label = output.featureValue(for: "classLabel")?.stringValue else {
            throw SpiralPredictionError.missingLabel
        }
        guard
            let rawProbabilities = output.featureValue(
                for: "classProbability"
            )?.dictionaryValue
        else {
            throw SpiralPredictionError.missingProbabilities
        }

        var probabilities: [String: Double] = [:]
        for (key, value) in rawProbabilities {
            guard let className = key as? String else {
                continue
            }
            probabilities[className] = value.doubleValue
        }
        let parkinsonProbability = probabilities["Parkinson"] ?? 0
        let thresholdedLabel = parkinsonProbability >= decisionThreshold
            ? "Parkinson"
            : "Healthy"
        return SpiralModelPrediction(
            label: decisionThreshold == 0.5 ? label : thresholdedLabel,
            parkinsonProbability: parkinsonProbability,
            classProbabilities: probabilities
        )
    }
}
