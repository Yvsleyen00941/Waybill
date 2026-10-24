import RealityKit
import simd

/// Geometry copied out of a RealityKit mesh (e.g. a rounded box), ready to be stamped many times.
struct MeshTemplate {
    var positions: [V3] = []
    var normals: [V3] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    init(_ mesh: MeshResource) {
        for model in mesh.contents.models {
            for part in model.parts {
                let base = UInt32(positions.count)
                let p = part.positions.elements
                positions += p
                normals += part.normals?.elements ?? Array(repeating: V3(0, 1, 0), count: p.count)
                uvs += part.textureCoordinates?.elements ?? Array(repeating: .zero, count: p.count)
                indices += (part.triangleIndices?.elements ?? []).map { $0 + base }
            }
        }
    }

    private static var cache: [String: MeshTemplate] = [:]

    /// Templates are cached: the first call builds the mesh, later calls reuse it.
    static func cached(_ key: String, _ make: () -> MeshResource) -> MeshTemplate {
        if let t = cache[key] { return t }
        let t = MeshTemplate(make())
        cache[key] = t
        return t
    }
}

/// Collects many small shapes into ONE mesh, so the GPU can draw them all in a single call.
/// This is the main trick that keeps a detailed world smooth.
struct MeshBuilder {
    private(set) var positions: [V3] = []
    private(set) var normals: [V3] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var vertexCount: Int { positions.count }

    /// RealityKit's triangle winding, detected once from one of its own meshes,
    /// so hand-made faces always point the right way.
    private static let counterClockwiseIsFront: Bool = {
        let t = MeshTemplate(MeshResource.generateBox(size: 1))
        guard t.indices.count >= 3 else { return true }
        let a = t.positions[Int(t.indices[0])], b = t.positions[Int(t.indices[1])], c = t.positions[Int(t.indices[2])]
        let n = t.normals[Int(t.indices[0])]
        return simd_dot(simd_cross(b - a, c - a), n) > 0
    }()

    // MARK: Stamping templates

    mutating func add(_ template: MeshTemplate, _ transform: float4x4) {
        let base = UInt32(positions.count)
        let normalMatrix = transform.upperLeft3x3.inverse.transpose
        let mirrored = transform.upperLeft3x3.determinant < 0
        positions.reserveCapacity(positions.count + template.positions.count)
        for p in template.positions { positions.append(transform.transformPoint(p)) }
        for n in template.normals { normals.append(simd_normalize(normalMatrix * n)) }
        uvs += template.uvs
        var i = 0
        while i + 2 < template.indices.count {
            let a = template.indices[i] + base, b = template.indices[i + 1] + base, c = template.indices[i + 2] + base
            indices += mirrored ? [a, c, b] : [a, b, c]
            i += 3
        }
    }

    // MARK: Hand-made faces

    /// A flat four-sided face. Corner order doesn't matter: winding is fixed using `normal`.
    mutating func addQuad(_ p0: V3, _ p1: V3, _ p2: V3, _ p3: V3, normal: V3) {
        let base = UInt32(positions.count)
        positions += [p0, p1, p2, p3]
        normals += Array(repeating: simd_normalize(normal), count: 4)
        uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let ccw = simd_dot(simd_cross(p1 - p0, p2 - p0), normal) > 0
        let front = ccw == Self.counterClockwiseIsFront
        indices += front ? [base, base + 1, base + 2, base, base + 2, base + 3]
                         : [base, base + 2, base + 1, base, base + 3, base + 2]
    }

    mutating func addTriangle(_ p0: V3, _ p1: V3, _ p2: V3, normal: V3) {
        let base = UInt32(positions.count)
        positions += [p0, p1, p2]
        normals += Array(repeating: simd_normalize(normal), count: 3)
        uvs += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)]
        let ccw = simd_dot(simd_cross(p1 - p0, p2 - p0), normal) > 0
        let front = ccw == Self.counterClockwiseIsFront
        indices += front ? [base, base + 1, base + 2] : [base, base + 2, base + 1]
    }

    /// A sharp-edged box (cheap: 24 vertices). Use rounded templates for "hero" objects.
    mutating func addBox(_ size: V3, _ transform: float4x4) {
        let h = size / 2
        let c: [V3] = [
            V3(-h.x, -h.y, -h.z), V3(h.x, -h.y, -h.z), V3(h.x, h.y, -h.z), V3(-h.x, h.y, -h.z),
            V3(-h.x, -h.y, h.z), V3(h.x, -h.y, h.z), V3(h.x, h.y, h.z), V3(-h.x, h.y, h.z),
        ].map { transform.transformPoint($0) }
        let m = transform.upperLeft3x3.inverse.transpose
        func n(_ v: V3) -> V3 { simd_normalize(m * v) }
        addQuad(c[4], c[5], c[6], c[7], normal: n([0, 0, 1]))   // front
        addQuad(c[1], c[0], c[3], c[2], normal: n([0, 0, -1]))  // back
        addQuad(c[5], c[1], c[2], c[6], normal: n([1, 0, 0]))   // right
        addQuad(c[0], c[4], c[7], c[3], normal: n([-1, 0, 0]))  // left
        addQuad(c[7], c[6], c[2], c[3], normal: n([0, 1, 0]))   // top
        addQuad(c[0], c[1], c[5], c[4], normal: n([0, -1, 0]))  // bottom
    }

    /// A gable: triangular cross-section (width × rise) extruded along z (length). Base sits at y = 0.
    mutating func addGable(width: Float, rise: Float, length: Float, _ transform: float4x4) {
        let w = width / 2, l = length / 2
        let a0 = transform.transformPoint([-w, 0, l]), b0 = transform.transformPoint([w, 0, l]), c0 = transform.transformPoint([0, rise, l])
        let a1 = transform.transformPoint([-w, 0, -l]), b1 = transform.transformPoint([w, 0, -l]), c1 = transform.transformPoint([0, rise, -l])
        let m = transform.upperLeft3x3.inverse.transpose
        func n(_ v: V3) -> V3 { simd_normalize(m * v) }
        addTriangle(a0, b0, c0, normal: n([0, 0, 1]))
        addTriangle(b1, a1, c1, normal: n([0, 0, -1]))
        addQuad(a1, a0, c0, c1, normal: n([-rise, w, 0]))
        addQuad(b0, b1, c1, c0, normal: n([rise, w, 0]))
    }

    // MARK: Low-poly primitives (much lighter than RealityKit's generators)

    /// Rounded box. `segments` = steps per rounded edge (1 is already soft thanks to smooth normals).
    /// Each face is a small grid; points near edges are pushed onto a quarter circle.
    mutating func addRoundedBox(_ size: V3, radius: Float, segments: Int = 1, _ transform: float4x4) {
        let h = size / 2
        let r = min(radius, min(h.x, min(h.y, h.z)) * 0.999)
        let inner = h - V3(repeating: r)
        let n = max(segments, 1)
        // Grid positions along one axis: n+1 steps across each rounded edge
        func axis(_ half: Float, _ inner: Float) -> [Float] {
            var a: [Float] = []
            for k in 0...n { a.append(-half + (half - inner) * Float(k) / Float(n)) }
            for k in 0...n { a.append(inner + (half - inner) * Float(k) / Float(n)) }
            return a
        }
        let ax = axis(h.x, inner.x), ay = axis(h.y, inner.y), az = axis(h.z, inner.z)
        let normalMatrix = transform.upperLeft3x3.inverse.transpose

        // Each face: (normal axis, sign, u axis, v axis)
        let faces: [(Int, Float, Int, Int)] = [(0, 1, 2, 1), (0, -1, 1, 2), (1, 1, 0, 2), (1, -1, 2, 0), (2, 1, 1, 0), (2, -1, 0, 1)]
        let grids = [ax, ay, az]
        let halves = [h.x, h.y, h.z]
        for (nAxis, sign, uAxis, vAxis) in faces {
            let us = grids[uAxis], vs = grids[vAxis]
            let base = UInt32(positions.count)
            for v in vs {
                for u in us {
                    var p = V3.zero
                    p[nAxis] = halves[nAxis] * sign
                    p[uAxis] = u
                    p[vAxis] = v
                    let c = simd_clamp(p, -inner, inner)
                    let dir = simd_normalize(p - c)
                    let local = c + dir * r
                    positions.append(transform.transformPoint(local))
                    normals.append(simd_normalize(normalMatrix * dir))
                    uvs.append(SIMD2((u + halves[uAxis]) / (2 * halves[uAxis]), (v + halves[vAxis]) / (2 * halves[vAxis])))
                }
            }
            let w = UInt32(us.count)
            // Winding: check the first triangle against the face normal once, then apply to all
            var faceNormal = V3.zero
            faceNormal[nAxis] = sign
            let a = positions[Int(base)], b = positions[Int(base + 1)], c = positions[Int(base + w)]
            let ccw = simd_dot(simd_cross(b - a, c - a), normalMatrix * faceNormal) > 0
            let front = ccw == Self.counterClockwiseIsFront
            for j in 0..<(UInt32(vs.count) - 1) {
                for i in 0..<(w - 1) {
                    let i0 = base + j * w + i, i1 = i0 + 1, i2 = i0 + w, i3 = i2 + 1
                    indices += front ? [i0, i1, i2, i1, i3, i2] : [i0, i2, i1, i1, i2, i3]
                }
            }
        }
    }

    /// Smooth UV sphere with few polygons.
    mutating func addSphere(radius: Float, segments: Int = 16, rings: Int = 10, _ transform: float4x4) {
        let base = UInt32(positions.count)
        let normalMatrix = transform.upperLeft3x3.inverse.transpose
        for ring in 0...rings {
            let phi = Float.pi * Float(ring) / Float(rings)
            for seg in 0...segments {
                let theta = 2 * Float.pi * Float(seg) / Float(segments)
                let n = V3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                positions.append(transform.transformPoint(n * radius))
                normals.append(simd_normalize(normalMatrix * n))
                uvs.append(SIMD2(Float(seg) / Float(segments), Float(ring) / Float(rings)))
            }
        }
        addGridIndices(base: base, columns: segments + 1, rows: rings + 1, outwardCheck: true)
    }

    /// Cylinder standing on its axis (y), centred at the origin, with caps.
    mutating func addCylinder(radius: Float, height: Float, segments: Int = 14, _ transform: float4x4) {
        addCone(bottomRadius: radius, topRadius: radius, height: height, segments: segments, transform)
    }

    /// Cone / truncated cone along y, centred at the origin. `topRadius` 0 = pointed (pointing up).
    mutating func addCone(bottomRadius: Float, topRadius: Float, height: Float, segments: Int = 14, _ transform: float4x4) {
        let normalMatrix = transform.upperLeft3x3.inverse.transpose
        let hh = height / 2
        let slope = (bottomRadius - topRadius) / height
        // Side
        let base = UInt32(positions.count)
        for row in 0...1 {
            let y = row == 0 ? -hh : hh
            let r = row == 0 ? bottomRadius : topRadius
            for seg in 0...segments {
                let theta = 2 * Float.pi * Float(seg) / Float(segments)
                let dir = V3(cos(theta), 0, sin(theta))
                positions.append(transform.transformPoint(dir * r + V3(0, y, 0)))
                normals.append(simd_normalize(normalMatrix * simd_normalize(dir + V3(0, slope, 0))))
                uvs.append(SIMD2(Float(seg) / Float(segments), Float(row)))
            }
        }
        addGridIndices(base: base, columns: segments + 1, rows: 2, outwardCheck: true)
        // Caps
        for (y, r, up) in [(-hh, bottomRadius, Float(-1)), (hh, topRadius, Float(1))] where r > 0.0001 {
            let center = transform.transformPoint([0, y, 0])
            let n = simd_normalize(normalMatrix * V3(0, up, 0))
            for seg in 0..<segments {
                let t0 = 2 * Float.pi * Float(seg) / Float(segments)
                let t1 = 2 * Float.pi * Float(seg + 1) / Float(segments)
                addTriangle(center, transform.transformPoint([cos(t0) * r, y, sin(t0) * r]),
                            transform.transformPoint([cos(t1) * r, y, sin(t1) * r]), normal: n)
            }
        }
    }

    /// A flat shape (convex outline in x/z, e.g. a ship hull seen from above) extruded from `y0` to `y1`.
    mutating func addPrism(outline: [SIMD2<Float>], y0: Float, y1: Float, _ transform: float4x4) {
        guard outline.count >= 3 else { return }
        let m = transform.upperLeft3x3.inverse.transpose
        func n(_ v: V3) -> V3 { simd_normalize(m * v) }
        func p(_ q: SIMD2<Float>, _ y: Float) -> V3 { transform.transformPoint([q.x, y, q.y]) }
        let centre = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
        for i in 0..<outline.count {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let edge = b - a
            var outward = V3(edge.y, 0, -edge.x)
            let mid = (a + b) / 2 - centre
            if simd_dot(SIMD2(outward.x, outward.z), mid) < 0 { outward = -outward }
            addQuad(p(a, y0), p(b, y0), p(b, y1), p(a, y1), normal: n(outward))
            addTriangle(p(centre, y1), p(a, y1), p(b, y1), normal: n([0, 1, 0]))
            addTriangle(p(centre, y0), p(b, y0), p(a, y0), normal: n([0, -1, 0]))
        }
    }

    /// Triangles for a grid of vertices (rows × columns), winding chosen so faces point outward.
    private mutating func addGridIndices(base: UInt32, columns: Int, rows: Int, outwardCheck: Bool) {
        let w = UInt32(columns)
        for j in 0..<UInt32(rows - 1) {
            for i in 0..<(w - 1) {
                let i0 = base + j * w + i, i1 = i0 + 1, i2 = i0 + w, i3 = i2 + 1
                // Decide per quad using the vertex normal (robust at poles and for any transform)
                let a = positions[Int(i0)], b = positions[Int(i1)], c = positions[Int(i2)], d = positions[Int(i3)]
                let n = normals[Int(i0)] + normals[Int(i3)]
                let cross = simd_cross(b - a, c - a) + simd_cross(d - b, c - b) // both triangles (a,b,c) and (b,d,c)
                let ccw = simd_dot(cross, n) > 0
                let front = ccw == Self.counterClockwiseIsFront
                indices += front ? [i0, i1, i2, i1, i3, i2] : [i0, i2, i1, i1, i2, i3]
            }
        }
    }

    /// A turned shape (like on a lathe): `profile` points are (radius, height), revolved around the y axis.
    /// Normals follow the profile, so curves come out smooth; repeat a point to get a crisp edge there.
    /// Used for tyres, rims, tanks, lamp heads, trees and rocket bodies.
    mutating func addLathe(_ profile: [SIMD2<Float>], segments: Int = 32, _ transform: float4x4) {
        guard profile.count >= 2 else { return }
        let normalMatrix = transform.upperLeft3x3.inverse.transpose
        func outward(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float>? {
            let t = b - a
            return simd_length(t) > 1e-6 ? simd_normalize(SIMD2(t.y, -t.x)) : nil
        }
        // Normals per profile point: average of the segments on either side (a zero-length segment splits them)
        var profileNormals: [SIMD2<Float>] = []
        for i in 0..<profile.count {
            var n = SIMD2<Float>.zero
            if i > 0, let before = outward(profile[i - 1], profile[i]) { n += before }
            if i < profile.count - 1, let after = outward(profile[i], profile[i + 1]) { n += after }
            profileNormals.append(simd_length(n) > 1e-6 ? simd_normalize(n) : SIMD2(0, 1))
        }
        // Total profile length for v texture coordinates
        var lengths: [Float] = [0]
        for i in 1..<profile.count { lengths.append(lengths[i - 1] + simd_length(profile[i] - profile[i - 1])) }
        let total = max(lengths.last ?? 1, 1e-6)
        let base = UInt32(positions.count)
        for (i, q) in profile.enumerated() {
            let pn = profileNormals[i]
            for seg in 0...segments {
                let theta = 2 * Float.pi * Float(seg) / Float(segments)
                let c = cos(theta), s = sin(theta)
                positions.append(transform.transformPoint(V3(q.x * c, q.y, q.x * s)))
                normals.append(simd_normalize(normalMatrix * V3(pn.x * c, pn.y, pn.x * s)))
                uvs.append(SIMD2(Float(seg) / Float(segments), lengths[i] / total))
            }
        }
        addGridIndices(base: base, columns: segments + 1, rows: profile.count, outwardCheck: true)
    }

    /// Append another builder's geometry.
    mutating func append(_ other: MeshBuilder) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += other.uvs
        indices += other.indices.map { $0 + base }
    }

    /// Append another builder's geometry with every texture coordinate set to `uv` (its material's patch in the
    /// `MaterialPalette`).
    mutating func append(_ other: MeshBuilder, uv: SIMD2<Float>) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        uvs += Array(repeating: uv, count: other.positions.count)
        indices += other.indices.map { $0 + base }
    }

    func descriptor(name: String) -> MeshDescriptor {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(indices)
        return d
    }

    func makeMesh(name: String = "merged") throws -> MeshResource {
        try MeshResource.generate(from: [descriptor(name: name)])
    }
}
