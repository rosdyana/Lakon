import Foundation
import LakonCore

/// New-project template: procedural art and audio, a complete small database (classes, skills, states,
/// equipment, enemies, troops), and a playable demo: a village (shop, inn, guessing game, chest, boat),
/// a house where a second hero joins, and an overworld with random encounters, a ship, an airship,
/// weather, a plugin-command campfire and a boss battle.
public enum SampleProject {
    typealias A = DefaultArt

    public static func create(at root: URL, title: String, withDemo: Bool = true) throws -> Project {
        let p = Project(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try DefaultArt.writeAll(to: p)
        try DefaultAudio.writeAll(to: p)
        buildDatabase(p, title: title)
        if withDemo {
            buildVillage(p); buildHouse(p); buildWorld(p); buildSkyLedge(p)
            try writeDemoPlugin(p)
        } else {
            p.createMap(name: "MAP001", fill: A.a2(A.grass)); fixShapes(&p.maps[1]!)
        }
        p.system.startMapId = 1
        p.system.startX = withDemo ? 11 : 8
        p.system.startY = withDemo ? 10 : 6
        try p.save()
        return p
    }

    static func fixShapes(_ m: inout GameMap) {
        for z in 0..<2 { for y in 0..<m.height { for x in 0..<m.width { m.refreshAutotile(x, y, z) } } }
    }

    // MARK: database

    static func buildDatabase(_ p: Project, title: String) {
        var s = SystemData()
        s.gameTitle = title
        s.switches = ["", "Talked to Elder", "Spirit Defeated"] + Array(repeating: "", count: 18)
        s.variables = ["", "Times Greeted", "Coins Donated", "Your Guess", "Answer"] + Array(repeating: "", count: 16)
        s.elements = ["", "Physical", "Fire", "Thunder", "Ice"]
        s.skillTypes = ["", "Magic", "Special"]
        s.weaponTypes = ["", "Dagger", "Sword"]
        s.armorTypes = ["", "General Armor", "Magic Armor"]
        s.sounds = DefaultAudio.systemSoundNames.map { AudioFile($0, volume: 80) }
        s.titleBgm = AudioFile("Title"); s.battleBgm = AudioFile("Battle"); s.victoryMe = AudioFile("Victory")
        s.defeatMe = AudioFile("Defeat"); s.gameoverMe = AudioFile("Gameover")
        s.boat = VehicleData(characterName: "Vehicle", characterIndex: 0); s.boat.bgm = AudioFile("Ship"); s.boat.startMapId = 1; s.boat.startX = 7; s.boat.startY = 13
        s.ship = VehicleData(characterName: "Vehicle", characterIndex: 1); s.ship.bgm = AudioFile("Ship"); s.ship.startMapId = 3; s.ship.startX = 22; s.ship.startY = 14
        s.airship = VehicleData(characterName: "Vehicle", characterIndex: 3); s.airship.bgm = AudioFile("Ship"); s.airship.startMapId = 3; s.airship.startX = 31; s.airship.startY = 17
        s.battleback1Name = "Grassland"; s.battleback2Name = "Grassland"
        s.partyMembers = [1]
        s.optSideView = true
        p.system = s
        p.animations = DefaultArt.animations()
        p.tilesets = [nil, DefaultArt.tileset()]

        // States (1 = death, 2 = guard, as MZ expects)
        var ko = StateData(id: 1, name: "Knockout"); ko.restriction = 4; ko.priority = 100; ko.iconIndex = A.iconKnockout; ko.motion = 3
        ko.message1 = "%1 has fallen!"; ko.message2 = "%1 is defeated!"; ko.message4 = "%1 revives!"
        var guardS = StateData(id: 2, name: "Guard"); guardS.autoRemovalTiming = 2; guardS.removeAtBattleEnd = true; guardS.priority = 0
        guardS.traits = [Trait(Trait.specialFlag, 1, 0)]; guardS.iconIndex = A.iconGuard
        var poison = StateData(id: 3, name: "Poison"); poison.iconIndex = A.iconPoison; poison.priority = 50
        poison.traits = [Trait(Trait.xparam, 7, -0.1)]; poison.message1 = "%1 is poisoned!"; poison.message2 = "%1 is poisoned!"; poison.message4 = "%1 is no longer poisoned."
        poison.removeByWalking = true; poison.stepsToRemove = 60; poison.motion = 1; poison.overlay = 1
        var sleep = StateData(id: 4, name: "Sleep"); sleep.iconIndex = A.iconSleep; sleep.restriction = 4; sleep.priority = 70
        sleep.autoRemovalTiming = 2; sleep.minTurns = 2; sleep.maxTurns = 4; sleep.removeByDamage = true; sleep.removeAtBattleEnd = true
        sleep.motion = 2; sleep.overlay = 7
        sleep.traits = [Trait(Trait.xparam, 1, -1)]; sleep.message1 = "%1 falls asleep!"; sleep.message2 = "%1 falls asleep!"; sleep.message4 = "%1 wakes up."
        var blind = StateData(id: 5, name: "Blind"); blind.iconIndex = A.iconBlind; blind.autoRemovalTiming = 2; blind.minTurns = 3; blind.maxTurns = 5
        blind.motion = 1; blind.overlay = 2
        blind.removeAtBattleEnd = true; blind.traits = [Trait(Trait.xparam, 0, -0.5)]; blind.message1 = "%1 is blinded!"; blind.message2 = "%1 is blinded!"; blind.message4 = "%1 can see again."
        p.states = [nil, ko, guardS, poison, sleep, blind]

        // Skills
        func skill(_ id: Int, _ name: String, _ desc: String, stype: Int, mp: Int = 0, tp: Int = 0, scope: Int, occasion: Int = 1,
                   hit: Int, type: Int, formula: String, element: Int = 0, effects: [Effect] = [], msg: String = "%1 casts %2!", icon: Int = 0, repeats: Int = 1, anim: Int = 0) -> Skill {
            var k = Skill(id: id, name: name); k.description = desc; k.stypeId = stype; k.mpCost = mp; k.tpCost = tp; k.scope = scope; k.animationId = anim
            k.occasion = occasion; k.hitType = hit; k.damage = Damage(type: type, formula: formula, elementId: element, critical: hit == 1)
            k.effects = effects; k.message1 = msg; k.iconIndex = icon; k.repeats = repeats
            return k
        }
        var attack = skill(1, "Attack", "Basic attack.", stype: 0, scope: 1, hit: 1, type: 1, formula: "a.atk * 4 - b.def * 2", element: -1,
                           effects: [Effect(Effect.addState, 0, 1)], msg: "%1 attacks!", icon: A.iconSword, anim: -1)
        attack.tpGain = 5
        var guardK = skill(2, "Guard", "Halves damage this turn.", stype: 0, scope: 11, hit: 0, type: 0, formula: "0",
                           effects: [Effect(Effect.addState, 2, 1)], msg: "%1 guards.", icon: A.iconGuard)
        guardK.speed = 2000; guardK.tpGain = 10
        p.skills = [nil, attack, guardK,
            skill(3, "Fire", "Fire damage to one enemy.", stype: 1, mp: 5, scope: 1, hit: 2, type: 1, formula: "100 + a.mat * 2 - b.mdf * 2", element: 2, icon: A.iconFire, anim: 3),
            skill(4, "Heal", "Restores HP of one ally.", stype: 1, mp: 5, scope: 7, occasion: 0, hit: 0, type: 3, formula: "200 + a.mat", icon: A.iconHeal, anim: 6),
            skill(5, "Double Slash", "Two quick strikes.", stype: 2, tp: 25, scope: 1, hit: 1, type: 1, formula: "a.atk * 4 - b.def * 2", element: -1, msg: "%1 uses %2!", icon: A.iconSlash, repeats: 2, anim: -1),
            skill(6, "Spark", "Lightning on one target.", stype: 1, mp: 6, scope: 1, hit: 2, type: 1, formula: "80 + a.mat * 2 - b.mdf * 2", element: 3, icon: A.iconThunder, anim: 4),
            skill(7, "Venom Bite", "Bite that may poison.", stype: 2, scope: 1, hit: 1, type: 1, formula: "a.atk * 4 - b.def * 2",
                  effects: [Effect(Effect.addState, 3, 0.5)], msg: "%1 bites!", icon: A.iconPoison, anim: 7),
            skill(8, "Lullaby", "Puts enemies to sleep.", stype: 1, mp: 4, scope: 2, hit: 2, type: 0, formula: "0",
                  effects: [Effect(Effect.addState, 4, 0.4)], msg: "%1 sings a lullaby!", icon: A.iconSleep, anim: 8),
            skill(9, "Blizzard", "Ice damage to all enemies.", stype: 1, mp: 10, scope: 2, hit: 2, type: 1, formula: "120 + a.mat * 2 - b.mdf * 2", element: 4, icon: A.iconIce, anim: 5),
            skill(10, "Cure", "Removes poison and blindness.", stype: 1, mp: 4, scope: 7, occasion: 0, hit: 0, type: 0, formula: "0",
                  effects: [Effect(Effect.removeState, 3, 1), Effect(Effect.removeState, 5, 1)], icon: A.iconHeal, anim: 6),
            skill(11, "Regrowth", "The spirit heals itself.", stype: 1, mp: 10, scope: 11, hit: 0, type: 3, formula: "300", msg: "%1 regrows its bark!", icon: A.iconHeal, anim: 12),
            skill(12, "Dust Cloud", "Blinds all enemies.", stype: 2, scope: 2, hit: 2, type: 0, formula: "0",
                  effects: [Effect(Effect.addState, 5, 0.6)], msg: "%1 kicks up dust!", icon: A.iconBlind, anim: 9),
        ]

        // Classes
        var warrior = ClassData(id: 1, name: "Warrior", base: [420, 30, 24, 22, 10, 14, 20, 18], growth: [44, 3, 3, 3, 1, 2, 2, 2])
        warrior.learnings = [Learning(level: 1, skillId: 5)]
        warrior.traits += [Trait(Trait.stypeAdd, 2, 0)]
        var mage = ClassData(id: 2, name: "Mage", base: [300, 90, 12, 12, 28, 24, 22, 20], growth: [30, 9, 1, 1, 3, 3, 2, 2])
        mage.learnings = [Learning(level: 1, skillId: 3), Learning(level: 1, skillId: 4), Learning(level: 3, skillId: 10), Learning(level: 5, skillId: 9)]
        mage.traits = mage.traits.filter { !($0.code == Trait.equipWtype && $0.dataId == 2) } + [Trait(Trait.stypeAdd, 1, 0)]
        p.classes = [nil, warrior, mage]

        var arya = Actor(id: 1, name: "Arya", characterName: "Actor1", characterIndex: 0)
        arya.nickname = "The Wanderer"; arya.classId = 1; arya.equips = [1, 3, 0, 1, 0]; arya.battlerName = "Actor1_1"
        arya.profile = "A traveller who came to Kampung Lakon on foot."
        var sekar = Actor(id: 2, name: "Sekar", characterName: "Actor1", characterIndex: 1)
        sekar.nickname = "Village Healer"; sekar.classId = 2; sekar.equips = [2, 0, 0, 2, 0]; sekar.battlerName = "Actor1_2"
        sekar.profile = "The elder's granddaughter. Knows the old songs."
        p.actors = [nil, arya, sekar]

        // Items
        func item(_ id: Int, _ name: String, _ desc: String, price: Int, icon: Int, scope: Int = 7, occasion: Int = 0, effects: [Effect] = [], damage: Damage = Damage(), itype: Int = 1, consumable: Bool = true, anim: Int = 6) -> Item {
            var i = Item(id: id, name: name, description: desc, price: price); i.iconIndex = icon; i.scope = scope; i.occasion = occasion; i.animationId = anim
            i.effects = effects; i.damage = damage; i.itypeId = itype; i.consumable = consumable
            if damage.type > 0 && scope <= 6 { i.hitType = 2 }
            return i
        }
        p.items = [nil,
            item(1, "Potion", "Restores 500 HP.", price: 50, icon: A.iconPotion, effects: [Effect(Effect.recoverHp, 0, 0, 500)]),
            item(2, "Old Key", "Opens something, somewhere.", price: 0, icon: A.iconKey, scope: 0, occasion: 3, itype: 2, consumable: false),
            item(3, "Magic Water", "Restores 50 MP.", price: 120, icon: A.iconEther, effects: [Effect(Effect.recoverMp, 0, 0, 50)]),
            item(4, "Antidote", "Cures poison.", price: 30, icon: A.iconAntidote, effects: [Effect(Effect.removeState, 3, 1)]),
            item(5, "Fire Scroll", "Burns all enemies.", price: 150, icon: A.iconScroll, scope: 2, occasion: 1, damage: Damage(type: 1, formula: "150", elementId: 2), anim: 3),
        ]
        func weapon(_ id: Int, _ name: String, _ desc: String, wtype: Int, atk: Int, mat: Int = 0, price: Int, icon: Int) -> EquipItem {
            var w = EquipItem(id: id, name: name, etypeId: 1, params: [0, 0, atk, 0, mat, 0, 0, 0], price: price)
            w.animationId = wtype == 1 ? 1 : 2
            w.description = desc; w.wtypeId = wtype; w.iconIndex = icon; w.traits = [Trait(Trait.attackElement, 1, 0)]
            return w
        }
        p.weapons = [nil,
            weapon(1, "Bronze Sword", "A plain, honest blade.", wtype: 2, atk: 8, price: 100, icon: A.iconSword),
            weapon(2, "Oak Dagger", "Light; helps channel magic.", wtype: 1, atk: 5, mat: 4, price: 80, icon: A.iconDagger),
            weapon(3, "Steel Sword", "Forged in the next valley.", wtype: 2, atk: 18, price: 420, icon: A.iconSword),
        ]
        func armor(_ id: Int, _ name: String, _ desc: String, etype: Int, atype: Int, params: [Int], price: Int, icon: Int) -> EquipItem {
            var a = EquipItem(id: id, name: name, etypeId: etype, params: params, price: price)
            a.description = desc; a.atypeId = atype; a.iconIndex = icon
            return a
        }
        p.armors = [nil,
            armor(1, "Leather Vest", "Sturdy travelling clothes.", etype: 4, atype: 1, params: [0, 0, 0, 6, 0, 0, 0, 0], price: 80, icon: A.iconVest),
            armor(2, "Healer's Robe", "Woven with protective charms.", etype: 4, atype: 2, params: [0, 10, 0, 3, 0, 6, 0, 0], price: 90, icon: A.iconRobe),
            armor(3, "Wooden Shield", "Blocks a blow or two.", etype: 2, atype: 1, params: [0, 0, 0, 4, 0, 0, 0, 0], price: 60, icon: A.iconShield),
            armor(4, "Bandana", "Keeps sweat out of your eyes.", etype: 3, atype: 1, params: [0, 0, 0, 2, 0, 1, 0, 0], price: 40, icon: A.iconBandana),
            armor(5, "Lucky Charm", "A spirit's blessing. Luck +15.", etype: 5, atype: 1, params: [0, 0, 0, 0, 0, 0, 0, 15], price: 600, icon: A.iconCharm),
        ]

        // Enemies
        func enemy(_ id: Int, _ name: String, _ battler: String, _ params: [Int], exp: Int, gold: Int, actions: [EnemyAction], drops: [DropItem] = [], weak: Int? = nil) -> Enemy {
            var e = Enemy(id: id, name: name, battlerName: battler, params: params, exp: exp, gold: gold)
            e.actions = actions; e.dropItems = drops
            if let w = weak { e.traits.append(Trait(Trait.elementRate, w, 2)) }
            return e
        }
        var regrow = EnemyAction(skillId: 11, rating: 7); regrow.conditionType = 2; regrow.conditionParam1 = 0; regrow.conditionParam2 = 0.4
        p.enemies = [nil,
            enemy(1, "Slime", "Slime", [140, 0, 22, 10, 10, 10, 12, 10], exp: 12, gold: 10, actions: [EnemyAction(skillId: 1)], drops: [DropItem(kind: 1, dataId: 1, denominator: 3)], weak: 2),
            enemy(2, "Bat", "Bat", [100, 20, 24, 8, 14, 10, 32, 10], exp: 15, gold: 12, actions: [EnemyAction(skillId: 1), EnemyAction(skillId: 8, rating: 3)], weak: 3),
            enemy(3, "Ular", "Snake", [170, 0, 28, 14, 10, 12, 18, 12], exp: 22, gold: 18, actions: [EnemyAction(skillId: 1), EnemyAction(skillId: 7, rating: 4)], drops: [DropItem(kind: 1, dataId: 4, denominator: 2)], weak: 4),
            enemy(4, "Forest Spirit", "Forest_Spirit", [1200, 200, 36, 26, 38, 30, 24, 20], exp: 260, gold: 400,
                  actions: [EnemyAction(skillId: 1), EnemyAction(skillId: 6, rating: 5), EnemyAction(skillId: 12, rating: 3), regrow],
                  drops: [DropItem(kind: 3, dataId: 5, denominator: 1)], weak: 2),
        ]
        var bossTroop = Troop(id: 4, name: "Forest Spirit", members: [TroopMember(enemyId: 4, x: 280, y: 430)])
        var enraged = TroopPage()
        enraged.conditions.enemyValid = true; enraged.conditions.enemyIndex = 0; enraged.conditions.enemyHp = 50
        enraged.list = [EventCommand(code: 337, indent: 0, parameters: [0, 12, false]), Cmd.shake(power: 6, speed: 6, duration: 30), Cmd.flash([255, 120, 60, 170], duration: 30)]
            + Cmd.text(["The Forest Spirit's eyes blaze green!"]) + [.end(0)]
        var opening = TroopPage()
        opening.conditions.turnValid = true; opening.conditions.turnA = 0
        opening.list = Cmd.text(["\"Who disturbs the grove?\""], speaker: "Forest Spirit") + [.end(0)]
        bossTroop.pages = [opening, enraged]
        p.troops = [nil,
            Troop(id: 1, name: "Slime x2", members: [TroopMember(enemyId: 1, x: 200, y: 330), TroopMember(enemyId: 1, x: 340, y: 420)]),
            Troop(id: 2, name: "Bat, Slime", members: [TroopMember(enemyId: 2, x: 210, y: 300), TroopMember(enemyId: 1, x: 360, y: 420)]),
            Troop(id: 3, name: "Ular x2", members: [TroopMember(enemyId: 3, x: 190, y: 340), TroopMember(enemyId: 3, x: 350, y: 430)]),
            bossTroop,
        ]

        p.commonEvents = [nil, CommonEvent(id: 1, name: "Refreshed")]
        p.commonEvents[1]!.list = [Cmd.playSe("Recovery")] + Cmd.text(["\\N[1] feels refreshed!"]) + [.end(0)]
    }

    // MARK: event helpers

    static func page(_ image: EventImage, trigger: Trigger = .actionButton, priority: Priority = .same, move: MoveType = .fixed,
                     _ list: [EventCommand], conditions: (inout PageConditions) -> Void = { _ in }) -> EventPage {
        var pg = EventPage()
        pg.image = image; pg.trigger = trigger.rawValue; pg.priorityType = priority.rawValue
        pg.moveType = move.rawValue; pg.list = list + [.end(0)]
        conditions(&pg.conditions)
        return pg
    }

    final class EventList {
        var events: [MapEvent?] = [nil]
        @discardableResult
        func add(_ name: String, _ x: Int, _ y: Int, _ pages: [EventPage]) -> Int {
            var e = MapEvent(id: events.count, x: x, y: y)
            e.name = name; e.pages = pages
            events.append(e)
            return e.id
        }
    }

    // MARK: village

    static func buildVillage(_ p: Project) {
        let id = p.createMap(name: "Village", width: 24, height: 18, fill: A.a2(A.grass))
        var m = p.maps[id]!
        m.displayName = "Kampung Lakon"
        m.autoplayBgm = true; m.bgm = AudioFile("Village", volume: 80)
        // Paths (east road leads out to the world map)
        for x in 2..<24 { m.place(A.a2(A.dirt), x, 10); m.place(A.a2(A.dirt), x, 11) }
        for y in 6..<17 { m.place(A.a2(A.dirt), 11, y); m.place(A.a2(A.dirt), 12, y) }
        // Pond (with a little boat)
        for y in 12..<16 { for x in 3..<8 where !(x == 3 && y == 15) && !(x == 7 && y == 12) { m.place(A.a2(A.water), x, y) } }
        // Flowers, hedge
        for x in 15..<20 { m.place(A.a2(A.flowers), x, 13); m.place(A.a2(A.flowers), x, 14) }
        for x in 14..<21 { m.place(A.a2(A.hedge), x, 16) }
        // Border trees
        for x in stride(from: 0, to: 24, by: 2) {
            if x != 12 { m.place(A.bTreeTop, x, 0); m.place(A.bTreeTrunk, x, 1) }
            m.place(A.bTreeTop, x, 16); m.place(A.bTreeTrunk, x, 17)
        }
        for y in stride(from: 3, to: 16, by: 2) where y != 11 {
            m.place(A.bTreeTop, 0, y - 1); m.place(A.bTreeTrunk, 0, y)
            if y != 9 { m.place(A.bTreeTop, 23, y - 1); m.place(A.bTreeTrunk, 23, y) }
        }
        // House
        for x in 8..<15 {
            m.place(A.a5(A.a5RoofRed), x, 2); m.place(A.a5(A.a5RoofRed), x, 3)
            m.place(A.a5(x == 9 || x == 13 ? A.a5Window : A.a5Wall), x, 4)
            m.place(A.a5(A.a5Wall), x, 5)
        }
        m.place(A.a5(A.a5Cobble), 11, 5)
        m.place(A.bDoor, 11, 5)
        // Market stall: counter at row 8, merchant behind it.
        for x in 2..<6 { m.place(A.a5(A.a5Counter), x, 8) }
        m.place(A.bTent, 2, 6)
        // Props
        m.place(A.bWell, 16, 7); m.place(A.bBarrel, 7, 6); m.place(A.bCrate, 6, 6)
        m.place(A.bRock, 19, 4); m.place(A.bBush, 4, 4); m.place(A.bSign, 13, 9)
        m.place(A.bLampTop, 9, 8); m.place(A.bLampPost, 9, 9)
        for x in 15..<21 { m.place(A.bFence, x, 12) }
        fixShapes(&m)

        let ev = EventList()
        let elderTalk = [Cmd.balloon(character: 0, 1)]
            + Cmd.text(["Welcome to Kampung Lakon, \\N[1].", "This village was built entirely in a Mac app."], speaker: "Elder")
            + [Cmd.variable(1, op: 1, constant: 1)]
            + Cmd.choices([
                ("Tell me more", Cmd.text(["Every event is a list of commands —", "like this one: Show Choices, then a branch."], speaker: "Elder")),
                ("Any work?", Cmd.text(["A spirit has gone wild on the island east", "of here. Take the ship from the dock.",
                                        "My granddaughter Sekar is in the house —", "she can help you."], speaker: "Elder") + [Cmd.switches(1, true)]),
                ("Goodbye", Cmd.text(["Safe travels."], speaker: "Elder")),
            ], cancel: 2)
        let elderAgain = Cmd.text(["You've greeted me \\V[1] times now."], speaker: "Elder") + [Cmd.variable(1, op: 1, constant: 1)]
            + Cmd.branch(Cmd.ifSwitch(2), then: Cmd.text(["You calmed the Forest Spirit! Thank you."], speaker: "Elder"),
                         else: Cmd.text(["The ship waits at the eastern dock."], speaker: "Elder"))
        ev.add("Elder", 10, 7, [
            page(EventImage(characterName: "People1", characterIndex: 0), elderTalk),
            page(EventImage(characterName: "People1", characterIndex: 0), elderAgain) { $0.switch1Valid = true; $0.switch1Id = 1 },
        ])

        var closed = page(EventImage(characterName: "!Objects", characterIndex: 0, direction: 2),
                          [Cmd.playSe("Chest"), Cmd.moveRoute(character: 0, [(36, []), (17, []), (15, [3]), (18, []), (15, [3]), (19, []), (35, [])])]
                          + [Cmd.item(2, 1), Cmd.gold(120), Cmd.playMe("Fanfare")] + Cmd.text(["Found an Old Key and 120 \\G!"]) + [Cmd.selfSwitch("A", true)])
        closed.directionFix = true
        var opened = page(EventImage(characterName: "!Objects", characterIndex: 0, direction: 8), Cmd.text(["The chest is empty."])) {
            $0.selfSwitchValid = true; $0.selfSwitchCh = "A"
        }
        opened.directionFix = true
        ev.add("Chest", 8, 14, [closed, opened])

        var villager = page(EventImage(characterName: "People1", characterIndex: 1), move: .random,
            Cmd.branch(Cmd.ifGold(100),
                       then: Cmd.text(["You look rich! Spare 30 \\G for the well?"], speaker: "Sari")
                           + Cmd.choices([("Sure", [Cmd.gold(-30), Cmd.variable(2, op: 1, constant: 30)] + Cmd.text(["Thank you! Donated so far: \\V[2] \\G."], speaker: "Sari")),
                                          ("No", Cmd.text(["Fair enough."], speaker: "Sari"))], cancel: 1),
                       else: Cmd.text(["Lovely weather today."], speaker: "Sari")))
        villager.moveFrequency = 3
        ev.add("Sari", 16, 9, [villager])

        ev.add("Sign", 13, 9, [page(EventImage(), priority: .same, Cmd.text(["↑ Elder's House   ← Market   → Road east"]))])
        ev.add("Door", 11, 5, [page(EventImage(), trigger: .playerTouch, priority: .below, [Cmd.playSe("Door"), Cmd.transfer(map: 2, x: 6, y: 8, direction: 8)])])

        // Intro: picture banner, name input, controls.
        ev.add("Intro", 1, 16, [
            page(EventImage(), trigger: .autorun, priority: .below,
                 [Cmd.showPicture(1, "Banner", x: 408, y: 150, scale: 80, opacity: 0),
                  Cmd.movePicture(1, x: 408, y: 170, scale: 100, opacity: 255, duration: 40, easing: 2)]
                 + Cmd.text(["Welcome to Kampung Lakon!", "Before we begin — what's your name?"])
                 + [Cmd.nameInput(actor: 1, maxLength: 8),
                    Cmd.movePicture(1, x: 408, y: 140, scale: 100, opacity: 0, duration: 30), Cmd.erasePicture(1)]
                 + Cmd.text(["Nice to meet you, \\N[1].", "Arrows move · Z talks · X opens the menu · Shift dashes."])
                 + [Cmd.selfSwitch("A", true)]),
            page(EventImage(), priority: .below, []) { $0.selfSwitchValid = true; $0.selfSwitchCh = "A" },
        ])

        // Shopkeeper behind the counter: talk across it.
        ev.add("Merchant", 3, 7, [page(EventImage(characterName: "People1", characterIndex: 3),
            Cmd.text(["Fresh goods from the coast!"], speaker: "Merchant")
            + Cmd.shop([(0, 1), (0, 3), (0, 4), (0, 5), (1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3), (2, 4), (2, 5)]))])

        // Inn: pay, fade, recover, ME.
        ev.add("Innkeeper", 18, 5, [page(EventImage(characterName: "People1", characterIndex: 5),
            Cmd.text(["A night's rest is 20 \\G. Stay?"], speaker: "Innkeeper")
            + Cmd.choices([
                ("Stay", Cmd.branch(Cmd.ifGold(20),
                                    then: [Cmd.gold(-20), Cmd.fadeOut(), Cmd.playMe("Inn"), Cmd.recoverAll(), Cmd.wait(150), Cmd.fadeIn(), Cmd.showAnimation(character: -1, 11)]
                                        + Cmd.text(["Good morning! Everyone is fully rested."], speaker: "Innkeeper"),
                                    else: Cmd.text(["Ah… you're short on coin."], speaker: "Innkeeper"))),
                ("Leave", Cmd.text(["Come back anytime."], speaker: "Innkeeper")),
            ], cancel: 1))])

        // Guessing game: Input Number + random variable + compare.
        ev.add("Pak Tebak", 21, 5, [page(EventImage(characterName: "People1", characterIndex: 6), move: .fixed,
            Cmd.text(["I'm thinking of a number from 1 to 9.", "Guess it and win 50 \\G!"], speaker: "Pak Tebak")
            + [Cmd.numberInput(variable: 3, digits: 1), Cmd.randomVariable(4, 1, 9)]
            + Cmd.branch([1, 3, 1, 4, 0],
                         then: [Cmd.playMe("Fanfare"), Cmd.gold(50)] + Cmd.text(["\\V[4]! You got it! Take 50 \\G."], speaker: "Pak Tebak"),
                         else: Cmd.text(["Nope, it was \\V[4]. Try again!"], speaker: "Pak Tebak")))])

        // Weather off when you come back from the rainy world map.
        ev.add("Clear Sky", 1, 1, [page(EventImage(), trigger: .parallel, priority: .below,
            [Cmd.weather("none", power: 0, duration: 60), Cmd.fadeOutBgs(2), Cmd.eraseEvent()])])

        // North gap in the trees → Sky Ledge (parallax demo).
        ev.add("To Sky Ledge", 12, 0, [page(EventImage(), trigger: .playerTouch, priority: .below, [Cmd.playSe("Wind"), Cmd.transfer(map: 4, x: 8, y: 11, direction: 8)])])

        // Road east → world map.
        for y in [10, 11] {
            ev.add("To World", 23, y, [page(EventImage(), trigger: .playerTouch, priority: .below, [Cmd.transfer(map: 3, x: 8, y: 11, direction: 6)])])
        }
        m.events = ev.events
        p.maps[id] = m
    }

    static func buildHouse(_ p: Project) {
        let id = p.createMap(name: "Elder's House", width: 13, height: 10, fill: A.a2(A.woodFloor))
        var m = p.maps[id]!
        m.autoplayBgm = true; m.bgm = AudioFile("Village", volume: 60)
        for x in 0..<13 {
            m.place(A.a5(A.a5WallDark), x, 0); m.place(A.a5(A.a5WallDark), x, 1)
            m.place(A.a5(A.a5Void), x, 9)
        }
        for y in 0..<10 { m.place(A.a5(A.a5Void), 0, y); m.place(A.a5(A.a5Void), 12, y) }
        m.place(A.a2(A.woodFloor), 6, 9)
        for y in 4..<7 { for x in 4..<9 { m.place(A.a2(A.carpet), x, y) } }
        m.place(A.bShelf, 2, 1); m.place(A.bShelf, 3, 1); m.place(A.bBed, 10, 2); m.place(A.bPlant, 1, 2)
        m.place(A.bTable, 6, 4); m.place(A.bChair, 5, 4); m.place(A.bPot, 10, 7); m.place(A.bRug, 6, 8)
        fixShapes(&m)

        let ev = EventList()
        ev.add("Exit", 6, 9, [page(EventImage(), trigger: .playerTouch, priority: .below, [Cmd.playSe("Door"), Cmd.transfer(map: 1, x: 11, y: 6, direction: 2)])])
        ev.add("Bayu", 3, 5, [
            page(EventImage(characterName: "People1", characterIndex: 4),
                 Cmd.text(["Grandpa told me to give you this."], speaker: "Bayu") + [Cmd.item(1, 2), Cmd.playMe("Fanfare")]
                 + Cmd.text(["Received 2 Potions!"]) + [Cmd.commonEvent(1), Cmd.selfSwitch("A", true)]),
            page(EventImage(characterName: "People1", characterIndex: 4), Cmd.text(["Grandpa says I should stop reading so much."], speaker: "Bayu")) {
                $0.selfSwitchValid = true
            },
        ])
        // Sekar joins the party (followers appear behind the leader).
        ev.add("Sekar", 9, 6, [
            page(EventImage(characterName: "Actor1", characterIndex: 1),
                 Cmd.branch(Cmd.ifSwitch(1),
                            then: Cmd.text(["Grandpa told me about the spirit.", "I'll come with you — I know a few spells."], speaker: "Sekar")
                                + [Cmd.addPartyMember(2), Cmd.playMe("Fanfare")] + Cmd.text(["Sekar joined the party!"]) + [Cmd.selfSwitch("A", true)],
                            else: Cmd.text(["Have you spoken with Grandpa outside?"], speaker: "Sekar"))),
            page(EventImage(), priority: .below, []) { $0.selfSwitchValid = true },
        ])
        m.events = ev.events
        p.maps[id] = m
    }

    // MARK: world map

    static func buildWorld(_ p: Project) {
        let id = p.createMap(name: "World", width: 40, height: 28, fill: A.a2(A.deepWater))
        var m = p.maps[id]!
        m.displayName = "Pulau Jawa Kecil"
        m.autoplayBgm = true; m.bgm = AudioFile("Field", volume: 80)
        m.encounterList = [Encounter(troopId: 1, weight: 10), Encounter(troopId: 2, weight: 8), Encounter(troopId: 3, weight: 5)]
        m.encounterStep = 22
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ f: (Int, Int) -> Void) {
            for y in 0..<m.height { for x in 0..<m.width {
                let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                if dx * dx + dy * dy <= 1 { f(x, y) }
            } }
        }
        // Shallow ring, then land.
        ellipse(11, 14, 11.5, 12.5) { x, y in m.place(A.a2(A.water), x, y) }
        ellipse(31, 14, 7.5, 8.5) { x, y in m.place(A.a2(A.water), x, y) }
        ellipse(11, 14, 10.2, 11.2) { x, y in m.place(A.a2(A.grass), x, y) }
        ellipse(31, 14, 6.2, 7.2) { x, y in m.place(A.a2(A.grass), x, y) }
        // Beaches on the east coast near the dock and around the island landing.
        for y in 11...17 { m.place(A.a2(A.sand), 20, y); m.place(A.a2(A.sand), 21, y) }
        ellipse(31, 18, 3, 2) { x, y in m.place(A.a2(A.sand), x, y) }
        // Tall grass (bush flag doubles encounter progress) and a poison swamp (damage floor).
        ellipse(8, 19, 4, 3) { x, y in m.place(A.a2(A.tallGrass), x, y) }
        ellipse(14, 6, 2.5, 1.6) { x, y in m.place(A.a2(A.swamp), x, y) }
        // Mountains and forest.
        for (x, y) in [(3, 8), (4, 7), (5, 6), (4, 9), (3, 11), (16, 18), (17, 19), (15, 20), (17, 21)] { m.place(A.bMountain, x, y) }
        for (x, y) in [(9, 4), (10, 5), (8, 5), (6, 15), (13, 9), (14, 10), (15, 11), (28, 10), (34, 10), (27, 15), (35, 15), (29, 9), (33, 9)] { m.place(A.bPine, x, y) }
        // Village marker, campfire, dock, shrine.
        m.place(A.bTent, 7, 11)
        m.place(A.bCampfire, 13, 15)
        m.place(A.bDock, 22, 13); m.place(A.bDock, 22, 15)
        m.place(A.bShrine, 31, 11)
        fixShapes(&m)

        let ev = EventList()
        ev.add("Village", 7, 11, [page(EventImage(), trigger: .playerTouch, priority: .below, [Cmd.transfer(map: 1, x: 22, y: 10, direction: 4)])])
        ev.add("Rain", 0, 0, [page(EventImage(), trigger: .parallel, priority: .below,
            [Cmd.weather("rain", power: 5, duration: 90), Cmd.playBgs("Rain", volume: 60), Cmd.eraseEvent()])])
        ev.add("Campfire", 13, 15, [page(EventImage(), priority: .same,
            Cmd.text(["A warm campfire. Rest a while?"])
            + Cmd.choices([("Rest", [Cmd.pluginCommand("LakonDemo", "restParty", args: ["message": "The fire crackles…"]), Cmd.flash([255, 200, 120, 160], duration: 30)]
                                   + Cmd.text(["HP and MP restored. (A plugin command did that.)"])),
                           ("Move on", [])], cancel: 1))])
        let bossWin = [Cmd.switches(2, true), Cmd.selfSwitch("A", true)] + Cmd.text(["The spirit's anger fades.", "The grove is quiet again."])
        ev.add("Shrine", 31, 12, [
            page(EventImage(characterName: "", characterIndex: 0),
                 Cmd.text(["A shrine hums with angry energy."]) + Cmd.choices([("Touch it", Cmd.battle(troop: 4, canEscape: false, canLose: true,
                                                                                            win: bossWin, lose: Cmd.text(["You wake at the shrine's foot, bruised."]))),
                                                                              ("Leave", [])], cancel: 1)),
            page(EventImage(), [Cmd.balloon(character: -1, 4)] + Cmd.text(["The shrine is peaceful now."])) { $0.selfSwitchValid = true },
        ])
        m.events = ev.events
        p.maps[id] = m
    }

    // MARK: sky ledge (parallax, Show Animation, Change Parallax)

    static func buildSkyLedge(_ p: Project) {
        let id = p.createMap(name: "Sky Ledge", width: 17, height: 13, fill: 0)
        var m = p.maps[id]!
        m.displayName = "Sky Ledge"
        m.parallaxName = "Sky"; m.parallaxLoopX = true; m.parallaxSx = -2
        m.autoplayBgs = true; m.bgs = AudioFile("Rain", volume: 25, pitch: 60)
        // A floating stone path: empty cells show the parallax and can't be walked on.
        for y in 4..<13 { m.place(A.a5(A.a5Cobble), 8, y) }
        for y in 3..<7 { for x in 4..<13 { m.place(A.a5(A.a5Cobble), x, y) } }
        m.place(A.bShrine, 8, 3); m.place(A.bLampTop, 5, 3); m.place(A.bLampPost, 5, 4); m.place(A.bLampTop, 11, 3); m.place(A.bLampPost, 11, 4)
        fixShapes(&m)
        let ev = EventList()
        ev.add("Back", 8, 12, [page(EventImage(), trigger: .playerTouch, priority: .below, [Cmd.transfer(map: 1, x: 12, y: 1, direction: 2)])])
        ev.add("Wind Spirit", 6, 5, [page(EventImage(characterName: "Actor1", characterIndex: 7),
            [Cmd.showAnimation(character: 0, 10)] + Cmd.text(["The wind carries the clouds past this ledge.", "Open the star chest and the sky turns to night."], speaker: "Wind Spirit")
            + [Cmd.showAnimation(character: -1, 11, wait: false)])])
        ev.add("Star Chest", 10, 5, [
            page(EventImage(characterName: "!Objects", characterIndex: 0, direction: 2),
                 [Cmd.playSe("Magic_Evasion"), Cmd.showAnimation(character: 0, 11), Cmd.changeParallax("!Starlit"),
                  Cmd.tint([-34, -34, 0, 34], duration: 30, wait: true)] + Cmd.text(["Stars spill out of the chest.", "The sky darkens into a field of stars."]) + [Cmd.selfSwitch("A", true)]),
            page(EventImage(characterName: "!Objects", characterIndex: 0, direction: 8),
                 [Cmd.playSe("Magic_Evasion"), Cmd.showAnimation(character: 0, 11), Cmd.changeParallax("Sky", loopX: true, sx: -2),
                  Cmd.tint([0, 0, 0, 0], duration: 30, wait: true)] + Cmd.text(["You close the chest. Daylight returns."]) + [Cmd.selfSwitch("A", false)]) { $0.selfSwitchValid = true },
        ])
        m.events = ev.events
        p.maps[id] = m
    }

    static func writeDemoPlugin(_ p: Project) throws {
        let dir = p.root.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let js = """
        /*:
         * @target Lakon
         * @plugindesc Demo plugin: a plugin command and a map hook, using the MZ-style API Lakon exposes.
         */
        (() => {
            const pluginName = "LakonDemo";
            PluginManager.registerCommand(pluginName, "restParty", function(args) {
                for (const actor of $gameParty.members()) actor.recoverAll();
                AudioManager.playSe({ name: "Recovery", volume: 90, pitch: 100, pan: 0 });
                console.log(args.message || "rested");
            });
            Lakon.on("mapStart", mapId => console.log("[LakonDemo] entered map " + mapId));
        })();
        """
        try js.write(to: dir.appendingPathComponent("LakonDemo.js"), atomically: true, encoding: .utf8)
        let list = #"[{"name":"LakonDemo","status":true,"description":"Demo plugin","parameters":{}}]"#
        try list.write(to: dir.appendingPathComponent("plugins.json"), atomically: true, encoding: .utf8)
    }
}
