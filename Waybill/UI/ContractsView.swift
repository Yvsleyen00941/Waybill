import SwiftUI

/// Contracts tab: timed delivery jobs from clients. Accept one, the fleet ships to the client first,
/// finish in time for a cash bonus and reputation stars (permanent income).
struct ContractsView: View {
    let game: GameModel

    var body: some View {
        if !game.contractsUnlocked {
            LockedPanel(symbol: "doc.text.fill", title: "Contracts",
                        message: "Hire the Dispatcher to unlock contracts: timed jobs from clients that pay a bonus and reputation.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Active", detail: "\(game.contracts.count) of \(game.contractSlots)")
                    if game.contracts.isEmpty {
                        Text("Pick an offer below. Your trucks will ship to the client first.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.UI.secondary)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 4)
                    }
                    ForEach(game.contracts) { c in
                        ActiveContractCard(contract: c, unit: game.config.unit.many)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    SectionLabel(text: "Offers", detail: "new ones arrive every few minutes")
                        .padding(.top, 4)
                    ForEach(game.offers) { c in
                        OfferRow(game: game, contract: c)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.2), value: game.contracts.map(\.id))
                .animation(.spring(duration: 0.4, bounce: 0.2), value: game.offers.map(\.id))
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 430)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionLabel: View {
    let text: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Palette.UI.secondary)
            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.UI.secondary.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 6)
    }
}

private struct ClientBadge: View {
    let name: String
    let color: UInt32
    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color(hex: color).gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct Stars: View {
    let count: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<count, id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0xF2B33D))
            }
        }
    }
}

private struct ActiveContractCard: View {
    let contract: Contract
    let unit: String

    var body: some View {
        let urgent = contract.remaining < 60
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                ClientBadge(name: contract.client, color: contract.colorHex)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contract.client)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.UI.ink)
                    Text("to \(contract.destination)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.UI.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(Format.money(contract.reward))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.positive)
                    Stars(count: contract.stars)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07))
                    Capsule().fill(Color(hex: contract.colorHex).gradient)
                        .frame(width: max(g.size.width * contract.progress, 6))
                        .animation(.spring(duration: 0.5, bounce: 0.2), value: contract.progress)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Format.short(contract.delivered)) of \(Format.short(contract.units)) \(unit)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.ink)
                    .contentTransition(.numericText())
                Spacer()
                Label(Format.duration(contract.remaining), systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? Palette.UI.warning : Palette.UI.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.6)))
        .overlay(alignment: .leading) {
            Capsule().fill(Color(hex: contract.colorHex)).frame(width: 3).padding(.vertical, 14)
        }
    }
}

private struct OfferRow: View {
    let game: GameModel
    let contract: Contract

    var body: some View {
        let full = game.contracts.count >= game.contractSlots
        HStack(spacing: 10) {
            ClientBadge(name: contract.client, color: contract.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(contract.client)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.UI.ink)
                    Stars(count: contract.stars)
                }
                Text("\(Format.short(contract.units)) \(game.config.unit.many) in \(Format.duration(contract.seconds)) · to \(contract.destination)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Offer ends in \(Format.duration(contract.offerExpires))")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary.opacity(0.75))
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.25)) { game.accept(contract) }
            } label: {
                VStack(spacing: 1) {
                    Text("Accept")
                        .font(.system(size: 10.5, weight: .semibold))
                        .opacity(0.85)
                    Text("+\(Format.money(contract.reward))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(full ? Palette.UI.secondary : .white)
                .frame(width: 86, height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(full ? AnyShapeStyle(Color.black.opacity(0.06))
                                   : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4B4FD8)], startPoint: .top, endPoint: .bottom)))
                }
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(full)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.35)))
    }
}

/// Shown on a tab that isn't unlocked yet.
struct LockedPanel: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.UI.infoBG).frame(width: 56, height: 56)
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.UI.brand)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Palette.UI.secondary))
                    .offset(x: 20, y: 20)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.UI.ink)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.UI.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}
