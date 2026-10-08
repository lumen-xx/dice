import SwiftUI

/// Shared visual vocabulary. See docs/STYLE_GUIDE.md.
enum DiceStyle {
    static let accent = Color(red: 0.96, green: 0.35, blue: 0.10)
    static let title = Font.system(size: 16, weight: .semibold)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let label = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11)
    static let data = Font.system(size: 11, design: .monospaced)
    static let emptySymbol = Font.system(size: 44, weight: .light)
    static let control = Font.system(size: 14, weight: .medium)
    static let page = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let inset: CGFloat = 16
    static let controlSize: CGFloat = 30
    static let cornerRadius: CGFloat = 14
}
