import Metal
import RealityKit
import UIKit

/// Every surface type in the world. One material per case, shared by all objects that use it.
enum Mat: Hashable, CaseIterable {
    case brand, brandLit, brandShade, brandDeep, roofRib
    case white, concrete, yard, ground, road, curb, grass, marking, markingWhite
    case foliage, foliageDark, trunk
    case cardboard, cardboardLight, cardboardDark, tape, pallet
    case interior, metal, darkMetal, glass, tire, forklift, hiVis, skin, container, containerRib
    case rivalTeal, rivalNavy
    case carSlate, carMint, carSand, carCoral, fence, skylight, stone, bark, conifer, hull
    case solar, belt, mint, insulated
    case crate, crateDark, sand, sandDark, snow, rock, rockDark, water, asphalt, glassTower, steel, concreteDark
    // Vehicle finishes: glossy clear-coated paint, chrome, rubber, tinted glass, light lenses, trim
    case paintBrand, paintWhite, paintTeal, paintNavy, paintYellow, paintSlate, paintMint, paintSand, paintCoral
    case chrome, aluminium, rubber, glassDark, lensWhite, lensAmber, lensRed, trim, seat, rubberSeal, hazard
    case foliageLight, label, plinth, gutter, lightBar

    var color: UIColor {
        switch self {
        case .brand: Palette.brand
        case .brandLit: Palette.brandLit
        case .brandShade: Palette.brandShade
        case .brandDeep: Palette.brandDeep
        case .roofRib: Palette.brandLit.mixed(with: .white, 0.24)
        case .white: Palette.white
        case .concrete: Palette.concrete
        case .yard: Palette.yard
        case .ground: Palette.ground
        case .road: Palette.road
        case .curb: Palette.curb
        case .grass: Palette.grass
        case .marking: Palette.marking
        case .markingWhite: Palette.markingWhite
        case .foliage: Palette.foliage
        case .foliageDark: Palette.foliageDark
        case .trunk: Palette.trunk
        case .cardboard: Palette.cardboard
        case .cardboardLight: Palette.cardboardLight
        case .cardboardDark: Palette.cardboardDark
        case .tape: Palette.tape
        case .pallet: Palette.pallet
        case .interior: Palette.interior
        case .metal: Palette.metal
        case .darkMetal: Palette.darkMetal
        case .glass: Palette.glass
        case .tire: Palette.tire
        case .forklift: Palette.forklift
        case .hiVis: Palette.hiVis
        case .skin: Palette.skin
        case .container: Palette.container
        case .containerRib: Palette.container.mixed(with: .black, 0.12)
        case .rivalTeal: Palette.rivalTeal
        case .rivalNavy: Palette.rivalNavy
        case .carSlate: UIColor(hex: 0x5B6382)
        case .carMint: UIColor(hex: 0x9BCDB7)
        case .carSand: UIColor(hex: 0xE5D1B2)
        case .carCoral: UIColor(hex: 0xE69C8B)
        case .fence: UIColor(hex: 0xA9AED3)
        case .skylight: UIColor(hex: 0xA3A7F2)
        case .stone: UIColor(hex: 0xCFD1E6)
        case .bark: UIColor(hex: 0x8F8295)
        case .conifer: UIColor(hex: 0x4F9C7C)
        case .hull: UIColor(hex: 0x2E3352)
        case .solar: UIColor(hex: 0x2A3373)
        case .belt: UIColor(hex: 0x3A3D4E)
        case .mint: UIColor(hex: 0x5FCB9A)
        case .insulated: UIColor(hex: 0xEEF0FA)
        case .crate: UIColor(hex: 0xD6B48A)
        case .crateDark: UIColor(hex: 0xB8946A)
        case .sand: UIColor(hex: 0xE9DCC4)
        case .sandDark: UIColor(hex: 0xD8C7A6)
        case .snow: UIColor(hex: 0xF4F6FD)
        case .rock: UIColor(hex: 0xA9ADC9)
        case .rockDark: UIColor(hex: 0x8A8FB0)
        case .water: UIColor(hex: 0x7C97E4)
        case .asphalt: UIColor(hex: 0x9298C9)
        case .glassTower: UIColor(hex: 0x8C9BE0)
        case .steel: UIColor(hex: 0xC3C8DE)
        case .concreteDark: UIColor(hex: 0xC5C8E0)
        case .paintBrand: Palette.brand
        case .paintWhite: UIColor(hex: 0xF3F4FA)
        case .paintTeal: Palette.rivalTeal
        case .paintNavy: Palette.rivalNavy
        case .paintYellow: Palette.forklift
        case .paintSlate: UIColor(hex: 0x5B6382)
        case .paintMint: UIColor(hex: 0x9BCDB7)
        case .paintSand: UIColor(hex: 0xE5D1B2)
        case .paintCoral: UIColor(hex: 0xE69C8B)
        case .chrome: UIColor(hex: 0xD4D7E3)
        case .aluminium: UIColor(hex: 0xBFC4D8)
        case .rubber: UIColor(hex: 0x2B2C36)
        case .glassDark: UIColor(hex: 0x262B45)
        case .lensWhite: UIColor(hex: 0xEEF1FA)
        case .lensAmber: UIColor(hex: 0xF0A23C)
        case .lensRed: UIColor(hex: 0xD8394E)
        case .trim: UIColor(hex: 0x3A3D50)
        case .seat: UIColor(hex: 0x41445C)
        case .rubberSeal: UIColor(hex: 0x2E3040)
        case .hazard: UIColor(hex: 0xF2C230)
        case .foliageLight: Palette.foliage.mixed(with: .white, 0.18)
        case .label: UIColor(hex: 0xFAF8F2)
        case .plinth: UIColor(hex: 0xBFC2DD)
        case .gutter: Palette.brandShade.mixed(with: .black, 0.1)
        case .lightBar: UIColor(hex: 0xDDE2FF)
        }
    }

    /// Clear-coated (glossy car paint with a sharp reflection on top).
    var isPaint: Bool {
        switch self {
        case .paintBrand, .paintWhite, .paintTeal, .paintNavy, .paintYellow, .paintSlate, .paintMint, .paintSand, .paintCoral: true
        default: false
        }
    }

    var metallic: Float {
        switch self {
        case .chrome: 1
        case .aluminium: 0.75
        case .metal: 0.6
        case .darkMetal: 0.35
        case .steel: 0.5
        default: 0
        }
    }

    var roughness: Float {
        switch self {
        case .paintBrand, .paintWhite, .paintTeal, .paintNavy, .paintYellow, .paintSlate, .paintMint, .paintSand, .paintCoral: 0.42
        case .chrome: 0.16
        case .aluminium: 0.34
        case .glassDark: 0.05
        case .lensWhite, .lensAmber, .lensRed: 0.12
        case .rubber, .rubberSeal: 0.88
        case .seat: 0.9
        case .trim: 0.55
        case .glass, .skylight: 0.18
        case .solar: 0.22
        case .glassTower: 0.2
        case .snow: 0.85
        case .metal, .darkMetal: 0.4
        case .tire: 0.92
        case .road, .ground, .yard, .concrete, .grass: 0.9
        default: 0.72
        }
    }
}

/// Builds and caches materials.
enum Materials {
    private static var cache: [Mat: PhysicallyBasedMaterial] = [:]

    static func pbr(_ m: Mat) -> PhysicallyBasedMaterial {
        if let cached = cache[m] { return cached }
        var mat = matte(m.color, roughness: m.roughness)
        mat.metallic = .init(floatLiteral: m.metallic)
        if m == .glass { mat.specular = .init(floatLiteral: 0.8) }
        if m == .glassDark { mat.specular = .init(floatLiteral: 1) }
        if m == .lightBar { // the vans' front light strip always glows softly
            mat.emissiveColor = .init(color: UIColor(hex: 0x9AA8FF))
            mat.emissiveIntensity = 1.2
        }
        if m == .lensRed { // tail lights always glow a little
            mat.emissiveColor = .init(color: Palette.tailLight)
            mat.emissiveIntensity = 0.9
        }
        if m.isPaint {
            mat.clearcoat = .init(floatLiteral: 1)
            mat.clearcoatRoughness = .init(floatLiteral: 0.1)
        }
        cache[m] = mat
        return mat
    }

    /// Curtain-wall glass: glossy and a little metallic so it picks up the sky, glowing from inside at night (0…1).
    static func facadeGlass(night: Float) -> PhysicallyBasedMaterial {
        let day = UIColor(hex: 0x46558E)
        var mat = matte(day.mixed(with: Palette.windowGlow, CGFloat(night * 0.55)), roughness: 0.16)
        mat.metallic = .init(floatLiteral: 0.45 * (1 - night))
        mat.specular = .init(floatLiteral: 0.9)
        mat.emissiveColor = .init(color: Palette.windowGlow)
        mat.emissiveIntensity = night * 1.9
        return mat
    }

    static func matte(_ color: UIColor, roughness: Float = 0.72) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
        mat.roughness = .init(floatLiteral: roughness)
        mat.metallic = .init(floatLiteral: 0)
        return mat
    }

    /// River water: glossy, reflects the sky, with a scrolling ripple normal map.
    static func water(offset: SIMD2<Float> = .zero, scale: SIMD2<Float> = SIMD2(28, 1.2), color: UIColor = UIColor(hex: 0x7C97E4)) -> PhysicallyBasedMaterial {
        var mat = matte(color, roughness: 0.1)
        mat.specular = .init(floatLiteral: 1.0)
        mat.normal = .init(texture: .init(Textures.ripples))
        mat.textureCoordinateTransform = .init(offset: offset, scale: scale, rotation: 0)
        return mat
    }

    /// The same water with its ripples flowing on the GPU (`Water.metal`), so nothing has to touch it per frame.
    /// - flow: how far the ripples move per second, in texture repeats. Nil when the shader isn't available.
    static func flowingWater(scale: SIMD2<Float>, color: UIColor, flow: SIMD2<Float>) -> CustomMaterial? {
        guard let modifier = waterFlow, var mat = try? CustomMaterial(from: water(scale: scale, color: color), geometryModifier: modifier) else { return nil }
        mat.custom.value = SIMD4(flow.x, flow.y, 0, 0)
        return mat
    }

    /// `-oldWater YES` uses the per-frame material swap instead (to compare).
    private static let waterFlow: CustomMaterial.GeometryModifier? = {
        guard !UserDefaults.standard.bool(forKey: "oldWater"), let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary() else { return nil }
        return CustomMaterial.GeometryModifier(named: "waterFlow", in: library)
    }()

    /// A surface that can glow (windows at night, lamps, headlights). `intensity` 0 = off.
    static func glowing(base: UIColor, glow: UIColor, intensity: Float) -> PhysicallyBasedMaterial {
        var mat = matte(base, roughness: 0.4)
        mat.emissiveColor = .init(color: glow)
        mat.emissiveIntensity = intensity
        return mat
    }

    /// A painted-on decal (logos on roofs and trucks): like `decal`, but lit by the sun, so it darkens at night.
    static func paintedDecal(mask: TextureResource, tint: UIColor, opacity: Float = 1) -> PhysicallyBasedMaterial {
        var mat = matte(tint, roughness: 0.6)
        mat.blending = .transparent(opacity: .init(scale: opacity, texture: .init(mask, sampler: sharpSampler)))
        mat.writesDepth = false   // or the depth-based shading (AO) outlines the decal's rectangle
        mat.specular = .init(floatLiteral: 0)   // no sheen on the see-through part of the plane
        return mat
    }

    /// Trilinear filtering with 8× anisotropy: decals seen at a slant (signs, the roof roundel, logos on trucks driving
    /// past) stay sharp instead of going soft, and the mask is clamped at its edges.
    static let sharpSampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.maxAnisotropy = 8
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return MaterialParameters.Texture.Sampler(d)
    }()

    /// A flat decal: a coloured shape whose outline comes from a mask texture (white = visible).
    /// Used for soft shadows, logos, light pools and markings.
    static func decal(mask: TextureResource, tint: UIColor, opacity: Float) -> UnlitMaterial {
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        mat.color = .init(tint: tint)
        mat.blending = .transparent(opacity: .init(scale: opacity, texture: .init(mask, sampler: sharpSampler)))
        // Decals are paint, not geometry: without this the ambient occlusion pass sees each one as a thin
        // slab and draws a square outline around it (the squares under walking staff and trucks).
        mat.writesDepth = false
        return mat
    }
}

/// Every `Mat` side by side in a tiny set of textures (colour, roughness, metalness, specular), so all the plain parts
/// of a model can share ONE material and be drawn in one call. Each part still looks exactly like its own material:
/// `Kit` and `Scenery` point every vertex at the patch of its material. Glossy paint shares a second material (with the
/// clear coat), and glowing lenses keep their own. Draw calls, not vertices, are what cost frame time here.
enum MaterialPalette {
    /// `-noPalette YES`: one material per part, as before (to compare looks and speed).
    static let enabled = !UserDefaults.standard.bool(forKey: "noPalette")

    private static let block = 4                 // texels per patch side, so filtering never reaches a neighbour
    private static let columns = 16
    private static let index: [Mat: Int] = Dictionary(uniqueKeysWithValues: Mat.allCases.enumerated().map { ($1, $0) })
    private static let width = columns * block
    private static let height = (Mat.allCases.count + columns - 1) / columns * block

    /// Can `m` share a palette material? Glowing lenses keep their own (each has its own glow strength).
    static func shares(_ m: Mat) -> Bool { enabled && m != .lensRed && m != .lightBar }
    static func isGlass(_ m: Mat) -> Bool { m == .glass || m == .glassDark }

    /// Texture coordinate of the centre of `m`'s patch (materials sample textures upside down in v).
    static func uv(_ m: Mat) -> SIMD2<Float> {
        let i = index[m] ?? 0
        let x = Float((i % columns) * block) + Float(block) / 2
        let y = Float((i / columns) * block) + Float(block) / 2
        return SIMD2(x / Float(width), 1 - y / Float(height))
    }

    /// The shared material for plain parts (`glass`: some parts are glass, which reflects more), or for glossy paint
    /// (all paints share roughness and clear coat, only the colour differs).
    static func material(paint: Bool, glass: Bool) -> PhysicallyBasedMaterial {
        if paint { return paintMaterial }
        return glass ? plainGlassMaterial : plainMaterial
    }

    private static let plainMaterial = makePlain(glass: false)
    private static let plainGlassMaterial = makePlain(glass: true)
    private static let paintMaterial: PhysicallyBasedMaterial = {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .white, texture: .init(colors, sampler: sampler))
        mat.roughness = .init(floatLiteral: Mat.paintBrand.roughness)
        mat.metallic = .init(floatLiteral: 0)
        mat.clearcoat = .init(floatLiteral: 1)
        mat.clearcoatRoughness = .init(floatLiteral: 0.1)
        return mat
    }()

    private static func makePlain(glass: Bool) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .white, texture: .init(colors, sampler: sampler))
        mat.roughness = .init(scale: 1, texture: .init(scalar("roughness") { $0.roughness }, sampler: sampler))
        mat.metallic = .init(scale: 1, texture: .init(scalar("metallic") { $0.metallic }, sampler: sampler))
        if glass { // glass 0.8, dark glass 1, everything else RealityKit's default 0.5
            mat.specular = .init(scale: 1, texture: .init(scalar("specular") { $0 == .glass ? 0.8 : ($0 == .glassDark ? 1 : 0.5) }, sampler: sampler))
        }
        return mat
    }

    /// Exact texel lookups: no filtering between patches, no mipmaps.
    private static let sampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest
        d.magFilter = .nearest
        d.mipFilter = .notMipmapped
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return MaterialParameters.Texture.Sampler(d)
    }()

    /// Each material's colour (sRGB, like the tint it replaces).
    private static let colors: TextureResource = {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        fill(&pixels, channels: 4) { m in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            m.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b, 1].map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
        }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return try! TextureResource(image: image, withName: "palette.color", options: .init(semantic: .color, mipmapsMode: .none))
    }()

    /// One value per material (roughness, metalness…), linear.
    private static func scalar(_ name: String, _ value: (Mat) -> Float) -> TextureResource {
        var pixels = [UInt8](repeating: 0, count: width * height)
        fill(&pixels, channels: 1) { [UInt8((min(max(value($0), 0), 1) * 255).rounded())] }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                            space: CGColorSpace(name: CGColorSpace.linearGray)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return try! TextureResource(image: image, withName: "palette.\(name)", options: .init(semantic: .scalar, mipmapsMode: .none))
    }

    private static func fill(_ pixels: inout [UInt8], channels: Int, _ value: (Mat) -> [UInt8]) {
        for (i, m) in Mat.allCases.enumerated() {
            let v = value(m)
            let x0 = (i % columns) * block, y0 = (i / columns) * block
            for y in y0..<(y0 + block) {
                for x in x0..<(x0 + block) {
                    for c in 0..<channels { pixels[(y * width + x) * channels + c] = v[c] }
                }
            }
        }
    }
}
