import SwiftUI
import AppKit
import ImageIO
import DiceCore

private let accent = Color(red: 0.96, green: 0.35, blue: 0.10)
struct DiceView: View {
    @ObservedObject var model: DiceModel
    @State private var metadata = false
    @State private var settings = false
    @State private var preview: NSImage?
    @State private var inspected: ImageInfo?
    @State private var previewError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var displayedURL: URL? { model.selection?.result?.url ?? model.selection?.url }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if metadata {
                MetadataPane(info: inspected, model: model).padding(.top, 51)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    if let preview {
                        Image(nsImage: preview).resizable().scaledToFit().padding(.horizontal, 20).padding(.top, 54).padding(.bottom, 20)
                    } else if let error = previewError {
                        Text(error).font(.caption).foregroundStyle(.secondary).padding(30)
                    } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
            }
            toolbar.padding(12)

        }
        .frame(minWidth: 430, minHeight: 340)
        .tint(accent)
        .task(id: displayedURL) { await loadPreview() }
        .alert("Dice couldn’t finish", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) { Button("OK") { model.alert = nil } } message: { Text(model.alert ?? "") }
    }
    var index: Int { model.items.firstIndex { $0.id == model.selected } ?? 0 }
    func step(_ direction: Int) { guard !model.items.isEmpty else { return }; model.selected = model.items[(index + direction + model.items.count) % model.items.count].id }
    var toolbar: some View {
        HStack(spacing: 2) {
            if metadata {
                icon("arrow.left", "Back to image") { flip() }
                Spacer(minLength: 10)
                Text("Metadata").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let info = inspected { Menu { Button("Copy all tags") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info.rows.map { "[\($0.group)] \($0.name): \($0.value)" }.joined(separator: "\n"), forType: .string) }; Button("Export JSON…") { model.exportMetadata(info) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().padding(7) }
            } else {
                if model.items.count > 1 {
                    Menu {
                        ForEach(model.items) { item in Button(item.url.lastPathComponent) { model.selected = item.id } }
                    } label: { Text("\(index + 1)/\(model.items.count)").font(.system(size: 10, design: .monospaced)) }.menuStyle(.borderlessButton).fixedSize().padding(7)
                }
                if model.busy || model.importing { ProgressView().controlSize(.mini).padding(.horizontal, 8) }
                icon("info", "View metadata") { flip() }.disabled(inspected == nil)
                icon("slider.horizontal.3", "Conversion settings") { settings.toggle() }
                    .popover(isPresented: $settings, arrowEdge: .bottom) { optionsPanel }
                icon("arrow.down", "Process and save a copy") { model.process(andSave: true) }.disabled(model.busy || model.importing || model.items.isEmpty)
            }
            icon("xmark", "Close") { NSApp.keyWindow?.close() }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 0.5))
        .frame(maxWidth: metadata ? .infinity : nil)
    }
    func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 27,height: 27).contentShape(Rectangle()) }.help(label).accessibilityLabel(label)
    }
    func flip() { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { metadata.toggle() } }
    var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image settings").font(.system(size: 12, weight: .semibold))
            Toggle("Metadata only", isOn: $model.options.metadataOnly).font(.caption)
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
            Text(model.options.metadataOnly ? "Pixels stay unchanged. Colour and orientation are retained." : "Copies only. No upscaling. PNG is lossless; JPEG transparency becomes white.").font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Apply") { settings = false; model.process() }.buttonStyle(.borderedProminent).disabled(model.busy || model.importing) }
        }.font(.system(size: 11)).padding(16).frame(width: 275).tint(accent).disabled(model.busy || model.importing)
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
struct MetadataPane: View {
    let info: ImageInfo?
    @ObservedObject var model: DiceModel
    @State private var search = ""
    @State private var group = "All"
    @State private var selected: MetadataRow.ID?
    var rows: [MetadataRow] { (info?.rows ?? []).filter { (group == "All" || $0.group == group) && (search.isEmpty || "\($0.group) \($0.name) \($0.value)".localizedCaseInsensitiveContains(search)) } }
    var groups: [String] { ["All"] + Array(Set((info?.rows ?? []).map(\.group))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let info {
                HStack(spacing: 8) {
                    Text("\(info.width) × \(info.height)").monospaced()
                    Text(info.value("FileType") ?? "Image")
                    Text(bytes(info.bytes))
                    Spacer()
                    if info.hasGPS { Image(systemName: "location.fill").foregroundStyle(accent).help("GPS metadata found") }
                    Text("\(info.rows.count) tags")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                if let camera = info.camera { Text(camera).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                TextField("Search metadata", text: $search).textFieldStyle(.roundedBorder)
                Picker("Group", selection: $group) { ForEach(groups,id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 110)
            }.controlSize(.small)
            Table(rows, selection: $selected) {
                TableColumn("Tag") { row in VStack(alignment: .leading, spacing: 2) { Text(row.name).font(.system(size: 10, weight: .medium)); Text(row.group).font(.system(size: 8)).foregroundStyle(.secondary) } }.width(min: 120, ideal: 155, max: 210)
                TableColumn("Value") { row in Text(row.value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).help(row.value).contextMenu { Button("Copy value") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.value, forType: .string) } } }
            }.scrollContentBackground(.hidden)
            if let row = rows.first(where: { $0.id == selected }) {
                ScrollView { Text(row.value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 46)
            }
        }.padding(.horizontal, 16).padding(.bottom, 14)
    }
}
