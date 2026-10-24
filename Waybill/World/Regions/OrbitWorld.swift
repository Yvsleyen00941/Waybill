import RealityKit
import UIKit

/// Region 5: the Waybill launch site, on a sandy coast.
///
/// Layout (metres, seen from above; +z is towards the highway):
///
///   dunes ▲            ASSEMBLY BUILDING ══ crawlerway ══ LAUNCH PAD + tower      ~~ ocean ~~
///   mission control │ clean room + payload canisters │ fuel farm               beach
///   ═══════════ coastal highway (z = 52) ═══════════
enum OrbitWorld {
    static let vabCenter = V3(-44, 0, -20)
    static let vabSize = V3(30, 46, 34)
    static let pad0 = V3(58, 0, -20)
    static let pad1 = V3(58, 0, 24)
    static let coastX: Float = 112

    static func build(into root: Entity, game: GameModel, camera: Entity, arView: ARView) -> BuiltWorld {
        let world = BuiltWorld()
        world.home = CameraHome(target: V3(8, 0, -2), yaw: deg(28), distance: 215, boundsMin: SIMD2(-120, -80), boundsMax: SIMD2(130, 80))
        world.ground = UIColor(hex: 0xEADFCB)
        let parts = world.site
        let s = Scenery()
        var rng = SeededRandom(seed: 55)

        // Sand, the site apron, the ocean
        Geo.part(root, .generatePlane(width: 2400, depth: 2400), .sand, at: [0, 0, 0])
        Geo.part(root, .generatePlane(width: 210, depth: 96, cornerRadius: 4), .concreteDark, at: [6, 0.02, 2])
        let ocean = ModelEntity(mesh: .generatePlane(width: 800, depth: 1400), materials: [Materials.water(scale: SIMD2(30, 56), color: UIColor(hex: 0x7C9FE6))])
        ocean.position = [coastX + 400, 0.05, 0]
        ocean.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(ocean)
        if let flow = WaterAnimator.flow(ocean, scale: SIMD2(30, 56), color: UIColor(hex: 0x7C9FE6), flow: SIMD2(-0.01, 0.002)) { world.animators.append(flow) }
        Geo.part(root, .generatePlane(width: 16, depth: 1400), .sandDark, at: [coastX - 2, 0.03, 0])

        Common.road(root, s, z: 52, north: [.driveway(26...41), .driveway(-22 ... -8)])   // the payload trucks' way in and out
        buildVAB(root, s, parts)
        buildPad(root, s, parts, at: pad0)
        buildCrawlerway(s)
        buildCleanRoom(root, s, parts)
        buildMissionControl(root, s, parts, world)
        buildFuelFarm(s)
        buildDunes(root, s, &rng)

        for (p, yaw) in [(V3(-80, 0, 40), deg(-40)), (V3(16, 0, 44), deg(-90)), (V3(96, 0, 36), deg(-140)), (V3(30, 0, -50), deg(60))] {
            Common.mast(root, s, parts, at: p, yaw: yaw, height: 18, pool: 34)
        }

        // Payload trucks bring cargo to the clean room: off the highway, along the canister rows, unload, out west.
        // The passing traffic brakes for them, they wait for a gap to pull out, and only one is on site at a time.
        let road = Common.traffic(world, root)
        let routes = supplyRoutes()
        let siteDock = Common.SupplyDock()
        for livery in [Livery.waybill, .nordway] {
            Common.supplyRun(world, root, road: road, dock: siteDock, truck: Vehicles.truck(livery),
                             inbound: routes.inbound, outbound: routes.outbound, unload: 10,
                             inStatus: "Payload inbound", unloadStatus: "Unloading", outStatus: "Back to the city")
        }
        Common.walkers(world, root, routes: [
            [[-20, 0, 26], [-6, 0, 26.6], [8, 0, 26]],
            [[-78, 0, 22], [-64, 0, 22], [-60, 0, 10]],
        ])

        // The fleet: rockets
        let rockets = RocketFleetVisual(game: game, layout: launchLayout(), root: root)
        world.fleet = rockets
        world.animators.append(rockets)

        // Stock: payload canisters lined up by the clean room; loads waiting near the pad
        var slots: [(position: V3, yaw: Float)] = []
        for z: Float in [22, 27.5] { for k in 0..<7 { slots.append((V3(-26 + Float(k) * 5, 0, z), 0)) } }
        let layout = StockLayout(unit: .canister, slots: slots, layers: 2, scale: 1,
                                 dockSlots: [(V3(40, 0, -6), 0), (V3(45, 0, -6), 0)], dockLayers: 2)
        let visuals = GameVisuals(game: game, arView: arView, root: root, layout: layout)
        world.visuals = visuals
        world.animators.append(visuals)

        Common.pin(world, root, camera: camera, at: [-11, 8, 25])
        Common.pin(world, root, camera: camera, at: [pad0.x, 2, pad0.z + 14])

        let research = ResearchVisuals(root: root, site: parts)
        OrbitResearch.install(research, rockets: rockets, game: game)
        for id in game.research { research.reveal(id, animated: false) }
        world.research = research
        world.animators.append(research)

        NSLog("[Waybill] orbit scenery vertices: %d", s.vertexCount)
        s.build(into: root)
        return world
    }

    /// The payload trucks' routes, for the rear axle: a right turn off the westbound lane, a left onto the lane along
    /// the canister rows (clear of the light mast at x 16); out: on west, left, and right onto the highway.
    static func supplyRoutes() -> (inbound: DrivePath, outbound: DrivePath) {
        typealias P = SIMD2<Float>
        func path(_ ps: [P]) -> DrivePath { DrivePath(ps.map { V3($0.x, 0, $0.y) }, samplesPerSegment: 3) }
        let road = Common.laneWest, stopX: Float = 6
        let inbound = path(Turtle.path(from: P(220, road), heading: P(-1, 0), [
            .straight(220 - 40), .arc(radius: 9, angle: .pi / 2), .arc(radius: 7.2, angle: -.pi / 2), .straight(31 - 7.2 - stopX),
        ]))
        let outbound = path(Turtle.path(from: P(stopX, 33), heading: P(-1, 0), [
            .straight(stopX + 6.8), .arc(radius: 7.2, angle: -.pi / 2), .arc(radius: 9, angle: .pi / 2), .straight(260),
        ]))
        return (inbound, outbound)
    }

    static func launchLayout() -> LaunchLayout {
        let door = V3(vabCenter.x + vabSize.x / 2 + 6, 0, vabCenter.z)
        let toPad0 = DrivePath([door, pad0])
        let toPad1 = DrivePath([door, door + [20, 0, 0], [24, 0, -6], [44, 0, 18], pad1])
        return LaunchLayout(crawlerways: [toPad0, toPad1], landing: V3(10, 0, -56))
    }

    // MARK: Vehicle assembly building

    private static func buildVAB(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        let c = vabCenter, size = vabSize
        s.rounded(.white, size, radius: 0.3, at: c + [0, size.y / 2, 0])
        s.box(.brand, [size.x + 0.3, 3, size.z + 0.3], at: c + [0, size.y - 1.5, 0])
        s.box(.steel, [size.x - 2, 0.5, size.z - 2], at: c + [0, size.y + 0.25, 0])
        // Tall door slit facing the pad, with a low annex
        s.box(.interior, [0.2, size.y - 6, 10], at: c + [size.x / 2 + 0.05, (size.y - 6) / 2, 0])
        for dz: Float in [-5.4, 5.4] { s.box(.brandShade, [0.4, size.y - 6, 0.6], at: c + [size.x / 2 + 0.2, (size.y - 6) / 2, dz]) }
        s.rounded(.white, [20, 9, 16], radius: 0.2, at: c + [-size.x / 2 - 10, 4.5, 8])
        // Panel bands, louvres and a plinth make the huge white box read at scale
        var py: Float = 8
        while py < size.y - 4 { s.box(.insulated, [size.x + 0.12, 0.25, size.z + 0.12], at: c + [0, py, 0]); py += 8 }
        s.box(.plinth, [size.x + 0.2, 1.4, size.z + 0.2], at: c + [0, 0.7, 0])
        for lz: Float in [-size.z / 2 + 4, size.z / 2 - 4] {
            for k in 0..<8 { s.box(.trim, [0.12, 0.12, 3.0], at: c + [size.x / 2 + 0.06, size.y - 9 + Float(k) * 0.4, lz]) }
        }
        for (dx, dz) in [(-size.x / 2 - 4, 2.0), (-size.x / 2 - 13, 2.0)] as [(Float, Float)] {
            s.rounded(.metal, [2.4, 1.3, 2.0], radius: 0.1, at: c + [dx, 9.7, dz])
            s.cylinder(.darkMetal, radius: 0.6, height: 0.08, at: c + [dx, 10.4, dz], segments: 16)
        }
        // Vertical ribs
        var z = -size.z / 2 + 3
        while z < size.z / 2 {
            if abs(z) > 6 { s.box(.steel, [0.3, size.y - 4, 0.5], at: c + [size.x / 2 + 0.15, (size.y - 4) / 2, z]) }
            z += 4
        }
        let mark = ModelEntity(mesh: .generatePlane(width: 18, height: 18),
                               materials: [Materials.paintedDecal(mask: Textures.roundel, tint: Palette.brand, opacity: 0.95)])
        mark.transform = Transform(matrix: .make(c + [0, size.y * 0.58, size.z / 2 + 0.33]))
        mark.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(mark)
        let sign = ModelEntity(mesh: .generatePlane(width: 24, height: 4.4),
                               materials: [Materials.paintedDecal(mask: Textures.logo("Waybill", emblem: .route, uppercase: true), tint: Palette.brand)])
        sign.transform = Transform(matrix: .make(c + [0, size.y * 0.25, size.z / 2 + 0.33]))
        sign.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sign)
        parts.lampHeads.append(Geo.part(root, Geo.box([0.4, 0.4, size.z + 0.4]), Materials.glowing(base: .white, glow: Palette.tailLight, intensity: 0),
                                        at: c + [size.x / 2, size.y + 0.6, 0]))
        Geo.contactShadow(root, size: [size.x + 10, size.z + 10], at: c + [0, 0.05, 0], opacity: 0.32)
    }

    // MARK: Launch pad with its tower

    static func buildPad(_ root: Entity, _ s: Scenery, _ parts: SiteParts, at p: V3) {
        s.cylinder(.concrete, radius: 16, height: 1.2, at: p + [0, 0.6, 0])
        s.box(.concreteDark, [26, 1.24, 6], at: p + [8, 0.62, 0])          // flame trench cover
        s.box(.interior, [10, 0.1, 5], at: p + [17, 1.25, 0])
        // Lattice tower beside the rocket
        let t = p + V3(-8, 0, -6)
        for (dx, dz) in [(-2.0, -2.0), (2.0, -2.0), (-2.0, 2.0), (2.0, 2.0)] as [(Float, Float)] {
            s.box(.carCoral, [0.7, 64, 0.7], at: t + [dx, 32, dz])
        }
        var y: Float = 3
        while y < 64 {
            for (dx, dz, yaw) in [(0.0, -2.0, Float(0)), (0.0, 2.0, 0), (-2.0, 0.0, .pi / 2), (2.0, 0.0, .pi / 2)] as [(Float, Float, Float)] {
                s.box(.carCoral, [4.4, 0.3, 0.3], at: t + [dx, y, dz], yaw: yaw)
                s.box(.carCoral, [5.6, 0.22, 0.22], at: t + [dx, y + 2.2, dz], yaw: yaw, roll: 0.7)
            }
            y += 4.5
        }
        s.box(.white, [5, 3, 5], at: t + [0, 65.5, 0])
        // Flame deflector, propellant lines and pad tanks
        s.prism(.concreteDark, outline: [SIMD2(-3, -3), SIMD2(3, -3), SIMD2(3, 3), SIMD2(-3, 3)], y0: 1.2, y1: 1.6, at: p)
        for dz: Float in [-0.6, 0.6] { s.cylinder(.aluminium, radius: 0.25, height: 20, at: p + [-4, 1.6, dz + 9], roll: .pi / 2) }
        for (dx, dz, m) in [(-12.0, 10.0, Mat.paintWhite), (-12.0, 14.0, Mat.paintBrand)] as [(Float, Float, Mat)] {
            s.roundedCylinder(m, radius: 1.6, height: 6.5, r: 0.8, at: p + [dx, 1.2 + 1.6, dz], roll: .pi / 2)
            for k in [-2, 2] as [Float] { s.box(.trim, [0.4, 1.4, 2.6], at: p + [dx + k, 1.9, dz]) }
        }
        // Access arms
        for ay: Float in [30, 48] { s.box(.carCoral, [6.5, 1, 1.4], at: t + [5, ay, 3], yaw: deg(-40)) }
        // Lightning masts and a water tower
        for (dx, dz) in [(-18.0, -18.0), (18.0, -18.0), (-18.0, 18.0), (18.0, 18.0)] as [(Float, Float)] {
            s.box(.white, [0.6, 70, 0.6], at: p + [dx, 35, dz])
        }
        s.box(.darkMetal, [0.05, 0.05, 50.9], at: p + [-18, 69.5, 0])
        s.box(.darkMetal, [0.05, 0.05, 50.9], at: p + [18, 69.5, 0])
        let w = p + V3(-24, 0, 16)
        for (dx, dz) in [(-2.0, -2.0), (2.0, -2.0), (-2.0, 2.0), (2.0, 2.0)] as [(Float, Float)] { s.box(.steel, [0.4, 20, 0.4], at: w + [dx, 10, dz]) }
        for by in stride(from: Float(4), through: 16, by: 6) {
            s.box(.steel, [4.4, 0.2, 0.2], at: w + [0, by, -2]); s.box(.steel, [4.4, 0.2, 0.2], at: w + [0, by, 2])
            s.box(.steel, [0.2, 0.2, 4.4], at: w + [-2, by, 0]); s.box(.steel, [0.2, 0.2, 4.4], at: w + [2, by, 0])
        }
        s.sphere(.paintWhite, radius: 5, at: w + [0, 24, 0])
        s.cylinder(.paintBrand, radius: 5.02, height: 1.0, at: w + [0, 24, 0])
        s.groundShadow(.round, center: p + [0, 1.25, 0], size: [36, 36])
        parts.lampHeads.append(Geo.part(root, Geo.sphere(radius: 0.5), Materials.glowing(base: .white, glow: Palette.tailLight, intensity: 0), at: t + [0, 67.4, 0]))
        for (dx, dz) in [(-18.0, -18.0), (18.0, 18.0)] as [(Float, Float)] {
            parts.lampHeads.append(Geo.part(root, Geo.sphere(radius: 0.4), Materials.glowing(base: .white, glow: Palette.tailLight, intensity: 0), at: p + [dx, 70.4, dz]))
        }
    }

    private static func buildCrawlerway(_ s: Scenery) {
        let x0 = vabCenter.x + vabSize.x / 2, x1 = pad0.x - 14
        for dz: Float in [-4.5, 4.5] { s.box(.sandDark, [x1 - x0, 0.06, 5], at: [(x0 + x1) / 2, 0.05, pad0.z + dz]) }
        s.box(.concreteDark, [x1 - x0, 0.04, 3.6], at: [(x0 + x1) / 2, 0.045, pad0.z])
    }

    // MARK: Clean room (payload processing)

    private static func buildCleanRoom(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        let c = V3(-12, 0, 8)
        s.rounded(.white, [34, 14, 16], radius: 0.25, at: c + [0, 7, 0])
        s.box(.brand, [34.3, 1.2, 16.3], at: c + [0, 12.8, 0])
        s.box(.steel, [10, 10, 0.2], at: c + [0, 5, 8.05])
        // Glass bands either side of the payload door (reflective by day, lit at night), with slim mullions
        var windows = MeshBuilder()
        for (x0, x1) in [(Float(-16.2), Float(-5.6)), (Float(5.6), Float(16.2))] {
            windows.addBox([x1 - x0, 2.8, 0.08], .make(c + [(x0 + x1) / 2, 8.2, 8.05]))
            var m = x0
            while m <= x1 + 0.01 { s.box(.darkMetal, [0.08, 2.84, 0.1], at: c + [m, 8.2, 8.1]); m += (x1 - x0) / 7 }
            s.box(.white, [x1 - x0 + 0.3, 0.16, 0.3], at: c + [(x0 + x1) / 2, 6.72, 8.12])
        }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.facadeGlass(night: 0)])
            root.addChild(e)
            parts.facadeGlass.append(e)
        }
        Geo.contactShadow(root, size: [38, 20], at: c + [0, 0.05, 0], opacity: 0.3)
    }

    // MARK: Mission control with satellite dishes

    private static func buildMissionControl(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ world: BuiltWorld) {
        let c = V3(-74, 0, 18)
        s.rounded(.white, [22, 7, 14], radius: 0.2, at: c + [0, 3.5, 0])
        s.box(.brand, [22.4, 0.6, 14.4], at: c + [0, 7.1, 0])
        var windows = MeshBuilder()
        windows.addBox([20, 1.8, 0.08], .make(c + [0, 4.2, 7.05]))
        var m: Float = -10
        while m <= 10.01 { s.box(.darkMetal, [0.07, 1.84, 0.1], at: c + [m, 4.2, 7.1]); m += 1.25 }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.facadeGlass(night: 0)])
            root.addChild(e)
            parts.facadeGlass.append(e)
        }
        for (i, p) in [V3(-90, 0, 4), V3(-98, 0, 22)].enumerated() {
            s.box(.steel, [1.2, 6, 1.2], at: p + [0, 3, 0])
            let dish = Entity()
            dish.position = p + [0, 7, 0]
            root.addChild(dish)
            let bowl = Entity()
            bowl.orientation = simd_quatf(angle: deg(-50), axis: [0, 0, 1])
            dish.addChild(bowl)
            Geo.part(bowl, Geo.cylinder(radius: 4.2, height: 0.5), .white, at: [0, 0, 0])
            Geo.part(bowl, Geo.cylinder(radius: 0.15, height: 3), .darkMetal, at: [0, 1.6, 0])
            world.animators.append(SpinAnimator(dish, axis: [0, 1, 0], speed: 0.05 + Float(i) * 0.03))
        }
        Geo.contactShadow(root, size: [26, 18], at: c + [0, 0.05, 0], opacity: 0.3)
    }

    // MARK: Fuel farm near the pad

    private static func buildFuelFarm(_ s: Scenery) {
        for (i, p) in [V3(78, 0, 6), V3(88, 0, 6), V3(83, 0, 15)].enumerated() {
            s.sphere(i == 2 ? .steel : .white, radius: 5, at: p + [0, 6, 0])
            for (dx, dz) in [(-3.0, -3.0), (3.0, -3.0), (-3.0, 3.0), (3.0, 3.0)] as [(Float, Float)] { s.box(.steel, [0.4, 3, 0.4], at: p + [dx, 1.5, dz]) }
            s.groundShadow(.round, center: p + [0, 0.05, 0], size: [12, 12])
        }
        s.box(.steel, [0.5, 0.5, 26], at: [70, 0.5, -6])
    }

    // MARK: Dunes and scrub

    private static func buildDunes(_ root: Entity, _ s: Scenery, _ rng: inout SeededRandom) {
        var rock = MeshBuilder(), cap = MeshBuilder()
        let dunes: [(V3, Float, Float)] = [([-150, 0, -70], 60, 14), ([-95, 0, -95], 48, 10), ([-30, 0, -110], 70, 16), ([40, 0, -100], 52, 11),
                                           ([-180, 0, 20], 56, 12), ([-160, 0, 90], 64, 14), ([140, 0, -140], 40, 8)]
        for (i, (p, r, h)) in dunes.enumerated() {
            Common.mountain(rock: &rock, snow: &cap, at: p, radius: r, height: h, segments: 8, snowLine: 0.7, seed: UInt64(70 + i))
        }
        Common.finishMountains(root, rock: rock, snow: cap, rockMat: .sandDark, snowMat: .sand)
        // Scrub and palms
        for _ in 0..<90 {
            let p = V3(rng.float(-200...105), 0, rng.float(-120...130))
            if p.x > -100 && p.x < 104 && p.z > -50 && p.z < 50 { continue }
            if abs(p.z - 52) < 10 { continue }
            Props.bush(s, at: p, size: rng.float(0.6...1.1))
        }
        for k in 0..<14 {
            let p = V3(rng.float(-190 ... -110), 0, rng.float(-40...130)) + (k % 2 == 0 ? V3(260, 0, 0) : .zero)
            if p.x > 104 { continue }
            palm(s, at: p, size: rng.float(0.9...1.3), rng: &rng)
        }
    }

    static func palm(_ s: Scenery, at p: V3, size: Float, rng: inout SeededRandom) {
        let h = 7 * size
        var q = p
        for k in 0..<5 {
            let seg = V3(0.18 * size, h / 5, 0)
            s.cylinder(.bark, radius: 0.28 * size * (1 - Float(k) * 0.08), height: h / 5 + 0.1, at: q + seg / 2, roll: -0.08)
            q += seg
        }
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi
            s.box(.foliageDark, [3.4 * size, 0.12, 0.8 * size], at: q + V3(cos(a), -0.3, sin(a)) * 1.5 * size, yaw: -a, roll: -0.35)
        }
        s.groundShadow(.round, center: p + [1, 0.05, 0], size: [5 * size, 5 * size])
    }
}
