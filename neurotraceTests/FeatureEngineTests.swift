import CoreGraphics
import XCTest
@testable import neurotrace

final class FeatureEngineTests: XCTestCase {
    func testStraightLineKinematics() async {
        let engine = FeatureEngine()
        let task = TaskCatalog.definition(for: .sentenceCopying)
        let samples = (0..<241).map { index in
            makeSample(
                taskID: UUID(),
                timestamp: Double(index) / 120,
                point: CGPoint(x: Double(index), y: 100),
                strokeID: 1
            )
        }

        let result = await engine.compute(task: task, samples: samples, taps: [])
        XCTAssertEqual(result.values["duration"] ?? -1, 2, accuracy: 0.01)
        XCTAssertEqual(result.values["pathLength"] ?? -1, 240, accuracy: 0.1)
        XCTAssertEqual(result.values["avgSpeed"] ?? -1, 120, accuracy: 0.5)
    }

    func testCircleFeaturesMeasureRadiusAndClosure() async {
        let engine = FeatureEngine()
        let task = TaskCatalog.definition(for: .circleTracing)
        let center = CGPoint(x: 500, y: 300)
        let radius = 120.0
        let samples = (0...360).map { index in
            let angle = Double(index) / 360 * 2 * Double.pi
            return makeSample(
                taskID: UUID(),
                timestamp: Double(index) / 120,
                point: CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                ),
                strokeID: 1
            )
        }

        let result = await engine.compute(task: task, samples: samples, taps: [])
        XCTAssertEqual(result.values["meanRadius"] ?? -1, radius, accuracy: 0.5)
        XCTAssertLessThan(result.values["closureError"] ?? 100, 1)
    }

    func testFiveHertzSignalFallsInsideBothTremorBands() async {
        let engine = FeatureEngine()
        let task = TaskCatalog.definition(for: .holdRight)
        let samples = (0..<1_200).map { index in
            let time = Double(index) / 120
            return makeSample(
                taskID: UUID(),
                timestamp: time,
                point: CGPoint(
                    x: 500 + sin(2 * .pi * 5 * time) * 8,
                    y: 300
                ),
                strokeID: 1
            )
        }

        let result = await engine.compute(task: task, samples: samples, taps: [])
        XCTAssertGreaterThan(result.values["tremorPower3to8Hz"] ?? 0, 0)
        XCTAssertGreaterThan(result.values["tremorPower4to6Hz"] ?? 0, 0)
        XCTAssertFalse(result.qualityFlags.contains("频域数据不足"))
    }

    func testTappingAccuracyAndAlternation() async {
        let engine = FeatureEngine()
        let task = TaskCatalog.definition(for: .tappingRight)
        let taskID = UUID()
        let taps = (0..<20).map { index in
            let target: TapTarget = index.isMultiple(of: 2) ? .left : .right
            return TapEvent(
                taskID: taskID,
                timestamp: Double(index) * 0.2,
                sequenceIndex: index + 1,
                point: .zero,
                canvasSize: CGSize(width: 1000, height: 600),
                target: target,
                expectedTarget: target,
                isCorrect: true,
                inputDevice: .finger
            )
        }

        let result = await engine.compute(task: task, samples: [], taps: taps)
        XCTAssertEqual(result.values["accuracy"] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(result.values["alternationErrorCount"] ?? -1, 0)
    }

    private func makeSample(
        taskID: UUID,
        timestamp: TimeInterval,
        point: CGPoint,
        strokeID: Int
    ) -> PencilSample {
        PencilSample(
            taskID: taskID,
            timestamp: timestamp,
            point: point,
            canvasSize: CGSize(width: 1000, height: 600),
            strokeID: strokeID,
            phase: timestamp == 0 ? .began : .moved,
            force: 1,
            maximumPossibleForce: 4,
            altitudeAngle: .pi / 3,
            azimuthAngle: 0,
            rollAngle: 0,
            majorRadius: 2,
            inputDevice: .pencil,
            wasCoalesced: false,
            estimatedPropertiesRawValue: 0,
            estimationUpdateIndex: nil
        )
    }
}
