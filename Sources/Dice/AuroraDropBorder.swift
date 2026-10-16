import SwiftUI

/// Rendered only while a file hovers over the window; no idle animation work.
struct AuroraDropBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 15) * 24
            let light = DiceStyle.auroraLoop(angle: angle)
            let edge = RoundedRectangle(cornerRadius: DiceStyle.cornerRadius, style: .continuous).inset(by: 3)
            ZStack {
                edge.stroke(light, lineWidth: 14).blur(radius: 12).opacity(0.5)
                edge.stroke(light, lineWidth: 5).blur(radius: 4).opacity(0.85)
                edge.stroke(light, lineWidth: 1.5).opacity(0.95)
            }
            .clipShape(RoundedRectangle(cornerRadius: DiceStyle.cornerRadius, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}
