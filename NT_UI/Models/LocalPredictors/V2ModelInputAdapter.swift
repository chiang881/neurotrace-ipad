import Foundation

nonisolated enum V2ModelInputAdapter {
    static func spiralSample(
        from sample: PencilSample,
        testID: Int
    ) -> SpiralHandwritingSample {
        SpiralHandwritingSample(
            x: sample.x,
            y: sample.y,
            pressure: min(max(sample.normalizedForce, 0), 1),
            gripAngle: sample.altitudeAngle,
            timestampSeconds: sample.timestamp,
            testID: testID
        )
    }

    static func pressureSample(
        from sample: PencilSample,
        testID: Int
    ) -> PressureDrawingSample {
        let pressure1023 = min(max(sample.normalizedForce, 0), 1) * 1_023
        let altitude = min(max(sample.altitudeAngle, 0), .pi)
        return PressureDrawingSample(
            x: min(max(sample.normalizedX, 0), 1) * 1_000,
            y: min(max(sample.normalizedY, 0), 1) * 570,
            z: pressure1023 * sin(altitude),
            pressure: pressure1023,
            gripAngleTenthsDegree: altitude * 180 / .pi * 10,
            timestampMilliseconds: sample.timestamp * 1_000,
            testID: testID
        )
    }
}
