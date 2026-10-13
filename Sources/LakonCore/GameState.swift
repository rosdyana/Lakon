import Foundation

/// $gameSwitches / $gameVariables / $gameSelfSwitches / $gameParty, plus player location — everything a save file holds.
public struct GameState: Codable {
    public var switches: [Int: Bool] = [:]
    public var variables: [Int: Int] = [:]
    public var selfSwitches: Set<String> = []
    public var gold = 0
    public var items: [Int: Int] = [:]
    public var party: [Int] = []
    public var mapId = 1
    public var playerX = 0, playerY = 0, playerDirection = 2
    public var steps = 0
    public var playFrames = 0
    public var weapons: [Int: Int] = [:]
    public var armors: [Int: Int] = [:]
    public var actors: [Int: ActorSave] = [:]
    public var screen = GameScreen()
    public var vehicles: [VehicleSave] = []
    public var vehicleType = -1          // -1 walking, 0 boat, 1 ship, 2 airship
    public var bgm: AudioFile?
    public var bgs: AudioFile?
    public var battleCount = 0
    public var winCount = 0
    public var escapeCount = 0
    public var saveCount = 0
    public var encounterEnabled = true
    public var menuEnabled = true
    public var saveEnabled = true
    public var battleBgm: AudioFile?
    public var victoryMe: AudioFile?

    /// Set when switches/variables change so events re-pick their page (Game_Map.requestRefresh).
    var needsRefresh = false

    enum CodingKeys: String, CodingKey {
        case switches, variables, selfSwitches, gold, items, party, mapId, playerX, playerY, playerDirection, steps, playFrames
        case weapons, armors, actors, screen, vehicles, vehicleType, bgm, bgs, battleCount, winCount, escapeCount, saveCount
        case encounterEnabled, menuEnabled, saveEnabled, battleBgm, victoryMe
    }

    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        switches = c.v(.switches, [:]); variables = c.v(.variables, [:]); selfSwitches = c.v(.selfSwitches, [])
        gold = c.v(.gold, 0); items = c.v(.items, [:]); party = c.v(.party, []); mapId = c.v(.mapId, 1)
        playerX = c.v(.playerX, 0); playerY = c.v(.playerY, 0); playerDirection = c.v(.playerDirection, 2)
        steps = c.v(.steps, 0); playFrames = c.v(.playFrames, 0); weapons = c.v(.weapons, [:]); armors = c.v(.armors, [:])
        actors = c.v(.actors, [:]); screen = c.v(.screen, GameScreen()); vehicles = c.v(.vehicles, []); vehicleType = c.v(.vehicleType, -1)
        bgm = c.v(.bgm, nil); bgs = c.v(.bgs, nil); battleCount = c.v(.battleCount, 0); winCount = c.v(.winCount, 0)
        escapeCount = c.v(.escapeCount, 0); saveCount = c.v(.saveCount, 0); encounterEnabled = c.v(.encounterEnabled, true)
        menuEnabled = c.v(.menuEnabled, true); saveEnabled = c.v(.saveEnabled, true); battleBgm = c.v(.battleBgm, nil); victoryMe = c.v(.victoryMe, nil)
    }

    public func switchValue(_ id: Int) -> Bool { switches[id] ?? false }
    public mutating func setSwitch(_ id: Int, _ v: Bool) { if id > 0 { switches[id] = v; needsRefresh = true } }
    public func variable(_ id: Int) -> Int { variables[id] ?? 0 }
    public mutating func setVariable(_ id: Int, _ v: Int) {
        if id > 0 { variables[id] = max(-99_999_999, min(99_999_999, v)); needsRefresh = true }
    }
    public static func selfKey(_ mapId: Int, _ eventId: Int, _ ch: String) -> String { "\(mapId),\(eventId),\(ch)" }
    public func selfSwitch(_ mapId: Int, _ eventId: Int, _ ch: String) -> Bool { selfSwitches.contains(Self.selfKey(mapId, eventId, ch)) }
    public mutating func setSelfSwitch(_ mapId: Int, _ eventId: Int, _ ch: String, _ v: Bool) {
        let k = Self.selfKey(mapId, eventId, ch)
        if v { selfSwitches.insert(k) } else { selfSwitches.remove(k) }
        needsRefresh = true
    }
    public func itemCount(_ id: Int) -> Int { items[id] ?? 0 }
    public mutating func gainItem(_ id: Int, _ n: Int) {
        let v = max(0, min(99, itemCount(id) + n))
        items[id] = v == 0 ? nil : v
        needsRefresh = true
    }
    public mutating func gainGold(_ n: Int) { gold = max(0, min(99_999_999, gold + n)) }

    /// kind: 1 item, 2 weapon, 3 armor (MZ's dropItem/goods kinds).
    public func count(kind: Int, id: Int) -> Int {
        switch kind { case 2: return weapons[id] ?? 0; case 3: return armors[id] ?? 0; default: return items[id] ?? 0 }
    }
    public mutating func gain(kind: Int, id: Int, _ n: Int) {
        guard id > 0 else { return }
        func bump(_ d: inout [Int: Int]) { let v = max(0, min(99, (d[id] ?? 0) + n)); d[id] = v == 0 ? nil : v }
        switch kind { case 2: bump(&weapons); case 3: bump(&armors); default: bump(&items) }
        needsRefresh = true
    }
}

public struct VehicleSave: Codable {
    public var mapId: Int
    public var x: Int
    public var y: Int
    public var direction: Int
}

public struct GameMessage {
    public var faceName = ""
    public var faceIndex = 0
    public var background = 0      // 0 window, 1 dim, 2 transparent
    public var positionType = 2    // 0 top, 1 middle, 2 bottom
    public var speakerName = ""
    public var lines: [String] = []
    public var choices: [String] = []
    public var choiceDefault = 0
    public var choiceCancel = -1   // -1 disallowed, -2 "Branch", else index
    public var choiceIndex = 0
    public var visibleChars = 0
    var onChoose: ((Int) -> Void)?
    /// Input Number (103): digits shown after the text; the value goes to `numberVariable`.
    public var numberVariable = 0
    public var numberDigits = 0
    public var number = 0
    public var numberCursor = 0
    /// Select Item (104): pick an item of `itemChoiceType` (1 regular, 2 key, 3 hidden A, 4 hidden B).
    public var itemChoiceVariable = 0
    public var itemChoiceType = 0
    public var itemChoices: [Int] = []
    public var itemChoiceIndex = 0
    /// Scrolling text (105): drawn as a scrolling page instead of a window.
    public var scrolling = false
    public var scrollSpeed = 2
    public var scrollOffset = 0.0

    public var text: String { lines.joined(separator: "\n") }
    public var isTextComplete: Bool { visibleChars >= text.count }
    public var showsChoices: Bool { !choices.isEmpty && isTextComplete }
}

public struct InputState {
    public var dir4 = 0
    public var ok = false
    public var cancel = false
    public var up = false
    public var down = false
    public var left = false
    public var right = false
    public var dash = false
    /// Held buttons for Conditional Branch "Button" (ok, cancel, shift, up, down, left, right, pageup, pagedown).
    public var held: Set<String> = []
    public init(dir4: Int = 0, ok: Bool = false, cancel: Bool = false, up: Bool = false, down: Bool = false,
                left: Bool = false, right: Bool = false, dash: Bool = false) {
        self.dir4 = dir4; self.ok = ok; self.cancel = cancel; self.up = up; self.down = down
        self.left = left; self.right = right; self.dash = dash
    }
}

public protocol RandomSource: AnyObject { func next(_ upper: Int) -> Int }
public final class SystemRandom: RandomSource {
    public init() {}
    public func next(_ upper: Int) -> Int { upper > 0 ? Int.random(in: 0..<upper) : 0 }
}
/// Deterministic generator for tests.
public final class SeededRandom: RandomSource {
    var s: UInt64
    public init(_ seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
    public func next(_ upper: Int) -> Int {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return upper > 0 ? Int(s % UInt64(upper)) : 0
    }
}
