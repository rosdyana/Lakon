import Foundation

/// One entry of data/Animations.json. MZ stores two formats in the same file (rmmz_sprites.js
/// Spriteset_Base.isMVAnimation: "!!animation.frames"):
/// - MZ format: an Effekseer effect (`effectName`, effects/<name>.efkefc) plus `flashTimings` and `soundTimings`.
/// - MV format: cell frames cut from 192×192 cells of img/animations sheets (`frames`, `timings`).
/// Lakon plays MV cells exactly. For Effekseer entries it honours the flash/sound timings and, in the Mac player,
/// draws a procedural particle stand-in; the HTML export can play the real effect.
public struct AnimationData: Codable, Hashable, Identifiable {
    public struct FlashTiming: Codable, Hashable {
        public var frame = 0
        public var duration = 10
        public var color = [255, 255, 255, 170]
        public init(frame: Int, duration: Int, color: [Int]) { self.frame = frame; self.duration = duration; self.color = color }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            frame = c.v(.frame, 0); duration = c.v(.duration, 10); color = c.v(.color, [255, 255, 255, 170])
        }
    }
    public struct SoundTiming: Codable, Hashable {
        public var frame = 0
        public var se = AudioFile()
        public init(frame: Int, se: AudioFile) { self.frame = frame; self.se = se }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            frame = c.v(.frame, 0); se = c.v(.se, AudioFile())
        }
    }
    /// MV timing: flashScope 0 none, 1 target, 2 screen, 3 hide target. flashDuration is in animation frames (×4 game frames).
    public struct MVTiming: Codable, Hashable {
        public var frame = 0
        public var flashScope = 0
        public var flashColor = [255, 255, 255, 255]
        public var flashDuration = 5
        public var se: AudioFile?
        public init(frame: Int, flashScope: Int = 0, flashColor: [Int] = [255, 255, 255, 255], flashDuration: Int = 5, se: AudioFile? = nil) {
            self.frame = frame; self.flashScope = flashScope; self.flashColor = flashColor; self.flashDuration = flashDuration; self.se = se
        }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            frame = c.v(.frame, 0); flashScope = c.v(.flashScope, 0); flashColor = c.v(.flashColor, [255, 255, 255, 255])
            flashDuration = c.v(.flashDuration, 5); se = c.v(.se, nil)
            if se?.name.isEmpty == true { se = nil }
        }
    }
    public struct Rotation: Codable, Hashable {
        public var x = 0.0, y = 0.0, z = 0.0
        public init() {}
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            x = c.v(.x, 0); y = c.v(.y, 0); z = c.v(.z, 0)
        }
    }

    public var id: Int
    public var name = ""
    // MZ (Effekseer) format
    /// 0 for each target, 1 center of the targets, 2 screen.
    public var displayType = 0
    public var effectName = ""
    public var flashTimings: [FlashTiming] = []
    public var soundTimings: [SoundTiming] = []
    public var offsetX = 0
    public var offsetY = 0
    public var rotation = Rotation()
    public var scale = 100
    public var speed = 100
    public var alignBottom = false
    // MV format
    /// frames[f][cell] = [pattern, x, y, scale%, rotation°, mirror, opacity, blend]; pattern ≥ 100 uses animation2.
    public var frames: [[[Double]]]?
    public var timings: [MVTiming] = []
    public var animation1Name = ""
    public var animation1Hue = 0
    public var animation2Name = ""
    public var animation2Hue = 0
    /// 0 head, 1 center, 2 feet, 3 screen.
    public var position = 1

    public init(id: Int, name: String) { self.id = id; self.name = name }

    enum CodingKeys: String, CodingKey {
        case id, name, displayType, effectName, flashTimings, soundTimings, offsetX, offsetY, rotation, scale, speed, alignBottom
        case frames, timings, animation1Name, animation1Hue, animation2Name, animation2Hue, position
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, "")
        displayType = c.v(.displayType, 0); effectName = c.v(.effectName, "")
        flashTimings = c.v(.flashTimings, []); soundTimings = c.v(.soundTimings, [])
        offsetX = c.v(.offsetX, 0); offsetY = c.v(.offsetY, 0); rotation = c.v(.rotation, Rotation())
        scale = c.v(.scale, 100); speed = c.v(.speed, 100); alignBottom = c.v(.alignBottom, false)
        frames = c.v(.frames, nil); timings = c.v(.timings, [])
        animation1Name = c.v(.animation1Name, ""); animation1Hue = c.v(.animation1Hue, 0)
        animation2Name = c.v(.animation2Name, ""); animation2Hue = c.v(.animation2Hue, 0)
        position = c.v(.position, 1)
    }

    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        if let f = frames {
            try c.encode(f, forKey: .frames); try c.encode(timings, forKey: .timings)
            try c.encode(animation1Name, forKey: .animation1Name); try c.encode(animation1Hue, forKey: .animation1Hue)
            try c.encode(animation2Name, forKey: .animation2Name); try c.encode(animation2Hue, forKey: .animation2Hue)
            try c.encode(position, forKey: .position)
        } else {
            try c.encode(displayType, forKey: .displayType); try c.encode(effectName, forKey: .effectName)
            try c.encode(flashTimings, forKey: .flashTimings); try c.encode(soundTimings, forKey: .soundTimings)
            try c.encode(offsetX, forKey: .offsetX); try c.encode(offsetY, forKey: .offsetY); try c.encode(rotation, forKey: .rotation)
            try c.encode(scale, forKey: .scale); try c.encode(speed, forKey: .speed); try c.encode(alignBottom, forKey: .alignBottom)
        }
    }

    public var isMV: Bool { frames != nil }
    /// MV: one sprite per target unless positioned on the screen. MZ: per target when displayType is 0 (Spriteset_Base.isAnimationForEach).
    public var isForEach: Bool { isMV ? position != 3 : displayType == 0 }
    public var isScreen: Bool { isMV ? position == 3 : displayType == 2 }

    /// Frames until one sprite of this animation stops playing (excluding its start delay).
    /// MV: frames × 4 + 1 (Sprite_AnimationMV.setupDuration). MZ: the last flash/sound timing, or the
    /// stand-in effect length when the effect can't be measured (Lakon has no Effekseer runtime on macOS).
    public var playFrames: Int {
        if let f = frames { return f.count * AnimationData.mvRate + 1 }
        let lastFlash = flashTimings.map { $0.frame + $0.duration }.max() ?? 0
        let lastSound = soundTimings.map(\.frame).max() ?? 0
        let standIn = effectName.isEmpty ? 0 : Int((Double(AnimationData.standInFrames) * 100 / Double(max(10, speed))).rounded())
        return max(lastFlash, lastSound + 1, standIn, 1)
    }

    /// Frames until every sprite for `targets` targets has finished: base delay 8, +12 per extra target in
    /// per-target mode (Spriteset_Base.animationBaseDelay/animationNextDelay).
    public func totalFrames(targets: Int) -> Int {
        let n = isForEach ? max(1, targets) : 1
        return AnimationData.baseDelay + (n - 1) * AnimationData.nextDelay + playFrames
    }

    public static let mvRate = 4
    public static let baseDelay = 8
    public static let nextDelay = 12
    public static let standInFrames = 40
}

extension Project {
    public func animation(_ id: Int) -> AnimationData? { id > 0 && id < animations.count ? animations[id] : nil }
}
