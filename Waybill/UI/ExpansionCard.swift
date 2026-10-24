import SwiftUI

/// "Expand to a new region": what's next, what you keep, what starts fresh.
struct ExpansionCard: View {
    let game: GameModel
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var appeared = false
    @State private var route: CGFloat = 0

    var body: some View {
        let current = game.config
        let next = game.region.next?.config ?? current
        let stars = Economy.expansionStars(lifetime: game.lifetimeEarned, goal: current.goal)
        ZStack {
            Color.black.opacity(appeared ? 0.22 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(spacing: 18) {
                // From → to, drawn like the brand's route
                HStack(spacing: 0) {
                    RegionDot(code: current.code, name: current.name, filled: true)
                    GeometryReader { g in
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: g.size.height / 2))
                            p.addCurve(to: CGPoint(x: g.size.width, y: g.size.height / 2),
                                       control1: CGPoint(x: g.size.width * 0.35, y: -6), control2: CGPoint(x: g.size.width * 0.65, y: g.size.height + 6))
                        }
                        .trim(from: 0, to: route)
                        .stroke(Palette.UI.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
                    }
                    .frame(height: 30)
                    RegionDot(code: next.code, name: next.name, filled: route >= 1)
                }
                .padding(.horizontal, 8)

                VStack(spacing: 6) {
                    Text("Region \(next.number)")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(Palette.UI.brand)
                    Text(next.name)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.UI.ink)
                    Text(next.blurb)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.UI.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(alignment: .top, spacing: 10) {
                    InfoBox(title: "New here", symbol: "sparkles", tint: Palette.UI.brand, lines: [next.mechanic])
                    InfoBox(title: "You keep", symbol: "star.fill", tint: Color(hex: 0xD9952B), lines: [
                        "+\(stars) reputation stars (now \(game.stars + stars))",
                        "\(current.name) joins your network: +\(Int(Economy.networkBonus * 100))% income",
                    ])
                    InfoBox(title: "Starts fresh", symbol: "arrow.counterclockwise", tint: Palette.UI.secondary, lines: [
                        "Money, levels, managers and research",
                    ])
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Not yet")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.UI.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    Button(action: onConfirm) {
                        Label("Expand to \(next.name)", systemImage: "arrow.right")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x7276F2), Color(hex: 0x4347CF)], startPoint: .top, endPoint: .bottom)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
            }
            .padding(26)
            .frame(width: 600)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.25)) { appeared = true }
            withAnimation(.timingCurve(0.6, 0, 0.25, 1, duration: 1.1).delay(0.3)) { route = 1 }
        }
    }
}

private struct RegionDot: View {
    let code: String
    let name: String
    let filled: Bool
    var body: some View {
        VStack(spacing: 4) {
            Text(code)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? .white : Palette.UI.brand)
                .frame(width: 40, height: 40)
                .background(Circle().fill(filled ? AnyShapeStyle(Palette.UI.brand.gradient) : AnyShapeStyle(Color.white)))
                .overlay(Circle().strokeBorder(Palette.UI.brand, lineWidth: 2))
                .animation(.spring(duration: 0.4, bounce: 0.4), value: filled)
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.UI.secondary)
        }
        .frame(width: 96)
    }
}

private struct InfoBox: View {
    let title: String
    let symbol: String
    let tint: Color
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.UI.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.55)))
    }
}

/// The curtain between regions: covers the rebuild, names the new place, lifts onto the fly-in.
struct RegionCurtain: View {
    let region: RegionConfig
    @State private var shown = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4347CF), Color(hex: 0x262874)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                WaybillMark(color: .white).frame(width: 64, height: 64)
                Text("Region \(region.number)")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(.white.opacity(0.7))
                Text(region.name)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(region.mechanic)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .blur(radius: shown ? 0 : 6)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.15).delay(0.2)) { shown = true } }
    }
}
