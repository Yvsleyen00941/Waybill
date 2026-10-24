import RealityKit
import UIKit

/// What a region stores, and how one "layer" of a stack looks.
enum StockUnit {
    case pallet       // 2×2 cardboard boxes on a pallet (Riverside)
    case container    // one shipping container per layer (Harbour City)
    case crate        // wooden crates on a pallet (Granite Pass)
    case cage         // roll cages of parcels (Metro)
    case canister     // white payload canisters (Orbit)

    var hasBase: Bool { self == .pallet || self == .crate }
    var baseHeight: Float { hasBase ? 0.15 : 0 }

    var layerHeight: Float {
        switch self {
        case .pallet: Props.layerHeight
        case .container: 2.6
        case .crate: 0.62
        case .cage: 1.7
        case .canister: 3.4
        }
    }
}

/// Shared meshes for stock (built once, reused by every stack).
enum StockMeshes {
    static let palletBase: MeshResource = {
        var b = MeshBuilder()
        b.addBox([1.2, 0.05, 1.0], .make([0, 0.125, 0]))
        for z: Float in [-0.42, 0, 0.42] { b.addBox([1.2, 0.1, 0.12], .make([0, 0.05, z])) }
        return try! b.makeMesh(name: "palletBase")
    }()
    static let boxLayer: MeshResource = {
        var b = MeshBuilder()
        for (x, z) in [(-0.3, -0.245), (0.3, -0.245), (-0.3, 0.245), (0.3, 0.245)] as [(Float, Float)] {
            b.addRoundedBox(Props.boxSize, radius: 0.035, segments: 1, .make([x, Props.boxSize.y / 2, z]))
        }
        return try! b.makeMesh(name: "palletLayer")
    }()
    static let tape: MeshResource = {
        var b = MeshBuilder()
        for z: Float in [-0.245, 0.245] { b.addBox([1.17, 0.012, 0.09], .make([0, Props.boxSize.y + 0.006, z])) }
        return try! b.makeMesh(name: "palletTape")
    }()
    static let container: MeshResource = {
        var b = MeshBuilder()
        b.addRoundedBox([12.2, 2.55, 2.44], radius: 0.06, segments: 1, .make([0, 1.275, 0]))
        return try! b.makeMesh(name: "container")
    }()
    static let containerRibs: MeshResource = {
        var b = MeshBuilder()
        var x: Float = -5.8
        while x <= 5.8 {
            for z: Float in [1.23, -1.23] { b.addBox([0.14, 2.25, 0.06], .make([x, 1.275, z])) }
            x += 0.62
        }
        return try! b.makeMesh(name: "containerRibs")
    }()
    static let crateLayer: MeshResource = {
        var b = MeshBuilder()
        for z: Float in [-0.24, 0.24] { b.addRoundedBox([1.14, 0.58, 0.46], radius: 0.03, segments: 1, .make([0, 0.29, z])) }
        return try! b.makeMesh(name: "crateLayer")
    }()
    static let crateSlats: MeshResource = {
        var b = MeshBuilder()
        for z: Float in [-0.24, 0.24] {
            for y: Float in [0.12, 0.46] { b.addBox([1.16, 0.06, 0.48], .make([0, y, z])) }
        }
        return try! b.makeMesh(name: "crateSlats")
    }()
    static let cage: MeshResource = {
        var b = MeshBuilder()
        b.addBox([1.2, 0.06, 0.9], .make([0, 0.05, 0]))
        for (x, z) in [(-0.58, -0.43), (0.58, -0.43), (-0.58, 0.43), (0.58, 0.43)] as [(Float, Float)] { b.addBox([0.04, 1.6, 0.04], .make([x, 0.85, z])) }
        for y: Float in [0.6, 1.1, 1.62] {
            b.addBox([1.2, 0.03, 0.03], .make([0, y, 0.43])); b.addBox([1.2, 0.03, 0.03], .make([0, y, -0.43]))
            b.addBox([0.03, 0.03, 0.9], .make([0.58, y, 0])); b.addBox([0.03, 0.03, 0.9], .make([-0.58, y, 0]))
        }
        return try! b.makeMesh(name: "cage")
    }()
    static let parcels: MeshResource = {
        var b = MeshBuilder()
        let sizes: [(V3, V3)] = [([0.5, 0.4, 0.4], [-0.3, 0.3, -0.2]), ([0.45, 0.35, 0.38], [0.28, 0.28, -0.18]), ([0.5, 0.42, 0.36], [-0.25, 0.3, 0.22]),
                                 ([0.4, 0.3, 0.4], [0.28, 0.25, 0.2]), ([0.55, 0.38, 0.42], [-0.05, 0.69, -0.1]), ([0.4, 0.34, 0.34], [0.28, 0.66, 0.2]),
                                 ([0.45, 0.3, 0.36], [-0.28, 1.0, 0.15]), ([0.42, 0.32, 0.4], [0.2, 1.02, -0.15])]
        for (size, p) in sizes { b.addRoundedBox(size, radius: 0.03, segments: 1, .make(p)) }
        return try! b.makeMesh(name: "parcels")
    }()
    static let canister: MeshResource = {
        var b = MeshBuilder()
        b.addCylinder(radius: 1.1, height: 2.6, segments: 18, .make([0, 1.5, 0]))
        b.addSphere(radius: 1.1, segments: 18, rings: 8, .make([0, 2.8, 0], scale: [1, 0.55, 1]))
        b.addCylinder(radius: 1.25, height: 0.2, segments: 18, .make([0, 0.1, 0]))
        return try! b.makeMesh(name: "canister")
    }()
    static let canisterBand: MeshResource = {
        var b = MeshBuilder()
        b.addCylinder(radius: 1.12, height: 0.3, segments: 18, .make([0, 2.2, 0]))
        return try! b.makeMesh(name: "canisterBand")
    }()
}

/// Detailed stock models (one merged entity per layer).
enum StockModels {
    /// Four cardboard boxes with tape and shipping labels (sits on a pallet base).
    static func boxLayer(_ k: ShapeCollector, tone: Mat) {
        for (x, z) in [(-0.3, -0.245), (0.3, -0.245), (-0.3, 0.245), (0.3, 0.245)] as [(Float, Float)] {
            k.box(tone, Props.boxSize, r: 0.03, at: [x, Props.boxSize.y / 2, z])
            k.box(.label, [0.006, 0.12, 0.16], at: [x + (x > 0 ? 1 : -1) * Props.boxSize.x / 2, Props.boxSize.y / 2 + 0.04, z])
        }
        for z: Float in [-0.245, 0.245] { k.box(.tape, [1.17, 0.012, 0.09], at: [0, Props.boxSize.y + 0.006, z]) }
    }

    /// Two slatted wooden crates with corner posts and stencil marks.
    static func crateLayer(_ k: ShapeCollector) {
        for z: Float in [-0.24, 0.24] {
            k.box(.crate, [1.14, 0.58, 0.46], r: 0.02, at: [0, 0.29, z])
            for y: Float in [0.1, 0.29, 0.48] { k.box(.crateDark, [1.16, 0.06, 0.48], at: [0, y, z]) }
            for x: Float in [-0.55, 0.55] { k.box(.crateDark, [0.06, 0.58, 0.48], at: [x, 0.29, z]) }
            k.box(.trim, [0.004, 0.08, 0.2], at: [0.575, 0.38, z])
        }
    }

    /// Roll cage with parcels.
    static func cage(_ k: ShapeCollector, tone: Mat) {
        k.box(.metal, [1.2, 0.06, 0.9], at: [0, 0.05, 0])
        for (x, z) in [(-0.58, -0.43), (0.58, -0.43), (-0.58, 0.43), (0.58, 0.43)] as [(Float, Float)] {
            k.cylinder(.metal, radius: 0.025, height: 1.6, at: [x, 0.85, z], segments: 8)
            k.cylinder(.rubber, radius: 0.06, height: 0.04, at: [x, 0.02, z], pitch: .pi / 2, segments: 10)
        }
        for y: Float in [0.6, 1.1, 1.62] {
            for z: Float in [0.43, -0.43] { k.cylinder(.metal, radius: 0.015, height: 1.2, at: [0, y, z], roll: .pi / 2, segments: 6) }
            for x: Float in [0.58, -0.58] { k.cylinder(.metal, radius: 0.015, height: 0.9, at: [x, y, 0], pitch: .pi / 2, segments: 6) }
        }
        let sizes: [(V3, V3)] = [([0.5, 0.4, 0.4], [-0.3, 0.3, -0.2]), ([0.45, 0.35, 0.38], [0.28, 0.28, -0.18]), ([0.5, 0.42, 0.36], [-0.25, 0.3, 0.22]),
                                 ([0.4, 0.3, 0.4], [0.28, 0.25, 0.2]), ([0.55, 0.38, 0.42], [-0.05, 0.69, -0.1]), ([0.4, 0.34, 0.34], [0.28, 0.66, 0.2]),
                                 ([0.45, 0.3, 0.36], [-0.28, 1.0, 0.15]), ([0.42, 0.32, 0.4], [0.2, 1.02, -0.15])]
        for (i, (size, p)) in sizes.enumerated() {
            k.box(i % 3 == 0 ? .cardboardLight : tone, size, r: 0.03, at: p)
            k.box(.tape, [size.x + 0.004, 0.01, 0.07], at: p + [0, size.y / 2, 0])
        }
    }

    /// Propellant canister: a lathe-turned tank with a brand band, valves and a frame.
    static func canister(_ k: ShapeCollector) {
        var profile: [SIMD2<Float>] = [SIMD2(0, 0.25), SIMD2(1.1, 0.25)]
        for i in 0...6 { let a = Float(i) / 6 * .pi / 2; profile.append(SIMD2(1.1 * cos(a), 2.8 + 0.6 * sin(a))) }
        k.lathe(.paintWhite, profile, at: .zero, segments: 28)
        k.cylinder(.paintBrand, radius: 1.12, height: 0.3, at: [0, 2.2, 0], segments: 28)
        k.cylinder(.paintBrand, radius: 1.12, height: 0.12, at: [0, 0.8, 0], segments: 28)
        k.roundedCylinder(.trim, radius: 1.25, height: 0.25, r: 0.06, at: [0, 0.125, 0])
        for a in stride(from: Float(0), to: 2 * .pi, by: .pi / 2) { k.box(.trim, [0.1, 0.5, 0.1], at: [cos(a) * 1.15, 0.4, sin(a) * 1.15]) }
        k.cylinder(.chrome, radius: 0.14, height: 0.3, at: [0, 3.45, 0], segments: 12)
        k.cylinder(.lensRed, radius: 0.18, height: 0.06, at: [0, 3.6, 0], segments: 12)
    }
}

/// A stack whose layers pop in and out (stock levels you can see).
private final class LayeredStack {
    let root = Entity()
    private var layers: [Entity] = []
    private var scales: [Float] = []
    var wanted = 0

    init(unit: StockUnit, layerCount: Int, tone: Mat, index: Int) {
        if unit.hasBase { root.addChild(Kit.entity("stock.palletBase") { Props.palletBase($0) }) }
        let containerColors: [Mat] = [.brand, .container, .carCoral, .carSand, .rivalNavy, .carSlate, .carMint, .white]
        for i in 0..<layerCount {
            let layer = Entity()
            layer.position = [0, unit.baseHeight + Float(i) * unit.layerHeight, 0]
            switch unit {
            case .pallet:
                layer.addChild(Kit.entity("stock.boxes \(tone)") { StockModels.boxLayer($0, tone: tone) })
            case .container:
                let c = containerColors[(index * 3 + i * 5) % containerColors.count]
                layer.addChild(Kit.entity("container \(c)") { Vehicles.containerModel($0, c) })
            case .crate:
                layer.addChild(Kit.entity("stock.crates") { StockModels.crateLayer($0) })
            case .cage:
                layer.addChild(Kit.entity("stock.cage \(tone)") { StockModels.cage($0, tone: tone) })
            case .canister:
                layer.addChild(Kit.entity("stock.canister") { StockModels.canister($0) })
            }
            layer.scale = [1, 0.001, 1]
            layer.isEnabled = false
            root.addChild(layer)
            layers.append(layer)
            scales.append(0)
        }
    }

    /// Animate layers towards `wanted`: new ones pop up, removed ones shrink away.
    func update(dt: Float) {
        for i in 0..<layers.count {
            let target: Float = i < wanted ? 1 : 0
            let speed: Float = target > scales[i] ? 7 : 9
            scales[i] += (target - scales[i]) * (1 - exp(-speed * dt))
            if abs(target - scales[i]) < 0.002 { scales[i] = target }
            let visible = scales[i] > 0.01
            layers[i].setEnabled(visible)          // settled layers aren't rewritten every frame
            if visible {
                let s = scales[i]
                let pop = target > 0 ? 1 + sin(min(s, 1) * .pi) * 0.12 : 1
                layers[i].setScale([pop, max(s, 0.001), pop])
            }
        }
    }
}

/// Where a region shows its stock and the loads waiting at the dock.
struct StockLayout {
    var unit: StockUnit
    var slots: [(position: V3, yaw: Float)]
    var layers: Int
    var scale: Float = Props.toyScale
    var dockSlots: [(position: V3, yaw: Float)] = []
    var dockLayers: Int = 2
    /// How many of the dock slots are in use right now (Riverside opens more bays as it grows). Nil = all.
    var activeDockSlots: ((GameModel) -> Int)?
}

/// Connects the game numbers to things you can see in the world:
/// stock stacks, loads on the dock, money popups, and machines that join as you level up.
final class GameVisuals: WorldAnimator {
    private let game: GameModel
    private let arView: ARView
    private var stock: [LayeredStack] = []
    private var dock: [LayeredStack] = []
    private let layers: Int
    private let dockLayers: Int
    private let activeDockSlots: ((GameModel) -> Int)?
    private var popups: [(label: UILabel, anchor: V3, age: Float)] = []
    private var unlocks: [(entity: Entity, condition: (GameModel) -> Bool, shown: Bool, pop: Float, scale: Float)] = []

    init(game: GameModel, arView: ARView, root: Entity, layout: StockLayout) {
        self.game = game
        self.arView = arView
        layers = layout.layers
        dockLayers = layout.dockLayers
        activeDockSlots = layout.activeDockSlots
        let tones: [Mat] = [.cardboard, .cardboardLight, .cardboardDark]
        for (i, slot) in layout.slots.enumerated() {
            let stack = LayeredStack(unit: layout.unit, layerCount: layout.layers, tone: tones[i % 3], index: i)
            stack.root.position = slot.position
            stack.root.scale = V3(repeating: layout.scale)
            stack.root.orientation = simd_quatf(angle: slot.yaw, axis: [0, 1, 0])
            root.addChild(stack.root)
            stock.append(stack)
        }
        for (i, slot) in layout.dockSlots.enumerated() {
            let stack = LayeredStack(unit: layout.unit, layerCount: layout.dockLayers, tone: .cardboardLight, index: i + 7)
            stack.root.position = slot.position
            stack.root.scale = V3(repeating: layout.scale)
            stack.root.orientation = simd_quatf(angle: slot.yaw, axis: [0, 1, 0])
            root.addChild(stack.root)
            dock.append(stack)
        }
    }

    /// Something that appears (with a pop) once a condition is met, e.g. a second forklift at Put-away level 10.
    func unlock(_ entity: Entity, when condition: @escaping (GameModel) -> Bool) {
        entity.isEnabled = false
        unlocks.append((entity, condition, false, 1, entity.scale.x))
    }

    // MARK: Events

    /// Floating "+$80" above the vehicle that just left (or above the dock if it isn't visible).
    func dispatched(amount: Double, at position: V3?) {
        let anchor = (position ?? V3(0, 0, 18)) + [0, 8.6, 0]
        let label = UILabel()
        label.text = "+" + Format.money(amount)
        label.font = UIFont.systemFont(ofSize: 22, weight: .heavy).rounded
        label.textColor = UIColor(hex: 0x2E9E5B)
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 6
        label.layer.shadowOffset = .zero
        label.sizeToFit()
        label.isUserInteractionEnabled = false
        arView.addSubview(label)
        popups.append((label, anchor, 0))
    }

    /// Remove floating labels (when the world is rebuilt).
    func tearDown() {
        for p in popups { p.label.removeFromSuperview() }
        popups = []
    }

    // MARK: Per frame

    func update(dt: Float, time: Float) {
        // Stock fill → layers in the stacks
        let fill = game.stock / max(game.stockCapacity, 1)
        let totalLayers = Int((fill * Double(stock.count * layers)).rounded())
        for (i, stack) in stock.enumerated() {
            stack.wanted = min(max(totalLayers - i * layers, 0), layers)
            stack.update(dt: dt)
        }
        // Shipping buffer → loads waiting at the dock (all of them together = one vehicle load)
        if !dock.isEmpty {
            let active = min(activeDockSlots?(game) ?? dock.count, dock.count)
            let dockTotal = Int((min(game.shipping / max(game.truckload, 1), 1) * Double(active * dockLayers)).rounded(.down))
            for (i, stack) in dock.enumerated() {
                stack.root.setEnabled(i < active)      // slots of bays that aren't open (or built) stay away
                guard i < active else { continue }
                stack.wanted = min(max(dockTotal - i * dockLayers, 0), dockLayers)
                stack.update(dt: dt)
            }
        }
        // Unlocks pop in
        for i in unlocks.indices {
            if !unlocks[i].shown && unlocks[i].condition(game) {
                unlocks[i].shown = true
                unlocks[i].entity.setEnabled(true)
                unlocks[i].pop = 0
            }
            if unlocks[i].pop < 1 {
                unlocks[i].pop = min(unlocks[i].pop + dt * 2.5, 1)
                let p = unlocks[i].pop
                let s = unlocks[i].scale * (p < 1 ? (0.6 + 0.4 * smootherstep(p) + sin(p * .pi) * 0.12) : 1)
                unlocks[i].entity.scale = V3(repeating: s)
            }
        }
        // Floating money: rise and fade
        popups = popups.filter { popup in
            let age = popup.age
            guard age < 1.6, let p = arView.project(popup.anchor) else {
                popup.label.removeFromSuperview()
                return false
            }
            let rise = CGFloat(smootherstep(age / 1.6)) * 46
            popup.label.center = CGPoint(x: p.x, y: p.y - rise)
            popup.label.alpha = CGFloat(age < 1.1 ? 1 : 1 - (age - 1.1) / 0.5)
            let s = CGFloat(age < 0.25 ? 0.6 + 0.4 * smootherstep(age / 0.25) + sin(age / 0.25 * .pi) * 0.15 : 1)
            popup.label.transform = CGAffineTransform(scaleX: s, y: s)
            return true
        }
        for i in popups.indices { popups[i].age += dt }
    }
}

extension UIFont {
    var rounded: UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
