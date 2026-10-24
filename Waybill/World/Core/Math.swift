import Foundation
import RealityKit
import simd

/// Short name for a 3D point / vector (x, y, z). In RealityKit, y points up and 1 unit = 1 metre.
typealias V3 = SIMD3<Float>

/// Degrees → radians.
@inline(__always) func deg(_ degrees: Float) -> Float { degrees * .pi / 180 }

@inline(__always) func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func lerp(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
@inline(__always) func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

/// Smooth S-curve from 0 to 1 with zero speed at both ends (gentle start and stop).
@inline(__always) func smootherstep(_ x: Float) -> Float {
    let t = clamp01(x)
    return t * t * t * (t * (t * 6 - 15) + 10)
}

/// Frame-rate independent smoothing: move `current` towards `target`.
/// Higher `sharpness` = snappier. Works the same at 60 and 120 fps.
@inline(__always) func damp(_ current: Float, _ target: Float, sharpness: Float, dt: Float) -> Float {
    lerp(current, target, 1 - exp(-sharpness * dt))
}
@inline(__always) func damp(_ current: V3, _ target: V3, sharpness: Float, dt: Float) -> V3 {
    lerp(current, target, 1 - exp(-sharpness * dt))
}

/// `damp` for values that come to rest: snaps onto the target once the difference is invisible,
/// so a settled value stops changing (and the entity it drives stops being rewritten every frame).
@inline(__always) func settle(_ current: Float, _ target: Float, sharpness: Float, dt: Float, within: Float = 1e-5) -> Float {
    let v = damp(current, target, sharpness: sharpness, dt: dt)
    return abs(v - target) < within ? target : v
}

/// Shortest signed difference between two angles (radians), in -π...π.
@inline(__always) func angleDelta(_ from: Float, _ to: Float) -> Float {
    var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

/// Deterministic random numbers, so the world looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func float(_ range: ClosedRange<Float>) -> Float {
        let unit = Float(next() >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
    mutating func chance(_ p: Float) -> Bool { float(0...1) < p }
}

extension float4x4 {
    /// Build a transform from position, rotation (yaw = around up axis, pitch = around x, roll = around z) and scale.
    static func make(_ position: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, scale: V3 = V3(1, 1, 1)) -> float4x4 {
        let q = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])
        return Transform(scale: scale, rotation: q, translation: position).matrix
    }

    func transformPoint(_ p: V3) -> V3 {
        let r = self * SIMD4<Float>(p.x, p.y, p.z, 1)
        return V3(r.x, r.y, r.z)
    }

    var upperLeft3x3: float3x3 {
        float3x3(V3(columns.0.x, columns.0.y, columns.0.z),
                 V3(columns.1.x, columns.1.y, columns.1.z),
                 V3(columns.2.x, columns.2.y, columns.2.z))
    }
}

extension Entity {
    // Write a transform only when it changes. Every write marks the entity dirty, and RealityKit then redoes its
    // bounds, shadow and draw data that frame, even when the value is the same as before.
    @inline(__always) func setPosition(_ p: V3) { if position != p { position = p } }
    @inline(__always) func setOrientation(_ q: simd_quatf) { if orientation != q { orientation = q } }
    @inline(__always) func setScale(_ s: V3) { if scale != s { scale = s } }
    @inline(__always) func setEnabled(_ on: Bool) { if isEnabled != on { isEnabled = on } }
}
