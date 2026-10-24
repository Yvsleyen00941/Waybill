import RealityKit
import UIKit

/// Region 4: Metro micro-hub in a dense city.
///
/// Layout (metres, seen from above; +z is towards the avenue):
///
///   ════════ back street (z = -42): vans leave west; the autonomous truck comes and goes east ════════
///   towers │  HUB (glass, x -32…32, z -28…0), four drive-through bays │ side dock, service yard │ side street (x 62)
///   stock cages │ robots │  bay lanes │ yard lane (z 34) ← gate between the planters (x 31)
///   ════════ avenue (z = 52) ════════   tram line (z = 63)   towers beyond
enum MetroWorld {
    /// Drive-through bays, west to east. The first three docks of the economy are the middle and east bays (A, B, C);
    /// the west bay (D) opens with the fourth dock (the hyperloop research).
    static let bays: [Float] = [-28, -14, 0, 14]
    static func dock(ofBay bay: Int) -> Int { [3, 0, 1, 2][bay] }
    static func bay(ofDock dock: Int) -> Int { [1, 2, 3, 0][max(min(dock, 3), 0)] }
    static func bayLetter(_ bay: Int) -> String { ["D", "A", "B", "C"][bay] }
    static let hubSize = V3(64, 17, 28)
    static let hubFront: Float = 0
    static let backStreet: Float = -42
    /// Where a van's rear axle stops in its bay: the van stands between the bay lines, its side door by the cage stack.
    static let stopZ: Float = 11.35

    static func build(into root: Entity, game: GameModel, camera: Entity, arView: ARView) -> BuiltWorld {
        let world = BuiltWorld()
        world.home = CameraHome(target: V3(2, 0, 8), yaw: deg(32), distance: 142, boundsMin: SIMD2(-90, -70), boundsMax: SIMD2(90, 80))
        world.ground = UIColor(hex: 0xCFD2EC)
        let parts = world.site
        let s = Scenery()
        var rng = SeededRandom(seed: 44)

        Geo.part(root, .generatePlane(width: 2400, depth: 2400), .concreteDark, at: [0, 0, 0])
        Geo.part(root, .generatePlane(width: 96, depth: 46, cornerRadius: 2), .asphalt, at: [-8, 0.02, 22])
        Geo.part(root, .generatePlane(width: 44, depth: 6.4), .asphalt, at: [0, 0.02, -30.9])                 // apron behind the hub
        Geo.part(root, .generatePlane(width: 20, depth: 34, cornerRadius: 1.5), .asphalt, at: [45.5, 0.02, -17.5])   // service yard
        // Roads: the curbs stop at the side streets and drop where the vans and the truck cross the pavement
        let sideStreets: [Common.CurbGap] = [.street(-68.5 ... -55.5), .street(55.5...68.5)]
        Common.road(root, s, z: 52, mat: .road, north: sideStreets + [.driveway(26.5...37.5)], south: sideStreets)
        Common.road(root, s, z: backStreet, mat: .road, north: sideStreets,
                    south: sideStreets + bays.map { .driveway(($0 - 2.6)...($0 + 2.6)) } + [.driveway(47...54)])
        for x: Float in [-62, 62] { Geo.part(root, .generatePlane(width: 13, depth: 220), .road, at: [x, 0.025, 10]) }
        // Crosswalks
        for (x, z) in [(Float(-62), Float(40)), (Float(62), Float(40)), (Float(-62), Float(-30)), (Float(62), Float(-30))] {
            for k in 0..<6 { s.box(.markingWhite, [12, 0.02, 0.6], at: [x, 0.05, z + Float(k) * 1.1]) }
        }
        // Tram line on a green strip south of the avenue, with its overhead wire on poles
        Geo.part(root, .generatePlane(width: 1200, depth: 6), .grass, at: [0, 0.022, 63])
        for z: Float in [62.3, 63.7] { s.box(.metal, [1200, 0.12, 0.12], at: [0, 0.08, z]) }
        var poleX: Float = -300
        while poleX <= 300 {
            s.cylinder(.darkMetal, radius: 0.13, height: 6.6, at: [poleX, 3.3, 65.6], segments: 10)
            s.box(.darkMetal, [0.1, 0.1, 3.0], at: [poleX, 6.3, 64.2])
            s.box(.darkMetal, [0.05, 0.42, 0.05], at: [poleX, 6.08, 63])
            poleX += 30
        }
        s.box(.darkMetal, [600, 0.035, 0.035], at: [0, 5.9, 63])

        buildHub(root, s, parts)
        buildYard(root, s, parts)
        buildCity(root, s, parts, &rng)

        // Street lamps
        for x in stride(from: Float(-110), through: 110, by: 22) {
            Common.lamp(root, s, parts, at: [x, 0, 45.4], yaw: -.pi / 2)
            Common.lamp(root, s, parts, at: [x + 11, 0, -35.4], yaw: .pi / 2)
        }

        // Tram running along its line
        let tram = Vehicles.tram()
        let tramDriver = VehicleDriver(tram, legs: [
            .drive(DrivePath([[-320, 0, 63], [320, 0, 63]], samplesPerSegment: 2), speed: 10),
            .wait(6),
            .drive(DrivePath([[320, 0, 63], [-320, 0, 63]], samplesPerSegment: 2), speed: 10),
            .wait(6),
        ], startAt: 20)
        tramDriver.setStatus("Line 4")
        root.addChild(tram.root)
        world.vehicles.append(tram)
        world.animators.insert(tramDriver, at: 0)
        world.labels.append(FloatingLabel(id: "TRAM", color: Palette.rivalTeal, vehicle: tram) { tramDriver.shownStatus })

        // The autonomous truck: in along the back street, stops in the service yard, reverses onto the side dock,
        // rolls its shutter up, unloads, and leaves by the side street
        let pod = Vehicles.podTruck()
        let routes = podRoutes()
        weak var podDriver: VehicleDriver?
        let road: (V3) -> Float = { _ in 11 }
        let pd = VehicleDriver(pod, legs: [
            .planned(MotionPlan(routes.inbound, limit: road, startSpeed: 11, accel: 1.3, lateral: 1.6),
                     onStart: { podDriver?.setStatus("Inbound"); pod.signal = .auto }),
            .wait(1.2, onStart: { podDriver?.setStatus("Docking"); pod.signal = .hazard }),
            .planned(MotionPlan(routes.reverse, reverse: true, limit: { _ in 1.5 }, accel: 0.45)),
            .wait(16, onStart: { podDriver?.setStatus("Unloading"); pod.signal = .none; pod.rearDoorsOpen = true }),
            .wait(1.8, onStart: { pod.rearDoorsOpen = false }),
            .planned(MotionPlan(routes.outbound, limit: road, endSpeed: 11, accel: 1.1, lateral: 1.6),
                     onStart: { podDriver?.setStatus("Outbound"); pod.signal = .auto }),
            .wait(22, onStart: { podDriver?.setStatus("Next run") }),
        ], startAt: 10, axleOffset: -2.95)
        podDriver = pd
        root.addChild(pod.root)
        world.vehicles.append(pod)
        world.animators.insert(pd, at: 0)
        world.labels.append(FloatingLabel(id: "AV-12", color: Palette.metal, vehicle: pod) { pd.shownStatus })

        // The fleet: electric vans in through the gate, forwards into a bay, out through the hub to the back street
        // (the same yard traffic as Riverside: they never drive through each other or the passing traffic)
        let fleet = YardFleetVisual(game: game, layout: fleetLayout(), root: root) { Vehicles.van(index: 0) }
        world.fleet = fleet
        game.holdVehicle = { [weak fleet] truck in fleet?.shouldHold(truck) ?? false }
        game.holdDock = { [weak fleet] dock in fleet?.dockBusy(dock) ?? false }
        world.animators.append(fleet)
        Common.traffic(world, root, fleet: fleet)

        // A worker at every bay pushes roll cages into the loading van; the van waits until they're clear
        let loaders = bays.indices.map { bay in
            CageLoader(bayX: bays[bay], root: root, seed: Float(bay) * 1.9,
                       loading: { [weak fleet] in fleet?.dockLoading[bay] ?? nil },
                       docked: { [weak fleet] in fleet?.dockStates[bay] == .docked || fleet?.dockStates[bay] == .closing },
                       open: { [weak game] in (game?.docks ?? 0) > dock(ofBay: bay) })
        }
        for l in loaders { world.vehicles.append(l.person) }
        world.animators += loaders as [WorldAnimator]
        fleet.bayBusy = { bay in bay >= 0 && bay < loaders.count && loaders[bay].isOut }
        world.animators.append(BaySignals(root: root, at: bays.map { V3($0 + 3.05, 3.4, hubFront + 0.47) }) { [weak fleet, weak game] bay in
            guard let fleet, let game, dock(ofBay: bay) < game.docks else { return 0 }
            return fleet.dockStates[bay] == .empty ? 1 : 2
        })

        Common.walkers(world, root, routes: [
            [[-50, 0, 44], [-20, 0, 44.6], [10, 0, 44]],
            [[38, 0, 44.2], [53.8, 0, 44], [54.2, 0, 28]],
            [[-50, 0, -51.2], [-20, 0, -51.6], [20, 0, -51.0]],
            [[-30, 0, 68], [0, 0, 68.6], [40, 0, 68]],
        ])

        // Stock: roll cages in the yard; loads waiting beside the bays, behind the vans' tails
        var slots: [(position: V3, yaw: Float)] = []
        for z: Float in [15, 19, 23, 27, 31] { for x: Float in [-51, -47, -43] { slots.append((V3(x, 0, z), 0)) } }
        let dockSlots = (0..<4).map { (V3(bays[bay(ofDock: $0)] + 3.6, 0, 12.8), Float.pi / 2) }
        let layout = StockLayout(unit: .cage, slots: slots, layers: 2, dockSlots: dockSlots, dockLayers: 1)
        let visuals = GameVisuals(game: game, arView: arView, root: root, layout: layout)
        world.visuals = visuals
        world.animators.append(visuals)

        Common.pin(world, root, camera: camera, at: [-47, 6, 23])
        Common.pin(world, root, camera: camera, at: [0, 19, -14])

        let research = ResearchVisuals(root: root, site: parts)
        MetroResearch.install(research, fleet: fleet, game: game)
        for id in game.research { research.reveal(id, animated: false) }
        world.research = research
        world.animators.append(research)

        NSLog("[Waybill] metro scenery vertices: %d", s.vertexCount)
        s.build(into: root)
        return world
    }

    // MARK: Van routes

    /// Van routes, for the rear axle (the van's nose swings wide in the turns and the back follows the line). Every route
    /// was checked with the van's real sweep against the planters, lamp posts, lockers, the stock fence and the hub walls:
    /// in from the westbound lane, right through the gap between the planters and left onto the yard lane; along it and
    /// right into the bay; loaded, straight on through the hub and left onto the back street, west and away.
    static func fleetLayout() -> YardLayout {
        typealias P = SIMD2<Float>
        let north = P(0, -1), west = P(-1, 0)
        func path(_ ps: [P]) -> DrivePath { DrivePath(ps.map { V3($0.x, 0, $0.y) }, samplesPerSegment: 3) }
        let road = Common.laneWest, backLane = backStreet - 2.8
        let gateX: Float = 31, laneZ: Float = 34, turnX: Float = 20
        let approach = path(Turtle.path(from: P(200, road), heading: west, [
            .straight(200 - (gateX + 7)), .arc(radius: 7, angle: .pi / 2),        // right, through the gate
            .straight(road - 7 - (laneZ + 6)), .arc(radius: 6, angle: -.pi / 2),  // left onto the yard lane
            .straight(gateX - 6 - turnX + 9),
        ]))
        let setup = bays.map { x in
            path(Turtle.path(from: P(turnX, laneZ), heading: west, [
                .straight(turnX - (x + 6)), .arc(radius: 6, angle: .pi / 2), .straight(laneZ - 6 - stopZ),
            ]))
        }
        var depart: [DrivePath] = [], claimEnd: [Float] = []
        for x in bays {
            let route = path(Turtle.path(from: P(x, stopZ), heading: north, [
                .straight(stopZ - (backLane + 7)), .arc(radius: 7, angle: -.pi / 2), .straight(x - 7 + 170),
            ]))
            depart.append(route)
            var end: Float = 0                     // holds its space until it's past the other bays' exits
            while end < route.length, !(route.sample(end).position.z < backLane + 0.5 && route.sample(end).position.x < -44) { end += 0.5 }
            claimEnd.append(end)
        }
        var turnS: Float = 0
        while turnS < approach.length, !(approach.sample(turnS).position.x < turnX + 0.05 && approach.sample(turnS).position.z < laneZ + 0.5) { turnS += 0.25 }

        var layout = YardLayout(
            approach: approach, bayX: bays,
            turnPoints: bays.map { _ in turnS },
            setup: setup, reverse: [], depart: depart, departClaimEnd: claimEnd,
            queueFront: { _ in turnS - 0.5 },
            queueSpacing: 8.5,
            limit: { p in
                if p.z > 46 { return p.x > 60 ? 11 : 4.5 }       // the avenue; slow for the turn in
                if p.z < backStreet + 3 { return p.x < -40 ? 11 : 5 }
                if p.z < 1 { return 3.4 }                        // through the hub
                return 4.2
            },
            reverseSpeed: 2.0,
            axleToOrigin: 1.8,                       // the van's origin is 1.8 m ahead of its rear axle
            axleToCenter: 1.85)
        // Two vans wait in the yard (one at the front of the lane, one in the curve behind it); the rest off the map
        layout.queueSpot = { k, _ in k == 0 ? turnS - 0.5 : (k == 1 ? turnS - 8.5 : 2) }
        layout.halfLength = 3.2
        layout.halfWidth = 1.15
        layout.driveThrough = true
        layout.gridOrigin = SIMD2(-170, -52)
        layout.gridSize = (380, 112)
        layout.bayOfDock = { bay(ofDock: $0) }
        layout.bayName = { "Bay \(bayLetter($0))" }
        layout.mayAppear = { $0.x > 150 }
        layout.inYard = { $0.z < 44 }
        return layout
    }

    /// The autonomous truck's routes, for its rear axle (between the tandem axles): in along the back street's westbound
    /// lane and left into the service yard; back onto the side dock (built from the dock forwards, driven backwards);
    /// out east, left up the side street, right onto the back street's eastbound lane.
    static func podRoutes() -> (inbound: DrivePath, reverse: DrivePath, outbound: DrivePath) {
        typealias P = SIMD2<Float>
        func path(_ ps: [P]) -> DrivePath { DrivePath(ps.map { V3($0.x, 0, $0.y) }, samplesPerSegment: 3) }
        let dockAxle = P(hubSize.x / 2 + 5.25, hubFront - hubSize.z / 2)    // rear on the dock bumpers
        let setupX = dockAxle.x + 4 + 9, setupZ = dockAxle.y + 9
        let westLane = backStreet - 2.8, eastLane = backStreet + 2.8
        let inbound = path(Turtle.path(from: P(210, westLane), heading: P(-1, 0), [
            .straight(210 - (setupX + 8)), .arc(radius: 8, angle: -.pi / 2), .straight(setupZ - (westLane + 8)),
        ]))
        let back = Turtle.path(from: dockAxle, heading: P(1, 0), [.straight(4), .arc(radius: 9, angle: .pi / 2)])
        let outbound = path(Turtle.path(from: dockAxle, heading: P(1, 0), [
            .straight(62 + 2.8 - 8 - dockAxle.x), .arc(radius: 8, angle: -.pi / 2),
            .straight((dockAxle.y - 8) - (eastLane + 8)), .arc(radius: 8, angle: .pi / 2), .straight(140),
        ]))
        return (inbound, path(back.reversed()), outbound)
    }

    // MARK: The hub

    private static func buildHub(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        let W = hubSize.x, H = hubSize.y, D = hubSize.z
        let zc = hubFront - D / 2, back = hubFront - D
        let floor1: Float = 5
        // Ground floor: walls between the drive-through bays (front and back), side walls
        let bayW: Float = 5.2
        var edges: [Float] = [-W / 2]
        for x in bays { edges += [x - bayW / 2, x + bayW / 2] }
        edges.append(W / 2)
        for i in stride(from: 0, to: edges.count, by: 2) {
            let w = edges[i + 1] - edges[i], cx = (edges[i] + edges[i + 1]) / 2
            for z in [hubFront - 0.3, back + 0.3] { s.box(.steel, [w, floor1, 0.6], at: [cx, floor1 / 2, z]) }
            if i > 0 && i < edges.count - 2 { s.box(.interior, [0.3, floor1, D - 1.2], at: [edges[i] + 0.15, floor1 / 2, zc]) }
        }
        for x in [-W / 2 + 0.3, W / 2 - 0.3] { s.box(.steel, [0.6, floor1, D], at: [x, floor1 / 2, zc]) }
        // Bay tunnels: lined walls, a painted floor, lights along the ceiling; indigo portal frames at both ends
        var tunnelLights = MeshBuilder()
        for x in bays {
            s.box(.interior, [0.3, floor1, D - 1.2], at: [x - bayW / 2 - 0.15, floor1 / 2, zc])
            s.box(.interior, [0.3, floor1, D - 1.2], at: [x + bayW / 2 + 0.15, floor1 / 2, zc])
            s.box(.interior, [bayW, 0.1, D], at: [x, 0.05, zc])
            s.box(.white, [bayW, 0.2, D], at: [x, floor1 - 0.1, zc])
            for z in [hubFront + 0.1, back - 0.1] {
                s.box(.brand, [0.4, floor1, 0.5], at: [x - bayW / 2 - 0.1, floor1 / 2, z])
                s.box(.brand, [0.4, floor1, 0.5], at: [x + bayW / 2 + 0.1, floor1 / 2, z])
                s.box(.brand, [bayW + 0.6, 0.5, 0.5], at: [x, floor1 - 0.25, z])
                for k in 0..<5 { s.box(k % 2 == 0 ? .hiVis : .trim, [0.42, 0.3, 0.52], at: [x - bayW / 2 - 0.1, 0.25 + Float(k) * 0.3, z]) }   // kerb guard
            }
            var z = hubFront - 2
            while z > back + 1.5 { tunnelLights.addBox([0.5, 0.06, 1.6], .make([x, floor1 - 0.23, z])); z -= 4 }
        }
        if let mesh = try? tunnelLights.makeMesh(name: "metroTunnelLights") {
            let e = ModelEntity(mesh: mesh, materials: [Materials.glowing(base: .white, glow: Palette.lampGlow, intensity: 0)])
            root.addChild(e)
            parts.lampHeads.append(e)
        }
        // Storefront glazing on the ground floor between the bays, and the staff entrance on the west side
        var glazing = MeshBuilder()
        for i in stride(from: 0, to: edges.count, by: 2) where edges[i + 1] - edges[i] > 6 {
            let w = edges[i + 1] - edges[i] - 2.4, cx = (edges[i] + edges[i + 1]) / 2
            glazing.addBox([w, 1.8, 0.06], .make([cx, 2.9, hubFront + 0.03]))
        }
        s.box(.glassDark, [0.08, 2.6, 2.4], at: [-W / 2 - 0.04, 1.3, -20])
        s.box(.white, [1.6, 0.2, 3.6], at: [-W / 2 - 0.8, 2.9, -20])
        for z: Float in [-21.2, -18.8] { s.box(.trim, [0.1, 2.6, 0.06], at: [-W / 2 - 0.06, 1.3, z]) }

        // Upper floors: white floor slabs and spandrels, a continuous band of glass on every floor (dark by day, lit at
        // night), slim mullions every 2 m, indigo fins across the front
        s.box(.white, [W, H - floor1, D], at: [0, floor1 + (H - floor1) / 2, zc])
        let floors = 3, floorH = (H - floor1) / Float(floors), bandH = floorH - 1.2
        for f in 0..<floors {
            let y0 = floor1 + Float(f) * floorH + 0.75, yc = y0 + bandH / 2
            glazing.addBox([W - 0.8, bandH, 0.06], .make([0, yc, hubFront + 0.03]))
            glazing.addBox([W - 0.8, bandH, 0.06], .make([0, yc, back - 0.03]))
            for x in [-W / 2 - 0.03, W / 2 + 0.03] { glazing.addBox([0.06, bandH, D - 0.8], .make([x, yc, zc])) }
            s.box(.brand, [W + 0.16, 0.14, D + 0.16], at: [0, floor1 + Float(f) * floorH + 0.07, zc])          // slab edge
            var m = -W / 2 + 2
            while m < W / 2 - 0.5 {
                for z in [hubFront + 0.07, back - 0.07] { s.box(.darkMetal, [0.07, bandH + 0.04, 0.08], at: [m, yc, z]) }
                m += 2
            }
            var mz = back + 2
            while mz < hubFront - 0.5 {
                for x in [-W / 2 - 0.07, W / 2 + 0.07] { s.box(.darkMetal, [0.08, bandH + 0.04, 0.07], at: [x, yc, mz]) }
                mz += 2
            }
        }
        var fx: Float = -W / 2 + 4
        while fx < W / 2 {
            s.box(.brandShade, [0.3, H - floor1 + 0.2, 0.7], at: [fx, floor1 + (H - floor1) / 2, hubFront + 0.35])
            fx += 8
        }
        // Parapet (white, indigo coping), roof deck, rooftop plant
        s.box(.concreteDark, [W - 0.6, 0.1, D - 0.6], at: [0, H + 0.05, zc])
        for (size, at) in [(V3(W + 0.4, 0.9, 0.5), V3(0, H + 0.45, hubFront - 0.05)), (V3(W + 0.4, 0.9, 0.5), V3(0, H + 0.45, back + 0.05)),
                           (V3(0.5, 0.9, D + 0.4), V3(-W / 2 + 0.05, H + 0.45, zc)), (V3(0.5, 0.9, D + 0.4), V3(W / 2 - 0.05, H + 0.45, zc))] {
            s.box(.white, size, at: at)
            s.box(.brand, size + [0.04, -0.76, 0.04], at: at + [0, 0.46, 0])
        }
        for (x, z) in [(Float(-8), Float(-20)), (Float(-3), Float(-20)), (Float(2), Float(-20))] {
            s.rounded(.metal, [3.6, 1.6, 2.4], radius: 0.12, at: [x, H + 0.9, z])
            for dx: Float in [-0.85, 0.85] { s.cylinder(.darkMetal, radius: 0.62, height: 0.08, at: [x + dx, H + 1.72, z], segments: 18) }
        }
        s.rounded(.white, [5, 3, 4], radius: 0.1, at: [26, H + 1.5, -23])                 // stair and lift core
        // Canopy over the bays, bay numbers hanging under its front edge
        s.box(.white, [W - 6, 0.35, 4.5], at: [0, floor1 + 0.3, hubFront + 2.25])
        s.box(.brand, [W - 6, 0.14, 0.16], at: [0, floor1 + 0.12, hubFront + 4.5])
        for (i, x) in bays.enumerated() {
            s.box(.brand, [1.5, 1.0, 0.1], r: 0.04, at: [x, floor1 - 0.45, hubFront + 4.2])
            s.box(.darkMetal, [0.05, 0.4, 0.05], at: [x - 0.5, floor1, hubFront + 4.2])
            s.box(.darkMetal, [0.05, 0.4, 0.05], at: [x + 0.5, floor1, hubFront + 4.2])
            let number = ModelEntity(mesh: .generatePlane(width: 1.3, height: 0.9),
                                     materials: [Materials.decal(mask: Textures.text(bayLetter(i), size: CGSize(width: 160, height: 112)), tint: .white, opacity: 0.95)])
            number.position = [x, floor1 - 0.45, hubFront + 4.26]
            number.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(number)
            // Signal housing beside the portal (the lenses are `BaySignals`)
            s.box(.darkMetal, [0.32, 0.72, 0.3], r: 0.05, at: [x + 3.05, 3.4, hubFront + 0.3])
        }
        // Night: glowing roof edge and the glass bands
        let edge = Geo.part(root, Geo.box([W + 0.5, 0.15, 0.15]), Materials.glowing(base: .white, glow: UIColor(hex: 0x7C8BFF), intensity: 0),
                            at: [0, H + 0.95, hubFront + 0.25])
        parts.lampHeads.append(edge)
        if let mesh = try? glazing.makeMesh(name: "metroGlazing") {
            let e = ModelEntity(mesh: mesh, materials: [Materials.facadeGlass(night: 0)])
            root.addChild(e)
            parts.facadeGlass.append(e)
        }
        // The sign on a solid panel across the top floor
        s.box(.brand, [19, 3.0, 0.14], r: 0.05, at: [0, H - 2.25, hubFront + 0.75])
        let sign = ModelEntity(mesh: .generatePlane(width: 16, height: 3.4),
                               materials: [Materials.decal(mask: Textures.logo("Waybill", emblem: .route, uppercase: true), tint: .white, opacity: 0.95)])
        sign.position = [0, H - 2.25, hubFront + 0.83]
        sign.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sign)
        // Side dock for the autonomous truck: platform, roller door, bumpers, a light over the door
        s.box(.concrete, [3, 1.2, 10], at: [W / 2 + 1.5, 0.6, zc])
        s.box(.darkMetal, [0.12, 1.2, 10.02], at: [W / 2 + 3.0, 0.6, zc])
        s.box(.aluminium, [0.1, 3.6, 3.2], at: [W / 2 + 0.06, 3.0, zc])
        for y in stride(from: Float(1.5), to: 4.7, by: 0.3) { s.box(.metal, [0.11, 0.03, 3.2], at: [W / 2 + 0.07, y, zc]) }
        s.box(.brand, [0.3, 0.4, 4.0], at: [W / 2 + 0.15, 5.0, zc])
        for dz: Float in [-1.2, 1.2] { s.box(.rubber, [0.25, 0.5, 0.4], r: 0.04, at: [W / 2 + 3.12, 0.9, zc + dz]) }
        s.box(.white, [3.4, 0.25, 5], at: [W / 2 + 1.7, 5.4, zc])
        Geo.contactShadow(root, size: [W + 8, D + 8], at: [0, 0.04, zc], opacity: 0.3)
    }

    // MARK: Yard markings

    private static func buildYard(_ root: Entity, _ s: Scenery, _ parts: SiteParts) {
        for (i, x) in bays.enumerated() {
            s.box(.markingWhite, [0.16, 0.02, 14], at: [x - 2.9, 0.04, 7])
            s.box(.markingWhite, [0.16, 0.02, 14], at: [x + 2.9, 0.04, 7])
            s.box(.markingWhite, [5.6, 0.02, 0.3], at: [x, 0.04, stopZ - 5.15])                 // stop line by the van's nose
            paint(root, Textures.text(bayLetter(i), size: CGSize(width: 112, height: 112)), size: [3.0, 3.0], at: [x, 0.05, 16.4])
            for k in 0..<3 { s.box(.brand, [1.2, 0.02, 0.5], at: [x, 0.04, 19 + Float(k) * 1.2], yaw: deg(45)) }
        }
        // The yard lane: edge lines, direction arrows, a dashed line through the gate
        s.box(.marking, [56, 0.02, 0.16], at: [-2, 0.04, 31.6])
        s.box(.marking, [16, 0.02, 0.16], at: [18, 0.04, 36.4])
        for x: Float in [-22, -8, 4, 16] {
            paint(root, Textures.symbol("arrow.left"), size: [2.4, 2.4], at: [x, 0.05, 34])
        }
        for k in 0..<4 { s.box(.markingWhite, [0.16, 0.02, 1.2], at: [27.6, 0.04, 39.5 + Float(k) * 1.6]) }
        for k in 0..<4 { s.box(.markingWhite, [0.16, 0.02, 1.2], at: [34.4, 0.04, 39.5 + Float(k) * 1.6]) }
        paint(root, Textures.text("IN"), size: [3.6, 0.8], at: [31, 0.05, 41.5], yaw: .pi / 2)
        // Fence around the stock area, with gaps for the sorter robots (south and east sides)
        let fence: [(V3, V3)] = [(V3(-54, 0, 12.5), V3(-46.2, 0, 12.5)), (V3(-43.8, 0, 12.5), V3(-40, 0, 12.5)),
                                 (V3(-40, 0, 12.5), V3(-40, 0, 19.8)), (V3(-40, 0, 22.2), V3(-40, 0, 33.5)),
                                 (V3(-54, 0, 33.5), V3(-40, 0, 33.5)), (V3(-54, 0, 12.5), V3(-54, 0, 33.5))]
        for (a, b) in fence {
            let d = b - a
            let n = max(Int(simd_length(d) / 2.5), 1)
            for i in 0...n { s.box(.fence, [0.08, 1.4, 0.08], at: a + d * (Float(i) / Float(n)) + [0, 0.7, 0]) }
            s.box(.fence, [simd_length(d), 0.06, 0.06], at: (a + b) / 2 + [0, 1.3, 0], yaw: atan2(-d.z, d.x))
            s.box(.fence, [simd_length(d), 0.05, 0.05], at: (a + b) / 2 + [0, 0.7, 0], yaw: atan2(-d.z, d.x))
        }
        // Bollards guarding the hub's corners and the gate island
        for (x, z) in [(Float(-31.2), Float(1.2)), (Float(31), Float(1.2)), (Float(-17.6), Float(1.0)), (Float(17.6), Float(1.0))] {
            s.cylinder(.hiVis, radius: 0.13, height: 1.0, at: [x, 0.5, z], segments: 12)
            s.cylinder(.trim, radius: 0.135, height: 0.1, at: [x, 0.75, z], segments: 12)
        }
        // Planters with trees along the yard edge
        var rng = SeededRandom(seed: 7)
        for x: Float in [-36, -26, 26, 36] {
            s.box(.white, [2.2, 0.6, 2.2], at: [x, 0.3, 42])
            Props.tree(s, at: [x, 0.6, 42], size: 0.7, rng: &rng)
        }
    }

    /// White road paint on the ground (lit by the sun, so it darkens at night like the painted lines).
    private static func paint(_ root: Entity, _ mask: TextureResource, size: SIMD2<Float>, at p: V3, yaw: Float = 0) {
        let e = ModelEntity(mesh: .generatePlane(width: size.x, depth: size.y), materials: [Materials.paintedDecal(mask: mask, tint: .white, opacity: 0.88)])
        e.transform = Transform(matrix: .make(p, yaw: yaw))
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(e)
    }

    // MARK: City blocks around the hub

    private static func buildCity(_ root: Entity, _ s: Scenery, _ parts: SiteParts, _ rng: inout SeededRandom) {
        var lit = MeshBuilder(), dark = MeshBuilder()
        let bodies: [Mat] = [.glassTower, .white, .steel, .insulated, .carSand, .glassTower]
        /// Buildings fill the block without spilling over its edges (onto the streets around it).
        func block(x0: Float, x1: Float, z0: Float, z1: Float, tall: ClosedRange<Float>) {
            var x = x0
            while x1 - x > 10 {
                let w = min(rng.float(14...22), x1 - x)
                var z = z0
                while z1 - z > 10 {
                    let d = min(rng.float(14...20), z1 - z)
                    let h = rng.float(tall)
                    Common.building(s, windows: &lit, dark: &dark, at: [x + w / 2, 0, z + d / 2], size: [w - 2, h, d - 2],
                                    body: bodies[Int(rng.next() % UInt64(bodies.count))], roof: rng.chance(0.25) ? .brand : .brandShade, rng: &rng, floor: 3.6)
                    z += d + 2
                }
                x += w + 2
            }
        }
        block(x0: -150, x1: -71, z0: -32, z1: 42, tall: 18...46)
        block(x0: 71, x1: 150, z0: -32, z1: 42, tall: 18...50)
        block(x0: -150, x1: 150, z0: 72, z1: 140, tall: 14...40)
        block(x0: -150, x1: 150, z0: -130, z1: -53, tall: 24...70)
        Common.finishWindows(root, parts, lit: lit, dark: dark)
        // Street trees
        var x: Float = -140
        while x < 140 {
            Props.tree(s, at: [x, 0, 59.2], size: rng.float(0.6...0.8), rng: &rng)
            x += rng.float(12...18)
        }
    }
}
