import SwiftData
import XCTest
import ZIPFoundation
@testable import NT_UI

@MainActor
final class PersistenceAndExportTests: XCTestCase {
    func testInterruptedTaskBecomesNeedsRedo() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let subject = Subject(code: "S001")
        context.insert(subject)

        let store = LocalCaptureStore(rootURL: temporaryRoot())
        let services = AppServices(captureStore: store)
        let session = try services.createSession(subject: subject, mode: .quick, context: context)
        XCTAssertEqual(session.tasks.count, 6)
        XCTAssertEqual(Set(session.tasks.map(\.id)).count, 6)
        let interruptedTask = try XCTUnwrap(session.orderedTasks.first)
        interruptedTask.state = .inProgress
        try context.save()

        try services.recoverInterruptedTasks(context: context)
        XCTAssertEqual(interruptedTask.state, .needsRedo)
        XCTAssertEqual(session.state, .inProgress)
    }

    func testQuickSessionUsesSubjectDominantHand() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let subject = Subject(code: "S-LEFT", dominantHand: .left)
        context.insert(subject)

        let services = AppServices(captureStore: LocalCaptureStore(rootURL: temporaryRoot()))
        let session = try services.createSession(subject: subject, mode: .quick, context: context)

        XCTAssertEqual(session.orderedTasks.map(\.taskKind), [
            .spiralDynamic,
            .holdLeft,
            .tappingLeft,
            .waveTracing,
            .circleTracing,
            .clockCommand
        ])
    }

    func testSessionDisplayNameCanBeCustomizedAndReset() throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let subject = Subject(code: "S-NAME")
        context.insert(subject)

        let services = AppServices(captureStore: LocalCaptureStore(rootURL: temporaryRoot()))
        let session = try services.createSession(subject: subject, mode: .quick, context: context)
        XCTAssertEqual(session.displayName, "S-NAME")
        XCTAssertFalse(session.hasCustomName)

        session.customName = "  晨间基线  "
        try context.save()
        let storedSession = try XCTUnwrap(context.fetch(FetchDescriptor<TestSession>()).first)
        XCTAssertEqual(storedSession.displayName, "晨间基线")
        XCTAssertTrue(storedSession.hasCustomName)

        storedSession.customName = " \n "
        XCTAssertEqual(storedSession.displayName, "S-NAME")
        XCTAssertFalse(storedSession.hasCustomName)
    }

    func testExportContainsRequiredFiles() async throws {
        let container = try inMemoryContainer()
        let context = ModelContext(container)
        let subject = Subject(code: "S-EXPORT")
        context.insert(subject)
        let root = temporaryRoot()
        let store = LocalCaptureStore(rootURL: root)
        let services = AppServices(captureStore: store)
        let session = try services.createSession(subject: subject, mode: .quick, context: context)
        session.customName = "晨间记录"

        for task in session.tasks {
            task.state = .completed
            task.features = TaskFeatureSet(taskKind: task.taskKind, values: ["duration": 1])
        }
        session.state = .completed
        session.completedAt = .now
        session.analysisReport = SessionAnalysisReport(
            status: .completed,
            overallRiskScore: 42,
            summary: "测试报告",
            warnings: ["仅用于测试"],
            taskReports: [
                TaskAnalysisReport(
                    taskKind: .spiralDynamic,
                    title: "动态螺旋",
                    hand: "右手",
                    largeModelResults: [
                        LargeModelAnalysisResult(
                            kind: .image,
                            modelName: "secret-image-model",
                            promptFocus: "测试",
                            summary: "图像结果"
                        )
                    ]
                )
            ]
        )
        try context.save()

        let archiveURL = try await services.exportService.export(session: session)
        XCTAssertTrue(archiveURL.lastPathComponent.contains("晨间记录"))
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let names = Set(archive.map(\.path))
        XCTAssertTrue(names.contains { $0.hasSuffix("manifest.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("subject.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("session.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("raw_points.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("tap_events.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("features.csv") })
        XCTAssertTrue(names.contains { $0.hasSuffix("test_summary.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("analysis_report.json") })
        XCTAssertTrue(names.contains { $0.hasSuffix("analysis_report.md") })

        let manifestData = try extractData(named: "manifest.json", from: archive)
        let manifest = try JSONDecoder.parchment.decode(ExportManifest.self, from: manifestData)
        XCTAssertEqual(manifest.schemaVersion, "2.0.0")
        XCTAssertEqual(manifest.modelVersions["spiral"], "ParkinsonSpiralXGBV2")
        XCTAssertEqual(manifest.modelVersions["pressure"], "ParkinsonXGBoostV2AllCommon")
        XCTAssertEqual(manifest.coordinateMapping["x"], "normalizedX * 1000")
        XCTAssertTrue(manifest.zProxyRule.contains("pressure1023 * sin(altitudeAngle)"))

        let sessionData = try extractData(named: "session.json", from: archive)
        let sessionExport = try JSONDecoder.parchment.decode(SessionExport.self, from: sessionData)
        XCTAssertEqual(sessionExport.recordName, "晨间记录")
        XCTAssertEqual(session.analysisReport?.schemaVersion, "2.0.0")

        let reportText = try XCTUnwrap(String(
            data: extractData(named: "analysis_report.md", from: archive),
            encoding: .utf8
        ))
        XCTAssertTrue(reportText.contains("图像分析：图像结果"))
        XCTAssertFalse(reportText.contains("secret-image-model"))

        let summaryText = try XCTUnwrap(String(
            data: extractData(named: "test_summary.json", from: archive),
            encoding: .utf8
        ))
        XCTAssertTrue(summaryText.contains("spiralModelVersion"))
        XCTAssertTrue(summaryText.contains("pressureSchemaVersion"))
        XCTAssertTrue(summaryText.contains("zProxyRule"))
        XCTAssertTrue(summaryText.contains("晨间记录"))
    }

    func testLargeModelBaseEndpointIsExpanded() throws {
        let client = LargeModelClient(configuration: LargeModelConfiguration(
            isEnabled: true,
            endpoint: "https://www.right.codes/codex/v1",
            apiKey: "",
            model: "test-model"
        ))

        XCTAssertEqual(
            try client.resolvedChatCompletionsEndpointURL().absoluteString,
            "https://www.right.codes/codex/v1/chat/completions"
        )
        XCTAssertEqual(
            try client.resolvedModelsEndpointURL().absoluteString,
            "https://www.right.codes/codex/v1/models"
        )
    }

    func testLargeModelConfigurationRejectsRelativeAndUnsupportedEndpoints() {
        for endpoint in ["api.example.com/v1", "file:///tmp/model", "ftp://example.com/v1"] {
            let configuration = LargeModelConfiguration(
                isEnabled: true,
                endpoint: endpoint,
                apiKey: "",
                model: "test-model"
            )

            XCTAssertFalse(configuration.isReady, endpoint)
            XCTAssertNil(configuration.endpointURL, endpoint)
        }
    }

    func testAPIKeyRoundTripsThroughKeychain() throws {
        let originalValue = SecureAPIKeyStore.load()
        defer { try? SecureAPIKeyStore.save(originalValue) }
        let testValue = "ui-test-\(UUID().uuidString)"

        try SecureAPIKeyStore.save("  \(testValue)  ")
        XCTAssertEqual(SecureAPIKeyStore.load(), testValue)

        try SecureAPIKeyStore.save("")
        XCTAssertEqual(SecureAPIKeyStore.load(), "")
    }

    private func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Subject.self, TestSession.self, TaskRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ParchmentTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func extractData(named suffix: String, from archive: Archive) throws -> Data {
        let entry = try XCTUnwrap(archive.first { $0.path.hasSuffix(suffix) })
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }
}
