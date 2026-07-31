import CoreGraphics
import Foundation
import UIKit

enum PreviewRenderer {
    static func render(
        task: ResearchTaskDefinition,
        samples: [PencilSample],
        size: CGSize
    ) -> UIImage {
        let renderSize = CGSize(width: max(640, size.width), height: max(420, size.height))
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        return renderer.image { context in
            let cg = context.cgContext
            UIColor(red: 0.97, green: 0.94, blue: 0.84, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: renderSize))

            let scaleX = size.width > 0 ? renderSize.width / size.width : 1
            let scaleY = size.height > 0 ? renderSize.height / size.height : 1
            cg.saveGState()
            cg.scaleBy(x: scaleX, y: scaleY)

            drawTemplate(task: task, in: cg, size: size)
            drawStrokes(samples: samples, in: cg)
            cg.restoreGState()
        }
    }

    static func save(
        image: UIImage,
        sessionID: UUID,
        taskID: UUID,
        attempt: Int
    ) throws -> String {
        let fileManager = FileManager.default
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ParchmentData", directoryHint: .isDirectory)
        let directory = root.appending(
            path: "sessions/\(sessionID.uuidString)/\(taskID.uuidString)/attempt-\(attempt)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "preview.png")
        guard let data = image.pngData() else { throw PreviewError.encodingFailed }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return "sessions/\(sessionID.uuidString)/\(taskID.uuidString)/attempt-\(attempt)/preview.png"
    }

    private static func drawTemplate(
        task: ResearchTaskDefinition,
        in context: CGContext,
        size: CGSize
    ) {
        let reference = TaskCatalog.referencePoints(for: task.kind, in: size)
        guard !reference.isEmpty else { return }
        context.setStrokeColor(UIColor.gray.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: reference[0])
        reference.dropFirst().forEach(context.addLine)
        context.strokePath()
    }

    private static func drawStrokes(samples: [PencilSample], in context: CGContext) {
        context.setStrokeColor(UIColor(red: 0.19, green: 0.12, blue: 0.08, alpha: 1).cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (_, stroke) in Dictionary(grouping: samples, by: \.strokeID) {
            let sorted = stroke.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first else { continue }
            context.beginPath()
            context.move(to: CGPoint(x: first.x, y: first.y))
            for sample in sorted.dropFirst() {
                context.setLineWidth(max(1.5, 2 + sample.normalizedForce * 3))
                context.addLine(to: CGPoint(x: sample.x, y: sample.y))
            }
            context.strokePath()
        }
    }

    enum PreviewError: Error {
        case encodingFailed
    }
}
