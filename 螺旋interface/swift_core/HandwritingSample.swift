import Foundation

public struct HandwritingSample: Sendable {
    public let x: Double
    public let y: Double
    public let pressure: Double
    public let gripAngle: Double
    public let timestampSeconds: Double
    public let testID: Int

    public init(
        x: Double,
        y: Double,
        pressure: Double,
        gripAngle: Double,
        timestampSeconds: Double,
        testID: Int
    ) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.gripAngle = gripAngle
        self.timestampSeconds = timestampSeconds
        self.testID = testID
    }
}

