import Combine
import Observation
import RealityKit
import UIKit
import simd

/// Owns the 3D world: the RealityKit view, the camera, the light, everything that moves,
/// and the per-frame loop that ties them together. The SwiftUI interface talks to this object.
@Observable
final class WorldController {
    enum TimeMode { case live, preview }

    // MARK: State the interface reads

    /// Frames per second of the 3D world, measured.
    private(set) var fps: Int = 0
    /// The hour currently shown in the world (live clock or preview).
    private(set) var shownHour: Double = DayCycle.currentHour()
    var timeMode: TimeMode = .live { didSet { applyTimeOfDay(force: true) } }
    var previewHour: Double = 21 { didSet { if timeMode == .preview { applyTimeOfDay(force: true) } } }
    /// Ambient occlusion (soft contact shading) and colour grade, both done in `PostFXShaders`.
    var occlusionOn = true { didSet { post.occlusionEnabled = occlusionOn } }
    var gradeOn = true { didSet { post.gradeEnabled = gradeOn } }
    var showsStatistics = false {
        didSet {
            if showsStatistics { arView.debugOptions.insert(.showStatistics) } else { arView.debugOptions.remove(.showStatistics) }
        }
    }

    // MARK: World objects

    @ObservationIgnored let arView: ARView
    @ObservationIgnored let post = PostProcessor()
    /// Ambience and effects.
    let sound = SoundEngine()
    @ObservationIgnored private let worldRoot = Entity()
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private let sun = DirectionalLight()
    @ObservationIgnored private var rig = CameraRig()
    @ObservationIgnored private var built = BuiltWorld()
    @ObservationIgnored private var labels: [(view: WorldLabel, spec: FloatingLabel)] = []
    @ObservationIgnored private var gestures = WorldGestures()
    @ObservationIgnored private var updateSubscription: (any Cancellable)?
    @ObservationIgnored let game: GameModel
    /// The truck the camera is following (tap a shipment in the tracker).
    private(set) var followedTruck: Int?

    // Per-frame bookkeeping
    @ObservationIgnored private var time: Float = 0
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var tickTotal: Double = 0   // ms of frame-loop work since the last log line
    @ObservationIgnored private var tickMax: Double = 0
    @ObservationIgnored private var tickFrames = 0
    @ObservationIgnored private let mainLoad = MainThreadLoad()
    @ObservationIgnored private var fpsFrames = 0
    @ObservationIgnored private var fpsTime: Float = 0
    @ObservationIgnored private var fpsLogCounter = 0
    @ObservationIgnored private var clockTimer: Float = 0
    @ObservationIgnored private var lastNight: Float = -1
    @ObservationIgnored private var lighting = DayCycle.state(hour: 12)
    @ObservationIgnored private var shadowScale: Float = 0
    @ObservationIgnored private var cameraView: (V3, V3) = (.zero, .zero)
    @ObservationIgnored private var sunPlacement: (V3, V3) = (.zero, .zero)
    /// Screenshot switches, read once (looking them up every frame cost time).
    @ObservationIgnored private let labelsHidden = UserDefaults.standard.bool(forKey: "hideHUD") || UserDefaults.standard.bool(forKey: "noLabels")

    init(game: GameModel) {
        self.game = game
        let clock = ContinuousClock()
        let start = clock.now
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        configureView()
        let viewReady = clock.now
        buildWorld()
        NSLog("[Waybill] view setup %@, world build %@", "\(viewReady - start)", "\(clock.now - viewReady)")
        gestures.install(on: arView, world: self)
        applyTestOverrides()
        applyTimeOfDay(force: true)
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(dt: Float(event.deltaTime))
        }
        sound.start(region: game.region)
        game.listen { [weak self] event in
            guard let self else { return }
            self.sound.handle(event)
            switch event {
            case .dispatched(let truck, let amount):
                self.built.visuals?.dispatched(amount: amount, at: self.built.fleet?.position(of: truck))
            case .researchDone(let project):
                self.built.research?.reveal(project.id, animated: true)
            case .regionChanged(let id):
                self.sound.setRegion(id)
                self.regionChanged()
            case .caughtUp:
                (self.built.fleet as? YardFleetVisual)?.resync()
            default: break
            }
        }
    }

    // MARK: Setup

    /// Developer hooks via launch arguments, e.g. `-previewHour 21.5 -cameraDistance 70 -cameraYaw 60 -cameraX 0 -cameraZ 14`.
    private func applyTestOverrides() {
        let d = UserDefaults.standard
        if d.object(forKey: "previewHour") != nil {
            previewHour = d.double(forKey: "previewHour")
            timeMode = .preview
        }
        // Numbers can't start with "-" on the command line (that's read as the next flag): write m28 for -28
        func number(_ key: String) -> Float? {
            guard let raw = d.string(forKey: key) else { return nil }
            return Float(raw.hasPrefix("m") ? "-" + raw.dropFirst() : raw)
        }
        let target: V3? = number("cameraX").map { V3($0, 0, number("cameraZ") ?? 0) }
        let yaw: Float? = number("cameraYaw").map(deg)
        let distance: Float? = number("cameraDistance")
        if d.bool(forKey: "closeCamera") { rig.minDistance = 6 }   // `-closeCamera YES`: let tests look up close
        rig.jump(target: target, yaw: yaw, distance: distance)
        if d.bool(forKey: "showStats") { showsStatistics = true }
        if d.bool(forKey: "materialProbe") {
            let m = PhysicallyBasedMaterial()
            NSLog("[Waybill] probe: specular %f tex %@, clearcoat %f, roughness %f, metallic %f, ao tex %@", m.specular.scale, m.specular.texture == nil ? "none" : "set",
                  m.clearcoat.scale, m.roughness.scale, m.metallic.scale, m.ambientOcclusion.texture == nil ? "none" : "set")
        }
        if d.bool(forKey: "aoDebug") { post.debugOcclusion = true }
        if d.bool(forKey: "depthDebug") { post.debugDepth = true }
        if d.bool(forKey: "noAO") { occlusionOn = false }
        if d.bool(forKey: "noGrade") { gradeOn = false }
        if d.bool(forKey: "noAA") { post.antialiasingEnabled = false }
        if d.bool(forKey: "noShadows") { sun.shadow = nil }
        switch d.string(forKey: "renderQuality") {
        case "best": arView.__renderQuality = .best
        case "high": arView.__renderQuality = .high
        case "tier4": arView.__renderQuality = .tier4
        default: break
        }
        if d.object(forKey: "renderScale") != nil { arView.contentScaleFactor = CGFloat(d.double(forKey: "renderScale")) }
        if d.object(forKey: "shadowBias") != nil { sun.shadow?.depthBias = Float(d.double(forKey: "shadowBias")) }
        if d.object(forKey: "snapshot") != nil { // `-snapshot 8`: save what the 3D view shows to Documents/snap.png after 8 s
            let delay = d.double(forKey: "snapshot")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.arView.snapshot(saveToHDR: false) { image in
                    guard let data = image?.pngData() else { NSLog("[Waybill] snapshot failed"); return }
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("snap.png")
                    try? data.write(to: url)
                    NSLog("[Waybill] snapshot saved %@", "\(image?.size ?? .zero)")
                }
            }
        }
        if d.object(forKey: "frameRate") != nil { arView.__preferredFrameRate = Float(d.integer(forKey: "frameRate")) }
    }

    private func configureView() {
        arView.environment.background = .color(Palette.ground)
        if let sky = try? EnvironmentResource(equirectangular: DayCycle.skyImage(), options: .init(samplingQuality: .normal)) {
            arView.environment.lighting.resource = sky
        }
        arView.renderOptions.insert([.disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disableAREnvironmentLighting])
        arView.renderCallbacks = PostProcessor.callbacks(for: post)
        // Ask RealityKit for ProMotion. This is an underscored (semi-private) setting, fine for a personal app.
        arView.__enableAutomaticFrameRate = false
        arView.__preferredFrameRate = 120
    }

    private func buildWorld() {
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)

        camera.camera.fieldOfViewInDegrees = rig.fieldOfView
        camera.camera.near = 4
        camera.camera.far = 1500
        anchor.addChild(camera)

        sun.light.intensity = 3000
        sun.shadow = DirectionalLightComponent.Shadow(shadowProjection: .automatic(maximumDistance: 300), depthBias: 1.5)
        anchor.addChild(sun)

        anchor.addChild(worldRoot)
        buildRegion()
    }

    /// Build the current region's diorama (and tear down the previous one).
    private func buildRegion() {
        for child in Array(worldRoot.children) { child.removeFromParent() }
        for entry in labels { entry.view.removeFromSuperview() }
        labels = []
        built.visuals?.tearDown()
        followedTruck = nil
        game.holdVehicle = nil
        game.holdDock = nil

        if let kind = UserDefaults.standard.string(forKey: "thumbnail") {
            built = Studio.build(kind, into: worldRoot)
            if Studio.showroom { rig.minDistance = 6 }
            if !Studio.showroom {
                arView.environment.background = .color(UIColor(red: 0, green: 1, blue: 0, alpha: 1))
                occlusionOn = false
                gradeOn = false
            }
            rig.setHome(built.home)
            rig.jump(target: built.home.target, yaw: built.home.yaw, distance: built.home.distance)
            return
        }
        switch game.region {
        case .riverside: built = RiversideWorld.build(into: worldRoot, game: game, camera: camera, arView: arView)
        case .harbour: built = HarbourWorld.build(into: worldRoot, game: game, camera: camera, arView: arView)
        case .granite: built = GraniteWorld.build(into: worldRoot, game: game, camera: camera, arView: arView)
        case .metro: built = MetroWorld.build(into: worldRoot, game: game, camera: camera, arView: arView)
        case .orbit: built = OrbitWorld.build(into: worldRoot, game: game, camera: camera, arView: arView)
        }
        rig.setHome(built.home)
        rig.jump(target: built.home.target, yaw: built.home.yaw, distance: built.home.distance)
        built.onHomeChange = { [weak self] home in self?.rig.setHome(home) }
        for spec in built.labels { addLabel(spec) }
        built.research?.onLightsChanged = { [weak self] in
            self?.lastNight = -1
            self?.applyTimeOfDay(force: true)
        }
        // Fleet trucks are created as they join; give each a label
        built.fleet?.onCreate = { [weak self] id, vehicle in
            guard let self, let fleet = self.built.fleet else { return }
            vehicle.setHeadlights(self.lighting.night)
            let code = self.game.config.vehicleCode(id)
            self.addLabel(FloatingLabel(id: code, color: Palette.brand, vehicle: vehicle) { [weak fleet] in fleet?.status(of: id) ?? "" })
        }
        lastNight = -1
        logEntityCount()
    }

    /// How many entities the world has (each one costs main-thread time every frame), and how many draw calls
    /// the visible ones make (one per mesh part, i.e. per material of each model).
    func logEntityCount() {
        var total = 0, models = 0, shown = 0, parts = 0
        var byKind: [String: (models: Int, parts: Int)] = [:]
        func walk(_ e: Entity, visible: Bool) {
            total += 1
            let on = visible && e.isEnabled
            if let m = (e as? ModelEntity)?.model {
                models += 1
                if on {
                    let n = m.mesh.contents.models.reduce(0) { $0 + $1.parts.count }
                    shown += 1; parts += n
                    var kind = e.name.isEmpty ? "" : String(e.name.split(separator: " ").first ?? "")
                    if kind.isEmpty { // name it after its material and its parent
                        let mat = m.materials.first.map { $0 is UnlitMaterial ? "unlit" : ($0 is PhysicallyBasedMaterial ? "pbr" : "other") } ?? "none"
                        let mesh = m.mesh.contents.models.first.map { String($0.id.prefix(12)) } ?? "?"
                        kind = "\(mat):\(mesh)"
                    }
                    byKind[kind, default: (0, 0)].models += 1
                    byKind[kind, default: (0, 0)].parts += n
                }
            }
            for c in e.children { walk(c, visible: on) }
        }
        walk(worldRoot, visible: true)
        NSLog("[Waybill] entities: %d (%d models, %d shown, %d draw calls)", total, models, shown, parts)
        if UserDefaults.standard.bool(forKey: "census") {
            let lines = byKind.sorted { $0.value.parts > $1.value.parts }.prefix(24).map { "\($0.key) \($0.value.models)/\($0.value.parts)" }
            NSLog("[Waybill] draw calls by kind (models/parts): %@", lines.joined(separator: ", "))
        }
    }

    /// Rebuild the world after expanding to a new region.
    func regionChanged() {
        buildRegion()
        applyTimeOfDay(force: true)
        rig.flyIn()
    }

    private func addLabel(_ spec: FloatingLabel) {
        let view = WorldLabel(dotColor: spec.color)
        arView.addSubview(view)
        labels.append((view, spec))
    }

    // MARK: Frame loop

    private func tick(dt rawDt: Float) {
        let started = ContinuousClock.now
        defer {
            let ms = Double((ContinuousClock.now - started) / .microseconds(1)) / 1000
            tickTotal += ms
            tickMax = max(tickMax, ms)
            tickFrames += 1
        }
        let dt = min(max(rawDt, 0), 1 / 15) // avoid jumps after a hitch
        time += dt
        frameCount += 1
        measureFPS(dt)
        if Self.traceSpikes { tracedTick(dt: dt); return }
        game.tick(dt: Double(dt))

        for animator in built.animators { animator.update(dt: dt, time: time) }
        if let id = followedTruck {
            if let p = built.fleet?.position(of: id) { rig.goalTarget = V3(p.x, 0, p.z) } else { followedTruck = nil }
        }
        rig.step(dt: dt)
        let view = (rig.target, rig.position)
        if view != cameraView { // a still camera isn't rewritten
            cameraView = view
            camera.look(at: rig.target, from: rig.position, relativeTo: nil)
        }
        updateSun()
        updateLabels()

        sound.update(dt: Double(dt), night: lighting.night, beep: reverseBeepLevel(), zoom: clamp01((rig.distance - rig.minDistance) / (rig.maxDistance - rig.minDistance)))

        clockTimer += dt
        if timeMode == .live && clockTimer > 1 {
            clockTimer = 0
            applyTimeOfDay(force: false)
        }
    }

    /// `-spikes YES`: time every part of the frame and log frames whose work takes over 3 ms, slowest parts first.
    private static let traceSpikes = UserDefaults.standard.bool(forKey: "spikes")

    private func tracedTick(dt: Float) {
        var parts: [(String, Double)] = []
        func timed(_ name: @autoclosure () -> String, _ body: () -> Void) {
            let t0 = ContinuousClock.now
            body()
            parts.append((name(), Double((ContinuousClock.now - t0) / .microseconds(1)) / 1000))
        }
        timed("game") { game.tick(dt: Double(dt)) }
        for animator in built.animators { timed("\(type(of: animator))") { animator.update(dt: dt, time: time) } }
        timed("camera") {
            if let id = followedTruck {
                if let p = built.fleet?.position(of: id) { rig.goalTarget = V3(p.x, 0, p.z) } else { followedTruck = nil }
            }
            rig.step(dt: dt)
            let view = (rig.target, rig.position)
            if view != cameraView { cameraView = view; camera.look(at: rig.target, from: rig.position, relativeTo: nil) }
            updateSun()
        }
        timed("labels") { updateLabels() }
        timed("sound") { sound.update(dt: Double(dt), night: lighting.night, beep: reverseBeepLevel(), zoom: clamp01((rig.distance - rig.minDistance) / (rig.maxDistance - rig.minDistance))) }
        timed("clock") {
            clockTimer += dt
            if timeMode == .live && clockTimer > 1 { clockTimer = 0; applyTimeOfDay(force: false) }
        }
        let total = parts.reduce(0) { $0 + $1.1 }
        if total > 3 {
            let top = parts.sorted { $0.1 > $1.1 }.prefix(4).map { String(format: "%@ %.2f", $0.0, $0.1) }.joined(separator: ", ")
            NSLog("[Waybill] spike %.2f ms: %@", total, top)
        }
    }

    /// How loud the reversing beeps are: a truck backing into a dock near the middle of the view.
    private func reverseBeepLevel() -> Float {
        guard let fleet = built.fleet else { return 0 }
        var level: Float = 0
        for truck in game.liveFleet {
            guard fleet.isReversing(truck.id), let p = fleet.position(of: truck.id) else { continue }
            let d = simd_distance(SIMD2(p.x, p.z), SIMD2(rig.target.x, rig.target.z))
            level = max(level, clamp01(1 - d / 70))
        }
        return level * (1 - clamp01((rig.distance - 60) / 140))
    }

    private func measureFPS(_ dt: Float) {
        fpsFrames += 1
        fpsTime += dt
        if fpsTime >= 0.5 {
            let measured = Int((Float(fpsFrames) / fpsTime).rounded())
            if measured != fps { fps = measured }
            fpsFrames = 0
            fpsTime = 0
            fpsLogCounter += 1
            if fpsLogCounter % 10 == 0 {
                NSLog("[Waybill] fps %d, thermal %d, low power %@, camera %.0f m at (%.0f, %.0f), frame work %.2f ms avg %.2f max",
                      measured, ProcessInfo.processInfo.thermalState.rawValue,
                      ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off", rig.distance, rig.target.x, rig.target.z,
                      tickTotal / Double(max(tickFrames, 1)), tickMax)
                NSLog("[Waybill] main thread: %@", mainLoad.report())
                if UserDefaults.standard.bool(forKey: "census") { logEntityCount() }
                tickTotal = 0
                tickMax = 0
                tickFrames = 0
            }
        }
    }

    /// The sun follows the camera target so shadows stay sharp wherever you look.
    private func updateSun() {
        let snap: Float = 4 // snapping avoids shadow shimmer while panning
        let center = V3((rig.target.x / snap).rounded() * snap, 0, (rig.target.z / snap).rounded() * snap)
        let placement = (center, lighting.towardsSun)
        if placement != sunPlacement { // moves only when the snapped spot or the time of day changes
            sunPlacement = placement
            sun.look(at: center, from: center + lighting.towardsSun * 200, relativeTo: nil)
        }
        let wanted = rig.distance * 2.2 + 60
        if abs(wanted - shadowScale) > shadowScale * 0.08 {
            shadowScale = wanted
            sun.shadow?.shadowProjection = .automatic(maximumDistance: wanted)
        }
    }

    private func updateLabels() {
        let bounds = arView.bounds
        let fade = 1 - clamp01((rig.distance - rig.home.distance - 35) / 50) // labels fade out when zoomed out past the home view
        // Keep labels out from under the top bar, the camera buttons and the bottom panels
        let clearArea = CGRect(x: 20, y: 86, width: bounds.width - 110, height: bounds.height - 110)
        let showing = fade > 0.01 && !labelsHidden
        for entry in labels {
            let v = entry.spec.vehicle
            guard showing, v.root.isEnabled, v.root.parent != nil,
                  let point = arView.project(v.root.convert(position: v.labelAnchor, to: nil)), clearArea.contains(point) else {
                if !entry.view.isHidden { entry.view.isHidden = true }
                continue
            }
            if entry.view.isHidden { entry.view.isHidden = false }
            let alpha = CGFloat(fade)
            if entry.view.alpha != alpha { entry.view.alpha = alpha }
            entry.view.set(id: entry.spec.id, status: entry.spec.status())
            let center = CGPoint(x: point.x, y: point.y - 16)
            if entry.view.center != center { entry.view.center = center }
        }
    }

    // MARK: Day & night

    private func applyTimeOfDay(force: Bool) {
        let hour = timeMode == .live ? DayCycle.currentHour() : previewHour
        if abs(hour - shownHour) > 0.001 || force { shownHour = hour }
        lighting = DayCycle.state(hour: hour, ground: built.ground)

        sun.light.color = lighting.sunColor
        sun.light.intensity = lighting.sunIntensity
        arView.environment.lighting.intensityExponent = lighting.ambient
        if UserDefaults.standard.bool(forKey: "shadowTest") { // debug: sky light off, only the sun
            arView.environment.lighting.intensityExponent = -6
            sun.light.intensity = 9000
        }
        if UserDefaults.standard.string(forKey: "thumbnail") == nil || Studio.showroom { arView.environment.background = .color(lighting.background) }
        updateSun()

        let night = lighting.night
        post.bloomStrength = night
        guard force || abs(night - lastNight) > 0.01 else { return }
        lastNight = night
        let windowMat = Materials.glowing(base: Palette.glass.mixed(with: Palette.windowGlow, CGFloat(night * 0.6)),
                                          glow: Palette.windowGlow, intensity: night * 2.4)
        for w in built.site.windows { w.model?.materials = [windowMat] }
        if !built.site.facadeGlass.isEmpty {
            let glass = Materials.facadeGlass(night: night)
            for w in built.site.facadeGlass { w.model?.materials = [glass] }
        }
        let lampMat = Materials.glowing(base: UIColor(hex: 0xF4F1E6), glow: Palette.lampGlow, intensity: night * 7)
        for lamp in built.site.lampHeads { lamp.model?.materials = [lampMat] }
        for pool in built.site.lightPools { pool.components.set(OpacityComponent(opacity: night)) }
        for vehicle in built.vehicles { vehicle.setHeadlights(night) }
        built.fleet?.setHeadlights(night)
    }

    // MARK: Camera commands (buttons)

    func zoomIn() { rig.zoom(to: rig.goalDistance * 0.7, anchor: nil) }
    func zoomOut() { rig.zoom(to: rig.goalDistance / 0.7, anchor: nil) }
    func rotateLeft() { rig.rotate(snapBy: deg(45)) }
    func rotateRight() { rig.rotate(snapBy: -deg(45)) }
    func goHome() { followedTruck = nil; rig.goHome() }

    /// Glide to where a research project changed the world.
    func show(research id: String) {
        guard let p = built.research?.focus(id) else { return }
        followedTruck = nil
        rig.goalTarget = V3(p.x, 0, p.z)
        rig.goalDistance = min(rig.goalDistance, 90)
    }

    /// Glide to the warehouse (Riverside), e.g. when an expansion starts.
    func showWarehouse() {
        guard let view = built.warehouseView?() else { return }
        followedTruck = nil
        rig.goalTarget = view.target
        rig.goalDistance = view.distance
        rig.goalYaw = rig.yaw + angleDelta(rig.yaw, rig.home.yaw)
    }

    /// Glide to a truck and keep it in view until you touch the map.
    func follow(truck id: Int) {
        guard built.fleet?.position(of: id) != nil else { return }
        followedTruck = id
        rig.goalDistance = min(rig.goalDistance, 82)
    }
    func flyIn() { rig.flyIn() }
    /// A short glide back into the current view (after the loading screen when you come back to the app).
    func settle() { rig.settle() }

    /// Wait until the world has drawn `frames` more frames, so first-frame hitches (shader set-up, uploads)
    /// happen behind the loading screen. Gives up after `timeout` (e.g. when nothing is rendering).
    func warmUp(frames: Int, timeout: Duration = .seconds(4)) async {
        let target = frameCount + frames
        let deadline = ContinuousClock.now + timeout
        while frameCount < target, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: Gesture plumbing (called by WorldGestures)

    /// The point on the ground under a screen position.
    func groundPoint(at screen: CGPoint) -> V3? {
        guard let ray = arView.ray(through: screen), abs(ray.direction.y) > 0.0001 else { return nil }
        let t = -ray.origin.y / ray.direction.y
        return t > 0 ? ray.origin + ray.direction * t : nil
    }

    func beginDrag() {
        followedTruck = nil
        rig.isDragging = true
        rig.velocity = .zero
    }

    func drag(from a: CGPoint, to b: CGPoint) {
        guard let pa = groundPoint(at: a), let pb = groundPoint(at: b) else { return }
        rig.pan(by: pa - pb)
    }

    func endDrag(at point: CGPoint, velocity: CGPoint) {
        rig.isDragging = false
        let ahead = CGPoint(x: point.x + velocity.x / 60, y: point.y + velocity.y / 60)
        guard let pa = groundPoint(at: point), let pb = groundPoint(at: ahead) else { return }
        var v = SIMD2<Float>(pa.x - pb.x, pa.z - pb.z) * 60
        let maxSpeed: Float = 260
        if simd_length(v) > maxSpeed { v = simd_normalize(v) * maxSpeed }
        rig.velocity = v
    }

    @ObservationIgnored private var pinchStart: Float = 0
    func beginPinch() { pinchStart = rig.goalDistance }
    func pinch(scale: CGFloat, center: CGPoint) {
        rig.zoom(to: pinchStart / Float(max(scale, 0.01)), anchor: groundPoint(at: center))
    }

    @ObservationIgnored private var rotateStart: Float = 0
    func beginRotate() { rotateStart = rig.goalYaw }
    func rotate(by radians: CGFloat) { rig.goalYaw = rotateStart - Float(radians) }

    func scrollZoom(delta: CGFloat, at point: CGPoint) {
        rig.zoom(to: rig.goalDistance * exp(Float(delta) * 0.004), anchor: groundPoint(at: point))
    }
}

/// Touch, trackpad and mouse gestures on the 3D view.
final class WorldGestures: NSObject, UIGestureRecognizerDelegate {
    private weak var world: WorldController?
    private var lastPan: CGPoint = .zero
    private var lastTouchCount = 0

    func install(on view: UIView, world: WorldController) {
        self.world = world
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.maximumNumberOfTouches = 0
        for recognizer in [pan, pinch, rotate, scroll] as [UIGestureRecognizer] {
            recognizer.delegate = self
            // The 3D view needs no touches of its own. Letting UIKit hold touches back while four gestures
            // recognise together crashed iPadOS (NSInvalidArgumentException in _delayTouchesForEvent).
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.cancelsTouchesInView = false
            view.addGestureRecognizer(recognizer)
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let world, let view = g.view else { return }
        let p = g.location(in: view)
        switch g.state {
        case .began:
            world.beginDrag()
            lastPan = p
            lastTouchCount = g.numberOfTouches
        case .changed:
            // When a finger is added or lifted the centre jumps: re-anchor instead of jumping the camera
            if g.numberOfTouches != lastTouchCount {
                lastTouchCount = g.numberOfTouches
                lastPan = p
                return
            }
            world.drag(from: lastPan, to: p)
            lastPan = p
        case .ended, .cancelled:
            world.endDrag(at: p, velocity: g.state == .ended ? g.velocity(in: view) : .zero)
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let world, let view = g.view else { return }
        switch g.state {
        case .began: world.beginPinch()
        case .changed: world.pinch(scale: g.scale, center: g.location(in: view))
        default: break
        }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard let world else { return }
        switch g.state {
        case .began: world.beginRotate()
        case .changed: world.rotate(by: g.rotation)
        default: break
        }
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        guard let world, let view = g.view, g.state == .changed else { return }
        world.scrollZoom(delta: g.translation(in: view).y, at: g.location(in: view))
        g.setTranslation(.zero, in: view)
    }
}

/// A small floating tag above a vehicle, drawn by UIKit on top of the 3D view.
final class WorldLabel: UIView {
    private let dot = UIView()
    private let label = UILabel()
    private var current = ""

    init(dotColor: UIColor) {
        super.init(frame: CGRect(x: 0, y: 0, width: 120, height: 24))
        isUserInteractionEnabled = false
        backgroundColor = UIColor.white.withAlphaComponent(0.95)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.shadowColor = Palette.brandDeep.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        dot.backgroundColor = dotColor
        dot.layer.cornerRadius = 3.5
        addSubview(dot)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func set(id: String, status: String) {
        let text = "\(id)|\(status)"
        guard text != current else { return }
        current = text
        let s = NSMutableAttributedString(string: id, attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: Palette.ink,
        ])
        s.append(NSAttributedString(string: "  \(status)", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor(hex: 0x6B7186),
        ]))
        label.attributedText = s
        let width = ceil(label.intrinsicContentSize.width) + 30
        let c = center
        bounds = CGRect(x: 0, y: 0, width: width, height: 24)
        center = c
        dot.frame = CGRect(x: 10, y: 8.5, width: 7, height: 7)
        label.frame = CGRect(x: 22, y: 0, width: width - 30, height: 24)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath
    }
}

/// Measures how busy the main thread is: every run-loop pass, and the long ones that can cost a frame.
final class MainThreadLoad {
    private var passStart: CFAbsoluteTime = 0
    private var busy: Double = 0
    private var longPasses = 0
    private var longest: Double = 0
    private var since = CFAbsoluteTimeGetCurrent()

    init() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if activity == .afterWaiting {
                self.passStart = now
            } else if self.passStart > 0 {
                let ms = (now - self.passStart) * 1000
                self.busy += ms
                self.longest = max(self.longest, ms)
                if ms > 8 { self.longPasses += 1 }
                self.passStart = 0
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func report() -> String {
        let seconds = max(CFAbsoluteTimeGetCurrent() - since, 0.001)
        let text = String(format: "busy %.0f%%, passes over 8 ms: %.1f/s, longest %.1f ms", busy / seconds / 10, Double(longPasses) / seconds, longest)
        busy = 0; longPasses = 0; longest = 0; since = CFAbsoluteTimeGetCurrent()
        return text
    }
}
