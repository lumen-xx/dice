import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

public enum DiceError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
public enum OutputFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case original = "Same as original", jpeg = "JPEG", png = "PNG", heic = "HEIC", webp = "WebP", gif = "GIF", bmp = "BMP", tiff = "TIFF", avif = "AVIF", jxl = "JPEG XL", ico = "ICO", icns = "ICNS", pdf = "PDF"
    public var id: String { rawValue }
    public var ext: String { switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic: return "heic"; case .webp: return "webp"; case .gif: return "gif"; case .bmp: return "bmp"; case .tiff: return "tiff"; case .avif: return "avif"; case .jxl: return "jxl"; case .ico: return "ico"; case .icns: return "icns"; case .pdf: return "pdf"; case .original: return "" } }
    public var type: String { switch self { case .jpeg: return UTType.jpeg.identifier; case .png: return UTType.png.identifier; case .heic: return UTType.heic.identifier; case .webp: return "org.webmproject.webp"; case .gif: return UTType.gif.identifier; case .bmp: return UTType.bmp.identifier; case .tiff: return UTType.tiff.identifier; case .avif: return "public.avif"; case .jxl: return "public.jpeg-xl"; case .ico: return UTType.ico.identifier; case .icns: return UTType.icns.identifier; case .pdf: return UTType.pdf.identifier; case .original: return "" } }
    /// PDF pages embed opaque images as JPEG at this quality.
    public var usesQuality: Bool { [.original, .jpeg, .heic, .webp, .avif, .jxl, .pdf].contains(self) }
    /// Formats with a lossless mode behind the Lossless switch (`webpLossless`, named before JPEG XL arrived).
    public var hasLosslessMode: Bool { self == .webp || self == .jxl }
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
        if type?.conforms(to: .rawImage) == true || ["public.jpeg-2000", "public.mpo-image"].contains(inputType) { return (.jpeg, false) }
        return (.png, false)
    }
    /// Whether a target file size can be met by lowering quality.
    public func fitsTargetSize(lossless: Bool) -> Bool { usesQuality && self != .original && !(hasLosslessMode && lossless) }
    /// Whether the quality setting changes the output for this input type.
    public func usesQuality(forInputType inputType: String) -> Bool {
        self == .original ? OutputFormat.matching(inputType: inputType).format.usesQuality : usesQuality
    }
}
public enum ResizeMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case original = "Original size", edge = "Longest edge", percent = "Percentage", fit = "Fit within dimensions", width = "Width", height = "Height", fill = "Fill and crop"
    public var id: String { rawValue }
}
/// Centred crop to an aspect ratio, applied after rotation and before resizing.
public enum CropAspect: String, CaseIterable, Identifiable, Sendable, Codable {
    case none = "No crop", square = "1:1", portrait = "4:5", standard = "4:3", photo = "3:2", wide = "16:9", story = "9:16"
    public var id: String { rawValue }
    /// Width divided by height.
    public var ratio: Double? {
        switch self { case .none: nil; case .square: 1; case .portrait: 0.8; case .standard: 4.0 / 3; case .photo: 1.5; case .wide: 16.0 / 9; case .story: 9.0 / 16 }
    }
}
/// How one image is reshaped: decode (or render) the source at `decodeEdge`, rotate and flip, centre-crop to `crop`,
/// then resample to exactly `width` × `height`.
public struct Geometry: Equatable, Sendable {
    public let decodeEdge: Int
    public let width: Int
    public let height: Int
    public let crop: Double?
    public let reorients: Bool
    /// True when the output is the source unchanged in size and orientation.
    public func isIdentity(width w: Int, height h: Int) -> Bool { !reorients && crop == nil && width == w && height == h }
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
    /// Output file name: `{name}` is the original's name, `{n}` the image's number in the batch, `{date}` today.
    public var namePattern = "{name}-dice"
    /// This image's position in the batch and the batch size, for `{n}`. Set per image, not saved.
    public var sequence = 1
    public var sequenceCount = 1
    /// Lossy formats: search for the highest quality that fits `targetKB` (1 KB = 1000 bytes) instead of using `quality`.
    public var useTargetSize = false
    public var targetKB = 500
    /// Losslessly recompress PNG output with oxipng.
    public var optimizePNG = true
    /// When re-encoding in the same format at the same size makes the file larger, keep the original's pixels.
    public var keepSmallerOriginal = true
    /// PDF output: one combined PDF for the batch instead of one per image.
    public var combinePDF = false
    /// Raster images may be scaled above their own size (vectors always render at the requested size).
    public var upscale = false
    /// Clockwise rotation in degrees: 0, 90, 180 or 270. Applied before flipping and cropping.
    public var rotation = 0
    public var flipHorizontal = false
    public var flipVertical = false
    public var crop: CropAspect = .none
    /// Treat the output as @3x and also save @2x and @1x, in a folder.
    public var scaleSet = false
    /// PDF pages render at this resolution for "Original size" (and as the base for percentages).
    public var pdfDPI = 144
    /// HDR photos stay HDR (with a gain map) when saved as HEIC, JPEG or AVIF; otherwise they are tone-mapped to SDR.
    public var keepHDR = true
    /// Convert colours to sRGB (SDR, 8 bits per channel), for the web and apps that ignore colour profiles.
    public var convertToSRGB = false
    /// With `stripMetadata`: remove only location (GPS coordinates and place names) and keep the rest.
    public var removeLocationOnly = false
    /// Keep the subjects Vision finds and make the background transparent.
    public var removeBackground = false
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
        namePattern = try c.decodeIfPresent(String.self, forKey: .namePattern) ?? namePattern
        useTargetSize = try c.decodeIfPresent(Bool.self, forKey: .useTargetSize) ?? useTargetSize
        targetKB = try c.decodeIfPresent(Int.self, forKey: .targetKB) ?? targetKB
        optimizePNG = try c.decodeIfPresent(Bool.self, forKey: .optimizePNG) ?? optimizePNG
        keepSmallerOriginal = try c.decodeIfPresent(Bool.self, forKey: .keepSmallerOriginal) ?? keepSmallerOriginal
        combinePDF = try c.decodeIfPresent(Bool.self, forKey: .combinePDF) ?? combinePDF
        upscale = try c.decodeIfPresent(Bool.self, forKey: .upscale) ?? upscale
        rotation = try c.decodeIfPresent(Int.self, forKey: .rotation) ?? rotation
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? flipHorizontal
        flipVertical = try c.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? flipVertical
        crop = try c.decodeIfPresent(CropAspect.self, forKey: .crop) ?? crop
        scaleSet = try c.decodeIfPresent(Bool.self, forKey: .scaleSet) ?? scaleSet
        pdfDPI = try c.decodeIfPresent(Int.self, forKey: .pdfDPI) ?? pdfDPI
        keepHDR = try c.decodeIfPresent(Bool.self, forKey: .keepHDR) ?? keepHDR
        convertToSRGB = try c.decodeIfPresent(Bool.self, forKey: .convertToSRGB) ?? convertToSRGB
        removeLocationOnly = try c.decodeIfPresent(Bool.self, forKey: .removeLocationOnly) ?? removeLocationOnly
        removeBackground = try c.decodeIfPresent(Bool.self, forKey: .removeBackground) ?? removeBackground
    }
    /// Choices that only make sense for the images they were made for; a new session starts without them.
    public mutating func resetSessionChoices() { metadataOnly = false; resizeOnly = false; webpLossless = false; rotation = 0; flipHorizontal = false; flipVertical = false; removeLocationOnly = false }
    /// The output name for `name` (the original's name, with any page or frame suffix) under `namePattern`.
    public func outputStem(_ name: String) -> String {
        let digits = max(2, String(sequenceCount).count)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let stem = namePattern.replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{n}", with: String(format: "%0\(digits)d", sequence))
            .replacingOccurrences(of: "{date}", with: formatter.string(from: Date()))
            .filter { !"/:\\".contains($0) }.trimmingCharacters(in: .whitespaces)
        // An empty or hidden name would be invisible in Finder.
        return stem.isEmpty ? name : stem.hasPrefix(".") ? name + stem : stem
    }
    /// Rotation, flips and crop, if any; empty when the image keeps its shape.
    public var shapeSummary: [String] {
        var parts: [String] = []
        if normalizedRotation != 0 { parts.append("\(normalizedRotation)°") }
        if flipHorizontal { parts.append("Flipped ↔") }
        if flipVertical { parts.append("Flipped ↕") }
        if crop != .none { parts.append(crop.rawValue) }
        if removeBackground { parts.append("No background") }
        return parts
    }
    public var normalizedRotation: Int { ((rotation % 360) + 360) % 360 / 90 * 90 }
    /// Largest output side Dice will produce.
    public static let maxSide = 32768
    /// Plans the output for an image that displays at `w` × `h`. Raster images never grow unless `upscale`;
    /// vector documents (`vector`) render at any requested size.
    public func geometry(width w: Int, height h: Int, vector: Bool = false) throws -> Geometry {
        guard w > 0, h > 0 else { throw DiceError.message("This image has no pixels.") }
        let turned = normalizedRotation % 180 == 90
        let (rw, rh) = turned ? (Double(h), Double(w)) : (Double(w), Double(h))
        var aspect = crop.ratio
        if resize == .fill {
            guard width > 0 && height > 0 else { throw DiceError.message("Width and height must be greater than zero.") }
            aspect = Double(width) / Double(height)
        }
        var (cw, ch) = (rw, rh)
        if let aspect { if cw / ch > aspect { cw = ch * aspect } else { ch = cw / aspect } }
        let grow = upscale || vector
        let factor: Double
        switch resize {
        case .original: factor = 1
        case .edge:
            guard edge > 0 else { throw DiceError.message("Enter a longest edge greater than zero.") }
            factor = Double(edge) / max(cw, ch)
        case .percent:
            guard percent > 0 else { throw DiceError.message("Percentage must be greater than zero.") }
            guard percent <= 100 || grow else { throw DiceError.message("Percentage must be between 1 and 100. Turn on Allow enlarging to go above 100.") }
            guard percent <= 1000 else { throw DiceError.message("Percentage can be at most 1000.") }
            factor = Double(percent) / 100
        case .fit:
            guard width > 0 && height > 0 else { throw DiceError.message("Width and height must be greater than zero.") }
            factor = min(Double(width) / cw, Double(height) / ch)
        case .width:
            guard width > 0 else { throw DiceError.message("Enter a width greater than zero.") }
            factor = Double(width) / cw
        case .height:
            guard height > 0 else { throw DiceError.message("Enter a height greater than zero.") }
            factor = Double(height) / ch
        case .fill: factor = Double(width) / cw
        }
        let scale = grow ? factor : min(1, factor)
        var tw = max(1, Int((cw * scale).rounded())), th = max(1, Int((ch * scale).rounded()))
        // Fill and crop gives the exact size whenever the image is large enough (or may grow).
        if resize == .fill && scale == factor { tw = width; th = height }
        guard tw <= Self.maxSide, th <= Self.maxSide else { throw DiceError.message("The output would be larger than \(Self.maxSide) pixels on a side.") }
        let longest = Double(max(w, h))
        let decode = max(1, Int(ceil(longest * (vector ? scale : min(1, scale)))))
        let cropped = aspect != nil && (Int(cw.rounded()) != Int(rw) || Int(ch.rounded()) != Int(rh))
        return Geometry(decodeEdge: decode, width: tw, height: th, crop: cropped ? aspect : nil, reorients: normalizedRotation != 0 || flipHorizontal || flipVertical)
    }
    /// Target longest edge of the output.
    public func longestEdge(width w: Int, height h: Int, upscale vector: Bool = false) throws -> Int {
        let g = try geometry(width: w, height: h, vector: vector)
        return max(g.width, g.height)
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
    /// A gain-map photo or a PQ/HLG image.
    public var isHDR = false
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
