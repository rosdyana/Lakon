import Foundation
import LakonCore

/// Procedurally synthesised starter audio (MZ's RTP audio is licensed, so none ships):
/// 16-bit mono WAVs for the 24 system sounds, a few BGM loops (village theme uses a slendro-like
/// pentatonic scale), MEs and a rain BGS. Written into audio/{bgm,bgs,me,se}.
public enum DefaultAudio {
    static let rate = 22050

    // MARK: synthesis primitives

    enum Wave { case square(Double), triangle, sine, noise, saw }

    struct Voice {
        var wave: Wave
        var attack = 0.005, decay = 0.08, sustain = 0.6, release = 0.06
        var volume = 0.3
    }

    final class Buffer {
        var s: [Double]
        init(seconds: Double) { s = Array(repeating: 0, count: Int(seconds * Double(DefaultAudio.rate))) }
        init(samples: Int) { s = Array(repeating: 0, count: samples) }

        /// Adds a note with optional pitch slide (freq → freqEnd) and ADSR envelope.
        func note(_ start: Double, _ dur: Double, _ freq: Double, _ v: Voice, slideTo freqEnd: Double? = nil, vibrato: Double = 0) {
            let r = Double(DefaultAudio.rate)
            let i0 = Int(start * r), n = Int((dur + v.release) * r)
            var phase = 0.0
            var noiseState: UInt32 = 0x1234_5678 &+ UInt32(truncatingIfNeeded: Int(freq * 7) & 0xffff)
            var held = 0.0
            for k in 0..<n where i0 + k < s.count && i0 + k >= 0 {
                let t = Double(k) / r
                let f = (freqEnd.map { freq + ($0 - freq) * min(1, t / max(dur, 0.001)) } ?? freq) * (1 + vibrato * sin(2 * .pi * 5.5 * t))
                phase += f / r
                let p = phase - floor(phase)
                var x: Double
                switch v.wave {
                case .square(let duty): x = p < duty ? 1 : -1
                case .triangle: x = 4 * abs(p - 0.5) - 1
                case .sine: x = sin(2 * .pi * p)
                case .saw: x = 2 * p - 1
                case .noise:
                    // Sample-and-hold noise clocked at the note frequency (classic chip noise).
                    if p < f / r { noiseState ^= noiseState << 13; noiseState ^= noiseState >> 17; noiseState ^= noiseState << 5; held = Double(noiseState % 2001) / 1000 - 1 }
                    x = held
                }
                let env: Double
                if t < v.attack { env = t / v.attack }
                else if t < v.attack + v.decay { env = 1 - (1 - v.sustain) * (t - v.attack) / v.decay }
                else if t < dur { env = v.sustain }
                else { env = v.sustain * max(0, 1 - (t - dur) / v.release) }
                s[i0 + k] += x * env * v.volume
            }
        }

        func lowpass(_ amount: Double) {
            var y = 0.0
            for i in s.indices { y += (s[i] - y) * amount; s[i] = y }
        }

        func wav() -> Data {
            var d = Data()
            func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
            func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
            let peak = max(1, s.map(abs).max() ?? 1)
            let gain = peak > 0.95 ? 0.95 / peak : 1
            d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + s.count * 2)); d.append(contentsOf: Array("WAVE".utf8))
            d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(DefaultAudio.rate)); u32(UInt32(DefaultAudio.rate * 2)); u16(2); u16(16)
            d.append(contentsOf: Array("data".utf8)); u32(UInt32(s.count * 2))
            for x in s { u16(UInt16(bitPattern: Int16(max(-1, min(1, x * gain)) * 32000))) }
            return d
        }
    }

    static func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    /// Plays a sequence of (midi or -1 rest, beats) at a tempo; returns end time.
    @discardableResult
    static func melody(_ b: Buffer, _ notes: [(Double, Double)], bpm: Double, voice: Voice, start: Double = 0, gate: Double = 0.85, vibrato: Double = 0) -> Double {
        let beat = 60 / bpm
        var t = start
        for (m, len) in notes {
            if m >= 0 { b.note(t, len * beat * gate, hz(m), voice, vibrato: vibrato) }
            t += len * beat
        }
        return t
    }

    // MARK: sound effects (24 system sounds + a few extras)

    static func se(_ name: String) -> Buffer {
        let sq = Voice(wave: .square(0.5), attack: 0.002, decay: 0.03, sustain: 0.7, release: 0.03, volume: 0.35)
        let tri = Voice(wave: .triangle, attack: 0.002, decay: 0.05, sustain: 0.8, release: 0.05, volume: 0.5)
        let nz = Voice(wave: .noise, attack: 0.001, decay: 0.06, sustain: 0.4, release: 0.08, volume: 0.45)
        switch name {
        case "Cursor": let b = Buffer(seconds: 0.08); b.note(0, 0.03, 1400, sq); return b
        case "Decision": let b = Buffer(seconds: 0.18); b.note(0, 0.05, 880, sq); b.note(0.05, 0.07, 1320, sq); return b
        case "Cancel": let b = Buffer(seconds: 0.18); b.note(0, 0.05, 660, sq); b.note(0.05, 0.07, 440, sq); return b
        case "Buzzer": let b = Buffer(seconds: 0.25); b.note(0, 0.18, 140, Voice(wave: .square(0.3), volume: 0.35)); return b
        case "Equip": let b = Buffer(seconds: 0.25); b.note(0, 0.03, 3000, nz); b.note(0, 0.12, 1800, Voice(wave: .square(0.12), decay: 0.12, sustain: 0.1, volume: 0.25)); return b
        case "Save": let b = Buffer(seconds: 0.5); for (i, m) in [72.0, 76, 79, 84].enumerated() { b.note(Double(i) * 0.07, 0.12, hz(m), tri) }; return b
        case "Load": let b = Buffer(seconds: 0.5); for (i, m) in [84.0, 79, 76, 84].enumerated() { b.note(Double(i) * 0.07, 0.12, hz(m), tri) }; return b
        case "Battle_Start":
            let b = Buffer(seconds: 0.9); b.note(0, 0.5, 800, Voice(wave: .noise, attack: 0.2, decay: 0.2, sustain: 0.5, release: 0.2, volume: 0.4), slideTo: 4000)
            for (i, m) in [57.0, 60, 64, 69].enumerated() { b.note(0.35 + Double(i) * 0.05, 0.3, hz(m), sq) }; return b
        case "Escape": let b = Buffer(seconds: 0.5); b.note(0, 0.35, 1200, Voice(wave: .square(0.25), volume: 0.3), slideTo: 200); return b
        case "Enemy_Attack", "Attack": let b = Buffer(seconds: 0.3); b.note(0, 0.12, 2400, nz, slideTo: 600); return b
        case "Enemy_Damage": let b = Buffer(seconds: 0.3); b.note(0, 0.12, 1800, nz); b.note(0, 0.15, 300, tri, slideTo: 90); return b
        case "Actor_Damage": let b = Buffer(seconds: 0.35); b.note(0, 0.15, 900, nz); b.note(0, 0.2, 200, Voice(wave: .square(0.5), volume: 0.3), slideTo: 70); return b
        case "Collapse", "Enemy_Collapse": let b = Buffer(seconds: 0.7); b.note(0, 0.55, 3000, Voice(wave: .noise, attack: 0.01, decay: 0.5, sustain: 0.2, release: 0.1, volume: 0.4), slideTo: 300); return b
        case "Boss_Collapse":
            let b = Buffer(seconds: 1.6); for i in 0..<6 { b.note(Double(i) * 0.2, 0.25, 2000 - Double(i) * 250, nz, slideTo: 200) }; return b
        case "Actor_Collapse": let b = Buffer(seconds: 0.8); b.note(0, 0.6, 600, Voice(wave: .square(0.5), volume: 0.3), slideTo: 80); return b
        case "Recovery":
            let b = Buffer(seconds: 0.7); for (i, m) in [72.0, 76, 79, 84, 88].enumerated() { b.note(Double(i) * 0.06, 0.2, hz(m), Voice(wave: .sine, release: 0.2, volume: 0.35)) }; return b
        case "Miss", "Evasion": let b = Buffer(seconds: 0.3); b.note(0, 0.2, 400, Voice(wave: .noise, attack: 0.05, decay: 0.1, sustain: 0.3, volume: 0.25), slideTo: 4000); return b
        case "Magic_Evasion", "Reflection": let b = Buffer(seconds: 0.4); b.note(0, 0.25, 2000, Voice(wave: .sine, volume: 0.3), slideTo: 3000, vibrato: 0.05); return b
        case "Shop", "Coin": let b = Buffer(seconds: 0.4); b.note(0, 0.06, hz(88), tri); b.note(0.07, 0.22, hz(95), tri); return b
        case "Item": let b = Buffer(seconds: 0.5); b.note(0, 0.1, hz(84), Voice(wave: .sine, volume: 0.35)); b.note(0.1, 0.25, hz(91), Voice(wave: .sine, volume: 0.35)); return b
        case "Skill", "Magic":
            let b = Buffer(seconds: 0.8); b.note(0, 0.6, 600, Voice(wave: .sine, attack: 0.1, decay: 0.2, sustain: 0.6, release: 0.2, volume: 0.3), slideTo: 1800, vibrato: 0.08)
            b.note(0.05, 0.5, 900, Voice(wave: .triangle, attack: 0.1, volume: 0.2), slideTo: 2600); return b
        case "Slash": let b = Buffer(seconds: 0.25); b.note(0, 0.1, 6000, Voice(wave: .noise, attack: 0.01, decay: 0.08, sustain: 0.2, volume: 0.4), slideTo: 1500); return b
        case "Fire": let b = Buffer(seconds: 0.8); b.note(0, 0.6, 400, Voice(wave: .noise, attack: 0.05, decay: 0.3, sustain: 0.5, release: 0.2, volume: 0.45), slideTo: 1500); b.lowpass(0.25); return b
        case "Open", "Chest": let b = Buffer(seconds: 0.5); b.note(0, 0.3, 120, Voice(wave: .saw, attack: 0.02, volume: 0.3), slideTo: 220, vibrato: 0.2); b.note(0.3, 0.1, hz(84), tri); return b
        case "Door": let b = Buffer(seconds: 0.4); b.note(0, 0.04, 180, Voice(wave: .triangle, volume: 0.6)); b.note(0.15, 0.04, 170, Voice(wave: .triangle, volume: 0.6)); return b
        case "Jump": let b = Buffer(seconds: 0.25); b.note(0, 0.15, 300, sq, slideTo: 900); return b
        case "Blow": let b = Buffer(seconds: 0.25); b.note(0, 0.06, 2600, nz); b.note(0, 0.1, 180, tri, slideTo: 60); return b
        case "Thunder":
            let b = Buffer(seconds: 0.9); b.note(0, 0.08, 5000, Voice(wave: .noise, attack: 0.001, decay: 0.05, sustain: 0.6, release: 0.05, volume: 0.5))
            b.note(0.08, 0.6, 900, Voice(wave: .noise, attack: 0.01, decay: 0.4, sustain: 0.3, release: 0.2, volume: 0.4), slideTo: 120); b.lowpass(0.4); return b
        case "Ice":
            let b = Buffer(seconds: 0.7); for (i, m) in [96.0, 91, 98, 93, 100].enumerated() { b.note(Double(i) * 0.05, 0.12, hz(m), Voice(wave: .triangle, decay: 0.05, sustain: 0.3, release: 0.2, volume: 0.3)) }
            b.note(0, 0.3, 7000, Voice(wave: .noise, attack: 0.01, decay: 0.2, sustain: 0.1, volume: 0.15)); return b
        case "Wind": let b = Buffer(seconds: 1.0); b.note(0, 0.8, 300, Voice(wave: .noise, attack: 0.3, decay: 0.3, sustain: 0.5, release: 0.3, volume: 0.35), slideTo: 900); b.lowpass(0.08); return b
        case "Darkness": let b = Buffer(seconds: 0.8); b.note(0, 0.6, 220, Voice(wave: .saw, attack: 0.1, volume: 0.25), slideTo: 110, vibrato: 0.1); b.lowpass(0.2); return b
        default: let b = Buffer(seconds: 0.1); b.note(0, 0.05, 1000, sq); return b
        }
    }

    /// Order matches System.json "sounds" (see SystemData.sounds doc).
    public static let systemSoundNames = ["Cursor", "Decision", "Cancel", "Buzzer", "Equip", "Save", "Load", "Battle_Start", "Escape",
                                          "Enemy_Attack", "Enemy_Damage", "Enemy_Collapse", "Boss_Collapse", "Boss_Collapse", "Actor_Damage",
                                          "Actor_Collapse", "Recovery", "Miss", "Evasion", "Magic_Evasion", "Reflection", "Shop", "Item", "Skill"]
    static let extraSE = ["Slash", "Fire", "Chest", "Door", "Jump", "Coin", "Blow", "Thunder", "Ice", "Wind", "Darkness"]

    // MARK: music

    // Slendro-like pentatonic (roughly equal 5-step octave approximated on the 12-TET grid): D E G A B.
    static func village() -> Buffer {
        let bpm = 112.0
        let lead = Voice(wave: .square(0.25), attack: 0.01, decay: 0.12, sustain: 0.55, release: 0.1, volume: 0.22)
        let bell = Voice(wave: .sine, attack: 0.002, decay: 0.4, sustain: 0.2, release: 0.3, volume: 0.22)
        let bass = Voice(wave: .triangle, attack: 0.01, decay: 0.1, sustain: 0.8, release: 0.05, volume: 0.4)
        let phrase: [(Double, Double)] = [(74, 1), (76, 0.5), (79, 0.5), (81, 1), (79, 1), (76, 0.5), (74, 0.5), (71, 1), (74, 2),
                                          (76, 1), (79, 0.5), (81, 0.5), (83, 1), (81, 1), (79, 0.5), (76, 0.5), (79, 1), (81, 2),
                                          (83, 1), (81, 0.5), (79, 0.5), (76, 1), (79, 1), (74, 0.5), (76, 0.5), (71, 1), (69, 2),
                                          (71, 1), (74, 0.5), (76, 0.5), (79, 1), (76, 1), (74, 1), (71, 1), (74, 2)]
        let beats = phrase.reduce(0) { $0 + $1.1 }
        let b = Buffer(seconds: beats * 60 / bpm)
        melody(b, phrase, bpm: bpm, voice: lead, vibrato: 0.004)
        // Gamelan-style interlocking bells (kotekan) on off-beats.
        var bells: [(Double, Double)] = []
        for i in 0..<Int(beats * 2) { bells.append((i % 2 == 0 ? -1 : [86.0, 88, 91, 93][(i / 2) % 4], 0.5)) }
        melody(b, bells, bpm: bpm, voice: bell, gate: 0.4)
        var bl: [(Double, Double)] = []
        for i in 0..<Int(beats / 2) { bl.append(([50.0, 55, 50, 47, 45, 50, 55, 50][i % 8], 2)) }
        melody(b, bl, bpm: bpm, voice: bass, gate: 0.6)
        // Gong on each phrase start.
        for i in stride(from: 0, to: Int(beats), by: 8) { b.note(Double(i) * 60 / bpm, 1.5, hz(38), Voice(wave: .sine, attack: 0.01, decay: 1.2, sustain: 0.1, release: 0.5, volume: 0.35), vibrato: 0.01) }
        return b
    }

    static func field() -> Buffer {
        let bpm = 132.0
        let lead = Voice(wave: .square(0.5), attack: 0.01, decay: 0.1, sustain: 0.6, release: 0.08, volume: 0.2)
        let harm = Voice(wave: .square(0.25), attack: 0.01, decay: 0.1, sustain: 0.5, release: 0.08, volume: 0.12)
        let bass = Voice(wave: .triangle, attack: 0.005, decay: 0.08, sustain: 0.7, volume: 0.42)
        let tune: [(Double, Double)] = [(72, 1.5), (74, 0.5), (76, 1), (79, 1), (77, 1.5), (76, 0.5), (74, 2),
                                        (74, 1.5), (76, 0.5), (77, 1), (81, 1), (79, 3), (-1, 1),
                                        (81, 1.5), (79, 0.5), (77, 1), (76, 1), (74, 1.5), (72, 0.5), (74, 2),
                                        (76, 1), (74, 1), (72, 1), (71, 1), (72, 3), (-1, 1)]
        let beats = tune.reduce(0) { $0 + $1.1 }
        let b = Buffer(seconds: beats * 60 / bpm)
        melody(b, tune, bpm: bpm, voice: lead, vibrato: 0.003)
        melody(b, tune.map { ($0.0 < 0 ? -1 : $0.0 - 4, $0.1) }, bpm: bpm, voice: harm)
        var bl: [(Double, Double)] = []
        let roots: [Double] = [48, 48, 50, 50, 53, 55, 48, 48, 57, 57, 53, 53, 50, 55, 48, 48]
        for i in 0..<Int(beats) { bl.append((roots[(i / 2) % roots.count] + (i % 2 == 0 ? 0 : 7), 1)) }
        melody(b, bl, bpm: bpm, voice: bass, gate: 0.5)
        return b
    }

    static func battle() -> Buffer {
        let bpm = 168.0
        let lead = Voice(wave: .square(0.5), attack: 0.005, decay: 0.08, sustain: 0.6, release: 0.05, volume: 0.2)
        let bass = Voice(wave: .saw, attack: 0.005, decay: 0.05, sustain: 0.6, release: 0.03, volume: 0.25)
        let drum = Voice(wave: .noise, attack: 0.001, decay: 0.05, sustain: 0.0, release: 0.02, volume: 0.35)
        let tune: [(Double, Double)] = [(69, 0.5), (72, 0.5), (76, 1), (74, 0.5), (72, 0.5), (71, 1), (72, 0.5), (74, 0.5), (76, 2),
                                        (77, 0.5), (76, 0.5), (74, 1), (72, 0.5), (71, 0.5), (69, 1), (68, 0.5), (71, 0.5), (69, 2),
                                        (76, 0.5), (79, 0.5), (81, 1), (79, 0.5), (77, 0.5), (76, 1), (74, 0.5), (76, 0.5), (77, 2),
                                        (76, 0.5), (74, 0.5), (72, 1), (71, 0.5), (72, 0.5), (74, 1), (71, 0.5), (68, 0.5), (69, 2)]
        let beats = tune.reduce(0) { $0 + $1.1 }
        let b = Buffer(seconds: beats * 60 / bpm)
        melody(b, tune, bpm: bpm, voice: lead)
        let roots: [Double] = [45, 45, 45, 45, 41, 41, 43, 43]
        var bl: [(Double, Double)] = []
        for i in 0..<Int(beats * 2) { bl.append((roots[(i / 4) % roots.count] + (i % 2 == 1 ? 12 : 0), 0.5)) }
        melody(b, bl, bpm: bpm, voice: bass, gate: 0.6)
        for i in 0..<Int(beats) {
            b.note(Double(i) * 60 / bpm, 0.05, i % 2 == 0 ? 200 : 4000, drum)
            if i % 2 == 1 { b.note((Double(i) + 0.5) * 60 / bpm, 0.03, 6000, Voice(wave: .noise, decay: 0.02, sustain: 0, volume: 0.15)) }
        }
        return b
    }

    static func title() -> Buffer {
        let bpm = 76.0
        let pad = Voice(wave: .triangle, attack: 0.3, decay: 0.5, sustain: 0.7, release: 0.6, volume: 0.18)
        let arp = Voice(wave: .sine, attack: 0.005, decay: 0.3, sustain: 0.3, release: 0.3, volume: 0.2)
        let chords: [[Double]] = [[62, 66, 69], [59, 62, 66], [55, 59, 62], [57, 61, 64]]
        let b = Buffer(seconds: 16 * 60 / bpm)
        for (i, c) in chords.enumerated() {
            for m in c { b.note(Double(i * 4) * 60 / bpm, 3.6 * 60 / bpm, hz(m), pad) }
            for k in 0..<8 { b.note((Double(i * 4) + Double(k) * 0.5) * 60 / bpm, 0.4, hz(c[k % 3] + 12 + (k >= 4 ? 12 : 0)), arp) }
        }
        return b
    }

    static func ship() -> Buffer {
        let bpm = 100.0
        let lead = Voice(wave: .square(0.25), attack: 0.02, decay: 0.1, sustain: 0.6, release: 0.1, volume: 0.2)
        let bass = Voice(wave: .triangle, volume: 0.4)
        let tune: [(Double, Double)] = [(67, 2), (72, 1), (71, 2), (69, 1), (67, 2), (64, 1), (67, 3),
                                        (69, 2), (71, 1), (72, 2), (74, 1), (76, 2), (74, 1), (72, 3)]
        let beats = tune.reduce(0) { $0 + $1.1 }
        let b = Buffer(seconds: beats * 60 / bpm)
        melody(b, tune, bpm: bpm, voice: lead, vibrato: 0.006)
        var bl: [(Double, Double)] = []
        for i in 0..<Int(beats) { bl.append((i % 3 == 0 ? [48.0, 53, 55, 48][(i / 6) % 4] : -1, 1)) }
        melody(b, bl, bpm: bpm, voice: bass)
        return b
    }

    static func me(_ name: String) -> Buffer {
        let brass = Voice(wave: .square(0.5), attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.2, volume: 0.22)
        let low = Voice(wave: .triangle, attack: 0.01, decay: 0.2, sustain: 0.6, release: 0.3, volume: 0.35)
        switch name {
        case "Victory":
            let b = Buffer(seconds: 3.2)
            melody(b, [(72, 0.33), (72, 0.33), (72, 0.33), (72, 1), (68, 1), (70, 1), (72, 0.66), (70, 0.33), (72, 3)], bpm: 150, voice: brass)
            melody(b, [(48, 1), (-1, 1), (44, 1), (46, 1), (48, 3)], bpm: 150, voice: low)
            return b
        case "Defeat", "Gameover":
            let b = Buffer(seconds: 3.5)
            melody(b, [(69, 1), (68, 1), (67, 1), (66, 3)], bpm: 70, voice: Voice(wave: .triangle, attack: 0.05, release: 0.6, volume: 0.35))
            melody(b, [(45, 3), (38, 3)], bpm: 70, voice: low)
            return b
        case "Fanfare", "Item":
            let b = Buffer(seconds: 1.6)
            melody(b, [(67, 0.5), (72, 0.5), (76, 0.5), (79, 1.5)], bpm: 160, voice: brass)
            return b
        case "Inn":
            let b = Buffer(seconds: 3.0)
            melody(b, [(72, 1), (76, 1), (79, 1), (77, 1), (74, 1), (72, 2)], bpm: 120, voice: Voice(wave: .sine, release: 0.4, volume: 0.3))
            return b
        default: return Buffer(seconds: 0.5)
        }
    }

    static func rain() -> Buffer {
        let b = Buffer(seconds: 4)
        b.note(0, 4, 9000, Voice(wave: .noise, attack: 0.01, decay: 0.01, sustain: 1, release: 0.01, volume: 0.25))
        b.lowpass(0.35)
        // Random drips.
        var seed: UInt32 = 99
        for _ in 0..<40 {
            seed = seed &* 1_103_515_245 &+ 12345
            b.note(Double(seed % 3900) / 1000, 0.02, 2500 + Double(seed % 2000), Voice(wave: .sine, decay: 0.02, sustain: 0, volume: 0.08))
        }
        return b
    }

    public static func writeAll(to project: Project) throws {
        let fm = FileManager.default
        func write(_ b: Buffer, _ folder: String, _ name: String) throws {
            let dir = project.root.appendingPathComponent("audio/\(folder)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try b.wav().write(to: dir.appendingPathComponent(name + ".wav"))
        }
        for n in Set(systemSoundNames + extraSE) { try write(se(n), "se", n) }
        try write(village(), "bgm", "Village")
        try write(field(), "bgm", "Field")
        try write(battle(), "bgm", "Battle")
        try write(title(), "bgm", "Title")
        try write(ship(), "bgm", "Ship")
        for n in ["Victory", "Defeat", "Gameover", "Fanfare", "Inn"] { try write(me(n), "me", n) }
        try write(rain(), "bgs", "Rain")
    }
}
