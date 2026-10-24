import simd

// Route geometry for vehicles: the shortest way between two poses for a vehicle that can't turn tighter than a given
// radius (Dubins curves), and "turtle" routes made of straight runs and arcs. Coordinates on the ground: SIMD2(x, z)
// (x east, z south); headings are unit vectors. The yard paths are built from these, so every turn is one a real
// truck can make.

/// Shortest path between two poses (position + heading) for a vehicle that can't turn tighter than `radius`:
/// arc–straight–arc or arc–arc–arc (Dubins). Points are returned every `step` metres.
/// Coordinates: x east, z south (passed as SIMD2(x, z)); headings are unit vectors.
enum Dubins {
    static func path(from p0: SIMD2<Float>, heading h0: SIMD2<Float>, to p1: SIMD2<Float>, heading h1: SIMD2<Float>,
                     radius r: Float, step: Float = 0.5) -> [SIMD2<Float>] {
        // Work in a frame where turning "left" is +angle (atan2 on (x, z))
        let th0 = atan2(h0.y, h0.x), th1 = atan2(h1.y, h1.x)
        let d = p1 - p0
        let D = simd_length(d) / r
        let phi = atan2(d.y, d.x)
        let a = mod2pi(th0 - phi), b = mod2pi(th1 - phi)
        var best: (Float, [(Character, Float)])? = nil
        for word in ["LSL", "RSR", "LSR", "RSL", "RLR", "LRL"] {
            guard let segs = solve(word, a, b, D) else { continue }
            let total = segs.reduce(0) { $0 + $1.1 }
            if best == nil || total < best!.0 { best = (total, Array(zip(Array(word), segs.map(\.1)))) }
        }
        guard let (_, segs) = best else { return [p0, p1] }
        var out = [p0]
        var p = p0, th = th0
        for (kind, len) in segs {
            let L = len * r
            let n = max(Int(L / step), 1)
            for _ in 0..<n {
                let ds = L / Float(n)
                switch kind {
                case "S":
                    p += SIMD2(cos(th), sin(th)) * ds
                case "L":
                    let dth = ds / r
                    p += SIMD2(cos(th + dth / 2), sin(th + dth / 2)) * (2 * r * sin(dth / 2)); th += dth
                default:
                    let dth = -ds / r
                    p += SIMD2(cos(th + dth / 2), sin(th + dth / 2)) * (2 * r * sin(-dth / 2)); th += dth
                }
                out.append(p)
            }
        }
        out[out.count - 1] = p1
        return out
    }

    private static func mod2pi(_ x: Float) -> Float { let t = x.truncatingRemainder(dividingBy: 2 * .pi); return t < 0 ? t + 2 * .pi : t }

    /// Segment lengths (in radii) of one Dubins word, or nil if it doesn't exist for this pair of poses.
    private static func solve(_ w: String, _ a: Float, _ b: Float, _ d: Float) -> [(Character, Float)]? {
        let sa = sin(a), sb = sin(b), ca = cos(a), cb = cos(b), cab = cos(a - b)
        switch w {
        case "LSL":
            let p2 = 2 + d * d - 2 * cab + 2 * d * (sa - sb); guard p2 >= 0 else { return nil }
            let t = atan2(cb - ca, d + sa - sb)
            return [("L", mod2pi(-a + t)), ("S", sqrt(p2)), ("L", mod2pi(b - t))]
        case "RSR":
            let p2 = 2 + d * d - 2 * cab + 2 * d * (sb - sa); guard p2 >= 0 else { return nil }
            let t = atan2(ca - cb, d - sa + sb)
            return [("R", mod2pi(a - t)), ("S", sqrt(p2)), ("R", mod2pi(-b + t))]
        case "LSR":
            let p2 = -2 + d * d + 2 * cab + 2 * d * (sa + sb); guard p2 >= 0 else { return nil }
            let p = sqrt(p2), t = atan2(-ca - cb, d + sa + sb) - atan2(-2, p)
            return [("L", mod2pi(-a + t)), ("S", p), ("R", mod2pi(-mod2pi(b) + t))]
        case "RSL":
            let p2 = d * d - 2 + 2 * cab - 2 * d * (sa + sb); guard p2 >= 0 else { return nil }
            let p = sqrt(p2), t = atan2(ca + cb, d - sa - sb) - atan2(2, p)
            return [("R", mod2pi(a - t)), ("S", p), ("L", mod2pi(b - t))]
        case "RLR":
            let tmp = (6 - d * d + 2 * cab + 2 * d * (sa - sb)) / 8; guard abs(tmp) <= 1 else { return nil }
            let p = mod2pi(2 * .pi - acos(tmp)), t = mod2pi(a - atan2(ca - cb, d - sa + sb) + p / 2)
            return [("R", t), ("L", p), ("R", mod2pi(a - b - t + p))]
        default: // LRL
            let tmp = (6 - d * d + 2 * cab + 2 * d * (sb - sa)) / 8; guard abs(tmp) <= 1 else { return nil }
            let p = mod2pi(2 * .pi - acos(tmp)), t = mod2pi(-a - atan2(ca - cb, d + sa - sb) + p / 2)
            return [("L", t), ("R", p), ("L", mod2pi(mod2pi(b) - a - t + p))]
        }
    }
}

enum Turtle {
    enum Step { case straight(Float), arc(radius: Float, angle: Float) }

    /// From a pose, follow straight runs and arcs (angle + turns from south towards west, i.e. counter-clockwise in
    /// (x, z)). Points come every `step` metres or less.
    static func path(from start: SIMD2<Float>, heading: SIMD2<Float>, _ steps: [Step], step: Float = 0.6) -> [SIMD2<Float>] {
        var p = start, h = simd_normalize(heading)
        var out = [p]
        for st in steps {
            switch st {
            case .straight(let l):
                guard l > 0.001 else { continue }
                let n = max(Int(l / step), 1)
                for _ in 0..<n { p += h * (l / Float(n)); out.append(p) }
            case .arc(let r, let a):
                let n = max(Int(abs(a) * r / step), 2)
                let da = a / Float(n)
                for _ in 0..<n {
                    let hn = SIMD2(h.x * cos(da) - h.y * sin(da), h.x * sin(da) + h.y * cos(da))
                    p += simd_normalize(h + hn) * (2 * r * sin(abs(da) / 2))
                    h = simd_normalize(hn)
                    out.append(p)
                }
            }
        }
        return out
    }
}
