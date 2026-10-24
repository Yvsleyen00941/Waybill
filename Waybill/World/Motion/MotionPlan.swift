import RealityKit
import simd

/// A drive along a path with a believable speed plan: pull away gently, keep to the speed limit
/// (slow in the yard, faster on the road), brake to a stop.
///
/// The position at time `t` is a pure function, so vehicles whose timing comes from the game
/// (a truck that must be back at the dock exactly when the economy says so) can be placed exactly.
struct MotionPlan {
    let path: DrivePath
    let reverse: Bool
    let from: Float
    let to: Float
    private var times: [Float] = []        // time at each sample (every `step` metres)
    private let step: Float
    /// Playback stretch: 1 = as planned, 0.5 = twice as fast.
    var timeScale: Float = 1

    var length: Float { to - from }
    var plannedDuration: Float { times.last ?? 0 }
    var duration: Float { plannedDuration * timeScale }
    var startPosition: V3 { path.sample(from).position }
    var endPosition: V3 { path.sample(to).position }

    /// - limit: speed limit (m/s) at a point on the ground.
    /// - lateral: if set, also slow down for the bends, keeping the sideways acceleration below this (m/s²).
    init(_ path: DrivePath, from: Float = 0, to: Float? = nil, reverse: Bool = false,
         limit: (V3) -> Float, startSpeed: Float = 0, endSpeed: Float = 0, accel: Float = 2.2, lateral: Float? = nil) {
        self.path = path
        self.reverse = reverse
        self.from = from
        self.to = to ?? path.length
        let length = max(self.to - from, 0.01)
        let count = max(Int(length / 0.5), 2)
        step = length / Float(count)
        // Speed at each sample: the limit, then smoothed so acceleration and braking stay within `accel`
        var v = (0...count).map { i in limit(path.sample(from + Float(i) * step).position) }
        if let lateral {
            // Curvature from the change of heading over ±1 m
            for i in 0...count {
                let d = from + Float(i) * step
                let a = path.sample(max(d - 1, 0)).tangent, b = path.sample(min(d + 1, path.length)).tangent
                let turn = acos(min(max(simd_dot(a, b), -1), 1))
                let curvature = turn / 2
                if curvature > 0.002 { v[i] = min(v[i], sqrt(lateral / curvature)) }
            }
        }
        v[0] = min(v[0], startSpeed)
        v[count] = min(v[count], endSpeed)
        for i in 1...count { v[i] = min(v[i], sqrt(v[i - 1] * v[i - 1] + 2 * accel * step)) }
        for i in stride(from: count - 1, through: 0, by: -1) { v[i] = min(v[i], sqrt(v[i + 1] * v[i + 1] + 2 * accel * step)) }
        times = [0]
        for i in 0..<count {
            let average = max((v[i] + v[i + 1]) / 2, 0.15)
            times.append(times[i] + step / average)
        }
    }

    /// Distance along the path after `t` seconds (clamped to the plan).
    func distance(at t: Float) -> Float {
        let local = t / max(timeScale, 0.0001)
        guard local > 0 else { return from }
        guard local < plannedDuration else { return to }
        var lo = 0, hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] < local { lo = mid } else { hi = mid }
        }
        let u = (local - times[lo]) / max(times[hi] - times[lo], 0.0001)
        return from + (Float(lo) + u) * step
    }

    /// Seconds (as planned) until the vehicle has covered `d` metres of the path (the inverse of `distance(at:)`).
    func time(atDistance d: Float) -> Float {
        let i = (d - from) / step
        guard i > 0 else { return 0 }
        let lo = min(Int(i), times.count - 1), hi = min(lo + 1, times.count - 1)
        let u = i - Float(lo)
        return (times[lo] + (times[hi] - times[lo]) * u) * timeScale
    }

    /// Where the vehicle is and which way it faces after `t` seconds.
    func pose(at t: Float) -> (position: V3, heading: Float) {
        let (p, tangent) = path.sample(distance(at: t))
        let facing = reverse ? -tangent : tangent
        return (p, atan2(-facing.z, facing.x))
    }
}

/// Puts a vehicle at poses from motion plans and adds the life: rolling wheels, reverse lights,
/// a little nose dip when braking. Switching to a new plan never jumps the wheels.
final class PlannedMover {
    let vehicle: Vehicle
    private var lastPosition: V3?
    private var lastSpeed: Float = 0
    private var heading: Float = 0
    private var shownHeading: Float = .nan
    private(set) var speed: Float = 0

    init(_ vehicle: Vehicle) { self.vehicle = vehicle }

    /// Place the vehicle. `reverse` lights the reversing lamps and spins the wheels backwards.
    /// - exact: face exactly `target` (paths that are already smooth, where the position depends on the heading).
    func place(_ position: V3, heading target: Float, reverse: Bool, dt: Float, exact: Bool = false) {
        let moved = lastPosition.map { simd_distance($0, position) } ?? 0
        let jumped = moved > 6 // teleported (hidden → visible): don't spin or tilt
        let before = heading
        if lastPosition == nil || jumped || exact { heading = target } else {
            let delta = angleDelta(heading, target)
            heading = abs(delta) < 1e-5 ? target : heading + delta * (1 - exp(-18 * dt))
        }
        // Standing still (parked, docked, waiting) writes nothing
        if position != lastPosition { vehicle.root.position = position }
        if heading != shownHeading {
            shownHeading = heading
            vehicle.root.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
        }
        vehicle.updateTrailer(reset: lastPosition == nil || jumped)
        speed = jumped ? 0 : moved / max(dt, 0.0001)
        lastSpeed = speed
        vehicle.drive(moved: jumped ? 0 : moved, turned: jumped ? 0 : angleDelta(before, heading), reverse: reverse, dt: dt)
        vehicle.setReverseLights(reverse && moved > 0.001)
        lastPosition = position
    }

    func park(dt: Float) {
        guard let p = lastPosition else { return }
        place(p, heading: heading, reverse: false, dt: dt)
    }

    /// Forget the last position (next placement is a fresh start, e.g. after being hidden).
    func reset() { lastPosition = nil; lastSpeed = 0; shownHeading = .nan }
}
