import UIKit
import ParkinsonSpiralCore

/// Minimal Apple Pencil collector. Render the static/dynamic spiral target in
/// the containing view controller and set `testID` to 0 or 1 before collection.
final class SpiralCanvasView: UIView {
    var testID = 0
    private(set) var samples: [HandwritingSample] = []

    func reset(testID: Int) {
        self.testID = testID
        samples.removeAll(keepingCapacity: true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        append(touches: touches, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        append(touches: touches, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        append(touches: touches, event: event)
    }

    private func append(touches: Set<UITouch>, event: UIEvent?) {
        for touch in touches where touch.type == .pencil {
            let resolvedTouches = event?.coalescedTouches(for: touch) ?? [touch]
            for resolvedTouch in resolvedTouches {
                let location = resolvedTouch.location(in: self)
                let maximumForce = max(resolvedTouch.maximumPossibleForce, 0.000_001)
                samples.append(
                    HandwritingSample(
                        x: Double(location.x),
                        y: Double(location.y),
                        pressure: Double(resolvedTouch.force / maximumForce),
                        gripAngle: Double(resolvedTouch.altitudeAngle),
                        timestampSeconds: resolvedTouch.timestamp,
                        testID: testID
                    )
                )
            }
        }
    }
}
