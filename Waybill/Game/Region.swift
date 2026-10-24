import Foundation

/// The five regions of the Waybill story. Each is a new diorama with its own twist.
enum RegionID: String, CaseIterable, Codable, Identifiable {
    case riverside, harbour, granite, metro, orbit
    var id: String { rawValue }
    var config: RegionConfig { RegionConfig.of(self) }
    var next: RegionID? {
        let all = RegionID.allCases
        let i = all.firstIndex(of: self)!
        return i + 1 < all.count ? all[i + 1] : nil
    }
}

/// The four steps every unit goes through. The slowest one limits income: the bottleneck.
/// Every region renames them (cranes, sortation robots, launch pads), but the chain stays the same.
enum StageKind: String, CaseIterable, Codable, Identifiable {
    case receiving, putaway, shipping, fleet
    var id: String { rawValue }
}

/// Fixed numbers for one stage in one region.
struct StageConfig {
    let title: String
    let subtitle: String
    let symbol: String
    let baseRate: Double        // units per minute at level 1 (not used by the fleet)
    let costBase: Double        // price of the first upgrade
    let costGrowth: Double      // each level costs this much more (×)
    let managerTitle: String
    let managerCost: Double
    let managerPerk: String
}

/// How the region's vehicles carry goods out (trucks, trains, vans, rockets).
struct FleetConfig {
    let vehicle: String          // "truck"
    let vehicles: String         // "trucks"
    let idPrefix: String         // "TRK"
    let firstID: Int             // 2051 → TRK-2051, TRK-2052, …
    let roadSeconds: Double      // round trip, dock to customer and back
    let dockSeconds: Double      // time to back into the dock
    let clearSeconds: Double     // the dock stays blocked this long after a departure
    let docks: Int
    let dockNames: [String]      // "Bay 2"
    let baseLoad: Double         // units per vehicle at level 1
    let loadGrowth: Double       // +this fraction of the base per level
    let levelsPerVehicle: Int    // one more vehicle every N levels
    let maxVehicles: Int
    let verb: String             // "Dispatch"
    let symbol: String           // SF Symbol
    let thumbnail: String        // asset name of the rendered vehicle
    /// Where each dock sits along the yard lane, in metres (bigger = nearer the gate). Vehicles drive from the
    /// waiting line to their dock, so far docks take longer. Empty = no yard drive (docks right at the queue).
    var dockPositions: [Double] = []
}

/// One step of a site's growth. In Riverside the warehouse fits out more bays and then grows longer,
/// section by section; every step is built over a few real minutes and shows in the world.
struct FacilityTier {
    let name: String             // "East wing"
    let detail: String           // what changes in the world
    let symbol: String
    let docks: Int               // loading docks in total
    let cost: Double
    let minutes: Double          // build time
    let stock: Double            // storage ×, relative to the start
    let putaway: Double          // put-away speed ×, relative to the start
    var seconds: Double { minutes * 60 }
}

/// Ships arrive in windows (Harbour City): the quay cranes only unload while a ship is berthed.
struct InboundWindows {
    let berthed: Double
    let away: Double
    var cycle: Double { berthed + away }
    var share: Double { berthed / cycle }
}

struct UnitNames {
    let one: String
    let many: String
    let symbol: String
}

/// Everything that makes a region different.
struct RegionConfig {
    let id: RegionID
    let number: Int
    let name: String             // "Riverside"
    let site: String             // "Riverside Depot"
    let blurb: String            // one line for the expansion card
    let mechanic: String         // what's new here
    let unit: UnitNames
    let unitValue: Double
    let startMoney: Double
    let stages: [StageKind: StageConfig]
    let fleet: FleetConfig
    let windows: InboundWindows?
    let goal: Double             // lifetime earnings here that open the next region
    let destinations: [String]
    let stockBase: Double
    let stockPerLevel: Double
    let receivingCapacity: Double
    let shippingCapacity: Double
    /// How the site grows (first entry = how it starts). Empty = it doesn't.
    var facility: [FacilityTier] = []

    var code: String { "R\(number)" }
    func stage(_ kind: StageKind) -> StageConfig { stages[kind]! }

    static func of(_ id: RegionID) -> RegionConfig {
        switch id {
        case .riverside: riverside
        case .harbour: harbour
        case .granite: granite
        case .metro: metro
        case .orbit: orbit
        }
    }
}

// MARK: - Shared economic shape

/// Every region uses the same price shape, scaled by a factor (×3 per region, ×300 for the finale).
/// Costs grow 30% per level (fleet 32%). Tuned with balance.py so a region takes 1.5 → 4.5 days.
private enum Shape {
    static let costBase: [StageKind: Double] = [.receiving: 15, .putaway: 20, .shipping: 25, .fleet: 45]
    static let managerCost: [StageKind: Double] = [.receiving: 12_000, .putaway: 4_000, .shipping: 30_000, .fleet: 350]
    static func growth(_ kind: StageKind) -> Double { kind == .fleet ? 1.32 : 1.3 }
}

extension StageConfig {
    /// A stage with the shared price shape, scaled by `scale`.
    init(_ kind: StageKind, scale: Double, title: String, subtitle: String, symbol: String, baseRate: Double,
         managerTitle: String, managerPerk: String) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, baseRate: baseRate,
                  costBase: Shape.costBase[kind]! * scale, costGrowth: Shape.growth(kind),
                  managerTitle: managerTitle, managerCost: Shape.managerCost[kind]! * scale, managerPerk: managerPerk)
    }
}

// MARK: - The regions

extension RegionConfig {
    /// Region 1. The Dispatcher arrives after ~6 minutes, all managers within ~35 minutes,
    /// Harbour City opens after about a day and a half (balance.py).
    static let riverside = RegionConfig(
        id: .riverside, number: 1, name: "Riverside", site: "Riverside Depot",
        blurb: "A small depot by the river. Where it all starts.",
        mechanic: "Receive, store, ship and drive: the four-step chain.",
        unit: UnitNames(one: "pallet", many: "pallets", symbol: "shippingbox.fill"),
        unitValue: 8, startMoney: 60,
        stages: [
            .receiving: StageConfig(.receiving, scale: 1, title: "Receiving", subtitle: "Unload supplier trucks", symbol: "arrow.down.to.line.compact",
                                    baseRate: 18, managerTitle: "Dock lead", managerPerk: "2× unloading"),
            .putaway: StageConfig(.putaway, scale: 1, title: "Put-away", subtitle: "Forklifts to the racks", symbol: "square.stack.3d.up.fill",
                                    baseRate: 15, managerTitle: "Floor lead", managerPerk: "2× forklifts"),
            .shipping: StageConfig(.shipping, scale: 1, title: "Shipping", subtitle: "Pick, pack and stage", symbol: "shippingbox.fill",
                                    baseRate: 18, managerTitle: "Shipping lead", managerPerk: "2× loading"),
            .fleet: StageConfig(.fleet, scale: 1, title: "Fleet", subtitle: "Trucks out to customers", symbol: "truck.box.fill",
                                    baseRate: 0, managerTitle: "Dispatcher", managerPerk: "Dispatches for you"),
        ],
        // Times match the yard you see: the drive out and back includes the yard lanes, backing in takes ~10 s,
        // the bay needs a few seconds to close up. Bigger loads keep the income where it was.
        fleet: FleetConfig(vehicle: "truck", vehicles: "trucks", idPrefix: "TRK", firstID: 2051, roadSeconds: 52, dockSeconds: 10.5, clearSeconds: 12,
                           docks: 1, dockNames: ["Bay 2", "Bay 1", "Bay 3", "Bay 4", "Bay 5", "Bay 6"], baseLoad: 14, loadGrowth: 0.25,
                           levelsPerVehicle: 4, maxVehicles: 12, verb: "Dispatch", symbol: "truck.box.fill", thumbnail: "thumb-truck",
                           dockPositions: [0, -12, 12, 24, 36, 48]),
        windows: nil, goal: 50_000_000,
        destinations: ["Ashford", "Millbrook", "Kestrel Bay", "Fernhill", "Oakhaven", "Lindmere", "Brackley", "Stonebridge", "Wrenfield", "Harlow Market", "Elmstead", "Corran"],
        stockBase: 60, stockPerLevel: 20, receivingCapacity: 30, shippingCapacity: 40,
        facility: [
            FacilityTier(name: "Starter depot", detail: "One working bay", symbol: "building.fill",
                         docks: 1, cost: 0, minutes: 0, stock: 1, putaway: 1),
            FacilityTier(name: "Three bays", detail: "Bays 1 and 3 fitted out, a pallet truck for each", symbol: "door.garage.open",
                         docks: 3, cost: 1_500, minutes: 0.5, stock: 1, putaway: 1),
            FacilityTier(name: "East wing", detail: "A new hall section with bay 4", symbol: "building.2.fill",
                         docks: 4, cost: 45_000, minutes: 1.5, stock: 1.3, putaway: 1.15),
            FacilityTier(name: "Long hall", detail: "Another section with bay 5", symbol: "building.2.fill",
                         docks: 5, cost: 600_000, minutes: 3, stock: 1.6, putaway: 1.3),
            FacilityTier(name: "Distribution centre", detail: "The full hall with bay 6", symbol: "building.columns.fill",
                         docks: 6, cost: 7_000_000, minutes: 5, stock: 2, putaway: 1.5),
        ])

    /// Region 2: ships arrive in windows, cranes unload them, trucks haul containers inland.
    static let harbour = RegionConfig(
        id: .harbour, number: 2, name: "Harbour City", site: "Harbour City Terminal",
        blurb: "A container terminal on the bay. Cranes, ships and stacks of steel boxes.",
        mechanic: "Ships berth in windows. The cranes only unload while a ship is in.",
        unit: UnitNames(one: "container", many: "containers", symbol: "shippingbox.and.arrow.backward.fill"),
        unitValue: 24, startMoney: 180,
        stages: [
            .receiving: StageConfig(.receiving, scale: 3, title: "Quay cranes", subtitle: "Unload berthed ships", symbol: "arrow.down.to.line.compact",
                                    baseRate: 14, managerTitle: "Harbour master", managerPerk: "2× crane speed"),
            .putaway: StageConfig(.putaway, scale: 3, title: "Yard stacking", subtitle: "Straddle carriers to the stacks", symbol: "square.stack.3d.up.fill",
                                    baseRate: 12, managerTitle: "Yard planner", managerPerk: "2× stacking"),
            .shipping: StageConfig(.shipping, scale: 3, title: "Gate loading", subtitle: "Reach stackers load the trucks", symbol: "shippingbox.fill",
                                    baseRate: 13, managerTitle: "Gate supervisor", managerPerk: "2× loading"),
            .fleet: StageConfig(.fleet, scale: 3, title: "Haulage", subtitle: "Container trucks inland", symbol: "truck.box.fill",
                                    baseRate: 0, managerTitle: "Haulage dispatcher", managerPerk: "Dispatches for you"),
        ],
        fleet: FleetConfig(vehicle: "truck", vehicles: "trucks", idPrefix: "HCT", firstID: 3101, roadSeconds: 44, dockSeconds: 8, clearSeconds: 4,
                           docks: 2, dockNames: ["Lane A", "Lane B"], baseLoad: 6, loadGrowth: 0.25, levelsPerVehicle: 4, maxVehicles: 14,
                           verb: "Dispatch", symbol: "truck.box.fill", thumbnail: "thumb-hauler"),
        windows: InboundWindows(berthed: 60, away: 30), goal: 2_500_000_000,
        destinations: ["Port Avel", "Calder", "Northgate", "Saltmarsh", "Bryn Halen", "Westmoor", "Ostrava Yard", "Pellmere", "Gallow Point", "Tidewell"],
        stockBase: 80, stockPerLevel: 24, receivingCapacity: 60, shippingCapacity: 50)

    /// Region 3: big batches by rail through the mountains.
    static let granite = RegionConfig(
        id: .granite, number: 3, name: "Granite Pass", site: "Granite Pass Railhead",
        blurb: "A railhead below snowy peaks. Long trains, tunnels and a viaduct.",
        mechanic: "Trains carry huge loads, but they take their time.",
        unit: UnitNames(one: "crate", many: "crates", symbol: "cube.box.fill"),
        unitValue: 72, startMoney: 540,
        stages: [
            .receiving: StageConfig(.receiving, scale: 9, title: "Truck intake", subtitle: "Trucks down from the valley", symbol: "arrow.down.to.line.compact",
                                    baseRate: 30, managerTitle: "Intake lead", managerPerk: "2× intake"),
            .putaway: StageConfig(.putaway, scale: 9, title: "Transload", subtitle: "Cranes sort crates for the rail", symbol: "square.stack.3d.up.fill",
                                    baseRate: 26, managerTitle: "Crane lead", managerPerk: "2× transload"),
            .shipping: StageConfig(.shipping, scale: 9, title: "Wagon loading", subtitle: "Fill the wagons on the siding", symbol: "shippingbox.fill",
                                    baseRate: 28, managerTitle: "Loading lead", managerPerk: "2× loading"),
            .fleet: StageConfig(.fleet, scale: 9, title: "Rail", subtitle: "Freight trains over the pass", symbol: "train.side.front.car",
                                    baseRate: 0, managerTitle: "Station master", managerPerk: "Departs for you"),
        ],
        fleet: FleetConfig(vehicle: "train", vehicles: "trains", idPrefix: "GP", firstID: 401, roadSeconds: 75, dockSeconds: 16, clearSeconds: 8,
                           docks: 1, dockNames: ["Siding 1"], baseLoad: 60, loadGrowth: 0.2, levelsPerVehicle: 10, maxVehicles: 4,
                           verb: "Depart", symbol: "train.side.front.car", thumbnail: "thumb-train"),
        windows: nil, goal: 60_000_000_000,
        destinations: ["Alder Gap", "Hollin", "Corvette Ridge", "Mirrin", "St. Varen", "Lowfield Junction", "Kalden", "Eastwick", "Brannoch"],
        stockBase: 400, stockPerLevel: 90, receivingCapacity: 200, shippingCapacity: 300)

    /// Region 4: a dense future city. Vans and drones, many small trips.
    static let metro = RegionConfig(
        id: .metro, number: 4, name: "Metro", site: "Metro Micro-Hub",
        blurb: "A glass hub in a dense city. Robots inside, vans and drones outside.",
        mechanic: "Many small trips: electric vans and delivery drones.",
        unit: UnitNames(one: "parcel", many: "parcels", symbol: "shippingbox.fill"),
        unitValue: 216, startMoney: 1_620,
        stages: [
            .receiving: StageConfig(.receiving, scale: 27, title: "Inbound", subtitle: "Autonomous trucks unload", symbol: "arrow.down.to.line.compact",
                                    baseRate: 40, managerTitle: "Inbound AI", managerPerk: "2× inbound"),
            .putaway: StageConfig(.putaway, scale: 27, title: "Sortation", subtitle: "Sorting robots by postcode", symbol: "square.grid.3x3.fill",
                                    baseRate: 36, managerTitle: "Robotics lead", managerPerk: "2× sortation"),
            .shipping: StageConfig(.shipping, scale: 27, title: "Pack-out", subtitle: "Bag, label, load", symbol: "shippingbox.fill",
                                    baseRate: 38, managerTitle: "Pack-out lead", managerPerk: "2× pack-out"),
            .fleet: StageConfig(.fleet, scale: 27, title: "Last mile", subtitle: "Electric vans to the door", symbol: "bolt.car.fill",
                                    baseRate: 0, managerTitle: "Fleet AI", managerPerk: "Sends vans for you"),
        ],
        fleet: FleetConfig(vehicle: "van", vehicles: "vans", idPrefix: "VAN", firstID: 101, roadSeconds: 26, dockSeconds: 5, clearSeconds: 2,
                           docks: 3, dockNames: ["Bay A", "Bay B", "Bay C", "Bay D"], baseLoad: 5, loadGrowth: 0.25, levelsPerVehicle: 2, maxVehicles: 18,
                           verb: "Send out", symbol: "bolt.car.fill", thumbnail: "thumb-van"),
        windows: nil, goal: 320_000_000_000,
        destinations: ["Canal District", "Neon Row", "Eastbank", "Old Mint", "Skyline Park", "Juniper Sq.", "Arcade Quarter", "Halcyon Ave.", "Pier 9", "Union Heights"],
        stockBase: 120, stockPerLevel: 30, receivingCapacity: 60, shippingCapacity: 50)

    /// Region 5: the finale. Payloads to orbit.
    static let orbit = RegionConfig(
        id: .orbit, number: 5, name: "Orbit", site: "Waybill Launch Site",
        blurb: "A launch site on the coast. The last mile is 400 km straight up.",
        mechanic: "Rockets carry the biggest loads of all. Every launch is an event.",
        unit: UnitNames(one: "payload", many: "payloads", symbol: "cube.transparent.fill"),
        unitValue: 2_400, startMoney: 18_000,
        stages: [
            .receiving: StageConfig(.receiving, scale: 300, title: "Cargo intake", subtitle: "Payloads arrive by road", symbol: "arrow.down.to.line.compact",
                                    baseRate: 8, managerTitle: "Intake lead", managerPerk: "2× intake"),
            .putaway: StageConfig(.putaway, scale: 300, title: "Integration", subtitle: "Clean-room payload integration", symbol: "square.stack.3d.up.fill",
                                    baseRate: 7, managerTitle: "Integration lead", managerPerk: "2× integration"),
            .shipping: StageConfig(.shipping, scale: 300, title: "Stacking & fuel", subtitle: "Fairings on, tanks full", symbol: "fuelpump.fill",
                                    baseRate: 7.5, managerTitle: "Pad lead", managerPerk: "2× pad work"),
            .fleet: StageConfig(.fleet, scale: 300, title: "Launch", subtitle: "Reusable rockets to orbit", symbol: "airplane.departure",
                                    baseRate: 0, managerTitle: "Flight director", managerPerk: "Launches for you"),
        ],
        fleet: FleetConfig(vehicle: "rocket", vehicles: "rockets", idPrefix: "WB", firstID: 1, roadSeconds: 90, dockSeconds: 12, clearSeconds: 8,
                           docks: 1, dockNames: ["Pad 39"], baseLoad: 4, loadGrowth: 0.25, levelsPerVehicle: 12, maxVehicles: 3,
                           verb: "Launch", symbol: "airplane.departure", thumbnail: "thumb-rocket"),
        windows: nil, goal: 380_000_000_000,
        destinations: ["LEO · 400 km", "Station Meridian", "SSO · 550 km", "Lunar Gateway", "GEO · 36,000 km", "Depot Halo"],
        stockBase: 24, stockPerLevel: 6, receivingCapacity: 16, shippingCapacity: 20)
}
