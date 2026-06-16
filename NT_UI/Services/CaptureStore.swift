import Foundation

nonisolated protocol CaptureStore: Sendable {
    func beginRecoveryLog(sessionID: UUID, taskID: UUID, attempt: Int) async throws -> CaptureLogWriter
    func commit(
        sessionID: UUID,
        taskID: UUID,
        attempt: Int,
        samples: [PencilSample],
        taps: [TapEvent]
    ) async throws -> CaptureCommit
    func loadSamples(relativePath: String?) async throws -> [PencilSample]
    func loadTaps(relativePath: String?) async throws -> [TapEvent]
    func absoluteURL(relativePath: String?) async -> URL?
    func removeSession(_ sessionID: UUID) async throws
}

nonisolated struct CaptureCommit: Sendable {
    let samplesRelativePath: String?
    let tapsRelativePath: String?
    let recoveryRelativePath: String
}

actor CaptureLogWriter {
    private let handle: FileHandle
    let relativePath: String
    private var isClosed = false

    init(url: URL, relativePath: String) throws {
        FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        handle = try FileHandle(forWritingTo: url)
        self.relativePath = relativePath
    }

    func append(samples: [PencilSample]) throws {
        guard !isClosed, !samples.isEmpty else { return }
        let encoder = JSONEncoder()
        for sample in samples {
            let data = try encoder.encode(sample)
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        }
    }

    func append(tap: TapEvent) throws {
        guard !isClosed else { return }
        let data = try JSONEncoder().encode(tap)
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
    }

    func close() throws {
        guard !isClosed else { return }
        try handle.synchronize()
        try handle.close()
        isClosed = true
    }
}

actor LocalCaptureStore: CaptureStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootURL = applicationSupport.appending(path: "ParchmentData", directoryHint: .isDirectory)
        }
        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func beginRecoveryLog(sessionID: UUID, taskID: UUID, attempt: Int) throws -> CaptureLogWriter {
        let directory = try attemptDirectory(sessionID: sessionID, taskID: taskID, attempt: attempt)
        let relativePath = relativePath(
            for: directory.appending(path: "recovery.jsonl")
        )
        return try CaptureLogWriter(
            url: rootURL.appending(path: relativePath),
            relativePath: relativePath
        )
    }

    func commit(
        sessionID: UUID,
        taskID: UUID,
        attempt: Int,
        samples: [PencilSample],
        taps: [TapEvent]
    ) throws -> CaptureCommit {
        let directory = try attemptDirectory(sessionID: sessionID, taskID: taskID, attempt: attempt)
        let samplesURL = directory.appending(path: "samples.json")
        let tapsURL = directory.appending(path: "taps.json")
        let recoveryURL = directory.appending(path: "recovery.jsonl")

        var samplesPath: String?
        var tapsPath: String?

        if !samples.isEmpty {
            try JSONEncoder.parchment.encode(samples).write(
                to: samplesURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            samplesPath = relativePath(for: samplesURL)
        }

        if !taps.isEmpty {
            try JSONEncoder.parchment.encode(taps).write(
                to: tapsURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            tapsPath = relativePath(for: tapsURL)
        }

        if !fileManager.fileExists(atPath: recoveryURL.path) {
            fileManager.createFile(
                atPath: recoveryURL.path,
                contents: Data(),
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }

        return CaptureCommit(
            samplesRelativePath: samplesPath,
            tapsRelativePath: tapsPath,
            recoveryRelativePath: relativePath(for: recoveryURL)
        )
    }

    func loadSamples(relativePath: String?) throws -> [PencilSample] {
        guard let url = absoluteURL(relativePath: relativePath) else { return [] }
        return try JSONDecoder.parchment.decode([PencilSample].self, from: Data(contentsOf: url))
    }

    func loadTaps(relativePath: String?) throws -> [TapEvent] {
        guard let url = absoluteURL(relativePath: relativePath) else { return [] }
        return try JSONDecoder.parchment.decode([TapEvent].self, from: Data(contentsOf: url))
    }

    func absoluteURL(relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return rootURL.appending(path: relativePath)
    }

    func removeSession(_ sessionID: UUID) throws {
        let directory = rootURL.appending(path: "sessions/\(sessionID.uuidString)", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func attemptDirectory(sessionID: UUID, taskID: UUID, attempt: Int) throws -> URL {
        let directory = rootURL.appending(
            path: "sessions/\(sessionID.uuidString)/\(taskID.uuidString)/attempt-\(attempt)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(fullPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
