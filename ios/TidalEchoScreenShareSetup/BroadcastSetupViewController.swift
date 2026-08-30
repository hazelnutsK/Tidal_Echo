import Foundation
import ReplayKit
import UIKit
import UniformTypeIdentifiers

final class BroadcastSetupViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        pasteConfiguration = UIPasteConfiguration(
            acceptableTypeIdentifiers: [UTType.utf8PlainText.identifier]
        )

        let titleLabel = UILabel()
        titleLabel.text = "给 Altair 看一眼"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center

        let detailLabel = UILabel()
        detailLabel.text = "回到 Tidal Echo 准备临时票据后，在这里亲手粘贴。共享只会送出一张压缩画面。"
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center

        let controlConfiguration = UIPasteControl.Configuration()
        controlConfiguration.cornerStyle = .capsule
        controlConfiguration.displayMode = .labelOnly
        let pasteControl = UIPasteControl(configuration: controlConfiguration)
        pasteControl.target = self

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.title = "取消"
        let cancelButton = UIButton(configuration: cancelConfig)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, detailLabel, pasteControl, statusLabel, cancelButton
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        pasteControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pasteControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            pasteControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
        }) else {
            showError("剪贴板里没有 Tidal Echo 的临时票据。")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier) { [weak self] item, error in
            let text: String?
            if let value = item as? String {
                text = value
            } else if let value = item as? NSString {
                text = value as String
            } else if let data = item as? Data {
                text = String(data: data, encoding: .utf8)
            } else {
                text = nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.showError(error.localizedDescription)
                } else {
                    self.finish(with: text)
                }
            }
        }
    }

    private func finish(with text: String?) {
        guard let text,
              let data = text.data(using: .utf8),
              let handoff = try? JSONDecoder().decode(ScreenShareHandoff.self, from: data),
              handoff.version == 1,
              !handoff.ticket.isEmpty,
              let relayURL = URL(string: handoff.relayURL),
              relayURL.scheme?.lowercased() == "https" else {
            showError("这不是有效的 Tidal Echo 临时票据，请回到 App 重新准备。")
            return
        }

        let uploadURL = ["app", "screen-share", "frame"].reduce(relayURL) {
            $0.appendingPathComponent($1)
        }
        extensionContext?.completeRequest(
            withBroadcast: uploadURL,
            setupInfo: [
                "relayURL": handoff.relayURL as NSString,
                "ticket": handoff.ticket as NSString,
                "expiresAt": handoff.expiresAt as NSString
            ]
        )
    }

    private func showError(_ text: String) {
        statusLabel.text = text
        statusLabel.textColor = .systemRed
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "TidalEcho.ScreenShare",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "你取消了这次屏幕共享。"]
        ))
    }
}

private struct ScreenShareHandoff: Decodable {
    let version: Int
    let relayURL: String
    let ticket: String
    let expiresAt: String
}
