import XCTest
@testable import LakonCore
@testable import LakonRender

/// Battle, shop, script/plugins, vehicles, pictures/screen, audio queue, message inputs.
final class SystemsTests: XCTestCase {
    static var sharedDir: URL!
    var world: GameWorld!

    override class func setUp() {
        sharedDir = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-sys-\(UUID().uuidString)")
        _ = try! SampleProject.create(at: sharedDir, title: "Systems")
    }
    override class func tearDown() { try? FileManager.default.removeItem(at: sharedDir) }

    override func setUpWithError() throws {
        let p = try Project.load(from: Self.sharedDir)
        world = GameWorld(project: p, rng: SeededRandom(42))
        world.newGame()
        world.state.setSelfSwitch(1, 6, "A", true)   // skip the intro autorun
    }

    func run(_ n: Int, _ i: InputState = InputState()) { for _ in 0..<n { world.update(i) } }
    func drain(_ max: Int = 4000) {
        for _ in 0..<max {
            if world.battle == nil && world.message == nil && !world.isEventRunning { return }
            world.update(InputState(ok: world.message?.isTextComplete == true))
            world.update(InputState())
        }
    }

    // MARK: battle

    func testBattleMathMatchesMZFormula() throws {
        let arya = try XCTUnwrap(world.actor(1))
        // Warrior Lv1: atk 24 + Bronze Sword 8 = 32, def 22 + vest 6 + shield 4 = 32.
        XCTAssertEqual(arya.atk, 32)
        XCTAssertEqual(arya.def, 32)
        XCTAssertEqual(arya.mhp, 420)
        XCTAssertEqual(arya.hp, 420)
        XCTAssertEqual(world.script.evalFormula("a.atk * 4 - b.def * 2", a: arya, b: arya), 64)
        XCTAssertEqual(arya.expForLevel(2), Int((30 * pow(1, 0.9 + 30.0 / 250) * 2 * 3 / (6 + 4 / 50 / 30.0) + 20).rounded()))
    }

    func testBattleWinGivesRewardsAndBranch() throws {
        world.state.gold = 0
        let list = Cmd.battle(troop: 1, canEscape: true, canLose: false, win: [Cmd.switches(10, true)], escape: [Cmd.switches(11, true)]) + [.end(0)]
        world.mainInterpreter.setup(list, eventId: 0)
        run(1)
        let b = try XCTUnwrap(world.battle)
        XCTAssertEqual(b.enemies.map(\.name), ["Slime A", "Slime B"])
        // Fight: attack enemy 0 every turn until the troop falls.
        var guardCount = 0
        while world.battle != nil && guardCount < 20000 {
            guardCount += 1
            if let bb = world.battle, bb.phase == .input {
                if bb.waitingForPartyCommand { bb.commandFight() }
                else if bb.inputActor != nil { bb.commandAttack(target: bb.enemies.firstIndex { $0.isAlive } ?? 0) }
            }
            world.update(InputState(ok: world.message?.isTextComplete == true))
        }
        XCTAssertNil(world.battle)
        XCTAssertEqual(b.outcome, .win)
        XCTAssertGreaterThan(world.state.gold, 0)
        XCTAssertGreaterThan(try XCTUnwrap(world.actor(1)).currentExp, 0)
        run(3)
        XCTAssertTrue(world.state.switchValue(10), "If Win branch ran")
        XCTAssertFalse(world.state.switchValue(11))
        XCTAssertTrue(b.log.joined().contains("victorious") || !b.log.isEmpty)
        XCTAssertTrue(world.audio.pending.contains { if case .playMe(let f) = $0 { return f.name == "Victory" }; return false })
    }

    func testEscapeAndGuardAndSkills() throws {
        world.addActor(2)
        world.startBattle(troopId: 3, canEscape: true, canLose: false)
        let b = try XCTUnwrap(world.battle)
        run(200)
        XCTAssertEqual(b.phase, .input)
        let sekar = try XCTUnwrap(world.actor(2))
        XCTAssertTrue(b.usableSkills(sekar).map(\.name).contains("Fire"))
        b.commandFight()
        b.commandGuard()                            // Arya guards
        let mp = sekar.mp
        b.commandSkill(3, target: 0)                // Sekar casts Fire
        run(600)
        XCTAssertEqual(sekar.mp, mp - 5)
        XCTAssertLessThan(b.enemies[0].hp, b.enemies[0].mhp, "Fire hit (Ular is weak to ice, normal to fire)")
    }

    func testDefeatWithCanLoseRevives() throws {
        let list = Cmd.battle(troop: 4, canEscape: false, canLose: true, lose: [Cmd.switches(12, true)]) + [.end(0)]
        world.mainInterpreter.setup(list, eventId: 0)
        run(1)
        let b = try XCTUnwrap(world.battle)
        for a in world.partyMembers { a.setHp(1) }
        b.enemies[0].paramPlusExtra[2] = 900       // boss hits very hard
        var n = 0
        while world.battle != nil && n < 20000 {
            n += 1
            if let bb = world.battle, bb.phase == .input {
                if bb.waitingForPartyCommand { bb.commandFight() } else if bb.inputActor != nil { bb.commandGuard() }
            }
            world.update(InputState(ok: world.message?.isTextComplete == true))
        }
        XCTAssertEqual(b.outcome, .lose)
        XCTAssertFalse(world.gameOver)
        run(3)
        XCTAssertTrue(world.state.switchValue(12))
        XCTAssertTrue(world.partyMembers.allSatisfy { $0.hp >= 1 })
    }

    func testRandomEncounterTriggers() {
        world.load({ var s = world.makeSave(); s.mapId = 3; s.playerX = 8; s.playerY = 13; return s }())
        var started = false
        for i in 0..<4000 {
            world.update(InputState(dir4: (i / 40) % 2 == 0 ? 2 : 8))
            if world.battle != nil { started = true; break }
        }
        XCTAssertTrue(started, "walking on the world map starts an encounter")
    }

    // MARK: shop, menu, equipment

    func testShopBuySellAndEquip() throws {
        world.state.gold = 1000
        let sword = ShopState.Good(kind: 1, id: 3, price: 420)
        XCTAssertEqual(ShopState.maxBuy(sword, world: world), 2)
        ShopState.buy(sword, qty: 1, world: world)
        XCTAssertEqual(world.state.gold, 580)
        XCTAssertEqual(world.state.count(kind: 2, id: 3), 1)
        let arya = try XCTUnwrap(world.actor(1))
        world.equip(actor: arya, slot: 0, itemId: 3)
        XCTAssertEqual(arya.atk, 24 + 18)
        XCTAssertEqual(world.state.count(kind: 2, id: 1), 1, "old sword back in the bag")
        ShopState.sell(kind: 1, id: 1, qty: 1, world: world)
        XCTAssertEqual(world.state.gold, 580 + 50)
        // Mage can't wear swords.
        world.addActor(2)
        let sekar = try XCTUnwrap(world.actor(2))
        XCTAssertFalse(sekar.canEquip(slot: 0, id: 3))
    }

    func testMenuItemAndSkillUse() throws {
        world.addActor(2)
        let arya = try XCTUnwrap(world.actor(1)), sekar = try XCTUnwrap(world.actor(2))
        arya.setHp(100)
        world.state.gain(kind: 1, id: 1, 1)
        XCTAssertTrue(world.useInMenu(itemId: 1, user: arya, target: arya))
        XCTAssertEqual(arya.hp, 420)
        XCTAssertEqual(world.state.count(kind: 1, id: 1), 0)
        XCTAssertFalse(world.useInMenu(itemId: 1, user: arya, target: arya), "none left")
        arya.setHp(50)
        XCTAssertTrue(world.useInMenu(skillId: 4, user: sekar, target: arya))
        XCTAssertGreaterThan(arya.hp, 50)
    }

    // MARK: scripts and plugins

    func testScriptCommandAndConditionAndPluginCommand() throws {
        let list = Cmd.script("$gameVariables.setValue(7, $gameParty.members().length * 10 + 5);\n$gameSwitches.setValue(15, true);")
            + Cmd.branch([12, "$gameVariables.value(7) === 15"], then: [Cmd.switches(16, true)])
            + [EventCommand(code: 122, indent: 0, parameters: [8, 8, 0, 4, "Math.max(3, 9)"])]
            + [Cmd.pluginCommand("LakonDemo", "restParty")] + [.end(0)]
        let arya = try XCTUnwrap(world.actor(1))
        arya.setHp(1)
        world.mainInterpreter.setup(list, eventId: 0)
        run(2)
        XCTAssertEqual(world.state.variable(7), 15)
        XCTAssertTrue(world.state.switchValue(15))
        XCTAssertTrue(world.state.switchValue(16))
        XCTAssertEqual(world.state.variable(8), 9)
        XCTAssertEqual(arya.hp, arya.mhp, "plugin command from plugins/LakonDemo.js healed the party")
        XCTAssertTrue(world.script.loadedPlugins.contains("LakonDemo"))
    }

    // MARK: vehicles

    func testShipBoardsAndSailsOnlyOnWater() throws {
        var s = world.makeSave(); s.mapId = 3; s.playerX = 21; s.playerY = 14; s.playerDirection = 6
        world.load(s)
        world.state.encounterEnabled = false
        run(2)
        world.update(InputState(ok: true)); run(40)
        XCTAssertEqual(world.state.vehicleType, 1, "on the ship")
        XCTAssertEqual(world.player.x, 22)
        run(1, InputState(dir4: 6)); run(12)
        XCTAssertEqual(world.player.x, 23, "sails east over water")
        let ship = world.vehicles[1]
        XCTAssertEqual(ship.x, world.player.x)
        world.update(InputState(ok: true)); run(10)
        XCTAssertEqual(world.state.vehicleType, 1, "water in front → stay aboard")
        run(1, InputState(dir4: 6)); run(12)
        world.update(InputState(ok: true)); run(30)
        XCTAssertEqual(world.state.vehicleType, -1, "island grass in front → disembark")
        XCTAssertEqual(world.player.x, 25)
        XCTAssertEqual(ship.x, 24, "ship stays moored")
    }

    // MARK: screen, pictures, audio, inputs

    func testPicturesTintWeatherAndAudioQueue() {
        let list = [Cmd.showPicture(1, "Banner", x: 100, y: 100, opacity: 0), Cmd.movePicture(1, x: 200, y: 100, opacity: 255, duration: 10),
                    Cmd.tint([-68, -68, 0, 68], duration: 10), Cmd.weather("snow", power: 6, duration: 0), Cmd.playBgm("Field"), Cmd.playSe("Coin"), .end(0)]
        world.mainInterpreter.setup(list, eventId: 0)
        run(30)
        let pic = world.screen.pictures[1]
        XCTAssertEqual(pic?.x ?? 0, 200, accuracy: 0.5)
        XCTAssertEqual(pic?.opacity ?? 0, 255, accuracy: 0.5)
        XCTAssertEqual(world.screen.tone[0], -68, accuracy: 0.5)
        XCTAssertEqual(world.screen.weatherType, "snow")
        let cmds = world.audio.drain()
        XCTAssertTrue(cmds.contains(.playBgm(AudioFile("Field"), position: 0)))
        XCTAssertTrue(cmds.contains(.playSe(AudioFile("Coin"))))
        // Pictures/screen persist through save/load.
        let data = try! JSONEncoder().encode(world.makeSave())
        let w2 = GameWorld(project: world.project)
        w2.load(try! JSONDecoder().decode(GameState.self, from: data))
        XCTAssertEqual(w2.screen.pictures[1]?.name, "Banner")
    }

    func testNumberInputAndNameInput() throws {
        world.mainInterpreter.setup(Cmd.text(["Pick"]) + [Cmd.numberInput(variable: 5, digits: 2), Cmd.nameInput(actor: 1), .end(0)], eventId: 0)
        run(1)
        world.update(InputState(ok: true))                 // finish text
        XCTAssertEqual(world.message?.numberDigits, 2)
        world.update(InputState(up: true)); world.update(InputState(right: true)); world.update(InputState(up: true)); world.update(InputState(up: true))
        world.update(InputState(ok: true))
        XCTAssertEqual(world.state.variable(5), 12)
        run(2)
        XCTAssertEqual(world.nameInput?.actorId, 1)
        world.actor(1)?.setName("Bimo"); world.nameInput = nil
        run(2)
        XCTAssertEqual(world.convertEscapes("\\N[1]"), "Bimo")
    }

    func testFollowersAndSaveRoundTripOfActors() throws {
        world.addActor(2)
        XCTAssertEqual(world.followers.count, 1)
        world.actor(2)?.changeLevel(5)
        let lv = world.actor(2)!.level
        let data = try JSONEncoder().encode(world.makeSave())
        let w2 = GameWorld(project: world.project)
        w2.load(try JSONDecoder().decode(GameState.self, from: data))
        XCTAssertEqual(w2.actor(2)?.level, lv)
        XCTAssertTrue(w2.actor(2)!.learnedSkills.contains(9), "Blizzard learned at level 5")
        XCTAssertEqual(w2.followers.count, 1)
    }
}
