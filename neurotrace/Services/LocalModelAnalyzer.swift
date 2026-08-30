import CoreML
import Foundation

nonisolated enum ModelResourceLoaderError: LocalizedError {
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name): "未在 App 资源中找到模型 \(name)。"
        }
    }
}

nonisolated enum ModelResourceLoader {
    static func loadModel(
        named name: String,
        bundle: Bundle = .main,
        configuration: MLModelConfiguration = defaultConfiguration()
    ) throws -> MLModel {
        if let compiledURL = findResource(named: name, extension: "mlmodelc", bundle: bundle) {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
        if let modelURL = findResource(named: name, extension: "mlmodel", bundle: bundle) {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
        throw ModelResourceLoaderError.modelNotFound(name)
    }

    private static func defaultConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }

    private static func findResource(
        named name: String,
        extension fileExtension: String,
        bundle: Bundle
    ) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        if let url = bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Models/CoreML"
        ) {
            return url
        }
        guard let root = bundle.resourceURL else { return nil }
        let target = "\(name).\(fileExtension)"
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == target {
                return url
            }
        }
        return nil
    }
}

nonisolated final class LocalModelAnalyzer {
    private let bundle: Bundle
    private var modelCache: [String: MLModel] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func analyzeSpiralV2(
        staticSamples: [PencilSample],
        dynamicSamples: [PencilSample]
    ) -> LocalModelAnalysisResult {
        do {
            let samples = spiralSamples(from: staticSamples, testID: 0)
                + spiralSamples(from: dynamicSamples, testID: 1)
            let model = try loadModel(named: "ParkinsonSpiralXGBV2")
            let prediction = try SpiralModelPredictor(model: model).predict(samples: samples)
            return LocalModelAnalysisResult(
                modelName: "螺旋模型 ParkinsonSpiralXGBV2",
                scope: "静态螺旋 testID 0 + 动态螺旋 testID 1",
                predictedLabel: prediction.label,
                probability: prediction.parkinsonProbability,
                summary: "螺旋轨迹 V2 模型输出研究模式分数 \(Self.percent(prediction.parkinsonProbability))。",
                featureCount: SpiralFeatureExtractor.featureNames.count
            )
        } catch {
            return LocalModelAnalysisResult(
                modelName: "螺旋模型 ParkinsonSpiralXGBV2",
                scope: "静态螺旋 + 动态螺旋",
                summary: "螺旋 V2 模型未能完成推理。",
                featureCount: SpiralFeatureExtractor.featureNames.count,
                errorMessage: Self.describe(error)
            )
        }
    }

    func analyzePressureV2(
        staticSamples: [PencilSample],
        dynamicSamples: [PencilSample]
    ) -> LocalModelAnalysisResult {
        do {
            let converted = pressureSamples(from: staticSamples, testID: 0)
                + pressureSamples(from: dynamicSamples, testID: 1)
            let model = try loadModel(named: "ParkinsonXGBoostV2AllCommon")
            let prediction = try PressureModelPredictor(model: model).predict(samples: converted)
            return LocalModelAnalysisResult(
                modelName: "压力模型 ParkinsonXGBoostV2AllCommon",
                scope: "静态螺旋 testID 0 + 动态螺旋 testID 1；Z 使用 iPad 垂直压力 proxy",
                predictedLabel: prediction.isParkinsonPattern ? "ParkinsonPattern" : "ControlPattern",
                probability: prediction.probabilityParkinsonPattern,
                summary: "压力/运动 V2 模型输出研究模式分数 \(Self.percent(prediction.probabilityParkinsonPattern))；Z 为 pressure1023 × sin(altitudeAngle) proxy。",
                featureCount: PressureModelSchema.featureNames.count
            )
        } catch {
            return LocalModelAnalysisResult(
                modelName: "压力模型 ParkinsonXGBoostV2AllCommon",
                scope: "静态螺旋 + 动态螺旋",
                summary: "压力 V2 模型未能完成推理。",
                featureCount: PressureModelSchema.featureNames.count,
                errorMessage: Self.describe(error)
            )
        }
    }

    private func spiralSamples(
        from samples: [PencilSample],
        testID: Int
    ) -> [SpiralHandwritingSample] {
        samples
            .filter { $0.phase != .cancelled && $0.phase != .hover }
            .sorted { $0.timestamp < $1.timestamp }
            .map { V2ModelInputAdapter.spiralSample(from: $0, testID: testID) }
    }

    private func loadModel(named name: String) throws -> MLModel {
        if let cached = modelCache[name] {
            return cached
        }
        let model = try ModelResourceLoader.loadModel(named: name, bundle: bundle)
        modelCache[name] = model
        return model
    }

    private func pressureSamples(
        from samples: [PencilSample],
        testID: Int
    ) -> [PressureDrawingSample] {
        samples
            .filter { $0.phase != .cancelled && $0.phase != .hover }
            .sorted { $0.timestamp < $1.timestamp }
            .map { V2ModelInputAdapter.pressureSample(from: $0, testID: testID) }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
