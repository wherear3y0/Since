import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Loads only explicitly shared attachments. No requests to shops, or access to the sender's account.
enum ShareInput {
    struct Content {
        var text = ""
        var url: URL?
        var image: UIImage?
    }

    static func read(_ items: [NSExtensionItem]) async -> Content {
        var result = Content()
        var texts = items.flatMap { [$0.attributedTitle?.string, $0.attributedContentText?.string].compactMap { $0 } }
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), result.url == nil {
                if let value = await string(from: provider, type: UTType.url.identifier) {
                    result.url = ParcelShare.webURL(URL(string: value))
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let value = await string(from: provider, type: UTType.plainText.identifier) {
                texts.append(value)
            }
            if result.image == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await data(from: provider, type: UTType.image.identifier) {
                // Downsample before decoding a full-resolution screenshot into extension memory.
                if let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400,
                   ] as CFDictionary) {
                    result.image = UIImage(cgImage: image)
                }
            }
        }
        result.text = texts.joined(separator: "\n")
        return result
    }

    private static func string(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func data(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
