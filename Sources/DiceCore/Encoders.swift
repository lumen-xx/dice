import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Pixel preparation and writing: flattening, still and animated encoders, and size optimisation.
extension Engine {
    static let noAlpha: [OutputFormat] = [.jpeg, .bmp]
    public static func hex(_ color: [Double]) -> String {
        "#" + (color + [1, 1, 1]).prefix(3).map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
    /// Draws `image` over an opaque background of `color` so formats without alpha get a predictable fill.
    static func flatten(_ image: CGImage, color: [Double]) throws -> CGImage {
        let c = color + [1, 1, 1]
        // Keep the image's own RGB space (Display P3, for instance) so flattening doesn't clip wide-gamut colour.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw DiceError.message("Could not prepare the output image.") }
        ctx.setFillColor(CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = ctx.makeImage() else { throw DiceError.message("Could not prepare the output image.") }
        return flat
    }
    /// Writes one still image in `format`; WebP goes through a temporary PNG and cwebp.
    /// The temporary PNG gets its own name, so it can never replace another result beside `output`.
    static func encode(_ image: CGImage, format: OutputFormat, options: Options, to output: URL) throws {
        if format.isIcon { return try encodeIcon(image, format: format, to: output) }
        if format == .pdf { return try encodePDFPage(image, quality: options.quality, to: output) }
        let destination = format == .webp ? FileManager.default.temporaryDirectory.appendingPathComponent("dice-webp-" + UUID().uuidString + ".png") : output
        defer { if format == .webp { try? FileManager.default.removeItem(at: destination) } }
        let type = format == .webp ? UTType.png.identifier : format.type
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(type) == true,
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else { throw DiceError.message("This Mac cannot encode the selected format.") }
        // The AVIF encoder fails outright at quality 1.0, so its top setting is 0.99 (visually the same).
        let ceiling = format == .avif ? 0.99 : 1
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: min(ceiling, max(0, options.quality)), kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DiceError.message("Could not write the converted image.") }
        if format == .png && options.optimizePNG { try optimizePNG(output) }
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
    /// Pads to a square on transparency, centred, so icons never stretch.
    static func squared(_ image: CGImage) throws -> CGImage {
        guard image.width != image.height else { return image }
        let side = max(image.width, image.height)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DiceError.message("Could not prepare the icon.") }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: (side - image.width) / 2, y: (side - image.height) / 2, width: image.width, height: image.height))
        guard let square = ctx.makeImage() else { throw DiceError.message("Could not prepare the icon.") }
        return square
    }
    /// One file holding every standard size up to the image's own; an image smaller than the smallest size is scaled up to it.
    static func encodeIcon(_ image: CGImage, format: OutputFormat, to output: URL) throws {
        let square = try squared(image)
        var sizes = format.iconSizes.filter { $0 <= square.width }
        if sizes.isEmpty { sizes = [format.iconSizes.last!] }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, format.type as CFString, sizes.count, nil) else { throw DiceError.message("This Mac cannot write \(format.rawValue) files.") }
        for size in sizes { CGImageDestinationAddImage(dest, size == square.width ? square : try resample(square, longestEdge: size), nil) }
        guard CGImageDestinationFinalize(dest) else { throw DiceError.message("Could not write the \(format.rawValue) file.") }
    }
    /// A one-page PDF the size of the image (1 pixel = 1 point). Opaque images are embedded as JPEG at `quality`;
    /// images with transparency are embedded losslessly.
    static func encodePDFPage(_ image: CGImage, quality: Double, to output: URL) throws {
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, (opaque ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil) else { throw DiceError.message("Could not prepare the PDF page.") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: min(1, max(0, quality))] as CFDictionary)
        guard CGImageDestinationFinalize(dest), let provider = CGDataProvider(data: data),
              let embedded = opaque ? CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) : CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw DiceError.message("Could not prepare the PDF page.") }
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(output as CFURL, mediaBox: &box, nil) else { throw DiceError.message("Could not write the PDF.") }
        ctx.beginPDFPage(nil); ctx.draw(embedded, in: box); ctx.endPDFPage(); ctx.closePDF()
    }
    /// Joins single- or multi-page PDFs, in order, into one document.
    public static func combinePDFs(_ inputs: [URL], to output: URL) throws {
        guard !inputs.isEmpty else { throw DiceError.message("There are no PDF pages to combine.") }
        var box = CGRect.zero
        guard let ctx = CGContext(output as CFURL, mediaBox: &box, nil) else { throw DiceError.message("Could not write the combined PDF.") }
        for url in inputs {
            guard let document = CGPDFDocument(url as CFURL) else { throw DiceError.message("Could not read \(url.lastPathComponent) to combine it.") }
            for index in 1...max(1, document.numberOfPages) {
                guard let page = document.page(at: index) else { continue }
                var media = page.getBoxRect(.mediaBox)
                let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
                ctx.beginPDFPage(info); ctx.drawPDFPage(page); ctx.endPDFPage()
            }
        }
        ctx.closePDF()
    }
    /// Writes an animation in `format`: GIF, APNG and HEIC sequences through ImageIO, WebP through img2webp.
    static func encodeAnimation(_ source: CGImageSource, frames total: Int, geometry: Geometry, format: OutputFormat, options: Options, to output: URL) throws {
        func frame(_ index: Int) throws -> CGImage { try shape(try frameImage(source, index, maxPixelSize: geometry.decodeEdge), geometry, options: options) }
        if format == .webp {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dice-frames-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            var args = ["-loop", "0", options.webpLossless ? "-lossless" : "-lossy", "-q", String(Int(options.quality * 100))]
            for index in 0..<total {
                try autoreleasepool {
                    let file = folder.appendingPathComponent(String(format: "%05d.png", index))
                    var still = options; still.optimizePNG = false
                    try encode(try frame(index), format: .png, options: still, to: file)
                    args += ["-d", String(max(10, Int((frameDelay(source, index) * 1000).rounded()))), file.path]
                }
            }
            _ = try run(toolsDirectory.appendingPathComponent("img2webp"), args + ["-o", output.path])
            return
        }
        let (type, file, frameKey, loop, delay): (String, CFString, CFString, CFString, CFString) = switch format {
        case .png: (UTType.png.identifier, kCGImagePropertyPNGDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount, kCGImagePropertyAPNGDelayTime)
        case .heic: ("public.heics", kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSLoopCount, kCGImagePropertyHEICSDelayTime)
        default: (UTType.gif.identifier, kCGImagePropertyGIFDictionary, kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount, kCGImagePropertyGIFDelayTime)
        }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type as CFString, total, nil) else { throw DiceError.message("This Mac cannot write animated \(format.rawValue).") }
        CGImageDestinationSetProperties(dest, [file: [loop: 0]] as CFDictionary)
        for index in 0..<total {
            try autoreleasepool {
                let image = try frame(index)
                CGImageDestinationAddImage(dest, image, [frameKey: [delay: frameDelay(source, index)], kCGImageDestinationLossyCompressionQuality: min(1, max(0, options.quality))] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(dest) else { throw DiceError.message("Could not write the animated \(format.rawValue).") }
    }
    /// Animated input → an animation when the format can hold one and `keepAnimation`; otherwise a folder of numbered frames, or just the first frame.
    static func convertAnimated(_ input: URL, source: CGImageSource, format: OutputFormat, options: Options, info: ImageInfo, directory: URL) throws -> ConversionResult {
        let total = info.frames
        let geometry = try options.geometry(width: info.width, height: info.height)
        let stem = input.deletingPathExtension().lastPathComponent
        if format.animates && options.keepAnimation {
            let output = uniqueURL(in: directory, stem: stem + options.fileSuffix, ext: format == .heic ? "heics" : format.ext)
            do { try encodeAnimation(source, frames: total, geometry: geometry, format: format, options: options, to: output) }
            catch { try? FileManager.default.removeItem(at: output); throw error }
            return ConversionResult(url: output, bytes: fileSize(output), note: "Animation kept (\(total) frames)")
        }
        let note = noAlpha.contains(format) ? "Transparency is flattened onto \(hex(options.flattenColor))" : nil
        func still(_ index: Int, to url: URL) throws {
            try autoreleasepool {
                var frame = try shape(try frameImage(source, index, maxPixelSize: geometry.decodeEdge), geometry, options: options)
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
    /// Lossless PNG recompression. `--strip safe` keeps the chunks that affect rendering (colour profile, gamma);
    /// descriptive metadata is copied back afterwards when the user keeps it.
    static func optimizePNG(_ url: URL) throws {
        _ = try run(toolsDirectory.appendingPathComponent("oxipng"), ["-q", "-o", "2", "--strip", "safe", url.path])
    }
    /// Resamples to a longest edge, keeping the image's RGB colour space.
    static func resample(_ image: CGImage, longestEdge: Int) throws -> CGImage {
        let factor = Double(longestEdge) / Double(max(image.width, image.height))
        return try resample(image, width: max(1, Int((Double(image.width) * factor).rounded())), height: max(1, Int((Double(image.height) * factor).rounded())))
    }
    /// Applies a `Geometry` to a decoded image: rotation and flips, the centred crop, then the exact output size.
    static func shape(_ image: CGImage, _ geometry: Geometry, options: Options) throws -> CGImage {
        var out = image
        if geometry.reorients { out = try reorient(out, rotation: options.normalizedRotation, flipHorizontal: options.flipHorizontal, flipVertical: options.flipVertical) }
        if let aspect = geometry.crop {
            var w = Double(out.width), h = Double(out.height)
            if w / h > aspect { w = h * aspect } else { h = w / aspect }
            let rect = CGRect(x: ((Double(out.width) - w) / 2).rounded(), y: ((Double(out.height) - h) / 2).rounded(), width: max(1, w.rounded()), height: max(1, h.rounded()))
            guard let cropped = out.cropping(to: rect) else { throw DiceError.message("Could not crop the image.") }
            out = cropped
        }
        if out.width != geometry.width || out.height != geometry.height { out = try resample(out, width: geometry.width, height: geometry.height) }
        return out
    }
    /// Clockwise rotation by a multiple of 90°, then mirroring, keeping the image's RGB colour space.
    static func reorient(_ image: CGImage, rotation: Int, flipHorizontal: Bool, flipVertical: Bool) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let turned = rotation % 180 == 90
        let (nw, nh) = turned ? (h, w) : (w, h)
        // Core Graphics has y pointing up, so a clockwise turn is a negative angle.
        var t: CGAffineTransform = switch rotation {
        case 90: CGAffineTransform(translationX: 0, y: w).rotated(by: -.pi / 2)
        case 180: CGAffineTransform(translationX: w, y: h).rotated(by: .pi)
        case 270: CGAffineTransform(translationX: h, y: 0).rotated(by: .pi / 2)
        default: .identity
        }
        if flipHorizontal { t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: nw, ty: 0)) }
        if flipVertical { t = t.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: nh)) }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(nw), height: Int(nh), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DiceError.message("Could not rotate the image.") }
        ctx.concatenate(t); ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let turnedImage = ctx.makeImage() else { throw DiceError.message("Could not rotate the image.") }
        return turnedImage
    }
    /// Resamples to an exact size, keeping the image's RGB colour space.
    static func resample(_ image: CGImage, width w: Int, height h: Int) throws -> CGImage {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DiceError.message("Could not resize the image.") }
        ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { throw DiceError.message("Could not resize the image.") }
        return scaled
    }
    /// Writes `image` at the highest quality whose file fits `budget` bytes, searching quality first and then,
    /// when even the lowest quality is too large, shrinking the image. Returns the image written and a note.
    static func encode(_ image: CGImage, format: OutputFormat, options: Options, to output: URL, budget: Int64) throws -> (image: CGImage, note: String) {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("dice-target-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        func attempt(_ image: CGImage, _ quality: Double) throws -> (URL, Int64) {
            var o = options; o.quality = quality
            let url = scratch.appendingPathComponent(UUID().uuidString + "." + format.ext)
            try encode(image, format: format, options: o, to: url)
            return (url, fileSize(url))
        }
        let floor = 0.05
        var current = image
        for round in 0..<4 {
            var best: (url: URL, quality: Double)?
            let lowest = try attempt(current, floor)
            if lowest.1 <= budget {
                best = (lowest.0, floor)
                var lo = floor, hi = 1.0
                for _ in 0..<7 {
                    let mid = (lo + hi) / 2
                    let tried = try attempt(current, mid)
                    if tried.1 <= budget { best = (tried.0, mid); lo = mid } else { hi = mid }
                }
            }
            if let best {
                if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
                try FileManager.default.moveItem(at: best.url, to: output)
                let quality = "quality \(Int((best.quality * 100).rounded()))%"
                let size = round == 0 ? "" : ", reduced to \(current.width) × \(current.height)"
                return (current, "Fits \(options.targetKB) KB at \(quality)\(size)")
            }
            // Bytes scale roughly with pixel count: shrink by the square root of the overshoot, with a margin.
            let factor = min(0.9, (Double(budget) / Double(lowest.1)).squareRoot() * 0.95)
            let edge = Int(Double(max(current.width, current.height)) * factor)
            guard edge >= 16 else { break }
            current = try resample(current, longestEdge: edge)
        }
        throw DiceError.message("This image can't be made as small as \(options.targetKB) KB in \(format.rawValue).")
    }
}
