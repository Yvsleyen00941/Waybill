import SwiftUI
import UIKit

/// Every colour in Waybill lives here.
/// World colours are `UIColor` (RealityKit wants those), interface colours are SwiftUI `Color`.
/// The whole look rests on one idea: a cool indigo world with warm cardboard as the only warm accent.
enum Palette {
    // MARK: Brand (indigo)
    static let brandLit = UIColor(hex: 0x6E72F0)
    static let brand = UIColor(hex: 0x4B4FD8)
    static let brandShade = UIColor(hex: 0x3536A8)
    static let brandDeep = UIColor(hex: 0x23246E)

    // MARK: Ground & surfaces
    static let ground = UIColor(hex: 0xC6CAEA)
    static let yard = UIColor(hex: 0xD4D7F0)
    static let concrete = UIColor(hex: 0xDFE1F2)
    static let road = UIColor(hex: 0xA6ADE2)
    static let curb = UIColor(hex: 0xE3E5F5)
    static let grass = UIColor(hex: 0xA3D3B6)
    static let marking = UIColor(hex: 0xF2C94C)
    static let markingWhite = UIColor(hex: 0xFAFBFF)

    // MARK: Nature
    static let foliage = UIColor(hex: 0x7FC29E)
    static let foliageDark = UIColor(hex: 0x62AE88)
    static let trunk = UIColor(hex: 0xA0929F)

    // MARK: Goods
    static let cardboard = UIColor(hex: 0xE0BE9D)
    static let cardboardLight = UIColor(hex: 0xE8CBAE)
    static let cardboardDark = UIColor(hex: 0xD3AD89)
    static let tape = UIColor(hex: 0xF3E1C8)
    static let pallet = UIColor(hex: 0xD9C4A3)

    // MARK: Buildings & machines
    static let white = UIColor(hex: 0xF7F8FC)
    static let interior = UIColor(hex: 0x2A2C5E)
    static let metal = UIColor(hex: 0x9097B3)
    static let darkMetal = UIColor(hex: 0x4A4F66)
    static let glass = UIColor(hex: 0x1D2342)
    static let tire = UIColor(hex: 0x2B2E3B)
    static let forklift = UIColor(hex: 0xF2C14E)
    static let hiVis = UIColor(hex: 0xFF8A3D)
    static let skin = UIColor(hex: 0xE6B48C)
    static let container = UIColor(hex: 0x2F8F8F)
    static let rivalTeal = UIColor(hex: 0x1F8290)
    static let rivalNavy = UIColor(hex: 0x39436A)

    // MARK: Light
    static let shadowTint = UIColor(hex: 0x5458A8)
    static let windowGlow = UIColor(hex: 0xFFC877)
    static let lampGlow = UIColor(hex: 0xFFD99A)
    static let headlight = UIColor(hex: 0xFFF3D6)
    static let tailLight = UIColor(hex: 0xFF4D5E)

    static let ink = UIColor(hex: 0x212633)
    static let brandDeepColor = Color(uiColor: brandDeep)

    /// Interface colours (SwiftUI).
    enum UI {
        static let brand = Color(uiColor: Palette.brand)
        static let ink = Color(uiColor: Palette.ink)
        static let secondary = Color(hex: 0x6B7186)
        static let positive = Color(hex: 0x2E9E5B)
        static let positiveBG = Color(hex: 0xE2F4E9)
        static let info = Color(hex: 0x4B4FD8)
        static let infoBG = Color(hex: 0xE8E9FC)
        static let warning = Color(hex: 0xD9822B)
        static let warningBG = Color(hex: 0xFCEEDD)
    }
}

extension UIColor {
    /// `UIColor(hex: 0x4B4FD8)` — the same notation designers use.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Blend two colours: t = 0 gives self, t = 1 gives `other`.
    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(t, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}
