import RealityKit
import UIKit
import simd

// Yard traffic: trucks that never drive through each other.
//
// Every truck drives along a path with real speed (accelerating, braking). Each frame it looks ahead along
// its path and brakes for anything in the way: another truck, or space another truck has claimed.
// Manoeuvres that cross the lane (backing into a bay, pulling out and driving to the exit) first claim the
// whole area they sweep; the claim is only granted when that area is empty, and released bit by bit as the
// truck moves through it. Trucks that haven't claimed anything keep out of claimed and requested space.
// That is enough to keep a busy yard moving without collisions or gridlock.

// MARK: - Grid

/// A coarse grid over the ground (1 m cells) that records who is where and who has claimed what.
final class YardGrid {
    let originX: Float, originZ: Float
    let width: Int, height: Int
    /// Truck standing on the cell this frame (truck id + 1, 0 = free).
    var occupied: [Int16]
    /// Cell claimed by a granted manoeuvre (truck id + 1).
    var reserved: [Int16]
    /// Cells wanted by pending manoeuvres (one bit per truck).
    var requested: [UInt32]
    /// Scratch marks for overlap tests.
    var mark: [UInt32]
    var generation: UInt32 = 0

    init(origin: SIMD2<Float> = SIMD2(-240, -24), size: (Int, Int) = (480, 90)) {
        originX = origin.x
        originZ = origin.y
        (width, height) = size
        occupied = Array(repeating: 0, count: width * height)
        reserved = Array(repeating: 0, count: width * height)
        requested = Array(repeating: 0, count: width * height)
        mark = Array(repeating: 0, count: width * height)
    }

    @inline(__always) func cell(_ x: Int, _ z: Int) -> Int32? {
        guard x >= 0, z >= 0, x < width, z < height else { return nil }
        return Int32(z * width + x)
    }

    /// Cells covered by a truck-sized rectangle centred at `p`, long axis along `dir`.
    func rectangle(center p: SIMD2<Float>, dir: SIMD2<Float>, halfLength: Float, halfWidth: Float, into out: inout [Int32]) {
        let u = dir, v = SIMD2<Float>(-dir.y, dir.x)
        let m: Float = 0.35
        let ex = abs(u.x) * halfLength + abs(v.x) * halfWidth + 1
        let ez = abs(u.y) * halfLength + abs(v.y) * halfWidth + 1
        let x0 = Int(floor(p.x - ex - originX)), x1 = Int(ceil(p.x + ex - originX))
        let z0 = Int(floor(p.y - ez - originZ)), z1 = Int(ceil(p.y + ez - originZ))
        for z in z0...z1 {
            for x in x0...x1 {
                let c = SIMD2<Float>(originX + Float(x) + 0.5, originZ + Float(z) + 0.5) - p
                if abs(simd_dot(c, u)) <= halfLength + m, abs(simd_dot(c, v)) <= halfWidth + m, let id = cell(x, z) { out.append(id) }
            }
        }
    }
}

/// A drive path with the grid cells a truck covers at every half metre along it (worked out once).
final class TrackedPath {
    let path: DrivePath
    let step: Float = 0.5
    let count: Int
    private var flat: [Int32] = []
    private var offsets: [Int] = [0]

    /// - reverse: driven backwards (the truck faces against the path). - centerOffset: the path is followed by the
    ///   rear axle; the middle of the truck is this far ahead of it.
    /// - reverse: driven backwards (the truck faces against the path). - centerOffset: the path is followed by the
    ///   rear axle; the middle of the truck is this far ahead of it. - tail: an articulated vehicle's trailer, which
    ///   follows the path behind the tractor: the footprint also covers the path this far back.
    init(_ path: DrivePath, grid: YardGrid, halfLength: Float, halfWidth: Float, reverse: Bool = false, centerOffset: Float = 0,
         trailer: YardLayout.TrailerShape? = nil) {
        self.path = path
        count = max(Int(path.length / step) + 1, 2)
        var scratch: [Int32] = []
        var axle: SIMD2<Float>?                    // the trailer's axles, simulated along the path from straight
        for i in 0..<count {
            let (p, t) = path.sample(Float(i) * step)
            var d = simd_length(SIMD2(t.x, t.z)) > 0.001 ? simd_normalize(SIMD2(t.x, t.z)) : SIMD2<Float>(1, 0)
            if reverse { d = -d }
            scratch.removeAll(keepingCapacity: true)
            grid.rectangle(center: SIMD2(p.x, p.z) + d * centerOffset, dir: d, halfLength: halfLength, halfWidth: halfWidth, into: &scratch)
            if let tr = trailer {
                // An articulated vehicle's trailer cuts inside every turn: follow it exactly (the same pulling as
                // `Vehicle.updateTrailer`), so the claimed space is where the trailer really goes
                let hitch = SIMD2(p.x, p.z) + d * tr.hitch
                if let a = axle, simd_length(hitch - a) > 0.001 { axle = hitch - simd_normalize(hitch - a) * tr.length } else { axle = hitch - d * tr.length }
                let e = simd_normalize(hitch - axle!)
                grid.rectangle(center: hitch - e * ((tr.back - tr.front) / 2), dir: e, halfLength: (tr.back + tr.front) / 2, halfWidth: halfWidth, into: &scratch)
                scratch = Array(Set(scratch))
            }
            flat += scratch
            offsets.append(flat.count)
        }
    }

    var length: Float { path.length }
    @inline(__always) func index(_ s: Float) -> Int { min(max(Int((s / step).rounded()), 0), count - 1) }
    @inline(__always) func cells(_ i: Int) -> ArraySlice<Int32> { flat[offsets[i]..<offsets[i + 1]] }
    /// First sample at or after distance `s` where `test` holds (or nil).
    func firstIndex(from s: Float, where test: (V3) -> Bool) -> Int? {
        for i in index(s)..<count where test(path.sample(Float(i) * step).position) { return i }
        return nil
    }
}

/// Space a truck wants for a manoeuvre: pending until the space is free, then granted and released as it goes.
/// A manoeuvre can run over several paths in a row (pull forward and swing out, then back in).
final class Claim {
    enum Kind { case reverse, depart }
    let owner: Int
    let kind: Kind
    let paths: [TrackedPath]
    private(set) var cells: [Int32] = []
    /// Per path: (cell, last sample covering it) sorted by sample, leaving out cells a later path still needs.
    private var steps: [[(cell: Int32, last: Int)]] = []
    private var released: [Int] = []
    var granted = false
    /// When it was requested (yard time).
    var since: Float = 0

    init(owner: Int, kind: Kind, segments: [(path: TrackedPath, from: Int, to: Int)]) {
        self.owner = owner
        self.kind = kind
        paths = segments.map(\.path)
        var perSegment: [[Int32: Int]] = []
        for seg in segments {
            var lastIndex: [Int32: Int] = [:]
            for i in max(seg.from, 0)...min(seg.to, seg.path.count - 1) { for c in seg.path.cells(i) { lastIndex[c] = i } }
            perSegment.append(lastIndex)
        }
        var all = Set<Int32>()
        for k in perSegment.indices.reversed() {
            let later = all
            steps.insert(perSegment[k].filter { !later.contains($0.key) }.map { ($0.key, $0.value) }.sorted { $0.last < $1.last }, at: 0)
            all.formUnion(perSegment[k].keys)
        }
        cells = Array(all)
        released = Array(repeating: 0, count: steps.count)
    }

    convenience init(owner: Int, kind: Kind, path: TrackedPath, from: Int, to: Int) {
        self.init(owner: owner, kind: kind, segments: [(path, from, to)])
    }

    func request(_ g: YardGrid) { let bit = UInt32(1) << UInt32(owner); for c in cells { g.requested[Int(c)] |= bit } }
    func withdraw(_ g: YardGrid) { let bit = ~(UInt32(1) << UInt32(owner)); for c in cells { g.requested[Int(c)] &= bit } }

    func grant(_ g: YardGrid) {
        withdraw(g)
        let me = Int16(owner + 1)
        for c in cells { g.reserved[Int(c)] = me }
        granted = true
    }

    func covers(_ path: TrackedPath) -> Bool { paths.contains { $0 === path } }

    /// Give back the cells the truck has left behind on `path` (and everything of the paths before it).
    func release(on path: TrackedPath, upTo index: Int, _ g: YardGrid) {
        guard let k = paths.firstIndex(where: { $0 === path }) else { return }
        for j in 0..<k { releaseStep(j, upTo: Int.max, g) }
        releaseStep(k, upTo: index, g)
    }

    private func releaseStep(_ k: Int, upTo index: Int, _ g: YardGrid) {
        let me = Int16(owner + 1)
        while released[k] < steps[k].count, steps[k][released[k]].last < index {
            let c = Int(steps[k][released[k]].cell)
            if g.reserved[c] == me { g.reserved[c] = 0 }
            released[k] += 1
        }
    }

    func releaseAll(_ g: YardGrid) {
        if granted { for k in steps.indices { releaseStep(k, upTo: Int.max, g) } } else { withdraw(g) }
    }
}

// MARK: - Layout

/// Where trucks drive in a yard with a row of bays (Riverside).
struct YardLayout {
    /// From off-map, in through the gate and along the yard lane (trucks queue on it).
    var approach: DrivePath
    /// Per bay (index 0 = bay 1): door x, where trucks stop before backing in, the reverse path, the way out.
    var bayX: [Float]
    var turnPoints: [Float]          // distance along `approach` where the bay manoeuvre starts
    /// Per bay: pull forward past the bay and swing the cab out (ends where the truck stops to reverse).
    var setup: [DrivePath]
    var reverse: [DrivePath]
    var depart: [DrivePath]
    /// Distance along each departure after which the truck is out of the yard (no claim needed beyond).
    var departClaimEnd: [Float]
    /// Distance along `approach` of the waiting line's front, for the open bays.
    var queueFront: (Set<Int>) -> Float
    var queueSpacing: Float = 12
    /// Speed limit (m/s) at a point.
    var limit: (V3) -> Float
    var reverseSpeed: Float = 2.5
    /// The paths are followed by the truck's rear axle (like a real rigid truck: the back follows the line, the cab
    /// swings wide). How far ahead of it the truck's origin and the middle of its body are.
    var axleToOrigin: Float = 0
    var axleToCenter: Float = 0
    /// Vehicle footprint (half length and width around its middle) and, for articulated vehicles, the trailer.
    var halfLength: Float = 4.85
    var halfWidth: Float = 1.45
    /// A semi-trailer: fifth wheel this far ahead of the rear axle, kingpin to trailer axles, how far the trailer
    /// reaches ahead of the kingpin and behind it.
    struct TrailerShape { var hitch: Float; var length: Float; var front: Float; var back: Float }
    var trailer: TrailerShape?
    /// Where the waiting line's spot `k` is along the approach, for the open bays (default: one behind the other from
    /// `queueFront`, `queueSpacing` apart).
    var queueSpot: ((Int, Set<Int>) -> Float)?
    /// Bays you drive into forwards (container lanes, van bays): the set-up path ends at the stop, no reversing.
    var driveThrough = false
    /// Area the traffic grid covers (1 m cells).
    var gridOrigin = SIMD2<Float>(-240, -24)
    var gridSize = (480, 90)
    /// The bay (index into the per-bay paths) of each dock of the economy, and what the bays are called.
    var bayOfDock: (Int) -> Int = { $0 }
    var bayName: (Int) -> String = { "Bay \($0 + 1)" }
    /// Where a truck may appear (beyond what the camera shows), and where it counts as back (in through the gate).
    var mayAppear: (V3) -> Bool = { _ in true }
    var inYard: (V3) -> Bool = { _ in true }
    /// Show the vehicle's cargo only once it's loaded (a container on a hauler).
    var showsCargo = false
}

// MARK: - The fleet in the yard

/// Shows the game's trucks in a yard with several bays. Each truck's state in the economy decides where it
/// wants to be (queue, bay, road); the yard traffic decides how it gets there without hitting anyone.
final class YardFleetVisual: FleetDisplay {
    final class Truck {
        enum Mode { case hidden, approach, setup, reversing, docked, departing, through }
        let id: Int
        let vehicle: Vehicle
        let mover: PlannedMover
        var mode: Mode = .hidden
        var path: TrackedPath?
        var reversing = false
        var s: Float = 0
        var v: Float = 0
        var stop: Float?
        var bay = -1                 // bay index while reversing, docked or departing
        var claim: Claim?
        var cells: [Int32] = []
        var stuck: Float = 0
        var ghost: Float = 0
        /// Who is in the way right now (truck id), to tell a queue from gridlock.
        var blockedBy: Int?
        var catchUp: Float = 1
        var claimBlocker: Int?
        var blockInfo = ""
        var status = ""
        var fresh = true             // not placed yet (first frame after the world is built)
        var pause: Float = 0         // standing still a moment (shifting into reverse)
        /// How far ahead of the path point the vehicle's origin is (the fleet's rear axle; 0 for passing traffic).
        var originOffset: Float = 0
        var cruise: Float = 0        // passing traffic: its own speed
        init(id: Int, vehicle: Vehicle) {
            self.id = id
            self.vehicle = vehicle
            mover = PlannedMover(vehicle)
        }
        var visible: Bool { mode != .hidden }
        var position: V3 { vehicle.root.position }
    }


    private let game: GameModel
    private let layout: YardLayout
    private let root: Entity
    private let make: () -> Vehicle
    private let grid: YardGrid
    private let approach: TrackedPath
    private let setupPaths: [TrackedPath]
    private let reversePaths: [TrackedPath]
    private let departPaths: [TrackedPath]
    private var trucks: [Int: Truck] = [:]
    private var pending: [Claim] = []
    private var arrivalPlans: [Int: MotionPlan] = [:]
    private var time: Float = 0
    private var decorators: [(key: String, apply: (Vehicle) -> Void)] = []
    var onCreate: ((Int, Vehicle) -> Void)?
    /// True while something is still working inside the truck at a bay (it waits before pulling out).
    var bayBusy: ((Int) -> Bool)?
    /// Per bay: what's happening there (the warehouse opens doors and switches signals from this).
    private(set) var dockStates: [Warehouse.DockState]
    /// Per bay: loading progress of the truck there (nil = nobody loading). Drives the pallet trucks.
    private(set) var dockLoading: [Float?]

    init(game: GameModel, layout: YardLayout, root: Entity, make: @escaping () -> Vehicle) {
        self.game = game
        self.layout = layout
        self.root = root
        self.make = make
        grid = YardGrid(origin: layout.gridOrigin, size: layout.gridSize)
        let hl = layout.halfLength, hw = layout.halfWidth, g = grid, c = layout.axleToCenter, tr = layout.trailer
        approach = TrackedPath(layout.approach, grid: g, halfLength: hl, halfWidth: hw, centerOffset: c, trailer: tr)
        setupPaths = layout.setup.map { TrackedPath($0, grid: g, halfLength: hl, halfWidth: hw, centerOffset: c, trailer: tr) }
        reversePaths = layout.reverse.map { TrackedPath($0, grid: g, halfLength: hl, halfWidth: hw, reverse: true, centerOffset: c, trailer: tr) }
        departPaths = layout.depart.map { TrackedPath($0, grid: g, halfLength: hl, halfWidth: hw, centerOffset: c, trailer: tr) }
        dockStates = [Warehouse.DockState](repeating: .empty, count: layout.bayX.count)
        dockLoading = [Float?](repeating: nil, count: layout.bayX.count)
    }

    func decorate(_ key: String, _ apply: @escaping (Vehicle) -> Void) {
        guard !decorators.contains(where: { $0.key == key }) else { return }
        decorators.append((key, apply))
        for t in trucks.values { apply(t.vehicle) }
    }

    private func truck(_ id: Int) -> Truck {
        if let t = trucks[id] { return t }
        let v = make()
        for d in decorators { d.apply(v) }
        v.root.isEnabled = false
        root.addChild(v.root)
        let t = Truck(id: id, vehicle: v)
        t.originOffset = layout.axleToOrigin
        trucks[id] = t
        onCreate?(id, v)
        return t
    }

    // MARK: FleetDisplay

    func position(of id: Int) -> V3? {
        guard let t = trucks[id], t.visible else { return nil }
        return t.position
    }
    func status(of id: Int) -> String { trucks[id]?.status ?? "" }
    func setHeadlights(_ level: Float) { for t in trucks.values { t.vehicle.setHeadlights(level) } }
    func isReversing(_ id: Int) -> Bool { trucks[id].map { $0.mode == .reversing && $0.v > 0.05 } ?? false }
    var visiblePositions: [V3] { trucks.values.filter(\.visible).map(\.position) }

    /// Passing traffic on the public road (rival trucks, cars): it loops along its lane at its own speed, keeps its
    /// distance, stops for the fleet's trucks and for the space they have claimed (pulling out across the road), and
    /// the fleet's trucks brake for it in turn. Ids from 24 up (the fleet's are lower).
    func addThroughTraffic(_ vehicle: Vehicle, lane: DrivePath, startAt s0: Float, speed: Float, halfLength: Float) {
        let id = 24 + guests
        guests += 1
        guard id < 32 else { return }                        // claim bookkeeping has 32 slots
        let t = Truck(id: id, vehicle: vehicle)
        t.cruise = speed
        t.originOffset = 0
        t.fresh = false
        root.addChild(vehicle.root)
        trucks[id] = t
        let path = TrackedPath(lane, grid: grid, halfLength: halfLength, halfWidth: 1.3)
        place(t, on: path, s: s0.truncatingRemainder(dividingBy: max(lane.length, 1)), mode: .through)
        t.v = speed
    }
    private var guests = 0

    /// The docking the dock marshal should guide: a truck backing in (the one closest to the bumpers), else one setting up.
    func dockingJob() -> (bay: Int, left: Float, reversing: Bool)? {
        let docking = trucks.values.filter { $0.bay >= 0 && ($0.mode == .reversing || $0.mode == .setup) }
            .map { (bay: $0.bay, left: ($0.path?.length ?? 0) - $0.s, reversing: $0.mode == .reversing) }
        return docking.filter(\.reversing).min { $0.left < $1.left } ?? docking.min { $0.left < $1.left }
    }

    // MARK: Keeping the economy in step

    /// Furthest along the approach a truck may appear (still on the road, east of everything you can see).
    private lazy var spawnHorizon: Float = {
        approach.firstIndex(from: 0) { !layout.mayAppear($0) }.map { Float($0) * approach.step } ?? 0
    }()

    /// Distance along the approach where a truck counts as "back" (through the gate, into the yard).
    private lazy var inYardS: Float = {
        approach.firstIndex(from: 0) { layout.inYard($0) }.map { Float($0) * approach.step } ?? 0
    }()

    /// The economy asks before moving a truck on: hold it while its animation hasn't caught up.
    func shouldHold(_ m: GameModel.TruckState) -> Bool {
        guard let t = trucks[m.id] else { return false }
        switch m.phase {
        case .away:      // back only once it has come in through the gate
            return t.mode != .approach || t.s < inYardS
        case .docking:   // docked only once it's on the bumpers of its own bay
            return !(t.mode == .docked && t.bay == bay(ofDock: m.dock))
        default: return false
        }
    }

    /// The economy asks before giving a dock to the next truck: wait until the last one has pulled out.
    func dockBusy(_ dock: Int) -> Bool {
        let bay = bay(ofDock: dock)
        for t in trucks.values where t.bay == bay {
            switch t.mode {
            case .docked, .setup, .reversing: return true
            case .departing where t.s < 16: return true
            case .approach where t.claim?.kind == .reverse: return true
            default: continue
            }
        }
        return false
    }

    /// After the economy jumped ahead (the app was away), show every truck where it is now instead of finishing
    /// moves that no longer match: everything is placed afresh, as when the world is first built.
    func resync() {
        for t in trucks.values where t.mode != .through {
            hide(t)
            t.fresh = true
            t.bay = -1
            t.ghost = 0
            t.cells.removeAll()
        }
        pending.removeAll()
        for i in grid.occupied.indices { grid.occupied[i] = 0; grid.reserved[i] = 0; grid.requested[i] = 0 }
        for t in trucks.values where t.mode == .through { t.cells.removeAll() }
        arrivalPlans.removeAll()
    }

    /// Drop a manoeuvre the economy no longer wants (the truck has no bay, or a different one), unless it is
    /// already being carried out. Returns true if the truck is free to take new orders.
    @discardableResult
    private func cancelClaim(_ t: Truck, unlessBay bay: Int? = nil) -> Bool {
        guard let c = t.claim else { return true }
        if let bay, c.kind == .reverse, t.bay == bay { return false }          // the right one: keep it
        guard t.mode == .approach, c.kind == .reverse else { return false }    // already manoeuvring or leaving
        c.releaseAll(grid)
        pending.removeAll { $0 === c }
        t.claim = nil
        t.bay = -1
        return true
    }

    // MARK: Geometry helpers

    private var openBays: Set<Int> { Set((0..<game.docks).map { bay(ofDock: $0) }) }

    /// The bay a dock of the economy uses; always a real bay (a dock beyond the bays shares one rather than crash).
    private func bay(ofDock dock: Int) -> Int {
        let n = layout.bayX.count
        let b = layout.bayOfDock(dock)
        return b >= 0 && b < n ? b : ((dock % n) + n) % n
    }
    private func queueSpot(_ k: Int) -> Float {
        layout.queueSpot?(k, openBays) ?? layout.queueFront(openBays) - Float(k) * layout.queueSpacing
    }

    /// A planned (unhindered) drive along the approach to `target`, for timing arrivals.
    private func arrivalPlan(to target: Float) -> MotionPlan {
        let key = Int(target.rounded())
        if let p = arrivalPlans[key] { return p }
        let p = MotionPlan(layout.approach, from: 0, to: max(target, 1), limit: layout.limit, startSpeed: 11, endSpeed: 0, accel: 1.6)
        arrivalPlans[key] = p
        return p
    }

    // MARK: Per frame

    func update(dt: Float, time now: Float) {
        time += dt
        let fleet = game.liveFleet
        let queued = fleet.filter { $0.phase == .queued }.sorted { $0.since < $1.since }
        // Trucks on their way back, in arrival order, line up behind the queue
        let arriving = fleet.filter { t in
            if case .away = t.phase, let v = trucks[t.id], v.mode == .approach { return true }
            return false
        }.sorted { $0.remaining < $1.remaining }

        reorderLine(fleet)
        for t in fleet { decide(t, queued: queued, arriving: arriving) }
        markOccupancy()
        sweepTimer += dt
        if sweepTimer > 1 { sweepTimer = 0; sweepClaims() }
        grantClaims()
        for t in trucks.values where t.visible { drive(t, dt: dt) }
        updateDocks()
        if Self.debug { debugTimer += dt; if debugTimer > 5 { debugTimer = 0; dump(fleet) } }
    }

    // `-yardDebug YES`: every 5 s, one line per truck (economy state vs. what the yard shows)
    private static let debug = UserDefaults.standard.bool(forKey: "yardDebug")
    private var debugTimer: Float = 0
    private func dump(_ fleet: [GameModel.TruckState]) {
        var lines: [String] = []
        for m in fleet.sorted(by: { $0.id < $1.id }) {
            guard let t = trucks[m.id] else { continue }
            let phase: String
            switch m.phase {
            case .away(let r): phase = String(format: "away %.0f", r)
            case .queued: phase = "queued"
            case .docking(let r): phase = String(format: "dock%d %.0f", m.dock, r)
            case .loading: phase = "load\(m.dock)"
            }
            let x = t.visible ? t.position.x : 0
            lines.append(String(format: "%d %@ | %@ x%.0f z%.0f s%.0f stop%.0f bay%d v%.1f blk%d %@ claim%@", m.id, phase, "\(t.mode)", x, t.visible ? t.position.z : 0,
                                t.s, t.stop ?? -1, t.bay, t.v, t.blockedBy ?? -1, t.blockInfo, t.claim == nil ? "-" : (t.claim!.granted ? "G" : "P")))
        }
        NSLog("[Waybill] yard: docks %d free %@\n%@", game.docks, game.freeDock.map { "\($0)" } ?? "-", lines.joined(separator: "\n"))
    }

    /// The trucks on the approach all look the same, so the line can always be in the economy's order:
    /// trucks that have a bay first, then the waiting line, then the ones still arriving. If two are the wrong
    /// way round (they arrived together), they quietly trade places — only their labels swap.
    private func reorderLine(_ fleet: [GameModel.TruckState]) {
        let line = fleet.compactMap { m -> (GameModel.TruckState, Truck)? in
            guard let t = trucks[m.id], t.mode == .approach, t.claim == nil else { return nil }
            return (m, t)
        }
        guard line.count > 1 else { return }
        func rank(_ m: GameModel.TruckState) -> (Int, Double) {
            switch m.phase {
            case .docking, .loading:   // heading for a bay: the one going furthest along the lane goes first
                return (0, -Double(layout.turnPoints[bay(ofDock: m.dock)]))
            case .queued: return (1, m.since)
            case .away(let r): return (2, r)
            }
        }
        let physical = line.sorted { $0.1.s > $1.1.s }.map(\.1)
        let logical = line.sorted { a, b in
            let ra = rank(a.0), rb = rank(b.0)
            return ra.0 != rb.0 ? ra.0 < rb.0 : (ra.1 != rb.1 ? ra.1 < rb.1 : a.0.id < b.0.id)
        }.map(\.1)
        guard physical.map(\.id) != logical.map(\.id) else { return }
        let states = physical.map { ($0.s, $0.v, $0.stop, $0.catchUp) }
        for (k, t) in logical.enumerated() {
            (t.s, t.v, t.stop, t.catchUp) = states[k]
            t.stuck = 0
            settle(t, path: approach, dt: 1 / 60)
        }
    }

    /// What the economy wants from a truck, turned into a target in the yard.
    private func decide(_ m: GameModel.TruckState, queued: [GameModel.TruckState], arriving: [GameModel.TruckState]) {
        let t = truck(m.id)
        let firstFrame = t.fresh
        t.fresh = false
        if layout.showsCargo {   // the container appears once it's half loaded and stays on until the truck is back
            let loaded: Bool
            switch m.phase {
            case .loading: loaded = game.loaded(m) >= game.truckload * 0.5
            case .away: loaded = t.mode == .departing || t.mode == .docked
            default: loaded = false
            }
            t.vehicle.cargo?.setEnabled(loaded)
        }

        switch m.phase {
        case .away(let remaining):
            switch t.mode {
            case .setup, .reversing:
                t.status = "Docking · \(dockName(t.bay))"            // finish backing in, then leave
            case .docked:
                requestDeparture(t)
                t.status = "Leaving"
            case .departing:
                t.status = "To \(m.job?.destination ?? "customer")"
            case .approach:
                cancelClaim(t)                                       // a bay it was heading for is no longer its own
                let k = queued.count + (arriving.firstIndex { $0.id == m.id } ?? 0)
                setApproachTarget(t, queueIndex: k)
                t.catchUp = catchUp(t, remaining: Float(remaining))
                t.status = m.job == nil ? "New \(game.config.fleet.vehicle)" : "Returning"
            case .hidden:
                let k = queued.count + arriving.count
                let target = arrivalTarget(queueIndex: k)
                let plan = arrivalPlan(to: target)
                let lead = plan.plannedDuration
                guard Float(remaining) <= lead else { return }
                // A truck running late still comes in from beyond the camera's reach (the economy waits for it)
                let s0 = min(plan.distance(at: lead - Float(remaining)), spawnHorizon)
                guard s0 < target - 2 else { return }
                guard spawn(t, at: s0, speed: min(layout.limit(layout.approach.sample(s0).position), 11)) else { return }
                t.stop = target
                t.status = m.job == nil ? "New \(game.config.fleet.vehicle)" : "Returning"
            case .through: break                                     // (passing traffic isn't part of the fleet)
            }

        case .queued:
            let k = queued.firstIndex { $0.id == m.id } ?? 0
            switch t.mode {
            case .hidden:
                let spot = queueSpot(k)
                guard spot > 6 else { return }                       // waiting outside, beyond the visible road
                spawn(t, at: firstFrame ? spot : 4, speed: firstFrame ? 0 : 9)
                setApproachTarget(t, queueIndex: k)
            case .approach:
                cancelClaim(t)
                setApproachTarget(t, queueIndex: k)
            case .docked:
                requestDeparture(t)                                  // still at a bay it no longer has: leave it
            default: break                                           // finish the move under way first
            }
            t.status = t.mode == .approach || t.mode == .hidden ? "Waiting for a bay" : "Leaving"

        case .docking(let remaining):
            let bay = bay(ofDock: m.dock)
            if leaveWrongBay(t, bay: bay) { return }
            switch t.mode {
            case .hidden:
                if firstFrame && Float(remaining) <= Float(game.config.fleet.dockSeconds) {
                    // Opened mid-manoeuvre: put it on the reverse path (or into its lane) with its claim already granted
                    let frac = 1 - Float(remaining / game.config.fleet.dockSeconds)
                    let path = layout.driveThrough ? setupPaths[bay] : reversePaths[bay]
                    var s0 = path.length * frac
                    // Driving into a lane starts at the turn point, where the waiting line's front is: start a van length on
                    if layout.driveThrough { s0 = max(s0, min(layout.halfLength * 2 + 2, path.length)) }
                    place(t, on: path, s: s0, mode: layout.driveThrough ? .setup : .reversing)
                    occupyNow(t)
                    t.bay = bay
                    let c = Claim(owner: t.id, kind: .reverse, path: path, from: 0, to: path.count - 1)
                    c.grant(grid)
                    t.claim = c
                    t.vehicle.rearDoorsOpen = true
                } else {
                    spawn(t, at: firstFrame ? layout.turnPoints[bay] : 4, speed: firstFrame ? 0 : 8)
                    t.stop = layout.turnPoints[bay]
                    t.bay = bay
                }
            case .approach:
                guard cancelClaim(t, unlessBay: bay) || t.bay == bay else { break }
                t.stop = layout.turnPoints[bay]
                t.bay = bay
                t.catchUp = 1.1
                if t.claim == nil, layout.turnPoints[bay] - t.s < 36 { requestReverse(t, bay: bay) }
            case .reversing:
                // Pace the reverse so it ends about when the economy says the truck is docked
                let left = t.path.map { $0.length - t.s } ?? 0
                t.catchUp = min(max(left / max(Float(remaining) - 0.5, 0.5) / layout.reverseSpeed, 0.8), 1.5)
            default: break
            }
            t.status = (t.mode == .reversing || t.mode == .setup) ? "Docking · \(dockName(bay))" : "To \(dockName(bay))"

        case .loading:
            let bay = bay(ofDock: m.dock)
            if leaveWrongBay(t, bay: bay) { return }
            switch t.mode {
            case .hidden:
                if firstFrame {
                    let path = layout.driveThrough ? setupPaths[bay] : reversePaths[bay]
                    place(t, on: path, s: path.length, mode: .docked)
                    occupyNow(t)
                    t.bay = bay
                    t.vehicle.rearDoorsOpen = true
                } else {
                    spawn(t, at: 4, speed: 8)
                    t.stop = layout.turnPoints[bay]
                    t.bay = bay
                }
            case .approach:
                guard cancelClaim(t, unlessBay: bay) || t.bay == bay else { break }
                t.stop = layout.turnPoints[bay]
                t.bay = bay
                t.catchUp = 1.2
                if t.claim == nil, layout.turnPoints[bay] - t.s < 36 { requestReverse(t, bay: bay) }
            case .reversing:
                t.catchUp = 1.4
            default: break
            }
            if t.mode == .docked {
                let loaded = game.loaded(m)
                t.status = game.isReady(m) ? (game.hasDispatcher ? "Ready" : "Ready · tap \(game.config.fleet.verb)") : "Loading \(Int(loaded))/\(Int(game.truckload))"
            } else {
                t.status = (t.mode == .reversing || t.mode == .setup) ? "Docking · \(dockName(bay))" : "To \(dockName(bay))"
            }
        }
    }

    private func dockName(_ bay: Int) -> String { layout.bayName(bay) }

    /// The economy has this truck at `bay`, but in the yard it is at (or backing into) another bay, or still pulling
    /// out: finish that, leave, and come back round for the right bay. Returns true while that is going on.
    private func leaveWrongBay(_ t: Truck, bay: Int) -> Bool {
        guard t.bay >= 0, t.bay != bay else { return false }
        switch t.mode {
        case .docked:
            requestDeparture(t)
            t.status = "Leaving"
            return true
        case .setup, .reversing, .departing:
            t.status = "Leaving"
            return true
        default:
            return false
        }
    }

    /// Arriving trucks head for the waiting line; the moment the economy gives them a bay they roll on to it.
    private func arrivalTarget(queueIndex k: Int) -> Float { queueSpot(k) }

    private func setApproachTarget(_ t: Truck, queueIndex k: Int) {
        guard t.claim == nil else { return }
        t.stop = arrivalTarget(queueIndex: k)
    }

    /// Speed factor that keeps an arriving truck on the economy's schedule (only on the road part).
    private func catchUp(_ t: Truck, remaining: Float) -> Float {
        guard let stop = t.stop else { return 1 }
        let plan = arrivalPlan(to: stop)
        let eta = plan.plannedDuration - plan.time(atDistance: t.s)
        return min(max(eta / max(remaining, 0.25), 0.85), 1.5)
    }

    // MARK: Claims

    private var sweepTimer: Float = 0

    /// Self-healing: rebuild the requested bits from the pending claims and drop reservations nobody holds.
    private func sweepClaims() {
        var holders = Set<Int16>()
        for t in trucks.values { if let c = t.claim, c.granted { holders.insert(Int16(t.id + 1)) } }
        var dropped = 0
        for i in grid.reserved.indices where grid.reserved[i] != 0 && !holders.contains(grid.reserved[i]) {
            grid.reserved[i] = 0
            dropped += 1
        }
        if dropped > 0 { NSLog("[Waybill] yard: dropped %d stale reserved cells", dropped) }
        // Footprints: start from scratch (the next markOccupancy redraws every visible truck)
        for i in grid.occupied.indices where grid.occupied[i] != 0 { grid.occupied[i] = 0 }
        for t in trucks.values {
            guard t.visible, let path = t.path else { t.cells.removeAll(); continue }
            t.cells = Array(path.cells(path.index(t.s)))
            for c in t.cells { grid.occupied[Int(c)] = Int16(t.id + 1) }
        }
        for i in grid.requested.indices where grid.requested[i] != 0 { grid.requested[i] = 0 }
        pending.removeAll { c in trucks[c.owner]?.claim !== c }
        for c in pending { c.request(grid) }
    }

    private func requestReverse(_ t: Truck, bay: Int) {
        let setup = setupPaths[bay]
        var segments = [(path: setup, from: 0, to: setup.count - 1)]
        if !layout.driveThrough { let back = reversePaths[bay]; segments.append((back, 0, back.count - 1)) }
        let c = Claim(owner: t.id, kind: .reverse, segments: segments)
        c.since = time
        c.request(grid)
        t.claim = c
        pending.append(c)
    }

    private func requestDeparture(_ t: Truck) {
        guard t.claim == nil, t.bay >= 0, !(bayBusy?(t.bay) ?? false) else { return }
        let path = departPaths[t.bay]
        let c = Claim(owner: t.id, kind: .depart, path: path, from: 0, to: path.index(layout.departClaimEnd[t.bay]))
        c.since = time
        c.request(grid)
        t.claim = c
        pending.append(c)
    }

    /// Grant waiting claims whose space is free. Trucks waiting at their turn point go first (they hold up the lane).
    private func grantClaims() {
        guard !pending.isEmpty else { return }
        let ordered = pending.sorted { a, b in
            func rank(_ c: Claim) -> Int {
                guard let t = trucks[c.owner] else { return 3 }
                if c.kind == .reverse && waitingAtTurn(t) { return 0 }
                return c.kind == .depart ? 1 : 2
            }
            return rank(a) < rank(b)
        }
        for c in ordered where canGrant(c) {
            c.grant(grid)
            pending.removeAll { $0 === c }
            if let t = trucks[c.owner], c.kind == .depart {
                t.mode = .departing
                t.path = c.paths[0]
                t.reversing = false
                t.s = 0
                t.v = 0
                t.stop = nil
                // A van shuts its sliding door before it pulls away
                if t.vehicle.slidingDoor != nil && t.vehicle.rearDoorsOpen {
                    t.vehicle.rearDoorsOpen = false
                    t.pause = 1.7
                }
            }
        }
    }

    private func canGrant(_ c: Claim) -> Bool {
        let me = Int16(c.owner + 1)
        let owner = trucks[c.owner]
        // Not while the bay is still busy with this truck (a worker at its door); asked before the worker set out
        if c.kind == .depart, let o = owner, o.bay >= 0, bayBusy?(o.bay) ?? false { return false }
        // Not while a truck ahead on the lane still has to drive through this bay's space (it would be shut in)
        if c.kind == .reverse, let o = owner, o.mode == .approach, o.bay >= 0 {
            let clear = layout.turnPoints[o.bay] + 22
            for t in trucks.values where t !== o && t.mode == .approach && t.s > o.s - 0.5 && t.s < clear {
                o.claimBlocker = t.id
                return false
            }
        }
        for cell in c.cells {
            let i = Int(cell)
            let r = grid.reserved[i], o = grid.occupied[i]
            if r != 0 && r != me { owner?.claimBlocker = Int(r) - 1; return false }
            if o != 0 && o != me { owner?.claimBlocker = Int(o) - 1; return false }
        }
        // Nobody may be about to drive into it (within braking distance)
        grid.generation &+= 1
        let gen = grid.generation
        for cell in c.cells { grid.mark[Int(cell)] = gen }
        for t in trucks.values where t.id != c.owner && t.visible && t.v > 0.3 {
            guard let path = t.path else { continue }
            let i = path.index(t.s)
            let ahead = Int((t.v * t.v / 5 + 3) / path.step) + 1
            for j in i...min(i + ahead, path.count - 1) {
                for cell in path.cells(j) where grid.mark[Int(cell)] == gen { owner?.claimBlocker = t.id; return false }
            }
        }
        owner?.claimBlocker = nil
        return true
    }

    // MARK: Motion

    private func markOccupancy() {
        for t in trucks.values {
            let me = Int16(t.id + 1)
            for c in t.cells where grid.occupied[Int(c)] == me { grid.occupied[Int(c)] = 0 }
            t.cells.removeAll(keepingCapacity: true)
            guard t.visible, let path = t.path else { continue }
            t.cells.append(contentsOf: path.cells(path.index(t.s)))
            for c in t.cells { grid.occupied[Int(c)] = me }
        }
    }

    /// Distance the truck can still drive before it would touch something, and who is in the way.
    private func freeDistance(_ t: Truck, path: TrackedPath) -> (Float, Int?) {
        let me = Int16(t.id + 1)
        let myBit = UInt32(1) << UInt32(t.id)
        var inside: UInt32 = myBit
        for c in t.cells { inside |= grid.requested[Int(c)] }
        // Requests from trucks behind me on the lane don't hold me up (they wait for me to pass, see canGrant)
        if path === approach {
            for o in trucks.values where o !== t && o.mode == .approach && o.s < t.s && o.claim != nil { inside |= UInt32(1) << UInt32(o.id) }
        }
        // A truck carrying out a granted manoeuvre has right of way over requests (its space was checked when granted)
        // (also while it is still driving up to it: a waiting request can't be granted before this claim is done anyway)
        if let c = t.claim, c.granted { inside = .max }
        let i = path.index(t.s)
        let ahead = Int((t.v * t.v / 4.4 + 6) / path.step) + 2
        guard i + 1 < path.count else { return (.infinity, nil) }
        for j in (i + 1)...min(i + ahead, path.count - 1) {
            for cell in path.cells(j) {
                let c = Int(cell)
                let o = grid.occupied[c], r = grid.reserved[c], q = grid.requested[c] & ~inside
                if o != 0 && o != me { t.blockInfo = "o@\(c % grid.width + Int(grid.originX)),\(c / grid.width + Int(grid.originZ))"; return (Float(j - i) * path.step, Int(o) - 1) }
                if r != 0 && r != me { t.blockInfo = "r@\(c % grid.width + Int(grid.originX)),\(c / grid.width + Int(grid.originZ))"; return (Float(j - i) * path.step, Int(r) - 1) }
                if q != 0 { t.blockInfo = "q@\(c % grid.width + Int(grid.originX)),\(c / grid.width + Int(grid.originZ))"; return (Float(j - i) * path.step, q.trailingZeroBitCount) }
            }
        }
        return (.infinity, nil)
    }

    /// True if following "who is in the way" from this truck leads back to it (real gridlock, not a queue).
    private func inCycle(_ t: Truck) -> Bool {
        var seen: Set<Int> = [t.id]
        var next = t.blockedBy
        for _ in 0..<16 {
            guard let id = next, let other = trucks[id] else { return false }
            if id == t.id { return true }
            if !seen.insert(id).inserted { return false }
            next = other.blockedBy
        }
        return false
    }

    private func drive(_ t: Truck, dt: Float) {
        guard let path = t.path else { return }
        if t.mode == .docked {
            t.v = 0
            settle(t, path: path, dt: dt)
            return
        }
        // A truck at its bay's turn point waits there until the whole manoeuvre's space is its own;
        // if the space is already granted as it comes along, it rolls straight on into the manoeuvre.
        let waitingForClaim = waitingAtTurn(t) && !(t.claim?.granted ?? true)
        let rollOn = t.mode == .approach && t.claim?.granted == true && t.claim?.kind == .reverse && t.bay >= 0
        let end = rollOn ? layout.turnPoints[t.bay] + 6 : (t.stop ?? path.length)
        let toStop = end - t.s
        if t.pause > 0 { t.pause -= dt; t.v = 0; settle(t, path: path, dt: dt); return }

        let pos = path.path.sample(t.s).position
        var limit: Float
        switch t.mode {
        case .reversing: limit = layout.reverseSpeed * t.catchUp
        case .setup: limit = 3.6
        case .departing: limit = t.s < 6 ? 2.2 : (t.s < 14 ? 3.6 : layout.limit(pos))
        case .through: limit = t.cruise
        default: limit = layout.limit(pos) * (layout.limit(pos) > 9 ? t.catchUp : min(t.catchUp, 1.1))
        }
        if rollOn { limit = min(limit, 3.4) }
        // Brake to the stop point, creeping the last few centimetres so it is actually reached
        var target = min(limit, sqrt(2 * 1.5 * max(toStop, 0)) + (toStop > 0.01 ? 0.2 : 0))
        if waitingForClaim { target = 0 }
        var free = Float.infinity
        if t.ghost <= 0 {
            let (distance, blocker) = freeDistance(t, path: path)
            free = distance
            t.blockedBy = distance < 3 ? blocker : (waitingForClaim ? t.claimBlocker : nil)
        } else {
            t.blockedBy = nil
        }
        if waitingForClaim { t.blockedBy = t.claimBlocker }
        target = min(target, sqrt(2 * 2.6 * max(free - 1.2, 0)))
        let accel: Float = t.mode == .reversing ? 0.9 : (t.mode == .departing && t.s < 8 ? 0.9 : 1.4)
        if target > t.v { t.v = min(t.v + accel * dt, target) }
        else { t.v = max(t.v - 2.6 * dt, target) }
        if free < 2 && t.v > 0.5 { t.v *= max(1 - 6 * dt, 0) }   // hard stop when something appears close

        // Gridlock guard: trucks waiting in a line are fine; trucks waiting on each other in a circle are not.
        // Then the one stuck longest slips through (rare; logged so the layout can be fixed).
        let wantsToMove = (toStop > 0.5 && free < 3) || waitingForClaim
        if wantsToMove && t.v < 0.05 && t.blockedBy != nil { t.stuck += dt } else { t.stuck = 0 }
        if (t.stuck > 6 && inCycle(t)) || (waitingForClaim && t.stuck > 60) {
            NSLog("[Waybill] yard: truck %d stuck behind %d (mode %@, s %.1f/%.1f, cycle %@) — letting it through",
                  t.id, t.blockedBy ?? -1, "\(t.mode)", t.s, path.length, inCycle(t) ? "yes" : "no")
            t.ghost = 4
            t.stuck = 0
            if waitingForClaim, let c = t.claim {
                c.grant(grid)
                pending.removeAll { $0 === c }
            }
        }
        if t.ghost > 0 { t.ghost -= dt }

        t.s = min(t.s + t.v * dt, end)
        if end - t.s < 0.005 { t.v = 0 }
        settle(t, path: path, dt: dt)
        if let c = t.claim, c.covers(path) { c.release(on: path, upTo: path.index(t.s), grid) }
        if t.mode == .departing && t.s > 7 { t.vehicle.rearDoorsOpen = false }

        // Rolled onto the bay manoeuvre: pull forward and swing the cab out
        if rollOn && t.s >= layout.turnPoints[t.bay] - 0.3 {
            t.mode = .setup
            t.path = setupPaths[t.bay]
            t.s = max(t.s - layout.turnPoints[t.bay], 0)
            t.stop = nil
            return
        }

        // Arrived somewhere?
        if t.s >= path.length - 0.01 {
            switch t.mode {
            case .setup where layout.driveThrough:
                // Drove into the lane: stopped at the loading spot (a van slides its side door open)
                t.mode = .docked
                t.v = 0
                t.claim?.releaseAll(grid)
                t.claim = nil
                t.vehicle.rearDoorsOpen = true
            case .setup:
                // Stop, shift into reverse, back in
                t.mode = .reversing
                t.path = reversePaths[t.bay]
                t.reversing = true
                t.s = 0
                t.v = 0
                t.pause = 0.5
                t.vehicle.rearDoorsOpen = true
            case .reversing:
                t.mode = .docked
                t.claim?.releaseAll(grid)
                t.claim = nil
            case .departing:
                t.claim?.releaseAll(grid)
                t.claim = nil
                hide(t)
            case .approach:
                hide(t)                                  // ran off the end of the lane (shouldn't happen)
            case .through:
                place(t, on: path, s: 0, mode: .through)   // round again (the lanes start and end off the map)
                t.v = t.cruise
            default: break
            }
            return
        }
    }

    /// Standing (or arriving) at its bay's turn point with a manoeuvre requested.
    private func waitingAtTurn(_ t: Truck) -> Bool {
        guard t.mode == .approach, t.bay >= 0, let c = t.claim, c.kind == .reverse else { return false }
        return abs(layout.turnPoints[t.bay] - t.s) < 1.5
    }

    /// The rear axle is on the path and the truck faces along it (backwards when reversing), so the back follows
    /// the line and the cab swings out, as with a real truck.
    private func settle(_ t: Truck, path: TrackedPath, dt: Float) {
        t.vehicle.signal = signal(for: t)
        let (p, tangent) = path.path.sample(t.s)
        let facing = t.reversing ? -tangent : tangent
        t.mover.place(p + facing * t.originOffset, heading: atan2(-facing.z, facing.x), reverse: t.reversing && t.v > 0.02, dt: dt, exact: true)
    }

    /// Like a driver: indicate right towards the bay on the way in, hazard lights while backing onto the dock,
    /// indicate right pulling out onto the lane; otherwise the indicators follow the steering.
    private func signal(for t: Truck) -> Vehicle.Signal {
        guard !layout.driveThrough, t.mode != .through else { return t.mode == .docked ? .none : .auto }
        switch t.mode {
        case .approach:
            guard t.bay >= 0, t.claim?.kind == .reverse else { return .auto }
            return layout.turnPoints[t.bay] - t.s < 28 ? .right : .auto
        case .setup: return .right
        case .reversing: return .hazard
        case .docked: return .none
        case .departing: return t.s < 24 ? .right : .auto
        case .hidden, .through: return .auto
        }
    }

    // MARK: Showing and hiding

    /// Bring a truck onto the approach at `s`, unless another truck is there (then it waits off-screen a little longer).
    @discardableResult
    private func spawn(_ t: Truck, at s: Float, speed: Float) -> Bool {
        let me = Int16(t.id + 1)
        let i = approach.index(s)
        for j in max(i - 4, 0)...min(i + 4, approach.count - 1) {
            for c in approach.cells(j) {
                let o = grid.occupied[Int(c)]
                if o != 0 && o != me { return false }
            }
        }
        place(t, on: approach, s: s, mode: .approach)
        t.v = speed
        for c in t.cells where grid.occupied[Int(c)] == me { grid.occupied[Int(c)] = 0 }
        for c in approach.cells(i) { grid.occupied[Int(c)] = me }   // so a second spawn this frame sees it
        t.cells = Array(approach.cells(i))
        return true
    }

    /// Mark a truck that was just placed as occupying its space at once (so a truck placed later in the same frame
    /// sees it), instead of waiting for the next `markOccupancy`.
    private func occupyNow(_ t: Truck) {
        guard let path = t.path else { return }
        let me = Int16(t.id + 1)
        for c in t.cells where grid.occupied[Int(c)] == me { grid.occupied[Int(c)] = 0 }
        t.cells = Array(path.cells(path.index(t.s)))
        for c in t.cells { grid.occupied[Int(c)] = me }
    }

    private func place(_ t: Truck, on path: TrackedPath, s: Float, mode: Truck.Mode) {
        t.path = path
        t.s = min(max(s, 0), path.length)
        t.v = 0
        t.mode = mode
        t.reversing = mode == .reversing || mode == .docked && path !== approach && reversePaths.contains { $0 === path }
        t.stuck = 0
        t.vehicle.root.isEnabled = true
        t.mover.reset()
        settle(t, path: path, dt: 1 / 60)
    }

    private func hide(_ t: Truck) {
        t.claim?.releaseAll(grid)
        if let c = t.claim { pending.removeAll { $0 === c } }
        t.claim = nil
        t.mode = .hidden
        t.path = nil
        t.v = 0
        t.stop = nil
        t.pause = 0
        t.vehicle.rearDoorsOpen = false
        t.vehicle.root.isEnabled = false
        t.mover.reset()
    }

    // MARK: Bays

    private func updateDocks() {
        var states = [Warehouse.DockState](repeating: .empty, count: layout.bayX.count)
        var loading = [Float?](repeating: nil, count: layout.bayX.count)
        for t in trucks.values where t.bay >= 0 && t.bay < states.count {
            switch t.mode {
            case .setup, .reversing: if states[t.bay] == .empty || states[t.bay] == .leaving { states[t.bay] = .arriving }
            case .docked:
                let m = game.liveFleet.first(where: { $0.id == t.id })
                if let m, m.phase == .loading || m.isAtDock {
                    states[t.bay] = .docked
                    if m.phase == .loading, !game.isReady(m) { loading[t.bay] = Float(game.loaded(m) / max(game.truckload, 1)) }
                } else {
                    states[t.bay] = .closing                 // loaded and sent: close up, then pull out
                }
            case .departing where t.s < 9: if states[t.bay] == .empty { states[t.bay] = .leaving }
            default: break
            }
        }
        dockStates = states
        dockLoading = loading
    }
}

extension GameModel {
    typealias TruckState = Truck
}
