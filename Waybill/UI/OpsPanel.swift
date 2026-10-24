import SwiftUI

/// The board on the right, with tabs like the reference's "Docks | Forklifts | Trucks":
/// Operations (stages, upgrades, managers, the next region), Contracts and Research.
struct OpsPanel: View {
    enum Tab: String, CaseIterable { case operations = "Operations", contracts = "Contracts", research = "Research" }

    let game: GameModel
    let world: WorldController
    @Binding var isOpen: Bool
    @Binding var tab: Tab
    var onExpand: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isOpen {
                Group {
                    switch tab {
                    case .operations: operations
                    case .contracts: ContractsView(game: game)
                    case .research: ResearchView(game: game, world: world)
                    }
                }
                .transition(.scale(scale: 0.97, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(width: 400)
        .hudGlass(in: .rect(cornerRadius: 24))
    }

    private var header: some View {
        HStack(spacing: 8) {
            TabPicker(game: game, tab: $tab, isOpen: $isOpen)
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.15)) { isOpen.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.UI.secondary)
                    .rotationEffect(.degrees(isOpen ? 0 : 180))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var operations: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Format.rate(game.throughput)) \(game.config.unit.many)/min")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.ink)
                        .contentTransition(.numericText())
                    Text("\(Format.money(game.unitValue)) per \(game.config.unit.one)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                BuyModePicker(game: game)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            ForEach(StageKind.allCases) { kind in
                StageRow(game: game, kind: kind)
            }
            if game.facility != nil { FacilityRow(game: game, world: world) }
            ExpansionRow(game: game, onExpand: onExpand)
        }
    }
}

/// Segmented tabs with small counters ("Contracts 1/2").
private struct TabPicker: View {
    let game: GameModel
    @Binding var tab: OpsPanel.Tab
    @Binding var isOpen: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(OpsPanel.Tab.allCases, id: \.self) { t in
                let selected = tab == t && isOpen
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        if tab == t { isOpen.toggle() } else { tab = t; isOpen = true }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(t.rawValue)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Palette.UI.ink : Palette.UI.secondary)
                        badge(t)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        if selected {
                            Capsule().fill(Color.white.opacity(0.9))
                                .shadow(color: Palette.brandDeepColor.opacity(0.12), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.05)))
    }

    @ViewBuilder private func badge(_ t: OpsPanel.Tab) -> some View {
        switch t {
        case .operations:
            if game.canExpand || game.canFinish { Circle().fill(Palette.UI.positive).frame(width: 7, height: 7) }
        case .contracts:
            if !game.contractsUnlocked {
                Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.UI.secondary.opacity(0.7))
            } else {
                Text("\(game.contracts.count)/\(game.contractSlots)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(game.contracts.isEmpty && !game.offers.isEmpty ? Palette.UI.brand : Palette.UI.secondary)
            }
        case .research:
            if !game.researchUnlocked {
                Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.UI.secondary.opacity(0.7))
            } else if game.activeResearch != nil {
                ProgressView().controlSize(.mini).tint(Palette.UI.brand)
            } else {
                let done = ResearchProject.projects(for: game.region).filter { game.research.contains($0.id) }.count
                Text("\(done)/\(ResearchProject.projects(for: game.region).count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
            }
        }
    }
}

/// Progress towards the next region, and the Expand button once it's reached.
/// In Orbit it counts down to the finale instead.
private struct ExpansionRow: View {
    let game: GameModel
    let onExpand: () -> Void
    @State private var glow = false

    var body: some View {
        if game.region.next == nil {
            finaleRow
        } else if let next = game.region.next {
            let ready = game.canExpand
            HStack(spacing: 11) {
                Image(systemName: ready ? "map.fill" : "map")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ready ? .white : Palette.UI.brand)
                    .frame(width: 38, height: 38)
                    .background(ready ? AnyShapeStyle(Palette.UI.brand.gradient) : AnyShapeStyle(Palette.UI.infoBG),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ready ? "\(next.config.name) is ready" : "Next: \(next.config.name)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.UI.ink)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.06))
                            Capsule().fill(Palette.UI.brand.gradient).frame(width: max(g.size.width * game.expansionProgress, 4))
                        }
                    }
                    .frame(height: 4)
                    Text("\(Format.money(game.lifetimeEarned)) of \(Format.money(game.config.goal)) earned here")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 4)
                if ready {
                    Button(action: onExpand) {
                        Text("Expand")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 86, height: 40)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4B4FD8)], startPoint: .top, endPoint: .bottom)))
                            .shadow(color: Palette.UI.brand.opacity(glow ? 0.55 : 0.2), radius: glow ? 12 : 5, y: 3)
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true } }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(ready ? 0.6 : 0.25)))
        }
    }

    @ViewBuilder private var finaleRow: some View {
        let ready = game.canFinish
        HStack(spacing: 11) {
            Image(systemName: game.finished ? "infinity" : "flag.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ready ? .white : Palette.UI.brand)
                .frame(width: 38, height: 38)
                .background(ready ? AnyShapeStyle(Palette.UI.brand.gradient) : AnyShapeStyle(Palette.UI.infoBG),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(game.finished ? "Endless mode" : (ready ? "Waybill reached orbit" : "Finale"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                if game.finished {
                    Text("\(Format.money(game.companyEarned)) earned across \(game.completed.count + 1) regions")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                } else {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.06))
                            Capsule().fill(Palette.UI.brand.gradient).frame(width: max(g.size.width * game.expansionProgress, 4))
                        }
                    }
                    .frame(height: 4)
                    Text("\(Format.money(game.lifetimeEarned)) of \(Format.money(game.config.goal)) earned here")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                }
            }
            Spacer(minLength: 4)
            if ready {
                Button(action: onExpand) {
                    Text("Celebrate")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 40)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4B4FD8)], startPoint: .top, endPoint: .bottom)))
                        .shadow(color: Palette.UI.brand.opacity(glow ? 0.55 : 0.2), radius: glow ? 12 : 5, y: 3)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true } }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(ready ? 0.6 : 0.25)))
    }
}

/// ×1 / ×10 / Max, with a sliding selection pill.
private struct BuyModePicker: View {
    let game: GameModel
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GameModel.BuyMode.allCases, id: \.self) { mode in
                let selected = game.buyMode == mode
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { game.buyMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? .white : Palette.UI.secondary)
                        .frame(width: 40, height: 26)
                        .background {
                            if selected {
                                Capsule().fill(Palette.UI.brand).matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.05)))
    }
}

private struct StageRow: View {
    let game: GameModel
    let kind: StageKind

    var body: some View {
        let config = game.config.stage(kind)
        let isBottleneck = game.bottleneck == kind
        let level = game.level(kind)
        let accent = isBottleneck ? Palette.UI.warning : Palette.UI.brand

        HStack(spacing: 11) {
            Image(systemName: config.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background((isBottleneck ? Palette.UI.warningBG : Palette.UI.infoBG), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .symbolEffect(.bounce, value: level)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(config.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.UI.ink)
                    Text("Lv \(level)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .contentTransition(.numericText(value: Double(level)))
                    if isBottleneck {
                        Text("Bottleneck")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Palette.UI.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.UI.warningBG, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText())
                ManagerLine(game: game, kind: kind)
            }
            .animation(.snappy, value: isBottleneck)

            Spacer(minLength: 4)
            UpgradeButton(game: game, kind: kind)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .padding(.bottom, 3)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isBottleneck ? Palette.UI.warningBG.opacity(0.45) : Color.white.opacity(0.35)))
        .overlay(alignment: .bottom) { MilestoneBar(level: level, tint: accent).padding(.horizontal, 14).padding(.bottom, 4) }
        .overlay(alignment: .leading) {
            if isBottleneck {
                Capsule().fill(Palette.UI.warning).frame(width: 3).padding(.vertical, 12)
            }
        }
    }

    private var detail: String {
        if kind == .receiving && game.config.windows != nil { return base } // ship window info is more useful here
        let milestone = Economy.nextMilestone(after: game.level(kind)).map { " · ×2 at \($0)" } ?? ""
        return base + milestone
    }

    private var base: String {
        switch kind {
        case .fleet:
            let f = game.config.fleet
            if game.facility != nil && game.docksAreLimit && game.vehiclesWaiting > 0 {
                return "\(game.fleetSize) \(game.fleetSize == 1 ? f.vehicle : f.vehicles) · \(game.vehiclesWaiting) waiting for a bay"
            }
            return "\(game.fleetSize) \(game.fleetSize == 1 ? f.vehicle : f.vehicles) · \(Int(game.truckload)) per load · \(Format.rate(game.rate(.fleet)))/min"
        case .receiving where game.config.windows != nil:
            return "\(Format.rate(game.rate(kind)))/min · " + (game.shipBerthed ? "ship in, \(Format.duration(game.shipWindowRemaining))" : "next ship \(Format.duration(game.shipWindowRemaining))")
        default:
            return "\(Format.rate(game.rate(kind))) \(game.config.unit.many)/min"
        }
    }
}

/// Thin progress line along the bottom of a row, towards the next ×2 milestone.
private struct MilestoneBar: View {
    let level: Int
    let tint: Color

    var body: some View {
        let previous = Economy.milestones.last { $0 <= level } ?? 1
        let next = Economy.nextMilestone(after: level)
        let progress = next.map { Double(level - previous) / Double($0 - previous) } ?? 1
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.05))
                Capsule().fill(tint.opacity(0.75)).frame(width: max(g.size.width * progress, 3))
                    .animation(.spring(duration: 0.5, bounce: 0.2), value: progress)
            }
        }
        .frame(height: 2.5)
    }
}

private struct ManagerLine: View {
    let game: GameModel
    let kind: StageKind

    var body: some View {
        let config = game.config.stage(kind)
        if game.isManaged(kind) {
            Label(config.managerPerk, systemImage: "checkmark.seal.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.UI.positive)
                .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
        } else {
            let affordable = game.money >= config.managerCost
            Button {
                withAnimation(.spring(duration: 0.45, bounce: 0.35)) { game.hire(kind) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                    Text("Hire \(config.managerTitle) · \(Format.money(config.managerCost))")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(affordable ? Palette.UI.brand : Palette.UI.secondary.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().strokeBorder(affordable ? Palette.UI.brand.opacity(0.6) : Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .disabled(!affordable)
        }
    }
}

private struct UpgradeButton: View {
    let game: GameModel
    let kind: StageKind
    @State private var bump = 0

    var body: some View {
        let purchase = game.purchase(kind)
        let affordable = game.money >= purchase.cost
        Button {
            game.buy(kind)
            bump += 1
        } label: {
            VStack(spacing: 1) {
                Text(purchase.count > 1 ? "+\(purchase.count) lv" : "Upgrade")
                    .font(.system(size: 10.5, weight: .semibold))
                    .opacity(0.85)
                Text(Format.money(purchase.cost))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: purchase.cost))
            }
            .foregroundStyle(affordable ? .white : Palette.UI.secondary)
            .frame(width: 86, height: 44)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(affordable ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4B4FD8)], startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.black.opacity(0.06)))
            }
            .shadow(color: affordable ? Palette.UI.brand.opacity(0.3) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(!affordable)
        .animation(.snappy(duration: 0.25), value: affordable)
        .sensoryFeedback(.increase, trigger: bump)
    }
}

/// The warehouse: how far it has grown, the next expansion and its build progress.
/// Docks limit how many trucks can load at once, so this is the fix when trucks queue up.
private struct FacilityRow: View {
    let game: GameModel
    let world: WorldController
    @State private var bump = 0

    var body: some View {
        let tier = game.facilityTier
        let total = game.config.facility.count
        let short = game.docksAreLimit && game.bottleneck == .fleet
        let accent = short ? Palette.UI.warning : Palette.UI.brand
        HStack(spacing: 11) {
            Button { world.showWarehouse() } label: {
                Image(systemName: game.construction != nil ? "hammer.fill" : (game.facility?.symbol ?? "building.fill"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(short ? Palette.UI.warningBG : Palette.UI.infoBG, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .symbolEffect(.bounce, value: tier)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.2)), isActive: game.construction != nil)
            }
            .buttonStyle(PressableStyle(scale: 0.92))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Warehouse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.UI.ink)
                    TierDots(tier: tier, total: total, building: game.construction != nil, tint: accent)
                    if short {
                        Text("Bays full")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Palette.UI.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.UI.warningBG, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                if let job = game.construction, job.tier < total {
                    let name = game.config.facility[job.tier].name
                    Text("Building \(name) · \(Format.duration(job.remaining / GameModel.buildSpeed))")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.06))
                            Capsule().fill(Palette.UI.brand.gradient).frame(width: max(g.size.width * job.progress, 4))
                                .animation(.linear(duration: 0.25), value: job.progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 1)
                } else {
                    Text(detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let next = game.nextFacility {
                        Text("Next: \(next.name) · \(nextGain(next))")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.UI.brand)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .animation(.snappy, value: short)

            Spacer(minLength: 4)
            if let next = game.nextFacility, game.construction == nil {
                let affordable = game.money >= next.cost
                Button {
                    withAnimation(.spring(duration: 0.45, bounce: 0.3)) { game.build() }
                    bump += 1
                    world.showWarehouse()
                } label: {
                    VStack(spacing: 1) {
                        Text("Build")
                            .font(.system(size: 10.5, weight: .semibold))
                            .opacity(0.85)
                        Text(Format.money(next.cost))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(affordable ? .white : Palette.UI.secondary)
                    .frame(width: 86, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(affordable ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4B4FD8)], startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(Color.black.opacity(0.06)))
                    }
                    .shadow(color: affordable ? Palette.UI.brand.opacity(0.3) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .disabled(!affordable)
                .animation(.snappy(duration: 0.25), value: affordable)
                .sensoryFeedback(.increase, trigger: bump)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(short ? Palette.UI.warningBG.opacity(0.45) : Color.white.opacity(0.35)))
        .overlay(alignment: .leading) {
            if short { Capsule().fill(Palette.UI.warning).frame(width: 3).padding(.vertical, 12) }
        }
    }

    private var detail: String {
        let docks = game.docks
        let name = game.facility?.name ?? "Warehouse"
        let waiting = game.vehiclesWaiting
        let bays = "\(docks) \(docks == 1 ? "bay" : "bays")"
        if waiting > 0 { return "\(name) · \(bays) · \(waiting) waiting" }
        return game.nextFacility == nil ? "\(name) · \(bays) · fully grown" : "\(name) · \(bays)"
    }

    private func nextGain(_ next: FacilityTier) -> String {
        var parts: [String] = []
        let now = game.facility
        let extra = next.docks - (now?.docks ?? 1)
        if extra > 0 { parts.append("+\(extra) \(extra == 1 ? "bay" : "bays")") }
        if let now, next.stock > now.stock { parts.append("+\(Int((next.stock / now.stock - 1) * 100 + 0.5))% storage") }
        return parts.joined(separator: ", ")
    }
}

/// Small dots for the warehouse stages (filled = built, pulsing = being built).
private struct TierDots: View {
    let tier: Int
    let total: Int
    let building: Bool
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                if i == tier + 1 && building { // the stage being built pulses
                    LoopingShape(shape: .capsule, color: tint, loop: .init(opacity: (0.25, 0.7), duration: 0.7, autoreverses: true, easeInOut: true))
                        .frame(width: 6, height: 5)
                } else {
                    Capsule()
                        .fill(i <= tier ? tint : Color.black.opacity(0.1))
                        .frame(width: i <= tier ? 9 : 6, height: 5)
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: tier)
    }
}
