import RealityKit
import UIKit
import simd

/// What the world controller needs from any fleet display (trucks, trains, vans, rockets).
protocol FleetDisplay: WorldAnimator {
    var onCreate: ((Int, Vehicle) -> Void)? { get set }
    func position(of id: Int) -> V3?
    func status(of id: Int) -> String
    func setHeadlights(_ level: Float)
    /// True while the vehicle is backing up (for the reversing beeper).
    func isReversing(_ id: Int) -> Bool
}

extension FleetDisplay {
    func isReversing(_ id: Int) -> Bool { false }
}
