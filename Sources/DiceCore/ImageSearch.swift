import Foundation

/// Search is entirely local. Whitespace-separated words may match different fields.
public enum ImageSearch {
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
