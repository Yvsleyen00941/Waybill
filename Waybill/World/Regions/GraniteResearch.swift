import RealityKit
import UIKit

/// What each Granite Pass research project adds to the railhead.
enum GraniteResearch {
    static func install(_ rv: ResearchVisuals, trains: TrainFleetVisual, game: GameModel) {
        rv.register("r3.hydro", focus: [GraniteWorld.riverX, 0, -60]) { rv in dam(rv) }
        rv.register("r3.gantry", focus: [-8, 0, 10]) { rv in gantry(rv) }
        rv.register("r3.chalet", focus: [-82, 0, 32]) { rv in chalet(rv) }
        rv.register("r3.catenary", focus: [0, 0, -10]) { _ in
            trains.electrified = true
            return catenary()
        }
        rv.register("r3.sidings", focus: [-50, 0, -4]) { _ in platformExtension() }
        rv.register("r3.snowsheds", focus: [-82, 0, -14]) { _ in snowShed() }
        rv.register("r3.loader", focus: [0, 0, -6]) { _ in loader() }
        rv.register("r3.observatory", focus: [-40, 0, -150]) { rv in observatory(rv) }
    }

    // MARK: Hydro power: a dam across the river upstream

    static func dam(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        let x = GraniteWorld.riverX, z: Float = -62
        s.box(.concreteDark, [34, 11, 4], at: [x, 5.5, z])
        s.box(.concrete, [36, 0.8, 5], at: [x, 11.2, z])
        for dx: Float in [-12, -4, 4, 12] { s.box(.concreteDark, [1.2, 11, 5.2], at: [x + dx, 5.5, z]) }
        s.box(.skylight, [6, 10, 0.4], at: [x, 5.5, z + 2.2])          // spillway
        s.rounded(.white, [8, 5, 6], radius: 0.15, at: [x + 22, 2.5, z + 6]) // powerhouse
        s.box(.brand, [8.2, 0.4, 6.2], at: [x + 22, 5.1, z + 6])
        // Reservoir behind the dam
        s.box(.water, [24, 0.1, 40], at: [x, 9.0, z - 22])
        for dx: Float in [-13, 13] { s.box(.rock, [3, 10, 40], at: [x + dx, 5, z - 22]) }
        s.build(into: group)
        rv.site.lampHeads.append(Geo.part(group, Geo.box([7.8, 0.2, 0.2]), Materials.glowing(base: .white, glow: Palette.lampGlow, intensity: 0), at: [x + 22, 4.6, z + 9.05]))
        rv.onLightsChanged?()
        return group
    }

    // MARK: Gantry crane over the yard and the siding

    static func gantry(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        for z: Float in [-11, 34] { s.box(.darkMetal, [90, 0.05, 0.5], at: [-6, 0.06, z]) }
        s.build(into: group)
        let g = Entity()
        g.position = [-20, 0, 0]
        group.addChild(g)
        let gs = Scenery()
        for z: Float in [-11, 34] {
            for x: Float in [-3, 3] { gs.box(.brand, [1, 17, 1], at: [x, 8.5, z]) }
            gs.box(.darkMetal, [7.4, 1.2, 2], at: [0, 0.6, z])
        }
        for x: Float in [-3, 3] { gs.box(.brand, [1.2, 1.8, 47], at: [x, 17.4, 11.5]) }
        gs.rounded(.white, [6.4, 2, 3.6], radius: 0.12, at: [0, 16, 8])
        gs.box(.forklift, [4, 0.4, 3], at: [0, 9, 8])
        gs.build(into: g)
        rv.animate(SlideAnimator(g, axis: [1, 0, 0], from: -36, to: 24, period: 48))
        return group
    }

    // MARK: Crew chalet with a smoking chimney

    static func chalet(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let c = V3(-84, 0, 33)
        let s = Scenery()
        s.rounded(.crate, [12, 5, 9], radius: 0.15, at: c + [0, 2.5, 0])
        s.gable(.carCoral, width: 10.4, rise: 4, length: 13.4, at: c + [0, 5, 0], yaw: .pi / 2)
        s.gable(.snow, width: 10.8, rise: 4.15, length: 13, at: c + [0, 5.22, 0], yaw: .pi / 2)
        s.rounded(.rock, [1.2, 3, 1.2], radius: 0.1, at: c + [3.5, 8, -1.5])
        s.box(.pallet, [12.4, 0.3, 2.4], at: c + [0, 2.6, 5.4])
        s.groundShadow(.rect, center: c + [0.4, 0.05, 0.3], size: [16, 13])
        // Stacked firewood
        for k in 0..<3 { s.cylinder(.bark, radius: 0.25, height: 2.2, at: c + [-4 + Float(k) * 0.55, 0.3, 5.8], pitch: .pi / 2) }
        s.build(into: group)
        var windows = MeshBuilder()
        for wx: Float in [-3.5, 0, 3.5] { windows.addBox([1.6, 1.4, 0.08], .make(c + [wx, 2.4, 4.53])) }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: Palette.glass, glow: Palette.windowGlow, intensity: 0)])
            group.addChild(e)
            rv.site.windows.append(e)
        }
        rv.animate(SmokeAnimator(parent: group, at: c + [3.5, 9.8, -1.5]))
        rv.onLightsChanged?()
        return group
    }

    // MARK: Electrified line: masts and wires

    static func catenary() -> Entity {
        let group = Entity()
        let s = Scenery()
        var x: Float = -90
        while x < 128 {
            let onBridge = x > 76 && x < 110
            let base: Float = onBridge ? GraniteWorld.bridgeY : 0
            s.box(.darkMetal, [0.3, 7.4, 0.3], at: [x, base + 3.7, GraniteWorld.mainZ - 3.4])
            s.box(.darkMetal, [0.2, 0.2, 4.2], at: [x, base + 7.2, GraniteWorld.mainZ - 1.6])
            if x > -42 && x < 40 {
                s.box(.darkMetal, [0.3, 7.4, 0.3], at: [x, 3.7, GraniteWorld.sidingZ + 3.4])
                s.box(.darkMetal, [0.2, 0.2, 4.0], at: [x, 7.2, GraniteWorld.sidingZ + 1.6])
            }
            x += 18
        }
        s.box(.darkMetal, [218, 0.06, 0.06], at: [19, 6.7, GraniteWorld.mainZ])
        s.box(.darkMetal, [82, 0.06, 0.06], at: [-1, 6.7, GraniteWorld.sidingZ])
        s.build(into: group)
        return group
    }

    // MARK: Longer sidings: the platform grows west

    static func platformExtension() -> Entity {
        let group = Entity()
        let s = Scenery()
        s.box(.concrete, [16, 1.0, 5.0], at: [-55, 0.5, -0.7])
        s.box(.marking, [16, 0.02, 0.2], at: [-55, 1.01, -3.0])
        for x: Float in [-60, -51] { s.box(.white, [0.3, 4.4, 0.3], at: [x, 3.2, 1.0]) }
        s.box(.brand, [16, 0.4, 4.6], at: [-55, 5.5, -0.4])
        s.box(.snow, [15.6, 0.25, 4.3], at: [-55, 5.82, -0.4])
        s.build(into: group)
        return group
    }

    // MARK: Snow shed over the line near the west tunnel

    static func snowShed() -> Entity {
        let group = Entity()
        let s = Scenery()
        let z = GraniteWorld.mainZ
        s.box(.concreteDark, [26, 0.9, 10], at: [-82, 7.6, z])
        s.box(.snow, [25.6, 0.5, 9.6], at: [-82, 8.3, z])
        var x: Float = -94
        while x <= -70 {
            s.box(.concrete, [1.0, 7.2, 1.0], at: [x, 3.6, z + 4.4])
            x += 4
        }
        s.box(.concreteDark, [26, 7.2, 1.4], at: [-82, 3.6, z - 4.6])
        s.build(into: group)
        return group
    }

    // MARK: Rapid loader: a tower over the siding

    static func loader() -> Entity {
        let group = Entity()
        let s = Scenery()
        let x: Float = 2, z = GraniteWorld.sidingZ
        for dz: Float in [-3.4, 3.4] {
            for dx: Float in [-3, 3] { s.box(.brand, [0.8, 14, 0.8], at: [x + dx, 7, z + dz]) }
        }
        s.rounded(.white, [8, 6, 8], radius: 0.2, at: [x, 15, z])
        s.box(.brand, [8.2, 0.6, 8.2], at: [x, 18.2, z])
        s.cone(.white, radius: 2.4, height: 2.8, at: [x, 11, z])
        s.box(.forklift, [1.4, 3.2, 1.4], at: [x, 8.4, z])
        s.rounded(.white, [5, 16, 5], radius: 2.4, at: [x - 9, 8, z - 9])   // silo
        s.box(.metal, [10, 0.8, 1.2], at: [x - 4.5, 16, z - 4.5], yaw: deg(45))
        s.build(into: group)
        return group
    }

    // MARK: Summit observatory

    static func observatory(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let peak = V3(-40, 135, -175) // top of the big northern peak
        let s = Scenery()
        s.rounded(.white, [8, 3, 8], radius: 0.3, at: peak + [0, -1, 0])
        s.sphere(.white, radius: 4, at: peak + [0, 1.6, 0], scale: [1, 0.85, 1])
        s.box(.darkMetal, [0.9, 3.2, 8.2], at: peak + [0, 2.2, 0], yaw: deg(30))
        s.build(into: group)
        rv.site.lampHeads.append(Geo.part(group, Geo.box([0.6, 2.6, 0.4]), Materials.glowing(base: .white, glow: UIColor(hex: 0x9AA8FF), intensity: 0),
                                          at: peak + [2.8, 2.4, 1.6], yaw: deg(30)))
        rv.onLightsChanged?()
        return group
    }
}

/// Slides an entity back and forth along an axis (gantry cranes).
final class SlideAnimator: WorldAnimator {
    private let entity: Entity
    private let axis: V3
    private let from: Float
    private let to: Float
    private let period: Float
    init(_ entity: Entity, axis: V3, from: Float, to: Float, period: Float) {
        self.entity = entity
        self.axis = axis
        self.from = from
        self.to = to
        self.period = period
    }
    func update(dt: Float, time: Float) {
        let u = (sin(time * 2 * .pi / period) + 1) / 2
        let base = entity.position - axis * simd_dot(entity.position, axis)
        entity.position = base + axis * lerp(from, to, smootherstep(u))
    }
}

/// Soft smoke puffs rising from a chimney.
final class SmokeAnimator: WorldAnimator {
    private var puffs: [(entity: ModelEntity, age: Float)] = []
    private let origin: V3

    init(parent: Entity, at origin: V3) {
        self.origin = origin
        for i in 0..<6 {
            let e = ModelEntity(mesh: Geo.sphere(radius: 0.6), materials: [Materials.matte(UIColor(hex: 0xEEF0F8), roughness: 1)])
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            parent.addChild(e)
            puffs.append((e, Float(i) * 1.0))
        }
    }

    func update(dt: Float, time: Float) {
        for i in puffs.indices {
            puffs[i].age += dt
            let a = puffs[i].age.truncatingRemainder(dividingBy: 6)
            let u = a / 6
            puffs[i].entity.position = origin + [u * 2.5 + sin(a) * 0.3, u * 7, u * 1.2]
            puffs[i].entity.scale = V3(repeating: 0.5 + u * 2.2)
            puffs[i].entity.components.set(OpacityComponent(opacity: (1 - u) * 0.8))
        }
    }
}
