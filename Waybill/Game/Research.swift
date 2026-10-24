import Foundation

/// What a finished research project does to the numbers.
enum ResearchEffect {
    case speed(StageKind, Double)   // stage rate ×
    case value(Double)              // value per unit ×
    case trip(Double)               // round-trip time × (below 1 = faster)
    case load(Double)               // vehicle load ×
    case stock(Double)              // stock capacity ×
    case offline(Double)            // + hours of offline earnings
    case contractSlots(Int)         // + contracts at the same time
    case docks(Int)                 // + loading docks
    case berth(Double)              // ships stay berthed × longer (Harbour City)

    var label: String {
        switch self {
        case .speed(let kind, let m): "\(Self.percent(m)) \(Self.stageName(kind))"
        case .value(let m): "\(Self.percent(m)) value"
        case .trip(let m): "\(Int(((1 / m) - 1) * 100 + 0.5))% faster trips"
        case .load(let m): "\(Self.percent(m)) load"
        case .stock(let m): "\(Self.percent(m)) storage"
        case .offline(let h): "+\(Int(h))h offline earnings"
        case .contractSlots(let n): "+\(n) contract slot"
        case .docks(let n): "+\(n) loading dock"
        case .berth(let m): "\(Self.percent(m)) berth time"
        }
    }

    private static func percent(_ m: Double) -> String {
        m >= 2 ? "×\(m.formatted(.number.precision(.fractionLength(0...1))))" : "+\(Int((m - 1) * 100 + 0.5))%"
    }
    private static func stageName(_ kind: StageKind) -> String {
        switch kind {
        case .receiving: "inbound"
        case .putaway: "storage speed"
        case .shipping: "loading"
        case .fleet: "fleet"
        }
    }
}

/// A research project: costs money and real time, changes the numbers *and* the world.
struct ResearchProject: Identifiable {
    let id: String
    let title: String
    let detail: String          // what you'll see in the world
    let symbol: String
    let cost: Double
    let minutes: Double
    let effects: [ResearchEffect]

    var seconds: Double { minutes * 60 }
    var effectLabel: String { effects.map(\.label).joined(separator: " · ") }

    static func projects(for region: RegionID) -> [ResearchProject] {
        switch region {
        case .riverside: riverside
        case .harbour: harbour
        case .granite: granite
        case .metro: metro
        case .orbit: orbit
        }
    }

    static func find(_ id: String) -> ResearchProject? {
        for region in RegionID.allCases { if let p = projects(for: region).first(where: { $0.id == id }) { return p } }
        return nil
    }

    // MARK: Riverside

    static let riverside: [ResearchProject] = [
        ResearchProject(id: "r1.solar", title: "Solar roof", detail: "Panels across the warehouse roof.", symbol: "sun.max.fill",
                        cost: 9_000, minutes: 3, effects: [.value(1.15)]),
        ResearchProject(id: "r1.canteen", title: "Staff canteen", detail: "A pavilion with tables and parasols.", symbol: "cup.and.saucer.fill",
                        cost: 25_000, minutes: 5, effects: [.offline(4), .contractSlots(1)]),
        ResearchProject(id: "r1.eforklift", title: "Electric forklifts", detail: "Quiet forklifts in Waybill colours, plus chargers.", symbol: "bolt.fill",
                        cost: 60_000, minutes: 8, effects: [.speed(.putaway, 1.5)]),
        ResearchProject(id: "r1.floodlights", title: "Floodlit yard", detail: "Tall floodlight masts for the night shift.", symbol: "lightbulb.max.fill",
                        cost: 140_000, minutes: 10, effects: [.speed(.receiving, 1.5)]),
        ResearchProject(id: "r1.conveyor", title: "Conveyor line", detail: "A powered belt out to a parcel shed.", symbol: "arrow.left.arrow.right",
                        cost: 320_000, minutes: 14, effects: [.speed(.shipping, 1.5)]),
        ResearchProject(id: "r1.routes", title: "Route planning", detail: "Aero kits on every truck.", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                        cost: 650_000, minutes: 18, effects: [.trip(0.75)]),
        ResearchProject(id: "r1.highbay", title: "High-bay racking", detail: "Two tall racks behind the yard.", symbol: "square.stack.3d.up.fill",
                        cost: 1_100_000, minutes: 22, effects: [.stock(2), .speed(.putaway, 1.25)]),
        ResearchProject(id: "r1.coldchain", title: "Cold chain", detail: "Reefer units and a cold store.", symbol: "snowflake",
                        cost: 1_800_000, minutes: 28, effects: [.value(1.3)]),
    ]

    // MARK: Harbour City

    static let harbour: [ResearchProject] = [
        ResearchProject(id: "r2.shorepower", title: "Shore power", detail: "Ships plug in at the quay.", symbol: "powerplug.fill",
                        cost: 27_000, minutes: 5, effects: [.value(1.15)]),
        ResearchProject(id: "r2.twinlift", title: "Twin-lift spreaders", detail: "Cranes lift two containers at once.", symbol: "arrow.up.and.down.square.fill",
                        cost: 75_000, minutes: 8, effects: [.speed(.receiving, 1.5)]),
        ResearchProject(id: "r2.lounge", title: "Drivers' lounge", detail: "A rest stop by the gate.", symbol: "cup.and.saucer.fill",
                        cost: 180_000, minutes: 10, effects: [.offline(4), .contractSlots(1)]),
        ResearchProject(id: "r2.rmg", title: "Automated stacking", detail: "Rail-mounted gantries over the stacks.", symbol: "square.grid.3x3.square",
                        cost: 420_000, minutes: 14, effects: [.speed(.putaway, 1.5)]),
        ResearchProject(id: "r2.wind", title: "Breakwater turbines", detail: "Wind turbines on the breakwater.", symbol: "wind",
                        cost: 960_000, minutes: 18, effects: [.value(1.2)]),
        // (The yard has two loading lanes under the crane, so the gate speeds trucks through instead of adding a dock)
        ResearchProject(id: "r2.ocr", title: "Smart gate", detail: "Camera portals wave trucks through the gate.", symbol: "barcode.viewfinder",
                        cost: 1_950_000, minutes: 22, effects: [.speed(.shipping, 1.5), .trip(0.85)]),
        ResearchProject(id: "r2.berth", title: "Second berth", detail: "A second ship at the quay.", symbol: "ferry.fill",
                        cost: 3_300_000, minutes: 28, effects: [.berth(1.5)]),
        ResearchProject(id: "r2.reefer", title: "Reefer stacks", detail: "Powered racks for cold containers.", symbol: "snowflake",
                        cost: 5_400_000, minutes: 34, effects: [.value(1.3)]),
    ]

    // MARK: Granite Pass

    static let granite: [ResearchProject] = [
        ResearchProject(id: "r3.hydro", title: "Hydro power", detail: "A small dam above the railhead.", symbol: "drop.fill",
                        cost: 81_000, minutes: 6, effects: [.value(1.15)]),
        ResearchProject(id: "r3.gantry", title: "Gantry crane", detail: "A big crane over the transload yard.", symbol: "square.stack.3d.up.fill",
                        cost: 225_000, minutes: 9, effects: [.speed(.putaway, 1.5)]),
        ResearchProject(id: "r3.chalet", title: "Crew chalet", detail: "A timber chalet for the night crews.", symbol: "house.lodge.fill",
                        cost: 540_000, minutes: 12, effects: [.offline(4), .contractSlots(1)]),
        ResearchProject(id: "r3.catenary", title: "Electrified line", detail: "Overhead wires and an electric locomotive.", symbol: "bolt.horizontal.fill",
                        cost: 1_260_000, minutes: 16, effects: [.trip(0.8)]),
        ResearchProject(id: "r3.sidings", title: "Longer sidings", detail: "Longer trains with more wagons.", symbol: "train.side.rear.car",
                        cost: 2_880_000, minutes: 20, effects: [.load(1.5)]),
        ResearchProject(id: "r3.snowsheds", title: "Snow sheds", detail: "Galleries that keep the line open.", symbol: "snowflake",
                        cost: 5_850_000, minutes: 25, effects: [.trip(0.8)]),
        ResearchProject(id: "r3.loader", title: "Rapid loader", detail: "A loading tower over the siding.", symbol: "arrow.down.to.line",
                        cost: 9_900_000, minutes: 30, effects: [.speed(.shipping, 1.5), .speed(.receiving, 1.25)]),
        ResearchProject(id: "r3.observatory", title: "Summit observatory", detail: "A dome on the peak (weather forecasting).", symbol: "moon.stars.fill",
                        cost: 16_200_000, minutes: 36, effects: [.value(1.3)]),
    ]

    // MARK: Metro

    static let metro: [ResearchProject] = [
        ResearchProject(id: "r4.facade", title: "Solar facade", detail: "Photovoltaic glass on the hub.", symbol: "sun.max.fill",
                        cost: 243_000, minutes: 6, effects: [.value(1.15)]),
        ResearchProject(id: "r4.robots", title: "Sorter swarm", detail: "Hundreds of tiny sorting robots.", symbol: "circle.grid.3x3.fill",
                        cost: 675_000, minutes: 9, effects: [.speed(.putaway, 1.5)]),
        ResearchProject(id: "r4.garden", title: "Rooftop garden", detail: "Trees and a café on the roof.", symbol: "leaf.fill",
                        cost: 1_620_000, minutes: 12, effects: [.offline(4), .contractSlots(1)]),
        ResearchProject(id: "r4.drones", title: "Drone delivery", detail: "Drones fly from rooftop pads.", symbol: "airplane",
                        cost: 3_780_000, minutes: 16, effects: [.load(1.5)]),
        ResearchProject(id: "r4.lockers", title: "Parcel lockers", detail: "Locker walls around the block.", symbol: "lock.square.stack.fill",
                        cost: 8_640_000, minutes: 20, effects: [.speed(.shipping, 1.5)]),
        ResearchProject(id: "r4.autonomous", title: "Autonomous vans", detail: "Driverless vans with light bars.", symbol: "car.side.fill",
                        cost: 17_550_000, minutes: 25, effects: [.trip(0.75)]),
        ResearchProject(id: "r4.hyperloop", title: "Freight hyperloop", detail: "A tube line feeding the hub.", symbol: "tram.tunnel.fill",
                        cost: 29_700_000, minutes: 30, effects: [.speed(.receiving, 1.5), .docks(1)]),
        ResearchProject(id: "r4.skyport", title: "Skyport", detail: "A landing deck for cargo eVTOLs.", symbol: "airplane.circle.fill",
                        cost: 48_600_000, minutes: 36, effects: [.value(1.3)]),
    ]

    // MARK: Orbit

    static let orbit: [ResearchProject] = [
        ResearchProject(id: "r5.solarfarm", title: "Solar farm", detail: "Fields of panels behind the dunes.", symbol: "sun.max.fill",
                        cost: 2_700_000, minutes: 6, effects: [.value(1.15)]),
        ResearchProject(id: "r5.landing", title: "Booster landing", detail: "Boosters fly back to a landing pad.", symbol: "arrow.down.circle.fill",
                        cost: 7_500_000, minutes: 10, effects: [.trip(0.75)]),
        ResearchProject(id: "r5.cleanroom", title: "Clean room II", detail: "A second integration building.", symbol: "square.stack.3d.up.fill",
                        cost: 18_000_000, minutes: 14, effects: [.speed(.putaway, 1.5), .offline(4)]),
        ResearchProject(id: "r5.methane", title: "Methane plant", detail: "Make propellant on site.", symbol: "flame.fill",
                        cost: 42_000_000, minutes: 18, effects: [.speed(.shipping, 1.5)]),
        ResearchProject(id: "r5.pad", title: "Second pad", detail: "A second launch pad and tower.", symbol: "airplane.departure",
                        cost: 96_000_000, minutes: 24, effects: [.docks(1), .contractSlots(1)]),
        ResearchProject(id: "r5.fairing", title: "Stretched fairing", detail: "Taller rockets carry more.", symbol: "arrow.up.and.down",
                        cost: 195_000_000, minutes: 30, effects: [.load(1.5)]),
        ResearchProject(id: "r5.elevator", title: "Tether study", detail: "A test tether rising into the sky.", symbol: "arrow.up.to.line",
                        cost: 330_000_000, minutes: 40, effects: [.value(1.5)]),
    ]
}
