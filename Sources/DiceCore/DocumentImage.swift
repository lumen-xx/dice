import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Vector inputs share the image pipeline after on-demand rasterization.
public enum DocumentImage {
    public enum Kind { case pdf, svg }
    /// PDF, Illustrator files saved with PDF compatibility (they begin with `%PDF`), SVG and gzip-compressed SVGZ.
    public static func kind(_ url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "svg", "svgz": return .svg
        case "ai": return hasPDFHeader(url) ? .pdf : nil
        default: return nil
        }
    }
    public static func isDocument(_ url: URL) -> Bool { kind(url) != nil }
    static func isPDF(_ url: URL) -> Bool { kind(url) == .pdf }
    static func hasPDFHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1024)).map { String(decoding: $0, as: UTF8.self).contains("%PDF") } ?? false
    }
    /// Why a document-like file can't be opened, for formats macOS can't render.
    static func unsupportedReason(_ url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "ai": return "This Illustrator file was saved without PDF compatibility. Re-save it with “Create PDF Compatible File” turned on."
        case "eps", "ps": return "macOS no longer renders PostScript, so Dice can't open EPS files. Save it as PDF or SVG first."
        default: return nil
        }
    }
    /// SVG source, decompressing SVGZ. Limited to 20 MB either way.
    static func svgData(_ url: URL) throws -> Data {
        guard Engine.fileSize(url) <= 20_000_000, let raw = try? Data(contentsOf: url) else { throw DiceError.message("This SVG could not be read or exceeds 20 MB.") }
        guard raw.starts(with: [0x1f, 0x8b]) else { return raw }
        guard let data = gunzip(raw), data.count <= 20_000_000 else { throw DiceError.message("This SVGZ could not be decompressed or exceeds 20 MB.") }
        return data
    }
    /// Minimal gzip reader: skips the header (RFC 1952) and inflates the raw DEFLATE stream.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]; var i = 10
        if flags & 4 != 0 { guard i + 2 <= bytes.count else { return nil }; i += 2 + Int(bytes[i]) + Int(bytes[i + 1]) << 8 }
        if flags & 8 != 0 { while i < bytes.count && bytes[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < bytes.count && bytes[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < bytes.count - 8 else { return nil }
        return try? (Data(bytes[i..<(bytes.count - 8)]) as NSData).decompressed(using: .zlib) as Data
    }
    static func pdf(_ url: URL) throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else { throw DiceError.message("This PDF could not be read.") }
        guard !document.isEncrypted || document.isUnlocked else { throw DiceError.message("Unlock this PDF before opening it in Dice.") }
        guard document.numberOfPages > 0 else { throw DiceError.message("This PDF has no pages.") }
        return document
    }
    static func dimensions(_ url: URL, page: Int) throws -> (Int, Int, Int) {
        if isPDF(url) {
            let document = try pdf(url)
            guard let selected = document.page(at: page) else { throw DiceError.message("This PDF page does not exist.") }
            let box = selected.getBoxRect(.cropBox)
            let rotated = abs(selected.rotationAngle) % 180 == 90
            // PDF points are 1/72 inch; render at 144 dpi by default.
            let width = (rotated ? box.height : box.width) * 2
            let height = (rotated ? box.width : box.height) * 2
            guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 32768, height <= 32768 else { throw DiceError.message("The PDF page dimensions are invalid or too large.") }
            let w = Int(ceil(width)), h = Int(ceil(height))
            try validate(w, h)
            return (w, h, document.numberOfPages)
        }
        let parser = try SVGHeader(url: url)
        let size = try parser.size()
        try validate(size.0, size.1)
        return (size.0, size.1, 1)
    }
    static func validate(_ w: Int, _ h: Int) throws {
        guard w > 0, h > 0, w <= 32768, h <= 32768 else { throw DiceError.message("The document dimensions are invalid or too large.") }
    }
    static func render(_ url: URL, page: Int, edge: Int) throws -> CGImage {
        let (w, h, _) = try dimensions(url, page: page)
        let scale = Double(edge) / Double(max(w, h))
        let width = max(1, Int((Double(w) * scale).rounded()))
        let height = max(1, Int((Double(h) * scale).rounded()))
        guard width * height <= 80_000_000 else { throw DiceError.message("Choose a smaller output size; this document exceeds 80 megapixels.") }
        if isPDF(url) {
            let document = try pdf(url)
            guard let selected = document.page(at: page), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DiceError.message("Could not render this PDF page.") }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
            let box = selected.getBoxRect(.cropBox)
            let rotated = abs(selected.rotationAngle) % 180 == 90
            let logical = CGRect(x: 0, y: 0, width: rotated ? box.height : box.width, height: rotated ? box.width : box.height)
            // Core Graphics' fitting transform doesn't enlarge pages; apply the raster scale explicitly.
            context.scaleBy(x: CGFloat(width) / logical.width, y: CGFloat(height) / logical.height)
            context.concatenate(selected.getDrawingTransform(.cropBox, rect: logical, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(selected)
            guard let image = context.makeImage() else { throw DiceError.message("Could not render this PDF page.") }
            return image
        }
        let renderer = Engine.toolsDirectory.appendingPathComponent("resvg")
        guard FileManager.default.fileExists(atPath: renderer.path) else { throw DiceError.message("The bundled SVG renderer is missing.") }
        let data = try Engine.run(renderer, ["--width", String(width), "--height", String(height), url.path, "-c"])
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DiceError.message("Could not render this SVG.") }
        return image
    }
}

private final class SVGHeader: NSObject, XMLParserDelegate {
    var attributes: [String: String]?
    init(url: URL) throws {
        super.init()
        let parser = XMLParser(data: try DocumentImage.svgData(url))
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        _ = parser.parse()
        guard attributes != nil else { throw DiceError.message("This file has no SVG root element.") }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes dict: [String: String]) {
        if attributes == nil {
            if name.split(separator: ":").last == "svg" { attributes = dict }
            parser.abortParsing()
        }
    }
    func size() throws -> (Int, Int) {
        let a = attributes ?? [:]
        let viewBox = (a["viewBox"] ?? "").split { $0.isWhitespace || $0 == "," }.compactMap { Double($0) }
        let vw = viewBox.count == 4 ? viewBox[2] : 0, vh = viewBox.count == 4 ? viewBox[3] : 0
        var w = length(a["width"]), h = length(a["height"])
        if w == nil && h == nil { w = vw > 0 ? vw : 100; h = vh > 0 ? vh : 100 }
        else if w == nil { w = vw > 0 && vh > 0 ? h! * vw / vh : 100 }
        else if h == nil { h = vw > 0 && vh > 0 ? w! * vh / vw : 100 }
        guard let w, let h, w.isFinite, h.isFinite, w > 0, h > 0, w <= 32768, h <= 32768 else { throw DiceError.message("The SVG dimensions are invalid or too large.") }
        return (Int(ceil(w)), Int(ceil(h)))
    }
    private func length(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let units: [(String, Double)] = [("px", 1), ("pt", 96/72), ("pc", 16), ("in", 96), ("cm", 96/2.54), ("mm", 96/25.4)]
        for (unit, scale) in units where value.hasSuffix(unit) { return Double(value.dropLast(unit.count)).map { $0 * scale } }
        return Double(value)
    }
}
