import AVFoundation
import Foundation

/// Every sound in Waybill is made here from maths: no audio files.
/// Ambience loops (wind, traffic, birds, crickets, water…) and short effects (chimes, plucks, stamps).
/// All functions are pure and `nonisolated`, so they can run off the main thread.
enum Synth {
    static let rate: Double = 44_100

    nonisolated static var format: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)! }

    /// Turn samples into a playable buffer.
    nonisolated static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
        return buf
    }

    // MARK: Building blocks

    /// Small, fast, deterministic noise.
    struct Noise {
        var state: UInt32
        nonisolated init(_ seed: UInt32) { state = seed | 1 }
        nonisolated mutating func next() -> Float {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Float(state) / Float(UInt32.max) * 2 - 1
        }
    }

    /// One-pole low-pass filter (simple and warm).
    struct LowPass {
        var y: Float = 0
        let a: Float
        nonisolated init(cutoff: Double) { a = Float(1 - exp(-2 * .pi * cutoff / Synth.rate)) }
        nonisolated mutating func run(_ x: Float) -> Float { y += a * (x - y); return y }
    }

    nonisolated static func count(_ seconds: Double) -> Int { Int(seconds * rate) }

    /// Make a loop seamless: fade the end into the beginning.
    nonisolated static func seamless(_ s: [Float], fade: Double = 0.6) -> [Float] {
        let n = count(fade)
        guard s.count > n * 2 else { return s }
        var out = Array(s[0..<(s.count - n)])
        for i in 0..<n {
            let t = Float(i) / Float(n)
            out[i] = out[i] * sqrt(t) + s[s.count - n + i] * sqrt(1 - t)
        }
        return out
    }

    /// Fade the last `seconds` to silence (no click at the end).
    nonisolated static func fadeOut(_ s: inout [Float], seconds: Double = 0.04) {
        let n = min(count(seconds), s.count)
        for i in 0..<n { s[s.count - 1 - i] *= Float(i) / Float(n) }
    }

    nonisolated static func normalize(_ s: inout [Float], to peak: Float) {
        let m = s.reduce(0) { max($0, abs($1)) }
        guard m > 0 else { return }
        let k = peak / m
        for i in s.indices { s[i] *= k }
    }

    /// Mix `other` into `s` starting at `offset` samples.
    nonisolated static func mix(_ s: inout [Float], _ other: [Float], at offset: Int, gain: Float = 1) {
        for i in other.indices where offset + i < s.count && offset + i >= 0 { s[offset + i] += other[i] * gain }
    }

    /// A bell-like tone: a few inharmonic partials with soft attack and exponential decay.
    nonisolated static func bell(_ freq: Double, seconds: Double = 1.4, decay: Double = 3.2, partials: [(Double, Float)] = [(1, 1), (2.0, 0.35), (2.76, 0.22), (5.4, 0.06)]) -> [Float] {
        let n = count(seconds)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let env = Float(min(t / 0.006, 1) * exp(-t * decay))
            var v: Float = 0
            for (ratio, amp) in partials { v += amp * Float(sin(2 * .pi * freq * ratio * t)) * Float(exp(-t * decay * (ratio - 0.5) * 0.35)) }
            out[i] = v * env
        }
        return out
    }

    /// A soft plucked note (Karplus–Strong string).
    nonisolated static func pluck(_ freq: Double, seconds: Double = 0.6, brightness: Float = 0.5) -> [Float] {
        let n = count(seconds)
        let period = max(Int(rate / freq), 2)
        var noise = Noise(UInt32(freq * 100))
        var ring = (0..<period).map { _ in noise.next() * 0.8 }
        var lp = LowPass(cutoff: 2400 + Double(brightness) * 4000)
        var out = [Float](repeating: 0, count: n)
        var idx = 0
        for i in 0..<n {
            let a = ring[idx], b = ring[(idx + 1) % period]
            let v = (a + b) * 0.5 * 0.996
            ring[idx] = v
            idx = (idx + 1) % period
            out[i] = lp.run(a)
        }
        return out
    }

    // MARK: Effects

    /// Dispatch: a bright two-note chime with a little "coin" sparkle.
    nonisolated static func dispatch() -> [Float] {
        var s = [Float](repeating: 0, count: count(1.6))
        mix(&s, bell(783.99, seconds: 1.2, decay: 4), at: 0, gain: 0.7)            // G5
        mix(&s, bell(1174.66, seconds: 1.4, decay: 3.4), at: count(0.09), gain: 0.6) // D6
        mix(&s, bell(2349.3, seconds: 0.5, decay: 9), at: count(0.16), gain: 0.18)   // sparkle
        normalize(&s, to: 0.8)
        return s
    }

    /// Upgrade: a short pluck; `step` raises the pitch along a pentatonic scale.
    nonisolated static func upgrade(step: Int) -> [Float] {
        let scale = [0, 2, 4, 7, 9, 12, 14, 16]
        let f = 523.25 * pow(2, Double(scale[step % scale.count]) / 12)
        var s = pluck(f, seconds: 0.5, brightness: 0.7)
        fadeOut(&s, seconds: 0.15)
        normalize(&s, to: 0.55)
        return s
    }

    /// Milestone / unlock: a quick rising arpeggio.
    nonisolated static func sparkle() -> [Float] {
        var s = [Float](repeating: 0, count: count(1.8))
        for (i, semis) in [0, 4, 7, 12, 16].enumerated() {
            mix(&s, bell(659.25 * pow(2, Double(semis) / 12), seconds: 1.1, decay: 4.5), at: count(0.07 * Double(i)), gain: 0.5)
        }
        normalize(&s, to: 0.7)
        return s
    }

    /// Hire: a warm major chord.
    nonisolated static func chord() -> [Float] {
        var s = [Float](repeating: 0, count: count(1.8))
        for semis in [0, 4, 7, 12] {
            mix(&s, bell(261.63 * pow(2, Double(semis) / 12), seconds: 1.8, decay: 2.2, partials: [(1, 1), (2, 0.3), (3, 0.1)]), at: 0, gain: 0.4)
        }
        normalize(&s, to: 0.6)
        return s
    }

    /// Contract accepted: a paper "stamp" (thump + click).
    nonisolated static func stamp() -> [Float] {
        let n = count(0.35)
        var noise = Noise(77)
        var lp = LowPass(cutoff: 900)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let thump = Float(sin(2 * .pi * 95 * t) * exp(-t * 28))
            let click = lp.run(noise.next()) * Float(exp(-t * 60))
            s[i] = thump * 0.9 + click * 1.4
        }
        fadeOut(&s)
        normalize(&s, to: 0.7)
        return s
    }

    /// Contract complete: three bright notes.
    nonisolated static func fanfare() -> [Float] {
        var s = [Float](repeating: 0, count: count(2.0))
        for (i, f) in [659.25, 830.61, 987.77].enumerated() { mix(&s, bell(f, seconds: 1.4, decay: 3.5), at: count(0.12 * Double(i)), gain: 0.55) }
        mix(&s, bell(1318.5, seconds: 1.6, decay: 2.8), at: count(0.38), gain: 0.4)
        normalize(&s, to: 0.75)
        return s
    }

    /// Contract expired: two soft low notes.
    nonisolated static func fail() -> [Float] {
        var s = [Float](repeating: 0, count: count(1.2))
        mix(&s, bell(392, seconds: 0.9, decay: 4, partials: [(1, 1), (2, 0.2)]), at: 0, gain: 0.5)
        mix(&s, bell(311.13, seconds: 1.0, decay: 3.5, partials: [(1, 1), (2, 0.2)]), at: count(0.18), gain: 0.5)
        normalize(&s, to: 0.5)
        return s
    }

    /// Research done: a shimmering bell cluster.
    nonisolated static func shimmer() -> [Float] {
        var s = [Float](repeating: 0, count: count(2.6))
        for (i, semis) in [0, 7, 12, 19, 24].enumerated() {
            mix(&s, bell(523.25 * pow(2, Double(semis) / 12), seconds: 2.2, decay: 2.0), at: count(0.05 * Double(i)), gain: 0.35)
        }
        normalize(&s, to: 0.7)
        return s
    }

    /// A soft blip for starting something.
    nonisolated static func blip() -> [Float] {
        var s = bell(880, seconds: 0.35, decay: 12, partials: [(1, 1), (2, 0.2)])
        normalize(&s, to: 0.4)
        return s
    }

    /// Rush: a rising whoosh.
    nonisolated static func whoosh() -> [Float] {
        let n = count(0.9)
        var noise = Noise(5)
        var s = [Float](repeating: 0, count: n)
        var y: Float = 0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let cutoff = 300 + 5000 * t * t
            let a = Float(1 - exp(-2 * .pi * cutoff / rate))
            y += a * (noise.next() - y)
            s[i] = y * Float(sin(.pi * t))
        }
        normalize(&s, to: 0.5)
        return s
    }

    /// Truck reversing beep (one beep; the engine loops it with a gap).
    nonisolated static func reverseBeep() -> [Float] {
        let n = count(1.0)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<count(0.42) {
            let t = Double(i) / rate
            let env = Float(min(t / 0.01, 1) * min((0.42 - t) / 0.01, 1))
            s[i] = Float(sin(2 * .pi * 1100 * t)) * env * 0.5
        }
        return s
    }

    // MARK: Ambience loops

    /// Wind: filtered noise with slow gusts.
    nonisolated static func wind(seconds: Double = 12, strength: Float = 1, seed: UInt32 = 11) -> [Float] {
        let n = count(seconds)
        var noise = Noise(seed)
        var lp1 = LowPass(cutoff: 380), lp2 = LowPass(cutoff: 650)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let gust = Float(0.55 + 0.25 * sin(2 * .pi * t / 5.3) + 0.2 * sin(2 * .pi * t / 2.1 + 1.3))
            s[i] = lp2.run(lp1.run(noise.next())) * gust * strength
        }
        normalize(&s, to: 0.5)
        return seamless(s)
    }

    /// Distant traffic: a low rumble with passing swells.
    nonisolated static func traffic(seconds: Double = 14) -> [Float] {
        let n = count(seconds)
        var noise = Noise(23)
        var lp = LowPass(cutoff: 160)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let swell = Float(0.5 + 0.3 * sin(2 * .pi * t / 7) + 0.2 * sin(2 * .pi * t / 3.1))
            s[i] = lp.run(noise.next()) * swell + Float(sin(2 * .pi * 55 * t)) * 0.02
        }
        normalize(&s, to: 0.5)
        return seamless(s)
    }

    /// Water lapping against a bank.
    nonisolated static func water(seconds: Double = 10) -> [Float] {
        let n = count(seconds)
        var noise = Noise(31)
        var lp = LowPass(cutoff: 900), hp = LowPass(cutoff: 200)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let x = noise.next()
            let band = lp.run(x) - hp.run(x)
            let lap = Float(max(0, sin(2 * .pi * t / 1.7)) * 0.7 + max(0, sin(2 * .pi * t / 2.9 + 1)) * 0.5)
            s[i] = band * lap
        }
        normalize(&s, to: 0.5)
        return seamless(s)
    }

    /// Crickets: high chirps in pulses, several insects out of phase.
    nonisolated static func crickets(seconds: Double = 8) -> [Float] {
        let n = count(seconds)
        var s = [Float](repeating: 0, count: n)
        for (k, f) in [4400.0, 4700.0, 4100.0].enumerated() {
            let offset = Double(k) * 0.23
            let period = 0.55 + Double(k) * 0.07
            for i in 0..<n {
                let t = Double(i) / rate + offset
                let phase = t.truncatingRemainder(dividingBy: period)
                guard phase < 0.18 else { continue }
                let pulse = max(0, sin(2 * .pi * 32 * phase))
                s[i] += Float(sin(2 * .pi * f * t) * pulse * sin(.pi * phase / 0.18)) * (k == 2 ? 0.5 : 0.8)
            }
        }
        normalize(&s, to: 0.4)
        return seamless(s, fade: 0.3)
    }

    /// One bird call: a few quick whistled sweeps.
    nonisolated static func bird(seed: UInt32) -> [Float] {
        var noise = Noise(seed)
        let notes = 2 + Int((noise.next() + 1) * 1.5)
        var s = [Float](repeating: 0, count: count(1.4))
        var at = 0
        for _ in 0..<notes {
            let len = 0.07 + Double(noise.next() + 1) * 0.05
            let f0 = 2600 + Double(noise.next() + 1) * 1500
            let f1 = f0 * (0.75 + Double(noise.next() + 1) * 0.3)
            let m = count(len)
            var phase = 0.0
            var note = [Float](repeating: 0, count: m)
            for i in 0..<m {
                let u = Double(i) / Double(m)
                let f = f0 + (f1 - f0) * u + sin(u * 40) * 120
                phase += 2 * .pi * f / rate
                note[i] = Float(sin(phase) * sin(.pi * u))
            }
            mix(&s, note, at: at, gain: 0.6)
            at += m + count(0.03 + Double(noise.next() + 1) * 0.05)
        }
        return s
    }

    /// Gull cry (Harbour City).
    nonisolated static func gull(seed: UInt32) -> [Float] {
        var noise = Noise(seed)
        var s = [Float](repeating: 0, count: count(1.2))
        var at = 0
        for _ in 0..<(2 + Int(noise.next() + 1)) {
            let m = count(0.22)
            var phase = 0.0
            var note = [Float](repeating: 0, count: m)
            for i in 0..<m {
                let u = Double(i) / Double(m)
                let f = 1500 - 700 * u
                phase += 2 * .pi * f / rate
                note[i] = Float((sin(phase) + 0.4 * sin(phase * 2) + 0.2 * sin(phase * 3)) * sin(.pi * u))
            }
            mix(&s, note, at: at, gain: 0.35)
            at += count(0.27)
        }
        return s
    }

    /// A deep ship horn or a two-tone train horn.
    nonisolated static func horn(freqs: [Double], seconds: Double = 1.8) -> [Float] {
        let n = count(seconds)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let env = Float(min(t / 0.12, 1) * min((seconds - t) / 0.3, 1))
            var v: Float = 0
            for f in freqs { v += Float(sin(2 * .pi * f * t) + 0.5 * sin(4 * .pi * f * t) + 0.25 * sin(6 * .pi * f * t)) }
            s[i] = v * env
        }
        normalize(&s, to: 0.45)
        return s
    }

    /// City hum (Metro): low drone, faint high whine of drones.
    nonisolated static func cityHum(seconds: Double = 12) -> [Float] {
        let n = count(seconds)
        var noise = Noise(41)
        var lp = LowPass(cutoff: 240)
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let whine = Float(sin(2 * .pi * (620 + 8 * sin(2 * .pi * t / 3)) * t)) * Float(0.04 + 0.03 * sin(2 * .pi * t / 4.5))
            s[i] = lp.run(noise.next()) + whine
        }
        normalize(&s, to: 0.5)
        return seamless(s)
    }
}
