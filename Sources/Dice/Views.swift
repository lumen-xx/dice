import SwiftUI
import AppKit
import ImageIO
import DiceCore
import UniformTypeIdentifiers

private let accent = DiceStyle.accent
struct DiceView: View {
    @ObservedObject var model: DiceModel
    let close: () -> Void
    var checkUpdates: () -> Void = {}
    @State private var imageSettingsPresented = false
    @State private var exportPopoverPresented = false
    @State private var finderMenu = FinderMenu.isEnabled
    // `--show metadata` or `--show batch` opens that pane, for screenshots; normal launches start on the image.
    @State private var metadata = DiceView.launchPane == "metadata"
    @State private var batch = DiceView.launchPane == "batch"
    private static let launchPane = CommandLine.arguments.firstIndex(of: "--show").flatMap { CommandLine.arguments.dropFirst($0 + 1).first }
    @State private var batchSearch = ""
    @State private var targeted = false
    @State private var loadedPreviewKey: String?
    @State private var preview: NSImage?
    @State private var inspected: ImageInfo?
    @State private var previewError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var displayedURL: URL? { model.selection?.result.map { $0.previewURL ?? $0.url } ?? model.selection?.url }
    var previewKey: String? { model.selection?.previewCacheKey }
    var displayedPreview: NSImage? {
        guard let key = previewKey else { return nil }
        if key == loadedPreviewKey { return preview }
        if let image = model.previewCache.image(for: key) { return NSImage(cgImage: image, size: .zero) }
        return model.selection?.thumbnail
    }
    var currentInfo: ImageInfo? {
        let known = model.selection?.result == nil ? model.selection?.info : model.selection?.resultInfo
        return known ?? (previewKey == loadedPreviewKey ? inspected : nil)
    }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if model.settingsPresented {
                ScrollView { appSettingsPanel.frame(maxWidth: .infinity) }
                    .padding(.top, 64).padding(.bottom, 16)
            } else if batch {
                BatchPane(model: model, query: $batchSearch) { id in model.selected = id; batch = false }
                    .padding(.top, 64).padding(.bottom, model.items.isEmpty ? 16 : 58)
            } else if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "die.face.5").font(DiceStyle.emptySymbol).foregroundStyle(DiceStyle.auroraMark)
                    Button("Choose images…") { model.chooseFiles() }.buttonStyle(.plain).font(DiceStyle.body).foregroundStyle(.secondary)
                    Text("or drop them here").font(DiceStyle.caption).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metadata {
                MetadataPane(info: currentInfo).id(model.selected).padding(.top, 64).padding(.bottom, 58)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    if model.busy {
                        VStack(spacing: 14) {
                            AuroraProgress(fraction: model.items.isEmpty ? 0 : Double(model.completed) / Double(model.items.count))
                            Text(model.status).font(DiceStyle.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let preview = displayedPreview {
                        Image(nsImage: preview).resizable().scaledToFit().padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 52)
                            .contextMenu { if let id = model.selected { removalMenu(id) } }
                    } else if let error = previewError {
                        Text(error).font(DiceStyle.caption).foregroundStyle(.secondary).padding(30)
                    } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
            }
            toolbar.padding(DiceStyle.inset).padding(.leading, metadata || batch || model.settingsPresented ? 56 : 0)
            if !model.items.isEmpty && !model.settingsPresented {
                VStack { Spacer(); HStack(spacing: 12) { footerSummary; Spacer(minLength: 12); pager }.padding(DiceStyle.inset) }
            }
        }
        .font(DiceStyle.body)
        .ignoresSafeArea()
        .frame(minWidth: 520, minHeight: 420)
        .overlay(alignment: .topLeading) {
            icon("xmark", "Close Dice") { close() }
                .keyboardShortcut("w", modifiers: .command)
                .buttonStyle(.plain)
                .padding(.horizontal, 4).padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5))
                .padding(DiceStyle.inset)
        }
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
        .background(SwipeCatcher { direction in
            guard !model.settingsPresented, !batch, !metadata, !model.busy, model.items.count > 1 else { return }
            step(direction)
        })
        .onChange(of: model.settingsPresented) { if model.settingsPresented { imageSettingsPresented = false } }
        .task(id: "\(model.selected?.uuidString ?? "")|\(previewKey ?? "")") { await loadPreview() }
        .alert("Dice couldn’t finish", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("OK") { model.alert = nil } } message: { Text(model.alert ?? "") }
    }
    var index: Int { model.items.firstIndex { $0.id == model.selected } ?? 0 }
    func step(_ direction: Int) { guard !model.items.isEmpty else { return }; model.selected = model.items[(index + direction + model.items.count) % model.items.count].id }
    var toolbar: some View {
        HStack(spacing: 2) {
            if model.settingsPresented {
                icon("arrow.left", "Back to image") { model.settingsPresented = false; metadata = false; batch = false }
                Text("App settings").font(DiceStyle.heading)
                Spacer()
            } else if batch {
                icon("arrow.left", "Back to image") { batch = false }
                Text("Images").font(DiceStyle.heading)
                Spacer()
                icon("plus", "Add images") { model.chooseFiles() }.disabled(model.busy || model.importing)
            } else if metadata {
                icon("arrow.left", "Back to image") { flip() }
                Text("Metadata").font(DiceStyle.heading)
                Spacer()
                if let info = currentInfo { Menu { Button("Copy all tags") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info.rows.map { "[\($0.group)] \($0.name): \($0.value)" }.joined(separator: "\n"), forType: .string) }; Button("Export JSON…") { model.exportMetadata(info) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.secondary).fixedSize().padding(7) }
            } else {
                icon("plus", "Add images") { model.chooseFiles() }.disabled(model.busy || model.importing)
                if model.busy || model.importing { ProgressView().controlSize(.mini).padding(.horizontal, 8) }
                icon("info", "View metadata") { flip() }.disabled(currentInfo == nil || model.items.isEmpty)
                icon("slider.horizontal.3", "Image settings") { imageSettingsPresented.toggle() }
                    .popover(isPresented: $imageSettingsPresented, arrowEdge: .top) { imageSettingsPanel }
            }
            if !model.settingsPresented {
            icon("play.fill", "Start with current settings (right-click for more export options)") { imageSettingsPresented = false; model.process() }.foregroundStyle(accent).disabled(model.busy || model.importing || model.items.isEmpty)
                .overlay { RightClickCatcher { if !(model.busy || model.importing || model.items.isEmpty) { exportPopoverPresented = true } } }
                .popover(isPresented: $exportPopoverPresented, arrowEdge: .top) { exportPopover }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background { if !metadata && !batch && !model.settingsPresented { Capsule().fill(.ultraThinMaterial) } }
        .overlay { if !metadata && !batch && !model.settingsPresented { Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5) } }
        .frame(maxWidth: metadata || batch || model.settingsPresented ? .infinity : nil)
    }
    @ViewBuilder var footerSummary: some View {
        if batch {
            let count = model.items.filter { ImageSearch.matches(batchSearch, text: $0.searchText) }.count
            Text("\(count) of \(model.items.count) images").font(DiceStyle.caption).foregroundStyle(.secondary)
        } else if let info = currentInfo {
            HStack(spacing: 6) {
                Text("\(info.width) × \(info.height) · \(info.value("FileType") ?? "Image") · \(bytes(info.bytes))")
                if model.selection?.savedURL != nil { Image(systemName: "checkmark").help(model.selection?.savedURL?.path ?? "Saved copy").accessibilityLabel("Copy saved") }
                if metadata {
                    Text("· \(info.rows.count) tags")
                    if info.hasGPS { Image(systemName: "location.fill").help("GPS metadata found") }
                }
            }.font(DiceStyle.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    var pager: some View {
        HStack(spacing: 0) {
            icon("chevron.left", "Previous image") { step(-1) }.disabled(model.items.count < 2)
            Button { model.settingsPresented = false; batch.toggle() } label: { Text("\(index + 1) / \(model.items.count)").font(DiceStyle.page).padding(.horizontal, 7).frame(height: DiceStyle.controlSize) }.help("Browse and search all images").accessibilityLabel("Browse images, page \(index + 1) of \(model.items.count)")
            icon("chevron.right", "Next image") { step(1) }.disabled(model.items.count < 2)
        }.buttonStyle(.plain).padding(3).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5))
    }
    func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(DiceStyle.control).frame(width: DiceStyle.controlSize,height: DiceStyle.controlSize).contentShape(Rectangle()) }.help(label).accessibilityLabel(label)
    }
    func flip() { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { metadata.toggle() } }
    @ViewBuilder func removalMenu(_ id: UUID) -> some View {
        Button("Remove from Dice") { model.remove(id) }.disabled(model.busy || model.importing)
        Button("Move Original to Trash") { model.trashOriginal(id) }.disabled(model.busy || model.importing)
        if let item = model.items.first(where: { $0.id == id }) { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.savedURL ?? item.url]) } }
    }
    /// Right-click menu on the start icon: where results go, and whether originals are replaced.
    var exportPopover: some View {
        let folderName = model.preferences.exportFolder.isEmpty ? "Choose a folder…" : URL(fileURLWithPath: model.preferences.exportFolder).lastPathComponent
        let rows: [(ExportAction, String, String, String)] = [
            (.beside, "square.and.arrow.down", "Save copies beside originals", "Next to each source file"),
            (.folder, "folder", "Save to folder", folderName),
            (.replace, "arrow.triangle.2.circlepath", "Replace originals", "Originals go to the Trash"),
            (.clipboard, "doc.on.clipboard", "Copy to clipboard", "Paste into any app"),
            (.edit, "pencil.and.outline", "Open to edit", "Opens results in your image editor"),
        ]
        return VStack(alignment: .leading, spacing: 2) {
            Text("Export").font(DiceStyle.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
            ForEach(rows, id: \.0) { action, symbol, title, detail in
                Button { exportPopoverPresented = false; imageSettingsPresented = false; model.process(action) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol).frame(width: 18).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.system(size: 13))
                            Text(detail).font(DiceStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider().padding(.vertical, 4)
            Button { exportPopoverPresented = false; model.chooseExportFolder() } label: {
                Text("Choose export folder…").font(DiceStyle.caption).padding(.horizontal, 10)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10).frame(width: 270)
    }
    var flattenColor: Binding<Color> {
        Binding(get: { let c = model.preferences.flattenColor + [1, 1, 1]; return Color(.sRGB, red: c[0], green: c[1], blue: c[2]) },
                set: { if let c = NSColor($0).usingColorSpace(.sRGB) { model.preferences.flattenColor = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)] } })
    }
    var appSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export defaults").font(DiceStyle.heading)
            Picker("When finished", selection: $model.preferences.exportMode) { ForEach(ExportMode.allCases) { Text($0.rawValue).tag($0) } }.tint(.primary)
            Toggle("Default export folder", isOn: $model.preferences.useExportFolder).disabled(model.preferences.exportMode == .clipboard)
            HStack {
                Text(model.preferences.exportFolder.isEmpty ? "Beside originals" : model.preferences.exportFolder).font(DiceStyle.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { model.chooseExportFolder() }.disabled(!model.preferences.useExportFolder)
            }
            Toggle("Default export format", isOn: $model.preferences.useExportFormat)
            Picker("Default format", selection: $model.preferences.exportFormat) {
                ForEach(OutputFormat.allCases.filter { $0 != .original }) { format in Text(format.rawValue).tag(format).disabled(!Engine.canEncode(format)) }
            }.tint(.primary).disabled(!model.preferences.useExportFormat)
            Picker("Default resize", selection: $model.preferences.defaultResize) { ForEach(ResizeMode.allCases.filter { $0 != .fit }) { Text($0.rawValue).tag($0) } }.tint(.primary)
            if model.preferences.defaultResize == .edge { HStack { Text("Longest edge"); number($model.preferences.defaultEdge); Text("px") } }
            if model.preferences.defaultResize == .percent { HStack { Text("Scale"); number($model.preferences.defaultPercent); Text("%") } }
            HStack { Text("Default quality"); Slider(value: $model.preferences.defaultQuality, in: 0.1...1); Text("\(Int(model.preferences.defaultQuality * 100))%").monospacedDigit() }
            Toggle("Remove personal metadata by default", isOn: $model.preferences.defaultStripMetadata).disabled(model.preferences.alwaysStripMetadata)
            HStack(spacing: 6) { Toggle("Always remove personal metadata", isOn: $model.preferences.alwaysStripMetadata); InfoTip("Removes metadata from every export and hides the option in image settings"); Spacer(minLength: 0) }
            HStack(spacing: 6) { Toggle("Replace originals by default", isOn: $model.preferences.defaultReplaceOriginals); InfoTip("Original goes to the Trash; PDFs, SVGs and multi-frame files are always saved as copies"); Spacer(minLength: 0) }
            Text("Defaults apply to newly opened images.").font(DiceStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider().padding(.vertical, 4)
            Text("Output").font(DiceStyle.heading)
            HStack(spacing: 6) {
                ColorPicker("Fill transparency with", selection: flattenColor, supportsOpacity: false)
                InfoTip("Used when an image with transparency is saved as JPEG or BMP, which have no alpha channel.")
                Text(Engine.hex(model.preferences.flattenColor)).font(DiceStyle.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) { Toggle("Keep animation when saving GIF", isOn: $model.preferences.keepAnimation); InfoTip("Animated GIFs stay animated when exported as GIF. Animated WebP and other animations can be read, but only GIF is written as an animation."); Spacer(minLength: 0) }
            Picker("Animated to other formats", selection: $model.preferences.framesAsFolder) {
                Text("Folder of frames").tag(true); Text("First frame only").tag(false)
            }.tint(.primary)
            HStack(spacing: 6) { Toggle("Keep the original when it's smaller", isOn: $model.preferences.keepSmallerOriginal); InfoTip("If re-encoding in the same format and size makes a file larger, Dice keeps the original's pixels instead. Personal metadata is still removed when that's on."); Spacer(minLength: 0) }
            HStack { Text("Filename suffix"); TextField("none", text: $model.preferences.fileSuffix).textFieldStyle(.roundedBorder).frame(width: 110); Spacer(minLength: 0) }
            Toggle("Close Dice when finished", isOn: $model.preferences.closeWhenDone)
            Divider().padding(.vertical, 4)
            Text("General").font(DiceStyle.heading)
            Toggle("Start at login", isOn: $model.preferences.startAtLogin)
            Toggle("Show in menu bar", isOn: $model.preferences.showInMenuBar)
            if model.preferences.showInMenuBar { Toggle("Drop images on the menu bar icon", isOn: $model.preferences.menuBarDrop).padding(.leading, 20) }
            Picker("Drag files to reveal a drop target", selection: $model.preferences.dragTarget) { ForEach(DragTarget.allCases) { Text($0.rawValue).tag($0) } }.tint(.primary)
            if (model.preferences.showInMenuBar && model.preferences.menuBarDrop) || model.preferences.dragTarget != .off { Toggle("Start right after a drop", isOn: $model.preferences.dropStartsImmediately) }
            Toggle("Stay on top of other apps", isOn: $model.preferences.stayOnTop)
            if FinderMenu.isAvailable {
                HStack(spacing: 6) {
                    Toggle("Show “Edit with Dice” in Finder's right-click menu", isOn: Binding(get: { finderMenu }, set: { finderMenu = $0; FinderMenu.setEnabled($0) }))
                    InfoTip("Adds or removes the item for images and PDFs. Finder may take a moment to update.")
                    Spacer(minLength: 0)
                }
            }
            Divider().padding(.vertical, 4)
            Text("Updates").font(DiceStyle.heading)
            Toggle("Automatically check for updates", isOn: $model.preferences.automaticallyCheckUpdates)
            Button("Check for updates…") { checkUpdates() }
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 2) {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                let year = Calendar.current.component(.year, from: Date())
                Text("Dice \(version)")
                Text("© \(String(year)) opyuii · open source under the MIT License")
                HStack(spacing: 10) {
                    Link("GitHub", destination: URL(string: "https://github.com/lumen-xx/dice")!)
                    Link("opyuii.com", destination: URL(string: "https://opyuii.com")!)
                }
            }.font(DiceStyle.caption).foregroundStyle(.secondary)
        }.font(DiceStyle.label).padding(DiceStyle.inset).frame(width: 380).tint(accent)
    }
    var imageSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image settings").font(DiceStyle.heading)
            Toggle("Metadata only", isOn: $model.options.metadataOnly)
            if !model.options.metadataOnly {
                Picker("Format", selection: $model.options.format) { ForEach(OutputFormat.allCases) { format in Text(format.rawValue).tag(format).disabled(!Engine.canEncode(format)) } }.tint(.primary)
                Picker("Resize", selection: $model.options.resize) { ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) } }.tint(.primary)
                if model.options.resize == .edge { HStack { Text("Longest edge"); number($model.options.edge); Text("px") } }
                if model.options.resize == .percent { HStack { Text("Scale"); number($model.options.percent); Text("%") } }
                if model.options.resize == .fit { HStack { number($model.options.width); Text("×"); number($model.options.height); Text("px") } }
                if model.options.resize != .original && !model.preferences.alwaysStripMetadata { HStack(spacing: 6) { Toggle("Resize only", isOn: $model.options.resizeOnly); InfoTip("Keep format and metadata; skip images already within the target size"); Spacer(minLength: 0) } }
                if usesQuality && !(model.options.resizeOnly && model.options.resize != .original && !model.preferences.alwaysStripMetadata) { compressionRow }
                if writesPNG { HStack(spacing: 6) { Toggle("Optimise PNG", isOn: $model.options.optimizePNG); InfoTip("Recompresses PNG files losslessly with oxipng: smaller files, identical pixels."); Spacer(minLength: 0) } }
                if model.options.format == .webp { Toggle("Lossless", isOn: $model.options.webpLossless) }
            }
            if !model.preferences.alwaysStripMetadata { Toggle("Remove personal metadata", isOn: $model.options.stripMetadata).disabled(model.options.metadataOnly) }
            Divider()
            HStack(spacing: 6) { Toggle("Replace originals", isOn: $model.options.replaceOriginals); InfoTip("Move each original to the Trash and save the result under its name. PDFs, SVGs and multi-frame files are always saved as copies."); Spacer(minLength: 0) }
        }.font(DiceStyle.label).padding(DiceStyle.inset).frame(width: 360).tint(accent)
            .disabled(model.busy || model.importing)
    }
    /// One row: the label is a menu switching between a quality slider and a target file size.
    var compressionRow: some View {
        HStack {
            Menu { Button("Quality") { model.options.useTargetSize = false }; Button("Target size") { model.options.useTargetSize = true } }
                label: { Text(model.options.useTargetSize ? "Target size" : "Quality") }
                .menuStyle(.borderlessButton).fixedSize().tint(.primary).help("Choose a quality, or a file size to fit")
            if model.options.useTargetSize {
                number($model.options.targetKB, label: "Target size in kilobytes"); Text("KB")
                InfoTip("Dice picks the highest quality that fits, and makes the image smaller only if even the lowest quality doesn't. 1 KB is 1000 bytes.")
                Spacer(minLength: 0)
            } else { Slider(value: $model.options.quality, in: 0.1...1); Text("\(Int(model.options.quality * 100))%").monospacedDigit() }
        }
    }
    var writesPNG: Bool { model.items.contains { model.options.format == .png || (model.options.format == .original && OutputFormat.matching(inputType: $0.info?.type ?? "").format == .png) } }
    /// "Same as original" only shows Quality when some image in the batch is written in a lossy format.
    var usesQuality: Bool { model.items.contains { model.options.format.usesQuality(forInputType: $0.info?.type ?? "") } }
    func number(_ binding: Binding<Int>, label: String = "Resize value") -> some View { TextField("", value: binding, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 65).accessibilityLabel(label) }
    func loadPreview() async {
        guard let item = model.selection, let url = displayedURL else { preview = nil; inspected = nil; previewError = nil; return }
        let id = item.id
        let page = item.result == nil ? item.page : 1
        let info = item.result == nil ? item.info : item.resultInfo
        let key = item.previewCacheKey
        inspected = info; previewError = nil
        if let image = model.previewCache.image(for: key) {
            preview = NSImage(cgImage: image, size: .zero); loadedPreviewKey = key
            return
        }
        // Keep the small batch thumbnail visible while a cold preview decodes.
        preview = item.thumbnail; loadedPreviewKey = key
        let cache = model.previewCache
        let loaded = await Task.detached(priority: .userInitiated) { () -> (CGImage?, ImageInfo?, String?) in
            autoreleasepool {
                do {
                    let image = try Engine.previewImage(url, maxPixelSize: 1200, page: page)
                    let metadata = try info ?? Engine.inspect(url, page: page)
                    cache.insert(image, for: key)
                    return (image, metadata, nil)
                } catch { return (nil, info, error.localizedDescription) }
            }
        }.value
        guard !Task.isCancelled, model.selected == id, displayedURL == url else { return }
        preview = loaded.0.map { NSImage(cgImage: $0, size: .zero) }; inspected = loaded.1; previewError = loaded.2
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
                                            Text(item.name).font(DiceStyle.label).lineLimit(1)
                                            if let info = item.info { Text("\(info.width) × \(info.height) · \(bytes(info.bytes))").font(DiceStyle.data).foregroundStyle(.secondary) }
                                            if let error = item.error { Text(error).font(DiceStyle.caption).foregroundStyle(.red).lineLimit(1) }
                                        }
                                        Spacer(minLength: 0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Open \(item.name)")
                                Button { model.remove(item.id) } label: { Image(systemName: "xmark").font(DiceStyle.caption).frame(width: 22,height: 26) }.buttonStyle(.plain).help("Remove from Dice; original stays in place").accessibilityLabel("Remove \(item.name)").disabled(model.busy || model.importing)
                            }.contextMenu { Button("Remove from Dice") { model.remove(item.id) }.disabled(model.busy || model.importing); Button("Move Original to Trash") { model.trashOriginal(item.id) }.disabled(model.busy || model.importing) }
                            .padding(8).background(item.id == model.selected ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
        }.padding(.horizontal, 16)
    }
}
final class DropURLs: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; storage.append(url) }
    var values: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

/// A small info icon whose explanation appears instantly on hover or click, instead of the delayed system tooltip.
struct InfoTip: View {
    let text: String
    init(_ text: String) { self.text = text }
    @State private var shown = false
    var body: some View {
        Image(systemName: "info.circle").font(DiceStyle.caption).foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { shown = $0 }
            .onTapGesture { shown.toggle() }
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(DiceStyle.caption).fixedSize(horizontal: false, vertical: true).frame(width: 220, alignment: .leading).padding(10)
            }
            .accessibilityLabel("More information").accessibilityHint(text)
    }
}

/// Reports right-clicks (and control-clicks) on top of a view while letting every other event through.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }
    final class CatcherView: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) { action() }
    }
}

/// Turns two-finger horizontal trackpad swipes over the window into previous/next steps.
struct SwipeCatcher: NSViewRepresentable {
    let onSwipe: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { let view = NSView(); context.coordinator.view = view; context.coordinator.start(); return view }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.onSwipe = onSwipe }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator {
        weak var view: NSView?
        var onSwipe: (Int) -> Void = { _ in }
        private var monitor: Any?
        private var travelled: CGFloat = 0
        private var fired = false
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.handle(event); return event }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        private func handle(_ event: NSEvent) {
            guard event.hasPreciseScrollingDeltas, event.momentumPhase == [], let window = view?.window, event.window === window else { return }
            if event.phase == .began || event.phase == .mayBegin { travelled = 0; fired = false }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
            // Fingers moving left → next image, whichever way the scrolling direction is set.
            travelled += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if !fired && abs(travelled) > 70 { fired = true; onSwipe(travelled < 0 ? 1 : -1) }
            if event.phase == .ended || event.phase == .cancelled { travelled = 0; fired = false }
        }
    }
}
