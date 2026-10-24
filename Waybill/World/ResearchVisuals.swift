import RealityKit
import UIKit

/// Research you can see: every finished project adds something to the diorama.
/// New things grow out of the ground with a little overshoot; things already researched are there from the start.
final class ResearchVisuals: WorldAnimator {
    /// Builds the visual for a project. Return the entity to grow in (or nil for changes to existing things).
    typealias Builder = (ResearchVisuals) -> Entity?

    let root: Entity
    let site: SiteParts
    private var builders: [String: Builder] = [:]
    private var focusPoints: [String: (point: V3, parent: Entity?)] = [:]
    private var parents: [String: Entity] = [:]
    private(set) var revealed: Set<String> = []
    private var growing: [(entity: Entity, t: Float, delay: Float)] = []
    private var extra: [WorldAnimator] = []
    /// Lamps or windows were added: the controller re-applies the night lighting.
    var onLightsChanged: (() -> Void)?

    init(root: Entity, site: SiteParts) {
        self.root = root
        self.site = site
    }

    /// - parent: build the visual inside this entity (it moves with it, e.g. the hall's east end); `focus` is then local to it.
    func register(_ id: String, focus: V3, parent: Entity? = nil, _ builder: @escaping Builder) {
        builders[id] = builder
        focusPoints[id] = (focus, parent)
        if let parent { parents[id] = parent }
    }

    /// Where to look at a project's visual, in world coordinates.
    func focus(_ id: String) -> V3? {
        guard let f = focusPoints[id] else { return nil }
        guard let parent = f.parent else { return f.point }
        return parent.convert(position: f.point, to: nil)
    }

    /// Animators that come with a visual (a conveyor belt, a spinning turbine).
    func animate(_ animator: WorldAnimator) { extra.append(animator) }

    func reveal(_ id: String, animated: Bool) {
        guard !revealed.contains(id), let build = builders[id] else { return }
        revealed.insert(id)
        guard let entity = build(self) else { return }
        (parents[id] ?? root).addChild(entity)
        if animated {
            entity.scale = [0.94, 0.001, 0.94]
            growing.append((entity, 0, 0.15))
        }
    }

    func update(dt: Float, time: Float) {
        for a in extra { a.update(dt: dt, time: time) }
        guard !growing.isEmpty else { return }
        for i in growing.indices {
            growing[i].t += dt
            let u = clamp01((growing[i].t - growing[i].delay) / 1.1)
            let y = smootherstep(u) + sin(u * .pi) * 0.14
            let xz = 0.94 + 0.06 * smootherstep(u)
            growing[i].entity.scale = [xz, max(y, 0.001), xz]
        }
        growing.removeAll { $0.t > $0.delay + 1.1 }
    }
}

/// Moves small boxes along a straight belt, looping (they vanish into a wall at the end).
final class ConveyorAnimator: WorldAnimator {
    private let boxes: [Entity]
    private let from: V3
    private let to: V3
    private let speed: Float
    private var offset: Float = 0

    init(boxes: [Entity], from: V3, to: V3, speed: Float) {
        self.boxes = boxes
        self.from = from
        self.to = to
        self.speed = speed
    }

    func update(dt: Float, time: Float) {
        let length = simd_distance(from, to)
        offset = (offset + speed * dt).truncatingRemainder(dividingBy: length)
        let spacing = length / Float(boxes.count)
        for (i, box) in boxes.enumerated() {
            let s = (offset + Float(i) * spacing).truncatingRemainder(dividingBy: length)
            box.position = lerp(from, to, s / length)
            // Pop in at the start, shrink at the end
            let edge = min(s, length - s)
            let scale = min(edge / 0.6, 1)
            box.scale = V3(repeating: max(scale, 0.001) * Props.toyScale)
        }
    }
}

/// Slowly turning blades (wind turbines, fans).
final class SpinAnimator: WorldAnimator {
    private let entity: Entity
    private let axis: V3
    private let speed: Float
    init(_ entity: Entity, axis: V3, speed: Float) {
        self.entity = entity
        self.axis = axis
        self.speed = speed
    }
    func update(dt: Float, time: Float) {
        entity.orientation = simd_quatf(angle: time * speed, axis: axis)
    }
}
