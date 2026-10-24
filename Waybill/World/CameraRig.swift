import simd

/// Where the camera rests in a region, and how far you may pan.
struct CameraHome {
    var target: V3
    var yaw: Float
    var distance: Float
    var boundsMin = SIMD2<Float>(-70, -45)
    var boundsMax = SIMD2<Float>(70, 70)
}

/// The game camera, described as "look at `target` from `distance` metres, rotated by `yaw`".
///
/// Each value has a *goal* (where your fingers want it) and a *current* value that glides
/// towards the goal every frame. That glide is what makes the camera feel smooth and expensive.
struct CameraRig {
    // Current (what's on screen)
    private(set) var target = V3(2, 0, 14)
    private(set) var yaw: Float = deg(34)
    private(set) var distance: Float = 120

    // Goals (what gestures and buttons change)
    var goalTarget = V3(2, 0, 14)
    var goalYaw: Float = deg(34)
    var goalDistance: Float = 120

    /// Momentum after a flick, in metres per second (ground plane).
    var velocity = SIMD2<Float>.zero
    var isDragging = false
    /// 1 = normal glide speed. Lower = slower, cinematic moves (the intro fly-in); recovers by itself.
    var glide: Float = 1

    var minDistance: Float = 38
    var maxDistance: Float = 230
    let fieldOfView: Float = 26
    /// Area the camera may look at (x/z), with a soft rubber-band edge.
    var boundsMin = SIMD2<Float>(-70, -45)
    var boundsMax = SIMD2<Float>(70, 70)

    /// The default view of the current region (the house button).
    var home = CameraHome(target: V3(2, 0, 14), yaw: deg(34), distance: 120)

    /// Camera tilt: looks down more when zoomed out (map-like), less when close (cinematic).
    var elevation: Float {
        let t = clamp01((distance - minDistance) / (maxDistance - minDistance))
        return deg(lerp(30, 52, t))
    }

    var position: V3 {
        let e = elevation
        let offset = V3(sin(yaw) * cos(e), sin(e), cos(yaw) * cos(e)) * distance
        return target + offset
    }

    // MARK: Gestures

    /// Move the view by a ground-plane delta (from a pan). Resists past the edges.
    mutating func pan(by delta: V3) {
        var d = SIMD2<Float>(delta.x, delta.z)
        // Rubber band: pushing further past an edge only counts for 35 %
        if (goalTarget.x >= boundsMax.x && d.x > 0) || (goalTarget.x <= boundsMin.x && d.x < 0) { d.x *= 0.35 }
        if (goalTarget.z >= boundsMax.y && d.y > 0) || (goalTarget.z <= boundsMin.y && d.y < 0) { d.y *= 0.35 }
        goalTarget += V3(d.x, 0, d.y)
        target = goalTarget // direct manipulation: no lag while the finger is down
    }

    /// Zoom, keeping the ground point under the fingers (`anchor`) in place.
    mutating func zoom(to newDistance: Float, anchor: V3?) {
        let clampedDistance = min(max(newDistance, minDistance * 0.85), maxDistance * 1.12)
        if let anchor {
            let factor = 1 - clampedDistance / goalDistance
            goalTarget += V3(anchor.x - goalTarget.x, 0, anchor.z - goalTarget.z) * factor
        }
        goalDistance = clampedDistance
    }

    mutating func rotate(snapBy step: Float) {
        let snapped = (goalYaw / deg(45)).rounded() * deg(45)
        goalYaw = snapped + step
    }

    /// Start far out and glide slowly to the home view (used behind the intro).
    mutating func flyIn() {
        jump(target: home.target + V3(12, 0, 20), yaw: home.yaw - deg(40), distance: 228)
        goalTarget = home.target
        goalYaw = home.yaw
        goalDistance = home.distance
        glide = 0.08
    }

    /// Start a little further out and rotated, then glide back to where the camera was.
    mutating func settle() {
        distance = min(goalDistance * 1.3, maxDistance)
        yaw = goalYaw - deg(12)
        glide = 0.2
    }

    /// Jump instantly (no glide), e.g. for testing a specific view.
    mutating func jump(target: V3? = nil, yaw: Float? = nil, distance: Float? = nil) {
        if let target { self.target = target; goalTarget = target }
        if let yaw { self.yaw = yaw; goalYaw = yaw }
        if let distance { self.distance = distance; goalDistance = distance }
    }

    /// Use a region's home view and bounds.
    mutating func setHome(_ h: CameraHome) {
        home = h
        maxDistance = max(230, h.distance + 50)
        boundsMin = h.boundsMin
        boundsMax = h.boundsMax
    }

    mutating func goHome() {
        goalTarget = home.target
        goalDistance = home.distance
        // Rotate the short way round to the home angle
        goalYaw = yaw + angleDelta(yaw, home.yaw)
        velocity = .zero
    }

    // MARK: Per frame

    mutating func step(dt: Float) {
        glide = min(1, glide + dt * 0.22)
        let g = glide * glide
        if !isDragging {
            // Flick momentum, decaying smoothly
            goalTarget += V3(velocity.x, 0, velocity.y) * dt
            velocity *= exp(-4.2 * dt)
            // Spring back inside the bounds
            let inside = clampedXZ(goalTarget)
            goalTarget = damp(goalTarget, inside, sharpness: 7, dt: dt)
            // Zoom springs back from over-pinch
            let zClamped = min(max(goalDistance, minDistance), maxDistance)
            goalDistance = damp(goalDistance, zClamped, sharpness: 8, dt: dt)
            target = damp(target, goalTarget, sharpness: 12 * max(g, 0.12), dt: dt)
        }
        yaw = damp(yaw, goalYaw, sharpness: 9 * max(g, 0.12), dt: dt)
        distance = damp(distance, goalDistance, sharpness: 10 * max(g, 0.12), dt: dt)
    }

    private func clampedXZ(_ p: V3) -> V3 {
        V3(min(max(p.x, boundsMin.x), boundsMax.x), p.y, min(max(p.z, boundsMin.y), boundsMax.y))
    }
}
