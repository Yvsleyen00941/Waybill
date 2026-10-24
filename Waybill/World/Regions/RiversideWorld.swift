import RealityKit
import UIKit

/// Everything a region builder puts into the world, handed to the `WorldController`.
final class BuiltWorld {
    var site = SiteParts()
    var animators: [WorldAnimator] = []
    var vehicles: [Vehicle] = []
    var labels: [FloatingLabel] = []
    var fleet: FleetDisplay?
    var visuals: GameVisuals?
    var research: ResearchVisuals?
    var home = CameraHome(target: V3(2, 0, 14), yaw: deg(34), distance: 120)
    var ground = Palette.ground
    /// The site grew (Riverside's warehouse): new home view and pan limits.
    var onHomeChange: ((CameraHome) -> Void)?
    /// Where to look at the warehouse, and from how far (nil where there is none).
    var warehouseView: (() -> (target: V3, distance: Float))?
}

/// A floating tag above a vehicle ("FL-01 · Loading").
struct FloatingLabel {
    let id: String
    let color: UIColor
    let vehicle: Vehicle
    let status: () -> String
}

/// Region 1: builds the Riverside depot and brings it to life.
enum RiversideWorld {
    static func build(into root: Entity, game: GameModel, camera: Entity, arView: ARView) -> BuiltWorld {
        let world = BuiltWorld()
        let site = RiversideDepot.build(into: root)
        world.site = site

        // The hall: grows with the warehouse tier, opens doors for docked trucks, shows construction
        let warehouse = Warehouse(game: game, root: root, parts: site)
        buildAnnex(warehouse.annex)
        world.home = home(tier: game.facilityTier)
        warehouse.onGrow = { [weak world] tier in world?.onHomeChange?(home(tier: tier)) }
        world.warehouseView = { [weak game] in
            let tier = game?.construction?.tier ?? game?.facilityTier ?? 0
            let c = Warehouse.center(tier: tier)
            return (c + V3(6, 0, 12), 100 + Float(Warehouse.sections(tier: tier) - 3) * 9)
        }

        // Map pins float and their rings pulse
        for (i, pin) in site.pins.enumerated() { world.animators.append(PinAnimator(pin, camera: camera, phase: Float(i) * 0.8)) }
        for (i, ring) in site.pinRings.enumerated() { world.animators.append(PulseAnimator(ring, phase: Float(i) * 0.7)) }

        // Pallets the forklifts set down on the dock
        let drop = DropAnimator(at: site.dropZone)
        let drop3 = DropAnimator(at: site.dropZone3)
        world.animators += [drop, drop3]

        // Forklifts, traffic and the barge (scripted loops)
        let corner = SharedSpot()
        let forklift = Vehicles.forklift()
        let forklift2 = Vehicles.forklift()
        forklift2.root.position = [-20.6, 0, 13.6]
        forklift2.root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let traffic1 = Vehicles.truck(.nordway)
        let traffic2 = Vehicles.truck(.peakfresh)
        let car1 = Vehicles.car(.carCoral), car2 = Vehicles.car(.carSlate)
        let barge = Vehicles.barge()
        let forkliftDriver = RiversideRoutines.forklift(forklift, drop: drop, spot: corner)
        let forklift2Driver = RiversideRoutines.forklift2(forklift2, drop: drop3, spot: corner)
        let bargeDriver = RiversideRoutines.barge(barge, startAt: 75)
        var movers: [(Vehicle, VehicleDriver)] = [
            (forklift, forkliftDriver), (forklift2, forklift2Driver),
            (traffic1, RiversideRoutines.roadTruck(traffic1, startAt: 6)), (traffic2, RiversideRoutines.roadTruck(traffic2, startAt: 36)),
            (car1, RiversideRoutines.roadCar(car1, startAt: 21)), (car2, RiversideRoutines.roadCar(car2, startAt: 50)),
            (barge, bargeDriver),
        ]
        // Staff walking around the west yard (away from the trucks)
        let routes: [[V3]] = [
            [[-29.2, 0, 11.6], [-26.4, 0, 10.6], [-24.0, 0, 10.4], [-20.1, 0, 10.0]],
            [[-35.4, 0, 14.2], [-35.4, 0, 22], [-35.2, 0, 29.0], [-32.2, 0, 29.6]],
            [[-24.5, 0, 29.4], [-31.6, 0, 29.2], [-31.8, 0, 14.6], [-28.4, 0, 14.2]],
        ]
        for (i, route) in routes.enumerated() {
            let person = Vehicles.person(vest: i == 1 ? .brand : .hiVis, helmet: i == 2 ? .forklift : .white)
            let driver = RiversideRoutines.walker(person, route: route, pause: Float(3 + i * 2), startAt: Float(i) * 7)
            movers.append((person, driver))
            world.animators.append(PersonAnimator(person, seed: Float(i) * 1.7))
        }
        for (vehicle, driver) in movers {
            root.addChild(vehicle.root)
            world.vehicles.append(vehicle)
            world.animators.insert(driver, at: 0) // drivers first, so walk/bob effects layer on top
        }

        // The fleet: every truck follows its state in the economy, the yard keeps them from colliding
        let fleet = YardFleetVisual(game: game, layout: RiversideDepot.yardLayout(), root: root) { Vehicles.truck(.waybill) }
        world.fleet = fleet
        game.holdVehicle = { [weak fleet] truck in fleet?.shouldHold(truck) ?? false }
        game.holdDock = { [weak fleet] dock in fleet?.dockBusy(dock) ?? false }
        world.animators.append(fleet)

        // Pallet trucks loading the docked trucks, one per bay
        var workers: [DockWorker] = []
        for bay in 1...Warehouse.maxSections {
            let w = DockWorker(bay: bay, root: root, loading: { [weak fleet] in fleet?.dockLoading[bay - 1] ?? nil },
                               open: { [weak warehouse] in warehouse?.isOpenForWork(bay: bay) ?? false },
                               built: { [weak warehouse] in warehouse?.isBuilt(bay: bay) ?? false })
            workers.append(w)
            world.vehicles.append(w.asVehicle)
        }
        // A loaded truck leaves only once the pallet truck is back inside, the leveller is up and the door is down
        fleet.bayBusy = { [weak warehouse] bay in
            guard bay >= 0, bay < workers.count else { return false }
            return workers[bay].isOut || !(warehouse?.isShut(bay: bay + 1) ?? true)
        }
        world.animators.append(EveryFrame { [weak warehouse, weak fleet] _, _ in
            guard let fleet, let warehouse else { return }
            warehouse.dockStates = fleet.dockStates
            for (i, w) in workers.enumerated() { warehouse.workerOut[i] = w.isOut }
        })
        world.animators.append(warehouse)
        world.animators += workers as [WorldAnimator]
        // The dock marshal waves reversing trucks onto the bumpers
        let marshal = DockMarshal(root: root, job: { [weak fleet] in fleet?.dockingJob() },
                                  canPass: { bay in bay < 0 || bay >= workers.count || !workers[bay].isOut })
        world.animators.append(marshal)
        world.vehicles.append(marshal.person)

        if let barrier = site.barrier {
            world.animators.append(BarrierAnimator(pivot: barrier, point: RiversideDepot.gatePoint) { [weak fleet] in fleet?.visiblePositions ?? [] })
        }
        if let water = site.water, let flow = WaterAnimator.flow(water) { world.animators.append(flow) }

        // Stock in the staging area (11 stacks × 3 layers); loads waiting on the dock beside every open bay
        var slots: [(position: V3, yaw: Float)] = []
        for row in 0..<4 {
            for col in 0..<3 where !(row == 0 && col == 2) {
                slots.append(([-29.5 + Float(col) * 2.6, 0, 16.5 + Float(row) * 3.3], Float(slots.count % 3 - 1) * 0.04))
            }
        }
        // Beside each door (not left of bay 1: the forklifts drop pallets there), in dock order so open bays come first
        var dockSlots: [(position: V3, yaw: Float)] = []
        var slotsPerDock: [Int] = []
        for bay in Warehouse.dockBays {
            let x = Warehouse.doorX(bay: bay)
            dockSlots.append((V3(x + 3.35, RiversideDepot.dockHeight, 12.35), 0))
            if bay > 1 { dockSlots.append((V3(x - 3.35, RiversideDepot.dockHeight, 12.35), 0)) }
            slotsPerDock.append(bay > 1 ? 2 : 1)
        }
        var layout = StockLayout(unit: .pallet, slots: slots, layers: 3, dockSlots: dockSlots, dockLayers: 2)
        layout.activeDockSlots = { game in slotsPerDock.prefix(min(game.docks, slotsPerDock.count)).reduce(0, +) }
        let visuals = GameVisuals(game: game, arView: arView, root: root, layout: layout)
        visuals.unlock(forklift2.root) { $0.level(.putaway) >= 10 }
        world.visuals = visuals
        world.animators.append(visuals)

        // Research you can see
        let research = ResearchVisuals(root: root, site: site)
        RiversideResearch.install(research, forklifts: [forklift, forklift2], docks: workers.map(\.asVehicle), fleet: fleet, annex: warehouse.annex)
        for id in game.research { research.reveal(id, animated: false) }
        world.research = research
        world.animators.append(research)

        world.labels = [
            FloatingLabel(id: "BRG-07", color: Palette.container, vehicle: barge) { bargeDriver.shownStatus },
            FloatingLabel(id: "FL-02", color: Palette.forklift, vehicle: forklift2) { forklift2Driver.shownStatus },
            FloatingLabel(id: "FL-01", color: Palette.forklift, vehicle: forklift) { forkliftDriver.shownStatus },
        ]
        return world
    }

    /// The default view: the whole hall plus the yard, wider as the warehouse grows.
    static func home(tier: Int) -> CameraHome {
        let east = Warehouse.eastX(sections: Warehouse.sections(tier: tier))
        let grow = east - 18
        return CameraHome(target: V3(2 + grow * 0.45, 0, 14), yaw: deg(34), distance: 120 + grow * 0.75,
                          boundsMin: SIMD2(-75, -45), boundsMax: SIMD2(max(70, east + 52), 70))
    }

    /// Static things at the east end of the hall that move along when it grows: an outdoor rack and a few pallets.
    private static func buildAnnex(_ annex: Entity) {
        let s = Scenery()
        var rng = SeededRandom(seed: 21)
        Props.rack(s, at: [9, 0, -2], yaw: .pi / 2, bays: 3, rng: &rng)
        Props.palletStack(s, at: [6.2, 0, 7.6], yaw: 0.1, layers: 2, rng: &rng)
        Props.palletStack(s, at: [6.4, 0, 9.6], yaw: -0.08, layers: 1, crates: true, rng: &rng)
        s.build(into: annex)
    }
}

extension RiversideDepot {
    /// Truck routes in the yard, for the truck's rear axle (the cab swings wide like a real truck's): in from the
    /// road through the east gate and along the yard lane (the waiting line forms there); past the bay, cab swung
    /// out towards the fence, then one smooth reverse arc that straightens out onto the bumpers; straight out of the
    /// bay, a wide turn onto the lane and out through the west exit. No turn is tighter than the truck can steer
    /// (about 9 m at the rear axle); the routes were checked against the fence and the trucks in the other bays.
    static func yardLayout() -> YardLayout {
        typealias P = SIMD2<Float>
        let lane = yardLaneZ, road = laneWestbound
        let axle: Float = 2.85                                   // rear axles (tandem) to the truck's origin
        let dockedR = Warehouse.dockedZ - axle                   // rear axle of a docked truck
        func v3(_ ps: [P]) -> [V3] { ps.map { V3($0.x, 0, $0.y) } }
        func path(_ ps: [P]) -> DrivePath { DrivePath(v3(ps), samplesPerSegment: 3) }

        // In: the road → an S-bend through the gate → the lane, and west along it past every bay
        let gate = P(73.5, 42), gateHeading = simd_normalize(P(-0.42, -0.91))
        var inPts = Dubins.path(from: P(230, road), heading: P(-1, 0), to: gate, heading: gateHeading, radius: 12)
        // (the straight part of the lane starts at x = 61, east of where any bay's manoeuvre begins)
        inPts += Dubins.path(from: gate, heading: gateHeading, to: P(61, lane), heading: P(-1, 0), radius: 12).dropFirst()
        inPts += Turtle.path(from: P(61, lane), heading: P(-1, 0), [.straight(83)]).dropFirst()
        let approach = path(inPts)

        // Out: the S-bend through the west exit onto the road
        let exitGate = P(-31.5, 42), exitHeading = simd_normalize(P(-0.42, 0.91))
        let exitTail = Array(Dubins.path(from: exitGate, heading: exitHeading, to: P(-70, road), heading: P(-1, 0), radius: 12).dropFirst())
            + Turtle.path(from: P(-70, road), heading: P(-1, 0), [.straight(45)]).dropFirst()

        let bays = (1...Warehouse.maxSections).map { Warehouse.doorX(bay: $0) }
        let swing: Float = 65 * .pi / 180                         // how far the cab is turned out when it stops to reverse
        let setupZ: Float = 37, reverseRadius: Float = 9.6, outRadius: Float = 10.5
        var setup: [DrivePath] = [], reverse: [DrivePath] = [], depart: [DrivePath] = [], turnX: [Float] = [], claimEnd: [Float] = []
        for x in bays {
            // Reverse, designed backwards from the bay: straight out of it, then the arc to where the truck stops
            let straightIn = setupZ - dockedR - reverseRadius * sin(swing)
            let back = Turtle.path(from: P(x, dockedR), heading: P(0, 1), [.straight(straightIn), .arc(radius: reverseRadius, angle: swing)])
            reverse.append(path(Array(back.reversed())))
            // Set-up: along the lane past the bay, then a long gentle arc that ends on that stopping pose
            let turnBack = Float.pi / 2 - swing
            let setupRadius = (setupZ - lane) / (1 - cos(turnBack))
            let arcStart = back.last!.x + setupRadius * sin(turnBack)
            setup.append(path(Turtle.path(from: P(arcStart + 5, lane), heading: P(-1, 0),
                                          [.straight(5), .arc(radius: setupRadius, angle: -turnBack)])))
            turnX.append(arcStart + 5)
            // Out: straight out, a wide right turn onto the lane, along it, out of the exit (the bay next to the exit
            // sweeps straight across to it)
            var out: [P]
            if x - outRadius > -12 {
                out = Turtle.path(from: P(x, dockedR), heading: P(0, 1), [.straight(lane - dockedR - outRadius), .arc(radius: outRadius, angle: .pi / 2)])
                out += Turtle.path(from: out.last!, heading: P(-1, 0), [.straight(out.last!.x + 12)]).dropFirst()
                out += Dubins.path(from: out.last!, heading: P(-1, 0), to: exitGate, heading: exitHeading, radius: 11).dropFirst()
                out += exitTail
            } else {
                // Bay 1, beside the forklifts and close to the exit: straight out past the forklift corner, then one
                // sweep across to the exit
                let gate1 = P(-32, 42), gate1Heading = simd_normalize(P(-0.62, 0.78))
                out = Turtle.path(from: P(x, dockedR), heading: P(0, 1), [.straight(23.5 - dockedR)])
                out += Dubins.path(from: out.last!, heading: P(0, 1), to: gate1, heading: gate1Heading, radius: 10.5).dropFirst()
                out += Dubins.path(from: gate1, heading: gate1Heading, to: P(-70, road), heading: P(-1, 0), radius: 11).dropFirst()
                out += Turtle.path(from: P(-70, road), heading: P(-1, 0), [.straight(45)]).dropFirst()
            }
            let route = path(out)
            depart.append(route)
            var end: Float = 0
            while end < route.length, route.sample(end).position.z < 44.5 { end += 0.5 }
            claimEnd.append(end)
        }
        // Distance along the approach where the rear axle passes a point of the lane (straight from x = 61 westwards,
        // so it's worked out once and then simple arithmetic: it's asked for every truck, every frame)
        var s61: Float = 0
        while s61 < approach.length, approach.sample(s61).position.x > 61 { s61 += 0.05 }
        func laneS(_ x: Float) -> Float { s61 + (61 - x) }
        let queueOffset = Float(GameModel.queueOffset)
        return YardLayout(
            approach: approach, bayX: bays,
            turnPoints: turnX.map(laneS),
            setup: setup, reverse: reverse, depart: depart, departClaimEnd: claimEnd,
            queueFront: { open in laneS((open.map { bays[$0] }.max() ?? 0) + queueOffset) },
            queueSpacing: 13.5,
            limit: { p in
                if p.z > 46.5 { return 11 }               // the road
                if p.x > 58 || p.x < -14 { return 4.2 }   // through the gate, round to the exit
                return 5.5                                // about 20 km/h along the yard lane
            },
            reverseSpeed: 2.3,
            axleToOrigin: axle,
            axleToCenter: axle - 0.05)
    }
}
