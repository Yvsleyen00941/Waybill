import Foundation

/// A timed delivery goal from a client: ship N units within the time limit for a bonus and reputation.
nonisolated struct Contract: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let client: String
    let colorHex: UInt32
    let destination: String
    let units: Double
    let seconds: Double          // time limit once accepted
    let reward: Double
    let stars: Int
    var delivered: Double = 0
    var remaining: Double        // counts down once accepted
    var offerExpires: Double     // counts down while on the board

    var progress: Double { min(delivered / max(units, 1), 1) }
    var isDone: Bool { delivered >= units }
}

extension Contract {
    /// Lenient for saves from older versions (fields with a default may be missing).
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        client = try c.decode(String.self, forKey: .client)
        colorHex = (try? c.decodeIfPresent(UInt32.self, forKey: .colorHex)) ?? nil ?? 0x4B4FD8
        destination = (try? c.decodeIfPresent(String.self, forKey: .destination)) ?? nil ?? client
        units = try c.decode(Double.self, forKey: .units)
        seconds = (try? c.decodeIfPresent(Double.self, forKey: .seconds)) ?? nil ?? 600
        reward = try c.decode(Double.self, forKey: .reward)
        stars = (try? c.decodeIfPresent(Int.self, forKey: .stars)) ?? nil ?? 1
        delivered = (try? c.decodeIfPresent(Double.self, forKey: .delivered)) ?? nil ?? 0
        remaining = (try? c.decodeIfPresent(Double.self, forKey: .remaining)) ?? nil ?? seconds
        offerExpires = (try? c.decodeIfPresent(Double.self, forKey: .offerExpires)) ?? nil ?? 0
    }
}

/// Fictional clients. Each has a brand colour (shown as a dot) and a kind of goods.
struct Client {
    let name: String
    let color: UInt32
}

enum ContractBoard {
    static let clients: [RegionID: [Client]] = [
        .riverside: [Client(name: "Harlow Foods", color: 0x2E9E5B), Client(name: "Kestrel Outdoor", color: 0xD9822B),
                     Client(name: "Maple & Co.", color: 0xC2553D), Client(name: "Juno Home", color: 0x8B5CF6),
                     Client(name: "Brightline Pharma", color: 0x0EA5E9), Client(name: "Nordway Retail", color: 0x1F8290),
                     Client(name: "Peakfresh", color: 0x39436A), Client(name: "Fernhill Garden", color: 0x65A30D)],
        .harbour: [Client(name: "Saltmarsh Motors", color: 0xC2553D), Client(name: "Tidewell Electronics", color: 0x0EA5E9),
                   Client(name: "Calder Steel", color: 0x64748B), Client(name: "Bay Fruit Co.", color: 0xF59E0B),
                   Client(name: "Avel Textiles", color: 0x8B5CF6), Client(name: "Northgate Retail", color: 0x2E9E5B)],
        .granite: [Client(name: "Hollin Timber", color: 0x65A30D), Client(name: "Kalden Machines", color: 0x64748B),
                   Client(name: "Mirrin Minerals", color: 0xC2553D), Client(name: "Alder Glassworks", color: 0x0EA5E9),
                   Client(name: "Brannoch Dairy", color: 0xF59E0B), Client(name: "St. Varen Pharma", color: 0x8B5CF6)],
        .metro: [Client(name: "Neon Grocer", color: 0x2E9E5B), Client(name: "Halcyon Books", color: 0xD9822B),
                 Client(name: "Pier 9 Fashion", color: 0xEC4899), Client(name: "Union Pharmacy", color: 0x0EA5E9),
                 Client(name: "Skyline Tech", color: 0x8B5CF6), Client(name: "Juniper Flowers", color: 0x65A30D)],
        .orbit: [Client(name: "Meridian Station", color: 0x0EA5E9), Client(name: "Halo Telecom", color: 0x8B5CF6),
                 Client(name: "Lunar Survey Co.", color: 0x64748B), Client(name: "Orbital Bio", color: 0x2E9E5B),
                 Client(name: "Deep Sky Mining", color: 0xD9822B)],
    ]

    /// A fresh offer sized to what the depot can do right now.
    /// - throughput: units per minute the chain manages today.
    static func make(id: Int, region: RegionConfig, throughput: Double, valuePerUnit: Double) -> Contract {
        var rng = SeededRandomD(seed: UInt64(id) &* 2_654_435_761 &+ UInt64(region.number))
        let list = clients[region.id] ?? clients[.riverside]!
        let client = list[Int(rng.next() % UInt64(list.count))]
        let destination = region.destinations[Int(rng.next() % UInt64(region.destinations.count))]
        // Three sizes: quick, standard, big. Bigger asks for a tighter pace and pays more.
        let size = Int(rng.next() % 3)
        let minutes: Double = [4, 8, 14][size] + Double(rng.next() % 3)
        let pace: Double = [0.75, 0.85, 0.95][size] + rng.unit() * 0.1
        let units = max((throughput * minutes * pace).rounded(), region.fleet.baseLoad * 2)
        let bonus: Double = [0.7, 0.9, 1.2][size] + rng.unit() * 0.2
        let reward = (units * valuePerUnit * bonus / 10).rounded() * 10
        return Contract(id: id, client: client.name, colorHex: client.color, destination: destination,
                        units: units, seconds: minutes * 60, reward: reward, stars: size + 1,
                        remaining: minutes * 60, offerExpires: 300 + Double(rng.next() % 180))
    }
}

/// Small deterministic random generator (Double flavour) for contracts and shipments.
struct SeededRandomD {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
