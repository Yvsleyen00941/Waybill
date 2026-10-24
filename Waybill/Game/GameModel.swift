import Foundation
import Observation

/// The game's state and rules. Units flow Receiving → Put-away → Shipping, vehicles back into a dock,
/// load from the shipping buffer and earn money when they're dispatched.
/// The 3D world and the interface both read from this object.
@Observable
final class GameModel {
    enum BuyMode: String, CaseIterable { case one = "×1", ten = "×10", max = "Max" }

    nonisolated struct ActiveResearch: Codable, Equatable, Sendable {
        let id: String
        var remaining: Double
    }

    /// A warehouse expansion being built (real time, also while the app is closed).
    nonisolated struct Construction: Codable, Equatable, Sendable {
        let tier: Int
        var remaining: Double
        let total: Double
        var progress: Double { total > 0 ? min(max(1 - remaining / total, 0), 1) : 1 }
    }

    struct AwayReport: Identifiable {
        let id = UUID()
        let seconds: Double
        let earned: Double
        let delivered: Double
        let hadDispatcher: Bool
        let contractsDone: Int
        let research: [String]
    }

    // MARK: Company (kept when you expand to a new region)

    private(set) var stars = 0
    private(set) var completed: [RegionID] = []
    private(set) var companyEarned: Double = 0
    private(set) var contractsCompleted = 0
    /// The finale was celebrated (Orbit's goal reached); the game continues endlessly.
    private(set) var finished = false
    private(set) var shipmentsSent = 0

    // MARK: This region (refreshed ~10× a second)

    private(set) var region: RegionID = .riverside
    private(set) var money: Double = RegionConfig.riverside.startMoney
    private(set) var levels: [StageKind: Int] = GameModel.freshLevels
    private(set) var managers: Set<StageKind> = []
    private(set) var research: Set<String> = []
    private(set) var activeResearch: ActiveResearch?
    /// How far the site has grown (index into `config.facility`), and what's being built now.
    private(set) var facilityTier = 0
    private(set) var construction: Construction?
    private(set) var receiving: Double = 6
    private(set) var stock: Double = 30
    private(set) var shipping: Double = 8
    private(set) var trucks: [Truck] = []
    private(set) var offers: [Contract] = []
    private(set) var contracts: [Contract] = []
    private(set) var history: [Shipment] = []
    private(set) var lifetimeEarned: Double = 0
    private(set) var delivered: Double = 0
    private(set) var berthClock: Double = 0
    /// Rush countdowns (only the Rush button follows these every frame).
    private(set) var rushRemaining: Double = 0 { didSet { if rushActive != (rushRemaining > 0) { rushActive = rushRemaining > 0 } } }
    private(set) var rushCooldown: Double = 0
    /// Changes only when a rush starts or ends, so views that just need to know don't redraw with the countdown.
    private(set) var rushActive = false
    var buyMode: BuyMode = .one
    var awayReport: AwayReport?

    // MARK: Events for the world, the interface and the sound

    enum Event {
        case dispatched(truck: Int, amount: Double)
        case milestone(StageKind, Int)
        case upgraded(StageKind)
        case hired(StageKind)
        case contractAccepted(Contract)
        case contractFinished(Contract, success: Bool)
        case researchStarted(ResearchProject)
        case researchDone(ResearchProject)
        case constructionStarted(FacilityTier)
        case constructionDone(FacilityTier)
        case unlocked(String)
        case regionChanged(RegionID)
        case rush
        /// The time the app was away has been simulated: the world should show the new state as it is.
        case caughtUp
    }
    @ObservationIgnored private var listeners: [(Event) -> Void] = []
    /// While catching up after a break, events are not sent (the "while you were away" card sums them up).
    @ObservationIgnored private var catchingUp = false

    func listen(_ listener: @escaping (Event) -> Void) { listeners.append(listener) }

    // MARK: Keeping the 3D yard in step (Riverside)

    /// While the app is open, the 3D yard may hold a vehicle until its animation has caught up (it has backed
    /// onto the bumpers, it has come back in through the gate), and keep a dock closed until the truck has
    /// pulled out. Never used while catching up after a break, and capped so a stuck animation can't stall the game.
    @ObservationIgnored var holdVehicle: ((Truck) -> Bool)?
    @ObservationIgnored var holdDock: ((Int) -> Bool)?
    @ObservationIgnored private var heldFor: [Int: Double] = [:]
    static let maxHold: Double = 40

    private func held(_ truck: Truck, dt: Double) -> Bool {
        guard let hold = holdVehicle, hold(truck) else { heldFor[truck.id] = nil; return false }
        let t = (heldFor[truck.id] ?? 0) + dt
        heldFor[truck.id] = t
        return t < Self.maxHold
    }
    private func emit(_ event: Event) {
        guard !catchingUp else { return }
        for l in listeners { l(event) }
    }

    // MARK: Precise values updated every frame (copied into the observed ones at 10 Hz)

    @ObservationIgnored private var r = 6.0
    @ObservationIgnored private var s = 30.0
    @ObservationIgnored private var sh = 8.0
    @ObservationIgnored private var fleet: [Truck] = []
    @ObservationIgnored private var dockClear: [Double] = []
    @ObservationIgnored private var offerList: [Contract] = []
    @ObservationIgnored private var activeList: [Contract] = []
    @ObservationIgnored private var researchTimer: ActiveResearch?
    @ObservationIgnored private var buildTimer: Construction?
    @ObservationIgnored private var berth = 0.0
    @ObservationIgnored private var clock = 0.0
    @ObservationIgnored private var nextShipment = 78_442
    @ObservationIgnored private var nextContract = 1
    @ObservationIgnored private var refillTimer = 0.0
    @ObservationIgnored private var publishTimer = 0.0
    @ObservationIgnored private var saveTimer = 0.0
    @ObservationIgnored private var savesSinceBackup = 0
    static let awayTest = UserDefaults.standard.double(forKey: "awayTest")
    @ObservationIgnored private var awayTestTimer = 0.0
    @ObservationIgnored private var pausedAt: Date?
    private(set) var mods = Modifiers()
    // Counters for the "while you were away" report
    @ObservationIgnored private var awayContracts = 0
    @ObservationIgnored private var awayResearch: [String] = []

    /// Developer setting (`-researchSpeed 60`): research runs this many times faster.
    static let researchSpeed: Double = max(UserDefaults.standard.double(forKey: "researchSpeed"), 1)
    static let autoBuild = UserDefaults.standard.integer(forKey: "autoBuild")
    static let autoBuildDelay: Double = UserDefaults.standard.object(forKey: "autoBuildDelay") != nil ? UserDefaults.standard.double(forKey: "autoBuildDelay") : 6
    @ObservationIgnored private var autoBuildWait = 0.0
    /// Developer setting (`-buildSpeed 20`): warehouse expansions build this many times faster.
    static let buildSpeed: Double = max(UserDefaults.standard.double(forKey: "buildSpeed"), 1)

    static let freshLevels: [StageKind: Int] = [.receiving: 1, .putaway: 1, .shipping: 1, .fleet: 1]

    init() {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetSave") { deleteSave() }
        if !load() { resetRegion(.riverside) }
        if let start = d.string(forKey: "region"), let id = RegionID(rawValue: start), id != region { resetRegion(id) }
        if d.object(forKey: "cash") != nil { money = d.double(forKey: "cash") }
        if d.object(forKey: "lifetime") != nil { lifetimeEarned = max(lifetimeEarned, d.double(forKey: "lifetime")) }
        if d.bool(forKey: "unlockAll") {
            managers.insert(.fleet)
            contractsCompleted = max(contractsCompleted, 1)
            if offerList.isEmpty { refillOffers() }
        }
        if d.bool(forKey: "allResearch") {
            for p in ResearchProject.projects(for: region) { research.insert(p.id) }
        }
        // `-depotTier 3`: start with the warehouse expanded this far
        if d.object(forKey: "depotTier") != nil, !config.facility.isEmpty {
            facilityTier = min(max(d.integer(forKey: "depotTier") - 1, 0), config.facility.count - 1)
            buildTimer = nil
        }
        // `-levels fleet:13,putaway:10`: start with these stage levels
        if let spec = d.string(forKey: "levels") {
            for part in spec.split(separator: ",") {
                let kv = part.split(separator: ":")
                if kv.count == 2, let kind = StageKind(rawValue: String(kv[0])), let level = Int(kv[1]) { levels[kind] = max(level, 1) }
            }
        }
        refreshMods()
        growFleet()
        publish()
    }

    /// Research and the warehouse together decide the modifiers.
    private func refreshMods() {
        var m = Modifiers(research: research)
        if let tier = facility { m.apply(tier, baseDocks: config.fleet.docks) }
        mods = m
    }

    // MARK: Derived numbers

    var config: RegionConfig { region.config }
    func level(_ kind: StageKind) -> Int { levels[kind] ?? 1 }
    func isManaged(_ kind: StageKind) -> Bool { managers.contains(kind) }
    var hasDispatcher: Bool { managers.contains(.fleet) }

    var reputationMultiplier: Double { 1 + Double(stars) * Economy.starBonus }
    var networkMultiplier: Double { 1 + Double(completed.count) * Economy.networkBonus }
    /// What one unit earns, after research, reputation and the network.
    var unitValue: Double { config.unitValue * mods.value * reputationMultiplier * networkMultiplier }

    /// Effective units per minute of a stage right now (receiving averaged over ship windows).
    func rate(_ kind: StageKind) -> Double {
        switch kind {
        case .fleet: Economy.fleetRate(level: level(.fleet), config.fleet, mods: mods, rush: rushActive, travel: averageTravel)
        case .receiving: stageRate(.receiving, rush: rushActive) * (windowShare ?? 1)
        default: stageRate(kind, rush: rushActive)
        }
    }

    private func stageRate(_ kind: StageKind, rush: Bool) -> Double {
        Economy.rate(config.stage(kind), kind: kind, level: level(kind), managed: isManaged(kind), rush: rush, mods: mods)
    }

    var bottleneck: StageKind { StageKind.allCases.min { rate($0) < rate($1) } ?? .putaway }
    var throughput: Double { rate(bottleneck) }
    var incomePerMinute: Double { throughput * unitValue }
    var stockCapacity: Double { Economy.stockCapacity(config, putawayLevel: level(.putaway), mods: mods) }
    var truckload: Double { Economy.load(level: level(.fleet), config.fleet, mods: mods) }
    var fleetSize: Int { Economy.vehicles(level: level(.fleet), config.fleet) }
    var roadSeconds: Double { Economy.roadSeconds(config.fleet, mods: mods) }
    var docks: Int { config.fleet.docks + mods.docks }

    // MARK: Warehouse (Riverside grows; other regions have a fixed site)

    /// The finished stage of the site, nil where the site doesn't grow.
    var facility: FacilityTier? { config.facility.isEmpty ? nil : config.facility[min(facilityTier, config.facility.count - 1)] }
    var nextFacility: FacilityTier? { facilityTier + 1 < config.facility.count ? config.facility[facilityTier + 1] : nil }
    var canBuild: Bool { buildTimer == nil && nextFacility.map { money >= $0.cost } == true }

    /// Seconds a vehicle needs to drive from the waiting line to dock `d` (the line waits next to the
    /// dock nearest the gate, so docks further along the hall take longer).
    func travelSeconds(dock d: Int) -> Double {
        let positions = config.fleet.dockPositions
        guard d >= 0, d < positions.count else { return 0 }
        let active = positions.prefix(min(docks, positions.count))
        let front = (active.max() ?? positions[d]) + Self.queueOffset
        return (front - positions[d] + Self.turnOffset) / Self.yardSpeed + 7.5
    }
    /// The waiting line starts this many metres past the dock nearest the gate (clear of its manoeuvre).
    static let queueOffset: Double = 15
    /// Where a truck turns off the lane for its bay, relative to the dock (its rear axle 8.5 m short of it; it pulls past, swings out, backs in;
    /// that set-up takes about 6 s, the `+ 7.5` above).
    static let turnOffset: Double = -8.5
    /// Average speed in the yard, metres per second.
    static let yardSpeed: Double = 5.5
    var averageTravel: Double {
        guard !config.fleet.dockPositions.isEmpty, docks > 0 else { return 0 }
        return (0..<docks).map { travelSeconds(dock: $0) }.reduce(0, +) / Double(docks)
    }
    /// The docks, not the vehicles, are what limits the fleet right now.
    var docksAreLimit: Bool {
        let f = config.fleet
        return Economy.dockCap(level: level(.fleet), f, mods: mods, travel: averageTravel)
            < Economy.vehicleCap(level: level(.fleet), f, mods: mods, travel: averageTravel) - 0.001
    }
    /// Vehicles queued for a bay. Kept up to date by `publish`, and changes only when the count does, so the
    /// interface doesn't redraw with every truck's countdown (same for `trucksAtDepot` and `stockPercent`).
    private(set) var vehiclesWaiting = 0
    /// The dock the next queued vehicle would get right now, if any (the 3D yard uses it to route arrivals).
    var freeDock: Int? {
        (0..<docks).first { d in (d >= dockClear.count || dockClear[d] <= 0) && !fleet.contains { $0.dock == d } && holdDock?(d) != true }
    }
    var shippingCapacity: Double { max(config.shippingCapacity, truckload * 1.5 * Double(docks), stageRate(.shipping, rush: false) / 60 * 12) }
    /// The receiving area holds about 12 seconds of unloading (a whole ship gap in Harbour City), so fast stages never starve.
    var receivingCapacity: Double {
        let seconds = config.windows.map { $0.away + 12 } ?? 12
        return max(config.receivingCapacity, stageRate(.receiving, rush: false) / 60 * seconds)
    }
    private(set) var trucksAtDepot = 0
    /// How full storage is, in whole percent.
    private(set) var stockPercent = 0

    /// Ship windows (Harbour City): share of the time a ship is berthed, and whether one is in now.
    var windowShare: Double? {
        guard let w = config.windows else { return nil }
        let berthed = w.berthed * mods.berth
        return berthed / (berthed + w.away)
    }
    var shipBerthed: Bool {
        guard let w = config.windows else { return true }
        return berthClock < w.berthed * mods.berth
    }
    var shipWindowRemaining: Double {
        guard let w = config.windows else { return 0 }
        let berthed = w.berthed * mods.berth
        return berthClock < berthed ? berthed - berthClock : berthed + w.away - berthClock
    }

    /// How many units a truck at a dock has on board (they share the shipping buffer, first docked first served).
    func loaded(_ truck: Truck) -> Double {
        guard case .loading = truck.phase else { return 0 }
        var left = shipping
        for t in trucks.filter({ $0.phase == .loading }).sorted(by: { $0.since < $1.since }) {
            let mine = min(left, truckload)
            if t.id == truck.id { return mine }
            left -= mine
        }
        return 0
    }

    /// The fleet right now (not throttled to 10 Hz): the 3D world reads this every frame.
    var liveFleet: [Truck] { fleet }

    func isReady(_ truck: Truck) -> Bool { truck.phase == .loading && loaded(truck) >= truckload - 0.001 }
    var readyTruck: Truck? { trucks.filter { isReady($0) }.min { $0.since < $1.since } }
    var canDispatch: Bool { readyTruck != nil }
    var dispatchValue: Double { truckload * unitValue }

    // MARK: Unlocks ("unfolding")

    var contractsUnlocked: Bool { region != .riverside || hasDispatcher || contractsCompleted > 0 }
    var researchUnlocked: Bool { region != .riverside || contractsCompleted > 0 || lifetimeEarned >= 15_000 }
    var contractSlots: Int { 1 + mods.contractSlots }
    var canExpand: Bool { config.goal.isFinite && lifetimeEarned >= config.goal && region.next != nil }
    /// Orbit's goal reached: time for the finale.
    var canFinish: Bool { region.next == nil && lifetimeEarned >= config.goal && !finished }

    /// Celebrate the finale (once), then keep playing.
    func finish() {
        guard canFinish else { return }
        finished = true
        stars += 25
        save()
    }
    var expansionProgress: Double { config.goal.isFinite ? min(lifetimeEarned / config.goal, 1) : 1 }
    var offlineCapHours: Double { Economy.baseOfflineHours + mods.offlineHours }

    /// How many levels the current buy mode would purchase, and what it costs.
    func purchase(_ kind: StageKind) -> (count: Int, cost: Double) {
        let lvl = level(kind)
        let c = config.stage(kind)
        switch buyMode {
        case .one: return (1, Economy.upgradeCost(c, level: lvl))
        case .ten: return (10, Economy.upgradeCost(c, level: lvl, count: 10))
        case .max:
            let n = max(Economy.affordableLevels(c, level: lvl, money: money), 1)
            return (n, Economy.upgradeCost(c, level: lvl, count: n))
        }
    }

    func canAfford(_ kind: StageKind) -> Bool { money >= purchase(kind).cost }

    // MARK: Actions

    func buy(_ kind: StageKind) {
        let (count, cost) = purchase(kind)
        guard money >= cost else { return }
        money -= cost
        let before = level(kind)
        levels[kind] = before + count
        emit(.upgraded(kind))
        if let m = Economy.milestones.last(where: { $0 > before && $0 <= before + count }) { emit(.milestone(kind, m)) }
        if kind == .fleet { growFleet() }
        publish()
        save()
    }

    func hire(_ kind: StageKind) {
        let cost = config.stage(kind).managerCost
        guard !isManaged(kind), money >= cost else { return }
        let contractsBefore = contractsUnlocked
        money -= cost
        managers.insert(kind)
        emit(.hired(kind))
        if !contractsBefore && contractsUnlocked {
            refillOffers()
            emit(.unlocked("contracts"))
        }
        publish()
        save()
    }

    /// Manual dispatch (before the Dispatcher is hired): sends the first ready vehicle.
    func dispatch() {
        guard let t = fleet.indices.filter({ isReadyPrecise(fleet[$0]) }).min(by: { fleet[$0].since < fleet[$1].since }) else { return }
        performDispatch(t, now: Date())
        publish()
    }

    func rush() {
        guard rushRemaining <= 0, rushCooldown <= 0 else { return }
        rushRemaining = Economy.rushDuration
        rushCooldown = Economy.rushDuration + Economy.rushCooldown
        emit(.rush)
    }

    func accept(_ contract: Contract) {
        guard activeList.count < contractSlots, let i = offerList.firstIndex(where: { $0.id == contract.id }) else { return }
        var c = offerList.remove(at: i)
        c.remaining = c.seconds
        activeList.append(c)
        refillTimer = min(refillTimer, 25) // a new offer appears shortly
        emit(.contractAccepted(c))
        publish()
        save()
    }

    func startResearch(_ project: ResearchProject) {
        guard researchTimer == nil, !research.contains(project.id), money >= project.cost else { return }
        money -= project.cost
        researchTimer = ActiveResearch(id: project.id, remaining: project.seconds)
        emit(.researchStarted(project))
        publish()
        save()
    }

    /// Start building the next warehouse expansion.
    func build() {
        guard let next = nextFacility, buildTimer == nil, money >= next.cost else { return }
        money -= next.cost
        buildTimer = Construction(tier: facilityTier + 1, remaining: next.seconds, total: next.seconds)
        emit(.constructionStarted(next))
        publish()
        save()
    }

    /// Finish the active research instantly (developer shortcut, see README).
    func finishResearchNow() { if researchTimer != nil { researchTimer?.remaining = 0 } }

    /// Move the company to the next region. Money, levels, managers and research start over;
    /// reputation, the network bonus and finished regions stay.
    func expand() {
        guard canExpand, let next = region.next else { return }
        stars += Economy.expansionStars(lifetime: lifetimeEarned, goal: config.goal)
        completed.append(region)
        resetRegion(next)
        publish()
        save()
        emit(.regionChanged(next))
    }

    // MARK: Simulation

    /// Advance the game by `dt` seconds. Called every frame.
    func tick(dt rawDt: Double) {
        let dt = min(max(rawDt, 0), 0.25)
        simulate(dt: dt, live: true, now: Date())
        if rushRemaining > 0 { rushRemaining = max(rushRemaining - dt, 0) }
        if rushCooldown > 0 { rushCooldown = max(rushCooldown - dt, 0) }
        // `-autoBuild 5 -autoBuildDelay 8`: keep expanding the warehouse up to that stage (for testing and recordings)
        if Self.autoBuild > facilityTier + 1, buildTimer == nil, let next = nextFacility {
            autoBuildWait += dt
            if autoBuildWait >= Self.autoBuildDelay {
                autoBuildWait = 0
                money = max(money, next.cost)
                build()
            }
        }
        // `-awayTest 120`: every 90 s, act as if the app had been closed this long (tests catching up and the yard)
        if Self.awayTest > 0 {
            awayTestTimer += dt
            if awayTestTimer > 90 {
                awayTestTimer = 0
                catchUp(since: Date().addingTimeInterval(-Self.awayTest))
                awayReport = nil
            }
        }
        publishTimer += dt
        if publishTimer >= 0.1 { publishTimer = 0; publish() }
        saveTimer += dt
        if saveTimer >= 5 { saveTimer = 0; save() }
    }

    private func simulate(dt: Double, live: Bool, now: Date) {
        let rush = live && rushActive
        let speed = rush ? 2.0 : 1.0
        clock += dt

        // 1. Goods flow through the three buffers
        var inRate = stageRate(.receiving, rush: rush) / 60
        if let w = config.windows {
            let berthed = w.berthed * mods.berth
            berth = (berth + dt).truncatingRemainder(dividingBy: berthed + w.away)
            if berth >= berthed { inRate = 0 } // no ship at the quay
        }
        let inFlow = max(min(inRate * dt, receivingCapacity - r), 0)
        r += inFlow
        let putFlow = max(min(stageRate(.putaway, rush: rush) / 60 * dt, r, stockCapacity - s), 0)
        r -= putFlow
        s += putFlow
        let shipFlow = max(min(stageRate(.shipping, rush: rush) / 60 * dt, s, shippingCapacity - sh), 0)
        s -= shipFlow
        sh += shipFlow

        // 2. Vehicles: road → queue → dock → loading
        let half = roadSeconds / 2
        for i in fleet.indices {
            switch fleet[i].phase {
            case .away(let left):
                let next = left - dt * speed
                if fleet[i].job?.departedAt != nil, fleet[i].job?.deliveredAt == nil, next <= half { fleet[i].job?.deliveredAt = now }
                if next <= 0, live, held(fleet[i], dt: dt) {
                    fleet[i].phase = .away(0)                // not back through the gate yet
                } else if next <= 0 {
                    if var job = fleet[i].job {
                        job.returnedAt = now
                        history.insert(job, at: 0)
                        if history.count > 6 { history.removeLast() }
                    }
                    fleet[i].job = nil
                    fleet[i].phase = .queued
                    fleet[i].since = clock
                } else {
                    fleet[i].phase = .away(next)
                }
            case .docking(let left):
                let next = left - dt * speed
                if next <= 0, live, held(fleet[i], dt: dt) {
                    fleet[i].phase = .docking(0)             // still backing in
                } else if next <= 0 {
                    fleet[i].phase = .loading
                    fleet[i].since = clock
                } else {
                    fleet[i].phase = .docking(next)
                }
            default: break
            }
        }
        if dockClear.count != docks { dockClear = Array(repeating: 0, count: docks) }
        for d in dockClear.indices where dockClear[d] > 0 { dockClear[d] = max(dockClear[d] - dt * speed, 0) }
        assignDocks(now: now, live: live)
        if hasDispatcher {
            while let t = fleet.indices.filter({ isReadyPrecise(fleet[$0]) }).min(by: { fleet[$0].since < fleet[$1].since }) {
                performDispatch(t, now: now)
            }
        }

        // 3. Contracts count down in real time
        if contractsUnlocked {
            for i in offerList.indices { offerList[i].offerExpires -= dt }
            offerList.removeAll { $0.offerExpires <= 0 }
            for i in activeList.indices { activeList[i].remaining -= dt }
            for c in activeList where c.remaining <= 0 && !c.isDone { emit(.contractFinished(c, success: false)) }
            activeList.removeAll { $0.remaining <= 0 }
            refillTimer -= dt
            if refillTimer <= 0 { refillOffers() }
        }

        // 4. Warehouse construction runs in real time
        if var job = buildTimer {
            job.remaining -= dt * Self.buildSpeed
            if job.remaining <= 0 {
                buildTimer = nil
                facilityTier = job.tier
                refreshMods()
                if live { saveTimer = .infinity }      // save this frame, not in up to 5 s
                if let tier = facility {
                    if !live { awayResearch.append("Warehouse: \(tier.name)") }
                    emit(.constructionDone(tier))
                }
            } else {
                buildTimer = job
            }
        }

        // 5. Research runs in real time
        if var job = researchTimer {
            job.remaining -= dt * Self.researchSpeed
            if job.remaining <= 0 {
                researchTimer = nil
                research.insert(job.id)
                refreshMods()
                if live { saveTimer = .infinity }
                if let p = ResearchProject.find(job.id) {
                    if !live { awayResearch.append(p.title) }
                    emit(.researchDone(p))
                }
            } else {
                researchTimer = job
            }
        }
    }

    /// Queued vehicles take free docks (first come, first served) and start a new shipment.
    private func assignDocks(now: Date, live: Bool = false) {
        while true {
            guard let dock = (0..<docks).first(where: { d in
                    dockClear[d] <= 0 && !fleet.contains { $0.dock == d } && !(live && holdDock?(d) == true)
                  }),
                  let i = fleet.indices.filter({ fleet[$0].phase == .queued }).min(by: { fleet[$0].since < fleet[$1].since })
            else { return }
            fleet[i].phase = .docking(config.fleet.dockSeconds + travelSeconds(dock: dock))
            fleet[i].dock = dock
            fleet[i].since = clock
            fleet[i].job = makeShipment(now: now)
        }
    }

    private func makeShipment(now: Date) -> Shipment {
        defer { nextShipment += 1 }
        // Contract work first: send loads to a client until the contract is covered
        for c in activeList {
            let pending = Double(fleet.filter { $0.job?.contract == c.id && $0.job?.departedAt == nil }.count) * truckload
            if c.delivered + pending < c.units {
                return Shipment(id: nextShipment, destination: c.client, contract: c.id, pickedAt: now)
            }
        }
        var rng = SeededRandomD(seed: UInt64(nextShipment))
        let destination = config.destinations[Int(rng.next() % UInt64(config.destinations.count))]
        return Shipment(id: nextShipment, destination: destination, contract: nil, pickedAt: now)
    }

    private func loadedPrecise(_ truck: Truck) -> Double {
        guard truck.phase == .loading else { return 0 }
        var left = sh
        for t in fleet.filter({ $0.phase == .loading }).sorted(by: { $0.since < $1.since }) {
            let mine = min(left, truckload)
            if t.id == truck.id { return mine }
            left -= mine
        }
        return 0
    }

    private func isReadyPrecise(_ truck: Truck) -> Bool { truck.phase == .loading && loadedPrecise(truck) >= truckload - 0.001 }

    private func performDispatch(_ i: Int, now: Date) {
        let load = truckload
        sh = max(sh - load, 0)
        let earned = load * unitValue
        let researchWasLocked = !researchUnlocked
        money += earned
        lifetimeEarned += earned
        if researchWasLocked && researchUnlocked { emit(.unlocked("research")) }
        companyEarned += earned
        delivered += load
        shipmentsSent += 1
        if fleet[i].dock >= 0 && fleet[i].dock < dockClear.count { dockClear[fleet[i].dock] = config.fleet.clearSeconds }
        fleet[i].job?.units = load
        fleet[i].job?.value = earned
        fleet[i].job?.departedAt = now
        fleet[i].phase = .away(roadSeconds)
        fleet[i].dock = -1
        fleet[i].since = clock
        if let cid = fleet[i].job?.contract, let ci = activeList.firstIndex(where: { $0.id == cid }) {
            activeList[ci].delivered += load
            if activeList[ci].isDone { finishContract(ci) }
        }
        emit(.dispatched(truck: fleet[i].id, amount: earned))
    }

    private func finishContract(_ i: Int) {
        let c = activeList.remove(at: i)
        money += c.reward
        lifetimeEarned += c.reward
        companyEarned += c.reward
        stars += c.stars
        let wasLocked = !researchUnlocked
        contractsCompleted += 1
        awayContracts += 1
        emit(.contractFinished(c, success: true))
        if wasLocked && researchUnlocked { emit(.unlocked("research")) }
    }

    private func refillOffers() {
        refillTimer = 40
        guard contractsUnlocked else { return }
        var attempts = 0
        while offerList.count < 3 && attempts < 20 {
            let offer = ContractBoard.make(id: nextContract, region: config, throughput: max(throughput, 4), valuePerUnit: unitValue)
            nextContract += 1
            attempts += 1
            // One offer per client, and not a client you're already working for
            if offerList.contains(where: { $0.client == offer.client }) || activeList.contains(where: { $0.client == offer.client }) { continue }
            offerList.append(offer)
        }
    }

    /// New vehicles join the fleet by driving in from the road.
    private func growFleet() {
        while fleet.count < fleetSize {
            fleet.append(Truck(id: fleet.count, phase: .away(min(18, roadSeconds * 0.45)), since: clock))
        }
    }

    private func publish() {
        if abs(receiving - r) > 0.01 { receiving = r }
        if abs(stock - s) > 0.01 { stock = s }
        if abs(shipping - sh) > 0.01 { shipping = sh }
        if trucks != fleet { trucks = fleet }
        let waiting = fleet.count { $0.phase == .queued }, atDepot = fleet.count { !$0.isAway }
        let percent = Int((s / max(stockCapacity, 1) * 100).rounded())
        if vehiclesWaiting != waiting { vehiclesWaiting = waiting }
        if trucksAtDepot != atDepot { trucksAtDepot = atDepot }
        if stockPercent != percent { stockPercent = percent }
        if offers != offerList { offers = offerList }
        if contracts != activeList { contracts = activeList }
        if activeResearch != researchTimer { activeResearch = researchTimer }
        if construction != buildTimer { construction = buildTimer }
        if abs(berthClock - berth) > 0.05 { berthClock = berth }
    }

    private func resetRegion(_ id: RegionID) {
        region = id
        let c = id.config
        money = c.startMoney
        levels = Self.freshLevels
        managers = []
        research = []
        researchTimer = nil
        facilityTier = 0
        buildTimer = nil
        refreshMods()
        r = 6; s = c.stockBase * 0.5; sh = c.fleet.baseLoad * 0.8
        fleet = [Truck(id: 0, phase: .queued, since: 0)]
        dockClear = Array(repeating: 0, count: c.fleet.docks)
        offerList = []
        activeList = []
        history = []
        lifetimeEarned = 0
        delivered = 0
        berth = 0
        rushRemaining = 0
        rushCooldown = 0
        refillTimer = 0
        if contractsUnlocked { refillOffers() }
        assignDocks(now: Date())
    }

    // MARK: Background

    /// The app went to the background: remember when, and save.
    func pause() {
        if pausedAt == nil { pausedAt = Date() } // keep the first time if we never really came back
        save(now: true)
    }

    /// How long the app has been in the background (nil when it hasn't been).
    var awaySeconds: TimeInterval? { pausedAt.map { Date().timeIntervalSince($0) } }

    /// Back in the foreground: simulate the time we were away.
    func resumeFromBackground() {
        guard let since = pausedAt else { return }
        pausedAt = nil
        catchUp(since: since)
        publish()
    }

    // MARK: Saving

    nonisolated private struct SaveData: Codable, Sendable {
        var version = 2
        var stars: Int
        var completed: [RegionID]
        var companyEarned: Double
        var contractsCompleted: Int
        var region: RegionID
        var money: Double
        var levels: [String: Int]
        var managers: [String]
        var research: [String]
        var activeResearch: ActiveResearch?
        var receiving: Double
        var stock: Double
        var shipping: Double
        var fleet: [Truck]
        var dockClear: [Double]
        var offers: [Contract]
        var contracts: [Contract]
        var history: [Shipment]
        var lifetimeEarned: Double
        var delivered: Double
        var berth: Double
        var clock: Double
        var nextShipment: Int
        var nextContract: Int
        var finished: Bool? = false
        var shipmentsSent: Int? = 0
        var facilityTier: Int? = 0
        var construction: Construction?
        var savedAt: Date

        init(stars: Int, completed: [RegionID], companyEarned: Double, contractsCompleted: Int, region: RegionID, money: Double,
             levels: [String: Int], managers: [String], research: [String], activeResearch: ActiveResearch?, receiving: Double,
             stock: Double, shipping: Double, fleet: [Truck], dockClear: [Double], offers: [Contract], contracts: [Contract],
             history: [Shipment], lifetimeEarned: Double, delivered: Double, berth: Double, clock: Double, nextShipment: Int,
             nextContract: Int, finished: Bool?, shipmentsSent: Int?, facilityTier: Int?, construction: Construction?, savedAt: Date) {
            (self.stars, self.completed, self.companyEarned, self.contractsCompleted, self.region, self.money) =
                (stars, completed, companyEarned, contractsCompleted, region, money)
            (self.levels, self.managers, self.research, self.activeResearch) = (levels, managers, research, activeResearch)
            (self.receiving, self.stock, self.shipping, self.fleet, self.dockClear) = (receiving, stock, shipping, fleet, dockClear)
            (self.offers, self.contracts, self.history) = (offers, contracts, history)
            (self.lifetimeEarned, self.delivered, self.berth, self.clock) = (lifetimeEarned, delivered, berth, clock)
            (self.nextShipment, self.nextContract, self.finished, self.shipmentsSent) = (nextShipment, nextContract, finished, shipmentsSent)
            (self.facilityTier, self.construction, self.savedAt) = (facilityTier, construction, savedAt)
        }

        /// Every field is read on its own, with a sensible default when it's missing or no longer fits (a field added or
        /// changed by a new version). Lists keep every entry that still reads. So an update never wipes the game.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
            func list<T: Decodable>(_ key: CodingKeys) -> [T] { ((try? c.decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? [] }
            version = value(.version, 2)
            stars = value(.stars, 0)
            completed = list(.completed)
            companyEarned = value(.companyEarned, 0)
            contractsCompleted = value(.contractsCompleted, 0)
            region = value(.region, .riverside)
            money = value(.money, region.config.startMoney)
            levels = value(.levels, [:])
            managers = list(.managers)
            research = list(.research)
            activeResearch = value(.activeResearch, nil)
            receiving = value(.receiving, 0)
            stock = value(.stock, 0)
            shipping = value(.shipping, 0)
            fleet = list(.fleet)
            dockClear = list(.dockClear)
            offers = list(.offers)
            contracts = list(.contracts)
            history = list(.history)
            lifetimeEarned = value(.lifetimeEarned, 0)
            delivered = value(.delivered, 0)
            berth = value(.berth, 0)
            clock = value(.clock, 0)
            nextShipment = value(.nextShipment, 78_442)
            nextContract = value(.nextContract, 1)
            finished = value(.finished, false)
            shipmentsSent = value(.shipmentsSent, 0)
            facilityTier = value(.facilityTier, 0)
            construction = value(.construction, nil)
            savedAt = value(.savedAt, Date())
        }
    }

    /// One list entry that may no longer read (then it's skipped instead of failing the whole list).
    nonisolated private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
    }

    /// Where the game is saved. Launches with developer flags that change the game (`-resetSave`, `-cash`, `-levels`…),
    /// or with `-testSave YES`, use a separate test save, so testing never touches the player's own game.
    static let usesTestSave: Bool = {
        let d = UserDefaults.standard
        if d.bool(forKey: "testSave") { return true }
        return ["resetSave", "cash", "lifetime", "unlockAll", "allResearch", "depotTier", "levels", "region", "autoBuild",
                "researchSpeed", "buildSpeed"].contains { d.object(forKey: $0) != nil }
    }()

    private static var saveDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var saveURL: URL { saveDirectory.appendingPathComponent(usesTestSave ? "waybill-save-test.json" : "waybill-save-v2.json") }
    /// A copy of the last save that loaded fine (made at every launch), used if the save itself can't be read.
    private static var backupURL: URL { saveDirectory.appendingPathComponent(usesTestSave ? "waybill-save-test.backup.json" : "waybill-save-v2.backup.json") }

    /// Saves are encoded and written in order on this queue, off the main thread, so saving never costs a frame.
    private static let saveQueue = DispatchQueue(label: "com.yorben.waybill.save", qos: .utility)

    /// - now: wait until it's on disk (the app is about to be suspended).
    func save(now: Bool = false) {
        let data = SaveData(stars: stars, completed: completed, companyEarned: companyEarned, contractsCompleted: contractsCompleted,
                            region: region, money: money,
                            levels: Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value) }),
                            managers: managers.map(\.rawValue), research: Array(research), activeResearch: researchTimer,
                            receiving: r, stock: s, shipping: sh, fleet: fleet, dockClear: dockClear,
                            offers: offerList, contracts: activeList, history: history,
                            lifetimeEarned: lifetimeEarned, delivered: delivered, berth: berth, clock: clock,
                            nextShipment: nextShipment, nextContract: nextContract, finished: finished, shipmentsSent: shipmentsSent,
                            facilityTier: facilityTier, construction: buildTimer, savedAt: Date())
        let url = Self.saveURL, backup = Self.backupURL
        savesSinceBackup += 1
        let refreshBackup = savesSinceBackup >= 24          // about every two minutes of play
        if refreshBackup { savesSinceBackup = 0 }
        let write = {
            guard let encoded = try? JSONEncoder().encode(data) else { return }
            try? encoded.write(to: url, options: .atomic)
            if refreshBackup { try? encoded.write(to: backup, options: .atomic) }
        }
        if now { Self.saveQueue.sync(execute: write) } else { Self.saveQueue.async(execute: write) }
    }

    /// Returns false when there's no save yet. A save that can't be read is never overwritten: the backup is used
    /// instead, and the unreadable file is kept next to it.
    private func load() -> Bool {
        let fm = FileManager.default
        func read(_ url: URL) -> SaveData? {
            guard let raw = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SaveData.self, from: raw)
        }
        func keepUnreadable() {
            guard fm.fileExists(atPath: Self.saveURL.path) else { return }
            let kept = Self.saveDirectory.appendingPathComponent("waybill-save-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.moveItem(at: Self.saveURL, to: kept)
            NSLog("[Waybill] the save could not be read; kept it as %@", kept.lastPathComponent)
        }
        let data: SaveData
        if let main = read(Self.saveURL) {
            data = main
            try? fm.removeItem(at: Self.backupURL)          // this save is good: it becomes the backup
            try? fm.copyItem(at: Self.saveURL, to: Self.backupURL)
        } else if let backup = read(Self.backupURL) {
            keepUnreadable()
            data = backup
        } else {
            keepUnreadable()
            return false
        }
        stars = data.stars
        completed = data.completed
        companyEarned = data.companyEarned
        contractsCompleted = data.contractsCompleted
        region = data.region
        money = data.money
        levels = Self.freshLevels
        for (key, value) in data.levels { if let k = StageKind(rawValue: key) { levels[k] = value } }
        managers = Set(data.managers.compactMap(StageKind.init(rawValue:)))
        research = Set(data.research)
        facilityTier = min(max(data.facilityTier ?? 0, 0), max(region.config.facility.count - 1, 0))
        buildTimer = data.construction
        refreshMods()
        researchTimer = data.activeResearch
        r = data.receiving
        s = data.stock
        sh = data.shipping
        fleet = data.fleet
        dockClear = data.dockClear
        offerList = data.offers
        activeList = data.contracts
        history = data.history
        lifetimeEarned = data.lifetimeEarned
        delivered = data.delivered
        berth = data.berth
        clock = data.clock
        nextShipment = data.nextShipment
        nextContract = data.nextContract
        finished = data.finished ?? false
        shipmentsSent = data.shipmentsSent ?? 0
        var seen = Set<Int>()
        fleet = fleet.filter { seen.insert($0.id).inserted }
        if fleet.isEmpty { fleet = [Truck(id: 0, phase: .queued, since: clock)] }
        growFleet()
        NSLog("[Waybill] loaded %@: %@, money %.0f, research %d, levels %@, warehouse %d, saved %@", Self.saveURL.lastPathComponent,
              region.rawValue, money, research.count, levels.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ","),
              facilityTier + 1, "\(data.savedAt)")
        catchUp(since: data.savedAt)
        return true
    }

    /// `-resetSave YES` (always a test save, see `usesTestSave`).
    private func deleteSave() {
        try? FileManager.default.removeItem(at: Self.saveURL)
        try? FileManager.default.removeItem(at: Self.backupURL)
    }

    /// Simulate the time the app was closed (up to the offline cap), in one-second steps.
    func catchUp(since date: Date) {
        let elapsed = min(Date().timeIntervalSince(date), offlineCapHours * 3600)
        guard elapsed > 30 else { return }
        let moneyBefore = money, deliveredBefore = delivered
        awayContracts = 0
        awayResearch = []
        catchingUp = true
        defer { catchingUp = false }
        var t = 0.0
        while t < elapsed {
            let step = min(1.0, elapsed - t)
            simulate(dt: step, live: false, now: date.addingTimeInterval(t + step))
            t += step
        }
        awayReport = AwayReport(seconds: elapsed, earned: money - moneyBefore, delivered: delivered - deliveredBefore,
                                hadDispatcher: hasDispatcher, contractsDone: awayContracts, research: awayResearch)
        catchingUp = false
        heldFor = [:]
        emit(.caughtUp)
    }
}
