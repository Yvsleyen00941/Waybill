import RealityKit
import UIKit

/// What each Metro research project adds to the hub.
enum MetroResearch {
    static var roof: Float { MetroWorld.hubSize.y + 0.75 }
    static var zc: Float { MetroWorld.hubFront - MetroWorld.hubSize.z / 2 }

    static func install(_ rv: ResearchVisuals, fleet: YardFleetVisual, game: GameModel) {
        rv.register("r4.facade", focus: [0, 0, -10]) { _ in solarRoof() }
        rv.register("r4.robots", focus: [-40, 0, 10]) { rv in robots(rv) }
        rv.register("r4.garden", focus: [-16, 0, -14]) { rv in garden(rv) }
        rv.register("r4.drones", focus: [18, 0, -14]) { rv in drones(rv) }
        rv.register("r4.lockers", focus: [-40, 0, 42]) { _ in lockers() }
        rv.register("r4.autonomous", focus: [0, 0, 20]) { _ in
            fleet.decorate("autonomous", Vehicles.autonomousKit)
            return nil
        }
        rv.register("r4.hyperloop", focus: [-60, 0, -14]) { rv in hyperloop(rv) }
        rv.register("r4.skyport", focus: [24, 0, -20]) { rv in skyport(rv) }
    }

    // MARK: Solar: panels across the east half of the roof

    static func solarRoof() -> Entity {
        let group = Entity()
        group.position = [0, roof, zc]
        let s = Scenery()
        for x in stride(from: Float(4), through: 28, by: 3.2) {
            for z in stride(from: Float(-10), through: 10, by: 2.4) {
                s.box(.white, [2.9, 0.06, 2.1], at: [x, 0.25, z], roll: 0.18)
                s.box(.solar, [2.75, 0.08, 1.95], at: [x, 0.3, z], roll: 0.18)
            }
        }
        s.build(into: group)
        return group
    }

    // MARK: Sorter swarm: little robots carrying totes between the stock area and the hub

    /// The robots' one-way loop (x, z): down the stock area between the cage rows, out through the fence, across to the
    /// hub's west wall (dropping totes at the hatch), back up beside the fence and in again. It stays west of the vans' lanes.
    static let robotLoop: [SIMD2<Float>] = [[-45, 29], [-45, -6], [-33.6, -6], [-33.6, 21], [-41.4, 21], [-41.4, 29]]
    static let robotHatch = SIMD2<Float>(-33.8, -6)

    static func robots(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        var bots: [(Entity, Entity)] = []
        for i in 0..<10 {
            let b = Entity()
            b.addChild(Kit.entity("sorter bot") { k in
                k.box(.paintWhite, [0.95, 0.32, 0.72], r: 0.14, at: [0, 0.24, 0])
                k.box(.hiVis, [0.97, 0.08, 0.74], r: 0.03, at: [0, 0.14, 0])
                k.box(.trim, [0.9, 0.06, 0.66], r: 0.02, at: [0, 0.42, 0])
                k.box(.glassDark, [0.04, 0.08, 0.3], r: 0.02, at: [0.48, 0.28, 0])
                for (x, z) in [(0.3, 0.33), (-0.3, 0.33), (0.3, -0.33), (-0.3, -0.33)] as [(Float, Float)] {
                    k.cylinder(.rubber, radius: 0.09, height: 0.06, at: [x, 0.09, z], pitch: .pi / 2, segments: 12)
                }
            })
            Geo.part(b, Geo.box([0.06, 0.05, 0.36], radius: 0.02),
                     Materials.glowing(base: .white, glow: UIColor(hex: 0x7C8BFF), intensity: 1.4), at: [0.47, 0.36, 0])
            let tote = Kit.entity(i % 2 == 0 ? "sorter tote brand" : "sorter tote sand") { k in
                k.box(i % 2 == 0 ? .brand : .carSand, [0.62, 0.32, 0.46], r: 0.04, at: [0, 0.61, 0])
                k.box(.trim, [0.64, 0.04, 0.48], at: [0, 0.78, 0])
            }
            b.addChild(tote)
            b.scale = V3(repeating: 1.3)
            group.addChild(b)
            bots.append((b, tote))
        }
        // The hatch they drop the totes into: a small opening with rollers in the hub's front wall
        let s = Scenery()
        let wall = -MetroWorld.hubSize.x / 2
        s.box(.darkMetal, [0.12, 1.1, 1.6], at: [wall - 0.07, 0.75, robotHatch.y])
        s.box(.brand, [0.5, 0.14, 1.9], at: [wall - 0.2, 1.36, robotHatch.y])
        s.box(.metal, [0.7, 0.08, 1.4], at: [wall - 0.35, 0.62, robotHatch.y])
        s.build(into: group)
        rv.animate(RobotSwarm(bots: bots))
        return group
    }

    /// Robots run the loop one behind the other, stop for a moment at the hatch (tote off) and at the stock (tote on),
    /// and keep their distance from the one in front.
    final class RobotSwarm: WorldAnimator {
        private let bots: [(body: Entity, tote: Entity)]
        private var s: [Float]
        private var pause: [Float]
        private var loaded: [Bool]
        private let points: [SIMD2<Float>]
        private let cumulative: [Float]
        private let length: Float
        private let hatchS: Float, pickS: Float

        init(bots: [(Entity, Entity)]) {
            self.bots = bots.map { (body: $0.0, tote: $0.1) }
            points = MetroResearch.robotLoop + [MetroResearch.robotLoop[0]]
            var c: [Float] = [0]
            for i in 1..<points.count { c.append(c[i - 1] + simd_distance(points[i - 1], points[i])) }
            cumulative = c
            length = c.last!
            hatchS = c[1] + simd_distance(points[1], MetroResearch.robotHatch)
            pickS = c[5] - 3.5
            s = bots.indices.map { Float($0) * c.last! / Float(bots.count) }
            pause = Array(repeating: 0, count: bots.count)
            loaded = bots.indices.map { _ in true }
        }

        private func sample(_ d: Float) -> (SIMD2<Float>, SIMD2<Float>) {
            var u = d.truncatingRemainder(dividingBy: length)
            if u < 0 { u += length }
            var i = 0
            while i < cumulative.count - 2 && cumulative[i + 1] < u { i += 1 }
            let a = points[i], b = points[i + 1]
            let t = (u - cumulative[i]) / max(cumulative[i + 1] - cumulative[i], 0.001)
            return (a + (b - a) * t, simd_normalize(b - a))
        }

        func update(dt: Float, time: Float) {
            for i in bots.indices {
                if pause[i] > 0 { pause[i] -= dt; continue }
                // Gap to the robot in front (the loop wraps round)
                var gap = Float.infinity
                for j in bots.indices where j != i {
                    var d = s[j] - s[i]
                    if d < 0 { d += length }
                    gap = min(gap, d)
                }
                let speed = min(1.5, max(gap - 1.6, 0) * 1.2)
                let before = s[i]
                s[i] += speed * dt
                // Stops: tote off at the hatch, a fresh one on at the stock
                func crossed(_ mark: Float) -> Bool {
                    let a = before.truncatingRemainder(dividingBy: length), b = s[i].truncatingRemainder(dividingBy: length)
                    return a <= mark && (b > mark || b < a)
                }
                if loaded[i] && crossed(hatchS) { loaded[i] = false; pause[i] = 1.4; bots[i].tote.isEnabled = false }
                if !loaded[i] && crossed(pickS) { loaded[i] = true; pause[i] = 1.4; bots[i].tote.isEnabled = true }
                if s[i] > length * 4 { s[i] -= length * 3 }       // keep the numbers small
            }
            for (i, b) in bots.enumerated() {
                // Corners are rounded off by easing the heading
                let (p, dir) = sample(s[i])
                b.body.setPosition(V3(p.x, 0, p.y))
                let yaw = atan2(-dir.y, dir.x)
                let q = simd_slerp(b.body.orientation, simd_quatf(angle: yaw, axis: [0, 1, 0]), min(dt * 8, 1))
                b.body.setOrientation(q)
            }
        }
    }

    // MARK: Rooftop garden (west half of the roof)

    static func garden(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        group.position = [0, roof, zc]
        let s = Scenery()
        var rng = SeededRandom(seed: 88)
        s.box(.grass, [26, 0.3, 22], at: [-16, 0.15, 0])
        s.box(.pallet, [26, 0.1, 3], at: [-16, 0.35, 0])
        for (x, z) in [(-26.0, -7.0), (-20.0, 7.0), (-12.0, -8.0), (-6.0, 6.0), (-27.0, 6.0)] as [(Float, Float)] {
            s.box(.white, [2.4, 0.8, 2.4], at: [x, 0.7, z])
            Props.tree(s, at: [x, 1.1, z], size: rng.float(0.6...0.85), rng: &rng)
        }
        for (x, z, mat) in [(Float(-18), Float(-4), Mat.carCoral), (-13, 3, .carSand), (-23, 2, .carMint)] {
            s.cylinder(.white, radius: 0.04, height: 2.2, at: [x, 1.4, z])
            s.cone(mat, radius: 1.3, height: 0.4, at: [x, 2.5, z])
            s.cylinder(.white, radius: 0.5, height: 0.06, at: [x, 1.05, z])
        }
        s.build(into: group)
        for p in [V3(-17, 0.3, -2.6), V3(-12, 0.3, 4.4), V3(-22, 0.3, 3.4)] {
            let person = Vehicles.person(vest: .carSlate)
            person.root.position = p
            group.addChild(person.root)
            rv.animate(PersonAnimator(person, seed: p.x))
        }
        return group
    }

    // MARK: Drone delivery: pads on the roof, drones out over the city

    static func drones(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let pads: [V3] = [[10, roof + 0.4, zc - 7], [18, roof + 0.4, zc - 7], [26, roof + 0.4, zc - 7], [18, roof + 0.4, zc + 6]]
        for p in pads {
            Geo.part(group, Geo.cylinder(radius: 2.2, height: 0.12), .white, at: p)
            Geo.decal(group, mask: Textures.text("H"), tint: Palette.brand, opacity: 0.9, size: [3.4, 1.4], at: p + [0, 0.08, 0])
        }
        rv.animate(DroneAnimator(parent: group, pads: pads.map { $0 + [0, 0.8, 0] },
                                 targets: [[-110, 30, 90], [120, 30, 100], [-120, 40, -90], [110, 45, -80]]))
        return group
    }

    // MARK: Parcel lockers on the sidewalks

    static func lockers() -> Entity {
        let group = Entity()
        let s = Scenery()
        for (x, z, yaw) in [(Float(-46), Float(42.5), Float(0)), (Float(41), Float(42.8), 0), (Float(-42), Float(-33), .pi), (Float(28), Float(-33), .pi)] {
            s.group(.make([x, 0, z], yaw: yaw)) {
                s.rounded(.brand, [6, 2.4, 0.9], radius: 0.12, at: [0, 1.2, 0])
                for k in 0..<5 { s.box(.brandShade, [0.05, 2.2, 0.92], at: [-2.4 + Float(k) * 1.2, 1.2, 0]) }
                s.box(.white, [6.2, 0.2, 1.1], at: [0, 2.5, 0])
                s.box(.glass, [0.9, 0.6, 0.06], at: [2.4, 1.5, 0.46])
            }
        }
        s.build(into: group)
        return group
    }

    // MARK: Freight hyperloop: an elevated guideway into the hub's west side

    static func hyperloop(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let s = Scenery()
        let z: Float = -14, y: Float = 8
        s.box(.steel, [140, 1.0, 2.2], at: [-102, y, z])
        s.box(.brand, [140, 0.3, 2.3], at: [-102, y + 0.6, z])
        var x: Float = -168
        while x < -36 {
            s.box(.white, [1.2, y, 1.2], at: [x, y / 2, z])
            s.groundShadow(.round, center: [x, 0.05, z], size: [2.5, 2.5])
            x += 12
        }
        s.build(into: group)
        let capsule = Entity()
        Geo.part(capsule, Geo.box([9, 1.8, 2.0], radius: 0.9), .white, at: [0, 0, 0])
        Geo.part(capsule, Geo.box([9.02, 0.3, 2.02], radius: 0.1), .brand, at: [0, -0.2, 0])
        group.addChild(capsule)
        rv.animate(Shuttle(capsule, from: V3(-170, y + 1.8, z), to: V3(-37, y + 1.8, z), period: 16))
        return group
    }

    final class Shuttle: WorldAnimator {
        let entity: Entity
        let from: V3, to: V3
        let period: Float
        init(_ entity: Entity, from: V3, to: V3, period: Float) { self.entity = entity; self.from = from; self.to = to; self.period = period }
        func update(dt: Float, time: Float) {
            let t = (time / period).truncatingRemainder(dividingBy: 1)
            entity.position = lerp(from, to, smootherstep(t))
            entity.setEnabled(t < 0.97)
        }
    }

    // MARK: Skyport: a deck on the roof and an air taxi coming and going

    static func skyport(_ rv: ResearchVisuals) -> Entity {
        let group = Entity()
        let deck = V3(24, roof + 3.5, zc + 2)
        let s = Scenery()
        s.box(.white, [14, 0.5, 14], at: deck)
        s.box(.brand, [14.2, 0.2, 14.2], at: deck + [0, -0.3, 0])
        for (dx, dz) in [(-5.5, -5.5), (5.5, -5.5), (-5.5, 5.5), (5.5, 5.5)] as [(Float, Float)] { s.box(.darkMetal, [0.5, 3.4, 0.5], at: deck + [dx, -1.9, dz]) }
        s.build(into: group)
        Geo.decal(group, mask: Textures.ring, tint: Palette.brand, opacity: 0.8, size: [10, 10], at: deck + [0, 0.27, 0])
        let (taxi, rotors) = Vehicles.evtol()
        group.addChild(taxi)
        rv.animate(AirTaxi(taxi, rotors: rotors, pad: deck + [0, 1.3, 0]))
        return group
    }

    final class AirTaxi: WorldAnimator {
        let entity: Entity
        let rotors: [Entity]
        let pad: V3
        init(_ entity: Entity, rotors: [Entity], pad: V3) { self.entity = entity; self.rotors = rotors; self.pad = pad }
        func update(dt: Float, time: Float) {
            let t = time.truncatingRemainder(dividingBy: 40)
            let away = V3(160, 60, -160)
            var p = pad
            switch t {
            case ..<6: p = pad                                                   // parked
            case ..<10: p = pad + [0, smootherstep((t - 6) / 4) * 18, 0]          // climb
            case ..<20: p = lerp(pad + [0, 18, 0], away, smootherstep((t - 10) / 10))
            case ..<26: p = away; entity.setEnabled(false)
            case ..<36: entity.setEnabled(true); p = lerp(away, pad + [0, 18, 0], smootherstep((t - 26) / 10))
            default: p = pad + [0, (1 - smootherstep((t - 36) / 4)) * 18, 0]
            }
            if t < 20 || t >= 26 { entity.setEnabled(true) }
            entity.position = p
            let dir = (t < 23) ? away - pad : pad - away
            entity.orientation = simd_quatf(angle: atan2(-dir.z, dir.x), axis: [0, 1, 0])
            let spinning = t >= 5 && t < 39
            for r in rotors { r.orientation = simd_quatf(angle: spinning ? time * 30 : 0, axis: [0, 1, 0]) }
        }
    }
}
