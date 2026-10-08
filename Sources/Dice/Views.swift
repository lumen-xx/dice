import SwiftUI
import AppKit
import ImageIO
import DiceCore
import UniformTypeIdentifiers

private let accent = DiceStyle.accent
struct DiceView: View {
    @ObservedObject var model: DiceModel
    @State private var metadata = false
    @State private var settings = false
    @State private var batch = false
    @State private var batchSearch = ""
    @State private var targeted = false
    @State private var preview: NSImage?
    @State private var inspected: ImageInfo?
    @State private var previewError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var displayedURL: URL? { model.selection?.result?.url ?? model.selection?.url }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if batch {
                BatchPane(model: model, query: $batchSearch) { id in model.selected = id; batch = false }
                    .padding(.top, 52).padding(.bottom, model.items.isEmpty ? 16 : 52)
            } else if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "die.face.5").font(DiceStyle.emptySymbol).foregroundStyle(.secondary)
                    Button("Choose images…") { model.chooseFiles() }.buttonStyle(.plain).font(DiceStyle.body).foregroundStyle(.secondary)
                    Text("or drop them here").font(DiceStyle.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metadata {
                MetadataPane(info: inspected).id(model.selected).padding(.top, 54).padding(.bottom, 52)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    if let preview {
                        Image(nsImage: preview).resizable().scaledToFit().padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 52)
                    } else if let error = previewError {
                        Text(error).font(DiceStyle.caption).foregroundStyle(.secondary).padding(30)
                    } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
            }
            toolbar.padding(DiceStyle.inset).padding(.leading, metadata || batch ? 80 : 0)
            if !model.items.isEmpty {
                VStack { Spacer(); HStack { Spacer(); pager }.padding(DiceStyle.inset) }
            }
        }
        .font(DiceStyle.body)
        .ignoresSafeArea()
        .frame(minWidth: 520, minHeight: 420)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard !model.busy && !model.importing else { return false }
            let group = DispatchGroup(); let urls = DropURLs()
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                    else if let url = item as? URL { urls.append(url) }
                }
            }
            group.notify(queue: .main) { model.add(urls.values) }; return true
        }
        .overlay {
            if targeted && !model.busy && !model.importing {
                AuroraDropBorder().allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: targeted)
        .tint(accent)
        .task(id: displayedURL) { await loadPreview() }
        .alert("Dice couldn’t finish", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("OK") { model.alert = nil } } message: { Text(model.alert ?? "") }
    }
    var index: Int { model.items.firstIndex { $0.id == model.selected } ?? 0 }
    func step(_ direction: Int) { guard !model.items.isEmpty else { return }; model.selected = model.items[(index + direction + model.items.count) % model.items.count].id }
    var toolbar: some View {
        HStack(spacing: 2) {
            if batch {
                icon("arrow.left", "Back to image") { batch = false }
                Text("Images").font(DiceStyle.heading)
                Spacer()
                icon("plus", "Add images") { model.chooseFiles() }.disabled(model.busy || model.importing)
            } else if metadata {
                icon("arrow.left", "Back to image") { flip() }
                Text("Metadata").font(DiceStyle.heading)
                Spacer()
                if let info = inspected { Menu { Button("Copy all tags") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info.rows.map { "[\($0.group)] \($0.name): \($0.value)" }.joined(separator: "\n"), forType: .string) }; Button("Export JSON…") { model.exportMetadata(info) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.secondary).fixedSize().padding(7) }
            } else {
                icon("plus", "Add images") { model.chooseFiles() }.disabled(model.busy || model.importing)
                if model.busy || model.importing { ProgressView().controlSize(.mini).padding(.horizontal, 8) }
                icon("info", "View metadata") { flip() }.disabled(inspected == nil || model.items.isEmpty)
                icon("slider.horizontal.3", "Conversion settings") { settings.toggle() }
                    .popover(isPresented: $settings, arrowEdge: .bottom) { optionsPanel }
                icon("arrow.down", "Save processed copies") { model.save() }.disabled(model.busy || model.importing || model.results.isEmpty)
            }
            icon("play.fill", "Start with current settings") { settings = false; model.process() }.foregroundStyle(accent).disabled(model.busy || model.importing || model.items.isEmpty)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background { if !metadata && !batch { Capsule().fill(.ultraThinMaterial) } }
        .overlay { if !metadata && !batch { Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5) } }
        .frame(maxWidth: metadata || batch ? .infinity : nil)
    }
    var pager: some View {
        HStack(spacing: 0) {
            icon("chevron.left", "Previous image") { step(-1) }.disabled(model.items.count < 2)
            Button { batch.toggle() } label: { Text("\(index + 1) / \(model.items.count)").font(DiceStyle.page).padding(.horizontal, 7).frame(height: DiceStyle.controlSize) }.help("Browse and search all images").accessibilityLabel("Browse images, page \(index + 1) of \(model.items.count)")
            icon("chevron.right", "Next image") { step(1) }.disabled(model.items.count < 2)
        }.buttonStyle(.plain).padding(3).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5))
    }
    func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(DiceStyle.control).frame(width: DiceStyle.controlSize,height: DiceStyle.controlSize).contentShape(Rectangle()) }.help(label).accessibilityLabel(label)
    }
    func flip() { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { metadata.toggle() } }
    var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image settings").font(DiceStyle.heading)
            Toggle("Metadata only", isOn: $model.options.metadataOnly).font(DiceStyle.caption)
            if !model.options.metadataOnly {
                Picker("Format", selection: $model.options.format) { ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Resize", selection: $model.options.resize) { ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) } }
                if model.options.resize == .edge { HStack { Text("Longest edge"); number($model.options.edge); Text("px") } }
                if model.options.resize == .percent { HStack { Text("Scale"); number($model.options.percent); Text("%") } }
                if model.options.resize == .fit { HStack { number($model.options.width); Text("×"); number($model.options.height); Text("px") } }
                if model.options.format != .png { HStack { Text("Quality"); Slider(value: $model.options.quality, in: 0.1...1); Text("\(Int(model.options.quality * 100))%").monospacedDigit() } }
                if model.options.format == .webp { Toggle("Lossless", isOn: $model.options.webpLossless) }
            }
            Toggle("Remove personal metadata", isOn: $model.options.stripMetadata).disabled(model.options.metadataOnly)
            Text(model.options.metadataOnly ? "Pixels stay unchanged. Colour and orientation are retained." : "Copies only. No upscaling. PNG is lossless; JPEG transparency becomes white.").font(DiceStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Apply") { settings = false; model.process() }.buttonStyle(.borderedProminent).disabled(model.busy || model.importing) }
        }.font(DiceStyle.label).padding(DiceStyle.inset).frame(width: 310).tint(accent).disabled(model.busy || model.importing)
    }
    func number(_ binding: Binding<Int>) -> some View { TextField("", value: binding, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 65).accessibilityLabel("Resize value") }
    func loadPreview() async {
        preview = nil; inspected = nil; previewError = nil
        guard let url = displayedURL else { return }
        let loaded = await Task.detached(priority: .userInitiated) { () -> (NSImage?, ImageInfo?, String?) in
            autoreleasepool {
                do {
                    let info = try Engine.inspect(url)
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) else { return (nil, info, "This image has no preview.") }
                    return (NSImage(cgImage: image, size: .zero), info, nil)
                } catch { return (nil,nil,error.localizedDescription) }
            }
        }.value
        guard !Task.isCancelled, displayedURL == url else { return }
        preview = loaded.0; inspected = loaded.1; previewError = loaded.2
    }
}

struct BatchPane: View {
    @ObservedObject var model: DiceModel
    @Binding var query: String
    let select: (UUID) -> Void
    var filtered: [ImageItem] { model.items.filter { ImageSearch.matches(query, text: $0.searchText) } }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search images, metadata or text", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Clear image search")
                    }
                }.font(DiceStyle.body).padding(.horizontal, 12).frame(height: 36)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                if model.importing { ProgressView().controlSize(.mini).help("Reading metadata and text") }
            }
            if filtered.isEmpty {
                Text(model.items.isEmpty ? "Add images to start a batch." : "No images match this search.").font(DiceStyle.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { item in
                            HStack(spacing: 10) {
                                Button { select(item.id) } label: {
                                    HStack(spacing: 10) {
                                        if let thumbnail = item.thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 36,height: 36) }
                                        else { Image(systemName: "photo").frame(width: 36,height: 36) }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.url.lastPathComponent).font(DiceStyle.label).lineLimit(1)
                                            if let info = item.info { Text("\(info.width) × \(info.height) · \(bytes(info.bytes))").font(DiceStyle.data).foregroundStyle(.secondary) }
                                            if let error = item.error { Text(error).font(DiceStyle.caption).foregroundStyle(.red).lineLimit(1) }
                                        }
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Open \(item.url.lastPathComponent)")
                                Button { model.remove(item.id) } label: { Image(systemName: "xmark").font(DiceStyle.caption).frame(width: 22,height: 26) }.buttonStyle(.plain).help("Remove from Dice; original stays in place").accessibilityLabel("Remove \(item.url.lastPathComponent)").disabled(model.busy || model.importing)
                            }.padding(8).background(item.id == model.selected ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            HStack { Text("\(filtered.count) of \(model.items.count) images").font(DiceStyle.caption).foregroundStyle(.secondary); Spacer() }
        }.padding(.horizontal, 16)
    }
}
final class DropURLs: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; storage.append(url) }
    var values: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}
