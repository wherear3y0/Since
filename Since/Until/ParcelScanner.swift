import UIKit
import Vision

/// Reads a screenshot of an order on the iPhone itself: its text, for the parcel's details, and the part of it
/// that stands out most, for a picture of what's coming.
enum ParcelScanner {
    struct Result {
        var draft: ParcelDraft
        var photo: Data?
        /// What was found, for telling the person: "dates, tracking number, shop".
        var found: [String]
    }

    static func scan(_ image: UIImage) async -> Result {
        guard let cgImage = image.cgImage else { return Result(draft: ParcelDraft(), photo: nil, found: []) }
        let lines = await textLines(in: cgImage)
        let draft = ParcelParser.parse(lines)
        let photo = await productPhoto(in: cgImage)
        var found: [String] = []
        if draft.from != nil { found.append(draft.to == nil ? "date" : "dates") }
        if draft.trackingNumber != nil { found.append("tracking number") }
        if draft.shop != nil { found.append("shop") }
        if draft.title != nil { found.append("name") }
        if photo != nil { found.append("photo") }
        return Result(draft: draft, photo: photo, found: found)
    }

    /// The recognized lines, top to bottom.
    private static func textLines(in image: CGImage) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ru-RU"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations
            .sorted { $0.boundingBox.cgRect.midY > $1.boundingBox.cgRect.midY }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// The object that stands out most, when it looks like a product shot: not tiny, not the whole screen,
    /// not a long strip.
    private static func productPhoto(in image: CGImage) async -> Data? {
        let request = GenerateObjectnessBasedSaliencyImageRequest()
        guard let result = try? await request.perform(on: image) else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let boxes = result.salientObjects
            .map { $0.boundingBox.toImageCoordinates(size, origin: .upperLeft) }
            .filter { box in
                let share = box.width * box.height / (size.width * size.height)
                let aspect = box.width / max(box.height, 1)
                return (0.02...0.5).contains(share) && (0.5...2).contains(aspect)
            }
        guard let best = boxes.max(by: { $0.width * $0.height < $1.width * $1.height }),
              let cropped = image.cropping(to: best.integral) else { return nil }
        return smallPhoto(UIImage(cgImage: cropped))
    }

    /// A picture made small enough to keep: at most 600 points on its long side.
    static func smallPhoto(_ image: UIImage, side: CGFloat = 600) -> Data? {
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.8)
    }
}
