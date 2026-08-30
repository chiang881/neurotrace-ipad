import NeuroTraceInfrastructure
import SwiftData

@MainActor
final class DependencyContainer {
    let modelContainer: ModelContainer
    let services: AppServices
    let backend: any AppBackend

    init() throws {
        let schema = Schema([
            Subject.self,
            TestSession.self,
            TaskRecord.self
        ])
        let configuration = ModelConfiguration(
            NeuroTraceInfrastructureModule.databaseName,
            schema: schema,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        modelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let captureStore = LocalCaptureStore()
        services = AppServices(captureStore: captureStore)
        backend = SwiftDataAppBackend(
            context: modelContainer.mainContext,
            services: services
        )
    }
}
