import XCTest
@testable import LakonCore
@testable import LakonRender

final class TileTests: XCTestCase {
    func testFloorShapesCoverMZTable() {
        // Every neighbour combination must map to a real MZ shape, and together they must produce all 47 edge shapes.
        var seen = Set<Int>()
        for mask in 0..<256 {
            let same = (0..<8).map { mask & (1 << $0) != 0 }
            let s = TileID.floorShape(same: same)
            let q = TileID.floorTable[s]
            XCTAssertNotEqual(s, 47, "preview shape must not be produced")
            seen.insert(s)
            _ = q
        }
        XCTAssertEqual(seen, Set(0..<47))
        XCTAssertEqual(TileID.floorShape(same: Array(repeating: true, count: 8)), 0)
        XCTAssertEqual(TileID.floorShape(same: Array(repeating: false, count: 8)), 46)
    }

    func testTileIdLayoutMatchesMZ() {
        XCTAssertEqual(TileID.make(kind: 16, shape: 0), TileID.A2)
        XCTAssertTrue(TileID.isA2(DefaultArt.a2(DefaultArt.water)))
        var m = GameMap(width: 3, height: 3)
        m.setTile(2, 1, 4, 7)
        XCTAssertEqual(m.data[(4 * 3 + 1) * 3 + 2], 7, "index = (z * height + y) * width + x")
    }

    func testAutoLayeringAndAutotileRefresh() {
        var m = GameMap(width: 5, height: 5, fill: DefaultArt.a2(DefaultArt.grass))
        m.place(DefaultArt.a2(DefaultArt.water), 2, 2)
        XCTAssertEqual(TileID.shape(m.tileId(2, 2, 0)), 46, "isolated tile gets the all-edges shape")
        XCTAssertEqual(TileID.kind(m.tileId(2, 1, 0)), TileID.kind(DefaultArt.a2(DefaultArt.grass)))
        m.place(DefaultArt.bRock, 1, 1)
        XCTAssertEqual(m.tileId(1, 1, 2), DefaultArt.bRock, "B tiles go to z2")
        m.place(DefaultArt.bSign, 1, 1)
        XCTAssertEqual(m.tileId(1, 1, 3), DefaultArt.bSign, "second B tile goes to z3")
        m.eraseTop(1, 1)
        XCTAssertEqual(m.tileId(1, 1, 3), 0)
    }

    func testPassabilityFollowsMZCheckPassage() {
        let t = DefaultArt.tileset()
        var m = GameMap(width: 4, height: 4, fill: DefaultArt.a2(DefaultArt.grass))
        m.place(DefaultArt.a2(DefaultArt.water), 1, 1)
        m.place(DefaultArt.bTreeTop, 2, 2)
        XCTAssertTrue(m.isPassable(0, 0, 6, tileset: t))
        XCTAssertFalse(m.isPassable(1, 1, 2, tileset: t), "water blocks")
        XCTAssertTrue(m.isPassable(2, 2, 2, tileset: t), "☆ tile is ignored, grass below decides")
    }

    func testCharacterFrameLayout() {
        let sheet = DefaultArt.makePeople()
        XCTAssertEqual(CharacterSheet.frame(sheet: sheet, name: "People1", index: 5, direction: 6, pattern: 1),
                       CGRect(x: (3 + 1) * 48, y: (4 + 2) * 48, width: 48, height: 48))
    }
}

final class WorldTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-test-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func makeWorld() throws -> GameWorld {
        _ = try SampleProject.create(at: dir, title: "Test")
        let p = try Project.load(from: dir)  // round-trip through disk
        let w = GameWorld(project: p, rng: SeededRandom(1))
        w.newGame()
        w.update(InputState())   // first frame starts the autorun intro
        return w
    }

    func run(_ w: GameWorld, _ frames: Int, _ input: InputState = InputState()) { for _ in 0..<frames { w.update(input) } }
    func press(_ w: GameWorld, _ input: InputState) { w.update(input); run(w, 2) }
    func drainMessages(_ w: GameWorld, max: Int = 50) {
        for _ in 0..<max where w.message != nil || w.isEventRunning || w.nameInput != nil {
            run(w, 200)
            if w.nameInput != nil { w.nameInput = nil }
            if w.message != nil { press(w, InputState(ok: true)) }
        }
    }

    func testAutorunIntroThenErasesItself() throws {
        let w = try makeWorld()
        run(w, 2)
        run(w, 60)
        XCTAssertNotNil(w.message)
        XCTAssertTrue(w.message!.text.contains("Welcome to Kampung Lakon"))
        XCTAssertEqual(w.screen.pictures[1]?.name, "Banner")
        drainMessages(w)
        XCTAssertNil(w.message)
        XCTAssertTrue(w.state.selfSwitch(1, 6, "A"))
        XCTAssertFalse(w.isEventRunning)
    }

    func testWalkingAndBlocking() throws {
        let w = try makeWorld()
        drainMessages(w)
        let x0 = w.player.x
        run(w, 16, InputState(dir4: 6))   // 1 tile = 16 frames at speed 4 (2^4/256)
        run(w, 1)
        XCTAssertEqual(w.player.x, x0 + 1)
        XCTAssertEqual(w.player.realX, Double(x0 + 1))
    }

    func testElderChoiceSetsSwitchAndChangesPage() throws {
        let w = try makeWorld()
        drainMessages(w)
        // Elder at (10,7); stand at (10,8) facing up.
        w.player.locate(10, 8); w.player.direction = 8
        press(w, InputState(ok: true))
        run(w, 70)                                          // "!" balloon plays first
        XCTAssertTrue(w.message?.text.contains("Kampung Lakon") ?? false, "\(String(describing: w.message?.text))")
        run(w, 200); press(w, InputState(ok: true))       // close text, choices appear
        XCTAssertEqual(w.message?.choices.count, 3)
        press(w, InputState(down: true))
        press(w, InputState(ok: true))                     // "Any work?"
        drainMessages(w)
        XCTAssertTrue(w.state.switchValue(1))
        XCTAssertEqual(w.state.variable(1), 1)
        XCTAssertEqual(w.events.first { $0.eventId == 1 }?.pageIndex, 1)
        w.player.direction = 8
        press(w, InputState(ok: true))
        XCTAssertTrue(w.message?.text.contains("greeted me 1 times") ?? false, "\\V[1] substitution")
    }

    func testChestGivesItemOnceAndTransferWorks() throws {
        let w = try makeWorld()
        drainMessages(w)
        w.player.locate(9, 14); w.player.direction = 4
        press(w, InputState(ok: true))
        drainMessages(w)
        XCTAssertEqual(w.state.itemCount(2), 1)
        XCTAssertEqual(w.state.gold, 120)
        XCTAssertEqual(w.events.first { $0.eventId == 2 }?.pageIndex, 1)
        XCTAssertEqual(w.events.first { $0.eventId == 2 }?.direction, 8, "opened chest frame")
        w.player.direction = 4
        press(w, InputState(ok: true)); drainMessages(w)
        XCTAssertEqual(w.state.itemCount(2), 1, "second open gives nothing")

        // Door at (11,5): walk up from (11,6).
        w.player.locate(11, 6)
        run(w, 16, InputState(dir4: 8)); run(w, 80)
        XCTAssertEqual(w.state.mapId, 2)
        XCTAssertEqual(w.player.x, 6); XCTAssertEqual(w.player.y, 8)

        let save = w.makeSave()
        let data = try JSONEncoder().encode(save)
        let w2 = GameWorld(project: w.project)
        w2.load(try JSONDecoder().decode(GameState.self, from: data))
        XCTAssertEqual(w2.state.mapId, 2)
        XCTAssertEqual(w2.state.itemCount(2), 1)
        XCTAssertTrue(w2.state.selfSwitch(1, 2, "A"))
    }

    func testBlockRangeAndConditionalSkip() {
        let list = Cmd.branch(Cmd.ifSwitch(5), then: [Cmd.switches(6, true)], else: [Cmd.switches(7, true)]) + [.end(0)]
        XCTAssertEqual(Cmd.blockRange(list, at: 0), 0..<(list.count - 1))
        let p = Project(root: dir)
        let w = GameWorld(project: p)
        let i = Interpreter()
        i.setup(list, eventId: 0)
        i.update(w)
        XCTAssertFalse(w.state.switchValue(6))
        XCTAssertTrue(w.state.switchValue(7))
    }

    func testEscapes() {
        let p = Project(root: dir)
        p.actors = [nil, Actor(id: 1, name: "Arya")]
        let w = GameWorld(project: p)
        w.state.setVariable(3, 42); w.state.setVariable(4, 3); w.state.party = [1]
        XCTAssertEqual(w.convertEscapes("\\N[1] has \\V[\\V[4]] \\G \\C[2]ok\\\\"), "Arya has 42 G \\C[2]ok\\", "colour codes are kept for the renderer")
        XCTAssertEqual(w.convertEscapes("\\P[1]!"), "Arya!")
    }
}

final class InputTests: XCTestCase {
    func testTapTowardBlockedTileTurnsPlayer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lakon-tap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try SampleProject.create(at: dir, title: "T")
        let w = GameWorld(project: try Project.load(from: dir), rng: SeededRandom(2))
        w.newGame()
        w.state.setSelfSwitch(1, 6, "A", true)   // skip intro
        w.player.locate(10, 8); w.player.direction = 4
        for _ in 0..<3 { w.update(InputState(dir4: 8)) }
        XCTAssertEqual(w.player.direction, 8)
        XCTAssertEqual(w.player.y, 8)
        w.update(InputState(ok: true))
        for _ in 0..<70 { w.update(InputState()) }   // "!" balloon, then the text
        XCTAssertTrue(w.message?.speakerName == "Elder")
    }
}

/// Runs only when LAKON_MZ_FIXTURE points at a real RPG Maker MZ project (not shipped: MZ RTP assets are licensed).
final class MZFixtureTests: XCTestCase {
    func testRealMZProjectLoadsAndSimulates() throws {
        guard let path = ProcessInfo.processInfo.environment["LAKON_MZ_FIXTURE"] else { throw XCTSkip("set LAKON_MZ_FIXTURE") }
        let p = try Project.load(from: URL(fileURLWithPath: path))
        XCTAssertFalse(p.maps.isEmpty)
        for (id, m) in p.maps {
            XCTAssertEqual(m.data.count, m.width * m.height * 6, "map \(id) layer count")
            for e in m.liveEvents { for pg in e.pages { for c in pg.list { _ = Cmd.describe(c, project: p) } } }
        }
        let w = GameWorld(project: p, rng: SeededRandom(7))
        w.newGame()
        for f in 0..<1200 { w.update(InputState(dir4: [2, 4, 6, 8][(f / 40) % 4], ok: f % 50 == 0)) }
        XCTAssertGreaterThan(w.state.playFrames, 0)
    }
}
