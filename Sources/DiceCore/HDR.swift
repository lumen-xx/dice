import Foundation
import ImageIO
import CoreGraphics

/// HDR photos: gain-map images (ISO 21496-1 or Apple's) and PQ/HLG images. Dice keeps them HDR when the output
/// can hold a gain map (HEIC, JPEG, AVIF), and otherwise tone-maps them to SDR.
extension Engine {
    /// Formats ImageIO writes with an ISO gain map.
    static let gainMapFormats: [OutputFormat] = [.heic, .jpeg, .avif]
    static var hdrAvailable: Bool { if #available(macOS 15, *) { return true } else { return false } }

    static func hasGainMap(_ source: CGImageSource, _ index: Int) -> Bool {
        var types = [kCGImageAuxiliaryDataTypeHDRGainMap]
        if #available(macOS 15, *) { types.append(kCGImageAuxiliaryDataTypeISOGainMap) }
        return types.contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, $0) != nil }
    }
    static func hasGainMap(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return hasGainMap(source, CGImageSourceGetPrimaryImageIndex(source))
    }
    /// True for gain-map images and for images in a PQ or HLG colour space.
    static func isHDR(_ source: CGImageSource, _ index: Int) -> Bool {
        if hasGainMap(source, index) { return true }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any], let name = props[kCGImagePropertyProfileName as String] as? String else { return false }
        return ["PQ", "HLG", "2100"].contains { name.contains($0) }
    }
    /// An image whose pixels go beyond SDR white: decoded HDR, or in an extended-range space.
    static func isHDR(_ image: CGImage) -> Bool {
        guard let space = image.colorSpace else { return false }
        return CGColorSpaceUsesITUR_2100TF(space) || CGColorSpaceUsesExtendedRange(space)
    }
    /// Decode options asking ImageIO for HDR pixels, or for tone-mapped SDR pixels from an HDR source.
    static func decodeRequest(hdr: Bool) -> [CFString: Any] {
        guard #available(macOS 15, *) else { return [:] }
        return [kCGImageSourceDecodeRequest: hdr ? kCGImageSourceDecodeToHDR : kCGImageSourceDecodeToSDR]
    }
    /// A drawing surface for `image`'s pixels: half-float extended linear Display P3 for HDR, so nothing above
    /// SDR white is clipped; otherwise 8-bit in the image's own RGB space.
    static func canvas(like image: CGImage, width: Int, height: Int, opaque: Bool = false) -> CGContext? {
        let alpha = (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
        if isHDR(image), let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) {
            return CGContext(data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0, space: space, bitmapInfo: alpha | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: alpha)
    }
    /// The source's metadata for writing through ImageIO (used for HDR output, where rewriting the file with
    /// ExifTool would drop the gain map), with orientation and pixel dimensions describing the new pixels.
    static func metadataForReencode(_ input: URL, page: Int, width: Int, height: Int) -> CGImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let original = CGImageSourceCopyMetadataAtIndex(source, imageIndex(source, page: page), nil),
              let metadata = CGImageMetadataCreateMutableCopy(original) else { return nil }
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber)
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, width as CFNumber)
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, height as CFNumber)
        return metadata
    }
}
