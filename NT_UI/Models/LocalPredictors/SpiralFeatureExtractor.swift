import Foundation

nonisolated public enum SpiralFeatureError: Error, Equatable {
    case insufficientSamples(testID: Int)
    case nonFiniteFeature(name: String)
}

nonisolated public enum SpiralFeatureExtractor {
    public static let featureNames = [
        "static_duration_s",
        "static_normalized_path_length",
        "static_median_speed",
        "static_speed_iqr",
        "static_speed_cv",
        "static_acceleration_rms",
        "static_median_abs_turn_rate",
        "static_spiral_fit_rmse",
        "static_radial_reversal_fraction",
        "static_relative_pressure_mean",
        "static_relative_pressure_std",
        "static_pressure_speed_correlation",
        "static_relative_angle_std",
        "static_median_relative_angle_change",
        "dynamic_duration_s",
        "dynamic_normalized_path_length",
        "dynamic_median_speed",
        "dynamic_speed_iqr",
        "dynamic_speed_cv",
        "dynamic_acceleration_rms",
        "dynamic_median_abs_turn_rate",
        "dynamic_spiral_fit_rmse",
        "dynamic_radial_reversal_fraction",
        "dynamic_relative_pressure_mean",
        "dynamic_relative_pressure_std",
        "dynamic_pressure_speed_correlation",
        "dynamic_relative_angle_std",
        "dynamic_median_relative_angle_change",
    ]

    private static let interval = 0.02
    private static let minimumGridPoints = 10
    private static let epsilon = 1e-9

    public static func extract(
        from samples: [SpiralHandwritingSample]
    ) throws -> [String: Double] {
        let values = try extractTest(samples, testID: 0)
            + extractTest(samples, testID: 1)

        var result: [String: Double] = [:]
        for (name, value) in zip(featureNames, values) {
            guard value.isFinite else {
                throw SpiralFeatureError.nonFiniteFeature(name: name)
            }
            result[name] = value
        }
        return result
    }

    private static func extractTest(
        _ samples: [SpiralHandwritingSample],
        testID: Int
    ) throws -> [Double] {
        let selected = samples.filter { $0.testID == testID }
        guard selected.count >= 3 else {
            throw SpiralFeatureError.insufficientSamples(testID: testID)
        }

        var monotonic: [SpiralHandwritingSample] = []
        var lastTimestamp = -Double.infinity
        for sample in selected where sample.timestampSeconds > lastTimestamp {
            monotonic.append(sample)
            lastTimestamp = sample.timestampSeconds
        }
        guard monotonic.count >= 3 else {
            throw SpiralFeatureError.insufficientSamples(testID: testID)
        }

        let firstTimestamp = monotonic[0].timestampSeconds
        let timestamps = monotonic.map { $0.timestampSeconds - firstTimestamp }
        let duration = max(timestamps.last ?? 0, 0.001)
        let grid = resamplingGrid(duration: duration)

        let x = interpolate(
            sourceTimes: timestamps,
            sourceValues: monotonic.map(\.x),
            targetTimes: grid
        )
        let y = interpolate(
            sourceTimes: timestamps,
            sourceValues: monotonic.map(\.y),
            targetTimes: grid
        )
        let pressure = interpolate(
            sourceTimes: timestamps,
            sourceValues: monotonic.map(\.pressure),
            targetTimes: grid
        )
        let angle = interpolate(
            sourceTimes: timestamps,
            sourceValues: monotonic.map(\.gripAngle),
            targetTimes: grid
        )

        let smoothX = movingAverageFive(x)
        let smoothY = movingAverageFive(y)
        let dx = differences(smoothX)
        let dy = differences(smoothY)

        let xSpan = (smoothX.max() ?? 0) - (smoothX.min() ?? 0)
        let ySpan = (smoothY.max() ?? 0) - (smoothY.min() ?? 0)
        let coordinateScale = max(hypot(xSpan, ySpan), epsilon)
        let normalizedStep = zip(dx, dy).map {
            hypot($0.0, $0.1) / coordinateScale
        }
        let speed = normalizedStep.map { $0 / interval }
        let acceleration = differences(speed).map { $0 / interval }

        let heading = unwrap(zip(dx, dy).map { atan2($0.1, $0.0) })
        let turnRate = differences(heading).map { $0 / interval }

        let radialX = smoothX.map { $0 - smoothX[0] }
        let radialY = smoothY.map { $0 - smoothY[0] }
        let radius = zip(radialX, radialY).map {
            hypot($0.0, $0.1) / coordinateScale
        }
        let theta = unwrap(zip(radialX, radialY).map { atan2($0.1, $0.0) })
        let fitStart = max(5, grid.count / 10)
        let spiralFitRMSE = linearFitRMSE(
            independent: Array(theta.dropFirst(fitStart)),
            dependent: Array(radius.dropFirst(fitStart))
        )

        let radialReversalFraction = mean(
            differences(radius).map { $0 < -0.001 ? 1.0 : 0.0 }
        )

        let pressureScale = max(percentile(pressure, 95), epsilon)
        let relativePressure = pressure.map {
            min(max($0 / pressureScale, 0), 2)
        }

        let angleScale = max(abs(median(angle)), epsilon)
        let relativeAngle = angle.map { $0 / angleScale }

        let speedMean = mean(speed)
        let speedCV = standardDeviation(speed) / (speedMean + epsilon)
        let pressureSpeedCorrelation = correlation(
            speed,
            Array(relativePressure.dropFirst())
        )

        return [
            duration,
            normalizedStep.reduce(0, +),
            median(speed),
            percentile(speed, 75) - percentile(speed, 25),
            speedCV,
            acceleration.isEmpty
                ? 0
                : sqrt(mean(acceleration.map { $0 * $0 })),
            turnRate.isEmpty ? 0 : median(turnRate.map(abs)),
            spiralFitRMSE,
            radialReversalFraction,
            mean(relativePressure),
            standardDeviation(relativePressure),
            pressureSpeedCorrelation,
            standardDeviation(relativeAngle),
            median(differences(relativeAngle).map(abs)) / interval,
        ]
    }

    private static func resamplingGrid(duration: Double) -> [Double] {
        var grid: [Double] = []
        var current = 0.0
        while current < duration {
            grid.append(current)
            current += interval
        }
        if grid.count >= minimumGridPoints {
            return grid
        }
        return (0..<minimumGridPoints).map {
            duration * Double($0) / Double(minimumGridPoints - 1)
        }
    }

    private static func interpolate(
        sourceTimes: [Double],
        sourceValues: [Double],
        targetTimes: [Double]
    ) -> [Double] {
        var sourceIndex = 0
        return targetTimes.map { target in
            while sourceIndex + 1 < sourceTimes.count
                && sourceTimes[sourceIndex + 1] < target
            {
                sourceIndex += 1
            }
            guard sourceIndex + 1 < sourceTimes.count else {
                return sourceValues.last ?? 0
            }
            let leftTime = sourceTimes[sourceIndex]
            let rightTime = sourceTimes[sourceIndex + 1]
            let fraction = (target - leftTime) / (rightTime - leftTime)
            return sourceValues[sourceIndex]
                + fraction * (sourceValues[sourceIndex + 1] - sourceValues[sourceIndex])
        }
    }

    private static func movingAverageFive(_ values: [Double]) -> [Double] {
        values.indices.map { index in
            var total = 0.0
            for offset in -2...2 {
                let sourceIndex = min(max(index + offset, 0), values.count - 1)
                total += values[sourceIndex]
            }
            return total / 5.0
        }
    }

    private static func differences(_ values: [Double]) -> [Double] {
        guard values.count >= 2 else { return [] }
        return zip(values.dropFirst(), values).map(-)
    }

    private static func unwrap(_ values: [Double]) -> [Double] {
        guard let first = values.first else { return [] }
        var result = [first]
        for index in 1..<values.count {
            var delta = values[index] - values[index - 1]
            if delta > .pi {
                delta -= 2 * .pi
            } else if delta < -.pi {
                delta += 2 * .pi
            }
            result.append(result[index - 1] + delta)
        }
        return result
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        percentile(values, 50)
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = (Double(sorted.count) - 1) * percentile / 100
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper {
            return sorted[lower]
        }
        let fraction = position - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let average = mean(values)
        return sqrt(mean(values.map { ($0 - average) * ($0 - average) }))
    }

    private static func linearFitRMSE(
        independent: [Double],
        dependent: [Double]
    ) -> Double {
        guard independent.count == dependent.count, independent.count >= 2 else {
            return 0
        }
        let independentMean = mean(independent)
        let dependentMean = mean(dependent)
        let centered = independent.map { $0 - independentMean }
        let denominator = centered.map { $0 * $0 }.reduce(0, +)
        let numerator = zip(centered, dependent).map {
            $0.0 * ($0.1 - dependentMean)
        }.reduce(0, +)
        let slope = denominator > epsilon ? numerator / denominator : 0
        let intercept = dependentMean - slope * independentMean
        let squaredResiduals = zip(independent, dependent).map {
            let residual = $0.1 - (intercept + slope * $0.0)
            return residual * residual
        }
        return sqrt(mean(squaredResiduals))
    }

    private static func correlation(_ left: [Double], _ right: [Double]) -> Double {
        guard left.count == right.count, left.count >= 2 else { return 0 }
        let leftMean = mean(left)
        let rightMean = mean(right)
        let leftCentered = left.map { $0 - leftMean }
        let rightCentered = right.map { $0 - rightMean }
        let denominator = sqrt(
            leftCentered.map { $0 * $0 }.reduce(0, +)
                * rightCentered.map { $0 * $0 }.reduce(0, +)
        )
        guard denominator > epsilon else { return 0 }
        return zip(leftCentered, rightCentered).map(*).reduce(0, +) / denominator
    }
}
