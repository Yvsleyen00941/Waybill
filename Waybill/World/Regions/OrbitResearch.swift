import RealityKit
import UIKit

/// What each Orbit research project adds to the launch site.
enum OrbitResearch {
    static func install(_ rv: ResearchVisuals, rockets: RocketFleetVisual, game: GameModel) {
        rv.register("r5.solarfarm", focus: [-104, 0, -40]) { _ in solarFarm() }
        rv.register("r5.landing", focus: [10, 0, -56]) { _ in
            rockets.boosterLanding = true
            return landingZone()
        }
        rv.register("r5.cleanroom", focus: [30, 0, 32]) { rv in cleanRoom2(rv) }
        rv.register("r5.methane", focus: [92, 0, 34]) { rv in methanePlant(rv) }
        rv.register("r5.pad", focus: [58, 0, 24]) { _ in secondPad() }
        rv.register("r5.fairing", focus: [58, 0, -20]) { _ in
            rockets.stretched = true
            return nil
        }
        rv.register("r5.elevator", focus: [-110, 0, 60]) { rv in tether(rv) }
    }

    static func solarFarm() -> Entity {
        let group = Entity()
        let s = Scenery()
        for row in 0..<6 {
            for col in 0..<5 {
                let p = V3(-128 + Float(col) * 11, 0, -64 + Float(row) * 8)
                s.box(.white, [9.6, 0.1, 3.6], at: p + [0, 1.7, 0], pitch: -0.4)
                s.box(.solar, [9.4, 0.12, 3.4], at: p + [0, 1.75, 0], pitch: -0.4)
                for dx: Float in [-4, 4] { s.box(.steel, [0.2, 1.6, 0.2], at: p + [dx, 0.8, 0]) }
            }
        }
        s.build(into: group)
        return group
    }

    static func landingZone() -> Entity {
        let group = Entity()
        let s = Scenery()
        let p = V3(10, 0, -56)
        s.cylinder(.concrete, radius: 13, height: 0.3, at: p + [0, 0.15, 0])
        s.build(into: group)
        Geo.decal(group, mask: Textures.ring, tint: .white, opacity: 0.9, size: [22, 22], at: p + [0, 0.33, 0])
        Geo.decal(group, mask: Textures.symbol("xmark"), tint: Palette.brand, opacity: 0.9, size: [10, 10], at: p + [0, 0.34, 0])
        return group
    }

    static func cleanRoom2(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        let c = V3(30, 0, 30)
        s.rounded(.white, [24, 12, 14], radius: 0.25, at: c + [0, 6, 0])
        s.box(.brand, [24.3, 1.0, 14.3], at: c + [0, 11, 0])
        s.box(.steel, [8, 8, 0.2], at: c + [0, 4, 7.05])
        s.build(into: group)
        var windows = MeshBuilder()
        for x: Float in [-8, 8] { windows.addBox([3, 2.4, 0.08], .make(c + [x, 7, 7.05])) }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: Palette.glass, glow: Palette.windowGlow, intensity: 0)])
            group.addChild(e)
            rv.site.windows.append(e)
        }
        rv.onLightsChanged?()
        return group
    }

    static func methanePlant(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        let c = V3(92, 0, 34)
        for (i, dx) in [Float(-8), -3, 2].enumerated() {
            s.cylinder(i == 1 ? .steel : .white, radius: 2.2, height: 14, at: c + [dx, 7, -4])
            s.sphere(i == 1 ? .steel : .white, radius: 2.2, at: c + [dx, 14, -4], scale: [1, 0.5, 1])
        }
        s.rounded(.white, [12, 5, 7], radius: 0.15, at: c + [0, 2.5, 6])
        s.box(.brand, [12.2, 0.4, 7.2], at: c + [0, 5.1, 6])
        for z: Float in [0, 1.2] { s.box(.steel, [18, 0.4, 0.4], at: c + [-3, 3, z]) }
        s.cylinder(.darkMetal, radius: 0.5, height: 20, at: c + [9, 10, -6])
        s.build(into: group)
        let flare = Geo.part(group, Geo.cone(radius: 0.8, height: 2.6), Materials.glowing(base: UIColor(hex: 0xFFB45E), glow: UIColor(hex: 0xFFC67A), intensity: 12),
                             at: c + [9, 21.4, -6])
        rv.animate(Flicker(flare))
        return group
    }

    final class Flicker: WorldAnimator {
        let e: Entity
        init(_ e: Entity) { self.e = e }
        func update(dt: Float, time: Float) {
            let k = 1 + sin(time * 13) * 0.08 + sin(time * 29) * 0.05
            e.scale = [k, k * 1.1, k]
        }
    }

    static func secondPad() -> Entity {
        let group = Entity()
        let s = Scenery()
        OrbitWorld.buildPad(group, s, SiteParts(), at: OrbitWorld.pad1)
        // Crawlerway branch to the second pad
        let path = OrbitWorld.launchLayout().crawlerways[1]
        var d: Float = 0
        while d < path.length {
            let p = path.sample(d).position
            s.box(.sandDark, [3, 0.05, 3], at: p + [0, 0.05, 0])
            d += 2.4
        }
        s.build(into: group)
        return group
    }

    static func tether(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let base = V3(-110, 0, 60)
        let s = Scenery()
        s.cylinder(.concrete, radius: 9, height: 2, at: base + [0, 1, 0])
        s.rounded(.white, [10, 6, 10], radius: 0.4, at: base + [0, 5, 0])
        s.box(.brand, [10.3, 0.8, 10.3], at: base + [0, 7.6, 0])
        s.box(.steel, [0.3, 900, 0.3], at: base + [0, 458, 0])
        s.build(into: group)
        let climber = Entity()
        Geo.part(climber, Geo.box([3, 4, 3], radius: 0.4), .brand, at: .zero)
        Geo.part(climber, Geo.box([3.1, 0.6, 3.1], radius: 0.1), .white, at: [0, 1.2, 0])
        group.addChild(climber)
        rv.site.lampHeads.append(Geo.part(climber, Geo.sphere(radius: 0.4), Materials.glowing(base: .white, glow: Palette.tailLight, intensity: 0), at: [0, 2.4, 0]))
        rv.animate(MetroResearch.Shuttle(climber, from: base + [0, 10, 0], to: base + [0, 420, 0], period: 50))
        rv.onLightsChanged?()
        return group
    }
}
