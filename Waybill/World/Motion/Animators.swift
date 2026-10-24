import RealityKit
import UIKit
import simd

/// Anything in the world that moves every frame.
protocol WorldAnimator: AnyObject {
    /// - dt: seconds since the last frame. - time: seconds since the world started.
    func update(dt: Float, time: Float)
}

/// One step of a vehicle's routine.
enum Leg {
    /// Drive along a path. `reverse: true` drives backwards (rear first), like backing into a dock.
    case drive(DrivePath, reverse: Bool = false, speed: Float, onStart: (() -> Void)? = nil)
    /// Stand still for a while; `progress` receives 0 → 1 (used to move forks).
    case wait(Float, progress: ((Float) -> Void)? = nil, onStart: (() -> Void)? = nil)
    /// Stand still for at least `minimum` seconds, then until `until` returns true (e.g. "dispatched").
    case hold(minimum: Float, until: () -> Bool, onStart: (() -> Void)? = nil)
    /// Drive with a speed plan (speed limits, slowing for bends) instead of one smooth ease over the whole leg.
    case planned(MotionPlan, onStart: (() -> Void)? = nil)
}

/// Plays a looping list of legs on a vehicle: steering, smooth speed, rolling wheels,
/// the body leaning into braking and corners, and the lights (see `Vehicle.drive`).
final class VehicleDriver: WorldAnimator {
    let vehicle: Vehicle
    private let legs: [Leg]
    private var index = 0
    private var legTime: Float = 0
    private var started = false
    private var lastDistance: Float = 0
    private var speed: Float = 0
    private var heading: Float = 0
    private(set) var status = "Idle"
    /// While true, `status` is computed by this closure instead (e.g. live cargo counts).
    var liveStatus: (() -> String?)?
    /// The paths are followed by the vehicle's fixed axle, this far ahead of its origin (forklifts steer with the
    /// rear wheels, so their front axle follows the line and the counterweight swings round; negative for a truck's
    /// rear axle, behind the origin, so the nose swings wide). 0 = the origin, with the heading eased.
    let axleOffset: Float

    init(_ vehicle: Vehicle, legs: [Leg], startAt timeOffset: Float = 0, axleOffset: Float = 0) {
        self.vehicle = vehicle
        self.legs = legs
        self.axleOffset = axleOffset
        // Skip ahead so several vehicles don't move in lockstep
        var remaining = timeOffset
        while remaining > 0, !legs.isEmpty {
            let d = Self.duration(of: legs[index])
            if remaining < d { legTime = remaining; break }
            remaining -= d
            index = (index + 1) % legs.count
        }
        var start: (path: DrivePath, reverse: Bool, s: Float)?
        switch legs[index] {
        case .drive(let path, let reverse, _, _): start = (path, reverse, path.length * smootherstep(min(legTime / Self.duration(of: legs[index]), 1)))
        case .planned(let plan, _): start = (plan.path, plan.reverse, plan.distance(at: legTime))
        default: break
        }
        if let (path, reverse, s) = start {
            let (p, t) = path.sample(s)
            vehicle.root.position = p - (reverse ? -t : t) * axleOffset
            heading = Self.yaw(for: reverse ? -t : t)
            vehicle.root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
        }
    }

    private static func duration(of leg: Leg) -> Float {
        switch leg {
        case .drive(let path, _, let speed, _): return path.length / speed + 1.4 // extra time for easing in/out
        case .planned(let plan, _): return plan.duration
        case .wait(let seconds, _, _): return seconds
        case .hold(let minimum, _, _): return minimum
        }
    }

    private static func yaw(for direction: V3) -> Float { atan2(-direction.z, direction.x) }

    func update(dt: Float, time: Float) {
        guard !legs.isEmpty else { return }
        let leg = legs[index]
        if !started {
            started = true
            lastDistance = 0
            switch leg {
            case .drive(_, let reverse, _, let onStart):
                vehicle.setReverseLights(reverse)
                status = reverse ? "Reversing" : "Driving"
                onStart?()
            case .planned(let plan, let onStart):
                vehicle.setReverseLights(plan.reverse)
                status = plan.reverse ? "Reversing" : "Driving"
                onStart?()
            case .wait(_, _, let onStart), .hold(_, _, let onStart):
                vehicle.setReverseLights(false)
                onStart?()
            }
        }
        legTime += dt
        let duration = Self.duration(of: leg)
        var u = min(legTime / duration, 1)
        if case .hold(_, let until, _) = leg, u >= 1, !until() { u = 0.999 } // keep holding

        var drive: (path: DrivePath, reverse: Bool, s: Float)?
        switch leg {
        case .drive(let path, let reverse, _, _): drive = (path, reverse, path.length * smootherstep(u))
        case .planned(let plan, _): drive = (plan.path, plan.reverse, plan.distance(at: legTime))
        default: break
        }
        switch leg {
        case .drive, .planned:
            guard let (path, reverse, s) = drive else { break }
            let (p, tangent) = path.sample(s)
            let ds = s - lastDistance
            lastDistance = s
            let newSpeed = ds / max(dt, 0.0001)
            speed = newSpeed

            let facing = reverse ? -tangent : tangent
            let targetYaw = Self.yaw(for: facing)
            let before = heading
            if axleOffset != 0 {
                // The fixed axle is on the path and the vehicle faces along it: no sliding sideways
                heading = targetYaw
                vehicle.root.setPosition(p - facing * axleOffset)
            } else {
                vehicle.root.setPosition(p)
                let delta = angleDelta(heading, targetYaw)
                heading = abs(delta) < 1e-5 ? targetYaw : heading + delta * (1 - exp(-14 * dt))
            }
            if heading != before { vehicle.root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0]) }
            // Wheels roll and steer, the body leans, lights react (see Vehicle.drive)
            vehicle.drive(moved: abs(ds), turned: angleDelta(before, heading), reverse: reverse, dt: dt)

        case .wait(_, let progress, _):
            speed = 0
            vehicle.drive(moved: 0, turned: 0, reverse: false, dt: dt)
            progress?(u)
        case .hold:
            speed = 0
            vehicle.drive(moved: 0, turned: 0, reverse: false, dt: dt)
        }

        if u >= 1 {
            index = (index + 1) % legs.count
            legTime = 0
            started = false
        }
    }

    func setStatus(_ text: String) { status = text }
    var currentSpeed: Float { speed }
    var shownStatus: String { liveStatus?() ?? status }
    /// True while standing in a `.hold` leg (e.g. docked and loading).
    var isHolding: Bool { if case .hold = legs[index] { return true } else { return false } }
}

/// The gate barrier lifts when a vehicle comes close, and lowers again after it passes.
final class BarrierAnimator: WorldAnimator {
    private let pivot: Entity
    private let point: V3
    private let positions: () -> [V3]
    private var angle: Float = 0

    init(pivot: Entity, point: V3, positions: @escaping () -> [V3]) {
        self.pivot = pivot
        self.point = point
        self.positions = positions
    }

    func update(dt: Float, time: Float) {
        let near = positions().contains { p in simd_length(SIMD2(p.x - point.x, p.z - point.z)) < 15 }
        let target: Float = near ? deg(-80) : 0
        let before = angle
        angle = settle(angle, target, sharpness: near ? 5 : 2.5, dt: dt)
        if angle != before { pivot.orientation = simd_quatf(angle: angle, axis: [0, 0, 1]) }
    }
}

/// Scrolls the river's ripple texture so the water flows (only where the GPU version, `Materials.flowingWater`, isn't available).
final class WaterAnimator: WorldAnimator {
    /// Makes `entity` flowing water. Returns an animator to run every frame only if the GPU can't do it.
    static func flow(_ entity: ModelEntity, scale: SIMD2<Float> = SIMD2(28, 1.2), color: UIColor = UIColor(hex: 0x7C97E4),
                     flow: SIMD2<Float> = SIMD2(0.012, 0.0035)) -> WaterAnimator? {
        let flow = UserDefaults.standard.bool(forKey: "stillWater") ? .zero : flow // `-stillWater YES`: frozen ripples, to compare looks
        if let mat = Materials.flowingWater(scale: scale, color: color, flow: flow) {
            entity.model?.materials = [mat]
            return nil
        }
        return WaterAnimator(entity, scale: scale, color: color, flow: flow)
    }

    private let entity: ModelEntity
    private var offset = SIMD2<Float>.zero
    private var accumulator: Float = 0
    private let flow: SIMD2<Float>
    /// Built once; each update only moves its texture offset (building a whole new material every update was the
    /// single biggest cost of a frame).
    private var material: PhysicallyBasedMaterial

    init(_ entity: ModelEntity, scale: SIMD2<Float> = SIMD2(28, 1.2), color: UIColor = UIColor(hex: 0x7C97E4), flow: SIMD2<Float> = SIMD2(0.012, 0.0035)) {
        self.entity = entity
        self.flow = flow
        material = Materials.water(scale: scale, color: color)
    }

    func update(dt: Float, time: Float) {
        offset += flow * dt
        accumulator += dt
        guard accumulator >= 1 / 30 else { return } // 30 updates a second is plenty for slow water
        accumulator = 0
        offset = SIMD2(offset.x.truncatingRemainder(dividingBy: 1), offset.y.truncatingRemainder(dividingBy: 1))
        material.textureCoordinateTransform.offset = offset
        entity.model?.materials = [material]
    }
}

/// Brings a person (`Vehicles.person`) to life from how it actually moves, whoever moves it: a walk cycle with legs
/// swinging from the hips, arms swinging the other way, a small rise on every step and a slight lean; standing still,
/// it settles and looks around now and then. Gestures (waving a truck back, signalling stop) play on top.
final class PersonAnimator: WorldAnimator {
    enum Gesture { case none, waveBack, stop, push }
    private let person: Vehicle
    private let rig: PersonRig
    private var last: V3?
    private var speed: Float = 0
    private var phase: Float = 0
    private var walk: Float = 0                 // 0 standing … 1 walking, eased
    private var look: Float = 0, lookTarget: Float = 0, lookTimer: Float
    private var gestureBlend: Float = 0
    var gesture: Gesture = .none
    /// Walking speed (m/s) at which the stride is fully developed.
    private let stride: Float = 1.35            // metres per full stride (two steps), world units

    init(_ person: Vehicle, seed: Float = 0) {
        self.person = person
        rig = person.rig ?? PersonRig(legL: Entity(), legR: Entity(), armL: Entity(), armR: Entity(), head: Entity())
        lookTimer = 2 + seed.truncatingRemainder(dividingBy: 3)
        phase = seed
    }

    func update(dt: Float, time: Float) {
        guard person.root.isEnabledInHierarchy else { last = nil; return }
        let p = person.root.position(relativeTo: nil)
        let moved = last.map { simd_length(SIMD2($0.x - p.x, $0.z - p.z)) } ?? 0
        last = p
        speed = damp(speed, moved / max(dt, 0.0001), sharpness: 10, dt: dt)
        walk = settle(walk, clamp01(speed / 1.0), sharpness: 6, dt: dt, within: 0.002)
        phase += moved / stride * 2 * .pi
        let g = gesture == .none ? Float(0) : 1
        gestureBlend = settle(gestureBlend, g, sharpness: 5, dt: dt, within: 0.002)

        // Standing still: now and then look somewhere else
        lookTimer -= dt
        if lookTimer <= 0 {
            lookTimer = Float.random(in: 2.5...6)
            lookTarget = walk > 0.3 ? 0 : Float.random(in: -0.75...0.75)
        }
        look = settle(look, walk > 0.3 ? 0 : lookTarget, sharpness: 3, dt: dt, within: 0.002)

        guard walk > 0 || gestureBlend > 0 || look != shownLook else { return } // a person at rest isn't rewritten
        shownLook = look
        let swing = sin(phase) * walk
        // Legs and arms swing about the z axis (the person faces +X): + swings forward
        var armL = -swing * 0.34, armR = swing * 0.34
        if gestureBlend > 0 {
            // Both arms raised in front, beckoning (waving back) or held out sideways (stop)
            let beat = sin(time * 2 * .pi * 1.4)
            let up: (Float, Float) = switch gesture {
            case .stop: (1.25, 1.25)
            case .push: (1.05, 1.05)          // both hands forward on a handle (pushing a cage)
            default: (1.45 + beat * 0.32, 1.45 + beat * 0.32)
            }
            armL = lerp(armL, up.0, gestureBlend)
            armR = lerp(armR, up.1, gestureBlend)
        }
        rig.legL.orientation = simd_quatf(angle: swing * 0.44, axis: [0, 0, 1])
        rig.legR.orientation = simd_quatf(angle: -swing * 0.44, axis: [0, 0, 1])
        let spread: Float = gesture == .stop ? gestureBlend * 1.2 : 0.06   // arms hang a little away from the body
        rig.armL.orientation = simd_quatf(angle: -spread, axis: [1, 0, 0]) * simd_quatf(angle: armL, axis: [0, 0, 1])
        rig.armR.orientation = simd_quatf(angle: spread, axis: [1, 0, 0]) * simd_quatf(angle: armR, axis: [0, 0, 1])
        rig.head.orientation = simd_quatf(angle: look, axis: [0, 1, 0])
        // Body: highest as the legs pass, a little twist and forward lean while walking
        person.body.position = [0, abs(cos(phase)) * 0.03 * walk, 0]
        person.body.orientation = simd_quatf(angle: sin(phase) * 0.07 * walk, axis: [0, 1, 0]) * simd_quatf(angle: -0.06 * walk, axis: [0, 0, 1])
    }
    private var shownLook: Float = .nan
}

/// Map pins: a gentle up-and-down float, always turned to face the camera.
final class PinAnimator: WorldAnimator {
    private let entity: Entity
    private let camera: Entity
    private let base: V3
    private let phase: Float

    init(_ entity: Entity, camera: Entity, phase: Float) {
        self.entity = entity
        self.camera = camera
        self.base = entity.position
        self.phase = phase
    }

    func update(dt: Float, time: Float) {
        let t = time + phase
        entity.position = base + [0, sin(t * 2 * .pi / 2.4) * 0.3, 0]
        let toCamera = camera.position(relativeTo: nil) - entity.position(relativeTo: nil)
        entity.orientation = simd_quatf(angle: atan2(toCamera.x, toCamera.z), axis: [0, 1, 0])
    }
}

/// Expanding, fading ring on the ground (the "live" marker under pins).
final class PulseAnimator: WorldAnimator {
    private let entity: ModelEntity
    private let phase: Float

    init(_ entity: ModelEntity, phase: Float) {
        self.entity = entity
        self.phase = phase
    }

    func update(dt: Float, time: Float) {
        let u = ((time + phase) / 2.2).truncatingRemainder(dividingBy: 1)
        let scale = 0.6 + smootherstep(u) * 1.4
        entity.scale = [scale, 1, scale]
        entity.components.set(OpacityComponent(opacity: 1 - u))
    }
}
