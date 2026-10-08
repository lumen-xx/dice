import SwiftUI
import AppKit
import ImageIO
import DiceCore
import Vision

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    var info: ImageInfo?
    var error: String?
    var result: ConversionResult?
    var thumbnail: NSImage?
    var recognizedText = ""
    var resultInfo: ImageInfo?
    var searchText = ""
    mutating func rebuildSearch() { searchText = ImageSearch.text(filename: url.lastPathComponent, path: url.path, info: info, recognizedText: recognizedText, extraInfo: resultInfo, error: error) }
}
@MainActor final class DiceModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var selected: UUID?
    @Published var options = Options() { didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: "dice.options") } } }
    @Published var busy = false
    @Published var importing = false
    @Published var status = "All processing stays on this Mac"
    @Published var alert: String?
    @Published var completed = 0
    private var cancelRequested = false
    private var closeRequested = false
    let session: URL
    init() {
        if let data = UserDefaults.standard.data(forKey: "dice.options"), let saved = try? JSONDecoder().decode(Options.self, from: data) { options = saved }
        session = FileManager.default.temporaryDirectory.appendingPathComponent("com.opyuii.dice/" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    }
    var selection: ImageItem? { items.first { $0.id == selected } }
    var results: [ImageItem] { items.filter { $0.result != nil } }
    var sourceBytes: Int64 { results.reduce(0) { $0 + ($1.info?.bytes ?? 0) } }
    var outputBytes: Int64 { results.reduce(0) { $0 + ($1.result?.bytes ?? 0) } }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]; panel.message = "Choose images to convert or inspect"
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func paste() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { add(urls); return }
        if let image = NSImage(pasteboard: .general), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            let path = session.appendingPathComponent("Pasted-" + UUID().uuidString + ".png")
            do { try data.write(to: path); add([path]) } catch { alert = error.localizedDescription }
        }
    }
    func add(_ urls: [URL]) {
        guard !busy, !importing else { return }
        let accepted = Array(Set(urls.filter { $0.isFileURL })).sorted { $0.path < $1.path }
        let fresh = accepted.filter { url in !items.contains(where: { $0.url == url }) }
        guard !fresh.isEmpty else { return }
        closeRequested = false
        importing = true
        Task {
            for url in fresh {
                let loaded = await Task.detached(priority: .userInitiated) { () -> ImageItem in
                    var item = ImageItem(url: url)
                    do { item.info = try Engine.inspect(url) } catch { item.error = error.localizedDescription }
                    if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 96] as CFDictionary) {
                        item.thumbnail = NSImage(cgImage: image, size: .zero)
                    }
                    if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) {
                        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                        request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
                        if (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil {
                            item.recognizedText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        }
                    }
                    item.rebuildSearch()
                    return item
                }.value
                if closeRequested { break }
                items.append(loaded)
                if selected == nil { selected = loaded.id }
            }
            importing = false
            if closeRequested { clear(); return }
            status = "\(items.count) image\(items.count == 1 ? "" : "s") ready"
        }
    }
    func remove(_ id: UUID) {
        guard !busy, !importing else { return }
        if let result = items.first(where: { $0.id == id })?.result { try? FileManager.default.removeItem(at: result.url) }
        let removedIndex = items.firstIndex { $0.id == id } ?? 0
        items.removeAll { $0.id == id }
        if selected == id { selected = items.isEmpty ? nil : items[min(removedIndex, items.count - 1)].id }
    }
    func clear() {
        guard !busy, !importing else { return }
        for item in items { if let result = item.result { try? FileManager.default.removeItem(at: result.url) } }
        items = []; selected = nil; status = "All processing stays on this Mac"
    }
    func process(andSave: Bool = false) {
        guard !busy, !importing, !items.isEmpty else { return }
        let snapshot = options
        busy = true; cancelRequested = false; completed = 0
        for i in items.indices {
            if let result = items[i].result { try? FileManager.default.removeItem(at: result.url) }
            items[i].result = nil; items[i].resultInfo = nil; items[i].rebuildSearch()
        }
        Task {
            for index in items.indices {
                if cancelRequested { break }
                guard items[index].info != nil else { completed += 1; continue }
                let input = items[index].url, directory = session
                status = "Processing \(index + 1) of \(items.count)…"
                let result = await Task.detached(priority: .userInitiated) { () -> Result<ConversionResult, Error> in
                    autoreleasepool { Result { try Engine.convert(input, options: snapshot, directory: directory) } }
                }.value
                switch result {
                case .success(let output):
                    items[index].result = output; items[index].error = nil
                    let info = await Task.detached { try? Engine.inspect(output.url) }.value
                    items[index].resultInfo = info
                case .failure(let error): items[index].error = error.localizedDescription
                }
                items[index].rebuildSearch()
                completed += 1
            }
            busy = false
            if closeRequested { clear(); return }
            status = cancelRequested ? "Stopped after the current image" : "\(results.count) of \(items.count) images processed"
            if let error = items.first(where: { $0.error != nil })?.error { alert = error }
            if andSave && !cancelRequested && !results.isEmpty { save() }
        }
    }
    func cancel() { cancelRequested = true; status = "Finishing the current image…" }
    func save() {
        do {
            if results.count == 1, let item = results.first, let result = item.result {
                let panel = NSSavePanel(); panel.nameFieldStringValue = item.url.deletingPathExtension().lastPathComponent + "-dice." + result.url.pathExtension
                panel.directoryURL = item.url.deletingLastPathComponent()
                guard panel.runModal() == .OK, let output = panel.url else { return }
                guard output.standardizedFileURL != item.url.standardizedFileURL else { throw DiceError.message("Choose a different filename to preserve the original.") }
                try Data(contentsOf: result.url).write(to: output, options: .atomic)
                status = "Saved a copy"
            } else {
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Save images"
                guard panel.runModal() == .OK, let directory = panel.url else { return }
                for item in results {
                    guard let result = item.result else { continue }
                    let output = Engine.uniqueURL(in: directory, stem: item.url.deletingPathExtension().lastPathComponent + "-dice", ext: result.url.pathExtension)
                    try FileManager.default.copyItem(at: result.url, to: output)
                }
                status = "Saved \(results.count) images"
            }
        } catch { alert = error.localizedDescription }
    }
    func exportMetadata(_ info: ImageInfo) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "metadata.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let records = info.rows.map { ["group": $0.group, "tag": $0.name, "value": $0.value] }
            try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { alert = error.localizedDescription }
    }
    func closeSession() {
        closeRequested = true
        if busy { cancel() }
        if !busy && !importing { clear() }
    }
    func cleanup() { try? FileManager.default.removeItem(at: session) }
}
func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
