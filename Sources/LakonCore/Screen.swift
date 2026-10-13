import Foundation

/// Port of MZ's Game_Screen + Game_Picture: tint, flash, shake, weather and pictures, updated once per frame.
/// Saved with the game like MZ's $gameScreen.
public struct GameScreen: Codable {
    public var tone: [Double] = [0, 0, 0, 0]          // r, g, b (-255…255), gray (0…255)
    var toneTarget: [Double] = [0, 0, 0, 0]
    var toneDuration = 0
    public var flashColor: [Double] = [0, 0, 0, 0]    // r, g, b, alpha (0…255)
    var flashDuration = 0
    var shakePower = 0.0, shakeSpeed = 0.0, shakeDuration = 0, shakeDirection = 1.0
    public var shake = 0.0                             // horizontal offset in px
    public var weatherType = "none"                    // none, rain, storm, snow
    public var weatherPower = 0.0                      // 0…9
    var weatherPowerTarget = 0.0
    var weatherDuration = 0
    public var pictures: [Int: GamePicture] = [:]

    public init() {}

    public mutating func startTint(_ t: [Double], duration: Int) {
        toneTarget = Array(t.prefix(4)); toneDuration = duration
        if duration <= 0 { tone = toneTarget }
    }
    public mutating func startFlash(_ c: [Double], duration: Int) { flashColor = Array(c.prefix(4)); flashDuration = max(1, duration) }
    public mutating func startShake(power: Int, speed: Int, duration: Int) {
        shakePower = Double(power); shakeSpeed = Double(speed); shakeDuration = duration
    }
    public mutating func changeWeather(_ type: String, power: Int, duration: Int) {
        if type != "none" || duration == 0 { weatherType = type }
        weatherPowerTarget = type == "none" ? 0 : Double(power)
        weatherDuration = duration
        if duration == 0 { weatherPower = weatherPowerTarget }
    }

    public mutating func update() {
        if toneDuration > 0 {
            let d = Double(toneDuration)
            for i in 0..<4 { tone[i] = (tone[i] * (d - 1) + toneTarget[i]) / d }
            toneDuration -= 1
        }
        if flashDuration > 0 {
            let d = Double(flashDuration)
            flashColor[3] *= (d - 1) / d
            flashDuration -= 1
        }
        if shakeDuration > 0 || shake != 0 {
            let delta = shakePower * shakeSpeed * shakeDirection / 10
            if shakeDuration <= 1 && shake * (shake + delta) < 0 { shake = 0 } else { shake += delta }
            if shake > shakePower * 2 { shakeDirection = -1 }
            if shake < -shakePower * 2 { shakeDirection = 1 }
            shakeDuration -= 1
        }
        if weatherDuration > 0 {
            let d = Double(weatherDuration)
            weatherPower = (weatherPower * (d - 1) + weatherPowerTarget) / d
            weatherDuration -= 1
            if weatherDuration == 0 && weatherPowerTarget == 0 { weatherType = "none" }
        }
        for k in pictures.keys { pictures[k]!.update() }
    }

    public mutating func clearForTransfer() { /* MZ keeps tone/pictures across transfers */ }
    public mutating func clearForBattleEnd() { flashColor = [0, 0, 0, 0]; flashDuration = 0; shake = 0; shakeDuration = 0 }
}

/// Port of Game_Map's parallax fields. `autoX/autoY` hold the auto-scroll accumulated by `update` in tiles;
/// the renderer adds the camera position the way Game_Map.parallaxOx/Oy do (MZ keeps both in `_parallaxX`).
public struct ParallaxState: Codable, Hashable {
    public var name = ""
    public var loopX = false
    public var loopY = false
    public var sx = 0
    public var sy = 0
    public var autoX = 0.0
    public var autoY = 0.0
    public init() {}
    public init(map: GameMap) {
        name = map.parallaxName; loopX = map.parallaxLoopX; loopY = map.parallaxLoopY; sx = map.parallaxSx; sy = map.parallaxSy
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = c.v(.name, ""); loopX = c.v(.loopX, false); loopY = c.v(.loopY, false); sx = c.v(.sx, 0); sy = c.v(.sy, 0)
        autoX = c.v(.autoX, 0); autoY = c.v(.autoY, 0)
    }
    /// "!" prefix: the image scrolls 1:1 with the map (ImageManager.isZeroParallax).
    public var isZero: Bool { name.hasPrefix("!") }

    /// Game_Map.updateParallax: loops advance by sx / tileWidth / 2 tiles per frame.
    public mutating func update() {
        if loopX { autoX += Double(sx) / 48 / 2 }
        if loopY { autoY += Double(sy) / 48 / 2 }
    }
    /// Game_Map.changeParallax: turning a loop off resets that axis.
    public mutating func change(name n: String, loopX lx: Bool, loopY ly: Bool, sx x: Int, sy y: Int) {
        if loopX && !lx { autoX = 0 }
        if loopY && !ly { autoY = 0 }
        name = n; loopX = lx; loopY = ly; sx = x; sy = y
    }
    /// Pixel origin of the tiling image for a camera at `displayX/Y` tiles (Game_Map.parallaxOx/Oy).
    public func origin(displayX: Double, displayY: Double) -> (Double, Double) {
        let px = displayX + autoX, py = displayY + autoY
        let ox = isZero ? px * 48 : loopX ? px * 48 / 2 : 0
        let oy = isZero ? py * 48 : loopY ? py * 48 / 2 : 0
        return (ox, oy)
    }
}

/// origin: 0 upper-left, 1 center. blendMode: 0 normal, 1 additive, 2 multiply, 3 screen.
/// easingType: 0 constant, 1 slow start, 2 slow end, 3 slow start and end.
public struct GamePicture: Codable {
    public var name: String
    public var origin = 0
    public var x = 0.0, y = 0.0
    public var scaleX = 100.0, scaleY = 100.0
    public var opacity = 255.0
    public var blendMode = 0
    public var angle = 0.0
    public var tone: [Double] = [0, 0, 0, 0]
    var target = [0.0, 0, 100, 100, 255]
    var duration = 0
    var wholeDuration = 0
    var easingType = 0
    var rotationSpeed = 0.0
    var toneTarget: [Double] = [0, 0, 0, 0]
    var toneDuration = 0

    public init(name: String, origin: Int, x: Double, y: Double, scaleX: Double, scaleY: Double, opacity: Double, blendMode: Int) {
        self.name = name; self.origin = origin; self.x = x; self.y = y
        self.scaleX = scaleX; self.scaleY = scaleY; self.opacity = opacity; self.blendMode = blendMode
    }

    mutating func move(origin o: Int, x: Double, y: Double, scaleX: Double, scaleY: Double, opacity: Double, blendMode: Int, duration d: Int, easing: Int) {
        origin = o; target = [x, y, scaleX, scaleY, opacity]; self.blendMode = blendMode
        duration = d; wholeDuration = d; easingType = easing
        if d == 0 { self.x = x; self.y = y; self.scaleX = scaleX; self.scaleY = scaleY; self.opacity = opacity }
    }
    mutating func rotate(_ speed: Double) { rotationSpeed = speed }
    mutating func tint(_ t: [Double], duration d: Int) {
        toneTarget = t; toneDuration = d
        if d == 0 { tone = t }
    }

    static func ease(_ type: Int, _ t: Double) -> Double {
        func easeIn(_ t: Double) -> Double { t * t }
        func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
        switch type {
        case 1: return easeIn(t)
        case 2: return easeOut(t)
        case 3: return t < 0.5 ? easeIn(t * 2) / 2 : easeOut(t * 2 - 1) / 2 + 0.5
        default: return t
        }
    }
    /// Game_Picture.applyEasing: interpolate so the remaining path follows the easing curve.
    func applyEasing(_ current: Double, _ target: Double) -> Double {
        let d = Double(duration), wd = Double(wholeDuration)
        let lt = Self.ease(easingType, (wd - d) / wd)
        let t = Self.ease(easingType, (wd - d + 1) / wd)
        let start = lt < 1 ? (current - target * lt) / (1 - lt) : target
        return start + (target - start) * t
    }

    mutating func update() {
        if duration > 0 {
            x = applyEasing(x, target[0]); y = applyEasing(y, target[1])
            scaleX = applyEasing(scaleX, target[2]); scaleY = applyEasing(scaleY, target[3])
            opacity = applyEasing(opacity, target[4])
            duration -= 1
        }
        if toneDuration > 0 {
            let d = Double(toneDuration)
            for i in 0..<4 { tone[i] = (tone[i] * (d - 1) + toneTarget[i]) / d }
            toneDuration -= 1
        }
        if rotationSpeed != 0 { angle += rotationSpeed / 2 }
    }
}

/// Audio requests from the simulation, drained by the app's audio player each frame (AudioManager's role).
public enum AudioCommand: Equatable {
    case playBgm(AudioFile, position: Double)
    case fadeOutBgm(seconds: Int)
    case stopBgm
    case playBgs(AudioFile)
    case fadeOutBgs(seconds: Int)
    case stopBgs
    case playMe(AudioFile)
    case playSe(AudioFile)
    case stopSe
}

public final class AudioState {
    public var pending: [AudioCommand] = []
    public private(set) var currentBgm: AudioFile?
    public private(set) var currentBgs: AudioFile?
    var savedBgm: AudioFile?
    var walkingBgm: AudioFile?

    public func playBgm(_ f: AudioFile) {
        if f.name.isEmpty { stopBgm(); return }
        if currentBgm == f { return }      // MZ keeps an already-playing BGM going
        currentBgm = f; pending.append(.playBgm(f, position: 0))
    }
    public func stopBgm() { currentBgm = nil; pending.append(.stopBgm) }
    public func fadeOutBgm(_ s: Int) { currentBgm = nil; pending.append(.fadeOutBgm(seconds: s)) }
    public func playBgs(_ f: AudioFile) {
        if f.name.isEmpty { currentBgs = nil; pending.append(.stopBgs); return }
        if currentBgs == f { return }
        currentBgs = f; pending.append(.playBgs(f))
    }
    public func fadeOutBgs(_ s: Int) { currentBgs = nil; pending.append(.fadeOutBgs(seconds: s)) }
    public func playMe(_ f: AudioFile) { if !f.name.isEmpty { pending.append(.playMe(f)) } }
    public func playSe(_ f: AudioFile) { if !f.name.isEmpty { pending.append(.playSe(f)) } }
    public func stopSe() { pending.append(.stopSe) }
    func saveBgm() { savedBgm = currentBgm }
    func replayBgm() { if let s = savedBgm { currentBgm = nil; playBgm(s) } else { stopBgm() } }
    public func drain() -> [AudioCommand] { defer { pending = [] }; return pending }
}
