import ParchmentUIKit
import UIKit

@MainActor
enum UIKitFactory {
    static func glassButton(
        title: String,
        symbol: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = prominent
            ? UIButton.Configuration.prominentGlass()
            : UIButton.Configuration.glass()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(
            greaterThanOrEqualToConstant: ParchmentUIKitModule.minimumHitTarget
        ).isActive = true
        return button
    }

    static func contentConfiguration(
        title: String,
        subtitle: String? = nil,
        image: String? = nil,
        tint: UIColor = .systemTeal
    ) -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = title
        configuration.secondaryText = subtitle
        configuration.textProperties.font = .preferredFont(forTextStyle: .body)
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        configuration.textProperties.adjustsFontForContentSizeCategory = true
        configuration.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        if let image {
            configuration.image = UIImage(systemName: image)
            configuration.imageProperties.tintColor = tint
            configuration.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        }
        return configuration
    }

    static func emptyConfiguration(
        title: String,
        message: String,
        symbol: String,
        buttonTitle: String? = nil,
        action: UIAction? = nil
    ) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: symbol)
        configuration.text = title
        configuration.secondaryText = message
        if let buttonTitle {
            configuration.button = .prominentGlass()
            configuration.button.title = buttonTitle
            configuration.buttonProperties.primaryAction = action
        }
        return configuration
    }
}

@MainActor
extension UIViewController {
    func presentError(_ error: Error, title: String = "操作失败") {
        let alert = UIAlertController(
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    func presentShareSheet(url: URL, source: UIBarButtonItem? = nil) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.barButtonItem = source
        if source == nil {
            controller.popoverPresentationController?.sourceView = view
            controller.popoverPresentationController?.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        present(controller, animated: true)
    }

    func presentTextPrompt(
        title: String,
        message: String? = nil,
        value: String,
        placeholder: String? = nil,
        secure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        completion: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = value
            field.placeholder = placeholder
            field.isSecureTextEntry = secure
            field.keyboardType = keyboardType
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak alert] _ in
            completion(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
}

nonisolated extension TimeInterval {
    var parchmentFormattedDuration: String {
        let total = max(0, Int(self))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
