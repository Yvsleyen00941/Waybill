import UIKit
import simd

/// How the world is lit at a given moment.
struct LightingState {
    var towardsSun: V3        // unit vector pointing at the sun (or moon)
    var sunColor: UIColor
    var sunIntensity: Float   // lux
    var ambient: Float        // sky light brightness (exponent: +1 = twice as bright)
    var night: Float          // 0 = full day … 1 = full night (lamps and windows on)
    var background: UIColor
}

/// A 24-hour lighting script. Keyframes are blended smoothly, so dusk slides into night.
enum DayCycle {
    private struct Key {
        let hour: Double
        let elevation: Float   // degrees above the horizon
        let azimuth: Float     // degrees; chosen so shadows fall pleasantly in the default view
        let color: UIColor
        let intensity: Float
        let ambient: Float
        let night: Float
    }

    private static let moon = UIColor(red: 0.62, green: 0.68, blue: 1.0, alpha: 1)

    private static let keys: [Key] = [
        Key(hour: 0.0, elevation: 42, azimuth: -120, color: moon, intensity: 260, ambient: -2.6, night: 1),
        Key(hour: 5.0, elevation: 32, azimuth: -128, color: moon, intensity: 260, ambient: -2.6, night: 1),
        Key(hour: 6.2, elevation: 5, azimuth: -150, color: UIColor(red: 1.0, green: 0.64, blue: 0.5, alpha: 1), intensity: 1300, ambient: -1.9, night: 0.75),
        Key(hour: 7.4, elevation: 15, azimuth: -140, color: UIColor(red: 1.0, green: 0.82, blue: 0.68, alpha: 1), intensity: 3300, ambient: -1.2, night: 0.15),
        Key(hour: 9.0, elevation: 32, azimuth: -118, color: UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1), intensity: 4500, ambient: -0.75, night: 0),
        Key(hour: 13.0, elevation: 56, azimuth: -85, color: UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1), intensity: 5200, ambient: -0.55, night: 0),
        Key(hour: 17.0, elevation: 36, azimuth: -55, color: UIColor(red: 1.0, green: 0.93, blue: 0.83, alpha: 1), intensity: 4700, ambient: -0.65, night: 0),
        Key(hour: 19.2, elevation: 13, azimuth: -40, color: UIColor(red: 1.0, green: 0.7, blue: 0.5, alpha: 1), intensity: 3000, ambient: -1.15, night: 0.15),
        Key(hour: 20.3, elevation: 4, azimuth: -32, color: UIColor(red: 0.95, green: 0.54, blue: 0.56, alpha: 1), intensity: 1200, ambient: -1.85, night: 0.65),
        Key(hour: 21.4, elevation: 34, azimuth: -112, color: moon, intensity: 260, ambient: -2.5, night: 1),
        Key(hour: 24.0, elevation: 42, azimuth: -120, color: moon, intensity: 260, ambient: -2.6, night: 1),
    ]

    static func state(hour rawHour: Double, ground: UIColor = Palette.ground) -> LightingState {
        let hour = rawHour.truncatingRemainder(dividingBy: 24) + (rawHour < 0 ? 24 : 0)
        var i = 0
        while i < keys.count - 2 && keys[i + 1].hour <= hour { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let t = Float((hour - a.hour) / max(b.hour - a.hour, 0.0001))
        let s = t * t * (3 - 2 * t) // ease between keyframes

        let elevation = deg(lerp(a.elevation, b.elevation, s))
        let azimuth = deg(lerp(a.azimuth, b.azimuth, s))
        let towards = V3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
        let night = lerp(a.night, b.night, s)
        return LightingState(
            towardsSun: simd_normalize(towards),
            sunColor: a.color.mixed(with: b.color, CGFloat(s)),
            sunIntensity: lerp(a.intensity, b.intensity, s),
            ambient: lerp(a.ambient, b.ambient, s),
            night: night,
            background: ground.mixed(with: UIColor(hex: 0x1B1D3A), CGFloat(night * 0.9))
        )
    }

    /// The current local time as an hour with fractions (e.g. 21.5 = 21:30).
    static func currentHour(_ date: Date = Date()) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// A soft sky image used as ambient light (image-based lighting). Cool lavender, like the reference.
    static func skyImage() -> CGImage {
        let size = CGSize(width: 512, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor(hex: 0xB9C1F4), UIColor(hex: 0xDCDFFA), UIColor(hex: 0xF3F2FB), UIColor(hex: 0xD6D8EE), UIColor(hex: 0xBFC2DE)]
                .map(\.cgColor) as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.32, 0.5, 0.62, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return image.cgImage!
    }
}
