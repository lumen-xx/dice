import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

public enum DiceError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
public enum OutputFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case original = "Same as original", jpeg = "JPEG", png = "PNG", heic = "HEIC", webp = "WebP", gif = "GIF", bmp = "BMP", tiff = "TIFF", avif = "AVIF"
    public var id: String { rawValue }
    public var ext: String { switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic: return "heic"; case .webp: return "webp"; case .gif: return "gif"; case .bmp: return "bmp"; case .tiff: return "tiff"; case .avif: return "avif"; case .original: return "" } }
    public var type: String { switch self { case .jpeg: return UTType.jpeg.identifier; case .png: return UTType.png.identifier; case .heic: return UTType.heic.identifier; case .webp: return "org.webmproject.webp"; case .gif: return UTType.gif.identifier; case .bmp: return UTType.bmp.identifier; case .tiff: return UTType.tiff.identifier; case .avif: return "public.avif"; case .original: return "" } }
    public var usesQuality: Bool { [.original, .jpeg, .heic, .webp, .avif].contains(self) }

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
    /// Keep animated images animated when the output is GIF.
    public var keepAnimation = true
    /// Animated images exported to a still format become a folder of frames; otherwise only the first frame is exported.
    public var framesAsFolder = true
    /// Appended to the original name for saved copies.
    public var fileSuffix = "-dice"
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
    }
    public func longestEdge(width w: Int, height h: Int) throws -> Int {
        let longest = max(w,h)
        switch resize {
        case .original: return longest
        case .edge: guard edge > 0 else { throw DiceError.message("Enter a longest edge greater than zero.") }; return min(longest, edge)
        case .percent: guard percent > 0 && percent <= 100 else { throw DiceError.message("Percentage must be between 1 and 100.") }; return max(1, Int(Double(longest) * Double(percent) / 100))
        case .fit: guard width > 0 && height > 0 else { throw DiceError.message("Width and height must be greater than zero.") }; return max(1, Int(Double(longest) * min(1, min(Double(width)/Double(w), Double(height)/Double(h)))))
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
}
public enum Engine {
    public static var toolsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["DICE_TOOLS"] { return URL(fileURLWithPath: path) }
        return Bundle.main.resourceURL!.appendingPathComponent("Tools")
    }
    public static func canEncode(_ format: OutputFormat) -> Bool {
        format == .original || format == .webp || (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(format.type) == true
    }
    public static func fileSize(_ url: URL) -> Int64 { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
    static func run(_ executable: URL, _ args: [String]) throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dice-tool-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("stdout"), err = dir.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let oh = try FileHandle(forWritingTo: out), eh = try FileHandle(forWritingTo: err)
        defer { try? oh.close(); try? eh.close() }
        let process = Process()
        process.executableURL = executable; process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        for key in ["PERL5LIB", "PERL5OPT", "PERLLIB", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH"] { environment.removeValue(forKey: key) }
        process.environment = environment
        process.standardOutput = oh; process.standardError = eh
        do { try process.run() } catch { throw DiceError.message("Could not start the image tool. Rebuild Dice with its bundled tools. " + error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: (try? Data(contentsOf: err)) ?? Data(), encoding: .utf8) ?? ""
            throw DiceError.message(message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "The image tool could not process this file.")
        }
        return try Data(contentsOf: out)
    }
    static func exif(_ args: [String]) throws -> Data {
        let script = toolsDirectory.appendingPathComponent("exiftool/exiftool")
        guard FileManager.default.fileExists(atPath: script.path) else { throw DiceError.message("The bundled metadata tool is missing.") }
        return try run(URL(fileURLWithPath: "/usr/bin/perl"), ["-I", script.deletingLastPathComponent().appendingPathComponent("lib").path, script.path, "-config", ""] + args)
    }
    public static func pageCount(_ url: URL) throws -> Int {
        if url.pathExtension.lowercased() == "pdf" { return try DocumentImage.pdf(url).numberOfPages }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) as String?, type == UTType.tiff.identifier else { return 1 }
        return max(1, CGImageSourceGetCount(source))
    }
    public static func scaledPreview(_ image: CGImage, maxPixelSize: Int) throws -> CGImage {
        let factor = min(1, Double(maxPixelSize) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * factor)), h = max(1, Int(Double(image.height) * factor))
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DiceError.message("Could not prepare an image preview.") }
        context.interpolationQuality = .high; context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let preview = context.makeImage() else { throw DiceError.message("Could not prepare an image preview.") }
        return preview
    }
    public static func previewImage(_ url: URL, maxPixelSize: Int, page: Int = 1) throws -> CGImage {
        if DocumentImage.isDocument(url) {
            let (w, h, _) = try DocumentImage.dimensions(url, page: page)
            return try DocumentImage.render(url, page: page, edge: min(max(w, h), maxPixelSize))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, page - 1, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw DiceError.message("This image has no preview.") }
        return image
    }
    public static func inspect(_ url: URL, page: Int = 1) throws -> ImageInfo {
        let rawW: Int, rawH: Int, frames: Int, type: String
        let swapped: Bool
        if DocumentImage.isDocument(url) {
            (rawW, rawH, frames) = try DocumentImage.dimensions(url, page: page)
            type = url.pathExtension.lowercased() == "pdf" ? UTType.pdf.identifier : UTType.svg.identifier
            swapped = false
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, page - 1, nil) as? [String: Any] else { throw DiceError.message("This file or frame is not a supported image.") }
            rawW = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            rawH = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
            swapped = (5...8).contains(props[kCGImagePropertyOrientation as String] as? Int ?? 1)
            type = (CGImageSourceGetType(source) as String?) ?? "Unknown"
            frames = CGImageSourceGetCount(source)
        }
        let data: Data
        if url.pathExtension.lowercased() == "svg" {
            data = (try? exif(["-j", "-G1:4", "-a", "-u", "-s", "-struct", url.path])) ?? Data("[{}]".utf8)
        } else { data = try exif(["-j", "-G1:4", "-a", "-u", "-s", "-struct", url.path]) }
        guard let object = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first else { throw DiceError.message("Could not read image metadata.") }
        var rows = object.filter { $0.key != "SourceFile" }.map { key, value -> MetadataRow in
            let split = key.split(separator: ":", omittingEmptySubsequences: false)
            let name = String(split.last ?? Substring(key))
            let group = split.count > 1 ? split.dropLast().joined(separator: ":") : "File"
            let text: String
            if let value = value as? String { text = value }
            else if JSONSerialization.isValidJSONObject(value), let json = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let s = String(data: json, encoding: .utf8) { text = s }
            else { text = String(describing: value) }
            return MetadataRow(group: group, name: name, value: text)
        }.sorted { ($0.group, $0.name) < ($1.group, $1.name) }
        if DocumentImage.isDocument(url) {
            rows += [MetadataRow(group: "Dice", name: "FileType", value: url.pathExtension.uppercased()), MetadataRow(group: "Dice", name: "RasterSize", value: "\(rawW)x\(rawH)")]
            if type == UTType.pdf.identifier { rows += [MetadataRow(group: "Dice", name: "Page", value: "\(page) of \(frames)"), MetadataRow(group: "Dice", name: "RenderDPI", value: "144")] }
            rows.sort { ($0.group, $0.name) < ($1.group, $1.name) }
        }
        return ImageInfo(width: swapped ? rawH : rawW, height: swapped ? rawW : rawH, bytes: fileSize(url), type: type, frames: frames, rows: rows)
    }
    /// Resolution-only batch action. Already-small inputs are left untouched.
    public static func resize(_ input: URL, options: Options, directory: URL, page: Int = 1) throws -> ConversionResult? {
        let info = try inspect(input, page: page)
        let target = try options.longestEdge(width: info.width, height: info.height)
        guard target < max(info.width, info.height) else { return nil }
        var resize = options
        resize.format = .original; resize.metadataOnly = false; resize.stripMetadata = false
        resize.quality = 1; resize.webpLossless = true; resize.keepAnimation = true
        return try convert(input, options: resize, directory: directory, page: page)
    }
    public static func convert(_ input: URL, options: Options, directory: URL, page: Int = 1) throws -> ConversionResult {
        let document = DocumentImage.isDocument(input)
        let source = document ? nil : CGImageSourceCreateWithURL(input as CFURL, nil)
        let inputType = document ? (input.pathExtension.lowercased() == "pdf" ? UTType.pdf.identifier : UTType.svg.identifier) : ((source.flatMap { CGImageSourceGetType($0) } as String?) ?? "")
        guard document || source != nil else { throw DiceError.message("This file is not a supported image.") }
        var format = options.format
        if format == .original && !options.metadataOnly {
            if document { format = .png }
            else {
                format = OutputFormat.allCases.first(where: { $0 != .original && $0.type == inputType }) ?? .png
            }
        }
        let count = try pageCount(input)
        let suffix = inputType == UTType.pdf.identifier || (inputType == UTType.tiff.identifier && count > 1) ? "-page-\(page)" : (count > 1 ? "-frame-\(page)" : "")
        let stem = input.deletingPathExtension().lastPathComponent + suffix + options.fileSuffix
        let output = uniqueURL(in: directory, stem: stem, ext: options.metadataOnly ? input.pathExtension : format.ext)
        if options.metadataOnly {
            let inputType = inputType
            guard [OutputFormat.jpeg, .png, .heic, .webp].contains(where: { $0.type == inputType }) else {
                throw DiceError.message("Metadata-only removal supports JPEG, PNG, HEIC and WebP. Convert this image to one of those formats to remove personal metadata.")
            }
            guard options.stripMetadata else { throw DiceError.message("Enable metadata removal for metadata-only mode.") }
            try FileManager.default.copyItem(at: input, to: output)
            do { _ = try exif(["-overwrite_original", "-all=", "-EXIF:all=", "-XMP:all=", "-IPTC:all=", "-MakerNotes:all=", "-Photoshop:all=", "-tagsFromFile", "@", "-ICC_Profile", "-Orientation", output.path]) }
            catch { try? FileManager.default.removeItem(at: output); throw error }
            return ConversionResult(url: output, bytes: fileSize(output), note: "Pixels unchanged; colour profile and orientation retained")
        }
        let imageInfo = try inspect(input, page: page)
        let isRaw = UTType(inputType)?.conforms(to: .rawImage) == true
        if let source, !document, !isRaw, count == 1, imageInfo.frames > 1, inputType != UTType.tiff.identifier {
            return try convertAnimated(input, source: source, format: format, options: options, info: imageInfo, directory: directory)
        }
        let edge = try options.longestEdge(width: imageInfo.width, height: imageInfo.height)
        var image = try previewImage(input, maxPixelSize: edge, page: page)
        if noAlpha.contains(format) { image = try flatten(image, color: options.flattenColor) }
        do {
            try encode(image, format: format, options: options, to: output)
            if !options.stripMetadata && !document {
                // Preserve descriptive tags, but keep the profile that describes the newly encoded pixels.
                let profile = try exif(["-b", "-ICC_Profile", output.path])
                let profileURL = directory.appendingPathComponent(UUID().uuidString + ".icc")
                defer { try? FileManager.default.removeItem(at: profileURL) }
                var args = ["-overwrite_original", "-tagsFromFile", input.path, "-all:all", "-ICC_Profile=", "-Orientation=1", "-ExifImageWidth=\(image.width)", "-ExifImageHeight=\(image.height)"]
                if !profile.isEmpty { try profile.write(to: profileURL); args.append("-ICC_Profile<=\(profileURL.path)") }
                args.append(output.path)
                _ = try exif(args)
            }
            return ConversionResult(url: output, bytes: fileSize(output), note: noAlpha.contains(format) ? "Transparency is flattened onto \(hex(options.flattenColor))" : nil)
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
    static let noAlpha: [OutputFormat] = [.jpeg, .bmp]
    public static func hex(_ color: [Double]) -> String {
        "#" + (color + [1, 1, 1]).prefix(3).map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
    /// Draws `image` over an opaque background of `color` so formats without alpha get a predictable fill.
    static func flatten(_ image: CGImage, color: [Double]) throws -> CGImage {
        let c = color + [1, 1, 1]
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw DiceError.message("Could not prepare the output image.") }
        ctx.setFillColor(CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = ctx.makeImage() else { throw DiceError.message("Could not prepare the output image.") }
        return flat
    }
    /// Writes one still image in `format`; WebP goes through a temporary PNG and cwebp.
    static func encode(_ image: CGImage, format: OutputFormat, options: Options, to output: URL) throws {
        let destination = format == .webp ? output.deletingPathExtension().appendingPathExtension("png") : output
        defer { if format == .webp { try? FileManager.default.removeItem(at: destination) } }
        let type = format == .webp ? UTType.png.identifier : format.type
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(type) == true,
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else { throw DiceError.message("This Mac cannot encode the selected format.") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: min(1,max(0,options.quality)), kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DiceError.message("Could not write the converted image.") }
        if format == .webp {
            var args = ["-quiet", "-q", String(Int(options.quality * 100)), "-metadata", "icc"]
            if options.webpLossless { args.append("-lossless") }
            args += [destination.path, "-o", output.path]
            _ = try run(toolsDirectory.appendingPathComponent("cwebp"), args)
        }
    }
    static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else { return 0.1 }
        for key in [kCGImagePropertyGIFDictionary, kCGImagePropertyWebPDictionary, kCGImagePropertyPNGDictionary] {
            guard let dictionary = props[key as String] as? [String: Any] else { continue }
            for name in [kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyGIFDelayTime, kCGImagePropertyWebPDelayTime, kCGImagePropertyAPNGDelayTime] {
                if let delay = dictionary[name as String] as? Double, delay > 0 { return delay }
            }
        }
        return 0.1
    }
    static func frameImage(_ source: CGImageSource, _ index: Int, maxPixelSize: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw DiceError.message("Could not read frame \(index + 1).") }
        return image
    }
    /// Animated GIF → animated GIF when `keepAnimation`; otherwise a folder of numbered frames, or just the first frame.
    static func convertAnimated(_ input: URL, source: CGImageSource, format: OutputFormat, options: Options, info: ImageInfo, directory: URL) throws -> ConversionResult {
        let total = info.frames
        let edge = try options.longestEdge(width: info.width, height: info.height)
        let stem = input.deletingPathExtension().lastPathComponent
        if format == .gif && options.keepAnimation {
            let output = uniqueURL(in: directory, stem: stem + options.fileSuffix, ext: "gif")
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, total, nil) else { throw DiceError.message("This Mac cannot encode GIF.") }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            do {
                for index in 0..<total {
                    try autoreleasepool {
                        let frame = try frameImage(source, index, maxPixelSize: edge)
                        CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay(source, index)]] as CFDictionary)
                    }
                }
                guard CGImageDestinationFinalize(dest) else { throw DiceError.message("Could not write the animated GIF.") }
            } catch { try? FileManager.default.removeItem(at: output); throw error }
            return ConversionResult(url: output, bytes: fileSize(output), note: "Animation kept (\(total) frames)")
        }
        let note = noAlpha.contains(format) ? "Transparency is flattened onto \(hex(options.flattenColor))" : nil
        func still(_ index: Int, to url: URL) throws {
            try autoreleasepool {
                var frame = try frameImage(source, index, maxPixelSize: edge)
                if noAlpha.contains(format) { frame = try flatten(frame, color: options.flattenColor) }
                try encode(frame, format: format, options: options, to: url)
            }
        }
        if !options.framesAsFolder {
            let output = uniqueURL(in: directory, stem: stem + options.fileSuffix, ext: format.ext)
            do { try still(0, to: output) } catch { try? FileManager.default.removeItem(at: output); throw error }
            return ConversionResult(url: output, bytes: fileSize(output), note: note)
        }
        let folder = uniqueURL(in: directory, stem: stem + "-frames" + options.fileSuffix, ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let digits = max(4, String(total).count)
            var size: Int64 = 0
            for index in 0..<total {
                let file = folder.appendingPathComponent("frame-" + String(format: "%0\(digits)d", index + 1) + "." + format.ext)
                try still(index, to: file); size += fileSize(file)
            }
            return ConversionResult(url: folder, bytes: size, note: "\(total) frames", previewURL: folder.appendingPathComponent("frame-" + String(format: "%0\(digits)d", 1) + "." + format.ext))
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    public static func saveCopy(_ result: ConversionResult, beside input: URL, directory: URL? = nil) throws -> URL {
        let output = uniqueURL(in: directory ?? input.deletingLastPathComponent(), stem: result.url.deletingPathExtension().lastPathComponent, ext: result.url.pathExtension)
        try FileManager.default.copyItem(at: result.url, to: output)
        return output
    }
    /// Moves `original` to the Trash and puts the processed file in its place under the original's name
    /// (with the processed extension). The processed copy is staged first, so a failure leaves the original intact.
    public static func replaceOriginal(_ original: URL, with result: ConversionResult) throws -> URL {
        let directory = original.deletingLastPathComponent()
        let staged = directory.appendingPathComponent(".dice-" + UUID().uuidString + "." + result.url.pathExtension)
        try FileManager.default.copyItem(at: result.url, to: staged)
        do { try FileManager.default.trashItem(at: original, resultingItemURL: nil) }
        catch { try? FileManager.default.removeItem(at: staged); throw DiceError.message("Could not move the original to the Trash: " + error.localizedDescription) }
        let stem = original.deletingPathExtension().lastPathComponent
        let ext = result.url.pathExtension
        let target = uniqueURL(in: directory, stem: stem, ext: ext)
        do { try FileManager.default.moveItem(at: staged, to: target) }
        catch { try? FileManager.default.removeItem(at: staged); throw error }
        return target
    }
    public static func uniqueURL(in directory: URL, stem: String, ext: String) -> URL {
        let dot = ext.isEmpty ? "" : "."
        var candidate = directory.appendingPathComponent(stem + dot + ext); var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) { candidate = directory.appendingPathComponent(stem + "-\(suffix)" + dot + ext); suffix += 1 }
        return candidate
    }
}
