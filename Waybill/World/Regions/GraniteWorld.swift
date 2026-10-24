import RealityKit
import UIKit

/// Region 3: Granite Pass railhead.
///
/// Layout (metres, seen from above; +z is towards the road):
///
///   snowy peaks ▲ ▲ ▲                                   ▲ ▲
///   [west tunnel] ══ main line ═══════════════════ bridge over the river ══ [east tunnel]
///                     ╲═ siding at the long platform ═╱
///   station chalet │ crate yard (transload)            river
///   ═══════════ valley road (z = 52) ═══════════   village chalets beyond
enum GraniteWorld {
    static let mainZ: Float = -14
    static let sidingZ: Float = -6
    static let riverX: Float = 93
    static let bridgeY: Float = 3

    static func build(into root: Entity, game: GameModel, camera: Entity, arView: ARView) -> BuiltWorld {
        let world = BuiltWorld()
        world.home = CameraHome(target: V3(6, 0, -2), yaw: deg(24), distance: 168, boundsMin: SIMD2(-95, -70), boundsMax: SIMD2(115, 80))
        world.ground = UIColor(hex: 0xE6E9F7)
        let parts = world.site
        let s = Scenery()
        var rng = SeededRandom(seed: 33)

        // Snowy ground, the yard, the river
        Geo.part(root, .generatePlane(width: 2400, depth: 2400), .snow, at: [0, 0, 0])
        Geo.part(root, .generatePlane(width: 118, depth: 74, cornerRadius: 3), .yard, at: [-6, 0.02, 12])
        let river = ModelEntity(mesh: .generatePlane(width: 26, depth: 1200), materials: [Materials.water(scale: SIMD2(1.5, 60), color: UIColor(hex: 0x86A0E8))])
        river.position = [riverX, 0.04, 0]
        river.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(river)
        if let flow = WaterAnimator.flow(river, scale: SIMD2(1.5, 60), color: UIColor(hex: 0x86A0E8), flow: SIMD2(0.002, 0.03)) { world.animators.append(flow) }
        for x in [riverX - 13.4, riverX + 13.4] { s.box(.rock, [1.4, 0.6, 1200], at: [x, 0.2, 0]) }

        // Railway: one route for the trains, plus the straight main line as scenery
        let rail = railLayout()
        Rails.track(s, path: rail.route, from: 0, to: rail.route.length)
        Rails.track(s, path: DrivePath([[-63, 0, mainZ], [66, 0, mainZ]]), from: 0, to: 129)
        buildBridge(s)
        buildTunnels(root, s)
        buildMountains(root, s, parts, &rng)

        // Road along the valley, with its own little bridge over the river
        Common.road(root, s, z: 52, north: [.driveway(33...47), .driveway(-18 ... -4)])   // the supply trucks' way in and out
        s.box(.stone, [32, 0.5, 15], at: [riverX, 0.08, 52])
        for z: Float in [44.6, 59.4] { s.box(.stone, [32, 0.9, 0.5], at: [riverX, 0.6, z]) }
        Geo.part(root, .generatePlane(width: 13, depth: 8, cornerRadius: 1.5), .road, at: [40, 0.032, 44])

        buildPlatform(root, s, parts)
        buildStation(root, s, parts)
        buildShed(root, s, parts)
        buildVillage(root, s, parts, &rng)

        // Lamps around the yard, signals at the switches
        for (p, yaw) in [(V3(-50, 0, 40), Float(0)), (V3(-14, 0, 40), 0), (V3(22, 0, 40), 0), (V3(46, 0, 22), Float.pi)] {
            Common.lamp(root, s, parts, at: p, yaw: yaw)
        }
        for (x, z) in [(Float(-68), mainZ - 3), (Float(56), mainZ - 3)] {
            s.box(.darkMetal, [0.25, 4.4, 0.25], at: [x, 2.2, z])
            s.rounded(.darkMetal, [0.7, 1.4, 0.5], radius: 0.1, at: [x, 4.6, z])
            parts.lampHeads.append(Geo.part(root, Geo.sphere(radius: 0.2), Materials.glowing(base: UIColor(hex: 0x5FCB9A), glow: UIColor(hex: 0x5FCB9A), intensity: 0),
                                            at: [x + 0.3, 4.9, z]))
            Geo.part(root, Geo.sphere(radius: 0.2), Materials.glowing(base: Palette.tailLight, glow: Palette.tailLight, intensity: 1.0), at: [x + 0.3, 4.35, z])
        }

        // Forklifts loading the wagons on the platform
        for (i, x) in [Float(-22), 18].enumerated() {
            let f = Vehicles.forklift()
            let y: Float = 1.0
            weak var driver: VehicleDriver?
            let d = VehicleDriver(f, legs: [
                .drive(DrivePath([[x, y, 0.6], [x + 6, y, 0.6]], keepHeight: true), speed: 2.2, onStart: { driver?.setStatus("To the wagons") }),
                .wait(1.6, onStart: { f.cargo?.isEnabled = false; driver?.setStatus("Loading") }),
                .drive(DrivePath([[x + 6, y, 0.6], [x, y, 0.6]], keepHeight: true), reverse: true, speed: 2.0),
                .wait(1.6, onStart: { f.cargo?.isEnabled = true; driver?.setStatus("Picking") }),
            ], startAt: Float(i) * 4)
            driver = d
            root.addChild(f.root)
            world.vehicles.append(f)
            world.animators.insert(d, at: 0)
            world.labels.append(FloatingLabel(id: "FL-0\(i + 1)", color: Palette.forklift, vehicle: f) { d.shownStatus })
        }
        // Trucks bringing goods down from the valley: in off the road, along the crate yard, unload, out west.
        // The passing traffic brakes for them, they wait for a gap to pull out, and only one is in the yard at a time.
        Geo.part(root, .generatePlane(width: 13, depth: 8, cornerRadius: 1.5), .road, at: [-11, 0.032, 44])
        let road = Common.traffic(world, root)
        let routes = supplyRoutes()
        let yardDock = Common.SupplyDock()
        for livery in [Livery.peakfresh, .nordway] {
            Common.supplyRun(world, root, road: road, dock: yardDock, truck: Vehicles.truck(livery),
                             inbound: routes.inbound, outbound: routes.outbound, unload: 9,
                             inStatus: "Bringing crates", unloadStatus: "Unloading", outStatus: "Back to the valley")
        }
        Common.walkers(world, root, routes: [
            [[-44, 1.0, 1.0], [-30, 1.0, 1.2], [-16, 1.0, 0.8]],
            [[-50, 0, 20], [-50, 0, 30], [-40, 0, 34]],
        ])

        // The fleet: trains
        let trains = TrainFleetVisual(game: game, rail: rail, root: root)
        world.fleet = trains
        world.animators.append(trains)

        // Stock: crate stacks in the transload yard (4 × 8 × 4 layers), loads waiting on the platform
        var slots: [(position: V3, yaw: Float)] = []
        for z: Float in [13, 18.5, 24, 29.5] {
            for k in 0..<8 { slots.append((V3(-38 + Float(k) * 7.4, 0, z), Float(k % 3 - 1) * 0.05)) }
        }
        let layout = StockLayout(unit: .crate, slots: slots, layers: 4,
                                 dockSlots: [-32, -12, 8, 28].map { (V3($0, 1.0, -1.0), Float.pi / 2) }, dockLayers: 2)
        let visuals = GameVisuals(game: game, arView: arView, root: root, layout: layout)
        world.visuals = visuals
        world.animators.append(visuals)

        Common.pin(world, root, camera: camera, at: [-8, 4.4, 20])
        Common.pin(world, root, camera: camera, at: [riverX, 8, mainZ])

        let research = ResearchVisuals(root: root, site: parts)
        GraniteResearch.install(research, trains: trains, game: game)
        for id in game.research { research.reveal(id, animated: false) }
        world.research = research
        world.animators.append(research)

        NSLog("[Waybill] granite scenery vertices: %d", s.vertexCount)
        s.build(into: root)
        return world
    }

    // MARK: The rail route

    static func railLayout() -> RailLayout {
        let m = mainZ, sd = sidingZ, y = bridgeY
        let route = DrivePath([[-230, 0, m], [-95, 0, m], [-75, 0, m], [-63, 0, m], [-51, 0, -9.6], [-41, 0, -6.3], [-30, 0, sd],
                               [40, 0, sd], [50, 0, -6.6], [58, 0, -10.6], [66, 0, -13.7], [72, 1.6, m], [78, y, m], [108, y, m],
                               [114, 1.6, m], [122, 0, m], [132, 0, m], [270, 0, m]], samplesPerSegment: 16, keepHeight: true)
        func distance(where test: (V3) -> Bool) -> Float {
            var d: Float = 0
            while d < route.length, !test(route.sample(d).position) { d += 0.25 }
            return d
        }
        let queue = distance { $0.x >= -75 }
        let platform = distance { $0.x >= 40 }
        return RailLayout(route: route, start: distance { $0.x >= -225 }, queue: queue, platform: platform, exit: route.length,
                          limit: { p in (p.x > -70 && p.x < 60) ? 7 : 14 })
    }

    // MARK: Bridge over the river

    private static func buildBridge(_ s: Scenery) {
        let x0 = riverX - 15, x1 = riverX + 15
        s.box(.stone, [x1 - x0, 1.2, 6], at: [riverX, bridgeY - 0.6, mainZ])
        for z: Float in [mainZ - 3.2, mainZ + 3.2] { s.box(.stone, [x1 - x0, 1.0, 0.5], at: [riverX, bridgeY + 0.5, z]) }
        for px: Float in [riverX - 7.5, riverX, riverX + 7.5] {
            s.box(.rock, [2.4, bridgeY, 5.6], at: [px, bridgeY / 2 - 0.6, mainZ])
            s.box(.rock, [3.2, 0.8, 6.4], at: [px, 0.2, mainZ])
        }
        // Arch rings under the deck
        for a in [riverX - 11.25, riverX - 3.75, riverX + 3.75, riverX + 11.25] {
            for k in 0...6 {
                let t = Float(k) / 6 * .pi
                let p = V3(a + cos(t) * 3.2, bridgeY - 1.2 - sin(t) * 0.0 - (1 - sin(t)) * 1.4, mainZ)
                s.box(.stone, [0.9, 0.5, 5.8], at: p, roll: -t + .pi / 2)
            }
        }
        // Approach embankments
        for (x, w) in [(riverX - 19, Float(8)), (riverX + 19, 8)] {
            s.box(.rockDark, [w, 1.6, 6.6], at: [x, 0.5, mainZ])
        }
    }

    // MARK: Tunnels

    private static func buildTunnels(_ root: Entity, _ s: Scenery) {
        for (x, facing) in [(Float(-95), Float(1)), (Float(132), Float(-1))] {
            // Rock mass behind the portal
            let depth: Float = 46
            s.rounded(.rock, [depth, 18, 52], radius: 4, at: [x - facing * (depth / 2 - 0.5), 8, mainZ - 4])
            s.rounded(.snow, [depth - 6, 3, 46], radius: 1.4, at: [x - facing * (depth / 2 + 1), 17.2, mainZ - 4])
            // Concrete portal with a dark opening
            s.box(.concreteDark, [1.6, 8.4, 1.6], at: [x + facing * 0.6, 4.2, mainZ - 3.6])
            s.box(.concreteDark, [1.6, 8.4, 1.6], at: [x + facing * 0.6, 4.2, mainZ + 3.6])
            s.box(.concreteDark, [1.8, 2.0, 9.2], at: [x + facing * 0.6, 9.2, mainZ])
            s.box(.interior, [0.2, 7.4, 5.6], at: [x + facing * 0.15, 3.7, mainZ])
            s.groundShadow(.rect, center: [x + facing * 3, 0.06, mainZ], size: [8, 12])
        }
    }

    // MARK: Mountains and forest

    private static func buildMountains(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        // Faceted peaks with snow: the two tunnel mountains, a ridge right behind the railhead, big peaks far away
        var rock = MeshBuilder(), snow = MeshBuilder()
        let peaks: [(V3, Float, Float, Float)] = [
            ([-165, 0, -26], 80, 72, 0.55), ([212, 0, -30], 88, 80, 0.55),
            ([-110, 0, -78], 44, 40, 0.5), ([-62, 0, -86], 50, 52, 0.48), ([-10, 0, -82], 42, 38, 0.52), ([36, 0, -90], 52, 56, 0.46),
            ([84, 0, -80], 40, 34, 0.55), ([130, 0, -86], 48, 46, 0.5),
            ([-40, 0, -175], 120, 135, 0.4), ([90, 0, -205], 110, 120, 0.42), ([-240, 0, -190], 130, 150, 0.4),
            ([260, 0, -220], 120, 130, 0.42), ([20, 0, -330], 170, 190, 0.38),
        ]
        for (i, (p, r, h, line)) in peaks.enumerated() {
            Common.mountain(rock: &rock, snow: &snow, at: p, radius: r, height: h, segments: 7, snowLine: line, seed: UInt64(40 + i))
        }
        Common.finishMountains(root, rock: rock, snow: snow)
        // Conifer forests on the slopes and around the valley
        for _ in 0..<160 {
            let p = V3(rng.float(-260...280), 0, rng.float(-62 ... -32))
            if abs(p.x - riverX) < 18 { continue }
            Props.conifer(s, at: p, size: rng.float(0.9...1.6))
        }
        for _ in 0..<70 {
            let p = V3(rng.float(-200...220), 0, rng.float(62...150))
            if abs(p.x - riverX) < 18 || (p.z < 120 && p.x > -60 && p.x < 40) { continue }
            Props.conifer(s, at: p, size: rng.float(0.8...1.4))
        }
        for (x, z) in [(Float(-75), Float(30)), (Float(-80), 8), (Float(55), 30), (Float(62), 8), (Float(-72), -24)] {
            Props.conifer(s, at: [x, 0, z], size: 1.3)
        }
        // A few boulders
        for _ in 0..<26 {
            let p = V3(rng.float(-90...120), 0, rng.float(-34 ... -22))
            if abs(p.x - riverX) < 16 { continue }
            s.rounded(rng.chance(0.5) ? .rock : .rockDark, [rng.float(1.5...4), rng.float(1...2.4), rng.float(1.5...3.5)], radius: 0.5, at: p + [0, 0.5, 0], yaw: rng.float(0...3))
        }
    }

    // MARK: Platform with a canopy

    /// The supply trucks' routes, for the rear axle: a right turn off the westbound lane through the yard gate, a left
    /// onto the lane along the crate stacks (clear of the stacks and the lamps); out: on west, left, and right onto the road
    /// (east of the lamp at x -14).
    static func supplyRoutes() -> (inbound: DrivePath, outbound: DrivePath) {
        typealias P = SIMD2<Float>
        func path(_ ps: [P]) -> DrivePath { DrivePath(ps.map { V3($0.x, 0, $0.y) }, samplesPerSegment: 3) }
        let road = Common.laneWest, lane: Float = 32.5, stopX: Float = 26
        let inbound = path(Turtle.path(from: P(200, road), heading: P(-1, 0), [
            .straight(200 - 47), .arc(radius: 9, angle: .pi / 2), .arc(radius: 7.7, angle: -.pi / 2), .straight(38 - 7.7 - stopX),
        ]))
        let outbound = path(Turtle.path(from: P(stopX, lane), heading: P(-1, 0), [
            .straight(stopX + 1.3), .arc(radius: 7.7, angle: -.pi / 2), .arc(radius: 9, angle: .pi / 2), .straight(260),
        ]))
        return (inbound, outbound)
    }

    private static func buildPlatform(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        s.box(.concrete, [92, 1.0, 5.0], at: [-1, 0.5, -0.7])
        s.box(.marking, [92, 0.02, 0.2], at: [-1, 1.01, -3.0])
        var x: Float = -44
        while x <= 42 {
            s.box(.white, [0.3, 4.4, 0.3], at: [x, 3.2, 1.0])
            x += 9.5
        }
        s.box(.brand, [92, 0.4, 4.6], at: [-1, 5.5, -0.4])
        s.box(.snow, [91.6, 0.25, 4.3], at: [-1, 5.82, -0.4])
        s.box(.white, [92.2, 0.5, 0.12], at: [-1, 5.4, -2.75])                                   // canopy fascia
        s.box(.hazard, [92, 0.02, 0.5], at: [-1, 1.015, -2.55])                                   // tactile edge strip
        // Brackets on the columns, benches and signs along the platform
        x = -44
        while x <= 42 {
            s.box(.white, [0.2, 0.2, 3.2], at: [x, 5.0, -0.6], pitch: -0.25)
            s.box(.trim, [0.6, 0.2, 0.6], at: [x, 1.1, 1.0])
            x += 9.5
        }
        x = -39
        while x < 40 {
            s.box(.crate, [2.2, 0.08, 0.5], at: [x, 1.48, 0.6]); s.box(.crate, [2.2, 0.5, 0.08], at: [x, 1.75, 0.84])
            for dx: Float in [-0.9, 0.9] { s.box(.trim, [0.08, 0.48, 0.5], at: [x + dx, 1.24, 0.6]) }
            x += 19
        }
        for sx: Float in [-25, 15] {
            s.box(.trim, [0.08, 1.6, 0.08], at: [sx, 4.0, -0.4])
            s.box(.brand, [2.8, 0.6, 0.1], r: 0.05, at: [sx, 4.6, -0.4])
        }
        // Platform lights under the canopy
        var lights = MeshBuilder()
        x = -40
        while x < 42 { lights.addBox([2.4, 0.1, 0.3], .make([x, 5.25, -0.4])); x += 8 }
        if let mesh = try? lights.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: .white, glow: Palette.lampGlow, intensity: 0)])
            root.addChild(e)
            parts.lampHeads.append(e)
        }
        Geo.contactShadow(root, size: [96, 9], at: [-1, 0.05, -0.5], opacity: 0.25)
    }

    // MARK: Station chalet

    private static func buildStation(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        let c = V3(-60, 0, 12)
        s.rounded(.rock, [15, 3.6, 10], radius: 0.2, at: c + [0, 1.8, 0])
        s.rounded(.crate, [15, 3.6, 10], radius: 0.15, at: c + [0, 5.4, 0])
        s.gable(.brandShade, width: 11.2, rise: 4.2, length: 16.6, at: c + [0, 7.2, 0], yaw: .pi / 2)
        s.gable(.snow, width: 11.6, rise: 4.35, length: 16.2, at: c + [0, 7.45, 0], yaw: .pi / 2)
        s.rounded(.rock, [1.4, 3, 1.4], radius: 0.1, at: c + [4.5, 10.5, -2])
        // Balcony with railing, window frames and flower boxes, front door with a little roof
        s.box(.crateDark, [15.6, 0.2, 1.6], at: c + [0, 3.7, 5.8])
        s.box(.crateDark, [15.6, 0.9, 0.08], at: c + [0, 4.25, 6.56])
        var bx: Float = -7.4
        while bx <= 7.4 { s.box(.crateDark, [0.08, 0.9, 0.08], at: c + [bx, 4.25, 6.56]); bx += 0.6 }
        for wx: Float in [-5, -1.7, 1.7, 5] {
            for wy: Float in [5.4, 1.9] {
                s.box(.white, [1.8, 0.12, 0.14], at: c + [wx, wy + 0.76, 5.06]); s.box(.white, [1.8, 0.12, 0.14], at: c + [wx, wy - 0.76, 5.06])
                s.box(.white, [0.1, 1.5, 0.14], at: c + [wx, wy, 5.07])
            }
            s.box(.crateDark, [1.7, 0.3, 0.35], at: c + [wx, 1.0, 5.2])
            s.sphere(.carCoral, radius: 0.22, at: c + [wx - 0.4, 1.25, 5.2], segments: 8)
            s.sphere(.foliage, radius: 0.25, at: c + [wx + 0.3, 1.25, 5.2], segments: 8)
        }
        s.box(.crateDark, [1.6, 2.4, 0.12], at: c + [-7.3 + 0.9, 1.2, 5.04])
        s.gable(.brandShade, width: 2.4, rise: 0.8, length: 1.4, at: c + [-6.4, 2.6, 5.6])
        var windows = MeshBuilder()
        for wx: Float in [-5, -1.7, 1.7, 5] {
            windows.addBox([1.6, 1.4, 0.08], .make(c + [wx, 5.4, 5.03]))
            windows.addBox([1.6, 1.4, 0.08], .make(c + [wx, 1.9, 5.03]))
        }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: Palette.glass, glow: Palette.windowGlow, intensity: 0)])
            root.addChild(e)
            parts.windows.append(e)
        }
        let sign = ModelEntity(mesh: .generatePlane(width: 7, height: 1.2),
                               materials: [Materials.decal(mask: Textures.text("GRANITE PASS", weight: .heavy, size: CGSize(width: 1024, height: 160)), tint: .white, opacity: 0.95)])
        sign.position = c + [0, 3.9, 5.05]
        sign.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sign)
        Geo.contactShadow(root, size: [19, 14], at: c + [0, 0.05, 0], opacity: 0.3)
    }

    // MARK: Engine shed behind the main line

    private static func buildShed(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        let c = V3(-24, 0, -30)
        s.rounded(.white, [34, 8, 12], radius: 0.15, at: c + [0, 4, 0])
        s.gable(.brand, width: 12.6, rise: 2.6, length: 34.6, at: c + [0, 8, 0], yaw: .pi / 2)
        s.gable(.snow, width: 12.8, rise: 2.7, length: 34.2, at: c + [0, 8.2, 0], yaw: .pi / 2)
        for dx: Float in [-8, 8] {
            s.box(.interior, [5, 6.2, 0.1], at: c + [dx, 3.1, 6.04])
            s.box(.brand, [5.6, 0.3, 0.2], at: c + [dx, 6.35, 6.08])
            for ex: Float in [-2.65, 2.65] { s.box(.brand, [0.3, 6.4, 0.2], at: c + [dx + ex, 3.2, 6.08]) }
        }
        var wx: Float = -15
        while wx <= 15 { s.box(.glass, [1.6, 1.0, 0.08], at: c + [wx, 6.6, 6.03]); wx += 5 }
        for dx: Float in [-12, 0, 12] { s.cylinder(.gutter, radius: 0.08, height: 7.6, at: c + [dx, 3.8, 6.1], segments: 8) }
        Geo.contactShadow(root, size: [38, 16], at: c + [0, 0.05, 0], opacity: 0.3)
    }

    // MARK: Village across the road

    private static func buildVillage(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        var windows = MeshBuilder()
        let spots: [V3] = [[-70, 0, 78], [-48, 0, 84], [-24, 0, 76], [6, 0, 86], [30, 0, 78], [56, 0, 88], [-58, 0, 108], [-20, 0, 106], [20, 0, 112], [48, 0, 110]]
        for (i, p) in spots.enumerated() {
            let size = V3(rng.float(8...11), rng.float(4.5...6), rng.float(7...9))
            let yaw = rng.float(-0.25...0.25)
            s.group(.make(p, yaw: yaw)) {
                s.rounded(i % 3 == 0 ? .white : .crate, size, radius: 0.15, at: [0, size.y / 2, 0])
                s.gable(i % 2 == 0 ? .brandShade : .carCoral, width: size.z + 1.2, rise: 3.4, length: size.x + 1.2, at: [0, size.y, 0], yaw: .pi / 2)
                s.gable(.snow, width: size.z + 1.4, rise: 3.5, length: size.x + 0.8, at: [0, size.y + 0.22, 0], yaw: .pi / 2)
                s.groundShadow(.rect, center: [0.4, 0.05, 0.3], size: [size.x + 3, size.z + 3])
            }
            let t = float4x4.make(p, yaw: yaw)
            for wx: Float in [-size.x * 0.25, size.x * 0.25] { windows.addBox([1.4, 1.3, 0.08], t * .make([wx, size.y * 0.5, -size.z / 2 - 0.03])) }
        }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: Palette.glass, glow: Palette.windowGlow, intensity: 0)])
            root.addChild(e)
            parts.windows.append(e)
        }
        // Church with a spire
        let ch = V3(-4, 0, 130)
        s.rounded(.white, [10, 7, 16], radius: 0.15, at: ch + [0, 3.5, 0])
        s.gable(.brandShade, width: 10.8, rise: 4, length: 16.6, at: ch + [0, 7, 0])
        s.rounded(.white, [4, 14, 4], radius: 0.1, at: ch + [0, 7, 9])
        s.cone(.brandShade, radius: 3, height: 7, at: ch + [0, 17.5, 9])
    }
}

/// Rails, sleepers and ballast along a route.
enum Rails {
    /// Top of the rails above the ground (trains stand on this).
    static let height: Float = 0.45

    static func track(_ s: Scenery, path: DrivePath, from: Float, to: Float) {
        var d = from
        let step: Float = 1.6
        var last = path.sample(d)
        d += step
        while d <= to {
            let cur = path.sample(d)
            let a = last.position, b = cur.position
            let seg = b - a
            let len = simd_length(SIMD2(seg.x, seg.z))
            let yaw = atan2(-seg.z, seg.x)
            let mid = (a + b) / 2
            s.box(.rockDark, [len + 0.05, 0.3, 3.4], at: mid + [0, 0.05, 0], yaw: yaw)
            s.box(.pallet, [0.28, 0.16, 2.6], at: mid + [0, 0.24, 0], yaw: yaw)
            let side = V3(-sin(yaw), 0, -cos(yaw))
            for k: Float in [-0.72, 0.72] { s.box(.metal, [len + 0.05, 0.14, 0.12], at: mid + side * k + [0, 0.38, 0], yaw: yaw) }
            last = cur
            d += step
        }
    }
}
