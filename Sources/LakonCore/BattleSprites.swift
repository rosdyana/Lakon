import Foundation

// Sprite logic without drawing: the frame-by-frame state of MZ's Sprite_AnimationMV / Sprite_Animation,
// Sprite_Actor (side-view motions, step forward/back, weapon swing) and Sprite_Enemy (whiten, blink, collapse).
// Renderers (SpriteKit player, web runtime) read these values and draw.

/// One playing animation (Spriteset_Base.createAnimationSprite). Call `update()` once per frame.
public final class AnimationPlayback {
    public struct Cell {
        public var pattern: Int          // cell index in the sheet (sx = pattern % 5 × 192, sy = pattern % 100 / 5 × 192)
        public var sheet: Int            // 1 or 2 (animation1Name / animation2Name)
        public var x: Double, y: Double
        public var scaleX: Double, scaleY: Double
        public var rotation: Double      // radians, clockwise on screen
        public var opacity: Double       // 0…255
        public var blend: Int            // 0 normal, 1 add, 2 multiply, 3 screen
    }

    public let animation: AnimationData
    public let mirror: Bool
    public private(set) var delay: Int
    /// Target ids (BattleCue encoding or map character serials), for positioning and flashes.
    public let targets: [Int]
    public private(set) var cells: [Cell] = []
    /// Target blend colour (r, g, b, a 0…255) while a flash runs (Sprite.setBlendColor).
    public private(set) var flashColor: [Double] = [0, 0, 0, 0]
    public private(set) var screenFlashColor: [Double] = [0, 0, 0, 0]
    public private(set) var hidingTargets = false
    public private(set) var isPlaying = true
    /// Effekseer entries: frames since start and the stand-in effect length (Lakon has no Effekseer runtime).
    public private(set) var frameIndex = 0
    public private(set) var started = false
    var duration = 0
    var flashDuration = 0, screenFlashDuration = 0, hidingDuration = 0
    var maxTimingFrames = 0

    public init(_ a: AnimationData, targets: [Int], mirror: Bool, delay: Int) {
        animation = a; self.targets = targets; self.mirror = mirror; self.delay = delay
        if let f = a.frames { duration = f.count * AnimationData.mvRate + 1 }
        else { maxTimingFrames = max(a.flashTimings.map(\.frame).max() ?? 0, a.soundTimings.map(\.frame).max() ?? 0) }
    }

    /// Effekseer stand-in length in frames (0 when the entry has no effect).
    public var standInLength: Int {
        animation.effectName.isEmpty ? 0 : Int((Double(AnimationData.standInFrames) * 100 / Double(max(10, animation.speed))).rounded())
    }
    /// 0…1 progress of the stand-in effect, nil once it ended or for MV animations.
    public var standInProgress: Double? {
        guard !animation.isMV, started, standInLength > 0, frameIndex <= standInLength else { return nil }
        return Double(frameIndex) / Double(standInLength)
    }

    /// Advances one frame; returns the sound effects to play now.
    public func update() -> [AudioFile] {
        var sounds: [AudioFile] = []
        if animation.isMV { updateMV(&sounds) } else { updateMZ(&sounds) }
        if flashDuration > 0 {
            let d = Double(flashDuration); flashDuration -= 1
            flashColor[3] *= (d - 1) / d
        }
        if screenFlashDuration > 0 {
            let d = Double(screenFlashDuration); screenFlashDuration -= 1
            screenFlashColor[3] *= (d - 1) / d
        }
        if hidingDuration > 0 { hidingDuration -= 1; if hidingDuration == 0 { hidingTargets = false } }
        return sounds
    }

    // Sprite_AnimationMV.updateMain / updateFrame / processTimingData / onEnd
    func updateMV(_ sounds: inout [AudioFile]) {
        guard isPlaying, let frames = animation.frames else { return }
        if delay > 0 { delay -= 1; return }
        started = true
        duration -= 1
        if duration % AnimationData.mvRate == 0 && duration > 0 {
            let index = frames.count - (duration + AnimationData.mvRate - 1) / AnimationData.mvRate
            if index >= 0 && index < frames.count {
                cells = frames[index].compactMap(makeCell)
                for t in animation.timings where t.frame == index {
                    let d = t.flashDuration * AnimationData.mvRate
                    switch t.flashScope {
                    case 1: flashColor = t.flashColor.map(Double.init); flashDuration = d
                    case 2: screenFlashColor = t.flashColor.map(Double.init); screenFlashDuration = d
                    case 3: hidingTargets = true; hidingDuration = d
                    default: break
                    }
                    if let se = t.se { sounds.append(se) }
                }
            }
        }
        if duration <= 0 {
            isPlaying = false; cells = []
            flashDuration = 0; screenFlashDuration = 0; hidingDuration = 0; hidingTargets = false
            flashColor = [0, 0, 0, 0]; screenFlashColor = [0, 0, 0, 0]
        }
    }

    func makeCell(_ c: [Double]) -> Cell? {
        guard c.count >= 8, c[0] >= 0 else { return nil }
        let pattern = Int(c[0])
        var cell = Cell(pattern: pattern % 100, sheet: pattern < 100 ? 1 : 2, x: c[1], y: c[2], scaleX: c[3] / 100, scaleY: c[3] / 100,
                        rotation: c[4] * .pi / 180, opacity: c[6], blend: Int(c[7]))
        if c[5] != 0 { cell.scaleX *= -1 }
        if mirror { cell.x *= -1; cell.rotation *= -1; cell.scaleX *= -1 }
        return cell
    }

    // Sprite_Animation.update / updateMain / checkEnd (the Effekseer handle replaced by the stand-in length)
    func updateMZ(_ sounds: inout [AudioFile]) {
        guard isPlaying else { return }
        if delay > 0 { delay -= 1; return }
        started = true
        for t in animation.soundTimings where t.frame == frameIndex { sounds.append(t.se) }
        for t in animation.flashTimings where t.frame == frameIndex { flashColor = t.color.map(Double.init); flashDuration = t.duration }
        frameIndex += 1
        if frameIndex > maxTimingFrames && flashDuration == 0 && frameIndex > standInLength { isPlaying = false }
    }
}

/// Sprite_Actor's motion and movement state for one party slot (side view).
public final class SVActorSprite {
    public static let motions: [String: (index: Int, loop: Bool)] = [
        "walk": (0, true), "wait": (1, true), "chant": (2, true), "guard": (3, true), "damage": (4, false), "evade": (5, false),
        "thrust": (6, false), "swing": (7, false), "missile": (8, false), "skill": (9, false), "spell": (10, false), "item": (11, false),
        "escape": (12, true), "victory": (13, true), "dying": (14, true), "abnormal": (15, true), "sleep": (16, true), "dead": (17, true),
    ]

    public let index: Int
    public private(set) var homeX: Double, homeY: Double
    public private(set) var offsetX = 0.0, offsetY = 0.0
    var targetOffsetX = Double.nan, targetOffsetY = Double.nan
    var movementDuration = 0
    public private(set) var motion = "wait"
    var motionCount = 0
    var pattern = 0
    public private(set) var weaponImageId = 0
    public private(set) var weaponPattern = 0
    var weaponCount = 0
    var lastActionState = ""
    var lastStateMotion = -1
    weak var actor: GameActor?

    public init(index: Int) {
        self.index = index
        homeX = Double(600 + index * 32); homeY = Double(280 + index * 48)
        startMove(300, 0, 0)      // moveToStartPosition
    }

    public var x: Double { homeX + offsetX }
    public var y: Double { homeY + offsetY }
    public var isMoving: Bool { movementDuration > 0 }
    var inHomePosition: Bool { offsetX == 0 && offsetY == 0 }
    /// Cell in the sv_actors sheet: column (motion / 6) × 3 + pattern, row motion % 6.
    public var frame: (col: Int, row: Int) {
        let m = Self.motions[motion]?.index ?? 1
        return ((m / 6) * 3 + (pattern < 3 ? pattern : 1), m % 6)
    }

    func startMove(_ x: Double, _ y: Double, _ d: Int) {
        if targetOffsetX != x || targetOffsetY != y {
            targetOffsetX = x; targetOffsetY = y; movementDuration = d
            if d == 0 { offsetX = x; offsetY = y }
        }
    }

    func startMotion(_ name: String) {
        if motion != name { motion = name; motionCount = 0; pattern = 0 }
    }
    /// A motion requested by the battle (Game_Battler.requestMotion). Like Sprite_Actor.setupMotion → clearMotion,
    /// it also drops a pending refresh, so "victory" isn't replaced by the action-state change made at the same time.
    public func requestMotion(_ name: String) {
        startMotion(name)
        if let a = actor { lastActionState = a.actionState; lastStateMotion = a.stateMotionIndex }
    }
    public func startWeapon(_ id: Int) { weaponImageId = id; weaponCount = 0; weaponPattern = 0 }

    /// Sprite_Actor.setBattler → startEntryMotion: run in from the right.
    public func setActor(_ a: GameActor?) {
        if a !== actor {
            actor = a
            if let a, a.canMove { startMotion("walk"); startMove(0, 0, 30) } else if !isMoving { refreshMotion(); startMove(0, 0, 0) }
        }
    }

    func refreshMotion() {
        guard let a = actor else { return }
        let sm = a.stateMotionIndex
        if a.isInputting || a.isActing { startMotion("walk") }
        else if sm == 3 || a.isDead { startMotion("dead") }
        else if sm == 2 { startMotion("sleep") }
        else if a.isChanting { startMotion("chant") }
        else if a.isGuardWaiting || (a.isGuarding && a.actionState != "done") { startMotion("guard") }
        else if sm == 1 { startMotion("abnormal") }
        else if a.isDying { startMotion("dying") }
        else if a.isUndecided { startMotion("walk") }
        else { startMotion("wait") }
    }

    /// One frame (Sprite_Actor.update): movement, step forward/back, motion pattern, weapon.
    public func update(escaped: Bool, battleEnded: Bool) {
        guard let a = actor else { return }
        if movementDuration > 0 {
            let d = Double(movementDuration)
            offsetX = (offsetX * (d - 1) + targetOffsetX) / d
            offsetY = (offsetY * (d - 1) + targetOffsetY) / d
            movementDuration -= 1
            if movementDuration == 0 && !battleEnded { refreshMotion() }
        }
        if !isMoving {
            if a.canMove && escaped { startMove(300, 0, 30) }                       // retreat
            else if a.isInputting || a.isActing { startMove(-48, 0, 12) }           // stepForward
            else if !inHomePosition { startMove(0, 0, 12) }                          // stepBack
        }
        // Game_Battler.setActionState / state changes request a motion refresh.
        if a.actionState != lastActionState || a.stateMotionIndex != lastStateMotion || (motion == "dead") != a.isDead {
            lastActionState = a.actionState; lastStateMotion = a.stateMotionIndex
            if !(Self.motions[motion]?.loop == false && motionCount > 0 && !a.isDead) || a.isDead { refreshMotion() }
        }
        motionCount += 1
        if motionCount >= 12 {
            if Self.motions[motion]?.loop ?? true { pattern = (pattern + 1) % 4 }
            else if pattern < 2 { pattern += 1 }
            else { refreshMotion() }
            motionCount = 0
        }
        if weaponImageId > 0 {
            weaponCount += 1
            if weaponCount >= 12 { weaponPattern += 1; weaponCount = 0; if weaponPattern >= 3 { weaponImageId = 0 } }
        }
    }
}

/// Sprite_Enemy's effects: appear, disappear, whiten, blink, collapse, boss collapse, instant collapse.
public final class EnemySpriteEffect {
    public private(set) var effectType: String?
    public private(set) var duration = 0
    public private(set) var opacity = 255.0
    /// Additive blend colour (r, g, b, a).
    public private(set) var blendColor: [Double] = [0, 0, 0, 0]
    public private(set) var additive = false
    public private(set) var shake = 0.0
    public private(set) var appeared: Bool
    /// Boss collapse: rows of the bitmap still visible (the sprite shrinks from the bottom).
    public var bossCollapseHeight: Int { effectType == "bossCollapse" ? duration : -1 }
    var bitmapHeight: Int
    /// Boss Collapse 2 SE requests (every 20 frames while the boss fades).
    public private(set) var wantsBossSound = false

    public init(alive: Bool, bitmapHeight: Int) {
        appeared = alive; self.bitmapHeight = max(1, bitmapHeight)
        if !alive { opacity = 0 }
    }

    public var isEffecting: Bool { effectType != nil }

    public func start(_ type: String) {
        effectType = type
        switch type {
        case "appear": duration = 16; appeared = true
        case "disappear": duration = 32; appeared = false
        case "whiten": duration = 16
        case "blink": duration = 20
        case "collapse": duration = 32; appeared = false
        case "bossCollapse": duration = bitmapHeight; appeared = false
        case "instantCollapse": duration = 16; appeared = false
        default: effectType = nil
        }
        shake = 0; additive = false; opacity = 255; blendColor = [0, 0, 0, 0]
    }

    /// Sprite_Enemy.setupEffect's automatic appear/disappear, then updateEffect.
    public func update(alive: Bool, hidden: Bool) {
        wantsBossSound = false
        if !appeared && alive && !hidden && !isCollapseEffect { start("appear") }
        else if appeared && hidden { start("disappear") }
        guard duration > 0, let t = effectType else { return }
        duration -= 1
        switch t {
        case "whiten": blendColor = [255, 255, 255, Double(128 - (16 - duration) * 8)]
        case "blink": opacity = duration % 10 < 5 ? 255 : 0
        case "appear": opacity = Double((16 - duration) * 16)
        case "disappear": opacity = Double(256 - (32 - duration) * 10)
        case "collapse":
            additive = true; blendColor = [255, 128, 128, 128]
            opacity *= Double(duration) / Double(duration + 1)
        case "bossCollapse":
            shake = Double(duration % 2 * 4 - 2); additive = true
            opacity *= Double(duration) / Double(duration + 1)
            blendColor = [255, 255, 255, 255 - opacity]
            if duration % 20 == 19 { wantsBossSound = true }
        case "instantCollapse": opacity = 0
        default: break
        }
        if duration == 0 {
            effectType = nil
            if t == "whiten" || t == "blink" { blendColor = [0, 0, 0, 0]; opacity = 255 }
            if t == "collapse" || t == "bossCollapse" || t == "instantCollapse" || t == "disappear" { opacity = 0 }
        }
    }
    var isCollapseEffect: Bool { ["collapse", "bossCollapse", "instantCollapse"].contains(effectType ?? "") }
}
