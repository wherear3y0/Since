import Messages
import SwiftUI
import UIKit

enum MessageFormat: String, CaseIterable { case interactive = "Card", image = "Picture" }

final class MessagesViewController: MSMessagesAppViewController {
    private var host: UIHostingController<AnyView>?
    private var attachments: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Always mount a screen during UIKit loading, including before a conversation is available.
        showLibrary()
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        loadViewIfNeeded()
        showSelected(in: conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        show(message)
    }

    private func showSelected(in conversation: MSConversation) {
        if let message = conversation.selectedMessage { show(message) }
        else { showLibrary() }
    }

    private func show(_ message: MSMessage) {
        guard let url = message.url, let card = try? SharedMessageCard.decode(url) else {
            showLibrary()
            return
        }
        requestPresentationStyle(.expanded)
        mount(AnyView(ReceivedMessageView(card: card, image: (message.layout as? MSMessageTemplateLayout)?.image) { [weak self] in
            self?.showLibrary()
        }))
    }

    private func showLibrary() {
        mount(AnyView(StoreAccessView { [weak self] container in
            MessagesView(container: container, insert: { [weak self] image, card, format in
                guard let self else { throw MessageCardError.noConversation }
                try await self.insert(image, card: card, format: format)
            }, expand: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            }, collapse: { [weak self] in
                self?.requestPresentationStyle(.compact)
            })
        }))
    }

    private func mount(_ content: AnyView) {
        if let host {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        let host = UIHostingController(rootView: content)
        self.host = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func insert(_ image: UIImage, card: SharedMessageCard, format: MessageFormat) async throws {
        guard let conversation = activeConversation else { throw MessageCardError.noConversation }
        if format == .interactive {
            let message = MSMessage(session: MSSession())
            let layout = MSMessageTemplateLayout()
            layout.image = image
            layout.caption = card.title
            layout.subcaption = card.locationLine ?? card.dateLine
            layout.trailingCaption = "Tap to open"
            message.layout = layout
            message.url = try card.encodedURL()
            message.summaryText = "\(card.title) · \(card.dateLine)"
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conversation.insert(message) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        } else {
            guard let data = image.pngData() else { throw MessageCardError.renderFailed }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("since-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            attachments.append(url)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conversation.insertAttachment(url, withAlternateFilename: "Since.png") { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }
}

enum MessageCardError: LocalizedError {
    case noConversation, renderFailed
    var errorDescription: String? {
        switch self {
        case .noConversation: "Open Since inside a conversation to add a card."
        case .renderFailed: "Couldn’t make the card image. Try again."
        }
    }
}
