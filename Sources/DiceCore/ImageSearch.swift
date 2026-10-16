import Foundation
import CoreGraphics
import Vision

/// Search is entirely local. Whitespace-separated words may match different fields.
public enum ImageSearch {
    /// Text in an image, for search. Can take tens of seconds the first time Vision loads its model after an
    /// install or update, so callers run it after the image is already usable.
    public static func recognizedText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return "" }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    public static func text(filename: String, path: String, info: ImageInfo?, recognizedText: String = "", extraInfo: ImageInfo? = nil, error: String? = nil) -> String {
        var fields = [filename, path, recognizedText, error ?? ""]
        for info in [info, extraInfo].compactMap({ $0 }) {
            fields += [info.type, "\(info.width)x\(info.height)", "\(info.width) × \(info.height)", "width \(info.width) height \(info.height)", "\(info.bytes) bytes", ByteCountFormatter.string(fromByteCount: info.bytes, countStyle: .file), "\(info.frames) frames", "camera " + (info.camera ?? ""), info.hasGPS ? "GPS location" : ""]
            fields += info.rows.flatMap { row in
                [row.group, row.name, row.name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression), row.value]
            }
        }
        return normalized(fields.joined(separator: "\n"))
    }
    public static func matches(_ query: String, text: String) -> Bool {
        let tokens = normalized(query).split(whereSeparator: { $0.isWhitespace })
        return tokens.allSatisfy { text.contains($0) }
    }
    static func normalized(_ string: String) -> String { string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "×", with: "x") }
}
