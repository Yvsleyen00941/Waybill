import SwiftUI

/// The floating interface over the 3D world.
///
/// Layout (landscape): top bar · camera buttons top-right · Shipment Tracking + Rush bottom-left ·
/// the operations board bottom-right. Tap the clock for the Studio (time of day, sound, rendering).
struct HUD: View {
    let world: WorldController
    let game: GameModel
    var onExpand: () -> Void = {}
    @State private var studioOpen = false
    @State private var networkOpen = false
    @State private var opsOpen = true
    @State private var tab: OpsPanel.Tab = .operations
    @State private var toast: Toast?

    /// Developer switch for performance tests: `-hudOff Tracker,Ops` leaves those parts out.
    static func off(_ part: String) -> Bool {
        (UserDefaults.standard.string(forKey: "hudOff") ?? "").split(separator: ",").contains { $0 == part }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !Self.off("TopBar") { TopBar(world: world, game: game, studioOpen: $studioOpen, networkOpen: $networkOpen) }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !Self.off("Chips") {
                            StatusChips(game: game) { t in
                                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { tab = t; opsOpen = true }
                            }
                        }
                        HStack(alignment: .bottom, spacing: 12) {
                            if !Self.off("Tracker") { ShipmentTracker(game: game, world: world) }
                            if !Self.off("Rush") { RushButton(game: game) }
                        }
                    }
                    Spacer(minLength: 0)
                    if !Self.off("Ops") { OpsPanel(game: game, world: world, isOpen: $opsOpen, tab: $tab, onExpand: onExpand) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if networkOpen {
                VStack {
                    HStack {
                        NetworkPanel(game: game)
                            .padding(.leading, 140)
                            .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                        Spacer()
                    }
                    .padding(.top, 68)
                    Spacer()
                }
            }

            VStack {
                HStack(alignment: .top, spacing: 12) {
                    Spacer()
                    if studioOpen {
                        StudioPanel(world: world, isOpen: $studioOpen)
                            .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                    }
                    if !Self.off("Camera") { CameraControls(world: world) }
                }
                .padding(.top, 68)
                .padding(.trailing, 16)
                Spacer()
            }

            if let toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 72)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            game.listen { event in
                switch event {
                case .milestone(let kind, let level):
                    show(Toast(symbol: "sparkles", title: "\(game.config.stage(kind).title) reached level \(level)", detail: "Speed ×2"))
                case .contractFinished(let c, let success):
                    if success {
                        show(Toast(symbol: "checkmark.seal.fill", title: "\(c.client) contract complete", detail: "+\(Format.money(c.reward)) · ★\(c.stars)"))
                    } else {
                        show(Toast(symbol: "clock.badge.xmark", title: "\(c.client) contract expired", detail: "\(Int(c.delivered))/\(Int(c.units))", tone: .warning))
                    }
                case .researchDone(let p):
                    show(Toast(symbol: p.symbol, title: "\(p.title) is ready", detail: p.effectLabel))
                case .constructionDone(let tier):
                    show(Toast(symbol: tier.symbol, title: "\(tier.name) is open", detail: "\(tier.docks) bays"))
                case .unlocked(let what):
                    switch what {
                    case "contracts":
                        show(Toast(symbol: "doc.text.fill", title: "Contracts unlocked", detail: "New"))
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { tab = .contracts; opsOpen = true }
                    case "research":
                        show(Toast(symbol: "flask.fill", title: "Research unlocked", detail: "New"))
                    default: break
                    }
                default: break
                }
            }
        }
    }

    private func show(_ t: Toast) {
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if toast?.id == t.id { withAnimation(.easeInOut(duration: 0.35)) { toast = nil } }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let world: WorldController
    let game: GameModel
    @Binding var studioOpen: Bool
    @Binding var networkOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            BrandChip()
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { networkOpen.toggle() }
            } label: {
                SiteSwitcher(game: game, open: networkOpen)
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            Spacer(minLength: 12)
            if game.stars > 0 { ReputationPill(game: game) }
            CashPill(game: game)
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { studioOpen.toggle() }
            } label: {
                ClockPill(world: world, open: studioOpen)
            }
            .buttonStyle(PressableStyle(scale: 0.95))
        }
    }
}

private struct ReputationPill: View {
    let game: GameModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0xF2B33D))
                .symbolEffect(.bounce, value: game.stars)
            Text("\(game.stars)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.UI.ink)
                .contentTransition(.numericText(value: Double(game.stars)))
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .hudGlass(in: .capsule)
        .animation(.snappy, value: game.stars)
    }
}

private struct BrandChip: View {
    var body: some View {
        HStack(spacing: 9) {
            WaybillTile(size: 30)
            Text(Brand.name)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.UI.ink)
        }
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(height: 44)
        .hudGlass(in: .capsule)
    }
}

private struct SiteSwitcher: View {
    let game: GameModel
    var open = false

    var body: some View {
        let fill = game.stockPercent
        HStack(spacing: 10) {
            Text(game.config.code)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 22)
                .background(Palette.UI.brand, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(game.config.site)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                Text("\(fill)% stock · \(game.trucksAtDepot)/\(game.fleetSize) \(game.config.fleet.vehicles) in")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
                    .contentTransition(.numericText())
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.UI.secondary)
                .rotationEffect(.degrees(open ? 180 : 0))
        }
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(height: 44)
        .hudGlass(in: .capsule)
    }
}

private struct CashPill: View {
    let game: GameModel

    var body: some View {
        HStack(spacing: 8) {
            Text(Format.money(game.money))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.UI.ink)
                .contentTransition(.numericText(value: game.money))
                .animation(.snappy(duration: 0.3), value: game.money)
            Text("+\(Format.money(game.incomePerMinute))/min")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.UI.positive)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.UI.positiveBG, in: Capsule())
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .hudGlass(in: .capsule)
    }
}

private struct ClockPill: View {
    let world: WorldController
    var open = false

    var body: some View {
        let live = world.timeMode == .live
        let tint = live ? Palette.UI.positive : Palette.UI.warning
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .overlay(LoopingShape(shape: .ring(lineWidth: 2), color: tint,
                                      loop: .init(scale: (1, 2.4), opacity: (0.7, 0), duration: 1.6, autoreverses: false, easeInOut: false)))
            Text(live ? "Live" : "Preview")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(Self.format(world.shownHour))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.UI.ink)
                .contentTransition(.numericText())
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(open ? Palette.UI.brand : Palette.UI.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .hudGlass(in: .capsule)
    }

    static func format(_ hour: Double) -> String {
        let total = Int((hour * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Camera controls

private struct CameraControls: View {
    let world: WorldController

    var body: some View {
        VStack(spacing: 2) {
            ControlButton(symbol: "plus") { world.zoomIn() }
            ControlButton(symbol: "minus") { world.zoomOut() }
            Divider().frame(width: 22).padding(.vertical, 2)
            ControlButton(symbol: "arrow.counterclockwise") { world.rotateLeft() }
            ControlButton(symbol: "arrow.clockwise") { world.rotateRight() }
            Divider().frame(width: 22).padding(.vertical, 2)
            ControlButton(symbol: "house") { world.goHome() }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .hudGlass(in: .capsule)
    }
}

private struct ControlButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.UI.ink)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .hoverEffect(.highlight)
    }
}

/// Pressed buttons shrink a little and spring back.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.45), value: configuration.isPressed)
    }
}

// MARK: - Toast

struct Toast: Equatable {
    enum Tone { case positive, warning }
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    var tone: Tone = .positive
}

private struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(toast.tone == .positive ? Palette.UI.brand : Palette.UI.warning, in: Circle())
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.UI.ink)
            Text(toast.detail)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(toast.tone == .positive ? Palette.UI.positive : Palette.UI.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(toast.tone == .positive ? Palette.UI.positiveBG : Palette.UI.warningBG, in: Capsule())
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 44)
        .hudGlass(in: .capsule)
    }
}

// MARK: - Studio panel (time preview + rendering + performance)

private struct StudioPanel: View {
    let world: WorldController
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Studio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { isOpen = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.UI.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(PressableStyle())
            }
            HStack {
                Text("Time of day")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                Spacer()
                Button(world.timeMode == .live ? "Live" : "Back to live") {
                    withAnimation(.snappy) { world.timeMode = .live }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(world.timeMode == .live ? Palette.UI.positive : Palette.UI.brand)
                .disabled(world.timeMode == .live)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill").foregroundStyle(Color(hex: 0xF2B33D))
                Slider(value: Binding(
                    get: { world.timeMode == .live ? world.shownHour : world.previewHour },
                    set: { world.previewHour = $0; if world.timeMode != .preview { world.timeMode = .preview } }
                ), in: 0...24)
                .tint(Palette.UI.brand)
                Image(systemName: "moon.stars.fill").foregroundStyle(Palette.UI.brand)
            }
            Divider()
            Toggle(isOn: Binding(get: { world.sound.enabled }, set: { world.sound.enabled = $0 })) {
                Label("Sound", systemImage: world.sound.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            Toggle("Ambient occlusion", isOn: Binding(get: { world.occlusionOn }, set: { world.occlusionOn = $0 }))
            Toggle("Colour grade", isOn: Binding(get: { world.gradeOn }, set: { world.gradeOn = $0 }))
            Divider()
            HStack {
                Label("\(world.fps) fps", systemImage: "speedometer")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(world.fps >= 100 ? Palette.UI.positive : Palette.UI.warning)
                    .contentTransition(.numericText())
                Spacer()
                Toggle("Stats", isOn: Binding(get: { world.showsStatistics }, set: { world.showsStatistics = $0 }))
                    .fixedSize()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Palette.UI.brand)
        .frame(width: 280)
        .padding(16)
        .hudGlass(in: .rect(cornerRadius: 22))
    }
}
