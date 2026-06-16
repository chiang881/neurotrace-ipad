import CoreGraphics
import XCTest
@testable import NT_UI

final class TaskCatalogTests: XCTestCase {
    func testQuickModeContainsFixedSixV2Tasks() {
        XCTAssertEqual(
            TaskCatalog.tasks(for: .quick).map(\.kind),
            [
                .spiralStatic, .spiralDynamic,
                .holdRight, .holdLeft,
                .tappingRight, .tappingLeft
            ]
        )
    }

    func testFullModeContainsAllElevenTasksInProtocolOrder() {
        XCTAssertEqual(TaskCatalog.tasks(for: .full).count, 11)
        XCTAssertEqual(TaskCatalog.tasks(for: .full).last?.kind, .clockCopy)
        XCTAssertFalse(TaskCatalog.tasks(for: .full).contains { $0.kind == .spiralRight || $0.kind == .spiralLeft })
    }

    func testLegacySpiralDefinitionsRemainAvailableForHistoricalSessions() {
        XCTAssertEqual(TaskCatalog.definition(for: .spiralRight).hand, .right)
        XCTAssertEqual(TaskCatalog.definition(for: .spiralLeft).hand, .left)
        XCTAssertEqual(TaskCatalog.definition(for: .spiralRight).template, .spiral)
        XCTAssertEqual(TaskCatalog.definition(for: .spiralLeft).template, .spiral)
    }

    func testReferenceTemplatesRemainInsideCanvas() {
        let size = CGSize(width: 1000, height: 600)
        for kind in [ResearchTaskKind.spiralStatic, .waveTracing, .circleTracing, .clockCopy] {
            let points = TaskCatalog.referencePoints(for: kind, in: size)
            XCTAssertFalse(points.isEmpty)
            XCTAssertTrue(points.allSatisfy { point in
                point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height
            })
        }
    }
}
