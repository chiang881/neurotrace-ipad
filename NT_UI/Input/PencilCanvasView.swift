import UIKit

@MainActor
final class PencilCaptureUIView: UIView, UIPencilInteractionDelegate {
    var taskID = UUID()
    var isRecording = false
    var resetToken = UUID()
    var onSamples: (([PencilSample]) -> Void)?
    var onSampleUpdates: (([PencilSample]) -> Void)?
    var onPencilDetection: ((PencilMonitor.DetectionSource) -> Void)?

    private var nextStrokeID = 0
    private var activeStrokes: [UITouch: Int] = [:]
    private var renderedStrokes: [Int: [PencilSample]] = [:]
    private var renderedSampleLocations: [UUID: (strokeID: Int, index: Int)] = [:]
    private var estimatedSamples: [NSNumber: PencilSample] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        addInteraction(UIPencilInteraction(delegate: self))
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handlePencilHover(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        hover.cancelsTouchesInView = false
        addGestureRecognizer(hover)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        nextStrokeID = 0
        activeStrokes.removeAll()
        renderedStrokes.removeAll()
        renderedSampleLocations.removeAll()
        estimatedSamples.removeAll()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRecording else { return }
        for touch in touches where accepts(touch) {
            nextStrokeID += 1
            activeStrokes[touch] = nextStrokeID
            capture(touch: touch, event: event, fallbackPhase: .began)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRecording else { return }
        for touch in touches where accepts(touch) {
            capture(touch: touch, event: event, fallbackPhase: .moved)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRecording else { return }
        for touch in touches where accepts(touch) {
            capture(touch: touch, event: event, fallbackPhase: .ended)
            activeStrokes.removeValue(forKey: touch)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRecording else { return }
        for touch in touches where accepts(touch) {
            capture(touch: touch, event: event, fallbackPhase: .cancelled)
            activeStrokes.removeValue(forKey: touch)
        }
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        var updates: [PencilSample] = []
        for touch in touches {
            guard
                let index = touch.estimationUpdateIndex,
                var sample = estimatedSamples[index]
            else { continue }

            sample.force = touch.force
            sample.maximumPossibleForce = touch.maximumPossibleForce
            sample.normalizedForce = touch.maximumPossibleForce > 0
                ? touch.force / touch.maximumPossibleForce
                : 0
            sample.altitudeAngle = touch.altitudeAngle
            sample.azimuthAngle = touch.azimuthAngle(in: self)
            sample.rollAngle = touch.rollAngle
            sample.estimatedPropertiesRawValue = touch.estimatedProperties.rawValue

            if touch.estimatedPropertiesExpectingUpdates.isEmpty {
                estimatedSamples.removeValue(forKey: index)
            } else {
                estimatedSamples[index] = sample
            }

            if
                let location = renderedSampleLocations[sample.id],
                var stroke = renderedStrokes[location.strokeID],
                stroke.indices.contains(location.index)
            {
                stroke[location.index] = sample
                renderedStrokes[location.strokeID] = stroke
            }
            updates.append(sample)
        }
        if !updates.isEmpty {
            onSampleUpdates?(updates)
            setNeedsDisplay()
        }
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        onPencilDetection?(.doubleTap)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        onPencilDetection?(.squeeze)
    }

    @objc private func handlePencilHover(_ recognizer: UIHoverGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        onPencilDetection?(.hover)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.label.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for strokeID in renderedStrokes.keys.sorted() {
            guard
                let samples = renderedStrokes[strokeID],
                let first = samples.first
            else { continue }
            context.beginPath()
            context.move(to: CGPoint(x: first.x, y: first.y))
            for sample in samples.dropFirst() {
                context.setLineWidth(max(1.5, 2 + sample.normalizedForce * 3))
                context.addLine(to: CGPoint(x: sample.x, y: sample.y))
            }
            context.strokePath()
        }
    }

    private func capture(touch: UITouch, event: UIEvent?, fallbackPhase: SamplePhase) {
        onPencilDetection?(.contact)
        let touches = event?.coalescedTouches(for: touch) ?? [touch]
        let strokeID = activeStrokes[touch] ?? max(1, nextStrokeID)
        var captured: [PencilSample] = []
        captured.reserveCapacity(touches.count)

        for (index, coalescedTouch) in touches.enumerated() {
            let sample = makeSample(
                touch: coalescedTouch,
                strokeID: strokeID,
                phase: index == touches.count - 1 ? fallbackPhase : .moved,
                coalesced: index != touches.count - 1
            )
            if
                let estimateIndex = coalescedTouch.estimationUpdateIndex,
                !coalescedTouch.estimatedPropertiesExpectingUpdates.isEmpty
            {
                estimatedSamples[estimateIndex] = sample
            }
            captured.append(sample)
        }

        appendRendered(captured, strokeID: strokeID)
        onSamples?(captured)
        setNeedsDisplay()
    }

    private func appendRendered(_ samples: [PencilSample], strokeID: Int) {
        var stroke = renderedStrokes[strokeID] ?? []
        stroke.reserveCapacity(stroke.count + samples.count)
        for sample in samples {
            renderedSampleLocations[sample.id] = (strokeID, stroke.count)
            stroke.append(sample)
        }
        renderedStrokes[strokeID] = stroke
    }

    private func makeSample(
        touch: UITouch,
        strokeID: Int,
        phase: SamplePhase,
        coalesced: Bool
    ) -> PencilSample {
        PencilSample(
            taskID: taskID,
            timestamp: touch.timestamp,
            point: touch.preciseLocation(in: self),
            canvasSize: bounds.size,
            strokeID: strokeID,
            phase: phase,
            force: touch.force,
            maximumPossibleForce: touch.maximumPossibleForce,
            altitudeAngle: touch.altitudeAngle,
            azimuthAngle: touch.azimuthAngle(in: self),
            rollAngle: touch.rollAngle,
            majorRadius: touch.majorRadius,
            inputDevice: touch.type == .pencil ? .pencil : .simulator,
            wasCoalesced: coalesced,
            estimatedPropertiesRawValue: touch.estimatedProperties.rawValue,
            estimationUpdateIndex: touch.estimationUpdateIndex?.intValue
        )
    }

    private func accepts(_ touch: UITouch) -> Bool {
        if touch.type == .pencil { return true }
        #if targetEnvironment(simulator)
        return touch.type == .direct
        #else
        return false
        #endif
    }
}
