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
    /// The one solid accent: Start, switches, sliders, selection, menu icons. Indigo in light appearance;
    /// a lighter indigo (#8C96FF) in dark, so it stays readable on translucent popovers over dark or busy images.
    static let indigoLightRGB = (0.549, 0.588, 1.0)
    static let nsAccent = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? nsColor(indigoLightRGB) : nsColor(indigoRGB) }
    static let accent = Color(nsColor: nsAccent)
    static let nsAurora: [NSColor] = [mintRGB, cyanRGB, indigoRGB, violetRGB].map(nsColor)
    /// Closed loop for rings and the drop glow.
    static func auroraLoop(angle: Double = 0) -> AngularGradient { AngularGradient(colors: aurora + [mint], center: .center, angle: .degrees(angle)) }

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
