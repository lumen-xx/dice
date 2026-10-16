import SwiftUI
import AppKit

/// Shared visual vocabulary. See docs/STYLE_GUIDE.md.
enum DiceStyle {
    // Aurora palette, from the drop glow: mint → cyan → indigo → violet. sRGB; scripts/icon.swift repeats these values.
    static let mintRGB = (0.204, 0.898, 0.722)     // #34E5B8
    static let cyanRGB = (0.169, 0.769, 0.949)     // #2BC4F2
    static let indigoRGB = (0.369, 0.420, 1.0)     // #5E6BFF
    static let violetRGB = (0.651, 0.361, 1.0)     // #A65CFF
    static let mint = color(mintRGB), cyan = color(cyanRGB), indigo = color(indigoRGB), violet = color(violetRGB)
    static let aurora: [Color] = [mint, cyan, indigo, violet]
    /// The one solid accent: control tints, selection, menu icons. Indigo keeps 4:1 contrast on light and dark surfaces.
    static let accent = indigo
    static let nsAccent = nsColor(indigoRGB)
    static let nsAurora: [NSColor] = [mintRGB, cyanRGB, indigoRGB, violetRGB].map(nsColor)
    /// Start's fill: the darker half of the aurora, so the white glyph stays legible.
    static let startFill = LinearGradient(colors: [indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Closed loop for rings and the drop glow.
    static func auroraLoop(angle: Double = 0) -> AngularGradient { AngularGradient(colors: aurora + [mint], center: .center, angle: .degrees(angle)) }
    static let auroraMark = LinearGradient(colors: aurora, startPoint: .topLeading, endPoint: .bottomTrailing)

    static let title = Font.system(size: 16, weight: .semibold)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let label = Font.system(size: 12, weight: .medium)
    static let metadataName = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let data = Font.system(size: 11, design: .monospaced)
    static let emptySymbol = Font.system(size: 44, weight: .light)
    static let control = Font.system(size: 14, weight: .medium)
    static let page = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let inset: CGFloat = 16
    static let controlSize: CGFloat = 30
    static let cornerRadius: CGFloat = 14

    private static func color(_ c: (Double, Double, Double)) -> Color { Color(.sRGB, red: c.0, green: c.1, blue: c.2) }
    private static func nsColor(_ c: (Double, Double, Double)) -> NSColor { NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1) }
}

/// The primary action: an indigo-to-violet disc with a fine aurora rim. Increased contrast drops the gradient for solid indigo.
struct StartGlyph: View {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            if contrast == .increased { Circle().fill(DiceStyle.accent) }
            else { Circle().fill(DiceStyle.startFill); Circle().strokeBorder(DiceStyle.auroraLoop(), lineWidth: 1.25) }
            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).offset(x: 1)
        }
        .frame(width: 24, height: 24)
        .saturation(enabled ? 1 : 0).opacity(enabled ? 1 : 0.4)
    }
}

/// Determinate progress in the aurora loop. Moves only when `fraction` changes.
struct AuroraProgress: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: 4)
            Circle().trim(from: 0, to: max(0.03, min(1, fraction)))
                .stroke(DiceStyle.auroraLoop(), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 44, height: 44)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        .accessibilityElement().accessibilityLabel("Progress").accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
