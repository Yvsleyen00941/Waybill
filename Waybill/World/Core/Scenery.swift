import RealityKit
import UIKit

/// Collects all the static (non-moving) shapes of a site, grouped by material.
/// At the end, each material becomes ONE entity, so even hundreds of boxes cost only a few draw calls.
/// (The shape functions live in `ShapeCollector`, shared with `Kit`.)
final class Scenery: ShapeCollector {
    init() { super.init(edgeSteps: 2, roundSegments: 20) }

    /// Soft ground shadows are batched too (one mesh per shape kind).
    enum ShadowKind { case round, rect }
    private var shadowBuilders: [ShadowKind: MeshBuilder] = [:]

    /// A soft contact shadow lying on the ground (fake ambient occlusion).
    func groundShadow(_ kind: ShadowKind, center: V3, size: SIMD2<Float>, yaw: Float = 0) {
        let t = current * float4x4.make(center, yaw: yaw)
        let hx = size.x / 2, hz = size.y / 2
        shadowBuilders[kind, default: MeshBuilder()].addQuad(
            t.transformPoint([-hx, 0, -hz]), t.transformPoint([hx, 0, -hz]),
            t.transformPoint([hx, 0, hz]), t.transformPoint([-hx, 0, hz]), normal: [0, 1, 0])
    }

    /// Turn everything collected so far into entities under `parent`.
    func build(into parent: Entity, castsShadows: Bool = true) {
        // Plain parts share one palette material and paint another (one draw call each); glowing lenses keep their own
        var plain = MeshBuilder(), paint = MeshBuilder(), glass = false
        func add(_ builder: MeshBuilder, _ name: String, _ material: any Material) {
            guard let mesh = try? builder.makeMesh(name: name) else { return }
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "scenery.\(name)"
            if !castsShadows { entity.components.set(DynamicLightShadowComponent(castsShadow: false)) }
            parent.addChild(entity)
        }
        for mat in order {
            guard let builder = builders[mat], !builder.isEmpty else { continue }
            if !MaterialPalette.shares(mat) { add(builder, "\(mat)", Materials.pbr(mat)) }
            else if mat.isPaint { paint.append(builder, uv: MaterialPalette.uv(mat)) }
            else { plain.append(builder, uv: MaterialPalette.uv(mat)); glass = glass || MaterialPalette.isGlass(mat) }
        }
        if !plain.isEmpty { add(plain, "plain", MaterialPalette.material(paint: false, glass: glass)) }
        if !paint.isEmpty { add(paint, "paint", MaterialPalette.material(paint: true, glass: false)) }
        clearShapes()

        for (kind, builder) in shadowBuilders where !builder.isEmpty {
            guard let mesh = try? builder.makeMesh(name: "shadows") else { continue }
            let mask = kind == .round ? Textures.softDot : Textures.softRect(aspect: 1.25)
            let entity = ModelEntity(mesh: mesh, materials: [Materials.decal(mask: mask, tint: Palette.shadowTint, opacity: 0.3)])
            entity.name = "scenery.shadows"
            entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            parent.addChild(entity)
        }
        shadowBuilders.removeAll()
    }
}

/// Helpers for individual (moving or changing) entities.
enum Geo {
    private static var meshCache: [String: MeshResource] = [:]

    private static func cached(_ key: String, _ make: () -> MeshResource) -> MeshResource {
        if let m = meshCache[key] { return m }
        let m = make()
        meshCache[key] = m
        return m
    }

    private static func built(_ key: String, _ build: (inout MeshBuilder) -> Void) -> MeshResource {
        cached(key) {
            var b = MeshBuilder()
            build(&b)
            return try! b.makeMesh(name: key)
        }
    }

    /// Box for vehicles and moving parts; `radius` > 0 gives soft rounded edges (2 steps).
    static func box(_ size: V3, radius: Float = 0) -> MeshResource {
        built("box \(size) \(radius)") { b in
            if radius > 0 { b.addRoundedBox(size, radius: radius, segments: 2, matrix_identity_float4x4) }
            else { b.addBox(size, matrix_identity_float4x4) }
        }
    }
    static func cylinder(radius: Float, height: Float) -> MeshResource {
        built("cyl \(radius) \(height)") { $0.addCylinder(radius: radius, height: height, segments: 16, matrix_identity_float4x4) }
    }
    static func sphere(radius: Float) -> MeshResource {
        built("sph \(radius)") { $0.addSphere(radius: radius, segments: 18, rings: 12, matrix_identity_float4x4) }
    }
    static func prism(_ key: String, outline: [SIMD2<Float>], y0: Float, y1: Float) -> MeshResource {
        built("prism \(key)") { $0.addPrism(outline: outline, y0: y0, y1: y1, matrix_identity_float4x4) }
    }
    /// Pointed cone, tip up.
    static func cone(radius: Float, height: Float) -> MeshResource {
        built("cone \(radius) \(height)") { $0.addCone(bottomRadius: radius, topRadius: 0, height: height, segments: 16, matrix_identity_float4x4) }
    }

    /// Several upright planes (like `generatePlane(width:height:)`) placed by `transforms`, as one mesh.
    static func planes(_ key: String, width: Float, height: Float, at transforms: [float4x4]) -> MeshResource {
        built("planes \(key) \(width) \(height) \(transforms.map { $0.columns.3 })") { b in
            let plane = MeshTemplate.cached("plane \(width) \(height)") { .generatePlane(width: width, height: height) }
            for t in transforms { b.add(plane, t) }
        }
    }

    /// Add a model as a child of `parent` and return it.
    @discardableResult
    static func part(_ parent: Entity, _ mesh: MeshResource, _ material: any Material, at p: V3,
                     yaw: Float = 0, pitch: Float = 0, roll: Float = 0, scale: V3 = V3(1, 1, 1)) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.transform = Transform(matrix: .make(p, yaw: yaw, pitch: pitch, roll: roll, scale: scale))
        parent.addChild(e)
        return e
    }

    @discardableResult
    static func part(_ parent: Entity, _ mesh: MeshResource, _ mat: Mat, at p: V3,
                     yaw: Float = 0, pitch: Float = 0, roll: Float = 0, scale: V3 = V3(1, 1, 1)) -> ModelEntity {
        part(parent, mesh, Materials.pbr(mat), at: p, yaw: yaw, pitch: pitch, roll: roll, scale: scale)
    }

    /// A flat decal lying on the ground (or any surface after rotating). Never casts shadows.
    @discardableResult
    static func decal(_ parent: Entity, mask: TextureResource, tint: UIColor, opacity: Float,
                      size: SIMD2<Float>, at p: V3, yaw: Float = 0) -> ModelEntity {
        let e = ModelEntity(mesh: .generatePlane(width: size.x, depth: size.y),
                            materials: [Materials.decal(mask: mask, tint: tint, opacity: opacity)])
        e.transform = Transform(matrix: .make(p, yaw: yaw))
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
        parent.addChild(e)
        return e
    }

    /// Soft contact shadow under an object. This fakes the ambient occlusion seen in the reference.
    @discardableResult
    static func contactShadow(_ parent: Entity, size: SIMD2<Float>, at p: V3, yaw: Float = 0, opacity: Float = 0.32, round: Bool = false) -> ModelEntity {
        let mask = round ? Textures.softDot : Textures.softRect(aspect: CGFloat(size.x / size.y))
        return decal(parent, mask: mask, tint: Palette.shadowTint, opacity: opacity, size: size, at: p, yaw: yaw)
    }
}
