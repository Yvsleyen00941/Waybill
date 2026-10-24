import RealityKit
import UIKit

/// Renders one vehicle on a green background (launch argument `-thumbnail truck`), used to make the
/// little vehicle pictures in the Shipment Tracking card. See README › Thumbnails.
enum Studio {
    /// `-showroom YES`: a normal lit floor instead of the green screen, to check models up close.
    static var showroom: Bool { UserDefaults.standard.bool(forKey: "showroom") }

    static func build(_ kind: String, into root: Entity) -> BuiltWorld {
        let world = BuiltWorld()
        let holder = Entity()
        root.addChild(holder)
        var size: Float = 10
        switch kind {
        case "hauler":
            let v = Vehicles.hauler(index: 0)
            v.cargo?.isEnabled = true
            holder.addChild(v.root); size = 17
        case "train":
            holder.addChild(Trains.locomotive().root); size = 16
        case "trainset":
            let loco = Trains.locomotive()
            holder.addChild(loco.root)
            for (i, kind) in [Trains.WagonKind.crates, .container, .boxcar].enumerated() {
                let w = Trains.wagon(kind, seed: i)
                w.cargo?.isEnabled = true
                w.root.position = [-Trains.locoLength / 2 - Trains.gap - Trains.wagonLength * (Float(i) + 0.5) - Trains.gap * Float(i), 0, 0]
                holder.addChild(w.root)
            }
            holder.position = [20, 0, 0]
            size = 30
        case "harbour":
            let h = Vehicles.hauler(index: 1)
            h.cargo?.isEnabled = true
            holder.addChild(h.root)
            let sc = Vehicles.straddleCarrier()
            sc.root.position = [0, 0, -10]
            holder.addChild(sc.root)
            let (rs, _) = Vehicles.reachStacker()
            rs.root.position = [-4, 0, 9]
            holder.addChild(rs.root)
            size = 22
        case "van":
            holder.addChild(Vehicles.van(index: 0).root); size = 6.5
        case "forklift":
            holder.addChild(Vehicles.forklift().root); size = 4.5
        case "car":
            holder.addChild(Vehicles.car(.carCoral).root); size = 5
        case "person":
            holder.addChild(Vehicles.person().root); size = 2.4
        case "walk": // animation checks: a worker walking a loop, one waving a truck back, one standing
            let walker = Vehicles.person()
            holder.addChild(walker.root)
            let loop = DrivePath([[-3, 0, -1.5], [3, 0, -1.5], [3.6, 0, 0], [3, 0, 1.5], [-3, 0, 1.5], [-3.6, 0, 0], [-3, 0, -1.5]])
            let driver = VehicleDriver(walker, legs: [.drive(loop, speed: 1.25), .wait(1.5)])
            world.animators += [driver, PersonAnimator(walker)]
            let marshal = Vehicles.person(vest: .hiVis, helmet: .white)
            marshal.root.position = [0, 0, -4.5]
            marshal.root.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            holder.addChild(marshal.root)
            let waving = PersonAnimator(marshal)
            waving.gesture = .waveBack
            world.animators.append(waving)
            let idle = Vehicles.person(vest: .brand)
            idle.root.position = [0, 0, 4.2]
            holder.addChild(idle.root)
            world.animators.append(PersonAnimator(idle, seed: 1))
            size = 6
        case "lineup": // everything side by side (showroom checks)
            let items: [(Entity, Float)] = [(Vehicles.truck(.waybill).root, 0), (Vehicles.truck(.nordway).root, 4),
                                            (Vehicles.forklift().root, 8.5), (Vehicles.car(.carCoral).root, 12), (Vehicles.person().root, 15)]
            for (e, z) in items { e.position = [0, 0, z]; holder.addChild(e) }
            holder.position = [0, 0, -7.5]
            size = 16
        case "rocket":
            let (r, _) = Rockets.rocket(stretched: false)
            r.root.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
            r.root.position = [-28, 2.4, 0]
            holder.addChild(r.root); size = 58
        default:
            holder.addChild(Vehicles.truck(.waybill).root); size = 10
        }
        if showroom {
            Geo.part(root, .generatePlane(width: 400, depth: 400), .yard, at: [0, 0, 0])
            world.home = CameraHome(target: V3(0, size * 0.12, 0), yaw: deg(38), distance: max(14, size * 1.9))
            return world
        }
        // No ground shadows on the green screen
        func strip(_ e: Entity) {
            for child in e.children {
                if let m = child as? ModelEntity, m.model?.materials.first is UnlitMaterial { m.isEnabled = false }
                strip(child)
            }
        }
        strip(holder)
        world.home = CameraHome(target: V3(0, size * 0.12, 0), yaw: deg(38), distance: max(38, size * 2.6))
        return world
    }
}
