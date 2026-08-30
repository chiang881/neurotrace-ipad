import UIKit

/// Observes physical Apple Pencil activity anywhere in the app. UIKit does not
/// expose a general paired/connected flag, so only real Pencil events count as
/// detection.
@MainActor
final class PencilTrackingWindow: UIWindow, UIPencilInteractionDelegate {
    var onPencilDetection: ((PencilMonitor.DetectionSource) -> Void)?

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        installPencilObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installPencilObservers()
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        if event.allTouches?.contains(where: { $0.type == .pencil }) == true {
            onPencilDetection?(.contact)
        }
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        onPencilDetection?(.doubleTap)
    }

    func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        onPencilDetection?(.squeeze)
    }

    private func installPencilObservers() {
        addInteraction(UIPencilInteraction(delegate: self))
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handlePencilHover(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        hover.cancelsTouchesInView = false
        addGestureRecognizer(hover)
    }

    @objc private func handlePencilHover(_ recognizer: UIHoverGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        onPencilDetection?(.hover)
    }
}
