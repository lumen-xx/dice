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
        let destination = format == .webp ? FileManager.default.temporaryDirectory.appendingPathComponent("dice-webp-" + UUID().uuidString + ".png") : output
        defer { if format == .webp { try? FileManager.default.removeItem(at: destination) } }
        let type = format == .webp ? UTType.png.identifier : format.type
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(type) == true,
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else { throw DiceError.message("This Mac cannot encode the selected format.") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: min(1,max(0,options.quality)), kCGImagePropertyOrientation: 1] as CFDictionary)
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
    /// Lossless PNG recompression. `--strip safe` keeps the chunks that affect rendering (colour profile, gamma);
    /// descriptive metadata is copied back afterwards when the user keeps it.
    static func optimizePNG(_ url: URL) throws {
        _ = try run(toolsDirectory.appendingPathComponent("oxipng"), ["-q", "-o", "2", "--strip", "safe", url.path])
    }
    /// Resamples to a longest edge, keeping the image's RGB colour space.
    static func resample(_ image: CGImage, longestEdge: Int) throws -> CGImage {
        let factor = Double(longestEdge) / Double(max(image.width, image.height))
        let w = max(1, Int((Double(image.width) * factor).rounded())), h = max(1, Int((Double(image.height) * factor).rounded()))
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
