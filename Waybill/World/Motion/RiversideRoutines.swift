import RealityKit
import simd

/// The scripted life of the Riverside depot: forklifts, traffic, walkers, the barge.
/// (The Waybill trucks follow the economy instead, see `YardFleetVisual`.)
/// Coordinates match the layout in `RiversideDepot`.
enum RiversideRoutines {
    /// Through-traffic on the far lane (rival brands).
    static func roadTruck(_ v: Vehicle, startAt offset: Float) -> VehicleDriver {
        let east = RiversideDepot.laneEastbound
        let d = VehicleDriver(v, legs: [.drive(DrivePath([[-260, 0, east], [260, 0, east]], samplesPerSegment: 2), speed: 9)], startAt: offset)
        d.setStatus("En route")
        return d
    }

    /// Same lane and speed as the trucks, so traffic never overlaps.
    static func roadCar(_ v: Vehicle, startAt offset: Float) -> VehicleDriver {
        roadTruck(v, startAt: offset)
    }

    /// Walks back and forth along a route, pausing at each end.
    static func walker(_ v: Vehicle, route points: [V3], pause: Float, startAt offset: Float) -> VehicleDriver {
        let d = VehicleDriver(v, legs: [
            .drive(DrivePath(points), speed: 1.25),
            .wait(pause),
            .drive(DrivePath(points.reversed()), speed: 1.25),
            .wait(pause),
        ], startAt: offset)
        d.setStatus("Walking")
        return d
    }

    /// A container barge drifting along the river.
    static func barge(_ v: Vehicle, startAt offset: Float) -> VehicleDriver {
        let z = RiversideDepot.riverZ + 1.2
        let d = VehicleDriver(v, legs: [.drive(DrivePath([[260, 0, z], [-260, 0, z]], samplesPerSegment: 2), speed: 3.2)], startAt: offset)
        d.setStatus("To Harbour City")
        return d
    }

    /// A forklift leg between two poses of its origin (position, facing), driven like a rear-steered forklift: the
    /// front axle (`axle` metres ahead of the origin) follows the smoothest path a forklift can turn (`radius`), and
    /// the back swings round. The poses stay exactly where they were (pick-up, drop). Use with `VehicleDriver.axleOffset`.
    static func forkliftPath(from a: V3, facing fa: V3, to b: V3, facing fb: V3, reverse: Bool, axle: Float, radius: Float = 1.7) -> DrivePath {
        let ha = simd_normalize(SIMD2(fa.x, fa.z)), hb = simd_normalize(SIMD2(fb.x, fb.z))
        let pa = SIMD2(a.x, a.z) + ha * axle, pb = SIMD2(b.x, b.z) + hb * axle
        // Backing up from a to b is the same curve as driving forwards from b to a, travelled the other way
        let pts = reverse ? Array(Dubins.path(from: pb, heading: hb, to: pa, heading: ha, radius: radius, step: 0.25).reversed())
                          : Dubins.path(from: pa, heading: ha, to: pb, heading: hb, radius: radius, step: 0.25)
        return DrivePath(pts.map { V3($0.x, 0, $0.y) }, samplesPerSegment: 3)
    }

    /// FL-01: takes pallets from the staging stack to the west end of the dock platform.
    /// It shares the corner by the platform with FL-02 (`spot`): one drives while the other waits with its load.
    static func forklift(_ v: Vehicle, drop: DropAnimator, spot: SharedSpot) -> VehicleDriver {
        guard let forks = v.forks, let cargo = v.cargo else { fatalError("forklift needs forks") }
        func forkHeight(_ from: Float, _ to: Float) -> (Float) -> Void {
            { u in forks.position.y = lerp(from, to, smootherstep(u)) }
        }
        // Fork heights are in the forklift's own (toy-scaled) units: the dock top is at 1.2 m in the world.
        let scale = v.root.scale.y
        let aboveDock = (RiversideDepot.dockHeight + 0.22) / scale
        let onDock = (RiversideDepot.dockHeight + 0.05) / scale
        weak var driver: VehicleDriver?
        // Poses (origin, facing): waiting spot, at the stack, backed out, at the dock edge
        let axle = 0.6 * scale
        let wait = (V3(-15.9, 0, 21.0), V3(-0.18, 0, -0.98)), pick = (V3(-20.9, 0, 17.1), V3(-1, 0, 0))
        let backedOut = (V3(-15.8, 0, 21.4), V3(-0.32, 0, -0.95)), atDock = (V3(-15.6, 0, 15.06), V3(0, 0, -1))
        func path(_ a: (V3, V3), _ b: (V3, V3), reverse: Bool) -> DrivePath {
            forkliftPath(from: a.0, facing: a.1, to: b.0, facing: b.1, reverse: reverse, axle: axle)
        }
        // The corner is FL-01's from leaving its waiting spot until it is back there (FL-02 works the same corner)
        let d = VehicleDriver(v, legs: [
            .hold(minimum: 0.6, until: { spot.acquire(1) }, onStart: { driver?.setStatus("Waiting") }),
            .drive(path(wait, pick, reverse: false), speed: 2.4, onStart: { driver?.setStatus("To pick-up") }),
            .wait(1.4, progress: forkHeight(0.12, 0.3), onStart: {
                cargo.isEnabled = true
                driver?.setStatus("Picking")
            }),
            .drive(path(pick, backedOut, reverse: true), reverse: true, speed: 2.0),
            .drive(path(backedOut, atDock, reverse: false), speed: 2.2, onStart: { driver?.setStatus("To the dock") }),
            .wait(1.4, progress: forkHeight(0.3, aboveDock)),
            .wait(0.6, progress: { u in
                forks.position.y = lerp(aboveDock, onDock, smootherstep(u))
                if u >= 0.999, cargo.isEnabled {
                    cargo.isEnabled = false
                    drop.trigger()
                }
            }),
            .wait(1.0, progress: forkHeight(onDock, 0.12)),
            .drive(path(atDock, wait, reverse: true), reverse: true, speed: 2.0, onStart: nil),
            .wait(0.1, onStart: { spot.release(1) }),
        ], axleOffset: axle)
        driver = d
        return d
    }
}

extension RiversideRoutines {
    /// FL-02 (unlocked at Put-away level 10): from the stack by the office to the platform's west end.
    static func forklift2(_ v: Vehicle, drop: DropAnimator, spot: SharedSpot) -> VehicleDriver {
        guard let forks = v.forks, let cargo = v.cargo else { fatalError("forklift needs forks") }
        func forkHeight(_ from: Float, _ to: Float) -> (Float) -> Void { { u in forks.position.y = lerp(from, to, smootherstep(u)) } }
        let scale = v.root.scale.y
        let aboveDock = (RiversideDepot.dockHeight + 0.22) / scale
        let onDock = (RiversideDepot.dockHeight + 0.05) / scale
        weak var driver: VehicleDriver?
        let axle = 0.6 * scale
        let pick = (V3(-20.6, 0, 13.6), V3(-1, 0, 0)), backedOut = (V3(-17.9, 0, 16.4), V3(-0.38, 0, -0.92))
        let atDock = (V3(-17.05, 0, 14.91), V3(0.34, 0, -0.94)), clear = (V3(-17.1, 0, 16.8), V3(0, 0, -1))
        func path(_ a: (V3, V3), _ b: (V3, V3), reverse: Bool) -> DrivePath {
            forkliftPath(from: a.0, facing: a.1, to: b.0, facing: b.1, reverse: reverse, axle: axle, radius: 1.3)
        }
        let d = VehicleDriver(v, legs: [
            .wait(1.4, progress: forkHeight(0.12, 0.3), onStart: { cargo.isEnabled = true; driver?.setStatus("Picking") }),
            // Only claims the corner while it is visible (before Put-away level 10 it isn't there)
            .hold(minimum: 0.2, until: { !v.root.isEnabled || spot.acquire(2) }, onStart: { driver?.setStatus("Waiting") }),
            .drive(path(pick, backedOut, reverse: true), reverse: true, speed: 1.9),
            .drive(path(backedOut, atDock, reverse: false), speed: 1.6, onStart: { driver?.setStatus("To the dock") }),
            .wait(1.4, progress: forkHeight(0.3, aboveDock)),
            .wait(0.6, progress: { u in
                forks.position.y = lerp(aboveDock, onDock, smootherstep(u))
                if u >= 0.999, cargo.isEnabled { cargo.isEnabled = false; drop.trigger() }
            }),
            .wait(1.0, progress: forkHeight(onDock, 0.12)),
            .drive(path(atDock, clear, reverse: true), reverse: true, speed: 1.8),
            .drive(path(clear, pick, reverse: false), speed: 2.2, onStart: { driver?.setStatus("To pick-up") }),
            .wait(0.1, onStart: { spot.release(2) }),
        ], axleOffset: axle)   // starts at its pick-up spot, so it waits its turn for the corner like FL-01
        driver = d
        return d
    }
}

/// A pallet that pops onto the dock when the forklift drops it, then gets taken inside.
final class DropAnimator: WorldAnimator {
    private let entity: Entity
    private var age: Float = -1

    init(at parent: Entity) {
        entity = Entity()
        Props.palletModel(into: entity)
        entity.isEnabled = false
        parent.addChild(entity)
    }

    func trigger() {
        age = 0
        entity.isEnabled = true
    }

    func update(dt: Float, time: Float) {
        guard age >= 0 else { return }
        age += dt
        let s: Float
        if age < 0.35 {
            // Squash-and-settle: overshoot slightly, then settle at 1
            let u = age / 0.35
            s = 0.9 + 0.1 * smootherstep(u) + sin(u * .pi) * 0.05
        } else if age < 5.5 {
            s = 1
        } else if age < 5.9 {
            s = 1 - smootherstep((age - 5.5) / 0.4)
        } else {
            entity.setEnabled(false)
            age = -1
            return
        }
        entity.setScale(V3(repeating: max(s, 0.001) * Props.toyScale))
    }
}
