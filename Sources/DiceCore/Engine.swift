import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

public enum Engine {
    public static var toolsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["DICE_TOOLS"] { return URL(fileURLWithPath: path) }
        return Bundle.main.resourceURL!.appendingPathComponent("Tools")
    }
    public static func canEncode(_ format: OutputFormat) -> Bool {
        format == .original || format == .webp || format == .pdf || (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(format.type) == true
    }
    /// Reads the size from disk each time; URL resource values are cached and go stale when a file is rewritten.
    public static func fileSize(_ url: URL) -> Int64 { ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0 }
    /// Longest a bundled tool may run on one file before it is stopped.
    public static let toolTimeout: TimeInterval = 180
    public static func run(_ executable: URL, _ args: [String], timeout: TimeInterval = toolTimeout) throws -> Data {
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
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { throw DiceError.message("Could not start the image tool. Rebuild Dice with its bundled tools. " + error.localizedDescription) }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw DiceError.message("The image tool took longer than \(Int(timeout)) seconds on this file and was stopped.")
        }
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
        if DocumentImage.isPDF(url) { return try DocumentImage.pdf(url).numberOfPages }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) as String?, type == UTType.tiff.identifier else { return 1 }
        return max(1, CGImageSourceGetCount(source))
    }
    /// Types whose extra images are animation frames. TIFF images are pages; in other containers
    /// (icons, MPO stereo pairs, RAW previews, HEIC collections) the extras are alternatives to one picture.
    static let animationTypes: Set<String> = [UTType.gif.identifier, "org.webmproject.webp", UTType.png.identifier, "public.heics", "public.avis"]
    static func frameCount(_ source: CGImageSource) -> Int {
        let type = (CGImageSourceGetType(source) as String?) ?? ""
        return type == UTType.tiff.identifier || animationTypes.contains(type) ? CGImageSourceGetCount(source) : 1
    }
    /// The image to read for `page`: that page or frame where they exist, otherwise the largest icon size or the primary image.
    static func imageIndex(_ source: CGImageSource, page: Int) -> Int {
        let type = (CGImageSourceGetType(source) as String?) ?? ""
        if type == UTType.tiff.identifier || animationTypes.contains(type) { return page - 1 }
        let count = CGImageSourceGetCount(source)
        if [UTType.ico.identifier, UTType.icns.identifier, "com.microsoft.cur"].contains(type), count > 1 {
            func area(_ i: Int) -> Int {
                let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
                return (p?[kCGImagePropertyPixelWidth as String] as? Int ?? 0) * (p?[kCGImagePropertyPixelHeight as String] as? Int ?? 0)
            }
            return (0..<count).max { area($0) < area($1) } ?? 0
        }
        return page == 1 ? CGImageSourceGetPrimaryImageIndex(source) : count
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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, imageIndex(source, page: page), [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw DiceError.message("This image has no preview.") }
        return image
    }
    /// `reusing` is another page of the same file: its file-level metadata is reused instead of running ExifTool again.
    public static func inspect(_ url: URL, page: Int = 1, reusing known: ImageInfo? = nil) throws -> ImageInfo {
        let rawW: Int, rawH: Int, frames: Int, type: String
        let swapped: Bool
        if DocumentImage.isDocument(url) {
            (rawW, rawH, frames) = try DocumentImage.dimensions(url, page: page)
            type = DocumentImage.isPDF(url) ? UTType.pdf.identifier : UTType.svg.identifier
            swapped = false
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, imageIndex(source, page: page), nil) as? [String: Any] else { throw DiceError.message(DocumentImage.unsupportedReason(url) ?? "This file or frame is not a supported image.") }
            rawW = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            rawH = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
            swapped = (5...8).contains(props[kCGImagePropertyOrientation as String] as? Int ?? 1)
            type = (CGImageSourceGetType(source) as String?) ?? "Unknown"
            frames = frameCount(source)
        }
        var rows = try known.map { $0.rows.filter { $0.group != "Dice" } } ?? metadataRows(url)
        if DocumentImage.isDocument(url) {
            rows += [MetadataRow(group: "Dice", name: "FileType", value: url.pathExtension.uppercased()), MetadataRow(group: "Dice", name: "RasterSize", value: "\(rawW)x\(rawH)")]
            if type == UTType.pdf.identifier { rows += [MetadataRow(group: "Dice", name: "Page", value: "\(page) of \(frames)"), MetadataRow(group: "Dice", name: "RenderDPI", value: "144")] }
            rows.sort { ($0.group, $0.name) < ($1.group, $1.name) }
        }
        return ImageInfo(width: swapped ? rawH : rawW, height: swapped ? rawW : rawH, bytes: fileSize(url), type: type, frames: frames, rows: rows)
    }
    static func metadataRows(_ url: URL) throws -> [MetadataRow] {
        let data: Data
        if DocumentImage.kind(url) == .svg {
            data = (try? exif(["-j", "-G1:4", "-a", "-u", "-s", "-struct", url.path])) ?? Data("[{}]".utf8)
        } else { data = try exif(["-j", "-G1:4", "-a", "-u", "-s", "-struct", url.path]) }
        guard let object = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first else { throw DiceError.message("Could not read image metadata.") }
        return object.filter { $0.key != "SourceFile" }.map { key, value -> MetadataRow in
            let split = key.split(separator: ":", omittingEmptySubsequences: false)
            let name = String(split.last ?? Substring(key))
            let group = split.count > 1 ? split.dropLast().joined(separator: ":") : "File"
            let text: String
            if let value = value as? String { text = value }
            else if JSONSerialization.isValidJSONObject(value), let json = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let s = String(data: json, encoding: .utf8) { text = s }
            else { text = String(describing: value) }
            return MetadataRow(group: group, name: name, value: text)
        }.sorted { ($0.group, $0.name) < ($1.group, $1.name) }
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
        let inputType = document ? (DocumentImage.isPDF(input) ? UTType.pdf.identifier : UTType.svg.identifier) : ((source.flatMap { CGImageSourceGetType($0) } as String?) ?? "")
        guard document || source != nil else { throw DiceError.message("This file is not a supported image.") }
        var format = options.format
        var notes: [String] = []
        if format == .original && !options.metadataOnly {
            let match = OutputFormat.matching(inputType: inputType)
            format = match.format
            if !match.exact && !document { notes.append("Saved as \(format.rawValue); Dice can't write \(UTType(inputType)?.localizedDescription ?? "this format")") }
        }
        let count = try pageCount(input)
        let suffix = inputType == UTType.pdf.identifier || (inputType == UTType.tiff.identifier && count > 1) ? "-page-\(page)" : (count > 1 ? "-frame-\(page)" : "")
        let stem = input.deletingPathExtension().lastPathComponent + suffix + options.fileSuffix
        let output = uniqueURL(in: directory, stem: stem, ext: options.metadataOnly ? input.pathExtension : format.ext)
        if options.metadataOnly {
            let inputType = inputType
            guard metadataOnlyTypes.contains(inputType) else {
                throw DiceError.message("Metadata-only removal supports JPEG, PNG, HEIC, WebP, TIFF, AVIF, GIF and DNG. Convert this image to one of those formats to remove personal metadata.")
            }
            guard options.stripMetadata else { throw DiceError.message("Enable metadata removal for metadata-only mode.") }
            try FileManager.default.copyItem(at: input, to: output)
            do { try removeMetadata(output) }
            catch { try? FileManager.default.removeItem(at: output); throw error }
            return ConversionResult(url: output, bytes: fileSize(output), note: "Pixels unchanged; colour profile and orientation retained")
        }
        let imageInfo = try inspect(input, page: page)
        if let source, !document, count == 1, imageInfo.frames > 1, inputType != UTType.tiff.identifier {
            return try convertAnimated(input, source: source, format: format, options: options, info: imageInfo, directory: directory)
        }
        let edge = try options.longestEdge(width: imageInfo.width, height: imageInfo.height, upscale: document)
        var image = document ? try DocumentImage.render(input, page: page, edge: edge) : try previewImage(input, maxPixelSize: edge, page: page)
        if noAlpha.contains(format) { image = try flatten(image, color: options.flattenColor); notes.append("Transparency is flattened onto \(hex(options.flattenColor))") }
        if !options.stripMetadata && !document && !format.holdsMetadata { notes.append("Metadata isn't copied into \(format.rawValue), so none was kept") }
        let target: Int64? = options.useTargetSize && format.fitsTargetSize(lossless: options.webpLossless) ? Int64(max(1, options.targetKB)) * 1000 : nil
        if options.useTargetSize && target == nil { notes.append("\(format.rawValue) has no quality setting, so the target size wasn't applied") }
        let keepMetadata = !options.stripMetadata && !document && format.holdsMetadata
        var metadataBytes: Int64 = 0
        func write(budget: Int64?) throws {
            if let budget {
                let fitted = try encode(image, format: format, options: options, to: output, budget: budget)
                image = fitted.image; notes.removeAll { $0.hasPrefix("Fits ") }; notes.append(fitted.note)
            } else { try encode(image, format: format, options: options, to: output) }
            guard keepMetadata else { return }
            let before = fileSize(output)
            // Preserve descriptive tags, but keep the profile that describes the newly encoded pixels.
            let profile = try exif(["-b", "-ICC_Profile", output.path])
            let profileURL = directory.appendingPathComponent(UUID().uuidString + ".icc")
            defer { try? FileManager.default.removeItem(at: profileURL) }
            var args = ["-overwrite_original", "-tagsFromFile", input.path, "-all:all", "-ICC_Profile=", "-Orientation=1", "-ExifImageWidth=\(image.width)", "-ExifImageHeight=\(image.height)"]
            if !profile.isEmpty { try profile.write(to: profileURL); args.append("-ICC_Profile<=\(profileURL.path)") }
            args.append(output.path)
            _ = try exif(args)
            metadataBytes = fileSize(output) - before
        }
        do {
            try write(budget: target)
            // Kept metadata is added after the search; when it pushes the file over, search again without its bytes.
            if let target, fileSize(output) > target {
                guard target - metadataBytes > 0 else { throw DiceError.message("The kept metadata alone is larger than \(options.targetKB) KB. Remove personal metadata or choose a larger target.") }
                try write(budget: target - metadataBytes)
            }
            let sameShape = count == 1 && format.type == inputType && image.width == imageInfo.width && image.height == imageInfo.height
            if options.keepSmallerOriginal && !document && sameShape && fileSize(output) >= fileSize(input), let kept = try keepOriginal(input, at: output, removingMetadata: options.stripMetadata) {
                return ConversionResult(url: output, bytes: fileSize(output), note: kept)
            }
            return ConversionResult(url: output, bytes: fileSize(output), note: notes.isEmpty ? nil : notes.joined(separator: ". "))
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
    /// Types whose metadata ExifTool can remove in place without touching pixels.
    static let metadataOnlyTypes: Set<String> = [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, "org.webmproject.webp", UTType.tiff.identifier, "public.avif", UTType.gif.identifier, "com.adobe.raw-image"]
    /// Removes personal metadata in place, keeping the colour profile and orientation.
    static func removeMetadata(_ url: URL) throws {
        _ = try exif(["-overwrite_original", "-all=", "-EXIF:all=", "-XMP:all=", "-IPTC:all=", "-MakerNotes:all=", "-Photoshop:all=", "-tagsFromFile", "@", "-ICC_Profile", "-Orientation", url.path])
    }
    /// Puts the original's bytes at `output` when re-encoding made the file larger. Returns nil (leaving the
    /// re-encoded file) when metadata must go but can't be removed from this type in place.
    static func keepOriginal(_ input: URL, at output: URL, removingMetadata: Bool) throws -> String? {
        let type = (CGImageSourceCreateWithURL(input as CFURL, nil).flatMap { CGImageSourceGetType($0) } as String?) ?? ""
        if removingMetadata && !metadataOnlyTypes.contains(type) { return nil }
        let reencoded = output.deletingLastPathComponent().appendingPathComponent(".dice-reencoded-" + UUID().uuidString)
        try FileManager.default.moveItem(at: output, to: reencoded)
        do {
            try FileManager.default.copyItem(at: input, to: output)
            if removingMetadata { try removeMetadata(output) }
            try? FileManager.default.removeItem(at: reencoded)
        } catch {
            try? FileManager.default.removeItem(at: output); try? FileManager.default.moveItem(at: reencoded, to: output); throw error
        }
        return "Kept the original's pixels; re-encoding made the file larger" + (removingMetadata ? ". Personal metadata removed" : "")
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
