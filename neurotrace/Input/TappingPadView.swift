import UIKit

@MainActor
final class TappingCaptureUIView: UIView {
    var taskID = UUID()
    var isRecording = false
    var resetToken = UUID()
    var onTap: ((TapEvent) -> Void)?

    private var expectedTarget: TapTarget = .left
    private var sequenceIndex = 0
    private var highlightedTarget: TapTarget?
    private var highlightIsCorrect = true
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        feedback.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        expectedTarget = .left
        sequenceIndex = 0
        highlightedTarget = nil
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRecording else { return }
        for touch in touches where accepts(touch) {
            let point = touch.location(in: self)
            let target = target(at: point)
            let correct = target == expectedTarget
            sequenceIndex += 1
            let tap = TapEvent(
                taskID: taskID,
                timestamp: touch.timestamp,
                sequenceIndex: sequenceIndex,
                point: point,
                canvasSize: bounds.size,
                target: target,
                expectedTarget: expectedTarget,
                isCorrect: correct,
                inputDevice: touch.type == .direct ? .finger : .simulator
            )
            onTap?(tap)

            highlightedTarget = target
            highlightIsCorrect = correct
            if correct {
                expectedTarget = expectedTarget == .left ? .right : .left
                feedback.impactOccurred(intensity: 0.45)
            }
            setNeedsDisplay()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                self?.highlightedTarget = nil
                self?.setNeedsDisplay()
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for target in [TapTarget.left, .right] {
            let circle = targetRect(target)
            let isHighlighted = highlightedTarget == target
            let color: UIColor
            if isHighlighted {
                color = highlightIsCorrect ? .systemMint : .systemRed
            } else if target == expectedTarget && isRecording {
                color = UIColor.systemCyan.withAlphaComponent(0.92)
            } else {
                color = .tertiaryLabel
            }
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: circle)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(4)
            context.strokeEllipse(in: circle)
        }
    }

    private func target(at point: CGPoint) -> TapTarget {
        if targetRect(.left).insetBy(dx: -24, dy: -24).contains(point) { return .left }
        if targetRect(.right).insetBy(dx: -24, dy: -24).contains(point) { return .right }
        return .outside
    }

    private func targetRect(_ target: TapTarget) -> CGRect {
        let diameter = min(120, max(92, bounds.height * 0.28))
        let x = target == .left ? bounds.width * 0.28 : bounds.width * 0.72
        return CGRect(
            x: x - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    private func accepts(_ touch: UITouch) -> Bool {
        if touch.type == .direct { return true }
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
