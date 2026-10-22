import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Text extraction seam. Implementations must not be called from the clipboard
/// capture path; OCR runs only for explicit user requests.
protocol OCREngine: Sendable {
    func recognizeText(inImageAt url: URL) async throws -> String
}

enum OCREngineError: LocalizedError, Equatable {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The image could not be read."
        }
    }
}

struct VisionOCREngine: OCREngine {
    let minimumConfidence: Float
    let languages: [String]

    init(minimumConfidence: Float = 0.3, languages: [String] = []) {
        self.minimumConfidence = minimumConfidence
        self.languages = languages
    }

    func recognizeText(inImageAt url: URL) async throws -> String {
        let minimumConfidence = self.minimumConfidence
        let languages = self.languages
        return try await Task.detached(priority: .userInitiated) {
            try Self.recognize(
                inImageAt: url,
                minimumConfidence: minimumConfidence,
                languages: languages
            )
        }.value
    }

    static func recognize(
        inImageAt url: URL,
        minimumConfidence: Float,
        languages: [String]
    ) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OCREngineError.unreadableImage
        }

        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let lines = (request.results ?? []).compactMap { observation -> String? in
            guard observation.confidence >= minimumConfidence,
                  let candidate = observation.topCandidates(1).first
            else { return nil }
            return candidate.string
        }
        return normalize(lines)
    }

    static func normalize(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
