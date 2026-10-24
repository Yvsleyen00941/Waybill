import SwiftUI

/// Bottom-left: the Shipment Tracking panel (inspired by the reference dashboard).
/// A Flighty-style stepper (Picked → Loading → In transit → Delivered) for one vehicle's shipment,
/// plus a card with the destination, the status and, when a truck is full, the Dispatch button.
/// Swipe (or use the arrows) to flip through every vehicle that's carrying something.
struct ShipmentTracker: View {
    let game: GameModel
    let world: WorldController
    @State private var selected: Int?
    @State private var direction: Edge = .trailing

    var body: some View {
        let list = trackable
        let current = list.first { $0.id == selected } ?? list.first
        VStack(alignment: .leading, spacing: 10) {
            header(list: list, current: current)
            if let truck = current, let job = truck.job {
                HStack(alignment: .center, spacing: 14) {
                    Stepper(model: StepModel(game: game, truck: truck, job: job))
                        .frame(width: 330)
                    ShipmentCard(game: game, world: world, truck: truck, job: job)
                }
                .id(truck.id)
                .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                        removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)))
            } else {
                EmptyTracker(game: game)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(width: 640, alignment: .leading)
        .hudGlass(in: .rect(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.width < -40 { step(+1, in: list, from: current) }
            if value.translation.width > 40 { step(-1, in: list, from: current) }
        })
        .animation(.spring(duration: 0.4, bounce: 0.15), value: current?.id)
    }

    /// Vehicles with a shipment: the ones at a dock first (that's where the action is), then the road.
    private var trackable: [Truck] {
        let withJob = game.trucks.filter { $0.job != nil }
        let atDock = withJob.filter(\.isAtDock).sorted { $0.since < $1.since }
        let away = withJob.filter(\.isAway).sorted { $0.remaining > $1.remaining }
        return atDock + away
    }

    private func step(_ delta: Int, in list: [Truck], from current: Truck?) {
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == current?.id } ?? 0
        let next = (index + delta + list.count) % list.count
        direction = delta > 0 ? .trailing : .leading
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { selected = list[next].id }
    }

    private func header(list: [Truck], current: Truck?) -> some View {
        HStack(spacing: 8) {
            Text("Shipment tracking")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.UI.ink)
            if game.rushActive {
                Label("Rush ×2", systemImage: "bolt.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC27C12))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xFCEFD3), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 8)
            if let truck = current {
                Text("\(game.config.vehicleCode(truck.id)) · \(Brand.name)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
                    .contentTransition(.numericText())
            }
            if list.count > 1 {
                HStack(spacing: 2) {
                    PagerButton(symbol: "chevron.left") { step(-1, in: list, from: current) }
                    Text("\((list.firstIndex { $0.id == current?.id } ?? 0) + 1)/\(list.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                        .frame(minWidth: 26)
                        .contentTransition(.numericText())
                    PagerButton(symbol: "chevron.right") { step(+1, in: list, from: current) }
                }
                .padding(.horizontal, 3)
                .background(Capsule().fill(Color.black.opacity(0.05)))
            }
        }
        .animation(.snappy, value: game.rushActive)
    }
}

private struct PagerButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.UI.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
    }
}

// MARK: - Stepper

/// Everything the stepper shows, worked out from the truck's state.
private struct StepModel {
    struct Step {
        let title: String
        let detail: String
        let symbol: String
    }
    let steps: [Step]
    let current: Int          // index of the step in progress (4 = all done)
    let fill: [Double]        // how far each connecting line is drawn (3 lines)
    let pulse: Bool           // breathe the current step (ready to dispatch)

    init(game: GameModel, truck: Truck, job: Shipment) {
        let unit = game.config.unit
        let load = game.truckload
        let half = game.roadSeconds / 2
        let speed = game.rushActive ? 2.0 : 1.0
        let picked = Step(title: "Picked", detail: Format.clock(job.pickedAt), symbol: "shippingbox")
        var loading = Step(title: "Loading", detail: "", symbol: "list.clipboard")
        var transit = Step(title: "In transit", detail: "—", symbol: game.config.fleet.symbol)
        var deliveredStep = Step(title: "Delivered", detail: "—", symbol: "checkmark")
        var current = 1
        var fill = [1.0, 0, 0]
        var pulse = false

        switch truck.phase {
        case .docking(let left):
            loading = Step(title: "Loading", detail: "docking · \(Format.duration(left / speed))", symbol: "list.clipboard")
            fill[1] = 0.04
            deliveredStep = Step(title: "Delivered", detail: Self.eta(game, extra: left / speed + Self.loadETA(game, truck: truck) + half / speed), symbol: "checkmark")
        case .loading:
            let have = game.loaded(truck)
            let ready = game.isReady(truck)
            let eta = Self.loadETA(game, truck: truck)
            loading = Step(title: "Loading \(Int(have))/\(Int(load))",
                           detail: ready ? (game.hasDispatcher ? "ready" : "ready to go") : "ready in \(Format.duration(eta))",
                           symbol: "list.clipboard")
            fill[1] = have / max(load, 1)
            pulse = ready && !game.hasDispatcher
            deliveredStep = Step(title: "Delivered", detail: Self.eta(game, extra: eta + half / speed), symbol: "checkmark")
        case .away(let left):
            let departed = job.departedAt.map(Format.clock) ?? "—"
            loading = Step(title: "Loaded \(Int(job.units))", detail: departed, symbol: "list.clipboard")
            fill[1] = 1
            if job.deliveredAt == nil {
                current = 2
                let toGo = max(left - half, 0)
                transit = Step(title: "In transit", detail: "arrives in \(Format.duration(toGo / speed))", symbol: game.config.fleet.symbol)
                fill[2] = 1 - toGo / max(half, 1)
                deliveredStep = Step(title: "Delivered", detail: Self.eta(game, extra: toGo / speed), symbol: "checkmark")
            } else {
                current = 4
                transit = Step(title: "In transit", detail: departed, symbol: game.config.fleet.symbol)
                fill[2] = 1
                deliveredStep = Step(title: "Delivered", detail: job.deliveredAt.map(Format.clock) ?? "", symbol: "checkmark")
            }
        case .queued:
            break
        }
        _ = unit
        steps = [picked, loading, transit, deliveredStep]
        self.current = current
        self.fill = fill
        self.pulse = pulse
    }

    /// Seconds until the truck is full, at the current shipping rate.
    static func loadETA(_ game: GameModel, truck: Truck) -> Double {
        let missing = max(game.truckload - game.loaded(truck), 0)
        let rate = max(min(game.rate(.shipping), game.rate(.putaway), game.rate(.receiving)), 0.1) / 60
        return missing / rate
    }

    static func eta(_ game: GameModel, extra seconds: Double) -> String {
        "ETA " + Format.clock(Date().addingTimeInterval(seconds))
    }
}

private struct Stepper: View {
    let model: StepModel

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let spacing = (w - 36) / 3
            ZStack(alignment: .topLeading) {
                // Connecting lines
                ForEach(0..<3, id: \.self) { i in
                    let x0 = 18 + spacing * CGFloat(i)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.08))
                        Capsule().fill(Palette.UI.brand.gradient)
                            .frame(width: max((spacing - 4) * model.fill[i], 0))
                            .animation(.linear(duration: 0.12), value: model.fill[i])
                    }
                    .frame(width: spacing - 4, height: 3)
                    .offset(x: x0 + 2, y: 18.5)
                }
                // Steps
                ForEach(0..<4, id: \.self) { i in
                    StepView(step: model.steps[i], state: i < model.current ? .done : (i == model.current ? .current : .upcoming),
                             pulse: model.pulse && i == model.current, isLast: i == 3)
                        .frame(width: 96)
                        .position(x: 18 + spacing * CGFloat(i), y: 48)
                }
            }
        }
        .frame(height: 92)
    }
}

private struct StepView: View {
    enum State { case done, current, upcoming }
    let step: StepModel.Step
    let state: State
    let pulse: Bool
    let isLast: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if state == .current {
                    LoopingShape(shape: .ring(lineWidth: 5), color: Palette.UI.brand.opacity(0.25),
                                 loop: .init(scale: (1, 1.12), opacity: (1, 0.5), duration: pulse ? 0.7 : 1.4, autoreverses: true, easeInOut: true))
                        .frame(width: 42, height: 42)
                }
                Circle()
                    .fill(state == .upcoming ? AnyShapeStyle(Color(hex: 0xE6E8F2)) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4347CF)], startPoint: .top, endPoint: .bottom)))
                    .frame(width: state == .current ? 36 : 30, height: state == .current ? 36 : 30)
                    .shadow(color: state == .upcoming ? .clear : Palette.UI.brand.opacity(0.35), radius: 6, y: 2)
                Image(systemName: state == .done && !isLast ? "checkmark" : step.symbol)
                    .font(.system(size: state == .current ? 14 : 12, weight: .bold))
                    .foregroundStyle(state == .upcoming ? Palette.UI.secondary.opacity(0.7) : .white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(height: 42)
            VStack(spacing: 1) {
                Text(step.title)
                    .font(.system(size: 12.5, weight: state == .current ? .bold : .semibold))
                    .foregroundStyle(state == .upcoming ? Palette.UI.secondary : Palette.UI.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(step.detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(pulse ? Palette.UI.positive : Palette.UI.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: state == .current)
    }
}

// MARK: - Shipment card

private struct ShipmentCard: View {
    let game: GameModel
    let world: WorldController
    let truck: Truck
    let job: Shipment

    var body: some View {
        let ready = game.isReady(truck) && !game.hasDispatcher
        let contract = job.contract.flatMap { id in game.contracts.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VehicleThumbnail(asset: game.config.fleet.thumbnail, symbol: game.config.fleet.symbol)
                    .frame(width: 64, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.code)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.ink)
                    HStack(spacing: 5) {
                        if let contract {
                            Circle().fill(Color(hex: contract.colorHex)).frame(width: 7, height: 7)
                        }
                        Text("To: \(job.destination)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.UI.secondary)
                            .lineLimit(1)
                    }
                    StatusChip(status: status)
                }
                Spacer(minLength: 0)
                Button {
                    world.follow(truck: truck.id)
                } label: {
                    Image(systemName: world.followedTruck == truck.id ? "scope" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(world.followedTruck == truck.id ? Palette.UI.brand : Palette.UI.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.6)))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle(scale: 0.85))
            }
            if ready {
                DispatchButton(game: game)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            } else {
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(height: 20, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: 252, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
        .animation(.spring(duration: 0.4, bounce: 0.3), value: ready)
    }

    private var status: StatusChip.Status {
        switch truck.phase {
        case .docking: .docking
        case .loading: game.isReady(truck) ? .ready : .loading
        case .away: job.deliveredAt == nil ? .transit : .returning
        case .queued: .loading
        }
    }

    private var detail: String {
        let speed = game.rushActive ? 2.0 : 1.0
        let place = "\(game.config.code) · \(game.config.dockName(truck.dock))"
        switch truck.phase {
        case .docking(let left): return "\(place) · docking, \(Format.duration(left / speed))"
        case .loading:
            if game.isReady(truck) { return "\(place) · full, leaving now" }
            return "\(place) · \(Int(game.truckload - game.loaded(truck))) \(game.config.unit.many) to go"
        case .away(let left):
            let half = game.roadSeconds / 2
            if job.deliveredAt == nil { return "\(Format.money(job.value)) · arrives in \(Format.duration(max(left - half, 0) / speed))" }
            return "Delivered · back at depot in \(Format.duration(left / speed))"
        case .queued: return place
        }
    }
}

struct StatusChip: View {
    enum Status {
        case docking, loading, ready, transit, returning
        var text: String {
            switch self {
            case .docking: "Docking"
            case .loading: "Loading"
            case .ready: "Ready"
            case .transit: "In transit"
            case .returning: "Delivered"
            }
        }
        var colors: (Color, Color) {
            switch self {
            case .docking: (Color(hex: 0x4B4FD8), Color(hex: 0xE8E9FC))
            case .loading: (Color(hex: 0x2E9E5B), Color(hex: 0xE2F4E9))
            case .ready: (Color.white, Color(hex: 0x2E9E5B))
            case .transit: (Color(hex: 0x4B4FD8), Color(hex: 0xE8E9FC))
            case .returning: (Color(hex: 0x2E9E5B), Color(hex: 0xE2F4E9))
            }
        }
    }
    let status: Status

    var body: some View {
        Text(status.text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(status.colors.0)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.colors.1, in: Capsule())
            .contentTransition(.opacity)
            .animation(.snappy, value: status.text)
    }
}

/// The rendered vehicle (if the asset exists), otherwise an icon.
struct VehicleThumbnail: View {
    let asset: String
    let symbol: String

    var body: some View {
        if UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.UI.infoBG)
                .overlay(Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.UI.brand))
        }
    }
}

private struct DispatchButton: View {
    let game: GameModel
    @State private var glow = false

    var body: some View {
        Button {
            game.dispatch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: game.config.fleet.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2.5)))
                Text(game.config.fleet.verb)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text("+\(Format.money(game.dispatchValue))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                Capsule().fill(LinearGradient(colors: [Color(hex: 0x7276F2), Color(hex: 0x4347CF)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Palette.UI.brand.opacity(glow ? 0.55 : 0.2), radius: glow ? 12 : 5, y: 3)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true } }
    }
}

/// Nothing is moving (all vehicles waiting for a free dock): show the last delivery instead.
private struct EmptyTracker: View {
    let game: GameModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(Palette.UI.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for a free dock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                if let last = game.history.first {
                    Text("Last delivery \(last.code) to \(last.destination)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.UI.secondary)
                }
            }
        }
        .frame(height: 92)
    }
}
