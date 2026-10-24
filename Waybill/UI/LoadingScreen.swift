import SwiftUI

/// The loading screen, shown every time Waybill opens: on a cold launch and when you come back to the app.
///
/// While the world warms up behind it, the Route W draws itself (a glowing shipment travels the route,
/// the destination ring lands with a ripple), the name settles in letter by letter, and a progress line
/// tracks the real work. Then the destination ring opens like an iris onto the world. Tap to hurry it along.
struct LoadingScreen: View {
    enum Kind { case launch, resume }

    /// One piece of real work, with the line shown while it runs.
    struct Step {
        let label: String
        let work: () async -> Void
    }

    let kind: Kind
    let siteLine: String
    /// False while the app is in the background: the sequence waits, and restarts when you come back.
    let running: Bool
    /// Built when the sequence starts, so the labels describe the current state.
    let steps: () -> [Step]
    /// The screen is fully covered (the interface underneath can be hidden now).
    var onCovered: () -> Void = {}
    var onReveal: () -> Void
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var backdrop = false
    @State private var origin: CGFloat = 0
    @State private var route: CGFloat = 0
    @State private var ring: CGFloat = 0
    @State private var rippleScale: CGFloat = 1
    @State private var rippleOpacity: Double = 0
    @State private var letters = false
    @State private var tagline = false
    @State private var showProgress = false
    @State private var progress: Double = 0
    @State private var status = ""
    @State private var leaving = false
    @State private var hurry = false

    // The iris: a hole that grows out of the destination ring
    @State private var size: CGSize = .zero
    @State private var markFrame: CGRect = .zero
    @State private var irisCenter: CGPoint = .zero
    @State private var iris: CGFloat = 0
    @State private var rimWidth: CGFloat = 0
    @State private var rimOpacity: Double = 0
    @State private var fade: Double

    private let markSize: CGFloat = 124

    init(kind: Kind, siteLine: String, running: Bool, steps: @escaping () -> [Step],
         onCovered: @escaping () -> Void = {}, onReveal: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.kind = kind
        self.siteLine = siteLine
        self.running = running
        self.steps = steps
        self.onCovered = onCovered
        self.onReveal = onReveal
        self.onFinished = onFinished
        // A cold launch takes over from the system launch screen (same colour). Coming back, the system
        // zooms in on a snapshot of the game, so the loading screen fades in over the live game instead of cutting.
        _fade = State(initialValue: kind == .resume ? 0 : 1)
    }

    var body: some View {
        ZStack {
            Color(hex: 0x24266E) // matches the system launch screen, so the hand-over is invisible
            LoadingBackdrop()
                .opacity(backdrop ? 1 : 0)
            VStack(spacing: 28) {
                mark
                    .background(GeometryReader { g in
                        Color.clear.preference(key: MarkFrameKey.self, value: g.frame(in: .named("loader")))
                    })
                VStack(spacing: 10) {
                    Wordmark(text: Brand.name, visible: letters)
                    Text(Brand.tagline)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .opacity(tagline ? 1 : 0)
                        .offset(y: tagline ? 0 : 6)
                }
            }
            .offset(y: -18)
            .scaleEffect(leaving ? 1.07 : 1)
            .opacity(leaving ? 0 : 1)
            .blur(radius: leaving ? 6 : 0)

            VStack {
                Spacer()
                progressBlock
                    .padding(.bottom, 58)
            }
            .opacity(showProgress && !leaving ? 1 : 0)

            IrisRing(center: irisCenter, radius: iris, width: rimWidth)
                .fill(.white, style: FillStyle(eoFill: true))
                .opacity(rimOpacity)
        }
        .coordinateSpace(name: "loader")
        .onPreferenceChange(MarkFrameKey.self) { markFrame = $0 }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { size = g.size }
                .onChange(of: g.size) { _, s in size = s }
        })
        .mask {
            IrisHole(center: irisCenter, radius: iris)
                .fill(style: FillStyle(eoFill: true))
        }
        .opacity(fade)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { hurry = true }
        .task(id: running) {
            guard running else { return }
            await run()
        }
    }

    // MARK: Pieces

    private var mark: some View {
        ZStack {
            WaybillMark(color: .white, progress: route, origin: origin, ring: ring)
            RouteHead(progress: route)
                .fill(.white)
                .blur(radius: 7)
                .opacity(0.9)
            RouteHead(progress: route, scale: 0.42)
                .fill(.white)
            // Delivery ripple off the destination ring
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: markSize * Brand.ringDiameter, height: markSize * Brand.ringDiameter)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .position(x: markSize * Brand.ringCenter.x, y: markSize * Brand.ringCenter.y)
        }
        .frame(width: markSize, height: markSize)
    }

    private var progressBlock: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.75), .white], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, 220 * progress))
                    .shadow(color: .white.opacity(0.55), radius: 6)
            }
            .frame(width: 220, height: 4)
            ZStack {
                Text(status)
                    .id(status)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 5)),
                                            removal: .opacity.combined(with: .offset(y: -5))))
            }
            .font(.system(size: 14, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
            .frame(height: 18)
            Text(siteLine.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.34))
        }
    }

    private var ringCenter: CGPoint {
        guard markFrame.width > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        return CGPoint(x: markFrame.minX + markFrame.width * Brand.ringCenter.x,
                       y: markFrame.minY + markFrame.height * Brand.ringCenter.y)
    }

    // MARK: Sequence

    private func run() async {
        reset()
        let k = kind == .resume ? 0.62 : 1.0
        func pause(_ seconds: Double) async {
            try? await Task.sleep(for: .seconds(hurry ? seconds * 0.25 : seconds * k))
        }

        if kind == .resume {
            backdrop = true
            withAnimation(.easeOut(duration: 0.3)) { fade = 1 } completion: { onCovered() }
        } else {
            withAnimation(.easeOut(duration: 0.7)) { backdrop = true }
            onCovered()
        }
        let work = Task { await runSteps(k: k) }

        // 1. origin dot  2. the shipment travels the route  3. the ring lands  4. the name settles
        await pause(0.25)
        withAnimation(.spring(duration: 0.45, bounce: 0.45)) { origin = 1 }
        await pause(0.2)
        withAnimation(.easeOut(duration: 0.4)) { showProgress = true }
        withAnimation(.timingCurve(0.55, 0, 0.25, 1, duration: 0.95 * k)) { route = 1 }
        await pause(0.88)
        withAnimation(.spring(duration: 0.5, bounce: 0.5)) { ring = 1 }
        rippleOpacity = 0.7
        withAnimation(.easeOut(duration: 1.2).delay(0.06)) {
            rippleScale = 3.4
            rippleOpacity = 0
        }
        await pause(0.15)
        letters = true
        await pause(0.4)
        withAnimation(.spring(duration: 0.7, bounce: 0.1)) { tagline = true }
        await pause(0.55)
        if Task.isCancelled { work.cancel(); return }

        await work.value
        if Task.isCancelled { return }
        withAnimation(.spring(duration: 0.35, bounce: 0)) { progress = 1 }
        await pause(0.3)
        if Task.isCancelled { return }
        await reveal()
    }

    private func runSteps(k: Double) async {
        try? await Task.sleep(for: .seconds(0.45 * k))
        let list = steps()
        for (i, step) in list.enumerated() {
            if Task.isCancelled { return }
            let n = Double(list.count)
            withAnimation(.easeInOut(duration: 0.3)) { status = step.label }
            // creep towards the end of this step while it works, then snap to it
            withAnimation(.spring(duration: 1.4, bounce: 0)) { progress = (Double(i) + 0.8) / n }
            let started = ContinuousClock.now
            await step.work()
            let minimum = Duration.seconds(hurry ? 0.1 : 0.5 * k)
            let spent = ContinuousClock.now - started
            if spent < minimum { try? await Task.sleep(for: minimum - spent) }
            withAnimation(.spring(duration: 0.4, bounce: 0)) { progress = Double(i + 1) / n }
        }
    }

    /// The destination ring opens onto the world.
    private func reveal() async {
        onReveal()
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.5)) { fade = 0 }
            try? await Task.sleep(for: .seconds(0.5))
            onFinished()
            return
        }
        // Start the hole exactly inside the ring, the rim exactly on it
        let s = markSize
        var start = Transaction()
        start.disablesAnimations = true
        withTransaction(start) {
            irisCenter = ringCenter
            iris = s * (Brand.ringDiameter / 2 - Brand.ringWidth)
            rimWidth = s * Brand.ringWidth
            rimOpacity = 1
        }
        let c = irisCenter
        let far = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? 1500
        withAnimation(.easeIn(duration: 0.32)) { leaving = true }
        withAnimation(.timingCurve(0.65, 0, 0.18, 1, duration: 1.15)) {
            iris = far + 40
            rimWidth = 1.5
        }
        withAnimation(.easeIn(duration: 0.75).delay(0.35)) { rimOpacity = 0 }
        try? await Task.sleep(for: .seconds(1.15))
        onFinished()
    }

    private func reset() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            origin = 0; route = 0; ring = 0; rippleScale = 1; rippleOpacity = 0; letters = false; tagline = false
            showProgress = false; progress = 0; status = ""; leaving = false; hurry = false
            iris = 0; rimWidth = 0; rimOpacity = 0
            if kind == .resume { fade = 0; backdrop = false }
        }
    }
}

// MARK: - Backdrop

/// Slowly drifting indigo mesh with dotted shipping lanes flowing across it.
private struct LoadingBackdrop: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                MeshGradient(width: 3, height: 3, points: points(t), colors: [
                    Color(hex: 0x2B2D86), Color(hex: 0x3538A6), Color(hex: 0x23246E),
                    Color(hex: 0x30329A), Color(hex: 0x4A4ED2), Color(hex: 0x2A2C88),
                    Color(hex: 0x1B1D44), Color(hex: 0x272975), Color(hex: 0x17183A),
                ])
                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    let lanes: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
                        (CGPoint(x: -40, y: h * 0.78), CGPoint(x: w * 0.3, y: h * 0.62), CGPoint(x: w * 0.62, y: h * 0.98), CGPoint(x: w + 40, y: h * 0.8)),
                        (CGPoint(x: -40, y: h * 0.2), CGPoint(x: w * 0.35, y: h * 0.05), CGPoint(x: w * 0.7, y: h * 0.4), CGPoint(x: w + 40, y: h * 0.16)),
                        (CGPoint(x: w * 0.12, y: h + 40), CGPoint(x: w * 0.2, y: h * 0.5), CGPoint(x: w * 0.06, y: h * 0.3), CGPoint(x: w * 0.18, y: -40)),
                        (CGPoint(x: w * 0.9, y: -40), CGPoint(x: w * 0.78, y: h * 0.4), CGPoint(x: w * 0.96, y: h * 0.62), CGPoint(x: w * 0.84, y: h + 40)),
                    ]
                    for (i, lane) in lanes.enumerated() {
                        var p = Path()
                        p.move(to: lane.0)
                        p.addCurve(to: lane.3, control1: lane.1, control2: lane.2)
                        let phase = CGFloat(t * (i.isMultiple(of: 2) ? -26 : 20))
                        ctx.stroke(p, with: .color(.white.opacity(0.075)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 13], dashPhase: phase))
                    }
                }
                RadialGradient(colors: [.white.opacity(0.10), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 420)
            }
        }
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ offset: Double, _ amount: Float) -> Float { Float(sin(t * speed + offset)) * amount }
        return [
            [0, 0], [0.5 + wave(0.21, 0, 0.12), 0], [1, 0],
            [0, 0.5 + wave(0.17, 1, 0.12)],
            [0.5 + wave(0.23, 2, 0.08), 0.45 + wave(0.19, 3, 0.07)],
            [1, 0.5 + wave(0.15, 4, 0.12)],
            [0, 1], [0.5 + wave(0.18, 5, 0.12), 1], [1, 1],
        ]
    }
}

// MARK: - Shapes

/// The glowing shipment at the tip of the route while it draws. Shrinks to nothing at both ends.
private struct RouteHead: Shape {
    var progress: CGFloat
    var scale: CGFloat = 1
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in r: CGRect) -> Path {
        guard progress > 0.001, progress < 0.999 else { return Path() }
        let pts = Brand.route.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        let lengths = zip(pts, pts.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = lengths.reduce(0, +) * progress
        var point = pts[0]
        for (i, length) in lengths.enumerated() {
            if remaining <= length {
                let f = remaining / length
                point = CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * f, y: pts[i].y + (pts[i + 1].y - pts[i].y) * f)
                break
            }
            remaining -= length
            point = pts[i + 1]
        }
        let radius = r.width * Brand.routeWidth * 0.9 * scale * min(1, sin(progress * .pi) * 2.2)
        return Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// Everything except a circle: the loading screen with a growing hole in it.
private struct IrisHole: Shape {
    var center: CGPoint
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path(r.insetBy(dx: -2, dy: -2))
        if radius > 0 {
            p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        return p
    }
}

/// The bright rim around the hole: starts as the mark's destination ring, thins as it grows.
private struct IrisRing: Shape {
    var center: CGPoint
    var radius: CGFloat
    var width: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, width) }
        set { radius = newValue.first; width = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        guard radius > 0, width > 0 else { return Path() }
        let outer = radius + width
        var p = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return p
    }
}

// MARK: - Wordmark

/// "Waybill", letter by letter: each one rises out of a soft blur.
private struct Wordmark: View {
    let text: String
    let visible: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, letter in
                Text(String(letter))
                    .opacity(visible ? 1 : 0)
                    .offset(y: visible ? 0 : 18)
                    .blur(radius: visible ? 0 : 7)
                    .animation(.spring(duration: 0.6, bounce: 0.22).delay(Double(i) * 0.045), value: visible)
            }
        }
        .font(.system(size: 52, weight: .bold, design: .rounded))
        .tracking(-0.6)
        .foregroundStyle(.white)
    }
}

private struct MarkFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next } // siblings without a mark report .zero; don't let them win
    }
}
