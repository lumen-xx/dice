import SwiftUI

/// Controls for Image settings: plain rows with a secondary label on the left and the value on the right, no
/// boxes or capsules. See "Image settings" in docs/STYLE_GUIDE.md.
enum Rows {
    static let height: CGFloat = 28
    static let label = Font.system(size: 13)
    static let value = Font.system(size: 13)
}

/// One row: label (with an optional tip), space, controls. The tip is drawn inside the panel, over the
/// neighbouring rows, so no second popover can close the first.
struct SettingRow<Label: View, Content: View>: View {
    var info: String?
    var tipAbove = false
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content
    @State private var tipShown = false
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                label.font(Rows.label).foregroundStyle(.secondary).lineLimit(1)
                if let info { RowTip(text: info, shown: $tipShown) }
            }
            Spacer(minLength: 8)
            content
        }.frame(minHeight: Rows.height)
            .overlay(alignment: tipAbove ? .bottomLeading : .topLeading) {
                if tipShown, let info { TipBubble(text: info).offset(y: tipAbove ? -(Rows.height + 2) : Rows.height + 2) }
            }
            .zIndex(tipShown ? 1 : 0)
    }
}

/// The info symbol beside a row's label: hover (or click) to show the tip.
struct RowTip: View {
    let text: String
    @Binding var shown: Bool
    var body: some View {
        Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.tertiary)
            .frame(width: 16, height: 16).contentShape(Rectangle())
            .onHover { shown = $0 }
            .onTapGesture { shown.toggle() }
            .accessibilityElement().accessibilityLabel("More information").accessibilityHint(text)
            .accessibilityAddTraits(.isButton).accessibilityAction { shown.toggle() }
    }
}

/// A small explanation over the panel.
struct TipBubble: View {
    let text: String
    var body: some View {
        Text(text).font(DiceStyle.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 8).frame(width: 264, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension SettingRow where Label == Text {
    init(_ title: String, info: String? = nil, tipAbove: Bool = false, @ViewBuilder content: () -> Content) { self.info = info; self.tipAbove = tipAbove; self.label = Text(title); self.content = content() }
}

/// A value that opens a menu: plain text with a small up-down chevron.
struct ValueMenu<Items: View>: View {
    let label: String
    let value: String
    /// For a menu that acts as a row's label (Quality or Target size).
    var secondary = false
    @ViewBuilder var items: Items
    var body: some View {
        Menu { items } label: {
            HStack(spacing: 5) {
                Text(value).font(Rows.value).foregroundStyle(secondary ? .secondary : .primary).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(label).accessibilityValue(value)
    }
}

/// A bare symbol button. When `on`, it sits on a soft round fill.
struct SymbolButton: View {
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .regular))
                .foregroundStyle(on ? .primary : .secondary)
                .frame(width: 26, height: 24)
                .background(Circle().fill(Color.primary.opacity(on ? 0.14 : 0)).frame(width: 24, height: 24))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(label)
            .accessibilityLabel(label).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A number with its unit, right-aligned on a faint field.
struct NumberValue: View {
    @Binding var value: Int
    let label: String
    var unit: String?
    var width: CGFloat = 44
    var body: some View {
        HStack(spacing: 3) {
            TextField("", value: $value, format: .number.grouping(.never)).textFieldStyle(.plain)
                .font(Rows.value.monospacedDigit()).multilineTextAlignment(.trailing)
                .frame(width: width).padding(.horizontal, 6).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                .accessibilityLabel(label)
            if let unit { Text(unit).font(Rows.value).foregroundStyle(.secondary) }
        }
    }
}

/// A monochrome switch: on is a solid primary track with a knob in the background colour (white on black in
/// light appearance, black on white in dark); off is a faint track with a white knob.
struct RowSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(label, isOn: $isOn).labelsHidden().toggleStyle(MonoSwitch())
    }
}
struct MonoSwitch: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) { configuration.isOn.toggle() } } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Color.primary.opacity(0.9) : Color.primary.opacity(0.14))
                Circle().fill(configuration.isOn ? AnyShapeStyle(.background) : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(configuration.isOn ? 0 : 0.25), radius: 1, y: 0.5)
                    .padding(2)
            }.frame(width: 30, height: 17).contentShape(Capsule())
        }.buttonStyle(.plain).opacity(isEnabled ? 1 : 0.4)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A titled group of rows in App settings.
struct SettingSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary).padding(.bottom, 4)
            content
        }
    }
}
