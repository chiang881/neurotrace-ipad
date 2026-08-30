import Foundation
import NeuroTraceInfrastructure

nonisolated enum NeuroTraceStorage {
    static func dataRoot(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let current = applicationSupport.appending(
            path: NeuroTraceInfrastructureModule.dataDirectoryName,
            directoryHint: .isDirectory
        )
        let legacy = applicationSupport.appending(
            path: NeuroTraceInfrastructureModule.legacyDataDirectoryName,
            directoryHint: .isDirectory
        )

        if fileManager.fileExists(atPath: current.path) {
            return current
        }
        guard fileManager.fileExists(atPath: legacy.path) else {
            return current
        }
        try? fileManager.moveItem(at: legacy, to: current)
        return fileManager.fileExists(atPath: current.path) ? current : legacy
    }
}
