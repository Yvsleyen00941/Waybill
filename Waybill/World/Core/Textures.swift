import RealityKit
import UIKit

/// Textures drawn in code with Core Graphics: no image files needed.
/// Masks are greyscale: white = fully visible, black = hidden, grey = partly visible.
/// (RealityKit reads opacity from the colour, so masks must not rely on transparency.)
enum Textures {
    private static var cache: [String: TextureResource] = [:]

    private static func make(_ key: String, size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> TextureResource {
        if let t = cache[key] { return t }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            draw(ctx.cgContext, size)
        }
        let texture = try! TextureResource(image: image.cgImage!, options: .init(semantic: .raw))
        cache[key] = texture
        return texture
    }

    /// Soft round blob: contact shadows under trees, pins and people.
    static var softDot: TextureResource {
        make("softDot", size: CGSize(width: 128, height: 128)) { ctx, size in
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
        }
    }

    /// Soft rounded rectangle: contact shadows under vehicles, pallets and buildings.
    /// Drawn by casting a blurred shadow from a shape placed outside the canvas.
    static func softRect(aspect: CGFloat) -> TextureResource {
        let w: CGFloat = 256, h = max(32, (256 / aspect).rounded())
        return make("softRect \(Int(h))", size: CGSize(width: w, height: h)) { ctx, size in
            let blur = min(size.width, size.height) * 0.22
            let inset = blur * 1.1
            let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            let offset: CGFloat = 10_000
            ctx.setShadow(offset: CGSize(width: offset, height: 0), blur: blur, color: UIColor.white.cgColor)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: rect.offsetBy(dx: -offset, dy: 0), cornerRadius: blur * 0.6).cgPath)
            ctx.fillPath()
        }
    }

    /// Warm pool of light on the ground under lamps (night only).
    static var lightPool: TextureResource {
        make("lightPool", size: CGSize(width: 128, height: 128)) { ctx, size in
            let colors = [UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
        }
    }

    /// Tileable ripple normal map for water (sum of waves with whole-number frequencies, so it repeats seamlessly).
    static var ripples: TextureResource {
        if let t = cache["ripples"] { return t }
        let n = 256
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        let waves: [(kx: Double, ky: Double, amp: Double, phase: Double)] = [
            (3, 1, 1.0, 0.3), (-2, 4, 0.7, 1.7), (5, -3, 0.45, 2.9), (7, 6, 0.25, 0.8), (-9, 2, 0.18, 4.1), (1, 9, 0.2, 5.5),
        ]
        for y in 0..<n {
            for x in 0..<n {
                var dx = 0.0, dy = 0.0
                let u = Double(x) / Double(n), v = Double(y) / Double(n)
                for w in waves {
                    let a = 2 * Double.pi * (w.kx * u + w.ky * v) + w.phase
                    dx += w.amp * w.kx * cos(a)
                    dy += w.amp * w.ky * cos(a)
                }
                var nx = -dx * 0.035, ny = -dy * 0.035, nz = 1.0
                let len = (nx * nx + ny * ny + nz * nz).squareRoot()
                nx /= len; ny /= len; nz /= len
                let i = (y * n + x) * 4
                pixels[i] = UInt8((nx * 0.5 + 0.5) * 255)
                pixels[i + 1] = UInt8((ny * 0.5 + 0.5) * 255)
                pixels[i + 2] = UInt8((nz * 0.5 + 0.5) * 255)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let texture = try! TextureResource(image: image, options: .init(semantic: .normal))
        cache["ripples"] = texture
        return texture
    }

    /// Ring for the pulsing marker under map pins.
    static var ring: TextureResource {
        make("ring", size: CGSize(width: 128, height: 128)) { ctx, size in
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(9)
            ctx.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
            ctx.setFillColor(UIColor(white: 1, alpha: 0.28).cgColor)
            ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12))
        }
    }

    /// Text mask, e.g. the "Waybill" wordmark on trucks and signs.
    static func text(_ string: String, weight: UIFont.Weight = .heavy, size: CGSize = CGSize(width: 512, height: 112)) -> TextureResource {
        make("text \(string) \(weight.rawValue) \(size)", size: size) { ctx, size in
            var font = UIFont.systemFont(ofSize: size.height * 0.62, weight: weight)
            if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: font.pointSize) }
            // Shrink long text so it stays on one line
            let lineWidth = (string as NSString).size(withAttributes: [.font: font, .kern: -1]).width
            if lineWidth > size.width * 0.94 { font = font.withSize(font.pointSize * size.width * 0.94 / lineWidth) }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: style, .kern: -1]
            let text = NSAttributedString(string: string, attributes: attributes)
            let bounds = text.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
            text.draw(in: CGRect(x: 0, y: (size.height - bounds.height) / 2, width: size.width, height: bounds.height))
        }
    }

    /// The Waybill roundel used on roofs: a white disc with the Route W left out, so the roof shows through.
    static var roundel: TextureResource {
        make("roundel4", size: CGSize(width: 1024, height: 1024)) { ctx, size in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12))
            Brand.drawMark(in: ctx, rect: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.15, dy: size.height * 0.15), color: .black, weight: 1.35)
        }
    }

    /// An SF Symbol as a mask (e.g. the snowflake on the cold store).
    static func symbol(_ name: String, size: CGFloat = 256) -> TextureResource {
        make("symbol \(name) \(size)", size: CGSize(width: size, height: size)) { ctx, s in
            let config = UIImage.SymbolConfiguration(pointSize: size * 0.7, weight: .bold)
            guard let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let fit = image.size
            let scale = min(s.width * 0.86 / fit.width, s.height * 0.86 / fit.height)
            let w = fit.width * scale, h = fit.height * scale
            UIGraphicsPushContext(ctx)
            image.draw(in: CGRect(x: (s.width - w) / 2, y: (s.height - h) / 2, width: w, height: h))
            UIGraphicsPopContext()
        }
    }

    /// Brand emblems drawn as masks.
    enum Emblem { case route, chevron, peak }

    private static func drawEmblem(_ emblem: Emblem, in ctx: CGContext, rect: CGRect) {
        switch emblem {
        case .route:
            Brand.drawMark(in: ctx, rect: rect, color: .white, weight: 1.2)
        case .chevron: // Nordway: a north-pointing chevron over a horizon line
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(rect.width * 0.12)
            ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.62))
            ctx.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.22))
            ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.minY + rect.height * 0.62))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.84))
            ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.84))
            ctx.strokePath()
        case .peak: // Peakfresh: two mountain peaks
            ctx.setFillColor(UIColor.white.cgColor)
            let big = CGMutablePath()
            big.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.15))
            big.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.18))
            big.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.maxY - rect.height * 0.15))
            big.closeSubpath()
            ctx.addPath(big)
            ctx.fillPath()
            let small = CGMutablePath()
            small.move(to: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.maxY - rect.height * 0.15))
            small.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.42))
            small.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.maxY - rect.height * 0.15))
            small.closeSubpath()
            ctx.addPath(small)
            ctx.fillPath()
        }
    }

    /// Emblem + name side by side, e.g. truck liveries and the facade sign.
    static func logo(_ name: String, emblem: Emblem, uppercase: Bool = false, size: CGSize = CGSize(width: 1024, height: 224)) -> TextureResource {
        make("logo \(name) \(emblem) \(uppercase) \(size)", size: size) { ctx, size in
            let h = size.height
            var font = UIFont.systemFont(ofSize: h * (uppercase ? 0.5 : 0.6), weight: uppercase ? .heavy : .bold)
            if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: font.pointSize) }
            let text = NSAttributedString(string: uppercase ? name.uppercased() : name, attributes: [
                .font: font, .foregroundColor: UIColor.white, .kern: uppercase ? h * 0.04 : -h * 0.01,
            ])
            let textSize = text.size()
            let emblemSize = h * 0.78
            let gap = h * 0.16
            let total = emblemSize + gap + textSize.width
            let x0 = (size.width - total) / 2
            drawEmblem(emblem, in: ctx, rect: CGRect(x: x0, y: (h - emblemSize) / 2, width: emblemSize, height: emblemSize))
            text.draw(at: CGPoint(x: x0 + emblemSize + gap, y: (h - textSize.height) / 2))
        }
    }
}
