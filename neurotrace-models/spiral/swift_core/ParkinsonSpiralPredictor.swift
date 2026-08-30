import CoreML
import Foundation

public struct ParkinsonPrediction: Sendable {
    public let label: String
    public let parkinsonProbability: Double
    public let classProbabilities: [String: Double]
}

public enum ParkinsonPredictionError: Error {
    case missingLabel
    case missingProbabilities
}

public final class ParkinsonSpiralPredictor: @unchecked Sendable {
    private let model: MLModel
    private let decisionThreshold: Double

    /// In an iPad app, pass the Xcode-generated model instance's `model` property.
    /// V2 uses 0.45; the V1-compatible default remains 0.5.
    public init(model: MLModel, decisionThreshold: Double = 0.5) {
        precondition((0...1).contains(decisionThreshold))
        self.model = model
        self.decisionThreshold = decisionThreshold
    }

    public func predict(
        samples: [HandwritingSample]
    ) throws -> ParkinsonPrediction {
        let features = try ParkinsonFeatureExtractor.extract(from: samples)
        let provider = try MLDictionaryFeatureProvider(
            dictionary: features.mapValues { NSNumber(value: $0) }
        )
        let output = try model.prediction(from: provider)

        guard let label = output.featureValue(for: "classLabel")?.stringValue else {
            throw ParkinsonPredictionError.missingLabel
        }
        guard
            let rawProbabilities = output.featureValue(
                for: "classProbability"
            )?.dictionaryValue
        else {
            throw ParkinsonPredictionError.missingProbabilities
        }

        var probabilities: [String: Double] = [:]
        for (key, value) in rawProbabilities {
            guard let className = key as? String else {
                continue
            }
            probabilities[className] = value.doubleValue
        }
        let parkinsonProbability = probabilities["Parkinson"] ?? 0
        let thresholdedLabel = decisionThreshold == 0.5
            ? label
            : (parkinsonProbability >= decisionThreshold
                ? "Parkinson"
                : "Healthy")
        return ParkinsonPrediction(
            label: thresholdedLabel,
            parkinsonProbability: parkinsonProbability,
            classProbabilities: probabilities
        )
    }
}
