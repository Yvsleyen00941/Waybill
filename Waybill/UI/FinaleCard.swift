import SwiftUI

/// The finale: Waybill reached orbit. A short celebration with the company's numbers, then endless play.
struct FinaleCard: View {
    let game: GameModel
    let onClose: () -> Void
    @State private var route: CGFloat = 0
    @State private var shown = false
    @State private var stars: [CGPoint] = (0..<70).map { _ in CGPoint(x: .random(in: 0...1), y: .random(in: 0...1)) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x14163F), Color(hex: 0x2E3194)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { g in
                ForEach(stars.indices, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(Double(i % 5) * 0.12 + 0.25))
                        .frame(width: CGFloat(i % 3) + 1.5, height: CGFloat(i % 3) + 1.5)
                        .position(x: stars[i].x * g.size.width, y: stars[i].y * g.size.height)
                }
            }
            .ignoresSafeArea()
            VStack(spacing: 26) {
                WaybillMark(color: .white, progress: route, origin: route > 0 ? 1 : 0, ring: route >= 1 ? 1 : 0)
                    .frame(width: 110, height: 110)
                VStack(spacing: 8) {
                    Text("Waybill reached orbit")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("From one truck by the river to payloads 400 km up.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 12) {
                    Stat(value: Format.money(game.companyEarned), label: "earned")
                    Stat(value: "\(game.completed.count + 1)", label: "regions")
                    Stat(value: Format.short(Double(game.shipmentsSent)), label: "shipments")
                    Stat(value: "\(game.contractsCompleted)", label: "contracts")
                    Stat(value: "★ \(game.stars + 25)", label: "reputation")
                }
                Button(action: onClose) {
                    Text("Keep it moving")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.UI.brand)
                        .padding(.horizontal, 34)
                        .frame(height: 54)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                Text("Endless mode: contracts keep coming and the numbers keep growing. +25 reputation stars.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.15)) { shown = true }
            withAnimation(.timingCurve(0.6, 0, 0.25, 1, duration: 1.4).delay(0.4)) { route = 1 }
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 118, height: 76)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

/// Every region at a glance: finished, current (with progress), and what's still ahead.
struct NetworkPanel: View {
    let game: GameModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your network")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                Spacer()
                Text("+\(Int((game.networkMultiplier - 1) * 100))% income · ★\(game.stars)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
            }
            ForEach(RegionID.allCases) { id in
                let c = id.config
                let done = game.completed.contains(id)
                let current = game.region == id
                HStack(spacing: 10) {
                    Text(c.code)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(done || current ? .white : Palette.UI.secondary)
                        .frame(width: 30, height: 22)
                        .background((done || current) ? AnyShapeStyle(Palette.UI.brand) : AnyShapeStyle(Color.black.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(done || current ? Palette.UI.ink : Palette.UI.secondary)
                        Text(done ? "Finished · in your network" : current ? c.mechanic : c.blurb)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.UI.secondary)
                            .lineLimit(1)
                        if current && c.goal.isFinite {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.black.opacity(0.06))
                                    Capsule().fill(Palette.UI.brand.gradient).frame(width: max(g.size.width * game.expansionProgress, 3))
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                    Spacer()
                    Image(systemName: done ? "checkmark.circle.fill" : current ? "location.circle.fill" : "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(done ? Palette.UI.positive : current ? Palette.UI.brand : Palette.UI.secondary.opacity(0.6))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(width: 330)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
