import SwiftUI

/// Small live chips above the tracker: active contracts and the running research.
/// Tap one to open its tab.
struct StatusChips: View {
    let game: GameModel
    var open: (OpsPanel.Tab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(game.contracts) { c in
                Button { open(.contracts) } label: {
                    Chip(progress: c.progress, tint: Color(hex: c.colorHex), symbol: "doc.text.fill",
                         title: c.client, detail: "\(Format.short(c.delivered))/\(Format.short(c.units)) · \(Format.duration(c.remaining))",
                         urgent: c.remaining < 60)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
            if let active = game.activeResearch, let p = ResearchProject.find(active.id) {
                Button { open(.research) } label: {
                    Chip(progress: 1 - active.remaining / max(p.seconds, 1), tint: Palette.UI.brand, symbol: p.symbol,
                         title: p.title, detail: Format.duration(active.remaining), urgent: false)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: game.contracts.map(\.id))
        .animation(.spring(duration: 0.45, bounce: 0.3), value: game.activeResearch?.id)
    }
}

private struct Chip: View {
    let progress: Double
    let tint: Color
    let symbol: String
    let title: String
    let detail: String
    let urgent: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.UI.ink)
            Text(detail)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(urgent ? Palette.UI.warning : Palette.UI.secondary)
                .contentTransition(.numericText())
        }
        .padding(.leading, 6)
        .padding(.trailing, 13)
        .frame(height: 36)
        .hudGlass(in: .capsule)
    }
}
