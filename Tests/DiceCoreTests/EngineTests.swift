import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import PDFKit
import DiceCore


private var failures = 0
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { if !value { failures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { XCTAssertTrue(!value, file:file,line:line) }
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) { if lhs != rhs { failures += 1; print("FAIL \(file):\(line): \(lhs) != \(rhs)") } }
func XCTAssertLessThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) { XCTAssertTrue(lhs < rhs,file:file,line:line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { XCTAssertTrue(value == nil,file:file,line:line) }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try value(); XCTAssertTrue(false,file:file,line:line) } catch {} }
@discardableResult func runExif(_ args: [String]) throws -> Data {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    let base = Engine.toolsDirectory.appendingPathComponent("exiftool")
    process.arguments = ["-I",base.appendingPathComponent("lib").path,base.appendingPathComponent("exiftool").path,"-config",""] + args
    let pipe = Pipe(); process.standardOutput = pipe
    try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw DiceError.message("Metadata fixture failed") }; return data
}

final class EngineTests {
    var directory: URL!
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dice-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func fixture(name: String = "image", width: Int = 120, height: Int = 80, format: String = UTType.jpeg.identifier, quality: Double = 1) throws -> URL {
        let url = directory.appendingPathComponent(name + "." + (UTType(format)?.preferredFilenameExtension ?? "img"))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        var rng: UInt32 = 12345
        for i in stride(from: 0, to: data.count, by: 4) {
            rng = 1664525 &* rng &+ 1013904223
            data[i] = UInt8(truncatingIfNeeded: rng); data[i+1] = UInt8(truncatingIfNeeded: rng >> 8); data[i+2] = UInt8(truncatingIfNeeded: rng >> 16); data[i+3] = 255
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, format as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest)); return url
    }
    func dimensions(_ url: URL) -> (Int,Int) {
        let source = CGImageSourceCreateWithURL(url as CFURL,nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(source,0,nil)! as NSDictionary
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }
    func testResizePreservesAspectRatioAndOriginal() throws {
        let input = try fixture(name: "unicode ü ; $ image")
        let original = try Data(contentsOf: input)
        var options = Options(); options.format = .png; options.resize = .edge; options.edge = 60
        let result = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(dimensions(result.url).0,60); XCTAssertEqual(dimensions(result.url).1,40)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
    func testResizeValidationAndNoUpscaling() throws {
        var options = Options(); options.resize = .edge; options.edge = 500
        XCTAssertEqual(try options.longestEdge(width:120,height:80),120)
        options.resize = .fit; options.width = 90; options.height = 30
        XCTAssertEqual(try options.longestEdge(width:120,height:80),45)
        options.resize = .percent; options.percent = 0
        XCTAssertThrowsError(try options.longestEdge(width:120,height:80))
    }
    func testJPEGCompressionReducesFileSize() throws {
        let input = try fixture(width:600,height:400)
        var high = Options(); high.format = .jpeg; high.quality = 0.95
        var low = high; low.quality = 0.25
        let larger = try Engine.convert(input, options: high, directory: directory)
        let smaller = try Engine.convert(input, options: low, directory: directory)
        XCTAssertLessThan(smaller.bytes,larger.bytes)
        XCTAssertEqual(dimensions(smaller.url).0,600)
    }
    func testMetadataViewerAndLosslessStripping() throws {
        let input = try fixture()
        _ = try runExif(["-overwrite_original", "-Artist=Dice test artist", "-GPSLatitude=52.5", "-GPSLatitudeRef=N", "-GPSLongitude=13.4", "-GPSLongitudeRef=E", input.path])
        let before = try Engine.inspect(input)
        XCTAssertEqual(before.value("Artist"),"Dice test artist"); XCTAssertTrue(before.hasGPS)
        let originalPixels = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(input as CFURL,nil)!,0,nil)!.dataProvider!.data! as Data
        var options = Options(); options.metadataOnly = true
        let result = try Engine.convert(input, options: options, directory: directory)
        let after = try Engine.inspect(result.url)
        XCTAssertNil(after.value("Artist")); XCTAssertFalse(after.hasGPS)
        let strippedPixels = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(result.url as CFURL,nil)!,0,nil)!.dataProvider!.data! as Data
        XCTAssertEqual(originalPixels,strippedPixels)
        XCTAssertEqual(try Engine.inspect(input).value("Artist"),"Dice test artist")
    }
    func testOrientationAppliedBeforeStripping() throws {
        let input = try fixture(width:120,height:80)
        _ = try runExif(["-overwrite_original", "-Orientation#=6", input.path])
        let before = try Engine.inspect(input)
        XCTAssertEqual(before.width,80); XCTAssertEqual(before.height,120)
        var options = Options(); options.format = .png
        let result = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(dimensions(result.url).0,80); XCTAssertEqual(dimensions(result.url).1,120)
    }
    func testWebPToolWorksWithBundledLibraries() throws {
        let input = try fixture(format: UTType.png.identifier)
        var options = Options(); options.format = .webp
        let result = try Engine.convert(input, options: options, directory: directory)
        let info = try Engine.inspect(result.url)
        XCTAssertEqual(info.width,120); XCTAssertEqual(info.value("FileType"),"WEBP")
    }
    func testPreserveMetadata() throws {
        let input = try fixture()
        _ = try runExif(["-overwrite_original", "-Artist=Keep me", input.path])
        var options = Options(); options.format = .jpeg; options.stripMetadata = false
        let result = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(try Engine.inspect(result.url).value("Artist"),"Keep me")
    }
    func testHEICAndLosslessWebP() throws {
        let input = try fixture(format: UTType.png.identifier)
        var options = Options(); options.format = .heic
        let heic = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(try Engine.inspect(heic.url).width, 120)
        options.format = .webp; options.webpLossless = true
        let webp = try Engine.convert(input, options: options, directory: directory)
        let properties = try Engine.inspect(webp.url)
        XCTAssertEqual(properties.width,120); XCTAssertEqual(properties.height,80)
        options.format = .original
        let originalWebP = try Engine.convert(webp.url, options: options, directory: directory)
        XCTAssertTrue(try Engine.inspect(originalWebP.url).value("FileType")?.hasPrefix("WEBP") == true)
    }
    func testTIFFMetadataOnly() throws {
        let input = try fixture(format: UTType.bmp.identifier)
        let before = try Data(contentsOf: input)
        var options = Options(); options.metadataOnly = true
        XCTAssertThrowsError(try Engine.convert(input, options: options, directory: directory))
        XCTAssertEqual(try Data(contentsOf: input), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [input.lastPathComponent])
    }
    func testImageSearchAcrossMetadataAndText() throws {
        let input = try fixture(name: "Photo café", width: 120, height: 80)
        _ = try runExif(["-overwrite_original", "-Artist=Quiet Atlas", "-Model=Test Camera", input.path])
        let info = try Engine.inspect(input)
        let text = ImageSearch.text(filename: input.lastPathComponent, path: input.path, info: info, recognizedText: "Moon Lantern")
        XCTAssertTrue(ImageSearch.matches("CAFE",text:text))
        XCTAssertTrue(ImageSearch.matches("Artist atlas",text:text))
        XCTAssertTrue(ImageSearch.matches("camera lantern",text:text))
        XCTAssertTrue(ImageSearch.matches("120×80",text:text))
        XCTAssertTrue(ImageSearch.matches("moon",text:text))
        XCTAssertFalse(ImageSearch.matches("atlas absent",text:text))
        XCTAssertTrue(ImageSearch.matches("",text:text))
    }
    func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }
    func testSVGRenderingAndTransparency() throws {
        let input = directory.appendingPathComponent("vector ü.svg")
        let data = Data("<svg xmlns='http://www.w3.org/2000/svg' width='120' height='80'><rect x='20' y='20' width='40' height='40' fill='#ff0000'/></svg>".utf8)
        try data.write(to: input)
        let info = try Engine.inspect(input)
        XCTAssertEqual(info.width, 120); XCTAssertEqual(info.height, 80)
        let output = try Engine.convert(input, options: Options(), directory: directory)
        XCTAssertEqual(output.url.pathExtension, "png")
        let image = try Engine.previewImage(output.url, maxPixelSize: 120)
        XCTAssertEqual(rgba(image, x: 0, y: 0)[3], 0)
        XCTAssertTrue(rgba(image, x: 40, y: 40)[0] > 240)
        var options = Options(); options.format = .jpeg; options.resize = .edge; options.edge = 60
        let jpeg = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(dimensions(jpeg.url).0, 60); XCTAssertEqual(dimensions(jpeg.url).1, 40)
        let flattened = try Engine.previewImage(jpeg.url, maxPixelSize: 60)
        XCTAssertTrue(rgba(flattened, x: 0, y: 0)[0] > 240)
        XCTAssertEqual(try Data(contentsOf: input), data)
        options.metadataOnly = true
        XCTAssertThrowsError(try Engine.convert(input, options: options, directory: directory))
    }
    func testSVGViewBoxAndInvalidInput() throws {
        let input = directory.appendingPathComponent("viewbox.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 150'><circle cx='150' cy='75' r='50' fill='blue'/></svg>".utf8).write(to: input)
        let output = try Engine.convert(input, options: Options(), directory: directory)
        XCTAssertEqual(dimensions(output.url).0, 300); XCTAssertEqual(dimensions(output.url).1, 150)
        try Data("<html/>".utf8).write(to: input)
        XCTAssertThrowsError(try Engine.inspect(input))
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='999999999' height='999999999'/>".utf8).write(to: input)
        XCTAssertThrowsError(try Engine.inspect(input))
    }
    func pdfFixture() throws -> URL {
        let url = directory.appendingPathComponent("two pages.pdf")
        var box = CGRect(x: 0, y: 0, width: 100, height: 60)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
            context.beginPDFPage(nil); context.setFillColor(color); context.fill(box); context.endPDFPage()
        }
        context.closePDF()
        return url
    }
    func testPDFAllPagesAndRotation() throws {
        let input = try pdfFixture()
        let original = try Data(contentsOf: input)
        XCTAssertEqual(try Engine.pageCount(input), 2)
        let first = try Engine.convert(input, options: Options(), directory: directory, page: 1)
        let second = try Engine.convert(input, options: Options(), directory: directory, page: 2)
        XCTAssertTrue(first.url.lastPathComponent.contains("page-1")); XCTAssertTrue(second.url.lastPathComponent.contains("page-2"))
        XCTAssertEqual(dimensions(first.url).0, 200); XCTAssertEqual(dimensions(first.url).1, 120)
        XCTAssertTrue(rgba(try Engine.previewImage(first.url, maxPixelSize: 200), x: 50, y: 50)[0] > 240)
        XCTAssertTrue(rgba(try Engine.previewImage(second.url, maxPixelSize: 200), x: 50, y: 50)[2] > 240)
        XCTAssertTrue(rgba(try Engine.previewImage(first.url, maxPixelSize: 200), x: 10, y: 10)[1] < 180)
        XCTAssertTrue(rgba(try Engine.previewImage(second.url, maxPixelSize: 200), x: 190, y: 110)[0] < 180)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertThrowsError(try Engine.convert(input, options: Options(), directory: directory, page: 3))
        let pdf = PDFDocument(url: input)!; pdf.page(at: 1)!.rotation = 90; XCTAssertTrue(pdf.write(to: input))
        let rotated = try Engine.convert(input, options: Options(), directory: directory, page: 2)
        XCTAssertEqual(dimensions(rotated.url).0, 120); XCTAssertEqual(dimensions(rotated.url).1, 200)
        var options = Options(); options.metadataOnly = true
        XCTAssertThrowsError(try Engine.convert(input, options: options, directory: directory))
    }
    func testAdditionalStillFormats() throws {
        let input = try fixture(format: UTType.png.identifier)
        for format in [OutputFormat.gif, .bmp, .tiff, .avif] {
            if !Engine.canEncode(format) { print("SKIP encoder unavailable: \(format.rawValue)"); continue }
            var options = Options(); options.format = format
            let output = try Engine.convert(input, options: options, directory: directory)
            XCTAssertEqual(dimensions(output.url).0, 120); XCTAssertEqual(dimensions(output.url).1, 80)
            XCTAssertEqual(try Engine.inspect(output.url).type, format.type)
            options.format = .png
            let roundTrip = try Engine.convert(output.url, options: options, directory: directory)
            XCTAssertEqual(dimensions(roundTrip.url).0, 120)
        }
    }
    func testGIFAndTIFFFrameExtraction() throws {
        let red = directory.appendingPathComponent("red.svg"), blue = directory.appendingPathComponent("blue.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><path d='M0 0h80v60H0z' fill='red'/></svg>".utf8).write(to: red)
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><path d='M0 0h80v60H0z' fill='blue'/></svg>".utf8).write(to: blue)
        let images = [try Engine.previewImage(red, maxPixelSize: 80), try Engine.previewImage(blue, maxPixelSize: 80)]
        for format in [OutputFormat.tiff] {
            let input = directory.appendingPathComponent("multiple." + format.ext)
            let dest = CGImageDestinationCreateWithURL(input as CFURL, format.type as CFString, 2, nil)!
            for image in images { CGImageDestinationAddImage(dest, image, nil) }
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            XCTAssertEqual(try Engine.pageCount(input), 2)
            var options = Options(); options.format = .png
            let first = try Engine.convert(input, options: options, directory: directory, page: 1)
            let second = try Engine.convert(input, options: options, directory: directory, page: 2)
            XCTAssertTrue(rgba(try Engine.previewImage(first.url, maxPixelSize: 80), x: 20, y: 20)[0] > 240)
            XCTAssertTrue(rgba(try Engine.previewImage(second.url, maxPixelSize: 80), x: 20, y: 20)[2] > 240)
            XCTAssertFalse(first.url == second.url)
        }
    }
    func testAnimatedGIFAndTransparencyFill() throws {
        let red = directory.appendingPathComponent("a.svg"), blue = directory.appendingPathComponent("b.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><path d='M0 0h80v60H0z' fill='red'/></svg>".utf8).write(to: red)
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><path d='M0 0h80v60H0z' fill='blue'/></svg>".utf8).write(to: blue)
        let images = [try Engine.previewImage(red, maxPixelSize: 80), try Engine.previewImage(blue, maxPixelSize: 80)]
        let input = directory.appendingPathComponent("anim.gif")
        let dest = CGImageDestinationCreateWithURL(input as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        for image in images { CGImageDestinationAddImage(dest, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        XCTAssertEqual(try Engine.pageCount(input), 1)
        var options = Options(); options.format = .gif
        let kept = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(CGImageSourceGetCount(CGImageSourceCreateWithURL(kept.url as CFURL, nil)!), 2)
        options.format = .png; options.keepAnimation = false
        let folder = try Engine.convert(input, options: options, directory: directory)
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).sorted(), ["frame-0001.png", "frame-0002.png"])
        XCTAssertTrue(rgba(try Engine.previewImage(folder.previewURL!, maxPixelSize: 80), x: 20, y: 20)[0] > 240)
        let copy = try Engine.saveCopy(folder, beside: input)
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("anim-frames-dice") && !copy.lastPathComponent.contains("."))
        options.framesAsFolder = false
        let first = try Engine.convert(input, options: options, directory: directory)
        XCTAssertFalse(first.isFolder)
        // Transparent pixels take the chosen fill colour in formats without alpha.
        let clear = directory.appendingPathComponent("clear.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'></svg>".utf8).write(to: clear)
        options = Options(); options.format = .jpeg; options.flattenColor = [0, 1, 0]
        let jpeg = try Engine.convert(clear, options: options, directory: directory)
        let pixel = rgba(try Engine.previewImage(jpeg.url, maxPixelSize: 40), x: 20, y: 20)
        XCTAssertTrue(pixel[1] > 200 && pixel[0] < 60 && pixel[2] < 60)
        options.fileSuffix = "-small"
        XCTAssertTrue(try Engine.convert(clear, options: options, directory: directory).url.lastPathComponent.contains("-small"))
    }
    func testResizeOnlySkipsSmallAndPreservesMetadata() throws {
        let input = try fixture(format: UTType.png.identifier)
        _ = try runExif(["-overwrite_original", "-Artist=Keep for resize", input.path])
        let original = try Data(contentsOf: input)
        var options = Options(); options.resize = .edge; options.edge = 200
        options.format = .jpeg; options.quality = 0.1; options.stripMetadata = true
        XCTAssertNil(try Engine.resize(input, options: options, directory: directory))
        options.edge = 60
        let output = try Engine.resize(input, options: options, directory: directory)!
        XCTAssertEqual(output.url.pathExtension, "png")
        XCTAssertEqual(dimensions(output.url).0, 60); XCTAssertEqual(dimensions(output.url).1, 40)
        XCTAssertEqual(try Engine.inspect(output.url).value("Artist"), "Keep for resize")
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
    func testSaveCopiesBesideOriginal() throws {
        let input = try fixture(format: UTType.png.identifier)
        let original = try Data(contentsOf: input)
        let temporary = directory.appendingPathComponent("processing")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let result = try Engine.convert(input, options: Options(), directory: temporary)
        let first = try Engine.saveCopy(result, beside: input)
        let second = try Engine.saveCopy(result, beside: input)
        XCTAssertEqual(first.deletingLastPathComponent(), input.deletingLastPathComponent())
        XCTAssertFalse(first == second); XCTAssertFalse(first == input)
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: result.url))
        let export = directory.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let configured = try Engine.saveCopy(result, beside: input, directory: export)
        XCTAssertEqual(configured.deletingLastPathComponent().path, export.path)
        XCTAssertEqual(try Data(contentsOf: configured), try Data(contentsOf: result.url))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
    func testReplaceOriginalAndLegacyOptions() throws {
        let input = try fixture(name: "photo", format: UTType.png.identifier)
        let temporary = directory.appendingPathComponent("processing")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        var options = Options(); options.format = .jpeg
        let result = try Engine.convert(input, options: options, directory: temporary)
        let replaced = try Engine.replaceOriginal(input, with: result)
        XCTAssertEqual(replaced.lastPathComponent, "photo.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: input.path))
        XCTAssertEqual(try Data(contentsOf: replaced), try Data(contentsOf: result.url))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".dice-") }.count, 0)
        let legacy = Data(#"{"format":"PNG","resize":"Longest edge","edge":800,"percent":50,"width":1,"height":1,"quality":0.5,"stripMetadata":false,"metadataOnly":false,"webpLossless":false}"#.utf8)
        let decoded = try JSONDecoder().decode(Options.self, from: legacy)
        XCTAssertEqual(decoded.edge, 800); XCTAssertFalse(decoded.replaceOriginals); XCTAssertFalse(decoded.resizeOnly)
    }
    func testPreviewBudgetAndPageKeys() throws {
        let input = try fixture(width: 120, height: 80, format: UTType.png.identifier)
        let image = try Engine.previewImage(input, maxPixelSize: 120)
        let cache = PreviewCache(limit: image.bytesPerRow * image.height * 2)
        let first = PreviewCache.key(input, page: 1), second = PreviewCache.key(input, page: 2), third = PreviewCache.key(input, page: 3)
        cache.insert(image, for: first); cache.insert(image, for: second)
        XCTAssertTrue(cache.image(for: first) != nil)
        cache.insert(image, for: third)
        XCTAssertNil(cache.image(for: second)); XCTAssertTrue(cache.image(for: first) != nil)
        XCTAssertTrue(cache.statistics.bytes <= cache.limit)
        cache.remove(first); XCTAssertNil(cache.image(for: first))
        cache.clear(); XCTAssertEqual(cache.statistics.bytes, 0)
    }
    func testPreviewPerformance() throws {
        let photo = try fixture(width: 2400, height: 1600)
        let cache = PreviewCache()
        let key = PreviewCache.key(photo)
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<8 { _ = try Engine.previewImage(photo, maxPixelSize: 1200) }
        let cold = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / 8
        cache.insert(try Engine.previewImage(photo, maxPixelSize: 1200), for: key)
        let warmStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<1000 { XCTAssertTrue(cache.image(for: key) != nil) }
        let warm = Double(DispatchTime.now().uptimeNanoseconds - warmStart) / 1_000_000 / 1000
        print(String(format: "PERF JPEG preview: decode %.3f ms; cached retrieval %.4f ms; %.2f MiB cached", cold, warm, Double(cache.statistics.bytes) / 1048576))
        XCTAssertEqual(cache.statistics.hits, 1000)
        XCTAssertTrue(cache.statistics.bytes <= cache.limit)
    }
    func testCollisionSafeNames() throws {
        let first = directory.appendingPathComponent("photo-dice.jpg")
        try Data().write(to: first)
        XCTAssertEqual(Engine.uniqueURL(in: directory,stem:"photo-dice",ext:"jpg").lastPathComponent,"photo-dice-2.jpg")
    }
    func image(_ size: Int, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!, alpha: Double = 1) -> CGImage {
        let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(colorSpace: space, components: [0, 1, 0, alpha])!); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return c.makeImage()!
    }
    func write(_ images: [CGImage], to url: URL, type: UTType) {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil)!
        for image in images { CGImageDestinationAddImage(dest, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
    func testBMPWithKeptMetadata() throws {
        let input = try fixture(format: UTType.png.identifier)
        _ = try runExif(["-overwrite_original", "-Artist=Kept", input.path])
        var options = Options(); options.format = .bmp; options.stripMetadata = false
        let output = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(output.url.pathExtension, "bmp"); XCTAssertEqual(dimensions(output.url).0, 120)
        XCTAssertTrue(output.note?.contains("isn't copied into BMP") == true)
    }
    func testMultiSizeIconsAreOneImage() throws {
        let input = directory.appendingPathComponent("app.ico")
        write([image(16), image(48), image(32)], to: input, type: .ico)
        let info = try Engine.inspect(input)
        XCTAssertEqual(info.frames, 1); XCTAssertEqual(info.width, 48)
        var options = Options(); options.format = .png
        let output = try Engine.convert(input, options: options, directory: directory)
        XCTAssertFalse(output.isFolder); XCTAssertEqual(dimensions(output.url).0, 48)
        XCTAssertEqual(output.url.pathExtension, "png")
        // Same as original now writes ICO again, rebuilt from the largest size.
        let same = try Engine.convert(input, options: Options(), directory: directory)
        XCTAssertEqual(same.url.pathExtension, "ico"); XCTAssertNil(same.note)
    }
    func testWebPTemporaryKeepsOtherResults() throws {
        let input = try fixture(name: "photo", format: UTType.png.identifier)
        let processing = directory.appendingPathComponent("processing")
        try FileManager.default.createDirectory(at: processing, withIntermediateDirectories: true)
        let other = processing.appendingPathComponent("photo-dice.png")
        try Data("earlier result".utf8).write(to: other)
        var options = Options(); options.format = .webp
        let output = try Engine.convert(input, options: options, directory: processing)
        XCTAssertEqual(output.url.lastPathComponent, "photo-dice.webp")
        XCTAssertEqual(try Data(contentsOf: other), Data("earlier result".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: processing.path).sorted(), ["photo-dice.png", "photo-dice.webp"])
    }
    func testVectorsRenderLargerThanIntrinsicSize() throws {
        let input = directory.appendingPathComponent("icon.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='16'><rect width='24' height='16' fill='red'/></svg>".utf8).write(to: input)
        var options = Options(); options.resize = .edge; options.edge = 480
        let edge = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(dimensions(edge.url).0, 480); XCTAssertEqual(dimensions(edge.url).1, 320)
        options.resize = .fit; options.width = 300; options.height = 100
        let fit = try Engine.convert(input, options: options, directory: directory)
        XCTAssertEqual(dimensions(fit.url).0, 150); XCTAssertEqual(dimensions(fit.url).1, 100)
        let pdf = try pdfFixture()
        options.resize = .edge; options.edge = 1000
        XCTAssertEqual(dimensions(try Engine.convert(pdf, options: options, directory: directory).url).0, 1000)
        // Raster images still never grow.
        let raster = try fixture(format: UTType.png.identifier)
        XCTAssertEqual(dimensions(try Engine.convert(raster, options: options, directory: directory).url).0, 120)
    }
    func testSameAsOriginalFallbacksAndQuality() throws {
        func match(_ type: String) -> String { let m = OutputFormat.matching(inputType: type); return m.format.rawValue + (m.exact ? "" : "*") }
        XCTAssertEqual(match(UTType.jpeg.identifier), "JPEG"); XCTAssertEqual(match("public.heif"), "HEIC*")
        XCTAssertEqual(match("public.heics"), "HEIC*"); XCTAssertEqual(match("public.avis"), "AVIF*")
        XCTAssertEqual(match("com.adobe.raw-image"), "JPEG*"); XCTAssertEqual(match("com.sony.arw-raw-image"), "JPEG*")
        XCTAssertEqual(match("public.jpeg-xl"), "JPEG*"); XCTAssertEqual(match("com.adobe.photoshop-image"), "PNG*")
        XCTAssertEqual(match(UTType.pdf.identifier), "PNG*")
        XCTAssertFalse(OutputFormat.original.usesQuality(forInputType: UTType.png.identifier))
        XCTAssertFalse(OutputFormat.original.usesQuality(forInputType: UTType.svg.identifier))
        XCTAssertTrue(OutputFormat.original.usesQuality(forInputType: "com.adobe.raw-image"))
        XCTAssertTrue(OutputFormat.jpeg.usesQuality(forInputType: UTType.png.identifier))
        XCTAssertFalse(OutputFormat.png.usesQuality(forInputType: UTType.jpeg.identifier))
        // A format Dice reads but can't write converts to its fallback, with a note.
        let input = directory.appendingPathComponent("photo.jp2")
        write([image(40)], to: input, type: UTType("public.jpeg-2000")!)
        let output = try Engine.convert(input, options: Options(), directory: directory)
        XCTAssertEqual(output.url.pathExtension, "jpg"); XCTAssertTrue(output.note?.contains("Saved as JPEG") == true)
    }
    func testSessionChoicesReset() throws {
        var options = Options(); options.metadataOnly = true; options.resizeOnly = true; options.webpLossless = true; options.quality = 0.4
        options.resetSessionChoices()
        XCTAssertFalse(options.metadataOnly); XCTAssertFalse(options.resizeOnly); XCTAssertFalse(options.webpLossless)
        XCTAssertEqual(options.quality, 0.4)
    }
    func testPagesReuseFileMetadata() throws {
        let input = try pdfFixture()
        let first = try Engine.inspect(input, page: 1)
        let tools = ProcessInfo.processInfo.environment["DICE_TOOLS"]
        setenv("DICE_TOOLS", directory.appendingPathComponent("no-tools").path, 1)
        defer { if let tools { setenv("DICE_TOOLS", tools, 1) } else { unsetenv("DICE_TOOLS") } }
        // With ExifTool unreachable, page 2 can only succeed by reusing page 1's metadata.
        XCTAssertThrowsError(try Engine.inspect(input, page: 2))
        let second = try Engine.inspect(input, page: 2, reusing: first)
        XCTAssertEqual(second.value("Page"), "2 of 2")
        XCTAssertEqual(second.rows.filter { $0.group != "Dice" }.map(\.id), first.rows.filter { $0.group != "Dice" }.map(\.id))
        XCTAssertEqual(second.rows.filter { $0.name == "Page" }.count, 1)
    }
    func testFoldersExpandToImages() throws {
        let folder = directory.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("day 2"), withIntermediateDirectories: true)
        write([image(8)], to: folder.appendingPathComponent("b.png"), type: .png)
        write([image(8)], to: folder.appendingPathComponent("day 2/a.jpg"), type: .jpeg)
        write([image(8)], to: folder.appendingPathComponent(".hidden.png"), type: .png)
        try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'/>".utf8).write(to: folder.appendingPathComponent("c.svg"))
        let loose = directory.appendingPathComponent("loose.txt"); try Data().write(to: loose)
        let all = ImageFiles.expand([folder, loose])
        let base = folder.resolvingSymlinksInPath().path + "/"
        XCTAssertEqual(all.urls.map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "") }, ["b.png", "c.svg", "day 2/a.jpg", loose.resolvingSymlinksInPath().path])
        XCTAssertFalse(all.truncated)
        let limited = ImageFiles.expand([folder], limit: 2)
        XCTAssertEqual(limited.urls.count, 2); XCTAssertTrue(limited.truncated)
    }
    func testToolTimeout() throws {
        let start = Date()
        XCTAssertThrowsError(try Engine.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 0.5))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        XCTAssertEqual(try Engine.run(URL(fileURLWithPath: "/bin/echo"), ["ok"], timeout: 5), Data("ok\n".utf8))
    }
    func testFlattenKeepsWideGamut() throws {
        let input = directory.appendingPathComponent("p3.png")
        write([image(20, space: CGColorSpace(name: CGColorSpace.displayP3)!, alpha: 0.5)], to: input, type: .png)
        var options = Options(); options.format = .jpeg; options.quality = 1
        let output = try Engine.convert(input, options: options, directory: directory)
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(output.url as CFURL, nil)!, 0, nil) as! [String: Any]
        XCTAssertEqual(props[kCGImagePropertyProfileName as String] as? String, "Display P3")
    }
    func pixels(_ url: URL) -> [UInt8] {
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
    func testTargetFileSize() throws {
        let input = try fixture(width: 800, height: 600, format: UTType.png.identifier)
        var options = Options(); options.format = .jpeg; options.useTargetSize = true; options.targetKB = 150
        let fitted = try Engine.convert(input, options: options, directory: directory)
        XCTAssertTrue(fitted.bytes <= 150_000); XCTAssertTrue(fitted.bytes > 75_000)
        XCTAssertEqual(dimensions(fitted.url).0, 800); XCTAssertTrue(fitted.note?.contains("Fits 150 KB at quality") == true)
        // Too small for any quality at full size: the image shrinks until it fits.
        options.targetKB = 12
        let shrunk = try Engine.convert(input, options: options, directory: directory)
        XCTAssertTrue(shrunk.bytes <= 12_000); XCTAssertLessThan(dimensions(shrunk.url).0, 800)
        XCTAssertTrue(shrunk.note?.contains("reduced to") == true)
        // Kept metadata still fits inside the budget.
        _ = try runExif(["-overwrite_original", "-XMP-dc:Description=" + String(repeating: "metadata ", count: 5500), input.path])
        options.targetKB = 150; options.stripMetadata = false
        let withTags = try Engine.convert(input, options: options, directory: directory)
        XCTAssertTrue(withTags.bytes <= 150_000)
        XCTAssertTrue(try Engine.inspect(withTags.url).value("Description")?.hasPrefix("metadata") == true)
        // Lossless outputs ignore the target, and say so.
        options.format = .png; options.stripMetadata = true
        XCTAssertTrue(try Engine.convert(input, options: options, directory: directory).note?.contains("target size wasn't applied") == true)
    }
    func testPNGOptimisationIsLossless() throws {
        let input = directory.appendingPathComponent("flat.png")
        write([image(400)], to: input, type: .png)
        var options = Options(); options.format = .png; options.optimizePNG = false; options.keepSmallerOriginal = false
        let plain = try Engine.convert(input, options: options, directory: directory)
        options.optimizePNG = true
        let optimised = try Engine.convert(input, options: options, directory: directory)
        XCTAssertLessThan(optimised.bytes, plain.bytes)
        XCTAssertTrue(pixels(optimised.url) == pixels(plain.url))
    }
    func testKeepSmallerOriginal() throws {
        let input = try fixture(width: 300, height: 200)
        let small = try Engine.convert(input, options: { var o = Options(); o.format = .jpeg; o.quality = 0.3; return o }(), directory: directory)
        _ = try runExif(["-overwrite_original", "-GPSLatitude=52.5", "-GPSLatitudeRef=N", "-Artist=Kept", small.url.path])
        var options = Options(); options.quality = 1; options.stripMetadata = false
        let kept = try Engine.convert(small.url, options: options, directory: directory)
        XCTAssertEqual(try Data(contentsOf: kept.url), try Data(contentsOf: small.url))
        XCTAssertTrue(kept.note?.hasPrefix("Kept the original's pixels") == true)
        options.stripMetadata = true
        let stripped = try Engine.convert(small.url, options: options, directory: directory)
        XCTAssertFalse(try Engine.inspect(stripped.url).hasGPS); XCTAssertNil(try Engine.inspect(stripped.url).value("Artist"))
        XCTAssertTrue(stripped.bytes < kept.bytes + 100)
        // A different format, or the setting off, keeps the re-encoded file.
        options.keepSmallerOriginal = false
        XCTAssertTrue(try Engine.convert(small.url, options: options, directory: directory).bytes > small.bytes)
        options.keepSmallerOriginal = true; options.format = .png
        XCTAssertEqual(try Engine.convert(small.url, options: options, directory: directory).url.pathExtension, "png")
    }
    func testSVGZIllustratorAndPostScript() throws {
        let svg = directory.appendingPathComponent("packed.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='90' height='30'><rect width='90' height='30' fill='red'/></svg>".utf8).write(to: svg)
        let gzip = Process(); gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); gzip.arguments = ["-n", svg.path]
        try gzip.run(); gzip.waitUntilExit()
        let svgz = directory.appendingPathComponent("packed.svgz")
        try FileManager.default.moveItem(at: directory.appendingPathComponent("packed.svg.gz"), to: svgz)
        XCTAssertEqual(DocumentImage.kind(svgz), .svg)
        var options = Options(); options.format = .png
        XCTAssertEqual(dimensions(try Engine.convert(svgz, options: options, directory: directory).url).0, 90)
        let ai = directory.appendingPathComponent("logo.ai")
        try FileManager.default.copyItem(at: try pdfFixture(), to: ai)
        XCTAssertEqual(try Engine.pageCount(ai), 2)
        XCTAssertEqual(dimensions(try Engine.convert(ai, options: options, directory: directory).url).0, 200)
        let legacy = directory.appendingPathComponent("legacy.ai"), eps = directory.appendingPathComponent("art.eps")
        try Data("%!PS-Adobe-3.0\n".utf8).write(to: legacy); try Data("%!PS-Adobe-3.0 EPSF-3.0\n".utf8).write(to: eps)
        func message(_ url: URL) -> String { do { _ = try Engine.convert(url, options: options, directory: directory); return "" } catch { return error.localizedDescription } }
        XCTAssertTrue(message(legacy).contains("PDF compatibility")); XCTAssertTrue(message(eps).contains("PostScript"))
    }
    func testIconOutput() throws {
        func sizes(_ url: URL) -> [Int] {
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            return (0..<CGImageSourceGetCount(source)).map { i in
                let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil)! as NSDictionary
                XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, p[kCGImagePropertyPixelHeight] as? Int)
                return p[kCGImagePropertyPixelWidth] as! Int
            }.sorted()
        }
        let wide = try fixture(name: "wide", width: 300, height: 200, format: UTType.png.identifier)
        var options = Options(); options.format = .ico
        let ico = try Engine.convert(wide, options: options, directory: directory)
        XCTAssertEqual(ico.url.pathExtension, "ico"); XCTAssertEqual(sizes(ico.url), [16, 24, 32, 48, 128, 256])
        // Padded, not stretched: the top row of a 300 × 200 image is transparent once squared.
        let largest = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(ico.url as CFURL, nil)!, 0, nil)!
        XCTAssertEqual(largest.width, 256); XCTAssertEqual(rgba(largest, x: 128, y: 2)[3], 0); XCTAssertEqual(rgba(largest, x: 128, y: 128)[3], 255)
        options.format = .icns
        let big = try fixture(name: "big", width: 600, height: 600, format: UTType.png.identifier)
        XCTAssertEqual(sizes(try Engine.convert(big, options: options, directory: directory).url), [16, 32, 128, 256, 512])
        let tiny = try fixture(name: "tiny", width: 10, height: 10, format: UTType.png.identifier)
        XCTAssertEqual(sizes(try Engine.convert(tiny, options: options, directory: directory).url), [16])
    }
    func testPDFOutputAndCombining() throws {
        let photo = try fixture(width: 120, height: 80)
        var options = Options(); options.format = .pdf
        let page = try Engine.convert(photo, options: options, directory: directory)
        XCTAssertEqual(page.url.pathExtension, "pdf")
        let document = CGPDFDocument(page.url as CFURL)!
        XCTAssertEqual(document.numberOfPages, 1)
        XCTAssertEqual(document.page(at: 1)!.getBoxRect(.mediaBox).size, CGSize(width: 120, height: 80))
        let clear = directory.appendingPathComponent("clear.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'><circle cx='20' cy='20' r='10'/></svg>".utf8).write(to: clear)
        XCTAssertEqual(CGPDFDocument(try Engine.convert(clear, options: options, directory: directory).url as CFURL)?.numberOfPages, 1)
        let combined = directory.appendingPathComponent("combined.pdf")
        try Engine.combinePDFs([page.url, try pdfFixture()], to: combined)
        let joined = CGPDFDocument(combined as CFURL)!
        XCTAssertEqual(joined.numberOfPages, 3)
        XCTAssertEqual(joined.page(at: 1)!.getBoxRect(.mediaBox).size, CGSize(width: 120, height: 80))
        XCTAssertEqual(joined.page(at: 3)!.getBoxRect(.mediaBox).size, CGSize(width: 100, height: 60))
        XCTAssertThrowsError(try Engine.combinePDFs([], to: combined))
    }
    func testAnimationOutputs() throws {
        let red = directory.appendingPathComponent("a.svg"), blue = directory.appendingPathComponent("b.svg")
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><path d='M0 0h80v60H0z' fill='red'/></svg>".utf8).write(to: red)
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='80' height='60'><path d='M0 0h80v60H0z' fill='blue'/></svg>".utf8).write(to: blue)
        let input = directory.appendingPathComponent("anim.gif")
        write([try Engine.previewImage(red, maxPixelSize: 80), try Engine.previewImage(blue, maxPixelSize: 80), try Engine.previewImage(red, maxPixelSize: 80)], to: input, type: .gif)
        for (format, ext) in [(OutputFormat.png, "png"), (.webp, "webp"), (.heic, "heics"), (.gif, "gif")] {
            if !Engine.canEncode(format) { print("SKIP encoder unavailable: \(format.rawValue)"); continue }
            var options = Options(); options.format = format; options.resize = .edge; options.edge = 40
            let output = try Engine.convert(input, options: options, directory: directory)
            XCTAssertEqual(output.url.pathExtension, ext); XCTAssertEqual(output.note, "Animation kept (3 frames)")
            guard let source = CGImageSourceCreateWithURL(output.url as CFURL, nil) else { XCTAssertTrue(false); continue }
            XCTAssertEqual(CGImageSourceGetCount(source), 3)
            guard let middle = CGImageSourceCreateImageAtIndex(source, 1, nil) else { XCTAssertTrue(false); continue }
            // The middle frame stays blue, at the resized width.
            XCTAssertEqual(middle.width, 40); XCTAssertTrue(rgba(middle, x: 20, y: 15)[2] > 200)
        }
    }
    func testAVIFAtFullQuality() throws {
        guard Engine.canEncode(.avif) else { print("SKIP encoder unavailable: AVIF"); return }
        var options = Options(); options.format = .avif; options.quality = 1
        XCTAssertEqual(dimensions(try Engine.convert(try fixture(format: UTType.png.identifier), options: options, directory: directory).url).0, 120)
    }
    func testMetadataOnlyMoreFormats() throws {
        for type in [UTType.tiff, .gif, UTType("public.avif")!] {
            if CGImageDestinationCreateWithData(NSMutableData(), type.identifier as CFString, 1, nil) == nil { print("SKIP \(type.identifier)"); continue }
            let input = try fixture(name: "personal", format: type.identifier, quality: 0.9)
            _ = try runExif(["-overwrite_original", "-XMP-dc:Creator=Remove me", input.path])
            XCTAssertTrue(try Engine.inspect(input).value("Creator")?.contains("Remove me") == true)
            var options = Options(); options.metadataOnly = true
            let output = try Engine.convert(input, options: options, directory: directory)
            XCTAssertEqual(output.url.pathExtension, input.pathExtension)
            XCTAssertNil(try Engine.inspect(output.url).value("Creator")); XCTAssertEqual(dimensions(output.url).0, 120)
            XCTAssertTrue(try Engine.inspect(input).value("Creator")?.contains("Remove me") == true)
            try FileManager.default.removeItem(at: input)
        }
    }
    func testGeometryModes() throws {
        func plan(_ w: Int, _ h: Int, vector: Bool = false, _ change: (inout Options) -> Void) throws -> (Int, Int) {
            var o = Options(); change(&o); let g = try o.geometry(width: w, height: h, vector: vector); return (g.width, g.height)
        }
        XCTAssertTrue(try plan(800, 600) { $0.resize = .width; $0.width = 400 } == (400, 300))
        XCTAssertTrue(try plan(800, 600) { $0.resize = .height; $0.height = 300 } == (400, 300))
        XCTAssertTrue(try plan(800, 600) { $0.resize = .width; $0.width = 1600 } == (800, 600))
        XCTAssertTrue(try plan(800, 600) { $0.resize = .width; $0.width = 1600; $0.upscale = true } == (1600, 1200))
        XCTAssertTrue(try plan(2000, 1200) { $0.resize = .fill; $0.width = 1080; $0.height = 1080 } == (1080, 1080))
        XCTAssertTrue(try plan(1600, 900) { $0.resize = .fill; $0.width = 1080; $0.height = 1080 } == (900, 900))
        XCTAssertTrue(try plan(500, 400) { $0.resize = .fill; $0.width = 1080; $0.height = 1080 } == (400, 400))
        XCTAssertTrue(try plan(500, 400) { $0.resize = .fill; $0.width = 1080; $0.height = 1080; $0.upscale = true } == (1080, 1080))
        XCTAssertTrue(try plan(800, 600) { $0.resize = .percent; $0.percent = 200; $0.upscale = true } == (1600, 1200))
        XCTAssertTrue(try plan(80, 60, vector: true) { $0.resize = .percent; $0.percent = 300 } == (240, 180))
        XCTAssertThrowsError(try plan(800, 600) { $0.resize = .percent; $0.percent = 200 })
        XCTAssertTrue(try plan(800, 600) { $0.rotation = 90; $0.resize = .width; $0.width = 300 } == (300, 400))
        XCTAssertTrue(try plan(800, 600) { $0.crop = .square } == (600, 600))
        XCTAssertTrue(try plan(800, 600) { $0.crop = .wide; $0.resize = .edge; $0.edge = 400 } == (400, 225))
        XCTAssertThrowsError(try plan(800, 600) { $0.resize = .width; $0.width = 40000; $0.upscale = true })
        var o = Options(); o.rotation = 180; o.crop = .square
        XCTAssertFalse(try o.geometry(width: 10, height: 10).isIdentity(width: 10, height: 10))
        o.rotation = 0; XCTAssertTrue(try o.geometry(width: 10, height: 10).isIdentity(width: 10, height: 10))
        o.rotation = 90; o.resetSessionChoices(); XCTAssertEqual(o.rotation, 0); XCTAssertEqual(o.crop, .square)
    }
    /// 40 × 20: left half red, right half blue.
    func halves() throws -> URL {
        let url = directory.appendingPathComponent("halves.png")
        let c = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        c.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); c.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        write([c.makeImage()!], to: url, type: .png); return url
    }
    func testRotateFlipAndCrop() throws {
        let input = try halves()
        func out(_ change: (inout Options) -> Void) throws -> CGImage {
            var o = Options(); o.format = .png; change(&o)
            return try Engine.previewImage(try Engine.convert(input, options: o, directory: directory).url, maxPixelSize: 100)
        }
        func red(_ p: [UInt8]) -> Bool { p[0] > 200 && p[2] < 50 }
        func blue(_ p: [UInt8]) -> Bool { p[2] > 200 && p[0] < 50 }
        // Clockwise: the left (red) half ends up on top.
        let cw = try out { $0.rotation = 90 }
        XCTAssertEqual(cw.width, 20); XCTAssertEqual(cw.height, 40)
        XCTAssertTrue(red(rgba(cw, x: 10, y: 5))); XCTAssertTrue(blue(rgba(cw, x: 10, y: 35)))
        let ccw = try out { $0.rotation = 270 }
        XCTAssertTrue(blue(rgba(ccw, x: 10, y: 5))); XCTAssertTrue(red(rgba(ccw, x: 10, y: 35)))
        let half = try out { $0.rotation = 180 }
        XCTAssertTrue(blue(rgba(half, x: 5, y: 10))); XCTAssertTrue(red(rgba(half, x: 35, y: 10)))
        let flipped = try out { $0.flipHorizontal = true }
        XCTAssertTrue(blue(rgba(flipped, x: 5, y: 10))); XCTAssertTrue(red(rgba(flipped, x: 35, y: 10)))
        // Rotate, then flip vertically: red moves from the top to the bottom.
        let both = try out { $0.rotation = 90; $0.flipVertical = true }
        XCTAssertTrue(blue(rgba(both, x: 10, y: 5))); XCTAssertTrue(red(rgba(both, x: 10, y: 35)))
        let square = try out { $0.crop = .square }
        XCTAssertEqual(square.width, 20); XCTAssertEqual(square.height, 20)
        XCTAssertTrue(red(rgba(square, x: 3, y: 10))); XCTAssertTrue(blue(rgba(square, x: 16, y: 10)))
        // Same format and size: keeping the smaller original must not undo the rotation.
        let jpeg = directory.appendingPathComponent("halves.jpg")
        let dest = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, try Engine.previewImage(input, maxPixelSize: 40), [kCGImageDestinationLossyCompressionQuality: 0.3] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        var o = Options(); o.rotation = 180; o.keepSmallerOriginal = true; o.quality = 1
        let kept = try Engine.convert(jpeg, options: o, directory: directory)
        XCTAssertEqual(kept.url.pathExtension, "jpg"); XCTAssertFalse(kept.note?.contains("Kept the original") == true)
        XCTAssertTrue(blue(rgba(try Engine.previewImage(kept.url, maxPixelSize: 100), x: 5, y: 10)))
    }
    func testFillUpscaleScaleSetsAndPDFResolution() throws {
        let photo = try fixture(name: "photo", width: 300, height: 200, format: UTType.png.identifier)
        var o = Options(); o.format = .png; o.resize = .fill; o.width = 100; o.height = 100
        XCTAssertTrue(dimensions(try Engine.convert(photo, options: o, directory: directory).url) == (100, 100))
        o = Options(); o.format = .jpeg; o.resize = .percent; o.percent = 200; o.upscale = true
        XCTAssertTrue(dimensions(try Engine.convert(photo, options: o, directory: directory).url) == (600, 400))
        o = Options(); o.format = .png; o.scaleSet = true
        let set = try Engine.convert(photo, options: o, directory: directory)
        XCTAssertTrue(set.isFolder); XCTAssertEqual(set.url.lastPathComponent, "photo-dice")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: set.url.path).sorted(), ["photo.png", "photo@2x.png", "photo@3x.png"])
        XCTAssertTrue(dimensions(set.url.appendingPathComponent("photo@3x.png")) == (300, 200))
        XCTAssertTrue(dimensions(set.url.appendingPathComponent("photo@2x.png")) == (200, 133))
        XCTAssertTrue(dimensions(set.url.appendingPathComponent("photo.png")) == (100, 67))
        XCTAssertTrue(set.note?.contains("@3x, @2x and @1x") == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".dice-") }.count, 0)
        o.resize = .fill; o.width = 90; o.height = 90
        let squares = try Engine.convert(photo, options: o, directory: directory)
        XCTAssertTrue(dimensions(squares.url.appendingPathComponent("photo.png")) == (30, 30))
        let pdf = try pdfFixture()
        o = Options(); o.format = .png
        XCTAssertTrue(dimensions(try Engine.convert(pdf, options: o, directory: directory).url) == (200, 120))
        o.pdfDPI = 300
        XCTAssertTrue(dimensions(try Engine.convert(pdf, options: o, directory: directory).url) == (417, 250))
        o.pdfDPI = 72
        XCTAssertTrue(dimensions(try Engine.convert(pdf, options: o, directory: directory).url) == (100, 60))
    }
    func testAnimationsRotate() throws {
        let input = directory.appendingPathComponent("spin.gif")
        write([image(30).cropping(to: CGRect(x: 0, y: 0, width: 30, height: 20))!, image(30).cropping(to: CGRect(x: 0, y: 0, width: 30, height: 20))!], to: input, type: .gif)
        var o = Options(); o.format = .gif; o.rotation = 90
        let output = try Engine.convert(input, options: o, directory: directory)
        let source = CGImageSourceCreateWithURL(output.url as CFURL, nil)!
        XCTAssertEqual(CGImageSourceGetCount(source), 2); XCTAssertTrue(dimensions(output.url) == (20, 30))
    }
}

@main struct Checks {
    static func main() {
        let suite = EngineTests()
        let checks: [(String, () throws -> Void)] = [
            ("resize and original preservation", suite.testResizePreservesAspectRatioAndOriginal),
            ("resize validation", suite.testResizeValidationAndNoUpscaling),
            ("JPEG compression", suite.testJPEGCompressionReducesFileSize),
            ("metadata analysis and pixel-preserving stripping", suite.testMetadataViewerAndLosslessStripping),
            ("orientation", suite.testOrientationAppliedBeforeStripping),
            ("bundled WebP", suite.testWebPToolWorksWithBundledLibraries),
            ("metadata preservation", suite.testPreserveMetadata),
            ("HEIC, lossless and same-format WebP", suite.testHEICAndLosslessWebP),
            ("unsupported metadata-only rejection", suite.testTIFFMetadataOnly),
            ("search across metadata, dimensions and image text", suite.testImageSearchAcrossMetadataAndText),
            ("SVG rendering, transparency and resizing", suite.testSVGRenderingAndTransparency),
            ("SVG viewBox and invalid input", suite.testSVGViewBoxAndInvalidInput),
            ("PDF pages, dimensions and rotation", suite.testPDFAllPagesAndRotation),
            ("GIF, BMP, TIFF and AVIF round trips", suite.testAdditionalStillFormats),
            ("GIF and TIFF frame extraction", suite.testGIFAndTIFFFrameExtraction),
            ("Animated GIF, frame folders and transparency fill", suite.testAnimatedGIFAndTransparencyFill),
            ("resolution-only resize and smaller-image skipping", suite.testResizeOnlySkipsSmallAndPreservesMetadata),
            ("automatic save location and original preservation", suite.testSaveCopiesBesideOriginal),
            ("replace original and legacy saved options", suite.testReplaceOriginalAndLegacyOptions),
            ("preview memory budget, eviction and page keys", suite.testPreviewBudgetAndPageKeys),
            ("preview decode and cache performance", suite.testPreviewPerformance),
            ("filename collisions", suite.testCollisionSafeNames),
            ("BMP output with metadata kept", suite.testBMPWithKeptMetadata),
            ("multi-size icons are one image", suite.testMultiSizeIconsAreOneImage),
            ("WebP temporary file keeps other results", suite.testWebPTemporaryKeepsOtherResults),
            ("SVG and PDF render larger than intrinsic size", suite.testVectorsRenderLargerThanIntrinsicSize),
            ("same-as-original fallbacks and quality visibility", suite.testSameAsOriginalFallbacksAndQuality),
            ("session-only choices reset", suite.testSessionChoicesReset),
            ("pages reuse file metadata", suite.testPagesReuseFileMetadata),
            ("folders expand to images", suite.testFoldersExpandToImages),
            ("bundled tool timeout", suite.testToolTimeout),
            ("flattening keeps wide-gamut colour", suite.testFlattenKeepsWideGamut),
            ("target file size", suite.testTargetFileSize),
            ("lossless PNG optimisation", suite.testPNGOptimisationIsLossless),
            ("keep the original when it's smaller", suite.testKeepSmallerOriginal),
            ("SVGZ, Illustrator and PostScript inputs", suite.testSVGZIllustratorAndPostScript),
            ("ICO and ICNS output", suite.testIconOutput),
            ("PDF output and combining", suite.testPDFOutputAndCombining),
            ("animated PNG, WebP, HEIC and GIF output", suite.testAnimationOutputs),
            ("metadata-only for TIFF, GIF and AVIF", suite.testMetadataOnlyMoreFormats),
            ("AVIF at 100% quality", suite.testAVIFAtFullQuality),
            ("width, height, fill, enlarging, rotation and crop plans", suite.testGeometryModes),
            ("rotate, flip and centred crop pixels", suite.testRotateFlipAndCrop),
            ("fill and crop, enlarging, @1x–@3x sets and PDF resolution", suite.testFillUpscaleScaleSetsAndPDFResolution),
            ("animations rotate frame by frame", suite.testAnimationsRotate)
        ]
        for (name, check) in checks {
            let before = failures
            do { try suite.setUpWithError(); try check(); try suite.tearDownWithError() }
            catch { failures += 1; print("FAIL \(name): \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(checks.count) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
