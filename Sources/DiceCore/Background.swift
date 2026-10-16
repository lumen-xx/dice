import Foundation
import CoreGraphics
import CoreVideo
import Vision

/// On-device background removal with Vision's foreground instance mask (macOS 14+). Nothing leaves the Mac.
extension Engine {
    /// Keeps every subject Vision finds and makes the rest transparent. The original pixels are masked, not
    /// re-rendered, so colour space and HDR are preserved.
    static func removeBackground(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { throw DiceError.message("Background removal failed: \(error.localizedDescription)") }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw DiceError.message("Dice couldn't find a subject to keep in this image, so the background wasn't removed.") }
        let buffer: CVPixelBuffer
        do { buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) }
        catch { throw DiceError.message("Background removal failed: \(error.localizedDescription)") }
        let mask = try maskImage(buffer)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = canvas(like: image, width: image.width, height: image.height) else { throw DiceError.message("Could not prepare the image for background removal.") }
        ctx.clip(to: rect, mask: mask); ctx.draw(image, in: rect)
        guard let cutout = ctx.makeImage() else { throw DiceError.message("Could not remove the background.") }
        return cutout
    }
    /// Vision's mask is one 32-bit float per pixel (0 background … 1 subject); Core Graphics masks with 8-bit grey.
    static func maskImage(_ buffer: CVPixelBuffer) throws -> CGImage {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float else { throw DiceError.message("Background removal returned an unexpected mask.") }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw DiceError.message("Background removal returned an empty mask.") }
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width { gray[y * width + x] = UInt8((min(1, max(0, row[x])) * 255).rounded()) }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let mask = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw DiceError.message("Could not read the background mask.") }
        return mask
    }
}
