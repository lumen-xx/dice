import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

public enum DiceError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
public enum OutputFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case original = "Same as original", jpeg = "JPEG", png = "PNG", heic = "HEIC", webp = "WebP", gif = "GIF", bmp = "BMP", tiff = "TIFF", avif = "AVIF", ico = "ICO", icns = "ICNS", pdf = "PDF"
    public var id: String { rawValue }
    public var ext: String { switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic: return "heic"; case .webp: return "webp"; case .gif: return "gif"; case .bmp: return "bmp"; case .tiff: return "tiff"; case .avif: return "avif"; case .ico: return "ico"; case .icns: return "icns"; case .pdf: return "pdf"; case .original: return "" } }
    public var type: String { switch self { case .jpeg: return UTType.jpeg.identifier; case .png: return UTType.png.identifier; case .heic: return UTType.heic.identifier; case .webp: return "org.webmproject.webp"; case .gif: return UTType.gif.identifier; case .bmp: return UTType.bmp.identifier; case .tiff: return UTType.tiff.identifier; case .avif: return "public.avif"; case .ico: return UTType.ico.identifier; case .icns: return UTType.icns.identifier; case .pdf: return UTType.pdf.identifier; case .original: return "" } }
    /// PDF pages embed opaque images as JPEG at this quality.
    public var usesQuality: Bool { [.original, .jpeg, .heic, .webp, .avif, .pdf].contains(self) }
    /// Formats ExifTool can copy image metadata into. BMP and icons have no room for it; PDF has its own document metadata.
    public var holdsMetadata: Bool { ![.bmp, .ico, .icns, .pdf, .original].contains(self) }
    /// Formats Dice writes as animations when the input is animated.
    public var animates: Bool { [.gif, .png, .webp, .heic].contains(self) }
    /// Multi-size icon files.
    public var isIcon: Bool { self == .ico || self == .icns }
    /// Icon sizes written, largest first. ICO stops at 256; ICNS goes to 1024 (512 @2x).
    /// ImageIO writes at most six images into one ICO, so 64 px (the least used) is left out; ICNS has no 64 px slot.
    public var iconSizes: [Int] { self == .ico ? [256, 128, 48, 32, 24, 16] : self == .icns ? [1024, 512, 256, 128, 32, 16] : [] }
    /// What "Same as original" writes for an input type. `exact` is false when Dice cannot write that type:
    /// HEIF variants become HEIC, camera and other photographic formats JPEG, everything else PNG.
    public static func matching(inputType: String) -> (format: OutputFormat, exact: Bool) {
        // Documents (PDF, SVG) rasterise to PNG; re-rendering a PDF into a PDF would only lose its vectors.
        if let same = allCases.first(where: { $0 != .original && $0 != .pdf && $0.type == inputType }) { return (same, true) }
        let type = UTType(inputType)
        if ["public.heif", "public.heics", "public.avci"].contains(inputType) { return (.heic, false) }
        if inputType == "public.avis" { return (.avif, false) }
        if type?.conforms(to: .rawImage) == true || ["public.jpeg-2000", "public.jpeg-xl", "public.mpo-image"].contains(inputType) { return (.jpeg, false) }
        return (.png, false)
    }
    /// Whether a target file size can be met by lowering quality.
    public func fitsTargetSize(lossless: Bool) -> Bool { usesQuality && self != .original && !(self == .webp && lossless) }
    /// Whether the quality setting changes the output for this input type.
    public func usesQuality(forInputType inputType: String) -> Bool {
        self == .original ? OutputFormat.matching(inputType: inputType).format.usesQuality : usesQuality
    }
}
public enum ResizeMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case original = "Original size", edge = "Longest edge", percent = "Percentage", fit = "Fit within dimensions"
    public var id: String { rawValue }
}
public struct Options: Sendable, Codable {
    public var format: OutputFormat = .original
    public var resize: ResizeMode = .original
    public var edge = 1920
    public var percent = 50
    public var width = 1920
    public var height = 1080
    public var quality = 0.82
    public var stripMetadata = true
    public var metadataOnly = false
    public var webpLossless = false
    /// Resolution-only run: keep format and metadata, skip images already within the target.
    public var resizeOnly = false
    /// Replace each original with its processed image (the original goes to the Trash).
    public var replaceOriginals = false
    /// RGB (0...1) used in place of transparency when the output format has no alpha channel.
    public var flattenColor: [Double] = [1, 1, 1]
    /// Keep animated images animated when the output is GIF, PNG (APNG), WebP or HEIC (an image sequence).
    public var keepAnimation = true
    /// Animated images exported to a still format become a folder of frames; otherwise only the first frame is exported.
    public var framesAsFolder = true
    /// Appended to the original name for saved copies.
    public var fileSuffix = "-dice"
    /// Lossy formats: search for the highest quality that fits `targetKB` (1 KB = 1000 bytes) instead of using `quality`.
    public var useTargetSize = false
    public var targetKB = 500
    /// Losslessly recompress PNG output with oxipng.
    public var optimizePNG = true
    /// When re-encoding in the same format at the same size makes the file larger, keep the original's pixels.
    public var keepSmallerOriginal = true
    /// PDF output: one combined PDF for the batch instead of one per image.
    public var combinePDF = false
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(OutputFormat.self, forKey: .format) ?? format
        resize = try c.decodeIfPresent(ResizeMode.self, forKey: .resize) ?? resize
        edge = try c.decodeIfPresent(Int.self, forKey: .edge) ?? edge
        percent = try c.decodeIfPresent(Int.self, forKey: .percent) ?? percent
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? height
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? quality
        stripMetadata = try c.decodeIfPresent(Bool.self, forKey: .stripMetadata) ?? stripMetadata
        metadataOnly = try c.decodeIfPresent(Bool.self, forKey: .metadataOnly) ?? metadataOnly
        webpLossless = try c.decodeIfPresent(Bool.self, forKey: .webpLossless) ?? webpLossless
        resizeOnly = try c.decodeIfPresent(Bool.self, forKey: .resizeOnly) ?? resizeOnly
        replaceOriginals = try c.decodeIfPresent(Bool.self, forKey: .replaceOriginals) ?? replaceOriginals
        flattenColor = try c.decodeIfPresent([Double].self, forKey: .flattenColor) ?? flattenColor
        keepAnimation = try c.decodeIfPresent(Bool.self, forKey: .keepAnimation) ?? keepAnimation
        framesAsFolder = try c.decodeIfPresent(Bool.self, forKey: .framesAsFolder) ?? framesAsFolder
        fileSuffix = try c.decodeIfPresent(String.self, forKey: .fileSuffix) ?? fileSuffix
        useTargetSize = try c.decodeIfPresent(Bool.self, forKey: .useTargetSize) ?? useTargetSize
        targetKB = try c.decodeIfPresent(Int.self, forKey: .targetKB) ?? targetKB
        optimizePNG = try c.decodeIfPresent(Bool.self, forKey: .optimizePNG) ?? optimizePNG
        keepSmallerOriginal = try c.decodeIfPresent(Bool.self, forKey: .keepSmallerOriginal) ?? keepSmallerOriginal
        combinePDF = try c.decodeIfPresent(Bool.self, forKey: .combinePDF) ?? combinePDF
    }
    /// Choices that only make sense for the images they were made for; a new session starts without them.
    public mutating func resetSessionChoices() { metadataOnly = false; resizeOnly = false; webpLossless = false }
    /// Target longest edge. Raster images never grow; vector documents (`upscale`) render at any requested size.
    public func longestEdge(width w: Int, height h: Int, upscale: Bool = false) throws -> Int {
        let longest = max(w,h)
        switch resize {
        case .original: return longest
        case .edge: guard edge > 0 else { throw DiceError.message("Enter a longest edge greater than zero.") }; return upscale ? edge : min(longest, edge)
        case .percent: guard percent > 0 && percent <= 100 else { throw DiceError.message("Percentage must be between 1 and 100.") }; return max(1, Int(Double(longest) * Double(percent) / 100))
        case .fit:
            guard width > 0 && height > 0 else { throw DiceError.message("Width and height must be greater than zero.") }
            let factor = min(Double(width)/Double(w), Double(height)/Double(h))
            return max(1, Int(Double(longest) * (upscale ? factor : min(1, factor))))
        }
    }
}
public struct MetadataRow: Identifiable, Sendable, Codable {
    public var id: String { group + ":" + name }
    public let group: String
    public let name: String
    public let value: String
}
public struct ImageInfo: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: Int64
    public let type: String
    public let frames: Int
    public let rows: [MetadataRow]
    public func value(_ suffix: String) -> String? { rows.first { $0.name == suffix }?.value }
    public var camera: String? { [value("Make"), value("Model")].compactMap { $0 }.joined(separator: " ").nilIfEmpty }
    public var hasGPS: Bool { rows.contains { $0.name.hasPrefix("GPS") } }
}
extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
public struct ConversionResult: Sendable {
    public let url: URL
    public let bytes: Int64
    public let note: String?
    /// For folder results: a file inside the folder to show as the preview.
    public var previewURL: URL? = nil
    public var isFolder: Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    public init(url: URL, bytes: Int64, note: String?, previewURL: URL? = nil) { self.url = url; self.bytes = bytes; self.note = note; self.previewURL = previewURL }
}
