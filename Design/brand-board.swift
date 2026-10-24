import SwiftUI
import AppKit

// Waybill brand board: 3×3 identity sheet. Usage: swift board.swift <scratchpad dir> <out.png> [scale]
let args = CommandLine.arguments
let dir = args[1]
let out = args[2]
let scale = args.count > 3 ? Double(args[3])! : 1

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

enum C {
    static let canvas = Color(hex: 0x0D0D12)
    static let indigo = Color(hex: 0x4B4FD8)
    static let peri = Color(hex: 0x6E72F0)
    static let deep = Color(hex: 0x3536A8)
    static let night = Color(hex: 0x23246E)
    static let mist = Color(hex: 0xC6CAEA)
    static let card = Color(hex: 0xE0BE9D)
    static let ink = Color(hex: 0x1B1D3A)
    static let go = Color(hex: 0x2E9E5B)
    static let amber = Color(hex: 0xD9822B)
    static let paper = Color(hex: 0xF4F4F8)
}

// MARK: images

func cg(_ name: String) -> CGImage {
    let img = NSImage(contentsOfFile: "\(dir)/\(name)")!
    var r = CGRect(origin: .zero, size: img.size)
    return img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
}
func crop(_ name: String, _ rect: CGRect) -> Image {
    let full = cg(name)
    // screenshots are 1400 wide in our coordinates; scale to real pixels
    let k = CGFloat(full.width) / 1400
    let r = CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)
    return Image(decorative: full.cropping(to: r)!, scale: 1)
}
func image(_ name: String) -> Image { Image(decorative: cg(name), scale: 1) }

// MARK: the mark (same geometry as Theme/Brand.swift)

enum Brand {
    static let route: [CGPoint] = [CGPoint(x: 0.15, y: 0.30), CGPoint(x: 0.32, y: 0.72), CGPoint(x: 0.50, y: 0.43),
                                   CGPoint(x: 0.68, y: 0.72), CGPoint(x: 0.787, y: 0.436)]
    static let routeWidth: CGFloat = 0.095
    static let originDiameter: CGFloat = 0.15
    static let ringCenter = CGPoint(x: 0.85, y: 0.27)
    static let ringDiameter: CGFloat = 0.19
    static let ringWidth: CGFloat = 0.055
}

struct RouteShape: Shape {
    var points = Brand.route
    func path(in r: CGRect) -> Path {
        var path = Path()
        let pts = points.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        path.move(to: pts[0])
        for q in pts.dropFirst() { path.addLine(to: q) }
        return path
    }
}

struct RouteOutline: Shape {
    let width: CGFloat
    func path(in r: CGRect) -> Path {
        RouteShape().path(in: r).strokedPath(StrokeStyle(lineWidth: width * r.width, lineCap: .round, lineJoin: .round))
    }
}

struct Mark: View {
    var color: Color = .white
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RouteShape().stroke(color, style: StrokeStyle(lineWidth: s * Brand.routeWidth, lineCap: .round, lineJoin: .round))
                Circle().fill(color)
                    .frame(width: s * Brand.originDiameter, height: s * Brand.originDiameter)
                    .position(x: s * Brand.route[0].x, y: s * Brand.route[0].y)
                Circle().stroke(color, lineWidth: s * Brand.ringWidth)
                    .frame(width: s * (Brand.ringDiameter - Brand.ringWidth), height: s * (Brand.ringDiameter - Brand.ringWidth))
                    .position(x: s * Brand.ringCenter.x, y: s * Brand.ringCenter.y)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct Tile: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x7A7EF4), Color(hex: 0x4A4ED6), Color(hex: 0x2E3097)], startPoint: .top, endPoint: .bottom))
            .overlay(RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: size * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)))
            .overlay(Mark().padding(size * 0.17).shadow(color: Color(hex: 0x14144D, alpha: 0.35), radius: size * 0.03, y: size * 0.012))
            .frame(width: size, height: size)
    }
}

// MARK: panel chrome

let panelW: CGFloat = 741
let panelH: CGFloat = 529

func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }

struct PanelLabel: View {
    let n: String
    let title: String
    var color: Color = .white
    var body: some View {
        HStack(spacing: 10) {
            Text(n).font(.system(size: 13, weight: .semibold, design: .monospaced)).opacity(0.55)
            Rectangle().frame(width: 14, height: 1).opacity(0.35)
            Text(title.uppercased()).font(.system(size: 13, weight: .semibold)).tracking(1.6).opacity(0.8)
        }
        .foregroundStyle(color)
    }
}

struct Panel<Content: View>: View {
    let n: String
    let title: String
    var ink: Color = .white
    var background: AnyView
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
            PanelLabel(n: n, title: title, color: ink).padding(.leading, 30).padding(.top, 26)
        }
        .frame(width: panelW, height: panelH)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

func bg(_ c: Color) -> AnyView { AnyView(c) }

// MARK: 01 cover

struct Cover: View {
    var body: some View {
        Panel(n: "01", title: "Mark", background: AnyView(
            ZStack {
                C.indigo
                RadialGradient(colors: [Color(hex: 0x8A8DF7, alpha: 0.55), .clear], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Color(hex: 0x23246E, alpha: 0.55), .clear], center: UnitPoint(x: 0.95, y: 1.05), startRadius: 0, endRadius: 520)
            })) {
            HStack(spacing: 22) {
                Mark().frame(width: 150, height: 150)
                Text("Waybill").font(rounded(112, .bold)).foregroundStyle(.white).tracking(-2.5)
            }
            .offset(x: -8)
            .frame(width: panelW, height: panelH)
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Text("A logistics idle game for iPad").font(.system(size: 15, weight: .medium)).opacity(0.75)
                    Spacer()
                    Text("2026").font(.system(size: 13, weight: .semibold, design: .monospaced)).opacity(0.55)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 30).padding(.bottom, 26)
            }
        }
    }
}

// MARK: 02 construction

struct Construction: View {
    var body: some View {
        Panel(n: "02", title: "Construction", background: bg(C.ink)) {
            let s: CGFloat = 400
            let ox = (panelW - s) / 2, oy = (panelH - s) / 2 + 6
            ZStack(alignment: .topLeading) {
                // grid
                Path { p in
                    for i in 0...20 {
                        let t = CGFloat(i) / 20 * s
                        p.move(to: CGPoint(x: t, y: 0)); p.addLine(to: CGPoint(x: t, y: s))
                        p.move(to: CGPoint(x: 0, y: t)); p.addLine(to: CGPoint(x: s, y: t))
                    }
                }
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
                Rectangle().stroke(Color.white.opacity(0.14), lineWidth: 1).frame(width: s, height: s)
                // filled mark, very quiet
                Mark(color: C.peri.opacity(0.16)).frame(width: s, height: s)
                // outline of the thick route
                RouteOutline(width: Brand.routeWidth)
                    .stroke(C.peri, lineWidth: 1.6)
                    .frame(width: s, height: s)
                // centre line
                RouteShape().stroke(C.mist.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: s, height: s)
                // origin + ring outlines
                Circle().stroke(C.peri, lineWidth: 1.6)
                    .frame(width: s * Brand.originDiameter, height: s * Brand.originDiameter)
                    .position(x: s * Brand.route[0].x, y: s * Brand.route[0].y)
                ForEach([Brand.ringDiameter, Brand.ringDiameter - 2 * Brand.ringWidth], id: \.self) { d in
                    Circle().stroke(C.peri, lineWidth: 1.6)
                        .frame(width: s * d, height: s * d)
                        .position(x: s * Brand.ringCenter.x, y: s * Brand.ringCenter.y)
                }
                // vertices
                ForEach(0..<5) { i in
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .position(x: s * Brand.route[i].x, y: s * Brand.route[i].y)
                }
                // gable guide: roof triangle over the middle peak
                Path { p in
                    p.move(to: CGPoint(x: s * 0.32, y: s * 0.72))
                    p.addLine(to: CGPoint(x: s * 0.50, y: s * 0.43))
                    p.addLine(to: CGPoint(x: s * 0.68, y: s * 0.72))
                    p.closeSubpath()
                }
                .stroke(C.amber.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                .frame(width: s, height: s)
                annotation("Origin", x: s * 0.15, y: s * 0.30 - 54, align: .center)
                annotation("Destination", x: s * 0.85, y: s * 0.27 - 66, align: .center)
                annotation("Gable", x: s * 0.50, y: s * 0.43 - 44, align: .center, color: C.amber)
            }
            .frame(width: s, height: s, alignment: .topLeading)
            .offset(x: ox, y: oy)
            VStack {
                Spacer()
                HStack {
                    Text("One continuous route that writes a W.").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("stroke 0.095 · grid 20").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 30).padding(.bottom, 26)
            }
        }
    }
    func annotation(_ text: String, x: CGFloat, y: CGFloat, align: HorizontalAlignment, color: Color = C.mist) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(color)
            .fixedSize()
            .position(x: x, y: y)
    }
}

// MARK: 03 product

struct Product: View {
    var body: some View {
        Panel(n: "03", title: "Product", ink: C.ink, background: AnyView(
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF1F2FC), Color(hex: 0xD8DBF5)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xFFFFFF, alpha: 0.9), .clear], center: UnitPoint(x: 0.75, y: 0.1), startRadius: 0, endRadius: 420)
            })) {
            // app icon, home-screen style
            VStack(spacing: 12) {
                Tile(size: 150).shadow(color: Color(hex: 0x23246E, alpha: 0.28), radius: 24, y: 14)
                Text("Waybill").font(.system(size: 17, weight: .semibold)).foregroundStyle(C.ink.opacity(0.85))
            }
            .position(x: 140, y: 190)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    pill { Tile(size: 32); Text("Waybill").font(.system(size: 18, weight: .semibold)).foregroundStyle(C.ink) }
                    pill {
                        Text("R1").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 26).background(C.indigo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Riverside Depot").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.ink)
                            Text("49% stock · 1/1 trucks in").font(.system(size: 11, weight: .medium)).foregroundStyle(C.ink.opacity(0.55))
                        }
                    }
                }
                pill {
                    Text("$12.4K").font(rounded(20, .semibold).monospacedDigit()).foregroundStyle(C.ink)
                    Text("+$420/min").font(.system(size: 12, weight: .bold)).foregroundStyle(C.go)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Color(hex: 0xE2F4E9), in: Capsule())
                }
            }
            .position(x: 270 + 210, y: 170)
            // shipment tracker card
            crop("th1_s.png", CGRect(x: 21, y: 739, width: 746, height: 198))
                .resizable().interpolation(.high)
                .frame(width: 746 * 0.9, height: 198 * 0.9)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color(hex: 0x23246E, alpha: 0.25), radius: 26, y: 14)
                .position(x: panelW / 2, y: panelH - 28 - 198 * 0.9 / 2)
        }
    }
}

extension Product {
    func pill<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.leading, 8).padding(.trailing, 16).frame(height: 50)
            .background(Capsule().fill(.white.opacity(0.92)))
            .overlay(Capsule().stroke(.white, lineWidth: 1))
            .shadow(color: Color(hex: 0x23246E, alpha: 0.12), radius: 12, y: 5)
    }
}

// MARK: 04 essence

struct Essence: View {
    var body: some View {
        Panel(n: "04", title: "Essence", background: AnyView(
            ZStack {
                Color(hex: 0x0F1020)
                // quiet route line, like a road seen at night
                RouteShape(points: [CGPoint(x: -0.05, y: 0.82), CGPoint(x: 0.28, y: 0.95), CGPoint(x: 0.62, y: 0.80), CGPoint(x: 1.05, y: 0.92)])
                    .stroke(C.peri.opacity(0.22), style: StrokeStyle(lineWidth: 2, dash: [14, 12]))
            })) {
            VStack(alignment: .leading, spacing: -8) {
                Text("Keep it").foregroundStyle(.white)
                Text("moving.").foregroundStyle(C.peri)
            }
            .font(rounded(96, .bold))
            .tracking(-2.5)
            .padding(.leading, 30)
            .frame(width: panelW, height: panelH, alignment: .leading)
            .offset(y: 8)
            VStack {
                Spacer()
                HStack {
                    Text("Every shipment, from origin to destination.").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Mark(color: C.peri).frame(width: 30, height: 30)
                }
                .padding(.horizontal, 30).padding(.bottom, 24)
            }
        }
    }
}

// MARK: 05 colour

struct Swatch: View {
    let name: String
    let hex: String
    let color: Color
    let light: Bool
    var big = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: big ? 16 : 12, style: .continuous).fill(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: big ? 20 : 14, weight: .semibold))
                Text("#" + hex).font(.system(size: big ? 13 : 11, weight: .medium, design: .monospaced)).opacity(0.75)
            }
            .foregroundStyle(light ? C.ink : .white)
            .padding(big ? 18 : 12)
        }
    }
}

struct Colour: View {
    var body: some View {
        Panel(n: "05", title: "Colour", ink: C.ink, background: bg(C.paper)) {
            HStack(spacing: 12) {
                Swatch(name: "Waybill Indigo", hex: "4B4FD8", color: C.indigo, light: false, big: true)
                    .frame(width: 250)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Swatch(name: "Periwinkle", hex: "6E72F0", color: C.peri, light: false)
                        Swatch(name: "Deep", hex: "3536A8", color: C.deep, light: false)
                    }
                    HStack(spacing: 12) {
                        Swatch(name: "Night", hex: "23246E", color: C.night, light: false)
                        Swatch(name: "Ink", hex: "1B1D3A", color: C.ink, light: false)
                    }
                    HStack(spacing: 12) {
                        Swatch(name: "Mist", hex: "C6CAEA", color: C.mist, light: true)
                        Swatch(name: "Cardboard", hex: "E0BE9D", color: C.card, light: true)
                    }
                    HStack(spacing: 12) {
                        Swatch(name: "Go", hex: "2E9E5B", color: C.go, light: false)
                        Swatch(name: "Bottleneck", hex: "D9822B", color: C.amber, light: false)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 70)
            .padding(.bottom, 30)
            .frame(width: panelW, height: panelH)
        }
    }
}

// MARK: 06 type

struct Typography: View {
    var body: some View {
        Panel(n: "06", title: "Type", background: AnyView(
            ZStack {
                C.night
                RadialGradient(colors: [C.indigo.opacity(0.45), .clear], center: UnitPoint(x: 0.15, y: 0.55), startRadius: 0, endRadius: 420)
            })) {
            HStack(alignment: .center, spacing: 34) {
                Text("Aa").font(rounded(210, .bold)).foregroundStyle(.white).tracking(-6)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SF Pro Rounded").font(rounded(30, .bold)).foregroundStyle(.white)
                    HStack(spacing: 14) {
                        Text("Regular").font(rounded(17, .regular))
                        Text("Medium").font(rounded(17, .medium))
                        Text("Semibold").font(rounded(17, .semibold))
                        Text("Bold").font(rounded(17, .bold))
                    }
                    .foregroundStyle(C.mist)
                    Text("Friendly, rounded, readable at a glance on a busy map.")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 4)
                        .frame(width: 300, alignment: .leading)
                }
            }
            .padding(.leading, 30)
            .frame(width: panelW, height: panelH, alignment: .leading)
            .offset(y: -24)
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                HStack(alignment: .firstTextBaseline) {
                    Text("TRK-2051 · 12:04 · $2.5M").font(rounded(34, .semibold).monospacedDigit()).foregroundStyle(.white)
                    Spacer()
                    Text("tabular figures").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 30).padding(.bottom, 26)
        }
    }
}

// MARK: 07 print

struct Barcode: View {
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            var seed: UInt64 = 78442
            while x < size.width {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let w = CGFloat(1 + (seed >> 33) % 4) * 1.6
                let gap = CGFloat(1 + (seed >> 41) % 3) * 1.6
                ctx.fill(Path(CGRect(x: x, y: 0, width: min(w, size.width - x), height: size.height)), with: .color(C.ink))
                x += w + gap
            }
        }
    }
}

struct ShippingLabel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Mark().frame(width: 34, height: 34)
                Text("WAYBILL").font(rounded(22, .bold)).tracking(2.5)
                Spacer()
                Text("#SHP-78442").font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 58)
            .background(C.indigo)
            HStack(alignment: .top, spacing: 0) {
                field("From", "Riverside Depot", sub: "Bay 2")
                Rectangle().fill(C.ink.opacity(0.15)).frame(width: 1)
                field("To", "Elmstead", sub: "Express · 1 of 1")
            }
            .frame(height: 96)
            Rectangle().fill(C.ink.opacity(0.15)).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                Barcode().frame(height: 62)
                HStack {
                    Text("TRK-2051").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("10 PALLETS · 18:06").font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(C.ink.opacity(0.8))
            }
            .padding(18)
        }
        .frame(width: 400)
        .background(Color(hex: 0xFBFAF7))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    func field(_ label: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(C.ink.opacity(0.5))
            Text(value).font(rounded(22, .bold)).foregroundStyle(C.ink)
            Text(sub).font(.system(size: 12, weight: .medium)).foregroundStyle(C.ink.opacity(0.6))
        }
        .padding(.horizontal, 18).padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Tape: View {
    var body: some View {
        ZStack {
            C.indigo.opacity(0.94)
            VStack(spacing: 34) {
                ForEach(0..<8) { _ in
                    HStack(spacing: 10) {
                        Mark().frame(width: 26, height: 26)
                        Text("KEEP IT MOVING").font(.system(size: 13, weight: .bold)).tracking(2)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(height: 170)
                }
            }
            // sheen
            LinearGradient(colors: [.white.opacity(0.18), .clear, .white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
        }
        .frame(width: 78)
    }
}

struct Print: View {
    var body: some View {
        Panel(n: "07", title: "Print", ink: C.ink, background: AnyView(
            ZStack {
                C.card
                // corrugation
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 3)), with: .color(Color(hex: 0x9C7350, alpha: 0.07)))
                        y += 9
                    }
                    var seed: UInt64 = 7
                    for _ in 0..<900 {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let x = CGFloat((seed >> 20) % 741), yy = CGFloat((seed >> 40) % 529)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: yy, width: 2, height: 2)), with: .color(Color(hex: 0x6B4A2E, alpha: 0.10)))
                    }
                }
                RadialGradient(colors: [.clear, Color(hex: 0x6B4A2E, alpha: 0.28)], center: .center, startRadius: 200, endRadius: 560)
            })) {
            Tape()
                .shadow(color: Color(hex: 0x6B4A2E, alpha: 0.3), radius: 2, x: 1)
                .frame(height: panelH)
                .position(x: panelW - 96, y: panelH / 2)
            ShippingLabel()
                .shadow(color: Color(hex: 0x4A3220, alpha: 0.35), radius: 14, y: 8)
                .rotationEffect(.degrees(-3.5))
                .position(x: panelW / 2 - 30, y: panelH / 2 + 18)
        }
    }
}

// MARK: 08 worlds

struct Worlds: View {
    struct Strip { let file: String; let cx: CGFloat; let cy: CGFloat; let tag: String; let name: String }
    let strips = [
        Strip(file: "hero_day_s.png", cx: 860, cy: 520, tag: "R1", name: "Riverside"),
        Strip(file: "hb2_s.png", cx: 700, cy: 330, tag: "R2", name: "Harbour"),
        Strip(file: "gp4_s.png", cx: 1210, cy: 420, tag: "R3", name: "Granite"),
        Strip(file: "mt1_s.png", cx: 720, cy: 380, tag: "R4", name: "Metro"),
        Strip(file: "or3_s.png", cx: 290, cy: 380, tag: "R5", name: "Orbit"),
    ]
    var body: some View {
        let gap: CGFloat = 3
        let w = (panelW - gap * 4) / 5
        let srcH: CGFloat = 760, srcW = srcH * w / panelH
        Panel(n: "08", title: "Worlds", background: bg(C.canvas)) {
            HStack(spacing: gap) {
                ForEach(0..<5) { i in
                    let s = strips[i]
                    let y0 = max(0, min(978 - srcH, s.cy - srcH / 2))
                    let x0 = max(0, min(1400 - srcW, s.cx - srcW / 2))
                    crop(s.file, CGRect(x: x0, y: y0, width: srcW, height: srcH))
                        .resizable().interpolation(.high)
                        .frame(width: w, height: panelH)
                }
            }
            // darken for type
            LinearGradient(colors: [Color(hex: 0x0D0D2A, alpha: 0.72), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.34))
            LinearGradient(colors: [.clear, Color(hex: 0x0D0D2A, alpha: 0.55), Color(hex: 0x0D0D2A, alpha: 0.88)], startPoint: UnitPoint(x: 0.5, y: 0.72), endPoint: .bottom)
            HStack(spacing: gap) {
                ForEach(0..<5) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strips[i].tag).font(.system(size: 11, weight: .semibold, design: .monospaced)).opacity(0.7)
                        Text(strips[i].name).font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 14).padding(.bottom, 22)
                    .frame(width: w, height: panelH, alignment: .bottomLeading)
                }
            }
            // one route through five worlds: the mark's five vertices, one per region
            let pts = [CGPoint(x: 0.1, y: 0.40), CGPoint(x: 0.3, y: 0.68), CGPoint(x: 0.5, y: 0.49), CGPoint(x: 0.7, y: 0.68), CGPoint(x: 0.9, y: 0.40)]
            ZStack {
                RouteShape(points: pts).stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                Circle().fill(.white).frame(width: 22, height: 22).position(x: pts[0].x * panelW, y: pts[0].y * panelH)
                ForEach(1..<4) { i in
                    Circle().fill(C.indigo).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 3))
                        .position(x: pts[i].x * panelW, y: pts[i].y * panelH)
                }
                Circle().stroke(.white, lineWidth: 6).frame(width: 26, height: 26).position(x: pts[4].x * panelW, y: pts[4].y * panelH)
            }
            .shadow(color: Color(hex: 0x14144D, alpha: 0.6), radius: 10, y: 3)
            .frame(width: panelW, height: panelH)
            Text("Five worlds, one route.")
                .font(rounded(34, .bold)).foregroundStyle(.white).tracking(-0.5)
                .padding(.leading, 30).padding(.top, 58)
        }
    }
}

// MARK: 09 system

struct System: View {
    var body: some View {
        Panel(n: "09", title: "System", ink: C.ink, background: AnyView(
            LinearGradient(colors: [Color(hex: 0xF4F5FC), Color(hex: 0xE4E6F7)], startPoint: .top, endPoint: .bottom))) {
            VStack(alignment: .leading, spacing: 30) {
                stepper
                HStack(spacing: 10) {
                    chip("Ready", fg: .white, bg: C.go)
                    chip("Loading 8/10", fg: C.go, bg: Color(hex: 0xE2F4E9))
                    chip("In transit", fg: C.indigo, bg: Color(hex: 0xE8E9FC))
                    chip("Bottleneck", fg: Color(hex: 0xB0630F), bg: Color(hex: 0xFBEBD9))
                    chip("★ 12", fg: C.ink, bg: .white)
                }
                HStack(spacing: 12) {
                    stage("arrow.down.to.line.compact")
                    stage("square.stack.3d.up.fill")
                    stage("shippingbox.fill")
                    stage("truck.box.fill", amber: true)
                    Rectangle().fill(C.ink.opacity(0.12)).frame(width: 1, height: 40).padding(.horizontal, 6)
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 16, weight: .bold))
                        Text("Rush").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(C.amber)
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Capsule().stroke(C.amber, lineWidth: 2.5))
                }
                HStack(spacing: 4) {
                    ForEach(["thumb-truck", "thumb-hauler", "thumb-train", "thumb-van", "thumb-rocket"], id: \.self) { t in
                        image("thumbs/\(t).png").resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .frame(width: 128, height: 100)
                    }
                }
                .offset(x: -8)
            }
            .padding(.horizontal, 30)
            .padding(.top, 76)
            .frame(width: panelW, height: panelH, alignment: .topLeading)
        }
    }
    var stepper: some View {
        let steps: [(String, String, Int)] = [("Picked", "18:06", 2), ("Loading", "10/10", 1), ("In transit", "—", 0), ("Delivered", "ETA 18:21", 0)]
        return ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Rectangle().fill(C.indigo).frame(height: 4)
                Rectangle().fill(C.ink.opacity(0.12)).frame(height: 4)
            }
            .frame(width: 480)
            .padding(.top, 20)
            HStack(spacing: 0) {
                ForEach(0..<4) { i in
                    let s = steps[i]
                    VStack(spacing: 8) {
                        ZStack {
                            if s.2 == 2 {
                                Circle().fill(C.indigo).frame(width: 40, height: 40)
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            } else if s.2 == 1 {
                                Circle().fill(C.indigo.opacity(0.18)).frame(width: 50, height: 50)
                                Circle().fill(C.indigo).frame(width: 38, height: 38)
                                Image(systemName: "list.clipboard.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            } else {
                                Circle().fill(Color(hex: 0xE6E7F2)).frame(width: 40, height: 40)
                                Image(systemName: i == 2 ? "truck.box.fill" : "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(C.ink.opacity(0.3))
                            }
                        }
                        .frame(height: 44)
                        Text(s.0).font(.system(size: 15, weight: .semibold)).foregroundStyle(s.2 == 0 ? C.ink.opacity(0.5) : C.ink)
                        Text(s.1).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(s.2 == 1 ? C.go : C.ink.opacity(0.5))
                    }
                    .frame(width: 160)
                }
            }
        }
        .frame(width: 640, alignment: .leading)
        .offset(x: -50)
    }
    func chip(_ t: String, fg: Color, bg: Color) -> some View {
        Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(fg)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(bg, in: Capsule())
            .overlay(Capsule().stroke(C.ink.opacity(bg == .white ? 0.1 : 0), lineWidth: 1))
    }
    func stage(_ symbol: String, amber: Bool = false) -> some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
            .foregroundStyle(amber ? C.amber : C.indigo)
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(amber ? Color(hex: 0xFBEBD9) : .white))
            .shadow(color: C.ink.opacity(0.08), radius: 6, y: 2)
    }
}

// MARK: board

struct Board: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    Mark(color: C.peri).frame(width: 22, height: 22)
                    Text("Waybill").font(rounded(18, .bold)).foregroundStyle(.white)
                    Text("Identity system").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.45)).padding(.leading, 6)
                }
                Spacer()
                Text("v1.0 · October 2026").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
            }
            .frame(height: 100)
            Grid(horizontalSpacing: 24, verticalSpacing: 24) {
                GridRow { Cover(); Construction(); Product() }
                GridRow { Essence(); Colour(); Typography() }
                GridRow { Print(); Worlds(); System() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 64)
        .frame(width: 2400, height: 1800, alignment: .top)
        .background(C.canvas)
        .environment(\.colorScheme, .dark)
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Board())
    r.scale = scale
    let img = r.nsImage!
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("board ok", img.size, "scale", scale)
}
