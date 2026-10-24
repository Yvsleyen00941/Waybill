import simd

/// A smooth route through a few control points (Catmull-Rom curve), measured in metres.
/// Vehicles ask "where am I after driving s metres?" and get a position and direction.
struct DrivePath {
    private(set) var points: [V3] = []
    private(set) var distances: [Float] = []
    var length: Float { distances.last ?? 0 }
    var start: V3 { points.first ?? .zero }

    /// - Parameter control: the corners of the route on the ground (y is ignored and set to 0,
    ///   unless `keepHeight` is true, e.g. rails that climb onto a bridge).
    init(_ control: [V3], samplesPerSegment: Int = 14, keepHeight: Bool = false) {
        let c = keepHeight ? control : control.map { V3($0.x, 0, $0.z) }
        guard c.count >= 2 else { points = c; distances = c.map { _ in 0 }; return }
        // Extend the ends so the curve passes through the first and last point.
        let padded = [c[0] * 2 - c[1]] + c + [c[c.count - 1] * 2 - c[c.count - 2]]
        for i in 1..<(padded.count - 2) {
            let p0 = padded[i - 1], p1 = padded[i], p2 = padded[i + 1], p3 = padded[i + 2]
            for k in 0..<samplesPerSegment {
                let t = Float(k) / Float(samplesPerSegment)
                points.append(Self.catmullRom(p0, p1, p2, p3, t))
            }
        }
        points.append(c[c.count - 1])
        distances = [0]
        for i in 1..<points.count { distances.append(distances[i - 1] + simd_distance(points[i - 1], points[i])) }
    }

    private static func catmullRom(_ p0: V3, _ p1: V3, _ p2: V3, _ p3: V3, _ t: Float) -> V3 {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    /// Position and direction of travel after `s` metres along the path.
    func sample(_ s: Float) -> (position: V3, tangent: V3) {
        guard points.count >= 2 else { return (points.first ?? .zero, V3(1, 0, 0)) }
        let s = min(max(s, 0), length)
        // Binary search for the segment containing s
        var lo = 0, hi = distances.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if distances[mid] < s { lo = mid } else { hi = mid }
        }
        let segment = max(distances[hi] - distances[lo], 0.0001)
        let t = (s - distances[lo]) / segment
        let dir = points[hi] - points[lo]
        let tangent = simd_length(dir) > 0.0001 ? simd_normalize(dir) : V3(1, 0, 0)
        return (lerp(points[lo], points[hi], t), tangent)
    }
}
