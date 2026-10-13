import XCTest
@testable import LakonCore
@testable import LakonRender

/// Side-view battle, animations (MV cells + MZ timings) and parallax.
final class BattleAnimationTests: XCTestCase {
    static var sharedDir: URL!
    var world: GameWorld!

    override class func setUp() {
        sharedDir = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-anim-\(UUID().uuidString)")
        _ = try! SampleProject.create(at: sharedDir, title: "Anim")
    }
    override class func tearDown() { try? FileManager.default.removeItem(at: sharedDir) }

    override func setUpWithError() throws {
        world = GameWorld(project: try Project.load(from: Self.sharedDir), rng: SeededRandom(7))
        world.newGame()
        world.state.setSelfSwitch(1, 6, "A", true)
    }

    func testAnimationsRoundTripBothFormats() throws {
        let p = world.project
        XCTAssertEqual(p.animations.compactMap { $0 }.count, 12)
        let slash = try XCTUnwrap(p.animation(2))
        XCTAssertTrue(slash.isMV)
        XCTAssertEqual(slash.playFrames, 5 * 4 + 1, "Sprite_AnimationMV.setupDuration")
        XCTAssertEqual(slash.totalFrames(targets: 3), 8 + 2 * 12 + 21, "base delay 8, +12 per extra target")
        // An MZ (Effekseer) entry as MZ writes it.
        let json = #"[null,{"id":1,"displayType":0,"effectName":"CureOne1","flashTimings":[{"frame":10,"duration":20,"color":[0,255,0,102]}],"name":"Heal One 1","offsetX":0,"offsetY":0,"rotation":{"x":0,"y":0,"z":0},"scale":100,"soundTimings":[{"frame":1,"se":{"name":"Heal3","pan":0,"pitch":100,"volume":90}}],"speed":100}]"#
        let mz = try JSONDecoder().decode([AnimationData?].self, from: Data(json.utf8))[1]!
        XCTAssertFalse(mz.isMV)
        XCTAssertEqual(mz.soundTimings.first?.se.name, "Heal3")
        XCTAssertEqual(mz.playFrames, 40, "stand-in length dominates the 30-frame flash")
        let back = try JSONDecoder().decode(AnimationData.self, from: JSONEncoder().encode(mz))
        XCTAssertEqual(back, mz)
        XCTAssertNil(String(data: try JSONEncoder().encode(mz), encoding: .utf8)!.range(of: "\"frames\""), "MZ entries don't gain MV fields")
    }

    func testMVPlaybackFramesTimingsAndEnd() throws {
        let a = try XCTUnwrap(world.project.animation(3))   // Fire One: SE frame 0, target flash frame 2, screen flash frame 3
        let pb = AnimationPlayback(a, targets: [0], mirror: true, delay: 8)
        var sounds: [String] = [], frames = 0, sawTargetFlash = false, sawScreenFlash = false
        while pb.isPlaying && frames < 500 {
            sounds += pb.update().map(\.name); frames += 1
            if pb.flashColor[3] > 0 { sawTargetFlash = true }
            if pb.screenFlashColor[3] > 0 { sawScreenFlash = true }
            if frames == 9 { XCTAssertEqual(pb.cells.first?.pattern, 0); XCTAssertLessThan(pb.cells.first?.scaleX ?? 1, 0, "mirrored") }
        }
        XCTAssertEqual(frames, 8 + a.playFrames)
        XCTAssertEqual(sounds, ["Fire"])
        XCTAssertTrue(sawTargetFlash); XCTAssertTrue(sawScreenFlash)
        XCTAssertTrue(pb.cells.isEmpty)
    }

    func testSideViewBattleCuesMotionsAnimationsAndWaits() throws {
        XCTAssertTrue(world.project.system.optSideView)
        world.addActor(2)
        world.startBattle(troopId: 1, canEscape: true, canLose: true)
        let b = try XCTUnwrap(world.battle)
        for _ in 0..<200 { world.update(InputState()) }
        XCTAssertEqual(b.phase, .input)
        b.commandFight()
        XCTAssertEqual(b.members[0].actionState, "inputting")
        b.commandAttack(target: 0)
        XCTAssertEqual(b.members[0].actionState, "waiting")
        b.commandSkill(3, target: 1)                       // Sekar: Fire (magic → chant while waiting)
        let sekar = b.members[1]
        if b.phase == .input { XCTAssertTrue(sekar.isChanting) }
        var actingSeen = false
        for _ in 0..<900 where world.battle != nil && b.phase != .input {
            world.update(InputState(ok: world.message?.isTextComplete == true))
            if b.members.contains(where: \.isActing) { actingSeen = true }
        }
        XCTAssertTrue(actingSeen)
        let kinds = b.cues.map(\.kind)
        XCTAssertTrue(kinds.contains { if case .motion("swing") = $0 { return true }; return false }, "sword → swing")
        XCTAssertTrue(kinds.contains { if case .weapon(2) = $0 { return true }; return false }, "Weapons1 sword image")
        XCTAssertTrue(kinds.contains { if case .motion("spell") = $0 { return true }; return false })
        XCTAssertTrue(kinds.contains { if case .animation(2, _, 8) = $0 { return true }; return false }, "Bronze Sword's slash")
        XCTAssertTrue(kinds.contains { if case .animation(3, _, 8) = $0 { return true }; return false }, "Fire")
        // Results come after the animation: the first damage cue is at least one animation length after its animation.
        let animIdx = try XCTUnwrap(b.cues.firstIndex { if case .animation = $0.kind { return true }; return false })
        XCTAssertNotNil(b.cues[animIdx...].first { if case .damage = $0.kind { return true }; if case .miss = $0.kind { return true }; return false })
    }

    func testBattleIsDeterministicWithSeededRandom() throws {
        func play(_ seed: UInt64) throws -> [String] {
            let w = GameWorld(project: try Project.load(from: Self.sharedDir), rng: SeededRandom(seed))
            w.newGame(); w.state.setSelfSwitch(1, 6, "A", true)
            w.startBattle(troopId: 2, canEscape: false, canLose: true)
            var n = 0
            while let b = w.battle, n < 20000 {
                n += 1
                if b.phase == .input {
                    if b.waitingForPartyCommand { b.commandFight() } else if b.inputActor != nil { b.commandAttack(target: b.enemies.firstIndex { $0.isAlive } ?? 0) }
                }
                w.update(InputState(ok: w.message?.isTextComplete == true))
                if w.battle == nil { return b.log + ["\(w.actor(1)!.hp)"] }
            }
            return []
        }
        XCTAssertEqual(try play(99), try play(99))
    }

    func testShowAnimationWaitsForItsLength() throws {
        let anim = try XCTUnwrap(world.project.animation(11))
        world.mainInterpreter.setup([Cmd.showAnimation(character: -1, 11), Cmd.switches(5, true), .end(0)], eventId: 0)
        var frames = 0
        while !world.state.switchValue(5) && frames < 600 { world.update(InputState()); frames += 1 }
        XCTAssertEqual(world.player.animationSerial, 1)
        XCTAssertGreaterThanOrEqual(frames, anim.totalFrames(targets: 1))
        XCTAssertLessThanOrEqual(frames, anim.totalFrames(targets: 1) + 2)
    }

    func testParallaxSetupScrollChangeAndSave() throws {
        world.reserveTransfer(mapId: 4, x: 8, y: 11, direction: 8, fadeType: 1)
        for _ in 0..<3 { world.update(InputState()) }
        XCTAssertEqual(world.state.mapId, 4)
        XCTAssertEqual(world.state.parallax.name, "Sky")
        let before = world.state.parallax.autoX
        for _ in 0..<48 { world.update(InputState()) }
        XCTAssertEqual(world.state.parallax.autoX - before, 48 * -2.0 / 48 / 2, accuracy: 1e-9, "sx / tileWidth / 2 per frame")
        let (ox, _) = world.state.parallax.origin(displayX: 2, displayY: 0)
        XCTAssertEqual(ox, (2 + world.state.parallax.autoX) * 24, accuracy: 1e-9, "loop: half speed of the map")
        XCTAssertEqual(ParallaxState(map: { var m = GameMap(width: 1, height: 1); m.parallaxName = "!Starlit"; return m }()).origin(displayX: 3, displayY: 1).0, 144, "zero parallax moves with tiles")

        world.mainInterpreter.setup([Cmd.changeParallax("!Starlit"), .end(0)], eventId: 0)
        world.update(InputState())
        XCTAssertEqual(world.state.parallax.name, "!Starlit")
        XCTAssertFalse(world.state.parallax.loopX)
        XCTAssertEqual(world.state.parallax.autoX, 0, "turning the loop off resets it")

        let data = try JSONEncoder().encode(world.makeSave())
        let w2 = GameWorld(project: world.project, rng: SeededRandom(1))
        w2.load(try JSONDecoder().decode(GameState.self, from: data))
        XCTAssertEqual(w2.state.parallax.name, "!Starlit", "Change Parallax survives save/load")
        // Saves from before parallax existed fall back to the map's own parallax.
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy["parallax"] = nil
        w2.load(try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: legacy)))
        XCTAssertEqual(w2.state.parallax.name, "Sky")
    }

    func testSVActorSpriteStepsForwardAndSwings() throws {
        world.startBattle(troopId: 1, canEscape: true, canLose: true)
        let b = try XCTUnwrap(world.battle)
        let s = SVActorSprite(index: 0)
        s.setActor(b.members[0])
        XCTAssertEqual(s.x, 600 + 300, "enters from the right")
        for _ in 0..<40 { s.update(escaped: false, battleEnded: false) }
        XCTAssertEqual(s.x, 600, accuracy: 0.01)
        for _ in 0..<200 { world.update(InputState()) }
        b.commandFight()
        for _ in 0..<13 { s.update(escaped: false, battleEnded: false) }
        XCTAssertEqual(s.x, 552, accuracy: 0.01, "stepForward −48 over 12 frames while inputting")
        XCTAssertEqual(s.motion, "walk")
        s.requestMotion("swing")
        XCTAssertEqual(s.frame.col, (7 / 6) * 3); XCTAssertEqual(s.frame.row, 7 % 6)
    }
}
