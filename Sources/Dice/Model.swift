import SwiftUI
import AppKit
import ImageIO
import DiceCore
import Vision
import UniformTypeIdentifiers

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    var page = 1
    var name: String {
        if url.pathExtension.lowercased() == "pdf" { return "\(url.lastPathComponent) · Page \(page)" }
        if (info?.frames ?? 1) > 1 { return "\(url.lastPathComponent) · \(info?.type == UTType.tiff.identifier ? "Page" : "Frame") \(page)" }
        return url.lastPathComponent
    }
    var info: ImageInfo?
    var error: String?
    var previewGeneration = UUID()
    var previewCacheKey: String { result.map { PreviewCache.key($0.url) + "|" + previewGeneration.uuidString } ?? PreviewCache.key(url, page: page) }
    var savedURL: URL?
    var result: ConversionResult?
    var thumbnail: NSImage?
    var recognizedText = ""
    var resultInfo: ImageInfo?
    var searchText = ""
    mutating func rebuildSearch() { searchText = ImageSearch.text(filename: name, path: url.path, info: info, recognizedText: recognizedText, extraInfo: resultInfo, error: error) }
}
@MainActor final class DiceModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var selected: UUID?
    @Published var preferences = AppPreferences() { didSet { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "dice.appPreferences") } } }
    @Published var settingsPresented = false
    @Published var options = Options() { didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: "dice.options") } } }
    @Published var busy = false
    @Published var importing = false
    @Published var status = "All processing stays on this Mac"
    @Published var alert: String?
    @Published var completed = 0
    private var cancelRequested = false
    private var closeRequested = false
    let previewCache = PreviewCache()
    let session: URL
    init() {
        if let data = UserDefaults.standard.data(forKey: "dice.appPreferences"), let saved = try? JSONDecoder().decode(AppPreferences.self, from: data) { preferences = saved }
        if let data = UserDefaults.standard.data(forKey: "dice.options"), let saved = try? JSONDecoder().decode(Options.self, from: data) { options = saved }
        session = FileManager.default.temporaryDirectory.appendingPathComponent("com.opyuii.dice/" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    }
    var selection: ImageItem? { items.first { $0.id == selected } }
    var results: [ImageItem] { items.filter { $0.result != nil } }
    var unsavedResults: [ImageItem] { results.filter { $0.savedURL == nil } }
    var sourceBytes: Int64 { results.reduce(0) { $0 + ($1.info?.bytes ?? 0) } }
    var outputBytes: Int64 { results.reduce(0) { $0 + ($1.result?.bytes ?? 0) } }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .svg, .pdf]; panel.message = "Choose images to convert or inspect"
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
        if items.isEmpty { options.format = preferences.useExportFormat ? preferences.exportFormat : .original }
        closeRequested = false
        importing = true
        let cache = previewCache
        Task {
            for url in fresh {
                let loaded = await Task.detached(priority: .userInitiated) { () -> [ImageItem] in
                    let pages: Int
                    do { pages = try Engine.pageCount(url) } catch {
                        var item = ImageItem(url: url); item.error = error.localizedDescription; item.rebuildSearch(); return [item]
                    }
                    return (1...pages).map { page in autoreleasepool {
                    var item = ImageItem(url: url, page: page)
                    do { item.info = try Engine.inspect(url, page: page) } catch { item.error = error.localizedDescription }
                    if let image = try? Engine.previewImage(url, maxPixelSize: 1600, page: page) {
                        cache.insert(image, for: PreviewCache.key(url, page: page))
                        if let thumbnail = try? Engine.scaledPreview(image, maxPixelSize: 96) { item.thumbnail = NSImage(cgImage: thumbnail, size: .zero) }
                        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                        request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
                        if (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil {
                            item.recognizedText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        }
                    }
                    item.rebuildSearch()
                    return item
                    } }
                }.value
                if closeRequested { break }
                items.append(contentsOf: loaded)
                if selected == nil { selected = loaded.first?.id }
            }
            importing = false
            if closeRequested { clear(); return }
            status = "\(items.count) image\(items.count == 1 ? "" : "s") ready"
        }
    }
    func remove(_ id: UUID) {
        guard !busy, !importing else { return }
        if let item = items.first(where: { $0.id == id }) { previewCache.remove(PreviewCache.key(item.url, page: item.page)); if item.result != nil { previewCache.remove(item.previewCacheKey) } }
        if let result = items.first(where: { $0.id == id })?.result { try? FileManager.default.removeItem(at: result.url) }
        let removedIndex = items.firstIndex { $0.id == id } ?? 0
        items.removeAll { $0.id == id }
        if selected == id { selected = items.isEmpty ? nil : items[min(removedIndex, items.count - 1)].id }
    }
    func clear() {
        guard !busy, !importing else { return }
        for item in items { if let result = item.result { try? FileManager.default.removeItem(at: result.url) } }
        previewCache.clear()
        items = []; selected = nil; status = "All processing stays on this Mac"
    }
    func chooseExportFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Choose export folder"
        if !preferences.exportFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: preferences.exportFolder) }
        if panel.runModal() == .OK, let url = panel.url { preferences.exportFolder = url.path; preferences.useExportFolder = true }
    }
    func process(resizeOnly: Bool = false) {
        guard !busy, !importing, !items.isEmpty else { return }
        if preferences.useExportFolder && preferences.exportFolder.isEmpty { alert = "Choose a default export folder in Settings."; settingsPresented = true; return }
        let exportDirectory = preferences.useExportFolder ? URL(fileURLWithPath: preferences.exportFolder) : nil
        let snapshot = options
        busy = true; cancelRequested = false; completed = 0
        for i in items.indices {
            if let result = items[i].result { previewCache.remove(items[i].previewCacheKey); try? FileManager.default.removeItem(at: result.url) }
            items[i].previewGeneration = UUID(); items[i].result = nil; items[i].resultInfo = nil; items[i].savedURL = nil; items[i].rebuildSearch()
        }
        Task {
            for index in items.indices {
                if cancelRequested { break }
                guard items[index].info != nil else { completed += 1; continue }
                let input = items[index].url, page = items[index].page, directory = session
                status = "Processing \(index + 1) of \(items.count)…"
                let result = await Task.detached(priority: .userInitiated) { () -> Result<ConversionResult?, Error> in
                    autoreleasepool { Result { resizeOnly ? try Engine.resize(input, options: snapshot, directory: directory, page: page) : try Engine.convert(input, options: snapshot, directory: directory, page: page) } }
                }.value
                switch result {
                case .success(nil): items[index].error = nil
                case .success(let output?):
                    items[index].result = output; items[index].error = nil
                    let saved = await Task.detached(priority: .userInitiated) { Result { try Engine.saveCopy(output, beside: input, directory: exportDirectory) } }.value
                    switch saved {
                    case .success(let url): items[index].savedURL = url
                    case .failure(let error): items[index].error = "Processed, but could not save the copy: " + error.localizedDescription + " Use Dice → Save Copies As… to choose another folder."
                    }
                    let info = await Task.detached { try? Engine.inspect(output.url) }.value
                    items[index].resultInfo = info
                case .failure(let error): items[index].error = error.localizedDescription
                }
                items[index].rebuildSearch()
                completed += 1
            }
            busy = false
            if closeRequested { clear(); return }
            status = cancelRequested ? "Stopped after the current image" : (resizeOnly ? "Resized \(results.count) images; smaller images skipped" : "\(results.count) of \(items.count) images processed")
            if let error = items.first(where: { $0.error != nil })?.error { alert = error }
        }
    }
    func cancel() { cancelRequested = true; status = "Finishing the current image…" }
    func save() {
        guard !busy, !importing, !results.isEmpty else { return }
        do {
            if results.count == 1, let item = results.first, let result = item.result {
                let panel = NSSavePanel(); panel.nameFieldStringValue = result.url.lastPathComponent
                panel.directoryURL = item.url.deletingLastPathComponent()
                guard panel.runModal() == .OK, let output = panel.url else { return }
                guard output.standardizedFileURL != item.url.standardizedFileURL else { throw DiceError.message("Choose a different filename to preserve the original.") }
                try Data(contentsOf: result.url).write(to: output, options: .atomic)
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].savedURL = output }
                status = "Saved a copy"
            } else {
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Save images"
                guard panel.runModal() == .OK, let directory = panel.url else { return }
                for item in results {
                    guard let result = item.result else { continue }
                    let output = Engine.uniqueURL(in: directory, stem: result.url.deletingPathExtension().lastPathComponent, ext: result.url.pathExtension)
                    try FileManager.default.copyItem(at: result.url, to: output)
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].savedURL = output }
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
