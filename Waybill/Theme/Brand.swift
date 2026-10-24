import SwiftUI
import UIKit

/// The Waybill identity in one place.
///
/// **The mark: "Route W".** A waybill is the document that travels with a shipment, from origin to
/// destination. The mark is that journey: one continuous route that writes a W, starting at a solid
/// origin dot and arriving at a destination ring. Its middle peak doubles as a warehouse gable.
enum Brand {
    static let name = "Waybill"
    static let tagline = "Keep it moving."

    // Geometry on a 1×1 grid (y points down), shared by SwiftUI, Core Graphics and the app icon script.
    static let route: [CGPoint] = [CGPoint(x: 0.15, y: 0.30), CGPoint(x: 0.32, y: 0.72), CGPoint(x: 0.50, y: 0.43),
                                   CGPoint(x: 0.68, y: 0.72), CGPoint(x: 0.787, y: 0.436)]
    static let routeWidth: CGFloat = 0.095
    static let originDiameter: CGFloat = 0.15
    static let ringCenter = CGPoint(x: 0.85, y: 0.27)
    static let ringDiameter: CGFloat = 0.19
    static let ringWidth: CGFloat = 0.055

    /// Draw the mark with Core Graphics (textures, decals). Fills/strokes in `color`.
    /// `weight` > 1 thickens it for signage seen from far away.
    static func drawMark(in ctx: CGContext, rect: CGRect, color: UIColor, weight: CGFloat = 1) {
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: rect.minX + q.x * rect.width, y: rect.minY + q.y * rect.height) }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(routeWidth * weight * rect.width)
        ctx.move(to: p(route[0]))
        for q in route.dropFirst() { ctx.addLine(to: p(q)) }
        ctx.strokePath()
        let o = p(route[0]), r = originDiameter * min(weight, 1.25) * rect.width / 2
        ctx.fillEllipse(in: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2))
        let c = p(ringCenter), rr = (ringDiameter - ringWidth) * rect.width / 2
        ctx.setLineWidth(ringWidth * weight * rect.width)
        ctx.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
        ctx.restoreGState()
    }
}

/// The route line of the mark (stroke it). `trim` lets it draw itself in the intro animation.
struct RouteShape: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let pts = Brand.route.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        path.move(to: pts[0])
        for q in pts.dropFirst() { path.addLine(to: q) }
        return path
    }
}

/// The full mark as a SwiftUI view. `progress` 0…1 animates the route drawing in.
struct WaybillMark: View {
    var color: Color = Palette.UI.brand
    var progress: CGFloat = 1     // how much of the route is drawn
    var origin: CGFloat = 1       // origin dot scale
    var ring: CGFloat = 1         // destination ring scale

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RouteShape()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: s * Brand.routeWidth, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(color)
                    .frame(width: s * Brand.originDiameter, height: s * Brand.originDiameter)
                    .scaleEffect(max(origin, 0.001))
                    .position(x: s * Brand.route[0].x, y: s * Brand.route[0].y)
                Circle()
                    .stroke(color, lineWidth: s * Brand.ringWidth)
                    .frame(width: s * (Brand.ringDiameter - Brand.ringWidth), height: s * (Brand.ringDiameter - Brand.ringWidth))
                    .scaleEffect(max(ring, 0.001))
                    .opacity(Double(min(ring * 2, 1)))
                    .position(x: s * Brand.ringCenter.x, y: s * Brand.ringCenter.y)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The app-icon style tile: indigo gradient with the white mark.
struct WaybillTile: View {
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x7276F2), Color(hex: 0x3F43C9)], startPoint: .top, endPoint: .bottom))
            .overlay(WaybillMark(color: .white).padding(size * 0.14))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .frame(width: size, height: size)
    }
}
