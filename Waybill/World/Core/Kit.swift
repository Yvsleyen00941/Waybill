import RealityKit
import simd

/// Collects shapes grouped by material, with a transform stack. Shared by `Scenery` (the static world,
/// merged per material into a few big entities) and `Kit` (one detailed object as one entity).
class ShapeCollector {
    private(set) var order: [Mat] = []
    var builders: [Mat: MeshBuilder] = [:]
    private var stack: [float4x4] = [matrix_identity_float4x4]
    var current: float4x4 { stack[stack.count - 1] }

    /// Smoothness: steps per rounded edge and segments around round parts.
    var edgeSteps: Int
    var roundSegments: Int

    init(edgeSteps: Int, roundSegments: Int) {
        self.edgeSteps = edgeSteps
        self.roundSegments = roundSegments
    }

    func add(_ m: Mat, _ body: (inout MeshBuilder) -> Void) {
        if builders[m] == nil { order.append(m); builders[m] = MeshBuilder() }
        body(&builders[m]!)
    }

    func clearShapes() {
        builders.removeAll()
        order.removeAll()
    }

    /// Total vertices collected (for performance checks).
    var vertexCount: Int { builders.values.reduce(0) { $0 + $1.vertexCount } }

    /// Parts added inside are moved/rotated/scaled together.
    func group(_ transform: float4x4, _ body: () -> Void) {
        stack.append(current * transform)
        body()
        stack.removeLast()
    }

    func group(at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, scale: V3 = V3(1, 1, 1), _ body: () -> Void) {
        group(.make(p, yaw: yaw, pitch: pitch, roll: roll, scale: scale), body)
    }

    // MARK: Shapes

    /// Box; `r` > 0 rounds the edges.
    func box(_ m: Mat, _ size: V3, r: Float = 0, at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0) {
        let t = current * .make(p, yaw: yaw, pitch: pitch, roll: roll)
        let steps = edgeSteps
        add(m) { b in
            if r > 0 { b.addRoundedBox(size, radius: r, segments: steps, t) } else { b.addBox(size, t) }
        }
    }

    func rounded(_ m: Mat, _ size: V3, radius: Float, at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0) {
        box(m, size, r: radius, at: p, yaw: yaw, pitch: pitch, roll: roll)
    }

    /// Cylinder along y (use `pitch: .pi / 2` for an axle along z, `roll: .pi / 2` for one along x).
    func cylinder(_ m: Mat, radius: Float, height: Float, at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, segments: Int? = nil) {
        let t = current * .make(p, yaw: yaw, pitch: pitch, roll: roll)
        let n = segments ?? roundSegments
        add(m) { $0.addCylinder(radius: radius, height: height, segments: n, t) }
    }

    /// Cylinder with softly rounded rims, along y.
    func roundedCylinder(_ m: Mat, radius: Float, height: Float, r: Float, at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0) {
        let h = height / 2, e = min(r, radius * 0.9, h * 0.9)
        var profile: [SIMD2<Float>] = [SIMD2(0, -h)]
        for k in 0...3 { let a = Float(k) / 3 * .pi / 2; profile.append(SIMD2(radius - e + sin(a) * e, -h + e - cos(a) * e)) }
        for k in 0...3 { let a = Float(k) / 3 * .pi / 2; profile.append(SIMD2(radius - e + cos(a) * e, h - e + sin(a) * e)) }
        profile.append(SIMD2(0, h))
        lathe(m, profile, at: p, yaw: yaw, pitch: pitch, roll: roll)
    }

    /// Pointed cone, tip up.
    func cone(_ m: Mat, radius: Float, height: Float, at p: V3) {
        cone(m, bottom: radius, top: 0, height: height, at: p)
    }

    func cone(_ m: Mat, bottom: Float, top: Float, height: Float, at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0) {
        let t = current * .make(p, yaw: yaw, pitch: pitch, roll: roll)
        let n = roundSegments
        add(m) { $0.addCone(bottomRadius: bottom, topRadius: top, height: height, segments: n, t) }
    }

    func sphere(_ m: Mat, radius: Float, at p: V3, scale: V3 = V3(1, 1, 1), yaw: Float = 0, pitch: Float = 0, roll: Float = 0, segments: Int? = nil) {
        let t = current * .make(p, yaw: yaw, pitch: pitch, roll: roll, scale: scale)
        let n = segments ?? roundSegments
        add(m) { $0.addSphere(radius: radius, segments: n, rings: max(n / 2, 8), t) }
    }

    /// Revolved profile of (radius, height) points around y.
    func lathe(_ m: Mat, _ profile: [SIMD2<Float>], at p: V3, yaw: Float = 0, pitch: Float = 0, roll: Float = 0,
               scale: V3 = V3(1, 1, 1), segments: Int? = nil) {
        let t = current * .make(p, yaw: yaw, pitch: pitch, roll: roll, scale: scale)
        let n = segments ?? roundSegments
        add(m) { $0.addLathe(profile, segments: n, t) }
    }

    /// Flat outline (x/z, convex) extruded from y0 to y1.
    func prism(_ m: Mat, outline: [SIMD2<Float>], y0: Float, y1: Float, at p: V3 = .zero, yaw: Float = 0, pitch: Float = 0, roll: Float = 0) {
        let t = current * .make(p, yaw: yaw, pitch: pitch, roll: roll)
        add(m) { $0.addPrism(outline: outline, y0: y0, y1: y1, t) }
    }

    /// A side profile (x/y outline, convex, e.g. a cab with a sloped windscreen) extruded across z.
    func extrude(_ m: Mat, side outline: [SIMD2<Float>], width: Float, at p: V3, yaw: Float = 0) {
        let t = current * .make(p, yaw: yaw) * .make(.zero, pitch: .pi / 2)
        add(m) { $0.addPrism(outline: outline.map { SIMD2($0.x, -$0.y) }, y0: -width / 2, y1: width / 2, t) }
    }

    func gable(_ m: Mat, width: Float, rise: Float, length: Float, at p: V3, yaw: Float = 0) {
        let t = current * .make(p, yaw: yaw)
        add(m) { $0.addGable(width: width, rise: rise, length: length, t) }
    }
}

/// Builds one detailed object (a truck body, a wheel, a forklift…) as a single entity.
///
/// Every part is merged per material into one mesh with a material slot per material. A truck made of
/// 150 parts is still one entity with a handful of draw calls, so detail costs vertices (cheap on the GPU)
/// instead of entities (expensive on the main thread). Built meshes are cached by key, so a fleet of
/// identical trucks shares one mesh.
final class Kit: ShapeCollector {
    init() { super.init(edgeSteps: 3, roundSegments: 28) }

    // MARK: Output

    var isEmpty: Bool { order.isEmpty }

    struct Model {
        let mesh: MeshResource
        let materials: [any Material]
        let slots: [Mat?]         // which Mat each material slot is (nil: the shared palette slots)
    }

    /// One mesh with as few material slots as possible: all plain parts share one palette material, all glossy paint
    /// another (`MaterialPalette`); glowing lenses and the materials in `separate` (parts that get repainted) keep
    /// their own slot.
    func makeModel(name: String, separate: Set<Mat> = []) -> Model? {
        var descriptors: [MeshDescriptor] = []
        var materials: [any Material] = []
        var slots: [Mat?] = []
        func addSlot(_ b: MeshBuilder, _ label: String, _ material: any Material, _ slot: Mat?) {
            var d = b.descriptor(name: "\(name).\(label)")
            d.materials = .allFaces(UInt32(materials.count))
            descriptors.append(d)
            materials.append(material)
            slots.append(slot)
        }
        var plain = MeshBuilder(), paint = MeshBuilder(), glass = false
        for m in order {
            guard let b = builders[m], !b.isEmpty else { continue }
            if separate.contains(m) || !MaterialPalette.shares(m) {
                addSlot(b, "\(m)", Materials.pbr(m), m)
            } else if m.isPaint {
                paint.append(b, uv: MaterialPalette.uv(m))
            } else {
                plain.append(b, uv: MaterialPalette.uv(m))
                glass = glass || MaterialPalette.isGlass(m)
            }
        }
        if !plain.isEmpty { addSlot(plain, "plain", MaterialPalette.material(paint: false, glass: glass), nil) }
        if !paint.isEmpty { addSlot(paint, "paint", MaterialPalette.material(paint: true, glass: false), nil) }
        guard !descriptors.isEmpty, let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
        return Model(mesh: mesh, materials: materials, slots: slots)
    }

    private static var cache: [String: Model] = [:]

    /// Build (or reuse) a model under `key` and return it as a new entity.
    /// - separate: materials that keep their own slot, so `slots(of:key:)` can repaint them.
    static func entity(_ key: String, castsShadow: Bool = true, separate: Set<Mat> = [], _ build: (Kit) -> Void) -> ModelEntity {
        let model: Model
        if let cached = cache[key] {
            model = cached
        } else {
            let kit = Kit()
            build(kit)
            model = kit.makeModel(name: key, separate: separate) ?? Model(mesh: .generateBox(size: 0.01), materials: [Materials.pbr(.white)], slots: [.white])
            cache[key] = model
        }
        let e = ModelEntity(mesh: model.mesh, materials: model.materials)
        e.name = key
        if !castsShadow { e.components.set(DynamicLightShadowComponent(castsShadow: false)) }
        return e
    }

    /// Material slots of a model built under `key` that use `m` (to repaint those parts later).
    static func slots(of m: Mat, key: String) -> [Int] {
        cache[key]?.slots.enumerated().compactMap { $0.element == m ? $0.offset : nil } ?? []
    }
}
