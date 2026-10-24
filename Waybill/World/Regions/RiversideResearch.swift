import RealityKit
import UIKit

/// What each Riverside research project adds to the depot.
enum RiversideResearch {
    /// - annex: the group at the hall's east end; the conveyor, high-bay racks and cold store stand there and move along when the hall grows.
    static func install(_ rv: ResearchVisuals, forklifts: [Vehicle], docks: [Vehicle], fleet: YardFleetVisual, annex: Entity) {
        rv.register("r1.solar", focus: [0, 0, 2]) { _ in solarRoof() }
        rv.register("r1.canteen", focus: [-24, 0, -11]) { rv in canteen(rv) }
        rv.register("r1.eforklift", focus: [-26, 0, 22]) { _ in
            electrify(forklifts)
            return chargers()
        }
        rv.register("r1.floodlights", focus: [20, 0, 30]) { rv in floodlights(rv) }
        rv.register("r1.conveyor", focus: [8, 0, 6], parent: annex) { rv in conveyor(rv) }
        rv.register("r1.routes", focus: [0, 0, 24]) { _ in
            fleet.decorate("aero", aeroKit)
            return nil
        }
        rv.register("r1.highbay", focus: [14, 0, -12], parent: annex) { _ in highBay() }
        rv.register("r1.coldchain", focus: [3, 0, -7], parent: annex) { _ in
            fleet.decorate("reefer", reeferUnit)
            return coldStore()
        }
    }

    // MARK: Solar roof

    /// Rows of panels on three roof slopes (the middle section keeps its roundel).
    static func solarRoof() -> Entity {
        let W = Warehouse.sectionWidth * 3, H = Warehouse.height
        let sectionW = W / 3, rise: Float = 2.2
        let slope = atan2(rise, sectionW / 2)
        let group = Entity()
        group.position = [0, H + rise / 2, 0] // grows onto the roof, not up from the ground
        let s = Scenery()
        for k in 0..<3 {
            let cx = -W / 2 + sectionW * (Float(k) + 0.5)
            let side: Float = k == 1 ? -1 : 1
            s.group(.make([cx + side * sectionW / 4, 0.3, 0], roll: -side * slope)) {
                for col: Float in [-1.45, 1.45] {
                    for row in 0..<5 {
                        let z = -3.6 + Float(row) * 1.8
                        s.box(.white, [2.72, 0.05, 1.68], at: [col, 0.02, z])
                        s.box(.solar, [2.58, 0.08, 1.54], at: [col, 0.06, z])
                        for dx: Float in [-0.86, 0, 0.86] { s.box(.skylight, [0.02, 0.09, 1.54], at: [col + dx, 0.07, z]) }
                    }
                }
            }
        }
        s.build(into: group)
        return group
    }

    // MARK: Staff canteen

    static func canteen(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        group.position = [-24, 0, -13.5]
        let s = Scenery()
        // Terrace and building
        s.box(.concrete, [9, 0.06, 6.5], at: [0, 0.03, 2.4])
        s.rounded(.white, [6.4, 3.2, 4.2], radius: 0.12, at: [0, 1.6, -2.2])
        s.box(.brand, [7.0, 0.3, 4.8], at: [0, 3.35, -2.2])
        s.box(.glass, [4.2, 1.7, 0.08], at: [-0.7, 1.55, -0.07])
        s.box(.glass, [1.1, 2.3, 0.08], at: [2.3, 1.15, -0.07])
        s.box(.carCoral, [6.4, 0.1, 1.5], at: [0, 2.72, 0.62], pitch: 0.18)
        s.groundShadow(.rect, center: [0.2, 0.07, -2.0], size: [8.4, 6.4])
        // Tables with parasols (toy scale, like the pallets)
        let tables: [(V3, Mat)] = [([-2.8, 0, 2.2], .carCoral), ([0.4, 0, 3.6], .carSand), ([3.2, 0, 2.0], .carMint)]
        for (p, canopy) in tables {
            s.group(.make(p, scale: V3(repeating: 1.3))) {
                s.cylinder(.white, radius: 0.55, height: 0.06, at: [0, 0.75, 0])
                s.cylinder(.darkMetal, radius: 0.05, height: 0.72, at: [0, 0.37, 0])
                s.cylinder(.white, radius: 0.035, height: 2.3, at: [0, 1.15, 0])
                s.cone(canopy, radius: 1.25, height: 0.42, at: [0, 2.05, 0])
                for dz: Float in [-0.62, 0.62] { s.box(.pallet, [1.1, 0.07, 0.28], at: [0, 0.45, dz]) }
                s.groundShadow(.round, center: [0.3, 0.07, -0.2], size: [2.8, 2.8])
            }
        }
        Props.bush(s, at: [-4.2, 0, 0.6], size: 0.7)
        Props.bush(s, at: [4.3, 0, -0.2], size: 0.8)
        s.build(into: group)
        // A few people on their break
        for (p, vest) in [(V3(-2.2, 0, 3.4), Mat.hiVis), (V3(1.2, 0, 4.6), .brand), (V3(3.9, 0, 3.0), .hiVis)] {
            let person = Vehicles.person(vest: vest)
            person.root.position = p
            person.root.orientation = simd_quatf(angle: Float(p.x) * 0.7, axis: [0, 1, 0])
            group.addChild(person.root)
            rv.animate(PersonAnimator(person, seed: p.x))
        }
        return group
    }

    // MARK: Electric forklifts

    static func electrify(_ forklifts: [Vehicle]) {
        for v in forklifts {
            v.repaint(.paintWhite)
            Geo.part(v.body, Geo.box([1.72, 0.12, 1.17], radius: 0.04), .mint, at: [0.05, 0.9, 0])
        }
    }

    static func chargers() -> Entity {
        let group = Entity()
        group.position = [-34.4, 0, 21]
        group.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        let s = Scenery()
        for x: Float in [-1.1, 1.1] {
            s.rounded(.white, [0.55, 1.6, 0.4], radius: 0.1, at: [x, 0.8, 0])
            s.box(.brand, [0.57, 0.18, 0.42], at: [x, 1.52, 0])
        }
        for (dx, w) in [(-2.2, 0.12), (2.2, 0.12)] as [(Float, Float)] { s.box(.mint, [w, 0.02, 3.6], at: [dx, 0.04, -1.6]) }
        s.box(.mint, [4.52, 0.02, 0.12], at: [0, 0.04, -3.4])
        s.groundShadow(.rect, center: [0, 0.05, 0], size: [3.4, 1.4])
        s.build(into: group)
        for x: Float in [-1.1, 1.1] {
            Geo.part(group, Geo.box([0.32, 0.3, 0.04], radius: 0.03), Materials.glowing(base: Palette.white, glow: UIColor(hex: 0x5FCB9A), intensity: 1.4),
                     at: [x, 1.12, 0.21])
        }
        return group
    }

    // MARK: Floodlights

    static func floodlights(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        // Corner masts (and one outside the south fence) aimed into the yard
        let masts: [(V3, Float)] = [([-35, 0, 40.5], deg(40)), ([28, 0, 43.9], deg(90)), ([91, 0, 40.5], deg(140)), ([91, 0, -18.5], deg(-140))]
        for (p, yaw) in masts {
            s.cylinder(.darkMetal, radius: 0.24, height: 15, at: p + [0, 7.5, 0])
            s.group(.make(p + [0, 15, 0], yaw: yaw)) {
                s.box(.darkMetal, [0.3, 0.28, 3.2], at: [0, 0, 0])
            }
            s.groundShadow(.round, center: p + [0, 0.05, 0], size: [1.6, 1.6])
            let heading = V3(cos(yaw), 0, -sin(yaw))
            for k in [-1.1, 0, 1.1] as [Float] {
                let side = V3(-heading.z, 0, heading.x) * k
                let lamp = Geo.part(group, Geo.box([0.5, 0.55, 0.9], radius: 0.06),
                                    Materials.glowing(base: UIColor(hex: 0xF4F1E6), glow: Palette.lampGlow, intensity: 0),
                                    at: p + [0, 14.75, 0] + side + heading * 0.35, yaw: yaw, roll: -0.5)
                rv.site.lampHeads.append(lamp)
            }
            let pool = Geo.decal(group, mask: Textures.lightPool, tint: Palette.lampGlow, opacity: 0.62,
                                 size: [34, 34], at: p + heading * 13 + [0, 0.1, 0])
            pool.components.set(OpacityComponent(opacity: 0))
            rv.site.lightPools.append(pool)
        }
        s.build(into: group)
        rv.onLightsChanged?()
        return group
    }

    // MARK: Conveyor line (hall → parcel shed on the east side)

    static func conveyor(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        let z: Float = 6, y: Float = 2.5, x0: Float = 0.1, x1: Float = 14.4
        let mid = (x0 + x1) / 2, length = x1 - x0
        var x = x0 + 1
        while x < x1 {
            for dz: Float in [-0.48, 0.48] { s.box(.darkMetal, [0.14, y - 0.15, 0.14], at: [x, (y - 0.15) / 2, z + dz]) }
            s.groundShadow(.rect, center: [x, 0.05, z], size: [0.9, 1.8])
            x += 3
        }
        s.box(.metal, [length, 0.24, 1.2], at: [mid, y - 0.12, z])
        s.box(.belt, [length, 0.06, 1.0], at: [mid, y + 0.02, z])
        for dz: Float in [-0.56, 0.56] { s.box(.brand, [length, 0.22, 0.08], at: [mid, y + 0.12, z + dz]) }
        s.box(.interior, [0.06, 1.3, 1.4], at: [x0 + 0.03, y + 0.6, z])
        // Parcel shed at the end
        s.rounded(.white, [3.6, 3.6, 3.8], radius: 0.1, at: [x1 + 1.85, 1.8, z])
        s.box(.brand, [4.1, 0.26, 4.3], at: [x1 + 1.85, 3.7, z])
        s.box(.interior, [0.06, 1.3, 1.4], at: [x1 + 0.02, y + 0.6, z])
        s.groundShadow(.rect, center: [x1 + 1.85, 0.05, z], size: [5, 5])
        s.build(into: group)
        // Boxes riding the belt
        let boxMesh = Geo.box(Props.boxSize, radius: 0.035)
        var boxes: [Entity] = []
        for i in 0..<9 {
            let box = Entity()
            Geo.part(box, boxMesh, [Mat.cardboard, .cardboardLight, .cardboardDark][i % 3], at: .zero)
            group.addChild(box)
            boxes.append(box)
        }
        let top = y + 0.05 + Props.boxSize.y * Props.toyScale / 2
        rv.animate(ConveyorAnimator(boxes: boxes, from: [x0 + 0.1, top, z], to: [x1 - 0.1, top, z], speed: 1.5))
        return group
    }

    // MARK: Trucks

    /// Roof fairing and side skirts in brand colour.
    static func aeroKit(_ v: Vehicle) {
        Geo.part(v.body, Geo.box([1.35, 0.5, 2.3], radius: 0.14), .brand, at: [2.95, 3.95, 0], roll: -0.3)
        for side: Float in [1, -1] {
            Geo.part(v.body, Geo.box([4.0, 0.5, 0.06], radius: 0.03), .brand, at: [0.35, 0.8, 1.25 * side])
        }
    }

    /// A refrigeration unit on the front of the box.
    static func reeferUnit(_ v: Vehicle) {
        Geo.part(v.body, Geo.box([0.42, 1.1, 2.0], radius: 0.08), .white, at: [2.0, 3.6, 0])
        Geo.part(v.body, Geo.box([0.05, 0.75, 1.5], radius: 0.02), .darkMetal, at: [2.22, 3.6, 0])
    }

    // MARK: High-bay racking

    static func highBay() -> Entity {
        let group = Entity()
        let s = Scenery()
        var rng = SeededRandom(seed: 314)
        Props.rack(s, at: [13.0, 0, -12], yaw: .pi / 2, bays: 3, levels: 4, rng: &rng)
        Props.rack(s, at: [16.3, 0, -12], yaw: .pi / 2, bays: 3, levels: 4, rng: &rng)
        s.build(into: group)
        return group
    }

    // MARK: Cold store

    static func coldStore() -> Entity {
        let group = Entity()
        let s = Scenery()
        let c = V3(3.35, 0, -6.8), size = V3(6.6, 6.5, 8.0)
        s.rounded(.insulated, size, radius: 0.1, at: c + [0, size.y / 2, 0])
        s.box(.brand, [size.x + 0.04, 0.5, size.z + 0.04], at: c + [0, size.y - 0.5, 0])
        var y: Float = 1.2
        while y < size.y - 0.8 {
            s.box(.fence, [0.02, 0.04, size.z - 0.3], at: c + [size.x / 2 + 0.01, y, 0])
            y += 1.1
        }
        s.box(.metal, [0.08, 3.4, 2.8], at: c + [size.x / 2 + 0.03, 1.9, 0])
        for dz: Float in [-1.6, 1.6] { s.rounded(.darkMetal, [0.3, 0.5, 0.26], radius: 0.06, at: c + [size.x / 2 + 0.15, 0.6, dz]) }
        for (dx, dz) in [(-0.9, -2.2), (1.2, 1.6)] as [(Float, Float)] {
            s.rounded(.metal, [1.8, 0.9, 1.4], radius: 0.08, at: c + [dx, size.y + 0.45, dz])
            s.cylinder(.darkMetal, radius: 0.48, height: 0.06, at: c + [dx, size.y + 0.93, dz])
        }
        s.groundShadow(.rect, center: c + [0, 0.05, 0], size: [size.x + 3, size.z + 3])
        s.build(into: group)
        let flake = ModelEntity(mesh: .generatePlane(width: 2.2, height: 2.2),
                                materials: [Materials.paintedDecal(mask: Textures.symbol("snowflake"), tint: Palette.brand)])
        flake.transform = Transform(matrix: .make(c + [size.x / 2 + 0.03, 4.3, 2.6], yaw: .pi / 2))
        flake.components.set(DynamicLightShadowComponent(castsShadow: false))
        group.addChild(flake)
        return group
    }
}
