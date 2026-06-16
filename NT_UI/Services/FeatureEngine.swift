import Accelerate
import CoreGraphics
import Foundation

nonisolated protocol FeatureComputing: Sendable {
    func compute(
        task: ResearchTaskDefinition,
        samples: [PencilSample],
        taps: [TapEvent]
    ) async -> TaskFeatureSet
}

actor FeatureEngine: FeatureComputing {
    private let samplingRate = 120.0

    func compute(
        task: ResearchTaskDefinition,
        samples: [PencilSample],
        taps: [TapEvent]
    ) -> TaskFeatureSet {
        if task.interaction == .tapping {
            return tappingFeatures(task: task, taps: taps)
        }

        let points = samples
            .filter { $0.phase != .cancelled && $0.phase != .hover }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = points.first, let last = points.last else {
            return TaskFeatureSet(taskKind: task.kind, qualityFlags: ["无有效采集点"])
        }

        let duration = max(0, last.timestamp - first.timestamp)
        let kinematics = calculateKinematics(points)
        let forces = points.map(\.normalizedForce).filter(\.isFinite)
        let reference = TaskCatalog.referencePoints(
            for: task.kind,
            in: CGSize(width: first.canvasWidth, height: first.canvasHeight)
        )
        let templateErrors = templateError(points: points, reference: reference)
        let pauses = pauseCount(points)
        let tremor = tremorPower(points)

        var values: [String: Double] = [
            "duration": duration,
            "pointCount": Double(points.count),
            "strokeCount": Double(Set(points.map(\.strokeID)).count),
            "pathLength": kinematics.pathLength,
            "avgSpeed": mean(kinematics.speeds),
            "maxSpeed": kinematics.speeds.max() ?? 0,
            "avgAcceleration": mean(kinematics.accelerations.map(abs)),
            "maxAcceleration": kinematics.accelerations.map(abs).max() ?? 0,
            "avgJerk": mean(kinematics.jerks.map(abs)),
            "pauseCount": Double(pauses),
            "forceMean": mean(forces),
            "forceStd": standardDeviation(forces),
            "templateErrorMean": mean(templateErrors),
            "templateErrorMax": templateErrors.max() ?? 0,
            "tremorPower3to8Hz": tremor.power3to8,
            "tremorPower4to6Hz": tremor.power4to6
        ]

        var qualityFlags: [String] = []
        if points.count < 30 { qualityFlags.append("采集点过少") }
        if duration < 0.5 { qualityFlags.append("任务时长过短") }
        if tremor.insufficientData { qualityFlags.append("频域数据不足") }
        if points.contains(where: { $0.inputDevice != .pencil }) {
            qualityFlags.append("包含非 Apple Pencil 输入")
        }
        if task.kind == .spiralStatic || task.kind == .spiralDynamic {
            qualityFlags.append("压力 V2 使用 iPad 垂直压力 proxy：pressure1023 × sin(altitudeAngle)，非训练数位板原始 Z")
        }

        appendTaskSpecificFeatures(task: task, points: points, values: &values)
        return TaskFeatureSet(taskKind: task.kind, values: values, qualityFlags: qualityFlags)
    }

    private func tappingFeatures(task: ResearchTaskDefinition, taps: [TapEvent]) -> TaskFeatureSet {
        let sorted = taps.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else {
            return TaskFeatureSet(taskKind: task.kind, qualityFlags: ["无点击事件"])
        }

        let intervals = zip(sorted.dropFirst(), sorted).map { max(0, $0.timestamp - $1.timestamp) }
        let midpoint = sorted.count / 2
        let firstHalf = Array(sorted.prefix(midpoint))
        let secondHalf = Array(sorted.suffix(sorted.count - midpoint))

        let firstRate = tapRate(firstHalf)
        let secondRate = tapRate(secondHalf)
        let accuracy = Double(sorted.count { $0.isCorrect }) / Double(sorted.count)
        let alternationErrors = zip(sorted.dropFirst(), sorted).count { $0.target == $1.target }

        return TaskFeatureSet(
            taskKind: task.kind,
            values: [
                "duration": last.timestamp - first.timestamp,
                "tapCount": Double(sorted.count),
                "accuracy": accuracy,
                "meanTapInterval": mean(intervals),
                "tapIntervalStd": standardDeviation(intervals),
                "rhythmInstability": coefficientOfVariation(intervals),
                "firstHalfTapRate": firstRate,
                "secondHalfTapRate": secondRate,
                "lateSpeedDecline": firstRate > 0 ? (firstRate - secondRate) / firstRate : 0,
                "errorCount": Double(sorted.count { !$0.isCorrect }),
                "alternationErrorCount": Double(alternationErrors)
            ],
            qualityFlags: sorted.count < 5 ? ["点击事件过少"] : []
        )
    }

    private func appendTaskSpecificFeatures(
        task: ResearchTaskDefinition,
        points: [PencilSample],
        values: inout [String: Double]
    ) {
        let cgPoints = points.map { CGPoint(x: $0.x, y: $0.y) }
        guard !cgPoints.isEmpty else { return }

        let minX = cgPoints.map(\.x).min() ?? 0
        let maxX = cgPoints.map(\.x).max() ?? 0
        let minY = cgPoints.map(\.y).min() ?? 0
        let maxY = cgPoints.map(\.y).max() ?? 0
        let center = CGPoint(x: mean(cgPoints.map(\.x)), y: mean(cgPoints.map(\.y)))
        values["boundingWidth"] = maxX - minX
        values["boundingHeight"] = maxY - minY
        values["drawingCenterX"] = center.x
        values["drawingCenterY"] = center.y

        switch task.kind {
        case .holdRight, .holdLeft:
            let target = CGPoint(x: points[0].canvasWidth / 2, y: points[0].canvasHeight / 2)
            let deviations = cgPoints.map { self.distance($0, target) }
            values["meanCenterDeviation"] = mean(deviations)
            values["maxCenterDeviation"] = deviations.max() ?? 0
            values["xStd"] = standardDeviation(cgPoints.map { Double($0.x) })
            values["yStd"] = standardDeviation(cgPoints.map { Double($0.y) })
            values["driftDistance"] = distance(cgPoints.first!, cgPoints.last!)

        case .circleTracing:
            let radii = cgPoints.map { self.distance($0, center) }
            values["meanRadius"] = mean(radii)
            values["radiusStd"] = standardDeviation(radii)
            values["closureError"] = distance(cgPoints.first!, cgPoints.last!)
            let angularVelocities = calculateAngularVelocities(points: points, center: center)
            values["meanAngularSpeed"] = mean(angularVelocities.map(abs))
            values["angularSpeedStd"] = standardDeviation(angularVelocities)

        case .waveTracing:
            let curvature = calculateCurvature(cgPoints)
            values["curvatureMean"] = mean(curvature)
            values["curvatureStd"] = standardDeviation(curvature)
            values["verticalAmplitude"] = maxY - minY

        case .sentenceCopying:
            let heights = strokeHeights(points)
            values["meanStrokeHeight"] = mean(heights)
            values["strokeHeightStd"] = standardDeviation(heights)
            values["micrographiaIndex"] = regressionSlope(heights)
            values["penLiftCount"] = Double(max(0, Set(points.map(\.strokeID)).count - 1))

        case .clockCommand, .clockCopy:
            values["drawingArea"] = (maxX - minX) * (maxY - minY)
            values["initialHesitation"] = initialHesitation(points)
            if task.kind == .clockCopy {
                let reference = TaskCatalog.referencePoints(
                    for: .clockCopy,
                    in: CGSize(width: points[0].canvasWidth, height: points[0].canvasHeight)
                )
                values["normalizedChamferSimilarity"] = chamferSimilarity(points: cgPoints, reference: reference)
            }

        default:
            break
        }
    }

    private func calculateKinematics(_ points: [PencilSample]) -> (
        pathLength: Double,
        speeds: [Double],
        accelerations: [Double],
        jerks: [Double]
    ) {
        var pathLength = 0.0
        var speeds: [Double] = []
        for (current, previous) in zip(points.dropFirst(), points) {
            guard current.strokeID == previous.strokeID else { continue }
            let deltaTime = current.timestamp - previous.timestamp
            guard deltaTime > 0 else { continue }
            let segment = hypot(current.x - previous.x, current.y - previous.y)
            pathLength += segment
            speeds.append(segment / deltaTime)
        }

        let accelerations = derivative(speeds, times: points.dropFirst().map(\.timestamp))
        let jerks = derivative(accelerations, times: Array(points.dropFirst(2)).map(\.timestamp))
        return (pathLength, speeds, accelerations, jerks)
    }

    private func derivative(_ values: [Double], times: [Double]) -> [Double] {
        guard values.count > 1, times.count >= values.count else { return [] }
        return values.indices.dropFirst().compactMap { index in
            let delta = times[index] - times[index - 1]
            guard delta > 0 else { return nil }
            return (values[index] - values[index - 1]) / delta
        }
    }

    private func pauseCount(_ points: [PencilSample]) -> Int {
        guard points.count > 1 else { return 0 }
        var count = 0
        var lowSpeedDuration = 0.0

        for (current, previous) in zip(points.dropFirst(), points) {
            let delta = current.timestamp - previous.timestamp
            guard delta > 0 else { continue }
            if current.strokeID != previous.strokeID {
                if delta >= 0.3 { count += 1 }
                lowSpeedDuration = 0
                continue
            }
            let speed = hypot(current.x - previous.x, current.y - previous.y) / delta
            if speed < 5 {
                lowSpeedDuration += delta
                if lowSpeedDuration >= 0.2 {
                    count += 1
                    lowSpeedDuration = -.infinity
                }
            } else {
                lowSpeedDuration = 0
            }
        }
        return count
    }

    private func templateError(points: [PencilSample], reference: [CGPoint]) -> [Double] {
        guard !reference.isEmpty else { return [] }
        return points.map { sample in
            let point = CGPoint(x: sample.x, y: sample.y)
            return reference.lazy.map { self.distance(point, $0) }.min() ?? 0
        }
    }

    private func tremorPower(_ points: [PencilSample]) -> (
        power3to8: Double,
        power4to6: Double,
        insufficientData: Bool
    ) {
        let resampled = resample(points: points, rate: samplingRate)
        guard resampled.x.count >= 128 else { return (0, 0, true) }

        let smoothX = savitzkyGolay(resampled.x)
        let smoothY = savitzkyGolay(resampled.y)
        let residualX = zip(resampled.x, smoothX).map { $0 - $1 }
        let residualY = zip(resampled.y, smoothY).map { $0 - $1 }
        let bandX = spectrumBandPowers(signal: residualX, sampleRate: samplingRate)
        let bandY = spectrumBandPowers(signal: residualY, sampleRate: samplingRate)
        return (
            (bandX.power3to8 + bandY.power3to8) / 2,
            (bandX.power4to6 + bandY.power4to6) / 2,
            false
        )
    }

    private func resample(points: [PencilSample], rate: Double) -> (x: [Double], y: [Double]) {
        guard let first = points.first, let last = points.last, last.timestamp > first.timestamp else {
            return ([], [])
        }
        let step = 1 / rate
        let count = Int((last.timestamp - first.timestamp) / step) + 1
        var x: [Double] = []
        var y: [Double] = []
        x.reserveCapacity(count)
        y.reserveCapacity(count)

        var sourceIndex = 1
        for index in 0..<count {
            let time = first.timestamp + Double(index) * step
            while sourceIndex < points.count - 1 && points[sourceIndex].timestamp < time {
                sourceIndex += 1
            }
            let previous = points[max(0, sourceIndex - 1)]
            let next = points[sourceIndex]
            let duration = next.timestamp - previous.timestamp
            let fraction = duration > 0 ? (time - previous.timestamp) / duration : 0
            x.append(previous.x + (next.x - previous.x) * fraction)
            y.append(previous.y + (next.y - previous.y) * fraction)
        }
        return (x, y)
    }

    private func savitzkyGolay(_ values: [Double]) -> [Double] {
        guard values.count >= 7 else { return values }
        let coefficients = [-2.0, 3, 6, 7, 6, 3, -2].map { $0 / 21 }
        var output = values
        for index in 3..<(values.count - 3) {
            output[index] = zip(coefficients, values[(index - 3)...(index + 3)]).reduce(0) {
                $0 + $1.0 * $1.1
            }
        }
        return output
    }

    private func spectrumBandPowers(signal: [Double], sampleRate: Double) -> (
        power3to8: Double,
        power4to6: Double
    ) {
        let length = 1 << Int(ceil(log2(Double(signal.count))))
        var real = detrend(signal) + Array(repeating: 0, count: length - signal.count)
        var imaginary = Array(repeating: 0.0, count: length)
        var window = Array(repeating: 0.0, count: length)
        vDSP_hann_windowD(&window, vDSP_Length(length), Int32(vDSP_HANN_NORM))
        vDSP_vmulD(real, 1, window, 1, &real, 1, vDSP_Length(length))

        var outputReal = Array(repeating: 0.0, count: length)
        var outputImaginary = Array(repeating: 0.0, count: length)
        guard let setup = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(length), .FORWARD) else {
            return (0, 0)
        }
        defer { vDSP_DFT_DestroySetupD(setup) }
        vDSP_DFT_ExecuteD(setup, &real, &imaginary, &outputReal, &outputImaginary)

        let frequencyResolution = sampleRate / Double(length)
        var power3to8 = 0.0
        var power4to6 = 0.0
        for index in 1..<(length / 2) {
            let frequency = Double(index) * frequencyResolution
            let power = (outputReal[index] * outputReal[index] + outputImaginary[index] * outputImaginary[index])
                / Double(length * length)
            if (3...8).contains(frequency) { power3to8 += power }
            if (4...6).contains(frequency) { power4to6 += power }
        }
        return (power3to8, power4to6)
    }

    private func detrend(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return values }
        let start = values[0]
        let slope = (values[values.count - 1] - start) / Double(values.count - 1)
        return values.enumerated().map { index, value in
            value - (start + Double(index) * slope)
        }
    }

    private func calculateAngularVelocities(points: [PencilSample], center: CGPoint) -> [Double] {
        zip(points.dropFirst(), points).compactMap { current, previous in
            let deltaTime = current.timestamp - previous.timestamp
            guard deltaTime > 0 else { return nil }
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            let previousAngle = atan2(previous.y - center.y, previous.x - center.x)
            var delta = currentAngle - previousAngle
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            return delta / deltaTime
        }
    }

    private func calculateCurvature(_ points: [CGPoint]) -> [Double] {
        guard points.count >= 3 else { return [] }
        return (1..<(points.count - 1)).map { index in
            let a = distance(points[index - 1], points[index])
            let b = distance(points[index], points[index + 1])
            let c = distance(points[index - 1], points[index + 1])
            let area = abs(
                (points[index].x - points[index - 1].x) * (points[index + 1].y - points[index - 1].y)
                    - (points[index].y - points[index - 1].y) * (points[index + 1].x - points[index - 1].x)
            ) / 2
            guard a * b * c > 0 else { return 0 }
            return 4 * area / (a * b * c)
        }
    }

    private func strokeHeights(_ points: [PencilSample]) -> [Double] {
        Dictionary(grouping: points, by: \.strokeID)
            .sorted { $0.key < $1.key }
            .map { _, samples in
                let ys = samples.map(\.y)
                return (ys.max() ?? 0) - (ys.min() ?? 0)
            }
            .filter { $0 > 1 }
    }

    private func initialHesitation(_ points: [PencilSample]) -> Double {
        guard let first = points.first else { return 0 }
        return max(0, first.timestamp - floor(first.timestamp))
    }

    private func chamferSimilarity(points: [CGPoint], reference: [CGPoint]) -> Double {
        guard !points.isEmpty, !reference.isEmpty else { return 0 }
        let averageA = mean(points.map { point in
            reference.lazy.map { self.distance(point, $0) }.min() ?? 0
        })
        let averageB = mean(reference.map { point in
            points.lazy.map { self.distance(point, $0) }.min() ?? 0
        })
        let scale = max(1, hypot(
            (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0),
            (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        ))
        return max(0, 1 - ((averageA + averageB) / 2) / scale)
    }

    private func tapRate(_ taps: [TapEvent]) -> Double {
        guard let first = taps.first, let last = taps.last, last.timestamp > first.timestamp else { return 0 }
        return Double(taps.count) / (last.timestamp - first.timestamp)
    }

    private func regressionSlope(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let xs = values.indices.map(Double.init)
        let meanX = mean(xs)
        let meanY = mean(values)
        let numerator = zip(xs, values).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
        return denominator > 0 ? numerator / denominator : 0
    }

    private func coefficientOfVariation(_ values: [Double]) -> Double {
        let average = mean(values)
        return average > 0 ? standardDeviation(values) / average : 0
    }

    private func mean<T: BinaryFloatingPoint>(_ values: [T]) -> T {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / T(values.count)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let average = mean(values)
        return sqrt(values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count))
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

enum SessionAnalytics {
    static func leftRightDifferences(tasks: [TaskRecord]) -> [String: Double] {
        let pairs: [(ResearchTaskKind, ResearchTaskKind, String)] = [
            (.spiralRight, .spiralLeft, "spiral"),
            (.holdRight, .holdLeft, "hold"),
            (.tappingRight, .tappingLeft, "tapping")
        ]
        var result: [String: Double] = [:]
        for (rightKind, leftKind, prefix) in pairs {
            guard
                let right = tasks.first(where: { $0.taskKind == rightKind })?.features,
                let left = tasks.first(where: { $0.taskKind == leftKind })?.features
            else { continue }
            for key in Set(right.values.keys).intersection(left.values.keys) {
                result["\(prefix)_\(key)_rightMinusLeft"] = (right.values[key] ?? 0) - (left.values[key] ?? 0)
            }
        }
        return result
    }
}
