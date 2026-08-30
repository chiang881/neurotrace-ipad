import Foundation

nonisolated public struct PressureDrawingSample: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let pressure: Double
    public let gripAngleTenthsDegree: Double
    public let timestampMilliseconds: Double
    public let testID: Int

    public init(
        x: Double,
        y: Double,
        z: Double,
        pressure: Double,
        gripAngleTenthsDegree: Double,
        timestampMilliseconds: Double,
        testID: Int
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.pressure = pressure
        self.gripAngleTenthsDegree = gripAngleTenthsDegree
        self.timestampMilliseconds = timestampMilliseconds
        self.testID = testID
    }
}

nonisolated public enum PressureFeatureError: Error {
    case noSamples
    case noIncreasingTimestamps(testID: Int)
    case segmentTooShort(testID: Int)
}

nonisolated public struct PressureFeatureExtractor {
    public let targetSampleRateHz: Double

    public init(
        targetSampleRateHz: Double = PressureModelSchema.targetSampleRateHz
    ) {
        self.targetSampleRateHz = targetSampleRateHz
    }

    public func extract(samples: [PressureDrawingSample]) throws -> [String: Double] {
        guard !samples.isEmpty else {
            throw PressureFeatureError.noSamples
        }

        var features: [String: Double] = [:]
        for testID in [0, 1] {
            let segment = samples.filter { $0.testID == testID }
            guard !segment.isEmpty else {
                continue
            }
            let testFeatures = try extractTestFeatures(
                samples: segment,
                testID: testID
            )
            features.merge(testFeatures) { _, newValue in newValue }
        }
        return features
    }

    public func modelVector(samples: [PressureDrawingSample]) throws -> [Double] {
        let features = try extract(samples: samples)
        return PressureModelSchema.featureNames.map { name in
            guard let value = features[name], value.isFinite else {
                return Double(PressureModelSchema.missingValue)
            }
            return value
        }
    }

    private func extractTestFeatures(
        samples: [PressureDrawingSample],
        testID: Int
    ) throws -> [String: Double] {
        let uniform = try uniformlySample(samples: samples, testID: testID)
        let time = uniform.time
        let x = uniform.x
        let y = uniform.y
        let z = uniform.z
        let pressure = uniform.pressure
        let gripAngle = uniform.gripAngleTenthsDegree
        let prefix = testID == 0
            ? "test0_static_spiral"
            : "test1_dynamic_spiral"

        var smoothingWindow = nearestEvenRoundedInt(targetSampleRateHz * 0.05)
        smoothingWindow = max(3, smoothingWindow)
        let xSmooth = movingAverage(x, window: smoothingWindow)
        let ySmooth = movingAverage(y, window: smoothingWindow)
        let vx = gradient(xSmooth, time: time)
        let vy = gradient(ySmooth, time: time)
        let ax = gradient(vx, time: time)
        let ay = gradient(vy, time: time)
        let jx = gradient(ax, time: time)
        let jy = gradient(ay, time: time)

        let speed = zip(vx, vy).map(hypot)
        let acceleration = zip(ax, ay).map(hypot)
        let jerk = zip(jx, jy).map(hypot)
        let direction = unwrap(zip(vy, vx).map { atan2($0, $1) })
        let turnRate = gradient(direction, time: time)
        var curvature = zip(zip(vx, ay), zip(vy, ax)).enumerated().map {
            index, pairs in
            let numerator = abs(pairs.0.0 * pairs.0.1 - pairs.1.0 * pairs.1.1)
            return numerator / (pow(speed[index], 3) + 1e-9)
        }
        let curvatureLimit = quantile(curvature, 0.99)
        curvature = curvature.map { min($0, curvatureLimit) }

        let pressureRate = gradient(pressure, time: time)
        let zRate = gradient(z, time: time)
        let angleRadians = gripAngle.map { $0 / 10.0 * .pi / 180.0 }
        let angleRate = gradient(unwrap(angleRadians), time: time)
        let circularC = mean(angleRadians.map(cos))
        let circularS = mean(angleRadians.map(sin))
        let circularConcentration = hypot(circularC, circularS)
        let circularStd = sqrt(
            max(0, -2 * log(max(circularConcentration, 1e-12)))
        )

        var features: [String: Double] = [
            "\(prefix)_duration_seconds": time.last ?? 0,
            "\(prefix)_pen_down_ratio": ratio(pressure) { $0 > 0 },
            "\(prefix)_pressure_median": median(pressure),
            "\(prefix)_pressure_iqr": iqr(pressure),
            "\(prefix)_pressure_robust_cv": robustCV(pressure),
            "\(prefix)_pressure_p90_p10":
                quantile(pressure, 0.90) - quantile(pressure, 0.10),
            "\(prefix)_pressure_rate_abs_mean":
                mean(pressureRate.map(abs)),
            "\(prefix)_pressure_rate_iqr": iqr(pressureRate),
            "\(prefix)_pressure_zero_ratio": ratio(pressure) { $0 <= 0 },
            "\(prefix)_z_median": median(z),
            "\(prefix)_z_iqr": iqr(z),
            "\(prefix)_z_p90": quantile(z, 0.90),
            "\(prefix)_z_zero_ratio": ratio(z) { $0 == 0 },
            "\(prefix)_z_rate_abs_mean": mean(zRate.map(abs)),
            "\(prefix)_grip_angle_circular_concentration":
                circularConcentration,
            "\(prefix)_grip_angle_circular_std": circularStd,
            "\(prefix)_grip_angle_rate_abs_mean":
                mean(angleRate.map(abs)),
            "\(prefix)_grip_angle_rate_iqr": iqr(angleRate),
            "\(prefix)_speed_median": median(speed),
            "\(prefix)_speed_iqr": iqr(speed),
            "\(prefix)_speed_p90": quantile(speed, 0.90),
            "\(prefix)_speed_robust_cv": robustCV(speed),
            "\(prefix)_stationary_ratio": ratio(speed) { $0 < 1e-6 },
            "\(prefix)_path_length": pathLength(x: xSmooth, y: ySmooth),
            "\(prefix)_acceleration_rms": rms(acceleration),
            "\(prefix)_acceleration_iqr": iqr(acceleration),
            "\(prefix)_jerk_rms": rms(jerk),
            "\(prefix)_jerk_iqr": iqr(jerk),
            "\(prefix)_turn_rate_abs_median":
                median(turnRate.map(abs)),
            "\(prefix)_turn_rate_iqr": iqr(turnRate),
            "\(prefix)_curvature_median": median(curvature),
            "\(prefix)_curvature_p90": quantile(curvature, 0.90),
        ]

        let motionSpectrum = spectralFeatures(
            signals: [xSmooth, ySmooth],
            sampleRateHz: targetSampleRateHz
        )
        for (name, value) in motionSpectrum {
            features["\(prefix)_motion_\(name)"] = value
        }

        let pressureSpectrum = spectralFeatures(
            signals: [pressure],
            sampleRateHz: targetSampleRateHz
        )
        for (name, value) in pressureSpectrum {
            features["\(prefix)_pressure_\(name)"] = value
        }
        return features
    }
}

nonisolated private extension PressureFeatureExtractor {
    struct UniformSignals {
        let time: [Double]
        let x: [Double]
        let y: [Double]
        let z: [Double]
        let pressure: [Double]
        let gripAngleTenthsDegree: [Double]
    }

    struct SampleAccumulator {
        var count = 0.0
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var pressure = 0.0
        var angle = 0.0

        mutating func append(_ sample: PressureDrawingSample) {
            count += 1
            x += sample.x
            y += sample.y
            z += sample.z
            pressure += sample.pressure
            angle += sample.gripAngleTenthsDegree
        }
    }

    func uniformlySample(
        samples: [PressureDrawingSample],
        testID: Int
    ) throws -> UniformSignals {
        var grouped: [Double: SampleAccumulator] = [:]
        for sample in samples {
            grouped[sample.timestampMilliseconds, default: SampleAccumulator()]
                .append(sample)
        }

        let timestamps = grouped.keys.sorted()
        let positiveDeltas = zip(timestamps.dropFirst(), timestamps).compactMap {
            next, previous -> Double? in
            let delta = next - previous
            return delta > 0 ? delta : nil
        }
        guard !positiveDeltas.isEmpty else {
            throw PressureFeatureError.noIncreasingTimestamps(testID: testID)
        }

        let timestampScale = median(positiveDeltas) >= 1 ? 1_000.0 : 1.0
        let origin = timestamps[0]
        let sourceTime = timestamps.map { ($0 - origin) / timestampScale }
        guard let duration = sourceTime.last, duration > 0 else {
            throw PressureFeatureError.noIncreasingTimestamps(testID: testID)
        }

        let sampleCount = max(
            2,
            Int(floor(duration * targetSampleRateHz)) + 1
        )
        let time = (0..<sampleCount)
            .map { Double($0) / targetSampleRateHz }
            .filter { $0 <= duration }
        guard time.count >= 32 else {
            throw PressureFeatureError.segmentTooShort(testID: testID)
        }

        func values(_ value: (SampleAccumulator) -> Double) -> [Double] {
            timestamps.map { timestamp in
                guard let accumulator = grouped[timestamp] else {
                    return 0
                }
                return value(accumulator) / accumulator.count
            }
        }

        return UniformSignals(
            time: time,
            x: interpolate(values(\.x), sourceTime: sourceTime, targetTime: time),
            y: interpolate(values(\.y), sourceTime: sourceTime, targetTime: time),
            z: interpolate(values(\.z), sourceTime: sourceTime, targetTime: time),
            pressure: interpolate(
                values(\.pressure),
                sourceTime: sourceTime,
                targetTime: time
            ),
            gripAngleTenthsDegree: interpolate(
                values(\.angle),
                sourceTime: sourceTime,
                targetTime: time
            )
        )
    }

    func interpolate(
        _ values: [Double],
        sourceTime: [Double],
        targetTime: [Double]
    ) -> [Double] {
        var sourceIndex = 0
        return targetTime.map { target in
            while sourceIndex + 1 < sourceTime.count
                    && sourceTime[sourceIndex + 1] < target {
                sourceIndex += 1
            }
            guard sourceIndex + 1 < sourceTime.count else {
                return values.last ?? 0
            }
            let leftTime = sourceTime[sourceIndex]
            let rightTime = sourceTime[sourceIndex + 1]
            if target <= leftTime || rightTime == leftTime {
                return values[sourceIndex]
            }
            let weight = (target - leftTime) / (rightTime - leftTime)
            return values[sourceIndex]
                + weight * (values[sourceIndex + 1] - values[sourceIndex])
        }
    }

    func movingAverage(_ values: [Double], window requestedWindow: Int) -> [Double] {
        guard values.count >= 3, requestedWindow > 1 else {
            return values
        }
        var window = min(requestedWindow, values.count)
        if window.isMultiple(of: 2) {
            window -= 1
        }
        guard window > 1 else {
            return values
        }

        let half = window / 2
        return values.indices.map { index in
            var sum = 0.0
            for offset in -half...half {
                let sourceIndex = min(max(index + offset, 0), values.count - 1)
                sum += values[sourceIndex]
            }
            return sum / Double(window)
        }
    }

    func gradient(_ values: [Double], time: [Double]) -> [Double] {
        guard values.count > 1 else {
            return Array(repeating: 0, count: values.count)
        }
        var result = Array(repeating: 0.0, count: values.count)
        result[0] = (values[1] - values[0]) / (time[1] - time[0])
        for index in 1..<(values.count - 1) {
            result[index] = (values[index + 1] - values[index - 1])
                / (time[index + 1] - time[index - 1])
        }
        let last = values.count - 1
        result[last] = (values[last] - values[last - 1])
            / (time[last] - time[last - 1])
        return result
    }

    func unwrap(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else {
            return []
        }
        var result = [values[0]]
        var correction = 0.0
        let period = 2 * Double.pi
        for index in 1..<values.count {
            let delta = values[index] - values[index - 1]
            var wrapped = (delta + .pi).truncatingRemainder(
                dividingBy: period
            )
            if wrapped < 0 {
                wrapped += period
            }
            wrapped -= .pi
            if wrapped == -.pi && delta > 0 {
                wrapped = .pi
            }
            let phaseCorrection = abs(delta) < .pi ? 0 : wrapped - delta
            correction += phaseCorrection
            result.append(values[index] + correction)
        }
        return result
    }

    func spectralFeatures(
        signals: [[Double]],
        sampleRateHz: Double
    ) -> [String: Double] {
        let empty = [
            "power_ratio_3_8hz": Double.nan,
            "power_ratio_4_6hz": Double.nan,
            "peak_frequency_3_8hz": Double.nan,
            "spectral_entropy_1_25hz": Double.nan,
        ]
        guard let sampleCount = signals.first?.count, sampleCount >= 64 else {
            return empty
        }

        let minimumBin = max(
            0,
            Int(ceil(Double(sampleCount) / sampleRateHz))
        )
        let maximumBin = min(
            sampleCount / 2,
            Int(floor(25 * Double(sampleCount) / sampleRateHz))
        )
        guard maximumBin >= minimumBin else {
            return empty
        }

        var combinedPower = Array(
            repeating: 0.0,
            count: maximumBin + 1
        )
        let trendWindow = nearestEvenRoundedInt(sampleRateHz * 0.5)
        for signal in signals where signal.count == sampleCount {
            let trend = movingAverage(signal, window: trendWindow)
            var detrended = zip(signal, trend).map(-)
            let detrendedMean = mean(detrended)
            for index in detrended.indices {
                let hann = 0.5 - 0.5 * cos(
                    2 * .pi * Double(index) / Double(sampleCount - 1)
                )
                detrended[index] = (detrended[index] - detrendedMean) * hann
            }

            for bin in minimumBin...maximumBin {
                let angle = -2 * Double.pi * Double(bin) / Double(sampleCount)
                let cosineStep = cos(angle)
                let sineStep = sin(angle)
                var cosine = 1.0
                var sine = 0.0
                var real = 0.0
                var imaginary = 0.0
                for value in detrended {
                    real += value * cosine
                    imaginary += value * sine
                    let nextCosine = cosine * cosineStep - sine * sineStep
                    sine = sine * cosineStep + cosine * sineStep
                    cosine = nextCosine
                }
                combinedPower[bin] += real * real + imaginary * imaginary
            }
        }

        func frequency(_ bin: Int) -> Double {
            Double(bin) * sampleRateHz / Double(sampleCount)
        }
        let analysisBins = (minimumBin...maximumBin).filter {
            let value = frequency($0)
            return value >= 1 && value <= 25
        }
        let tremorBins = analysisBins.filter {
            let value = frequency($0)
            return value >= 3 && value <= 8
        }
        let classicBins = analysisBins.filter {
            let value = frequency($0)
            return value >= 4 && value <= 6
        }
        let totalPower = analysisBins.reduce(0) {
            $0 + combinedPower[$1]
        }
        guard totalPower > 0 else {
            return empty
        }

        let tremorPower = tremorBins.reduce(0) {
            $0 + combinedPower[$1]
        }
        let classicPower = classicBins.reduce(0) {
            $0 + combinedPower[$1]
        }
        let peakBin = tremorBins.max {
            combinedPower[$0] < combinedPower[$1]
        }
        let distribution = analysisBins
            .map { combinedPower[$0] / totalPower }
            .filter { $0 > 0 }
        var entropy = -distribution.reduce(0) {
            $0 + $1 * log($1)
        }
        if distribution.count > 1 {
            entropy /= log(Double(distribution.count))
        }

        return [
            "power_ratio_3_8hz": tremorPower / totalPower,
            "power_ratio_4_6hz": classicPower / totalPower,
            "peak_frequency_3_8hz":
                peakBin.map(frequency) ?? Double.nan,
            "spectral_entropy_1_25hz": entropy,
        ]
    }

    func nearestEvenRoundedInt(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    func finite(_ values: [Double]) -> [Double] {
        values.filter(\.isFinite)
    }

    func mean(_ values: [Double]) -> Double {
        let values = finite(values)
        return values.isEmpty ? .nan : values.reduce(0, +) / Double(values.count)
    }

    func median(_ values: [Double]) -> Double {
        quantile(values, 0.5)
    }

    func quantile(_ values: [Double], _ probability: Double) -> Double {
        let sorted = finite(values).sorted()
        guard !sorted.isEmpty else {
            return .nan
        }
        let position = Double(sorted.count - 1) * probability
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else {
            return sorted[lower]
        }
        let weight = position - Double(lower)
        return sorted[lower] + weight * (sorted[upper] - sorted[lower])
    }

    func iqr(_ values: [Double]) -> Double {
        quantile(values, 0.75) - quantile(values, 0.25)
    }

    func rms(_ values: [Double]) -> Double {
        let values = finite(values)
        guard !values.isEmpty else {
            return .nan
        }
        return sqrt(values.reduce(0) { $0 + $1 * $1 } / Double(values.count))
    }

    func robustCV(_ values: [Double]) -> Double {
        iqr(values) / (abs(median(values)) + 1e-9)
    }

    func ratio(
        _ values: [Double],
        where predicate: (Double) -> Bool
    ) -> Double {
        let values = finite(values)
        guard !values.isEmpty else {
            return .nan
        }
        return Double(values.filter(predicate).count) / Double(values.count)
    }

    func pathLength(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count > 1 else {
            return 0
        }
        return (1..<x.count).reduce(0) {
            $0 + hypot(x[$1] - x[$1 - 1], y[$1] - y[$1 - 1])
        }
    }
}
