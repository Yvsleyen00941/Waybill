import Foundation

/// One delivery: what a vehicle carries, where to, and when each step happened.
/// This is what the Shipment Tracking panel shows.
nonisolated struct Shipment: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let destination: String
    let contract: Int?
    var units: Double = 0
    var value: Double = 0
    let pickedAt: Date
    var departedAt: Date?
    var deliveredAt: Date?
    var returnedAt: Date?

    var code: String { "#SHP-\(id)" }
}

/// One vehicle of the fleet and where it is in its cycle:
/// queued at the depot → backing into a dock → loading → on the road (delivering, then returning).
nonisolated struct Truck: Codable, Equatable, Identifiable, Sendable {
    enum Phase: Codable, Equatable {
        case queued
        case docking(Double)     // seconds left
        case loading
        case away(Double)        // seconds left on the round trip
    }

    let id: Int                  // 0, 1, 2… (displayed as TRK-2051, TRK-2052…)
    var phase: Phase
    var dock: Int = -1           // which dock while docking or loading
    var since: Double = 0        // game clock when the phase began (queue and loading order)
    var job: Shipment?

    var isAway: Bool { if case .away = phase { true } else { false } }
    var isAtDock: Bool {
        switch phase {
        case .docking, .loading: true
        default: false
        }
    }
    var remaining: Double {
        switch phase {
        case .away(let r), .docking(let r): r
        default: 0
        }
    }
}

extension RegionConfig {
    func vehicleCode(_ truck: Int) -> String { "\(fleet.idPrefix)-\(fleet.firstID + truck)" }
    func dockName(_ dock: Int) -> String { dock >= 0 && dock < fleet.dockNames.count ? fleet.dockNames[dock] : "Dock \(dock + 1)" }
}

// Fields with a default may be missing in saves from older versions: read them leniently.
extension Shipment {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        destination = (try? c.decodeIfPresent(String.self, forKey: .destination)) ?? nil ?? "Customer"
        contract = (try? c.decodeIfPresent(Int.self, forKey: .contract)) ?? nil
        units = (try? c.decodeIfPresent(Double.self, forKey: .units)) ?? nil ?? 0
        value = (try? c.decodeIfPresent(Double.self, forKey: .value)) ?? nil ?? 0
        pickedAt = (try? c.decodeIfPresent(Date.self, forKey: .pickedAt)) ?? nil ?? Date()
        departedAt = (try? c.decodeIfPresent(Date.self, forKey: .departedAt)) ?? nil
        deliveredAt = (try? c.decodeIfPresent(Date.self, forKey: .deliveredAt)) ?? nil
        returnedAt = (try? c.decodeIfPresent(Date.self, forKey: .returnedAt)) ?? nil
    }
}

extension Truck {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        phase = (try? c.decodeIfPresent(Phase.self, forKey: .phase)) ?? nil ?? .queued
        dock = (try? c.decodeIfPresent(Int.self, forKey: .dock)) ?? nil ?? -1
        since = (try? c.decodeIfPresent(Double.self, forKey: .since)) ?? nil ?? 0
        job = (try? c.decodeIfPresent(Shipment.self, forKey: .job)) ?? nil
    }
}
