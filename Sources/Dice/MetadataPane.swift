import SwiftUI
import AppKit
import DiceCore

struct MetadataPane: View {
    let info: ImageInfo?
    @State private var search = ""
    @State private var group = "All"
    @State private var selected: MetadataRow.ID?

    private var rows: [MetadataRow] {
        (info?.rows ?? []).filter {
            (group == "All" || $0.group == group) &&
            (search.isEmpty || "\($0.group) \($0.name) \($0.value)".localizedCaseInsensitiveContains(search))
        }
    }
    private var groups: [String] { Array(Set((info?.rows ?? []).map(\.group))).sorted() }
    private var visibleGroups: [String] { groups.filter { name in rows.contains { $0.group == name } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info {
                HStack(spacing: 6) {
                    Text("\(info.width) × \(info.height)").monospacedDigit()
                    Text("·")
                    Text(info.value("FileType") ?? "Image")
                    Text("·")
                    Text(bytes(info.bytes))
                    Spacer()
                    if info.hasGPS { Image(systemName: "location.fill").help("GPS metadata found") }
                    Text("\(rows.count) tags")
                }.font(DiceStyle.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search metadata", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear metadata search")
                    }
                }
                .font(DiceStyle.body).padding(.horizontal, 12).frame(height: 36)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                Menu {
                    Button("All groups") { group = "All" }
                    Divider()
                    ForEach(groups, id: \.self) { name in Button(name) { group = name } }
                } label: {
                    HStack(spacing: 5) {
                        Text(group == "All" ? "All groups" : group).lineLimit(1)
                        Image(systemName: "chevron.down").font(DiceStyle.caption)
                    }.foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .font(DiceStyle.body).tint(.secondary).accessibilityLabel("Filter metadata group: \(group)")
            }
            if rows.isEmpty {
                Text(info == nil ? "Reading metadata…" : "No matching tags")
                    .font(DiceStyle.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visibleGroups, id: \.self) { name in
                                Text(name).font(DiceStyle.caption).foregroundStyle(.tertiary)
                                    .padding(.top, 14).padding(.bottom, 6).padding(.horizontal, 8)
                                ForEach(rows.filter { $0.group == name }) { row in
                                    tag(row, labelWidth: max(130, geometry.size.width * 0.4))
                                }
                            }
                        }.padding(.bottom, 8)
                    }.scrollIndicators(.automatic)
                }
            }
        }.padding(.horizontal, DiceStyle.inset)
    }

    private func tag(_ row: MetadataRow, labelWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selected = selected == row.id ? nil : row.id
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.name).font(DiceStyle.metadataName).foregroundStyle(.primary)
                        .lineLimit(1).frame(width: labelWidth, alignment: .leading)
                    Text(row.value).font(DiceStyle.data).foregroundStyle(.secondary)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 8).padding(.vertical, 9).contentShape(Rectangle())
            }.buttonStyle(.plain).help("\(row.name): \(row.value)")
                .accessibilityLabel("\(row.name), \(row.value)")
                .accessibilityHint("Show or hide the full value")
            if selected == row.id {
                Text(row.value).font(DiceStyle.data).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
        .background(.primary.opacity(selected == row.id ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.045)).frame(height: 0.5).padding(.horizontal, 8) }
        .contextMenu {
            Button("Copy value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.value, forType: .string)
            }
        }
    }
}
