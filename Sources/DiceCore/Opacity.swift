import CoreGraphics

public enum Opacity {
    /// True when no pixel is noticeably transparent. Images without an alpha channel answer at once; others are
    /// drawn at 256 × 256 and checked for alpha below 250, so a transparent corner or border still counts.
    public static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return true; default: break }
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return !stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }
}
