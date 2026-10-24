import RealityKit
import UIKit

/// Region 2: Harbour City container terminal.
///
/// Layout (metres, seen from above; +z is towards the road):
///
///   ~~~~~~~~~~~~ the bay ~~~~~~~~~~~ breakwater + lighthouse (north-east)
///   ═══ quay (z = -24) ═══ two ship-to-shore cranes, a ship berths in windows
///   container yard: block A (west) │ straddle lane │ block B │ lane │ loading lanes A/B + gate (east)
///   office + warehouse (south-west)
///   ═══════════ road (z = 52) ═══════════   city blocks beyond
enum HarbourWorld {
    static let quayZ: Float = -24
    static let yardColumns: [Float] = [-56, -42, -28, 4, 18]
    static let yardRows: [Float] = [-2, 3.5, 9, 14.5, 20]

    static func build(into root: Entity, game: GameModel, camera: Entity, arView: ARView) -> BuiltWorld {
        let world = BuiltWorld()
        world.home = CameraHome(target: V3(2, 0, 6), yaw: deg(34), distance: 138,
                                boundsMin: SIMD2(-80, -70), boundsMax: SIMD2(80, 70))
        let parts = world.site
        let s = Scenery()
        var rng = SeededRandom(seed: 21)

        // Ground, bay, terminal apron
        Geo.part(root, .generatePlane(width: 2400, depth: 2400), .ground, at: [0, 0, 0])
        Geo.part(root, .generatePlane(width: 150, depth: 70, cornerRadius: 2), .yard, at: [-2, 0.02, 10])
        Geo.part(root, .generatePlane(width: 150, depth: 16), .concrete, at: [-2, 0.025, quayZ + 8])
        let water = ModelEntity(mesh: .generatePlane(width: 1400, depth: 700), materials: [Materials.water(scale: SIMD2(56, 28))])
        water.position = [0, 0.035, quayZ - 350]
        water.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(water)
        if let flow = WaterAnimator.flow(water, scale: SIMD2(56, 28)) { world.animators.append(flow) }
        // Quay edge, fenders, bollards, crane rails
        s.box(.stone, [150, 1.4, 1.2], at: [-2, -0.5, quayZ])
        var fx: Float = -74
        while fx < 72 {
            s.box(.darkMetal, [1.6, 1.2, 0.5], at: [fx, -0.4, quayZ - 0.8])
            s.cylinder(.darkMetal, radius: 0.28, height: 0.6, at: [fx + 3, 0.3, quayZ + 1.2])
            fx += 9
        }
        for z: Float in [-21, -13] { s.box(.darkMetal, [148, 0.03, 0.35], at: [-2, 0.04, z]) }
        // Shoreline beyond the terminal (grass banks either side)
        Geo.part(root, .generatePlane(width: 300, depth: 70), .grass, at: [-226, 0.015, 10])
        Geo.part(root, .generatePlane(width: 300, depth: 70), .grass, at: [222, 0.015, 10])
        s.box(.stone, [300, 1.0, 1.0], at: [-226, -0.3, quayZ])
        s.box(.stone, [300, 1.0, 1.0], at: [222, -0.3, quayZ])

        // Road and the city beyond
        Common.road(root, s, z: 52, north: [.driveway(42...71)])     // dropped kerb across the gate and the exit
        buildCity(root, s, parts, &rng)
        buildFarShore(root, s, parts, &rng)

        // Yard markings (white lane lines around the stacks)
        for x in yardColumns {
            for z in yardRows { s.box(.markingWhite, [12.8, 0.02, 0.12], at: [x, 0.04, z - 1.5]) }
        }
        s.box(.marking, [0.18, 0.02, 48], at: [-21, 0.04, 10])
        s.box(.marking, [0.18, 0.02, 48], at: [-3, 0.04, 10])
        s.box(.marking, [0.18, 0.02, 48], at: [26, 0.04, 10])

        buildGate(root, s, parts)
        buildOffice(root, s, parts, &rng)
        buildBreakwater(root, s, parts, &rng)

        // Terminal light masts
        for (p, yaw) in [(V3(-68, 0, -10), deg(-30)), (V3(-12, 0, 27), deg(80)), (V3(30, 0, 27), deg(100)), (V3(68, 0, -6), deg(-150))] {
            Common.mast(root, s, parts, at: p, yaw: yaw, height: 18, pool: 34)
        }
        // Fence along the road (gap for the gate and the exit)
        for (a, b) in [(Float(-75), Float(38)), (Float(70), Float(75))] {
            let count = Int((b - a) / 3)
            for i in 0...count { s.box(.fence, [0.09, 1.7, 0.09], at: [a + Float(i) * (b - a) / Float(count), 0.85, 44.2]) }
            for h: Float in [0.55, 1.45] { s.box(.fence, [b - a, 0.06, 0.05], at: [(a + b) / 2, h, 44.2]) }
        }

        // Cranes, ship and their animation
        let cranes = [QuayCrane(x: -14, seed: 1), QuayCrane(x: 16, seed: 4)]
        for c in cranes { root.addChild(c.root) }
        world.animators.append(CraneAnimator(cranes: cranes, game: game))
        let ship = Vehicles.containerShip(seed: 3)
        ship.root.position = [0, 0, quayZ - 8.6]
        ship.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]) // bow to the west: it arrives from the east
        root.addChild(ship.root)
        world.animators.append(ShipAnimator(ship: ship, game: game, berthX: 0))
        let shipLight = Geo.part(ship.root, Geo.box([0.5, 0.5, 0.5]), Materials.glowing(base: .white, glow: Palette.lampGlow, intensity: 0), at: [-28, 20.2, 0])
        parts.lampHeads.append(shipLight)

        // Straddle carriers: quay → yard and back
        let straddles = [Vehicles.straddleCarrier(), Vehicles.straddleCarrier()]
        for (i, (v, x)) in zip(straddles, [Float(-12), 30]).enumerated() {
            let cargo = v.cargo
            weak var driver: VehicleDriver?
            let d = VehicleDriver(v, legs: [
                .drive(DrivePath([[x, 0, 24], [x, 0, -16]]), speed: 5, onStart: { driver?.setStatus("To the quay") }),
                .wait(2.4, onStart: { cargo?.isEnabled = true; driver?.setStatus("Picking up") }),
                .drive(DrivePath([[x, 0, -16], [x, 0, 24]]), reverse: true, speed: 4, onStart: { driver?.setStatus("To the stacks") }),
                .wait(2.4, onStart: { cargo?.isEnabled = false; driver?.setStatus("Stacking") }),
            ], startAt: Float(i) * 9)
            driver = d
            root.addChild(v.root)
            world.vehicles.append(v)
            world.animators.insert(d, at: 0)
            world.labels.append(FloatingLabel(id: "SC-0\(i + 1)", color: Palette.forklift, vehicle: v) { d.shownStatus })
        }
        // Reach stacker between the loading lanes
        let (stacker, boom) = Vehicles.reachStacker()
        stacker.root.position = [39.5, 0, -4]
        stacker.root.orientation = simd_quatf(angle: deg(-90), axis: [0, 1, 0])
        root.addChild(stacker.root)
        world.animators.append(ReachStackerAnimator(boom: boom, cargo: stacker.cargo, game: game))

        // A tug doing laps in the bay
        let tug = Vehicles.tug()
        let tugPath = DrivePath([[150, 0, -90], [60, 0, -118], [-60, 0, -112], [-140, 0, -80], [-60, 0, -58], [60, 0, -62], [150, 0, -90]])
        let tugDriver = VehicleDriver(tug, legs: [.drive(tugPath, speed: 4.5)], startAt: 30)
        tugDriver.setStatus("Harbour patrol")
        root.addChild(tug.root)
        world.animators.insert(tugDriver, at: 0)
        world.labels.append(FloatingLabel(id: "TUG-2", color: Palette.container, vehicle: tug) { tugDriver.shownStatus })

        Common.walkers(world, root, routes: [
            [[-40, 0, -18], [-20, 0, -18.5], [-4, 0, -17.8]],
            [[34, 0, 30], [34, 0, 14], [36, 0, 0]],
            [[-62, 0, 26], [-50, 0, 25], [-36, 0, 26.5]],
        ])

        // The fleet: container haulers through the gate, loaded in lanes A and B, never driving through each other
        // (the same yard traffic as Riverside), each trailer following its tractor round the corners
        let fleet = YardFleetVisual(game: game, layout: fleetLayout(), root: root) { Vehicles.hauler(index: Int.random(in: 0..<20)) }
        world.fleet = fleet
        game.holdVehicle = { [weak fleet] truck in fleet?.shouldHold(truck) ?? false }
        game.holdDock = { [weak fleet] dock in fleet?.dockBusy(dock) ?? false }
        world.animators.append(fleet)
        Common.traffic(world, root, fleet: fleet)

        // Stock: containers in the yard (25 stacks × 3), loads waiting at the lanes
        var slots: [(position: V3, yaw: Float)] = []
        for z in yardRows { for x in yardColumns { slots.append((V3(x, 0, z), 0)) } }
        let layout = StockLayout(unit: .container, slots: slots, layers: 3, scale: 1,
                                 dockSlots: [(V3(36.5, 0, 6), .pi / 2), (V3(36.5, 0, 20), .pi / 2)], dockLayers: 2)
        let visuals = GameVisuals(game: game, arView: arView, root: root, layout: layout)
        world.visuals = visuals
        world.animators.append(visuals)
        // A third crane joins at Quay cranes level 25
        let crane3 = QuayCrane(x: 46, seed: 7)
        root.addChild(crane3.root)
        visuals.unlock(crane3.root) { $0.level(.receiving) >= 25 }

        Common.pin(world, root, camera: camera, at: [-42, 8.6, 9])
        Common.pin(world, root, camera: camera, at: [48, 7.5, 40])

        let research = ResearchVisuals(root: root, site: parts)
        HarbourResearch.install(research, cranes: cranes + [crane3], fleet: fleet, game: game)
        for id in game.research { research.reveal(id, animated: false) }
        world.research = research
        world.animators.append(research)

        NSLog("[Waybill] harbour scenery vertices: %d", s.vertexCount)
        s.build(into: root)
        return world
    }

    // MARK: Fleet routes

    /// Hauler routes, for the tractor's rear axle (the trailer follows behind; every route was checked with the trailer's
    /// real sweep against the gatehouse, the canopy posts, the stacks, the reach stacker and the crane legs):
    /// in on the westbound road and one right turn through the gate east of the booth, into lane A or B; out north,
    /// round to the exit road, down it and east. Passing road traffic yields to them (see `Common.traffic`).
    static func fleetLayout() -> YardLayout {
        typealias P = SIMD2<Float>
        let road = Common.laneWest, roadE = Common.laneEast
        let north = P(0, -1), south = P(0, 1), east = P(1, 0), west = P(-1, 0)
        func path(_ ps: [P]) -> DrivePath { DrivePath(ps.map { V3($0.x, 0, $0.y) }, samplesPerSegment: 3) }
        func straight(_ from: P, _ dir: P, _ length: Float) -> [P] { Turtle.path(from: from, heading: dir, [.straight(length)]) }

        let gateX: Float = 53.4, gateZ: Float = 39.7, turnZ: Float = 31, stopZ: Float = 5.95
        // In the westbound lane, then one right turn through the gate east of the booth (the canopy has no posts on that
        // side, so the trailer can cut the corner)
        var inPts = straight(P(190, road), west, 190 - (gateX + 11))
        inPts += Dubins.path(from: inPts.last!, heading: west, to: P(gateX, gateZ), heading: north, radius: 9).dropFirst()
        inPts += straight(P(gateX, gateZ), north, gateZ - turnZ + 9).dropFirst()
        let approach = path(inPts)
        let lanes: [Float] = [44, 52]
        let setup = lanes.map { x in path(Dubins.path(from: P(gateX, turnZ), heading: north, to: P(x, stopZ), heading: north, radius: 12)) }
        var depart: [DrivePath] = [], claimEnd: [Float] = []
        for x in lanes {
            var out = straight(P(x, stopZ), north, stopZ + 3)
            out += Dubins.path(from: out.last!, heading: north, to: P(66, -3), heading: south, radius: 7).dropFirst()
            out += straight(P(66, -3), south, 49).dropFirst()
            out += Dubins.path(from: out.last!, heading: south, to: P(88, roadE), heading: east, radius: 9).dropFirst()
            out += straight(P(88, roadE), east, 90).dropFirst()
            let route = path(out)
            depart.append(route)
            var end: Float = 0                     // holds its space until it's past the arrivals' swing
            while end < route.length, !(route.sample(end).position.z > 50 && route.sample(end).position.x > 110) { end += 0.5 }
            claimEnd.append(end)
        }
        func sAt(_ test: (V3) -> Bool) -> Float {
            var s: Float = 0
            while s < approach.length, !test(approach.sample(s).position) { s += 0.25 }
            return s
        }
        let turnS = sAt { $0.z < turnZ + 0.05 && $0.x < gateX + 0.5 }

        var layout = YardLayout(
            approach: approach, bayX: lanes,
            turnPoints: [turnS, turnS],
            setup: setup, reverse: [], depart: depart, departClaimEnd: claimEnd,
            queueFront: { _ in turnS - 0.5 },
            queueSpacing: 21,
            limit: { p in
                if p.z > 47 { return p.x > 95 ? 11 : 5 }   // the road; slow for the turn in and out
                if p.z > 33 || p.z < 1 || p.x > 60 { return 3.6 }   // gate, turns, exit road
                return 4.5
            },
            reverseSpeed: 2.3,
            axleToOrigin: -4.05,                     // the rig's origin is 4 m behind the tractor's rear axle
            axleToCenter: 1.75)
        // Only the next truck waits inside the gate; the others wait off the map (no queue on the public road)
        layout.queueSpot = { k, _ in k == 0 ? turnS - 0.5 : 2 }
        layout.halfLength = 2.6
        layout.halfWidth = 1.4
        layout.trailer = .init(hitch: 0.35, length: 9.6, front: 1.3, back: 11.35)
        layout.driveThrough = true
        layout.showsCargo = true
        layout.gridOrigin = SIMD2(-10, -24)
        layout.gridSize = (220, 86)
        layout.bayName = { $0 == 0 ? "Lane A" : "Lane B" }
        layout.mayAppear = { $0.x > 130 }
        layout.inYard = { $0.z < 44 }
        return layout
    }

    // MARK: Gate and loading lanes

    private static func buildGate(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        // Lane markings
        for x: Float in [40, 48, 56] { s.box(.markingWhite, [0.18, 0.02, 30], at: [x, 0.04, 14]) }
        for (x, label) in [(Float(44), "A"), (Float(52), "B")] {
            Geo.decal(root, mask: Textures.text(label), tint: .white, opacity: 0.9, size: [3.2, 0.7], at: [x, 0.05, 27])
        }
        // Gate canopy over the entry
        s.box(.white, [20, 0.5, 7], at: [48, 6.4, 40])
        s.box(.brand, [20.2, 0.6, 7.2], at: [48, 6.9, 40])
        // Posts on the west side and on the booth island; the east side is cantilevered, so haulers turning in from the
        // road can swing their trailers through
        for (x, z): (Float, Float) in [(38.5, 37.2), (38.5, 42.8), (48, 37.6), (48, 42.4)] { s.box(.darkMetal, [0.35, 6.4, 0.35], at: [x, 3.2, z]) }
        s.box(.brandShade, [0.5, 0.9, 7.2], at: [48, 5.9, 40])          // the beam that carries the cantilever
        s.rounded(.white, [1.6, 2.6, 2.2], radius: 0.1, at: [48, 1.3, 40])
        s.box(.brand, [1.8, 0.25, 2.4], at: [48, 2.72, 40])
        parts.windows.append(Geo.part(root, Geo.box([0.05, 0.9, 1.4]), Materials.glowing(base: Palette.glass, glow: Palette.windowGlow, intensity: 0), at: [48.82, 1.65, 40]))
        s.groundShadow(.rect, center: [48, 0.05, 40], size: [22, 9])
        // Exit road along the east edge
        Geo.part(root, .generatePlane(width: 9, depth: 54), .road, at: [64, 0.03, 20])
        Geo.part(root, .generatePlane(width: 12, depth: 9, cornerRadius: 2), .road, at: [66, 0.032, 45])
        Geo.part(root, .generatePlane(width: 14, depth: 9, cornerRadius: 2), .road, at: [52, 0.032, 46])
    }

    // MARK: Office, warehouse, car park

    private static func buildOffice(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        // Terminal office: three floors of glass
        let c = V3(-60, 0, 33)
        s.rounded(.white, [16, 11, 10], radius: 0.2, at: c + [0, 5.5, 0])
        s.box(.brand, [16.4, 0.7, 10.4], at: c + [0, 11.2, 0])
        var windows = MeshBuilder()
        for y: Float in [2.6, 5.9, 9.2] {
            windows.addBox([14.4, 1.6, 0.08], .make(c + [0, y, 5.03]))
            windows.addBox([0.08, 1.6, 8.4], .make(c + [8.03, y, 0]))
        }
        if let mesh = try? windows.makeMesh() {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: Palette.glass, glow: Palette.windowGlow, intensity: 0)])
            root.addChild(e)
            parts.windows.append(e)
        }
        let sign = ModelEntity(mesh: .generatePlane(width: 9, height: 1.6),
                               materials: [Materials.decal(mask: Textures.logo("Waybill", emblem: .route, uppercase: true), tint: .white, opacity: 0.95)])
        sign.position = c + [0, 10.4, 5.06]
        sign.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sign)
        Geo.contactShadow(root, size: [20, 14], at: c + [0, 0.045, 0], opacity: 0.3)
        // Container freight station (a long shed)
        let w = V3(-24, 0, 35)
        s.rounded(.white, [30, 7, 11], radius: 0.15, at: w + [0, 3.5, 0])
        s.gable(.brand, width: 11.6, rise: 1.6, length: 30.6, at: w + [0, 7, 0], yaw: .pi / 2)
        for x: Float in [-10, -2, 6] {
            s.box(.concreteDark, [4, 4.2, 0.12], at: w + [x, 2.1, -5.56])
            s.box(.marking, [0.14, 0.02, 9], at: w + [x - 2.3, 0.04, -10])
        }
        Geo.contactShadow(root, size: [34, 15], at: w + [0, 0.045, 0], opacity: 0.3)
        // Staff car park
        let paints: [Mat] = [.carSlate, .white, .carCoral, .carMint, .carSand, .carSlate]
        for i in 0..<6 where i != 2 {
            Props.parkedCar(s, at: [-72 + Float(i) * 3.2, 0, 22], yaw: .pi / 2, paint: paints[i])
        }
        for i in 0...6 { s.box(.markingWhite, [0.12, 0.02, 5.2], at: [-73.6 + Float(i) * 3.2, 0.04, 22.2]) }
        Props.bush(s, at: [-52, 0, 39.5], size: 0.9)
        Props.bush(s, at: [-68, 0, 39.5], size: 0.8)
    }

    // MARK: Breakwater, lighthouse, buoys

    private static func buildBreakwater(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        let a = V3(40, 0, -100), b = V3(175, 0, -62)
        let steps = 36
        for i in 0...steps {
            let p = lerp(a, b, Float(i) / Float(steps))
            for _ in 0..<3 {
                let q = p + [rng.float(-2...2), 0, rng.float(-2.5...2.5)]
                s.rounded(rng.chance(0.5) ? .rock : .rockDark, [rng.float(2.4...4.2), rng.float(1.6...2.8), rng.float(2.2...3.6)], radius: 0.6,
                          at: q + [0, 0.4, 0], yaw: rng.float(0...3))
            }
        }
        let d = b - a
        s.box(.concrete, [simd_length(d), 0.5, 3.2], at: (a + b) / 2 + [0, 2.0, 0], yaw: atan2(-d.z, d.x))
        // Lighthouse
        let l = b + V3(4, 0, -1)
        s.cone(.white, radius: 2.6, height: 1, at: l + [0, 1.2, 0])
        s.group(.make(l)) {
            s.cylinder(.white, radius: 1.9, height: 14, at: [0, 8.5, 0])
            for y: Float in [5, 10] { s.cylinder(.brand, radius: 1.95, height: 1.6, at: [0, y, 0]) }
            s.cylinder(.darkMetal, radius: 2.4, height: 0.3, at: [0, 15.6, 0])
            s.cylinder(.brand, radius: 1.4, height: 0.9, at: [0, 18.5, 0])
            s.cone(.brand, radius: 1.5, height: 1.4, at: [0, 19.6, 0])
        }
        parts.lampHeads.append(Geo.part(root, Geo.cylinder(radius: 1.2, height: 2.2),
                                        Materials.glowing(base: UIColor(hex: 0xF4F1E6), glow: Palette.lampGlow, intensity: 0), at: l + [0, 16.9, 0]))
        // Buoys marking the channel
        for (p, mat) in [(V3(-30, 0, -70), Mat.carCoral), (V3(30, 0, -74), .carMint), (V3(-80, 0, -95), .carCoral), (V3(-20, 0, -110), .carMint)] {
            s.cylinder(mat, radius: 0.7, height: 1.6, at: p + [0, 0.4, 0])
            s.cone(mat, radius: 0.5, height: 1.0, at: p + [0, 1.7, 0])
        }
    }

    // MARK: City (south of the road) and the far shore

    private static func buildCity(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        var lit = MeshBuilder(), dark = MeshBuilder()
        Geo.part(root, .generatePlane(width: 600, depth: 120), .concreteDark, at: [0, 0.012, 122])
        // Street grid
        for x: Float in stride(from: -240, through: 240, by: 60) { Geo.part(root, .generatePlane(width: 10, depth: 120), .road, at: [x, 0.02, 122]) }
        Geo.part(root, .generatePlane(width: 600, depth: 10), .road, at: [0, 0.02, 102])
        let bodies: [Mat] = [.white, .insulated, .carSand, .stone, .steel]
        var bx: Float = -270
        while bx < 270 {
            for row in 0..<2 {
                let z: Float = row == 0 ? 76 : 120
                let size = V3(rng.float(14...24), rng.float(12...34), rng.float(12...18))
                let p = V3(bx + rng.float(-2...2), 0, z + rng.float(-2...2))
                if abs(p.x - 0) < 300 {
                    Common.building(s, windows: &lit, dark: &dark, at: p, size: size, body: bodies[Int(rng.next() % 5)],
                                    roof: rng.chance(0.3) ? .brand : .brandShade, rng: &rng)
                }
            }
            bx += rng.float(24...32)
        }
        // Street trees along the road
        var tx: Float = -200
        while tx < 200 {
            Props.tree(s, at: [tx, 0, 62.5], size: rng.float(0.7...0.9), rng: &rng)
            tx += rng.float(10...16)
        }
        Common.finishWindows(root, parts, lit: lit, dark: dark)
    }

    /// Towers across the bay (a skyline on the horizon).
    private static func buildFarShore(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        var lit = MeshBuilder(), dark = MeshBuilder()
        Geo.part(root, .generatePlane(width: 900, depth: 200), .grass, at: [-100, 0.06, -460])
        var x: Float = -420
        while x < 160 {
            let h = rng.float(18...70)
            Common.building(s, windows: &lit, dark: &dark, at: [x, 0, -400 + rng.float(-20...20)], size: [rng.float(14...22), h, rng.float(14...22)],
                            body: rng.chance(0.5) ? .glassTower : .steel, roof: .brandShade, rng: &rng, floor: 4)
            x += rng.float(22...34)
        }
        Common.finishWindows(root, parts, lit: lit, dark: dark)
    }
}
