import CoreGraphics
import CoreML
import XCTest
@testable import NT_UI

final class V2ModelContractTests: XCTestCase {
    func testSpiralV2FeatureContractUsesTwentyEightNamedFeatures() {
        XCTAssertEqual(SpiralFeatureExtractor.featureNames.count, 28)
        XCTAssertEqual(SpiralFeatureExtractor.featureNames.first, "static_duration_s")
        XCTAssertEqual(SpiralFeatureExtractor.featureNames.last, "dynamic_median_relative_angle_change")
    }

    func testPressureV2SchemaUsesSeventyTwoFloatFeaturesAndNaNMissingValue() {
        XCTAssertEqual(PressureModelSchema.featureNames.count, 72)
        XCTAssertEqual(PressureModelSchema.featureNames.first, "test0_static_spiral_acceleration_iqr")
        XCTAssertEqual(PressureModelSchema.featureNames.last, "test1_dynamic_spiral_z_zero_ratio")
        XCTAssertTrue(PressureModelSchema.missingValue.isNaN)
    }

    func testApplePencilSamplesMapToV2ModelUnits() {
        let sample = PencilSample(
            taskID: UUID(),
            timestamp: 12.345,
            point: CGPoint(x: 500, y: 300),
            canvasSize: CGSize(width: 1000, height: 600),
            strokeID: 1,
            phase: .moved,
            force: 2,
            maximumPossibleForce: 4,
            altitudeAngle: .pi / 6,
            azimuthAngle: .pi / 3,
            rollAngle: 0,
            majorRadius: 2,
            inputDevice: .pencil,
            wasCoalesced: true,
            estimatedPropertiesRawValue: 0,
            estimationUpdateIndex: nil
        )

        let spiral = V2ModelInputAdapter.spiralSample(from: sample, testID: 0)
        XCTAssertEqual(spiral.pressure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(spiral.gripAngle, .pi / 6, accuracy: 0.0001)
        XCTAssertEqual(spiral.timestampSeconds, 12.345, accuracy: 0.0001)

        let pressure = V2ModelInputAdapter.pressureSample(from: sample, testID: 1)
        XCTAssertEqual(pressure.x, 500, accuracy: 0.0001)
        XCTAssertEqual(pressure.y, 285, accuracy: 0.0001)
        XCTAssertEqual(pressure.pressure, 511.5, accuracy: 0.0001)
        XCTAssertEqual(pressure.z, 255.75, accuracy: 0.0001)
        XCTAssertEqual(pressure.gripAngleTenthsDegree, 300, accuracy: 0.0001)
        XCTAssertEqual(pressure.timestampMilliseconds, 12_345, accuracy: 0.0001)
        XCTAssertEqual(pressure.testID, 1)
    }

    func testPressureFeatureVectorPreservesNaNForMissingSpectralFeatures() throws {
        let samples = syntheticPressureSamples(countPerTest: 40)
        let vector = try PressureFeatureExtractor().modelVector(samples: samples)

        XCTAssertEqual(vector.count, 72)
        XCTAssertTrue(vector.contains { $0.isNaN })
    }

    func testPressureV2ExampleVectorsSeparateControlAndParkinsonPatterns() throws {
        let model = try ModelResourceLoader.loadModel(named: "ParkinsonXGBoostV2AllCommon")
        let predictor = PressureModelPredictor(model: model)
        let control = try predictor.predict(featureVector: fixtureVector("C_0001_feature_vector"))
        let patient = try predictor.predict(featureVector: fixtureVector("P_02100001_feature_vector"))

        XCTAssertLessThan(control.probabilityParkinsonPattern, patient.probabilityParkinsonPattern)
        XCTAssertLessThan(control.probabilityParkinsonPattern, 0.5)
        XCTAssertGreaterThan(patient.probabilityParkinsonPattern, 0.5)
    }

    private func syntheticPressureSamples(countPerTest: Int) -> [PressureDrawingSample] {
        PressureModelSchema.testIDs.flatMap { testID in
            (0..<countPerTest).map { index in
                let timestamp = Double(index) * 9.1
                return PressureDrawingSample(
                    x: 200 + Double(index),
                    y: 220 + sin(Double(index) / 5) * 20,
                    z: 400 + cos(Double(index) / 6) * 30,
                    pressure: 700 + sin(Double(index) / 4) * 40,
                    gripAngleTenthsDegree: 1_180 + cos(Double(index) / 8) * 20,
                    timestampMilliseconds: timestamp,
                    testID: testID
                )
            }
        }
    }

    private func fixtureVector(_ name: String) throws -> [Double] {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoURL = testsURL.deletingLastPathComponent()
        let url = repoURL.appending(path: "压力interface/examples/\(name).json")
        let fixture = try JSONDecoder().decode(
            FeatureVectorFixture.self,
            from: Data(contentsOf: url)
        )
        return fixture.values_in_feature_schema_order.map { $0 ?? Double.nan }
    }
}

private struct FeatureVectorFixture: Decodable {
    let values_in_feature_schema_order: [Double?]
}
