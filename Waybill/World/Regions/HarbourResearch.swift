import RealityKit
import UIKit

/// What each Harbour City research project adds to the terminal.
enum HarbourResearch {
    static func install(_ rv: ResearchVisuals, cranes: [QuayCrane], fleet: YardFleetVisual, game: GameModel) {
        rv.register("r2.shorepower", focus: [0, 0, -20]) { _ in shorePower() }
        rv.register("r2.twinlift", focus: [0, 0, -16]) { _ in
            for c in cranes { twinLift(c) }
            return nil
        }
        rv.register("r2.lounge", focus: [28, 0, 36]) { rv in lounge(rv) }
        rv.register("r2.rmg", focus: [-42, 0, 9]) { rv in gantries(rv) }
        rv.register("r2.wind", focus: [110, 0, -76]) { rv in turbines(rv) }
        rv.register("r2.ocr", focus: [48, 0, 34]) { rv in smartGate(rv) }
        rv.register("r2.berth", focus: [-72, 0, -30]) { _ in secondShip() }
        rv.register("r2.reefer", focus: [-68, 0, 10]) { _ in reeferStacks() }
    }

    // MARK: Shore power: cabinets on the quay, cables to the ship

    static func shorePower() -> Entity {
        let group = Entity()
        let s = Scenery()
        for x: Float in [-28, 2, 30] {
            s.rounded(.mint, [2.2, 1.8, 1.2], radius: 0.12, at: [x, 0.9, -22])
            s.box(.white, [2.25, 0.22, 1.25], at: [x, 1.6, -22])
            s.cylinder(.darkMetal, radius: 0.16, height: 4.6, at: [x, 0.5, -24.4], pitch: .pi / 2)
            s.groundShadow(.rect, center: [x, 0.05, -22], size: [3, 2])
        }
        // Substation
        s.rounded(.white, [6, 3.2, 4.4], radius: 0.12, at: [-66, 1.6, -14])
        for dx: Float in [-1.8, 0, 1.8] { s.box(.marking, [0.5, 0.06, 4.45], at: [-66 + dx, 3.25, -14]) }
        s.box(.mint, [6.05, 0.4, 4.45], at: [-66, 2.6, -14])
        s.groundShadow(.rect, center: [-66, 0.05, -14], size: [8, 6])
        s.build(into: group)
        return group
    }

    // MARK: Twin-lift spreaders: each crane carries two containers side by side

    static func twinLift(_ crane: QuayCrane) {
        Geo.part(crane.spreader, Geo.box([12.4, 0.5, 2.6], radius: 0.06), .forklift, at: [0, 0, 2.8])
        let twin = Vehicles.container(ContainerColors.pick(Int(crane.root.position.x) + 9))
        twin.position = [0, 0, 2.8]
        crane.cargo.addChild(twin)
    }

    // MARK: Drivers' lounge by the gate

    static func lounge(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        group.position = [27, 0, 37]
        let s = Scenery()
        s.box(.concrete, [11, 0.06, 7], at: [0, 0.03, 0])
        s.rounded(.white, [6, 3, 4], radius: 0.12, at: [-1.5, 1.5, -1])
        s.box(.brand, [6.6, 0.3, 4.6], at: [-1.5, 3.15, -1])
        s.box(.glass, [4, 1.6, 0.08], at: [-1.5, 1.5, 1.04])
        s.box(.carCoral, [6, 0.1, 1.6], at: [-1.5, 2.6, 1.8], pitch: 0.18)
        s.rounded(.brand, [0.9, 1.9, 0.7], radius: 0.08, at: [2.5, 0.95, -1.6])
        s.rounded(.carMint, [0.9, 1.9, 0.7], radius: 0.08, at: [3.5, 0.95, -1.6])
        for x: Float in [-3, 0] { s.box(.pallet, [1.8, 0.1, 0.5], at: [x, 0.5, 2.8]) }
        s.groundShadow(.rect, center: [-1.5, 0.05, -0.8], size: [8, 6])
        s.build(into: group)
        for (p, vest) in [(V3(-2.5, 0, 3.6), Mat.hiVis), (V3(1, 0, 3.2), .carSlate)] {
            let person = Vehicles.person(vest: vest)
            person.root.position = p
            person.root.orientation = simd_quatf(angle: p.x, axis: [0, 1, 0])
            group.addChild(person.root)
            rv.animate(PersonAnimator(person, seed: p.x))
        }
        return group
    }

    // MARK: Automated stacking: rail-mounted gantries over block A

    static func gantries(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        for z: Float in [-6.5, 25.5] { s.box(.darkMetal, [44, 0.05, 0.4], at: [-42, 0.05, z]) }
        s.build(into: group)
        var movers: [Entity] = []
        for i in 0..<2 {
            let g = Entity()
            g.position = [-52 + Float(i) * 18, 0, 9.5]
            let gs = Scenery()
            for z: Float in [-16, 16] {
                for x: Float in [-2.2, 2.2] { gs.box(.white, [0.8, 15, 0.8], at: [x, 7.5, z]) }
                gs.box(.darkMetal, [5.6, 1.0, 1.6], at: [0, 0.5, z])
            }
            for x: Float in [-2.2, 2.2] { gs.box(.brand, [0.9, 1.4, 33], at: [x, 15.4, 0]) }
            gs.rounded(.brand, [5.6, 1.4, 3], radius: 0.1, at: [0, 14.2, Float(i) * 8 - 4])
            gs.box(.forklift, [12.4, 0.4, 2.6], at: [0, 9, Float(i) * 8 - 4], yaw: .pi / 2)
            gs.build(into: g)
            group.addChild(g)
            movers.append(g)
        }
        rv.animate(GantryAnimator(gantries: movers))
        return group
    }

    final class GantryAnimator: WorldAnimator {
        let gantries: [Entity]
        init(gantries: [Entity]) { self.gantries = gantries }
        func update(dt: Float, time: Float) {
            for (i, g) in gantries.enumerated() {
                let u = (sin(time * 0.12 + Float(i) * 2.1) + 1) / 2
                g.position.x = -56 + Float(i) * 14 + smootherstep(u) * 12
            }
        }
    }

    // MARK: Wind turbines on the breakwater

    static func turbines(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        for (i, p) in [V3(70, 0, -90), V3(110, 0, -79), V3(150, 0, -68)].enumerated() {
            let t = Entity()
            t.position = p + [0, 2.2, 0]
            group.addChild(t)
            Geo.part(t, MeshResource.generateCylinder(height: 1, radius: 1), .white, at: [0, 0.5, 0], scale: [1.4, 1, 1.4])
            var b = MeshBuilder()
            b.addCone(bottomRadius: 1.0, topRadius: 0.55, height: 38, segments: 14, .make([0, 19, 0]))
            if let tower = try? b.makeMesh(name: "turbineTower") { t.addChild(ModelEntity(mesh: tower, materials: [Materials.pbr(.white)])) }
            Geo.part(t, Geo.box([4.6, 2.0, 2.0], radius: 0.6), .white, at: [0.6, 38.6, 0])
            Geo.part(t, Geo.box([0.4, 0.4, 2.1], radius: 0.1), .brand, at: [-0.9, 38.6, 0])
            let rotor = Entity()
            rotor.position = [3.1, 38.6, 0]
            t.addChild(rotor)
            Geo.part(rotor, Geo.sphere(radius: 0.9), .white, at: .zero)
            for k in 0..<3 {
                let blade = Entity()
                blade.orientation = simd_quatf(angle: Float(k) * 2 * .pi / 3, axis: [1, 0, 0])
                rotor.addChild(blade)
                Geo.part(blade, Geo.box([0.35, 15, 1.1], radius: 0.15), .white, at: [0.2, 8, 0])
            }
            t.orientation = simd_quatf(angle: deg(-20), axis: [0, 1, 0])
            rv.animate(SpinAnimator(rotor, axis: [1, 0, 0], speed: 0.9 + Float(i) * 0.12))
        }
        return group
    }

    // MARK: Smart gate: camera portals over the lanes

    static func smartGate(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        for z: Float in [33.5] {
            for x: Float in [39, 48, 57] { s.box(.white, [0.5, 6.4, 0.5], at: [x, 3.2, z]) }
            s.box(.brand, [18.6, 0.9, 0.9], at: [48, 6.6, z])
            for x: Float in [43, 46, 50, 53] { s.rounded(.darkMetal, [0.7, 0.5, 0.9], radius: 0.08, at: [x, 5.9, z + 0.2]) }
        }
        s.build(into: group)
        let strip = Geo.part(group, Geo.box([18.4, 0.12, 0.1]), Materials.glowing(base: .white, glow: UIColor(hex: 0x7C8BFF), intensity: 0), at: [48, 6.1, 34])
        rv.site.lampHeads.append(strip)
        rv.onLightsChanged?()
        return group
    }

    // MARK: Second berth: another ship along the west quay

    static func secondShip() -> Entity {
        let ship = Vehicles.containerShip(seed: 11)
        ship.root.position = [-80, 0, quayZ - 8.6]
        return ship.root
    }

    static var quayZ: Float { HarbourWorld.quayZ }

    // MARK: Reefer stacks: powered racks of white containers

    static func reeferStacks() -> Entity {
        let group = Entity()
        let s = Scenery()
        for z: Float in [-1, 13, 27] where z < 25 {
            for tier in 0..<2 {
                s.rounded(.insulated, [2.44, 2.55, 12.2], radius: 0.06, at: [-68.6, 1.3 + Float(tier) * 2.6, z])
                s.box(.metal, [0.06, 1.6, 1.8], at: [-67.35, 1.4 + Float(tier) * 2.6, z + 5])
            }
        }
        for z: Float in [6, 20] {
            for x: Float in [-70.6, -66.6] { s.box(.marking, [0.3, 6.5, 0.3], at: [x, 3.25, z]) }
            s.box(.marking, [4.3, 0.3, 0.3], at: [-68.6, 6.4, z])
            for y: Float in [2.6, 5.2] { s.box(.marking, [4.3, 0.15, 1.2], at: [-68.6, y, z]) }
        }
        s.groundShadow(.rect, center: [-68.6, 0.05, 12], size: [4.6, 30])
        s.build(into: group)
        return group
    }
}
