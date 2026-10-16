import AppKit
import DiceCore

/// "Fit photos to the window": which previews may fill the window edge to edge. Only opaque raster images do;
/// anything with transparent pixels keeps its margins, so it's never cropped against the window material.
@MainActor enum PreviewFill {
    private static var opaque: [String: Bool] = [:]
    /// Cached per preview key; see `Opacity.isOpaque`.
    static func isOpaque(_ image: NSImage, key: String) -> Bool {
        if let known = opaque[key] { return known }
        let result = image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(Opacity.isOpaque) ?? false
        if opaque.count > 512 { opaque.removeAll() }
        opaque[key] = result
        return result
    }
}
