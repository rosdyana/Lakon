import Foundation

// Battle/database records in MZ's schema (Classes.json, Skills.json, Weapons.json, Armors.json,
// Enemies.json, Troops.json, States.json). Decoding is lenient like the rest of the models.

public struct AudioFile: Codable, Hashable {
    public var name = ""
    public var volume = 90
    public var pitch = 100
    public var pan = 0
    public init(_ name: String = "", volume: Int = 90, pitch: Int = 100, pan: Int = 0) {
        self.name = name; self.volume = volume; self.pitch = pitch; self.pan = pan
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = c.v(.name, ""); volume = c.v(.volume, 90); pitch = c.v(.pitch, 100); pan = c.v(.pan, 0)
    }
    public init?(_ v: JSONValue) {
        guard case .object(let o) = v else { return nil }
        name = o["name"]?.string ?? ""; volume = o["volume"]?.int ?? 90; pitch = o["pitch"]?.int ?? 100; pan = o["pan"]?.int ?? 0
    }
    public var json: JSONValue { .object(["name": .string(name), "volume": .int(volume), "pitch": .int(pitch), "pan": .int(pan)]) }
}

public struct Trait: Codable, Hashable {
    public var code: Int
    public var dataId: Int
    public var value: Double
    public init(_ code: Int, _ dataId: Int, _ value: Double) { self.code = code; self.dataId = dataId; self.value = value }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = c.v(.code, 0); dataId = c.v(.dataId, 0); value = c.v(.value, 0)
    }
    // Trait codes (rmmz_objects.js Game_BattlerBase.TRAIT_*)
    public static let elementRate = 11, debuffRate = 12, stateRate = 13, stateResist = 14
    public static let param = 21, xparam = 22, sparam = 23
    public static let attackElement = 31, attackState = 32, attackSpeed = 33, attackTimes = 34, attackSkill = 35
    public static let stypeAdd = 41, stypeSeal = 42, skillAdd = 43, skillSeal = 44
    public static let equipWtype = 51, equipAtype = 52, equipLock = 53, equipSeal = 54, slotType = 55
    public static let actionPlus = 61, specialFlag = 62, collapseType = 63, partyAbility = 64
}

public struct Effect: Codable, Hashable {
    public var code: Int
    public var dataId: Int
    public var value1: Double
    public var value2: Double
    public init(_ code: Int, _ dataId: Int = 0, _ value1: Double = 0, _ value2: Double = 0) {
        self.code = code; self.dataId = dataId; self.value1 = value1; self.value2 = value2
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = c.v(.code, 0); dataId = c.v(.dataId, 0); value1 = c.v(.value1, 0); value2 = c.v(.value2, 0)
    }
    // Effect codes (Game_Action.EFFECT_*)
    public static let recoverHp = 11, recoverMp = 12, gainTp = 13, addState = 21, removeState = 22
    public static let addBuff = 31, addDebuff = 32, removeBuff = 33, removeDebuff = 34
    public static let special = 41, grow = 42, learnSkill = 43, commonEvent = 44
}

/// damage.type: 0 none, 1 HP damage, 2 MP damage, 3 HP recover, 4 MP recover, 5 HP drain, 6 MP drain.
public struct Damage: Codable, Hashable {
    public var type = 0
    public var elementId = 0
    public var formula = "0"
    public var variance = 20
    public var critical = false
    public init(type: Int = 0, formula: String = "0", elementId: Int = 0, variance: Int = 20, critical: Bool = false) {
        self.type = type; self.formula = formula; self.elementId = elementId; self.variance = variance; self.critical = critical
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        type = c.v(.type, 0); elementId = c.v(.elementId, 0); formula = c.v(.formula, "0")
        variance = c.v(.variance, 20); critical = c.v(.critical, false)
    }
}

/// Shared by skills and items. scope: 0 none, 1 one enemy, 2 all enemies, 3–6 1–4 random enemies,
/// 7 one ally, 8 all allies, 9 one dead ally, 10 all dead allies, 11 user, 12 one ally (any), 13 all allies (any), 14 everybody.
/// occasion: 0 always, 1 battle only, 2 menu only, 3 never. hitType: 0 certain, 1 physical, 2 magical.
public protocol UsableItem {
    var id: Int { get }
    var name: String { get }
    var description: String { get }
    var iconIndex: Int { get }
    var scope: Int { get }
    var occasion: Int { get }
    var speed: Int { get }
    var successRate: Int { get }
    var repeats: Int { get }
    var tpGain: Int { get }
    var hitType: Int { get }
    var animationId: Int { get }
    var damage: Damage { get }
    var effects: [Effect] { get }
    var isSkill: Bool { get }
}

extension UsableItem {
    public var isForOpponent: Bool { (1...6).contains(scope) || scope == 14 }
    public var isForFriend: Bool { (7...13).contains(scope) || scope == 14 }
    public var isForOne: Bool { [1, 3, 7, 9, 11, 12].contains(scope) }
    public var isForAll: Bool { [2, 8, 10, 13, 14].contains(scope) }
    public var isForRandom: Bool { (3...6).contains(scope) }
    public var isForUser: Bool { scope == 11 }
    public var isForDeadFriend: Bool { scope == 9 || scope == 10 }
    public var needsTargetSelection: Bool { [1, 7, 9, 12].contains(scope) }
    public var isPhysical: Bool { hitType == 1 }
    public var isMagical: Bool { hitType == 2 }
    public var isBattleUsable: Bool { occasion == 0 || occasion == 1 }
    public var isMenuUsable: Bool { occasion == 0 || occasion == 2 }
}

public struct Skill: Codable, Hashable, Identifiable, UsableItem {
    public var id: Int
    public var name: String
    public var description = ""
    public var iconIndex = 0
    public var stypeId = 1
    public var mpCost = 0
    public var tpCost = 0
    public var scope = 1
    public var occasion = 1
    public var speed = 0
    public var successRate = 100
    public var repeats = 1
    public var tpGain = 0
    public var hitType = 1
    public var animationId = 0
    public var damage = Damage()
    public var effects: [Effect] = []
    public var message1 = ""
    public var message2 = ""
    public var note = ""
    public var requiredWtypeId1 = 0
    public var requiredWtypeId2 = 0
    public var isSkill: Bool { true }

    public init(id: Int, name: String) { self.id = id; self.name = name }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); description = c.v(.description, ""); iconIndex = c.v(.iconIndex, 0)
        stypeId = c.v(.stypeId, 1); mpCost = c.v(.mpCost, 0); tpCost = c.v(.tpCost, 0); scope = c.v(.scope, 1)
        occasion = c.v(.occasion, 1); speed = c.v(.speed, 0); successRate = c.v(.successRate, 100); repeats = c.v(.repeats, 1)
        tpGain = c.v(.tpGain, 0); hitType = c.v(.hitType, 1); animationId = c.v(.animationId, 0); damage = c.v(.damage, Damage())
        effects = c.v(.effects, []); message1 = c.v(.message1, ""); message2 = c.v(.message2, ""); note = c.v(.note, "")
        requiredWtypeId1 = c.v(.requiredWtypeId1, 0); requiredWtypeId2 = c.v(.requiredWtypeId2, 0)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, description, iconIndex, stypeId, mpCost, tpCost, scope, occasion, speed, successRate, repeats, tpGain
        case hitType, animationId, damage, effects, message1, message2, note, requiredWtypeId1, requiredWtypeId2
    }
}

/// Weapons (etypeId 1) and armors share this shape; params = [mhp, mmp, atk, def, mat, mdf, agi, luk] bonuses.
public struct EquipItem: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var description = ""
    public var iconIndex = 0
    public var price = 0
    public var etypeId = 1
    public var wtypeId = 0
    public var atypeId = 0
    public var params = [0, 0, 0, 0, 0, 0, 0, 0]
    public var traits: [Trait] = []
    public var animationId = 0
    public var note = ""
    public init(id: Int, name: String, etypeId: Int, params: [Int] = [0, 0, 0, 0, 0, 0, 0, 0], price: Int = 0) {
        self.id = id; self.name = name; self.etypeId = etypeId; self.params = params; self.price = price
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); description = c.v(.description, ""); iconIndex = c.v(.iconIndex, 0)
        price = c.v(.price, 0); etypeId = c.v(.etypeId, 1); wtypeId = c.v(.wtypeId, 0); atypeId = c.v(.atypeId, 0)
        params = c.v(.params, [0, 0, 0, 0, 0, 0, 0, 0]); traits = c.v(.traits, []); animationId = c.v(.animationId, 0); note = c.v(.note, "")
        if params.count < 8 { params += Array(repeating: 0, count: 8 - params.count) }
    }
}

public struct Learning: Codable, Hashable {
    public var level: Int
    public var skillId: Int
    public var note = ""
    public init(level: Int, skillId: Int) { self.level = level; self.skillId = skillId }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        level = c.v(.level, 1); skillId = c.v(.skillId, 1); note = c.v(.note, "")
    }
}

/// params[paramId][level] (8 x 100) — MZ stores the full curve per level.
public struct ClassData: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var expParams = [30, 20, 30, 30]
    public var params: [[Int]]
    public var learnings: [Learning] = []
    public var traits: [Trait] = []
    public var note = ""
    public init(id: Int, name: String, base: [Int], growth: [Int]) {
        self.id = id; self.name = name
        params = (0..<8).map { p in (0..<100).map { lv in base[p] + growth[p] * max(0, lv - 1) } }
        traits = [Trait(Trait.equipWtype, 1, 1), Trait(Trait.equipWtype, 2, 1), Trait(Trait.equipAtype, 1, 1), Trait(Trait.equipAtype, 2, 1),
                  Trait(Trait.xparam, 0, 0.95), Trait(Trait.xparam, 1, 0.05), Trait(Trait.xparam, 2, 0.04),
                  Trait(Trait.sparam, 0, 1), Trait(Trait.sparam, 1, 1), Trait(Trait.sparam, 2, 1), Trait(Trait.sparam, 3, 1),
                  Trait(Trait.sparam, 4, 1), Trait(Trait.sparam, 5, 1), Trait(Trait.sparam, 6, 1), Trait(Trait.sparam, 7, 1),
                  Trait(Trait.sparam, 8, 1), Trait(Trait.sparam, 9, 1), Trait(Trait.attackElement, 1, 0)]
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); expParams = c.v(.expParams, [30, 20, 30, 30])
        params = c.v(.params, []); learnings = c.v(.learnings, []); traits = c.v(.traits, []); note = c.v(.note, "")
        if params.count < 8 { params += Array(repeating: Array(repeating: 1, count: 100), count: 8 - params.count) }
    }
}

public struct DropItem: Codable, Hashable {
    public var kind = 0        // 0 none, 1 item, 2 weapon, 3 armor
    public var dataId = 1
    public var denominator = 1
    public init(kind: Int, dataId: Int, denominator: Int) { self.kind = kind; self.dataId = dataId; self.denominator = denominator }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = c.v(.kind, 0); dataId = c.v(.dataId, 1); denominator = c.v(.denominator, 1)
    }
}

public struct EnemyAction: Codable, Hashable {
    public var skillId = 1
    public var rating = 5
    public var conditionType = 0
    public var conditionParam1 = 0.0
    public var conditionParam2 = 0.0
    public init(skillId: Int, rating: Int = 5) { self.skillId = skillId; self.rating = rating }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        skillId = c.v(.skillId, 1); rating = c.v(.rating, 5); conditionType = c.v(.conditionType, 0)
        conditionParam1 = c.v(.conditionParam1, 0); conditionParam2 = c.v(.conditionParam2, 0)
    }
}

public struct Enemy: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var battlerName = ""
    public var battlerHue = 0
    public var params = [100, 0, 10, 10, 10, 10, 10, 10]
    public var exp = 0
    public var gold = 0
    public var dropItems: [DropItem] = []
    public var actions: [EnemyAction] = [EnemyAction(skillId: 1)]
    public var traits: [Trait] = []
    public var note = ""
    public init(id: Int, name: String, battlerName: String, params: [Int], exp: Int, gold: Int) {
        self.id = id; self.name = name; self.battlerName = battlerName; self.params = params; self.exp = exp; self.gold = gold
        traits = [Trait(Trait.xparam, 0, 0.95), Trait(Trait.xparam, 1, 0.05), Trait(Trait.attackElement, 1, 0)]
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); battlerName = c.v(.battlerName, ""); battlerHue = c.v(.battlerHue, 0)
        params = c.v(.params, [100, 0, 10, 10, 10, 10, 10, 10]); exp = c.v(.exp, 0); gold = c.v(.gold, 0)
        dropItems = c.v(.dropItems, []); actions = c.v(.actions, []); traits = c.v(.traits, []); note = c.v(.note, "")
        if params.count < 8 { params += Array(repeating: 0, count: 8 - params.count) }
    }
}

public struct TroopMember: Codable, Hashable {
    public var enemyId: Int
    public var x: Int
    public var y: Int
    public var hidden = false
    public init(enemyId: Int, x: Int, y: Int) { self.enemyId = enemyId; self.x = x; self.y = y }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enemyId = c.v(.enemyId, 1); x = c.v(.x, 408); y = c.v(.y, 312); hidden = c.v(.hidden, false)
    }
}

public struct TroopPageConditions: Codable, Hashable {
    public var actorHp = 50, actorId = 1, actorValid = false
    public var enemyHp = 50, enemyIndex = 0, enemyValid = false
    public var switchId = 1, switchValid = false
    public var turnA = 0, turnB = 0, turnEnding = false, turnValid = false
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        actorHp = c.v(.actorHp, 50); actorId = c.v(.actorId, 1); actorValid = c.v(.actorValid, false)
        enemyHp = c.v(.enemyHp, 50); enemyIndex = c.v(.enemyIndex, 0); enemyValid = c.v(.enemyValid, false)
        switchId = c.v(.switchId, 1); switchValid = c.v(.switchValid, false)
        turnA = c.v(.turnA, 0); turnB = c.v(.turnB, 0); turnEnding = c.v(.turnEnding, false); turnValid = c.v(.turnValid, false)
    }
}

/// span: 0 battle, 1 turn, 2 moment.
public struct TroopPage: Codable, Hashable {
    public var conditions = TroopPageConditions()
    public var list: [EventCommand] = [.end(0)]
    public var span = 0
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conditions = c.v(.conditions, TroopPageConditions()); list = c.v(.list, [.end(0)]); span = c.v(.span, 0)
    }
}

public struct Troop: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var members: [TroopMember] = []
    public var pages: [TroopPage] = [TroopPage()]
    public init(id: Int, name: String, members: [TroopMember]) { self.id = id; self.name = name; self.members = members }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); members = c.v(.members, []); pages = c.v(.pages, [TroopPage()])
    }
}

/// restriction: 0 none, 1 attack an enemy, 2 attack anyone, 3 attack an ally, 4 cannot move.
/// autoRemovalTiming: 0 none, 1 action end, 2 turn end.
public struct StateData: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var iconIndex = 0
    public var restriction = 0
    public var priority = 50
    public var autoRemovalTiming = 0
    public var minTurns = 1
    public var maxTurns = 1
    public var removeAtBattleEnd = false
    public var removeByDamage = false
    public var chanceByDamage = 100
    public var removeByRestriction = false
    public var removeByWalking = false
    public var stepsToRemove = 100
    public var traits: [Trait] = []
    public var message1 = ""
    public var message2 = ""
    public var message3 = ""
    public var message4 = ""
    public var note = ""
    public init(id: Int, name: String) { self.id = id; self.name = name }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.v(.id, 0); name = c.v(.name, ""); iconIndex = c.v(.iconIndex, 0); restriction = c.v(.restriction, 0)
        priority = c.v(.priority, 50); autoRemovalTiming = c.v(.autoRemovalTiming, 0); minTurns = c.v(.minTurns, 1)
        maxTurns = c.v(.maxTurns, 1); removeAtBattleEnd = c.v(.removeAtBattleEnd, false); removeByDamage = c.v(.removeByDamage, false)
        chanceByDamage = c.v(.chanceByDamage, 100); removeByRestriction = c.v(.removeByRestriction, false)
        removeByWalking = c.v(.removeByWalking, false); stepsToRemove = c.v(.stepsToRemove, 100); traits = c.v(.traits, [])
        message1 = c.v(.message1, ""); message2 = c.v(.message2, ""); message3 = c.v(.message3, ""); message4 = c.v(.message4, "")
        note = c.v(.note, "")
    }
}

public struct VehicleData: Codable, Hashable {
    public var bgm = AudioFile()
    public var characterIndex = 0
    public var characterName = ""
    public var startMapId = 0
    public var startX = 0
    public var startY = 0
    public init(characterName: String = "", characterIndex: Int = 0) { self.characterName = characterName; self.characterIndex = characterIndex }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        bgm = c.v(.bgm, AudioFile()); characterIndex = c.v(.characterIndex, 0); characterName = c.v(.characterName, "")
        startMapId = c.v(.startMapId, 0); startX = c.v(.startX, 0); startY = c.v(.startY, 0)
    }
}

public struct Terms: Codable, Hashable {
    public var basic = ["Level", "Lv", "HP", "HP", "MP", "MP", "TP", "TP", "EXP", "EXP"]
    public var commands = ["Fight", "Escape", "Attack", "Guard", "Item", "Skill", "Equip", "Status", "Formation", "Save", "Game End", "Options",
                           "Weapon", "Armor", "Key Item", "Equip", "Optimize", "Clear", "New Game", "Continue", "", "To Title", "Cancel", "",
                           "Buy", "Sell"]
    public var params = ["Max HP", "Max MP", "Attack", "Defense", "M.Attack", "M.Defense", "Agility", "Luck", "Hit", "Evasion"]
    public var messages: [String: String] = [
        "emerge": "%1 emerged!", "preemptive": "%1 got the upper hand!", "surprise": "%1 was surprised!",
        "escapeStart": "%1 has started to escape!", "escapeFailure": "However, it was unable to escape!",
        "victory": "%1 was victorious!", "defeat": "%1 was defeated.", "obtainExp": "%1 %2 received!",
        "obtainGold": "%1\\G found!", "obtainItem": "%1 found!", "levelUp": "%1 is now %2 %3!", "obtainSkill": "%1 learned!",
        "actorDamage": "%1 took %2 damage!", "actorRecovery": "%1 recovered %2 %3!", "actorGain": "%1 gained %2 %3!",
        "actorLoss": "%1 lost %2 %3!", "actorDrain": "%1 was drained of %2 %3!", "actorNoDamage": "%1 took no damage!",
        "actorNoHit": "Miss! %1 took no damage!", "enemyDamage": "%1 took %2 damage!", "enemyRecovery": "%1 recovered %2 %3!",
        "enemyGain": "%1 gained %2 %3!", "enemyLoss": "%1 lost %2 %3!", "enemyDrain": "Drained %2 %3 from %1!",
        "enemyNoDamage": "%1 took no damage!", "enemyNoHit": "Miss! %1 took no damage!", "evasion": "%1 evaded the attack!",
        "criticalToEnemy": "An excellent hit!!", "criticalToActor": "A painful blow!!", "useItem": "%1 uses %2!",
        "partyName": "%1's Party", "possession": "Possession", "alwaysDash": "Always Dash", "commandRemember": "Command Remember",
        "bgmVolume": "BGM Volume", "bgsVolume": "BGS Volume", "meVolume": "ME Volume", "seVolume": "SE Volume",
        "saveMessage": "Save to which file?", "loadMessage": "Load which file?", "file": "File", "autosave": "Autosave",
        "expTotal": "Current %1", "expNext": "To Next %1", "buffAdd": "%1's %2 went up!", "debuffAdd": "%1's %2 went down!",
        "buffRemove": "%1's %2 returned to normal!", "actionFailure": "There was no effect on %1!",
    ]
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Terms()
        basic = c.v(.basic, def.basic); commands = c.v(.commands, def.commands); params = c.v(.params, def.params)
        let m: [String: String] = c.v(.messages, [:])
        messages = def.messages.merging(m) { _, new in new }
        if commands.count < def.commands.count { commands += def.commands.suffix(def.commands.count - commands.count) }
    }
    public func message(_ key: String, _ args: String...) -> String {
        var s = messages[key] ?? key
        for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "%\(i + 1)", with: a) }
        return s
    }
}

/// Map encounter entry; regionSet empty = anywhere on the map.
public struct Encounter: Codable, Hashable {
    public var troopId: Int
    public var weight = 10
    public var regionSet: [Int] = []
    public init(troopId: Int, weight: Int = 10, regionSet: [Int] = []) { self.troopId = troopId; self.weight = weight; self.regionSet = regionSet }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        troopId = c.v(.troopId, 1); weight = c.v(.weight, 10); regionSet = c.v(.regionSet, [])
    }
}
