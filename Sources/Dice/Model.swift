import SwiftUI
import AppKit
import ImageIO
import DiceCore
import Vision
import UniformTypeIdentifiers

struct ImageItem: Identifiable {
    let id = UUID()
    var url: URL
    var page = 1
    var name: String {
        if url.pathExtension.lowercased() == "pdf" { return "\(url.lastPathComponent) · Page \(page)" }
        if (info?.frames ?? 1) > 1 { return info?.type == UTType.tiff.identifier ? "\(url.lastPathComponent) · Page \(page)" : "\(url.lastPathComponent) · \(info?.frames ?? 1) frames" }
        return url.lastPathComponent
    }
    var info: ImageInfo?
    var error: String?
    var previewGeneration = UUID()
    var previewCacheKey: String { result.map { PreviewCache.key($0.previewURL ?? $0.url) + "|" + previewGeneration.uuidString } ?? PreviewCache.key(url, page: page) }
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
    /// Called when a run finishes with every image processed and saved.
    var onFinished: (() -> Void)?
    /// Set by a menu bar drop: run with the current settings as soon as the dropped images are read.
    var startWhenReady = false
    private var cancelRequested = false
    private var closeRequested = false
    let previewCache = PreviewCache()
    let session: URL
    init() {
        if let data = UserDefaults.standard.data(forKey: "dice.appPreferences"), let saved = try? JSONDecoder().decode(AppPreferences.self, from: data) { preferences = saved }
        if let data = UserDefaults.standard.data(forKey: "dice.options"), let saved = try? JSONDecoder().decode(Options.self, from: data) { options = saved }
        Self.pruneClipboardFiles()
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
        if items.isEmpty {
            options.format = preferences.useExportFormat ? preferences.exportFormat : .original
            options.quality = preferences.defaultQuality
            options.resize = preferences.defaultResize
            options.edge = preferences.defaultEdge
            options.percent = preferences.defaultPercent
            options.replaceOriginals = preferences.defaultReplaceOriginals
            options.stripMetadata = preferences.alwaysStripMetadata || preferences.defaultStripMetadata
        }
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
            if startWhenReady { startWhenReady = false; if !items.isEmpty { process() } }
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
    func trashOriginal(_ id: UUID) {
        guard !busy, !importing, let item = items.first(where: { $0.id == id }) else { return }
        let others = items.contains { $0.id != id && $0.url == item.url }
        do {
            if !others { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
            remove(id)
            status = "Moved \(item.url.lastPathComponent) to the Trash"
        } catch { alert = error.localizedDescription }
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
    /// Runs the conversion. A nil action follows the saved defaults; an action overrides the destination for this run only.
    func process(_ action: ExportAction? = nil) {
        guard !busy, !importing, !items.isEmpty else { return }
        let clipboard = action == .clipboard || (action == nil && preferences.exportMode == .clipboard)
        let edit = action == .edit
        let skipSave = clipboard || edit
        var useFolder = action == .folder || (action == nil && preferences.useExportFolder)
        if !skipSave && useFolder && preferences.exportFolder.isEmpty {
            if action == .folder { chooseExportFolder(); if preferences.exportFolder.isEmpty { return } }
            else { alert = "Choose a default export folder in Settings."; settingsPresented = true; return }
        }
        if skipSave { useFolder = false }
        let exportDirectory = useFolder ? URL(fileURLWithPath: preferences.exportFolder) : nil
        var snapshot = options
        if let action { snapshot.replaceOriginals = action == .replace }
        if preferences.alwaysStripMetadata { snapshot.stripMetadata = true }
        snapshot.flattenColor = preferences.flattenColor
        snapshot.keepAnimation = preferences.keepAnimation
        snapshot.framesAsFolder = preferences.framesAsFolder
        let suffix = preferences.fileSuffix.filter { !"/:\\".contains($0) }
        snapshot.fileSuffix = suffix
        let resizeOnly = snapshot.resizeOnly && snapshot.resize != .original && !snapshot.metadataOnly && !preferences.alwaysStripMetadata
        busy = true; cancelRequested = false; completed = 0
        for i in items.indices {
            if let result = items[i].result { previewCache.remove(items[i].previewCacheKey); try? FileManager.default.removeItem(at: result.url) }
            items[i].previewGeneration = UUID(); items[i].result = nil; items[i].resultInfo = nil; items[i].savedURL = nil; items[i].rebuildSearch()
        }
        var replaced = 0
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
                    // PDFs, SVGs and multi-frame files produce one output per page, so they are never replaced in place.
                    let replace = snapshot.replaceOriginals && !["pdf", "svg"].contains(input.pathExtension.lowercased()) && (items[index].info?.frames ?? 1) == 1 && !skipSave
                    let saved: Result<URL, Error>? = skipSave ? nil : await Task.detached(priority: .userInitiated) { Result { replace ? try Engine.replaceOriginal(input, with: output) : try Engine.saveCopy(output, beside: input, directory: exportDirectory) } }.value
                    var replacedHere = false
                    switch saved {
                    case nil: break
                    case .success(let url)?:
                        items[index].savedURL = url
                        if replace { replacedHere = true; previewCache.remove(PreviewCache.key(input, page: page)); items[index].url = url; replaced += 1 }
                    case .failure(let error)?: items[index].error = (replace ? "Processed, but could not replace the original: " : "Processed, but could not save the copy: ") + error.localizedDescription + (replace ? "" : " Use Dice → Save Copies As… to choose another folder.")
                    }
                    let info = await Task.detached { try? Engine.inspect(output.previewURL ?? output.url) }.value
                    items[index].resultInfo = info
                    if replacedHere, let info { items[index].info = info }
                case .failure(let error): items[index].error = error.localizedDescription
                }
                items[index].rebuildSearch()
                completed += 1
            }
            var copied = 0
            if clipboard && !cancelRequested && !closeRequested { copied = copyResultsToClipboard() }
            var opened = 0
            if edit && !cancelRequested && !closeRequested { opened = openResultsInEditor() }
            busy = false
            if closeRequested { clear(); return }
            status = edit && opened > 0 ? "Opened \(opened) image\(opened == 1 ? "" : "s") for editing" : clipboard && copied > 0 ? "Copied \(copied) image\(copied == 1 ? "" : "s") to the clipboard" : cancelRequested ? "Stopped after the current image" : (replaced > 0 ? "Replaced \(replaced) original\(replaced == 1 ? "" : "s"); moved to the Trash" : resizeOnly ? "Resized \(results.count) images; smaller images skipped" : "\(results.count) of \(items.count) images processed")
            if let error = items.first(where: { $0.error != nil })?.error { alert = error }
            else if !cancelRequested { onFinished?() }
        }
    }
    /// Puts the processed images on the clipboard: image data for one still image, file URLs otherwise.
    /// Files are copied out of the session folder first so a paste still works after Dice closes.
    func stagedResults() throws -> (urls: [URL], outputs: [ConversionResult]) {
        let outputs = results.compactMap { $0.result }
        guard !outputs.isEmpty else { return ([], []) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("com.opyuii.dice-clipboard/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for output in outputs {
            let target = Engine.uniqueURL(in: folder, stem: output.url.deletingPathExtension().lastPathComponent, ext: output.url.pathExtension)
            try FileManager.default.copyItem(at: output.url, to: target); urls.append(target)
        }
        return (urls, outputs)
    }
    /// Opens the processed images in the default app (usually Preview) from a copy that outlives Dice's session.
    func openResultsInEditor() -> Int {
        do {
            let staged = try stagedResults()
            for url in staged.urls { NSWorkspace.shared.open(url) }
            return staged.urls.count
        } catch { alert = "Could not open the images: " + error.localizedDescription; return 0 }
    }
    func copyResultsToClipboard() -> Int {
        do {
            let (urls, outputs) = try stagedResults()
            guard !outputs.isEmpty else { return 0 }
            let pasteboard = NSPasteboard.general; pasteboard.clearContents()
            if urls.count == 1, !outputs[0].isFolder, let image = NSImage(contentsOf: urls[0]) {
                let item = NSPasteboardItem()
                item.setString(urls[0].absoluteString, forType: .fileURL)
                if let tiff = image.tiffRepresentation {
                    item.setData(tiff, forType: .tiff)
                    if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
                }
                pasteboard.writeObjects([item])
            } else { pasteboard.writeObjects(urls as [NSURL]) }
            return urls.count
        } catch { alert = "Could not copy to the clipboard: " + error.localizedDescription; return 0 }
    }
    /// Removes clipboard copies from earlier runs once they are a day old.
    static func pruneClipboardFiles() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("com.opyuii.dice-clipboard")
        let entries = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for entry in entries where Date().timeIntervalSince((try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > 86_400 { try? FileManager.default.removeItem(at: entry) }
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
                if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.trashItem(at: output, resultingItemURL: nil) }
                try FileManager.default.copyItem(at: result.url, to: output)
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
