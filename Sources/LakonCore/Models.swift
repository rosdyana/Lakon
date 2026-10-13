import Foundation

// Field names mirror RPG Maker MZ's data/*.json so MZ projects can be imported
// and Lakon's files stay readable by anyone who knows the MZ schema.

public struct EventCommand: Codable, Hashable {
    public var code: Int
    public var indent: Int
    public var parameters: [JSONValue]
    public init(code: Int, indent: Int, parameters: [JSONValue] = []) {
        self.code = code; self.indent = indent; self.parameters = parameters
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = c.v(.code, 0); indent = c.v(.indent, 0); parameters = c.v(.parameters, [])
    }
    public static func end(_ indent: Int) -> EventCommand { EventCommand(code: 0, indent: indent) }
}

public struct PageConditions: Codable, Hashable {
    public var actorId = 1, actorValid = false
    public var itemId = 1, itemValid = false
    public var selfSwitchCh = "A", selfSwitchValid = false
    public var switch1Id = 1, switch1Valid = false
    public var switch2Id = 1, switch2Valid = false
    public var variableId = 1, variableValid = false, variableValue = 0
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        actorId = c.v(.actorId, 1); actorValid = c.v(.actorValid, false)
        itemId = c.v(.itemId, 1); itemValid = c.v(.itemValid, false)
        selfSwitchCh = c.v(.selfSwitchCh, "A"); selfSwitchValid = c.v(.selfSwitchValid, false)
        switch1Id = c.v(.switch1Id, 1); switch1Valid = c.v(.switch1Valid, false)
        switch2Id = c.v(.switch2Id, 1); switch2Valid = c.v(.switch2Valid, false)
        variableId = c.v(.variableId, 1); variableValid = c.v(.variableValid, false)
        variableValue = c.v(.variableValue, 0)
    }
}

public struct EventImage: Codable, Hashable {
    public var tileId = 0
    public var characterName = ""
    public var direction = 2
    public var pattern = 1
    public var characterIndex = 0
    public init(characterName: String = "", characterIndex: Int = 0, direction: Int = 2, tileId: Int = 0) {
        self.characterName = characterName; self.characterIndex = characterIndex
        self.direction = direction; self.tileId = tileId
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        tileId = c.v(.tileId, 0); characterName = c.v(.characterName, "")
        direction = c.v(.direction, 2); pattern = c.v(.pattern, 1); characterIndex = c.v(.characterIndex, 0)
    }
    public var isEmpty: Bool { tileId == 0 && characterName.isEmpty }
}

public enum Trigger: Int, CaseIterable { case actionButton = 0, playerTouch, eventTouch, autorun, parallel
    public var label: String { ["Action Button", "Player Touch", "Event Touch", "Autorun", "Parallel"][rawValue] }
}
public enum Priority: Int, CaseIterable { case below = 0, same, above
    public var label: String { ["Below characters", "Same as characters", "Above characters"][rawValue] }
}
public enum MoveType: Int, CaseIterable { case fixed = 0, random, approach, custom
    public var label: String { ["Fixed", "Random", "Approach", "Custom"][rawValue] }
}

public struct EventPage: Codable, Hashable {
    public var conditions = PageConditions()
    public var directionFix = false
    public var image = EventImage()
    public var list: [EventCommand] = [.end(0)]
    public var moveFrequency = 3
    public var moveRoute: JSONValue = .object(["list": [.object(["code": 0, "parameters": []])], "repeat": true, "skippable": false, "wait": false])
    public var moveSpeed = 3
    public var moveType = 0
    public var priorityType = 0
    public var stepAnime = false
    public var through = false
    public var trigger = 0
    public var walkAnime = true
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conditions = c.v(.conditions, PageConditions()); directionFix = c.v(.directionFix, false)
        image = c.v(.image, EventImage()); list = c.v(.list, [.end(0)])
        if list.isEmpty { list = [.end(0)] }
        moveFrequency = c.v(.moveFrequency, 3); moveRoute = c.v(.moveRoute, .null)
        moveSpeed = c.v(.moveSpeed, 3); moveType = c.v(.moveType, 0)
        priorityType = c.v(.priorityType, 0); stepAnime = c.v(.stepAnime, false)
        through = c.v(.through, false); trigger = c.v(.trigger, 0); walkAnime = c.v(.walkAnime, true)
    }
}

public struct MapEvent: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var note = ""
    public var pages: [EventPage]
    public var x: Int
    public var y: Int
    public init(id: Int, x: Int, y: Int) {
        self.id = id; self.x = x; self.y = y
        name = String(format: "EV%03d", id); pages = [EventPage()]
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); note = c.v(.note, "")
        pages = c.v(.pages, [EventPage()]); x = c.v(.x, 0); y = c.v(.y, 0)
        if pages.isEmpty { pages = [EventPage()] }
    }
}

/// `data` is a flat array of width*height*6: z0..z3 tile layers, z4 shadow bits, z5 region id.
/// Index = (z * height + y) * width + x  (rmmz_objects.js Game_Map.prototype.tileId).
public struct GameMap: Codable, Hashable {
    public static let layerCount = 6
    public var displayName = ""
    public var note = ""
    public var tilesetId = 1
    public var width: Int
    public var height: Int
    public var scrollType = 0
    public var data: [Int]
    public var events: [MapEvent?] = [nil]
    public var autoplayBgm = false
    public var bgm = AudioFile()
    public var autoplayBgs = false
    public var bgs = AudioFile()
    public var encounterList: [Encounter] = []
    public var encounterStep = 30
    public var specifyBattleback = false
    public var battleback1Name = ""
    public var battleback2Name = ""
    public var disableDashing = false

    public init(width: Int, height: Int, tilesetId: Int = 1, fill: Int = 0) {
        self.width = width; self.height = height; self.tilesetId = tilesetId
        data = Array(repeating: 0, count: width * height * Self.layerCount)
        if fill != 0 { for i in 0..<(width * height) { data[i] = fill } }
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        displayName = c.v(.displayName, ""); note = c.v(.note, ""); tilesetId = c.v(.tilesetId, 1)
        width = c.v(.width, 17); height = c.v(.height, 13); scrollType = c.v(.scrollType, 0)
        data = c.v(.data, []); events = c.v(.events, [nil])
        autoplayBgm = c.v(.autoplayBgm, false); bgm = c.v(.bgm, AudioFile()); autoplayBgs = c.v(.autoplayBgs, false); bgs = c.v(.bgs, AudioFile())
        encounterList = c.v(.encounterList, []); encounterStep = c.v(.encounterStep, 30)
        specifyBattleback = c.v(.specifyBattleback, false); battleback1Name = c.v(.battleback1Name, ""); battleback2Name = c.v(.battleback2Name, "")
        disableDashing = c.v(.disableDashing, false)
        let need = width * height * Self.layerCount
        if data.count < need { data += Array(repeating: 0, count: need - data.count) }
        if events.isEmpty { events = [nil] }
    }

    @inline(__always) public func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (z * height + y) * width + x }
    public func isValid(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }
    public func tileId(_ x: Int, _ y: Int, _ z: Int) -> Int { isValid(x, y) ? data[index(x, y, z)] : 0 }
    public mutating func setTile(_ x: Int, _ y: Int, _ z: Int, _ id: Int) { if isValid(x, y) { data[index(x, y, z)] = id } }

    public var liveEvents: [MapEvent] { events.compactMap { $0 } }
    public func event(at x: Int, _ y: Int) -> MapEvent? { liveEvents.first { $0.x == x && $0.y == y } }
    public func nextEventId() -> Int { max(1, events.count) }

    /// Resizes keeping content anchored at top-left (MZ's map properties dialog behaves the same).
    public mutating func resize(width w: Int, height h: Int) {
        var nd = Array(repeating: 0, count: w * h * Self.layerCount)
        for z in 0..<Self.layerCount { for y in 0..<min(h, height) { for x in 0..<min(w, width) {
            nd[(z * h + y) * w + x] = data[index(x, y, z)]
        } } }
        data = nd; width = w; height = h
        for i in events.indices where events[i] != nil {
            if events[i]!.x >= w || events[i]!.y >= h { events[i] = nil }
        }
    }
}

public struct MapInfo: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var parentId = 0
    public var order: Int
    public var expanded = false
    public var scrollX = 0.0
    public var scrollY = 0.0
    public init(id: Int, name: String, order: Int, parentId: Int = 0) {
        self.id = id; self.name = name; self.order = order; self.parentId = parentId
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); parentId = c.v(.parentId, 0); order = c.v(.order, 0)
        expanded = c.v(.expanded, false); scrollX = c.v(.scrollX, 0); scrollY = c.v(.scrollY, 0)
    }
}

/// `tilesetNames` order: A1, A2, A3, A4, A5, B, C, D, E (setNumber 0...8 in Tilemap).
/// `flags[tileId]` bits: 0x1 down, 0x2 left, 0x4 right, 0x8 up = impassable; 0x10 = ☆ (above chars, no effect on passage).
public struct Tileset: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var mode = 1
    public var note = ""
    public var tilesetNames: [String]
    public var flags: [Int]
    public init(id: Int, name: String, names: [String]) {
        self.id = id; self.name = name
        tilesetNames = names + Array(repeating: "", count: max(0, 9 - names.count))
        flags = Array(repeating: 0, count: TileID.max)
        flags[0] = 0x10
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); mode = c.v(.mode, 1); note = c.v(.note, "")
        tilesetNames = c.v(.tilesetNames, Array(repeating: "", count: 9))
        flags = c.v(.flags, [])
        if tilesetNames.count < 9 { tilesetNames += Array(repeating: "", count: 9 - tilesetNames.count) }
        if flags.count < TileID.max { flags += Array(repeating: 0, count: TileID.max - flags.count) }
    }
    public func flag(_ tileId: Int) -> Int { tileId >= 0 && tileId < flags.count ? flags[tileId] : 0 }
}

public struct SystemData: Codable, Hashable {
    public var gameTitle = "Untitled"
    public var currencyUnit = "G"
    public var startMapId = 1
    public var startX = 0
    public var startY = 0
    public var partyMembers = [1]
    public var switches: [String] = [""] + Array(repeating: "", count: 20)
    public var variables: [String] = [""] + Array(repeating: "", count: 20)
    public var windowTone: [Int] = [0, 0, 0, 0]
    public var titleBgm = AudioFile()
    public var battleBgm = AudioFile()
    public var victoryMe = AudioFile()
    public var defeatMe = AudioFile()
    public var gameoverMe = AudioFile()
    /// 24 system sounds: cursor, ok, cancel, buzzer, equip, save, load, battle start, escape, enemy attack, enemy damage,
    /// enemy collapse, boss collapse 1, boss collapse 2, actor damage, actor collapse, recovery, miss, evasion, magic evasion,
    /// magic reflection, shop, use item, use skill.
    public var sounds: [AudioFile] = Array(repeating: AudioFile(), count: 24)
    public var boat = VehicleData()
    public var ship = VehicleData()
    public var airship = VehicleData()
    public var terms = Terms()
    public var elements: [String] = ["", "Physical"]
    public var skillTypes: [String] = ["", "Magic", "Special"]
    public var weaponTypes: [String] = ["", "Dagger", "Sword"]
    public var armorTypes: [String] = ["", "General Armor", "Magic Armor"]
    public var equipTypes: [String] = ["", "Weapon", "Shield", "Head", "Body", "Accessory"]
    public var battleback1Name = ""
    public var battleback2Name = ""
    public var optDisplayTp = true
    public var optSlipDeath = false
    public var optFloorDeath = false
    public var optExtraExp = false
    public var title1Name = ""
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        gameTitle = c.v(.gameTitle, "Untitled"); currencyUnit = c.v(.currencyUnit, "G")
        startMapId = c.v(.startMapId, 1); startX = c.v(.startX, 0); startY = c.v(.startY, 0)
        partyMembers = c.v(.partyMembers, [1])
        switches = c.v(.switches, [""]); variables = c.v(.variables, [""])
        windowTone = c.v(.windowTone, [0, 0, 0, 0])
        titleBgm = c.v(.titleBgm, AudioFile()); battleBgm = c.v(.battleBgm, AudioFile()); victoryMe = c.v(.victoryMe, AudioFile())
        defeatMe = c.v(.defeatMe, AudioFile()); gameoverMe = c.v(.gameoverMe, AudioFile())
        sounds = c.v(.sounds, Array(repeating: AudioFile(), count: 24))
        if sounds.count < 24 { sounds += Array(repeating: AudioFile(), count: 24 - sounds.count) }
        boat = c.v(.boat, VehicleData()); ship = c.v(.ship, VehicleData()); airship = c.v(.airship, VehicleData())
        terms = c.v(.terms, Terms())
        elements = c.v(.elements, ["", "Physical"]); skillTypes = c.v(.skillTypes, ["", "Magic", "Special"])
        weaponTypes = c.v(.weaponTypes, ["", "Dagger", "Sword"]); armorTypes = c.v(.armorTypes, ["", "General Armor", "Magic Armor"])
        equipTypes = c.v(.equipTypes, ["", "Weapon", "Shield", "Head", "Body", "Accessory"])
        battleback1Name = c.v(.battleback1Name, ""); battleback2Name = c.v(.battleback2Name, "")
        optDisplayTp = c.v(.optDisplayTp, true); optSlipDeath = c.v(.optSlipDeath, false)
        optFloorDeath = c.v(.optFloorDeath, false); optExtraExp = c.v(.optExtraExp, false); title1Name = c.v(.title1Name, "")
    }
}

public struct Actor: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var nickname = ""
    public var profile = ""
    public var classId = 1
    public var initialLevel = 1
    public var maxLevel = 99
    public var characterName = ""
    public var characterIndex = 0
    public var faceName = ""
    public var faceIndex = 0
    public var battlerName = ""
    /// Initial equipment per slot (weapon, shield, head, body, accessory).
    public var equips = [0, 0, 0, 0, 0]
    public var traits: [Trait] = []
    public var note = ""
    public init(id: Int, name: String, characterName: String = "", characterIndex: Int = 0) {
        self.id = id; self.name = name; self.characterName = characterName; self.characterIndex = characterIndex
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); nickname = c.v(.nickname, ""); profile = c.v(.profile, "")
        classId = c.v(.classId, 1); initialLevel = c.v(.initialLevel, 1); maxLevel = c.v(.maxLevel, 99)
        characterName = c.v(.characterName, ""); characterIndex = c.v(.characterIndex, 0)
        faceName = c.v(.faceName, ""); faceIndex = c.v(.faceIndex, 0); battlerName = c.v(.battlerName, "")
        equips = c.v(.equips, [0, 0, 0, 0, 0]); traits = c.v(.traits, []); note = c.v(.note, "")
    }
}

/// itypeId: 1 regular, 2 key item, 3 hidden A, 4 hidden B.
public struct Item: Codable, Hashable, Identifiable, UsableItem {
    public var id: Int
    public var name: String
    public var description = ""
    public var iconIndex = 0
    public var price = 0
    public var consumable = true
    public var itypeId = 1
    public var scope = 7
    public var occasion = 0
    public var speed = 0
    public var successRate = 100
    public var repeats = 1
    public var tpGain = 0
    public var hitType = 0
    public var animationId = 0
    public var damage = Damage()
    public var effects: [Effect] = []
    public var note = ""
    public var isSkill: Bool { false }
    public init(id: Int, name: String, description: String = "", price: Int = 0) {
        self.id = id; self.name = name; self.description = description; self.price = price
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); description = c.v(.description, "")
        iconIndex = c.v(.iconIndex, 0); price = c.v(.price, 0); consumable = c.v(.consumable, true)
        itypeId = c.v(.itypeId, 1); scope = c.v(.scope, 7); occasion = c.v(.occasion, 0); speed = c.v(.speed, 0)
        successRate = c.v(.successRate, 100); repeats = c.v(.repeats, 1); tpGain = c.v(.tpGain, 0); hitType = c.v(.hitType, 0)
        animationId = c.v(.animationId, 0); damage = c.v(.damage, Damage()); effects = c.v(.effects, []); note = c.v(.note, "")
    }
    enum CodingKeys: String, CodingKey {
        case id, name, description, iconIndex, price, consumable, itypeId, scope, occasion, speed, successRate, repeats, tpGain
        case hitType, animationId, damage, effects, note
    }
}

/// trigger: 0 none, 1 autorun, 2 parallel (both gated by switchId).
public struct CommonEvent: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var trigger = 0
    public var switchId = 1
    public var list: [EventCommand] = [.end(0)]
    public init(id: Int, name: String) { self.id = id; self.name = name }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); trigger = c.v(.trigger, 0)
        switchId = c.v(.switchId, 1); list = c.v(.list, [.end(0)])
        if list.isEmpty { list = [.end(0)] }
    }
}
