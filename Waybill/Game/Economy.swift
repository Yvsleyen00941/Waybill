import Foundation

/// Everything research, reputation and the network add on top of the base numbers.
struct Modifiers {
    var speed: [StageKind: Double] = [:]
    var value = 1.0
    var trip = 1.0
    var load = 1.0
    var stock = 1.0
    var offlineHours = 0.0
    var contractSlots = 0
    var docks = 0
    var berth = 1.0

    init() {}

    init(research: Set<String>) {
        for id in research {
            guard let project = ResearchProject.find(id) else { continue }
            for effect in project.effects {
                switch effect {
                case .speed(let kind, let m): speed[kind, default: 1] *= m
                case .value(let m): value *= m
                case .trip(let m): trip *= m
                case .load(let m): load *= m
                case .stock(let m): stock *= m
                case .offline(let h): offlineHours += h
                case .contractSlots(let n): contractSlots += n
                case .docks(let n): docks += n
                case .berth(let m): berth *= m
                }
            }
        }
    }

    /// A finished warehouse expansion: more docks, more room, more forklifts.
    mutating func apply(_ tier: FacilityTier, baseDocks: Int) {
        docks += tier.docks - baseDocks
        stock *= tier.stock
        speed[.putaway, default: 1] *= tier.putaway
    }

    func speed(_ kind: StageKind) -> Double { speed[kind] ?? 1 }
}

/// All the formulas in one place, so balancing is easy.
/// Costs grow exponentially, speeds grow linearly with a ×2 bump at every milestone (AdVenture Capitalist maths).
enum Economy {
    static let milestones = [10, 25, 50, 100, 150, 200, 300]
    static let rushDuration: Double = 20
    static let rushCooldown: Double = 60
    static let baseOfflineHours: Double = 8
    /// Each reputation star adds this much income, forever.
    static let starBonus = 0.01
    /// Each finished region adds this much income in every later region.
    static let networkBonus = 0.5

    /// Cost of going from `level` to `level + 1`.
    static func upgradeCost(_ c: StageConfig, level: Int) -> Double {
        (c.costBase * pow(c.costGrowth, Double(level - 1))).rounded()
    }

    /// Total cost of buying `count` levels starting at `level`.
    static func upgradeCost(_ c: StageConfig, level: Int, count: Int) -> Double {
        (0..<count).reduce(0) { $0 + upgradeCost(c, level: level + $1) }
    }

    /// How many levels you can afford right now (at least 0).
    static func affordableLevels(_ c: StageConfig, level: Int, money: Double, limit: Int = 1000) -> Int {
        var total = 0.0, n = 0
        while n < limit {
            let next = upgradeCost(c, level: level + n)
            if total + next > money { break }
            total += next
            n += 1
        }
        return n
    }

    /// Speed doubles at every milestone level.
    static func milestoneMultiplier(level: Int) -> Double {
        pow(2, Double(milestones.filter { level >= $0 }.count))
    }

    static func nextMilestone(after level: Int) -> Int? { milestones.first { $0 > level } }

    /// Units per minute for receiving / put-away / shipping (receiving is the rate while a ship is in).
    static func rate(_ c: StageConfig, kind: StageKind, level: Int, managed: Bool, rush: Bool, mods: Modifiers) -> Double {
        c.baseRate * Double(level) * milestoneMultiplier(level: level) * (managed ? 2 : 1) * (rush ? 2 : 1) * mods.speed(kind)
    }

    // MARK: Fleet

    static func vehicles(level: Int, _ f: FleetConfig) -> Int { min(1 + (level - 1) / f.levelsPerVehicle, f.maxVehicles) }

    static func load(level: Int, _ f: FleetConfig, mods: Modifiers) -> Double {
        (f.baseLoad * (1 + f.loadGrowth * Double(level - 1)) * milestoneMultiplier(level: level) * mods.load).rounded()
    }

    static func roadSeconds(_ f: FleetConfig, mods: Modifiers) -> Double { f.roadSeconds * mods.trip }

    /// Units per minute the fleet can carry when every vehicle runs non-stop (road + yard + docking).
    /// - travel: average seconds from the waiting line to a dock (Riverside's long hall).
    static func fleetRate(level: Int, _ f: FleetConfig, mods: Modifiers, rush: Bool, travel: Double = 0) -> Double {
        min(vehicleCap(level: level, f, mods: mods, travel: travel), dockCap(level: level, f, mods: mods, travel: travel)) * (rush ? 2 : 1)
    }

    /// What the vehicles could carry if docks were never busy.
    static func vehicleCap(level: Int, _ f: FleetConfig, mods: Modifiers, travel: Double = 0) -> Double {
        let cycle = roadSeconds(f, mods: mods) + f.dockSeconds + travel
        return Double(vehicles(level: level, f)) * load(level: level, f, mods: mods) * 60 / cycle
    }

    /// What the docks can load per minute (each dock is busy while a vehicle drives up, backs in, loads and clears).
    static func dockCap(level: Int, _ f: FleetConfig, mods: Modifiers, travel: Double = 0) -> Double {
        let docks = Double(f.docks + mods.docks)
        return docks * 60 / (f.dockSeconds + travel + f.clearSeconds + 2) * load(level: level, f, mods: mods)
    }

    static func stockCapacity(_ r: RegionConfig, putawayLevel: Int, mods: Modifiers) -> Double {
        ((r.stockBase + r.stockPerLevel * Double(putawayLevel - 1)) * mods.stock).rounded()
    }

    /// Reputation you earn by expanding: grows with the square root of what the region earned (diminishing returns).
    static func expansionStars(lifetime: Double, goal: Double) -> Int {
        guard goal.isFinite, goal > 0 else { return 0 }
        return max(Int((10 * sqrt(lifetime / goal)).rounded(.down)), 0)
    }
}

/// Money and numbers formatted the way the interface shows them ($12.4K, 3.2M).
enum Format {
    static func money(_ value: Double) -> String { "$" + short(value) }

    static func short(_ value: Double) -> String {
        let v = abs(value)
        let sign = value < 0 ? "-" : ""
        switch v {
        case ..<10_000: return sign + v.formatted(.number.precision(.fractionLength(0)))
        case ..<1_000_000: return sign + trimmed(v / 1_000) + "K"
        case ..<1_000_000_000: return sign + trimmed(v / 1_000_000) + "M"
        case ..<1_000_000_000_000: return sign + trimmed(v / 1_000_000_000) + "B"
        default: return sign + trimmed(v / 1_000_000_000_000) + "T"
        }
    }

    private static func trimmed(_ v: Double) -> String {
        v >= 100 ? v.formatted(.number.precision(.fractionLength(0))) : v.formatted(.number.precision(.fractionLength(1)))
    }

    static func rate(_ perMinute: Double) -> String {
        perMinute >= 100 ? short(perMinute) : perMinute.formatted(.number.precision(.fractionLength(perMinute < 10 ? 1 : 0)))
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        if s >= 3600 { return s % 3600 / 60 == 0 ? "\(s / 3600)h" : "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }

    /// "13:02" for a date.
    static func clock(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
