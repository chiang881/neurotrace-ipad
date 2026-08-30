#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum IconToolError: Error, CustomStringConvertible {
    case usage
    case invalidArgument(String)
    case unreadableImage(String)
    case contextCreation
    case outputCreation(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: make-squircle-icon.swift <input.png> <output.png> [size=512] [exponent=5.0] [inset=0.02]"
        case .invalidArgument(let name):
            return "Invalid \(name)."
        case .unreadableImage(let path):
            return "Unable to read image: \(path)"
        case .contextCreation:
            return "Unable to create the RGBA drawing context."
        case .outputCreation(let path):
            return "Unable to write image: \(path)"
        }
    }
}

private func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else { throw IconToolError.usage }

    let inputPath = arguments[1]
    let outputPath = arguments[2]
    guard let outputSize = Int(arguments.count > 3 ? arguments[3] : "512"), outputSize > 0 else {
        throw IconToolError.invalidArgument("size")
    }
    guard let exponent = Double(arguments.count > 4 ? arguments[4] : "5.0"), exponent >= 2 else {
        throw IconToolError.invalidArgument("exponent")
    }
    guard let inset = Double(arguments.count > 5 ? arguments[5] : "0.02"), (0..<0.5).contains(inset) else {
        throw IconToolError.invalidArgument("inset")
    }

    let inputURL = URL(fileURLWithPath: inputPath)
    guard
        let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
        let inputImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw IconToolError.unreadableImage(inputPath)
    }

    let bytesPerRow = outputSize * 4
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: outputSize * bytesPerRow)
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let wroteImage = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let context = CGContext(
            data: rawBuffer.baseAddress,
            width: outputSize,
            height: outputSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.interpolationQuality = .high
        context.draw(inputImage, in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))

        let bytes = rawBuffer.bindMemory(to: UInt8.self)
        let center = Double(outputSize) / 2
        let radius = center * (1 - inset)
        let sampleOffsets = [0.125, 0.375, 0.625, 0.875]

        for y in 0..<outputSize {
            for x in 0..<outputSize {
                var insideSamples = 0
                for offsetY in sampleOffsets {
                    for offsetX in sampleOffsets {
                        let normalizedX = abs((Double(x) + offsetX - center) / radius)
                        let normalizedY = abs((Double(y) + offsetY - center) / radius)
                        if pow(normalizedX, exponent) + pow(normalizedY, exponent) <= 1 {
                            insideSamples += 1
                        }
                    }
                }

                let coverage = Double(insideSamples) / Double(sampleOffsets.count * sampleOffsets.count)
                let pixelOffset = y * bytesPerRow + x * 4
                for channel in 0..<4 {
                    bytes[pixelOffset + channel] = UInt8(
                        (Double(bytes[pixelOffset + channel]) * coverage).rounded()
                    )
                }
            }
        }

        guard
            let outputImage = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { return false }

        CGImageDestinationAddImage(destination, outputImage, nil)
        return CGImageDestinationFinalize(destination)
    }

    guard wroteImage else { throw IconToolError.outputCreation(outputPath) }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
