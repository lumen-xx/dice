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
    /// With "Fit photos to the window", an opaque photo fills the window behind the controls. Transparent images
    /// and documents (SVG, PDF, Illustrator) keep the inset layout.
    var fillsWindow: Bool {
        guard model.preferences.fitToWindow, !model.busy, let item = model.selection, let key = previewKey, let preview = displayedPreview else { return false }
        if DocumentImage.isDocument(item.url) || displayedURL.map(DocumentImage.isDocument) == true { return false }
        return PreviewFill.isOpaque(preview, key: key)
    }
    var currentInfo: ImageInfo? {
        let known = model.selection?.result == nil ? model.selection?.info : model.selection?.resultInfo
        return known ?? (previewKey == loadedPreviewKey ? inspected : nil)
    }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if model.settingsPresented {
                ScrollView { appSettingsPanel.frame(maxWidth: .infinity) }.scrollIndicators(.never)
                    .padding(.top, 64).padding(.bottom, 16)
            } else if batch {
                BatchPane(model: model, query: $batchSearch) { id in model.selected = id; batch = false }
                    .padding(.top, 64).padding(.bottom, model.items.isEmpty ? 16 : 58)
            } else if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "die.face.5").font(DiceStyle.emptySymbol).foregroundStyle(.secondary)
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
                        if fillsWindow {
                            Color.clear.overlay { Image(nsImage: preview).resizable().scaledToFill() }.clipped()
                                .contextMenu { if let id = model.selected { removalMenu(id) } }
                        } else {
                            Image(nsImage: preview).resizable().scaledToFit().padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 52)
                                .contextMenu { if let id = model.selected { removalMenu(id) } }
                        }
                    } else if let error = previewError {
                        Text(error).font(DiceStyle.caption).foregroundStyle(.secondary).padding(30)
                    } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
            }
            toolbar.padding(DiceStyle.inset).padding(.leading, metadata || batch || model.settingsPresented ? 56 : 0)
            if !model.items.isEmpty && !model.settingsPresented {
                VStack { Spacer(); HStack(spacing: 12) { footerSummary.modifier(OverPhoto(active: fillsWindow && !metadata && !batch)); Spacer(minLength: 12); pager }.padding(DiceStyle.inset) }
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
                Text("\(info.width) × \(info.height) · \(info.value("FileType") ?? "Image")\(info.isHDR ? " HDR" : "") · \(bytes(info.bytes))")
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
        VStack(alignment: .leading, spacing: 24) {
            SettingSection("New images") {
                SettingRow("Format") {
                    ValueMenu(label: "Default format", value: defaultFormat.wrappedValue == .original ? "Same as original" : defaultFormat.wrappedValue.rawValue) {
                        Picker("Default format", selection: defaultFormat) {
                            Text(OutputFormat.original.rawValue).tag(OutputFormat.original)
                            Divider()
                            ForEach(Self.formatOrder, id: \.self) { f in Text(f.rawValue).tag(f).disabled(!Engine.canEncode(f)) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                }
                SettingRow("Quality") {
                    Slider(value: $model.preferences.defaultQuality, in: 0.1...1).controlSize(.mini).frame(width: 140).accessibilityLabel("Default quality")
                    Text("\(Int(model.preferences.defaultQuality * 100))%").font(Rows.value.monospacedDigit()).frame(width: 36, alignment: .trailing)
                }
                SettingRow("Size") {
                    if model.preferences.defaultResize == .edge { NumberValue(value: $model.preferences.defaultEdge, label: "Longest edge", unit: "px") }
                    if model.preferences.defaultResize == .percent { NumberValue(value: $model.preferences.defaultPercent, label: "Scale", unit: "%") }
                    ValueMenu(label: "Default size", value: Self.shortName(model.preferences.defaultResize)) {
                        Picker("Default size", selection: $model.preferences.defaultResize) { ForEach([ResizeMode.original, .edge, .percent]) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden()
                    }
                }
                SettingRow("Metadata", info: "Remove takes all metadata out except the colour profile, and you can still keep it per batch. Always remove does it for every export and hides the choice in Image settings.") {
                    ValueMenu(label: "Default metadata", value: ["Keep", "Remove", "Always remove"][defaultMetadata.wrappedValue]) {
                        Picker("Default metadata", selection: defaultMetadata) { Text("Keep").tag(0); Text("Remove").tag(1); Divider(); Text("Always remove").tag(2) }.pickerStyle(.inline).labelsHidden()
                    }
                }
                SettingRow("Replace originals", info: "Originals go to the Trash and the result takes their name. PDFs, SVGs and multi-frame files are always saved as copies.") {
                    RowSwitch(label: "Replace originals by default", isOn: $model.preferences.defaultReplaceOriginals)
                }
            }
            SettingSection("Saving") {
                SettingRow("When finished") {
                    ValueMenu(label: "When finished", value: model.preferences.exportMode.rawValue) {
                        Picker("When finished", selection: $model.preferences.exportMode) { ForEach(ExportMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden()
                    }
                }
                if model.preferences.exportMode == .save {
                    SettingRow("Save to") {
                        ValueMenu(label: "Save to", value: model.preferences.useExportFolder && !model.preferences.exportFolder.isEmpty ? URL(fileURLWithPath: model.preferences.exportFolder).lastPathComponent : "Beside originals") {
                            Picker("Save to", selection: $model.preferences.useExportFolder) {
                                Text("Beside originals").tag(false)
                                if !model.preferences.exportFolder.isEmpty { Text(URL(fileURLWithPath: model.preferences.exportFolder).lastPathComponent).tag(true) }
                            }.pickerStyle(.inline).labelsHidden()
                            Divider()
                            Button("Choose folder…") { model.chooseExportFolder() }
                        }.help(model.preferences.useExportFolder ? model.preferences.exportFolder : "Each result is saved in its original's folder")
                    }
                    SettingRow("File name", info: "{name} is the original name, {n} the image's number in the batch (01, 02…), {date} today's date. Replace originals keeps the original name.") {
                        TextField("{name}-dice", text: $model.preferences.namePattern).textFieldStyle(.plain).font(Rows.value).multilineTextAlignment(.trailing)
                            .frame(width: 130).padding(.horizontal, 6).frame(height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                            .accessibilityLabel("File name")
                    }
                }
                SettingRow("Close Dice when finished") { RowSwitch(label: "Close Dice when finished", isOn: $model.preferences.closeWhenDone) }
            }
            SettingSection("Conversion") {
                SettingRow("Keep animations", info: "Animated images stay animated when saved as GIF, PNG (APNG), WebP or HEIC.") {
                    RowSwitch(label: "Keep animations", isOn: $model.preferences.keepAnimation)
                }
                SettingRow("Animations in other formats") {
                    ValueMenu(label: "Animations in other formats", value: model.preferences.framesAsFolder ? "Folder of frames" : "First frame") {
                        Picker("Animations in other formats", selection: $model.preferences.framesAsFolder) { Text("Folder of frames").tag(true); Text("First frame only").tag(false) }.pickerStyle(.inline).labelsHidden()
                    }
                }
                SettingRow("JPEG background", info: "JPEG and BMP have no transparency, so transparent areas are filled with this colour.") {
                    Text(Engine.hex(model.preferences.flattenColor)).font(Rows.value.monospacedDigit()).foregroundStyle(.secondary)
                    ColorPicker("JPEG background colour", selection: flattenColor, supportsOpacity: false).labelsHidden().controlSize(.mini)
                }
                SettingRow("Keep the original when it's smaller", info: "If re-encoding in the same format and size makes a file larger, Dice keeps the original's pixels instead. Metadata is still removed when that's on.") {
                    RowSwitch(label: "Keep the original when it's smaller", isOn: $model.preferences.keepSmallerOriginal)
                }
            }
            SettingSection("Window") {
                SettingRow("Fit photos to the window", info: "Photos fill the whole window, edge to edge, behind the controls; edges that don't fit are hidden in the preview only. Transparent images, SVGs and PDFs keep their margins.") {
                    RowSwitch(label: "Fit photos to the window", isOn: $model.preferences.fitToWindow)
                }
                SettingRow("Stay on top of other apps") { RowSwitch(label: "Stay on top of other apps", isOn: $model.preferences.stayOnTop) }
            }
            SettingSection("System") {
                SettingRow("Start at login") { RowSwitch(label: "Start at login", isOn: $model.preferences.startAtLogin) }
                SettingRow("Show in menu bar") { RowSwitch(label: "Show in menu bar", isOn: $model.preferences.showInMenuBar) }
                if model.preferences.showInMenuBar {
                    SettingRow("Drop images on the menu bar icon") { RowSwitch(label: "Drop images on the menu bar icon", isOn: $model.preferences.menuBarDrop) }.padding(.leading, 14)
                }
                SettingRow("Drop target while dragging", info: "Dragging files anywhere reveals a small drop target in this screen corner.") {
                    ValueMenu(label: "Drop target while dragging", value: model.preferences.dragTarget.rawValue) {
                        Picker("Drop target while dragging", selection: $model.preferences.dragTarget) { ForEach(DragTarget.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden()
                    }
                }
                if (model.preferences.showInMenuBar && model.preferences.menuBarDrop) || model.preferences.dragTarget != .off {
                    SettingRow("Start right after a drop") { RowSwitch(label: "Start right after a drop", isOn: $model.preferences.dropStartsImmediately) }
                }
                if FinderMenu.isAvailable {
                    SettingRow("“Edit with Dice” in Finder", info: "Adds or removes the item in Finder's right-click menu for images and PDFs. Finder may take a moment to update.") {
                        RowSwitch(label: "Edit with Dice in Finder", isOn: Binding(get: { finderMenu }, set: { finderMenu = $0; FinderMenu.setEnabled($0) }))
                    }
                }
            }
            SettingSection("Updates") {
                SettingRow("Check automatically") { RowSwitch(label: "Check for updates automatically", isOn: $model.preferences.automaticallyCheckUpdates) }
                SettingRow("Check now") { Button("Check for updates…") { checkUpdates() }.buttonStyle(.plain).font(Rows.value) }
            }
            VStack(alignment: .leading, spacing: 2) {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                let year = Calendar.current.component(.year, from: Date())
                Text("Dice \(version) · © \(String(year)) opyuii · MIT License")
                HStack(spacing: 10) {
                    Link("GitHub", destination: URL(string: "https://github.com/lumen-xx/dice")!)
                    Link("opyuii.com", destination: URL(string: "https://opyuii.com")!)
                }
            }.font(DiceStyle.caption).foregroundStyle(.tertiary).tint(.secondary)
        }.padding(DiceStyle.inset).frame(width: 380).tint(.primary)
    }
    static func shortName(_ mode: ResizeMode) -> String {
        switch mode { case .original: "Original"; case .edge: "Longest edge"; case .percent: "Scale"; case .fit: "Fit"; case .width: "Width"; case .height: "Height"; case .fill: "Fill" }
    }
    /// "Same as original" turns the default format off; any other choice turns it on.
    var defaultFormat: Binding<OutputFormat> {
        Binding(get: { model.preferences.useExportFormat ? model.preferences.exportFormat : .original },
                set: { if $0 == .original { model.preferences.useExportFormat = false } else { model.preferences.useExportFormat = true; model.preferences.exportFormat = $0 } })
    }
    /// Keep, remove by default, or always remove (which hides the choice in Image settings).
    var defaultMetadata: Binding<Int> {
        Binding(get: { model.preferences.alwaysStripMetadata ? 2 : model.preferences.defaultStripMetadata ? 1 : 0 },
                set: { model.preferences.alwaysStripMetadata = $0 == 2; model.preferences.defaultStripMetadata = $0 != 0 })
    }
    var imageSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow("Format", info: "Same as original keeps each file's format. Metadata only changes the metadata without re-encoding, so pixels stay identical. Formats Dice can't write on this Mac are greyed out.") {
                ValueMenu(label: "Format", value: formatValue) {
                    Picker("Format", selection: Binding(get: { model.options.metadataOnly ? nil : model.options.format }, set: { if let f = $0 { model.options.metadataOnly = false; model.options.format = f } })) {
                        Text(OutputFormat.original.rawValue).tag(OutputFormat?.some(.original))
                        Divider()
                        ForEach(Self.formatOrder, id: \.self) { f in Text(f.rawValue).tag(OutputFormat?.some(f)).disabled(!Engine.canEncode(f)) }
                    }.pickerStyle(.inline).labelsHidden()
                    Divider()
                    Toggle("Metadata only", isOn: $model.options.metadataOnly)
                    if !model.options.metadataOnly {
                        if model.options.format.hasLosslessMode { Toggle("Lossless", isOn: $model.options.webpLossless) }
                        if writesPNG { Toggle("Optimise PNG", isOn: $model.options.optimizePNG) }
                        if model.options.format == .pdf && model.items.count > 1 { Toggle("Combine into one PDF", isOn: $model.options.combinePDF) }
                        Toggle("Convert to sRGB", isOn: $model.options.convertToSRGB)
                        if batchHasHDR { Toggle("Keep HDR", isOn: $model.options.keepHDR) }
                    }
                }
            }
            if !model.options.metadataOnly {
                if showsCompression {
                    SettingRow(info: model.options.useTargetSize ? "Dice picks the highest quality that fits the size, and makes the image smaller only if even the lowest quality doesn't. 1 KB is 1000 bytes." : "Higher means more detail and bigger files. 80–90% is hard to tell from the original for photos.") {
                        ValueMenu(label: "Compression", value: model.options.useTargetSize ? "Target size" : "Quality", secondary: true) {
                            Picker("Compression", selection: $model.options.useTargetSize) { Text("Quality").tag(false); Text("Target size").tag(true) }.pickerStyle(.inline).labelsHidden()
                        }
                    } content: {
                        if model.options.useTargetSize {
                            NumberValue(value: $model.options.targetKB, label: "Target size in kilobytes", unit: "KB", width: 52)
                        } else {
                            Slider(value: $model.options.quality, in: 0.1...1).controlSize(.mini).frame(width: 120).accessibilityLabel("Quality")
                            Text("\(Int(model.options.quality * 100))%").font(Rows.value.monospacedDigit()).frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                SettingRow("Size", info: "Fit keeps the whole image inside the box. Fill covers the box and crops the overflow from the centre. Photos aren't enlarged unless you turn on Allow enlarging in this menu; SVGs and PDFs always render at the size you ask for.") {
                    switch model.options.resize {
                    case .original: EmptyView()
                    case .edge: NumberValue(value: $model.options.edge, label: "Longest edge", unit: "px")
                    case .percent: NumberValue(value: $model.options.percent, label: "Scale", unit: "%")
                    case .width: NumberValue(value: $model.options.width, label: "Width", unit: "px")
                    case .height: NumberValue(value: $model.options.height, label: "Height", unit: "px")
                    case .fit, .fill:
                        NumberValue(value: $model.options.width, label: "Width", width: 40)
                        Text("×").font(Rows.value).foregroundStyle(.secondary)
                        NumberValue(value: $model.options.height, label: "Height", width: 40)
                    }
                    ValueMenu(label: "Size", value: sizeValue) {
                        Picker("Size", selection: $model.options.resize) { ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline).labelsHidden()
                        Divider()
                        if model.options.resize != .original {
                            Toggle("Allow enlarging", isOn: $model.options.upscale)
                            if !model.preferences.alwaysStripMetadata { Toggle("Resize only (keep format and metadata)", isOn: $model.options.resizeOnly) }
                        }
                        Toggle("Also save @2x and @1x", isOn: $model.options.scaleSet)
                        if model.items.contains(where: { DocumentImage.kind($0.url) == .pdf }) {
                            Picker("PDF resolution", selection: $model.options.pdfDPI) { ForEach([72, 144, 300, 600], id: \.self) { Text("\($0) dpi").tag($0) } }
                        }
                    }
                }
                SettingRow("Rotate") {
                    if model.options.normalizedRotation != 0 { Text("\(model.options.normalizedRotation)°").font(Rows.value.monospacedDigit()).foregroundStyle(.secondary).fixedSize() }
                    HStack(spacing: 0) {
                        SymbolButton(symbol: "rotate.left", label: "Rotate anticlockwise") { model.options.rotation = (model.options.normalizedRotation + 270) % 360 }
                        SymbolButton(symbol: "rotate.right", label: "Rotate clockwise") { model.options.rotation = (model.options.normalizedRotation + 90) % 360 }
                        SymbolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip horizontally", on: model.options.flipHorizontal) { model.options.flipHorizontal.toggle() }
                        SymbolButton(symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", label: "Flip vertically", on: model.options.flipVertical) { model.options.flipVertical.toggle() }
                    }.padding(.trailing, -5)
                }
                SettingRow("Crop", info: "Crops to the aspect ratio around the centre, after rotating and before resizing.") {
                    ValueMenu(label: "Crop", value: model.options.crop == .none ? "None" : model.options.crop.rawValue) {
                        Picker("Crop", selection: $model.options.crop) { ForEach(CropAspect.allCases) { Text($0 == .none ? "None" : $0.rawValue + " (centred)").tag($0) } }.pickerStyle(.inline).labelsHidden()
                    }
                }
            }
            SettingRow("Metadata", info: "Remove location takes out GPS and place names and keeps the rest. Remove all strips camera details, GPS, dates, captions and maker notes; only the colour profile stays, so colours still display correctly.") {
                if model.preferences.alwaysStripMetadata {
                    Text("Always removed").font(Rows.value).foregroundStyle(.secondary).help("Set in App settings. All metadata except the colour profile is removed.")
                } else {
                    ValueMenu(label: "Metadata", value: ["Keep", "Remove location", "Remove all"][metadataChoice.wrappedValue]) {
                        Picker("Metadata", selection: metadataChoice) {
                            Text("Keep").tag(0).disabled(model.options.metadataOnly); Text("Remove location").tag(1); Text("Remove all (keeps the colour profile)").tag(2)
                        }.pickerStyle(.inline).labelsHidden()
                    }
                }
            }
            Divider().padding(.vertical, 6)
            if !model.options.metadataOnly {
                SettingRow("Remove background", info: "Best on photos with a clear subject: people, pets, products. Runs on this Mac; nothing is uploaded. Needs a format with transparency, so Same as original saves JPEG and BMP as PNG. Images without a clear subject aren't saved.", tipAbove: true) { RowSwitch(label: "Remove background", isOn: $model.options.removeBackground) }
            }
            SettingRow("Replace originals", info: "Moves each original to the Trash and saves the result under its name, so you can still restore it. PDFs, SVGs and multi-frame files are always saved as copies.", tipAbove: true) { RowSwitch(label: "Replace originals", isOn: $model.options.replaceOriginals) }
        }.padding(.horizontal, 18).padding(.vertical, 14).frame(width: 300).tint(.primary)
            .disabled(model.busy || model.importing)
    }
    /// Everyday formats first, then the specialised ones.
    static let formatOrder: [OutputFormat] = [.jpeg, .png, .heic, .webp, .avif, .jxl, .gif, .tiff, .bmp, .ico, .icns, .pdf]
    var formatValue: String {
        let o = model.options
        if o.metadataOnly { return "Metadata only" }
        var parts = [o.format == .original ? "Original" : o.format.rawValue]
        if o.format.hasLosslessMode && o.webpLossless { parts.append("Lossless") }
        if o.convertToSRGB { parts.append("sRGB") }
        if !o.keepHDR && batchHasHDR { parts.append("SDR") }
        if o.format == .pdf && o.combinePDF && model.items.count > 1 { parts.append("One file") }
        return parts.joined(separator: " · ")
    }
    var sizeValue: String { Self.shortName(model.options.resize) + (model.options.scaleSet ? " · @1–3x" : "") }
    var showsCompression: Bool {
        usesQuality && !(model.options.format.hasLosslessMode && model.options.webpLossless)
            && !(model.options.resizeOnly && model.options.resize != .original && !model.preferences.alwaysStripMetadata)
    }
    /// Keep, location only (GPS and place names), or all metadata except the colour profile.
    var metadataChoice: Binding<Int> {
        Binding(get: { !model.options.stripMetadata ? 0 : model.options.removeLocationOnly ? 1 : 2 },
                set: { model.options.stripMetadata = $0 != 0; model.options.removeLocationOnly = $0 == 1 })
    }
    var batchHasHDR: Bool { model.items.contains { $0.info?.isHDR == true } }
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

/// Over a full-window photo, the footer text gets the same capsule material as the toolbar so it stays readable.
struct OverPhoto: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.padding(.horizontal, 12).frame(height: 30)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5))
        } else { content }
    }
}
