import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
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
    func fixture(name: String = "image", width: Int = 120, height: Int = 80, format: String = UTType.jpeg.identifier) throws -> URL {
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
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
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
        let input = try fixture(format: UTType.tiff.identifier)
        _ = try runExif(["-overwrite_original", "-Artist=Remove me", input.path])
        var options = Options(); options.metadataOnly = true
        XCTAssertThrowsError(try Engine.convert(input, options: options, directory: directory))
        XCTAssertEqual(try Engine.inspect(input).value("Artist"),"Remove me")
    }
    func testCollisionSafeNames() throws {
        let first = directory.appendingPathComponent("photo-dice.jpg")
        try Data().write(to: first)
        XCTAssertEqual(Engine.uniqueURL(in: directory,stem:"photo-dice",ext:"jpg").lastPathComponent,"photo-dice-2.jpg")
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
            ("filename collisions", suite.testCollisionSafeNames)
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
