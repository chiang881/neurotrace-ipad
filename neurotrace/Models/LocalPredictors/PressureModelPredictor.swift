import CoreML
import Foundation

nonisolated public struct PressureModelPrediction: Sendable {
    public let classLabel: Int
    public let probabilityParkinsonPattern: Double

    public var isParkinsonPattern: Bool {
        classLabel == 1
    }
}

nonisolated public enum PressurePredictorError: Error {
    case compiledModelNotFound(String)
    case invalidFeatureCount(expected: Int, actual: Int)
    case missingModelOutput(String)
    case missingParkinsonProbability
}

nonisolated public final class PressureModelPredictor {
    private let model: MLModel
    private let featureExtractor: PressureFeatureExtractor

    public static func defaultConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }

    public init(
        compiledModelURL: URL,
        configuration: MLModelConfiguration =
            PressureModelPredictor.defaultConfiguration()
    ) throws {
        model = try MLModel(
            contentsOf: compiledModelURL,
            configuration: configuration
        )
        featureExtractor = PressureFeatureExtractor()
    }

    public init(model: MLModel) {
        self.model = model
        featureExtractor = PressureFeatureExtractor()
    }

    public convenience init(
        bundle: Bundle = .main,
        resourceName: String = "ParkinsonXGBoostV2AllCommon",
        configuration: MLModelConfiguration =
            PressureModelPredictor.defaultConfiguration()
    ) throws {
        guard let modelURL = bundle.url(
            forResource: resourceName,
            withExtension: "mlmodelc"
        ) else {
            throw PressurePredictorError.compiledModelNotFound(resourceName)
        }
        try self.init(
            compiledModelURL: modelURL,
            configuration: configuration
        )
    }

    public func predict(samples: [PressureDrawingSample]) throws -> PressureModelPrediction {
        let vector = try featureExtractor.modelVector(samples: samples)
        return try predict(featureVector: vector)
    }

    public func predict(
        featureVector: [Double]
    ) throws -> PressureModelPrediction {
        let expectedCount = PressureModelSchema.featureNames.count
        guard featureVector.count == expectedCount else {
            throw PressurePredictorError.invalidFeatureCount(
                expected: expectedCount,
                actual: featureVector.count
            )
        }

        let multiArray = try MLMultiArray(
            shape: [NSNumber(value: expectedCount)],
            dataType: .float32
        )
        for (index, value) in featureVector.enumerated() {
            multiArray[index] = NSNumber(value: Float(value))
        }
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["features": multiArray]
        )
        let output = try model.prediction(from: input)

        guard let label = output.featureValue(
            for: "classLabel"
        )?.int64Value else {
            throw PressurePredictorError.missingModelOutput("classLabel")
        }
        guard let probabilityDictionary = output.featureValue(
            for: "classProbability"
        )?.dictionaryValue else {
            throw PressurePredictorError.missingModelOutput(
                "classProbability"
            )
        }

        for (key, value) in probabilityDictionary {
            if let number = key as? NSNumber, number.intValue == 1 {
                return PressureModelPrediction(
                    classLabel: Int(label),
                    probabilityParkinsonPattern: value.doubleValue
                )
            }
        }
        throw PressurePredictorError.missingParkinsonProbability
    }
}
