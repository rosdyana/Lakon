import Foundation

/// Movement + animation shared by the player and events.
/// Behaviour follows rmmz_objects.js Game_CharacterBase / Game_Character:
/// tile-locked position (x, y) with a smoothly interpolated (realX, realY),
/// distancePerFrame = 2^speed / 256, animationWait = (9 - speed) * 3.
public class GameCharacter {
    public var x = 0, y = 0
    public var realX = 0.0, realY = 0.0
    public var direction = 2
    public var moveSpeed = 4
    public var moveFrequency = 6
    public var pattern = 1
    public var animationCount = 0.0
    public var stopCount = 0
    public var priorityType = 1
    public var through = false
    public var walkAnime = true
    public var stepAnime = false
    public var directionFix = false
    public var transparent = false
    public var characterName = ""
    public var characterIndex = 0
    public var tileId = 0
    public var movementSucceeded = true
    public var dashing = false
    /// Balloon icon (Show Balloon Icon, 213): 1 !, 2 ?, 3 ♪, 4 ♥, 5 anger, 6 sweat, 7 frustration, 8 silence, 9 light bulb, 10 zzz.
    public var balloonId = 0
    public var balloonFrames = 0
    /// Animation request (Show Animation, 212); the renderer plays a generic burst.
    public var animationId = 0
    public var animationFrames = 0

    // Move route (Set Movement Route / custom move type)
    public var moveRoute: [EventCommand] = []
    public var moveRouteRepeat = false
    public var moveRouteSkippable = false
    public var moveRouteIndex = 0
    public var moveRouteForcing = false
    var routeWait = 0

    weak var world: GameWorld?

    public init() {}

    public var isMoving: Bool { realX != Double(x) || realY != Double(y) }
    public var isObjectCharacter: Bool { characterName.hasPrefix("!") || characterName.hasPrefix("$!") }
    public var isBigCharacter: Bool { characterName.range(of: "^[!$]*\\$", options: .regularExpression) != nil }
    public var isNormalPriority: Bool { priorityType == 1 }
    public var patternIndex: Int { pattern < 3 ? pattern : 1 }
    var realMoveSpeed: Int { moveSpeed + (dashing ? 1 : 0) }
    var distancePerFrame: Double { pow(2, Double(realMoveSpeed)) / 256 }
    var animationWait: Double { Double(9 - realMoveSpeed) * 3 }

    public func locate(_ x: Int, _ y: Int) {
        self.x = x; self.y = y; realX = Double(x); realY = Double(y)
    }
    public func setDirection(_ d: Int) { if !directionFix && d != 0 { direction = d } }
    public func setImage(_ name: String, _ index: Int) { characterName = name; characterIndex = index; tileId = 0 }

    public static func xWith(_ x: Int, _ d: Int) -> Int { d == 6 ? x + 1 : d == 4 ? x - 1 : x }
    public static func yWith(_ y: Int, _ d: Int) -> Int { d == 2 ? y + 1 : d == 8 ? y - 1 : y }
    public static func reverse(_ d: Int) -> Int { 10 - d }

    // MARK: per-frame

    func update() {
        if balloonFrames > 0 { balloonFrames -= 1; if balloonFrames == 0 { balloonId = 0 } }
        if animationFrames > 0 { animationFrames -= 1; if animationFrames == 0 { animationId = 0 } }
        if !isMoving { stopCount += 1 }
        if isMoving { updateMove() }
        else if moveRouteForcing { updateRoutineMove() }
        else { updateSelfMovement() }
        updateAnimation()
    }

    func updateSelfMovement() {}

    private func updateMove() {
        let dpf = distancePerFrame
        if Double(x) < realX { realX = max(realX - dpf, Double(x)) }
        if Double(x) > realX { realX = min(realX + dpf, Double(x)) }
        if Double(y) < realY { realY = max(realY - dpf, Double(y)) }
        if Double(y) > realY { realY = min(realY + dpf, Double(y)) }
    }

    private func updateAnimation() {
        if isMoving && walkAnime { animationCount += 1.5 }
        else if stepAnime || pattern != 1 { animationCount += 1 }
        if animationCount >= animationWait {
            if !stepAnime && stopCount > 0 { pattern = 1 } else { pattern = (pattern + 1) % 4 }
            animationCount = 0
        }
    }

    // MARK: movement

    func canPass(_ x: Int, _ y: Int, _ d: Int) -> Bool {
        guard let w = world else { return false }
        let x2 = Self.xWith(x, d), y2 = Self.yWith(y, d)
        guard w.map.isValid(x2, y2) else { return false }
        if through { return true }
        guard w.map.isPassable(x, y, d, tileset: w.tileset),
              w.map.isPassable(x2, y2, Self.reverse(d), tileset: w.tileset) else { return false }
        return !isCollided(x2, y2)
    }

    func isCollided(_ x: Int, _ y: Int) -> Bool {
        guard let w = world else { return false }
        return w.events.contains { $0 !== self && $0.x == x && $0.y == y && !$0.through && $0.isNormalPriority && $0.pageIndex >= 0 }
    }

    @discardableResult
    public func moveStraight(_ d: Int) -> Bool {
        movementSucceeded = canPass(x, y, d)
        if movementSucceeded {
            setDirection(d)
            x = Self.xWith(x, d); y = Self.yWith(y, d)
            stopCount = 0
        } else {
            setDirection(d)
            checkEventTriggerTouchFront(d)
        }
        return movementSucceeded
    }

    func checkEventTriggerTouchFront(_ d: Int) {}

    func moveRandom() { moveStraight([2, 4, 6, 8][world?.rng.next(4) ?? 0]) }

    func moveToward(_ c: GameCharacter) {
        let sx = x - c.x, sy = y - c.y
        guard sx != 0 || sy != 0 else { return }
        if abs(sx) > abs(sy) {
            if !moveStraight(sx > 0 ? 4 : 6), sy != 0 { moveStraight(sy > 0 ? 8 : 2) }
        } else {
            if !moveStraight(sy > 0 ? 8 : 2), sx != 0 { moveStraight(sx > 0 ? 4 : 6) }
        }
    }
    func moveAway(_ c: GameCharacter) {
        let sx = x - c.x, sy = y - c.y
        if abs(sx) > abs(sy) { moveStraight(sx > 0 ? 6 : 4) } else { moveStraight(sy > 0 ? 2 : 8) }
    }
    func turnToward(_ c: GameCharacter) {
        let sx = x - c.x, sy = y - c.y
        if abs(sx) > abs(sy) { setDirection(sx > 0 ? 4 : 6) } else if sy != 0 { setDirection(sy > 0 ? 8 : 2) }
    }

    // MARK: move routes (ROUTE_* codes from rmmz_objects.js:7487)

    public func forceMoveRoute(_ list: [EventCommand], repeat rep: Bool, skippable: Bool) {
        moveRoute = list; moveRouteRepeat = rep; moveRouteSkippable = skippable
        moveRouteIndex = 0; moveRouteForcing = true; routeWait = 0
    }
    func setCustomRoute(_ list: [EventCommand], repeat rep: Bool, skippable: Bool) {
        moveRoute = list; moveRouteRepeat = rep; moveRouteSkippable = skippable; moveRouteIndex = 0
    }

    func updateRoutineMove() {
        if routeWait > 0 { routeWait -= 1; return }
        movementSucceeded = true
        guard moveRouteIndex < moveRoute.count else { moveRouteForcing = false; return }
        let cmd = moveRoute[moveRouteIndex]
        processMoveCommand(cmd)
        if movementSucceeded || moveRouteSkippable {
            moveRouteIndex += 1
            if moveRouteRepeat && moveRouteIndex >= moveRoute.count - 1 { moveRouteIndex = 0 }
        }
    }

    func processMoveCommand(_ c: EventCommand) {
        let p = c.parameters
        guard let w = world else { return }
        switch c.code {
        case 0:
            if moveRouteRepeat { moveRouteIndex = -1 } else if moveRouteForcing { moveRouteForcing = false }
        case 1: moveStraight(2)
        case 2: moveStraight(4)
        case 3: moveStraight(6)
        case 4: moveStraight(8)
        case 9: moveRandom()
        case 10: moveToward(w.player)
        case 11: moveAway(w.player)
        case 12: moveStraight(direction)
        case 13: let d = direction; let fix = directionFix; directionFix = true; moveStraight(Self.reverse(d)); directionFix = fix
        case 15: routeWait = max(0, p[p: 0].int - 1)
        case 16: setDirection(2)
        case 17: setDirection(4)
        case 18: setDirection(6)
        case 19: setDirection(8)
        case 22: setDirection(Self.reverse(direction))
        case 24: setDirection([2, 4, 6, 8][w.rng.next(4)])
        case 25: turnToward(w.player)
        case 27: w.state.setSwitch(p[p: 0].int, true)
        case 28: w.state.setSwitch(p[p: 0].int, false)
        case 29: moveSpeed = p[p: 0].int
        case 30: moveFrequency = p[p: 0].int
        case 31: walkAnime = true
        case 32: walkAnime = false
        case 33: stepAnime = true
        case 34: stepAnime = false
        case 35: directionFix = true
        case 36: directionFix = false
        case 37: through = true
        case 38: through = false
        case 39: transparent = true
        case 40: transparent = false
        case 41: setImage(p[p: 0].string, p[p: 1].int)
        case 44: if let f = AudioFile(p[p: 0]) { w.audio.playSe(f) }
        case 45: w.script.run(p[p: 0].string, interpreter: nil)
        case 14: break // jump: not animated; position unchanged
        case 5, 6, 7, 8:
            let (h, v) = [(4, 2), (6, 2), (4, 8), (6, 8)][c.code - 5]
            if canPass(x, y, h) && canPass(Self.xWith(x, h), y, v) { moveStraight(h); moveStraight(v) } else { movementSucceeded = false }
        case 20: setDirection([2: 4, 4: 8, 6: 2, 8: 6][direction] ?? direction)
        case 21: setDirection([2: 6, 4: 2, 6: 8, 8: 4][direction] ?? direction)
        case 23: setDirection(w.rng.next(2) == 0 ? ([2: 4, 4: 8, 6: 2, 8: 6][direction] ?? direction) : ([2: 6, 4: 2, 6: 8, 8: 4][direction] ?? direction))
        case 26: turnToward(w.player); setDirection(Self.reverse(direction))
        default: break
        }
        if moveRouteIndex < 0 { moveRouteIndex = 0; movementSucceeded = false }
    }
}

public final class GamePlayer: GameCharacter {
    override init() {
        super.init()
        moveSpeed = 4
        priorityType = 1
    }

    override func checkEventTriggerTouchFront(_ d: Int) {
        guard world?.vehicle == nil else { return }
        world?.startMapEvent(Self.xWith(x, d), Self.yWith(y, d), triggers: [1, 2], normal: true)
    }

    /// In a vehicle, passability comes from the vehicle (Game_Player.isMapPassable → Game_Vehicle.isMapPassable).
    override func canPass(_ x: Int, _ y: Int, _ d: Int) -> Bool {
        guard let w = world, let v = w.vehicle, !through else { return super.canPass(x, y, d) }
        let x2 = Self.xWith(x, d), y2 = Self.yWith(y, d)
        guard w.map.isValid(x2, y2) else { return false }
        if v.kind == .airship { return true }
        return v.isPassable(at: x2, y2) && !isCollided(x2, y2)
    }
}

public final class GameEvent: GameCharacter {
    public let eventId: Int
    public let data: MapEvent
    public private(set) var pageIndex = -1
    public var erased = false
    public var starting = false
    var locked = false
    var prelockDirection = 0
    public var trigger = -1
    public var moveType = 0
    var parallel: Interpreter?

    init(data: MapEvent, world: GameWorld) {
        eventId = data.id
        self.data = data
        super.init()
        self.world = world
        locate(data.x, data.y)
        refresh()
    }

    public var page: EventPage? { pageIndex >= 0 ? data.pages[pageIndex] : nil }
    public var list: [EventCommand] { page?.list ?? [] }

    func refresh() {
        let newIndex = erased ? -1 : findProperPageIndex()
        if newIndex != pageIndex { pageIndex = newIndex; setupPage() }
    }

    func findProperPageIndex() -> Int {
        // Last page whose conditions pass wins (rmmz_objects.js:9286).
        for i in stride(from: data.pages.count - 1, through: 0, by: -1) where meetsConditions(data.pages[i]) { return i }
        return -1
    }

    func meetsConditions(_ page: EventPage) -> Bool {
        guard let w = world else { return false }
        let c = page.conditions, s = w.state
        if c.switch1Valid && !s.switchValue(c.switch1Id) { return false }
        if c.switch2Valid && !s.switchValue(c.switch2Id) { return false }
        if c.variableValid && s.variable(c.variableId) < c.variableValue { return false }
        if c.selfSwitchValid && !s.selfSwitch(w.state.mapId, eventId, c.selfSwitchCh) { return false }
        if c.itemValid && s.itemCount(c.itemId) == 0 { return false }
        if c.actorValid && !s.party.contains(c.actorId) { return false }
        return true
    }

    private func setupPage() {
        parallel = nil
        guard let p = page else {
            characterName = ""; tileId = 0; priorityType = 0; trigger = -1; through = true
            moveRouteForcing = false
            return
        }
        tileId = p.image.tileId
        characterName = p.image.characterName
        characterIndex = p.image.characterIndex
        if p.image.direction != 0 { direction = p.image.direction }
        pattern = p.image.pattern
        moveSpeed = p.moveSpeed; moveFrequency = p.moveFrequency
        priorityType = p.priorityType; walkAnime = p.walkAnime; stepAnime = p.stepAnime
        directionFix = p.directionFix; through = p.through
        moveType = p.moveType; trigger = p.trigger
        if moveType == MoveType.custom.rawValue, case .object(let r) = p.moveRoute {
            let list = (r["list"]?.array ?? []).compactMap { v -> EventCommand? in
                guard case .object(let o) = v else { return nil }
                return EventCommand(code: o["code"]?.int ?? 0, indent: 0, parameters: o["parameters"]?.array ?? [])
            }
            setCustomRoute(list, repeat: r["repeat"]?.bool ?? true, skippable: r["skippable"]?.bool ?? false)
        }
        if trigger == Trigger.parallel.rawValue { parallel = Interpreter(depth: 0) }
    }

    public func isTriggerIn(_ triggers: [Int]) -> Bool { triggers.contains(trigger) }

    func start() {
        guard !list.isEmpty, list.count > 1 || list.first?.code != 0 else { return }
        starting = true
        if isTriggerIn([0, 1, 2]) { lock() }
    }
    func clearStartingFlag() { starting = false }

    func lock() {
        guard !locked, let w = world else { return }
        prelockDirection = direction
        turnToward(w.player)
        locked = true
    }
    func unlock() {
        guard locked else { return }
        locked = false
        setDirection(prelockDirection)
    }

    public func erase() { erased = true; refresh() }

    func checkEventTriggerAuto() { if trigger == Trigger.autorun.rawValue { start() } }

    override func update() {
        super.update()
        checkEventTriggerAuto()
        if let interp = parallel, let w = world {
            if !interp.isRunning { interp.setup(list, eventId: eventId) }
            interp.update(w)
        }
    }

    override func updateSelfMovement() {
        guard !locked, let w = world, pageIndex >= 0 else { return }
        if stopCount > 30 * (5 - moveFrequency) {
            switch moveType {
            case 1:
                switch w.rng.next(6) { case 0, 1: moveRandom(); case 2, 3, 4: moveStraight(direction); default: stopCount = 0 }
            case 2: moveToward(w.player)
            case 3: if !moveRoute.isEmpty { updateRoutineMove() }
            default: break
            }
        }
    }

    override func isCollided(_ x: Int, _ y: Int) -> Bool {
        if super.isCollided(x, y) { return true }
        guard let p = world?.player, isNormalPriority else { return false }
        return !p.through && p.x == x && p.y == y
    }

    /// Event Touch: the event bumped into the player (rmmz_objects.js Game_Event.checkEventTriggerTouch).
    override func checkEventTriggerTouchFront(_ d: Int) {
        guard let w = world, !w.isEventRunning, trigger == Trigger.eventTouch.rawValue, isNormalPriority else { return }
        if w.player.x == Self.xWith(x, d) && w.player.y == Self.yWith(y, d) { start() }
    }
}
