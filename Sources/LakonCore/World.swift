import Foundation

/// Headless game simulation: one `update(_:)` per 60 Hz frame, no rendering.
/// Combines what MZ splits across Game_Map, Game_Player, Game_Party, Scene_Map's update loop and Window_Message's input.
/// Renderers (SpriteKit) only read from it, which also makes it testable without a window.
public final class GameWorld {
    public let project: Project
    public let rng: RandomSource
    public var state = GameState()
    public private(set) var map: GameMap
    public private(set) var tileset: Tileset
    public let player = GamePlayer()
    public private(set) var followers: [GameFollower] = []
    public private(set) var events: [GameEvent] = []
    public private(set) var vehicles: [GameVehicle] = []
    public var message: GameMessage?
    public private(set) var transferPending: (mapId: Int, x: Int, y: Int, d: Int, fade: Int)?
    public private(set) var brightness = 255.0
    var fadeTarget = 255.0
    var fadeDuration = 0
    public var gameOver = false
    public var returnToTitle = false
    /// Bumped whenever the map (or its tileset) changes so renderers rebuild tile layers.
    public private(set) var mapGeneration = 0
    public private(set) var frameCount = 0
    /// MZ tile animation frame (advances every 30 frames).
    public var animationFrame: Int { frameCount / 30 }
    public let audio = AudioState()
    public private(set) var battle: BattleManager?
    public var shop: ShopState?
    public var nameInput: (actorId: Int, maxLength: Int)?
    /// Scene requests from events (351 Open Menu, 352 Open Save).
    public var requestMenu = false
    public var requestSave = false
    /// Flash for damage floors / map poison.
    public var mapDamageFlash = 0
    public private(set) var lastInput = InputState()
    public var followersVisible = true
    /// Last used skill/item/actor/enemy ids for Control Variables "Last" data (type 8).
    var lastActions = [0, 0, 0, 0, 0, 0]
    func lastActionData(_ i: Int) -> Int { lastActions[safe: i] ?? 0 }

    let mainInterpreter = Interpreter()
    var commonParallels: [Int: Interpreter] = [:]
    var reservedCommonEvents: [Int] = []
    var actors: [Int: GameActor] = [:]
    var encounterCount = 0
    var pluginsLoaded = false
    var actorStepCounters: [Int: [Int: Int]] = [:]

    public private(set) lazy var script: ScriptEngine = ScriptEngine(world: self)

    public init(project: Project, rng: RandomSource = SystemRandom()) {
        self.project = project
        self.rng = rng
        map = GameMap(width: 1, height: 1)
        tileset = Tileset(id: 0, name: "", names: [])
        player.world = self
    }

    // MARK: lifecycle

    public func newGame() {
        mainInterpreter.clear()
        state = GameState()
        actors = [:]
        state.party = project.system.partyMembers.filter { project.actor($0) != nil }
        for id in state.party { _ = actor(id) }
        setupVehicles(nil)
        loadPluginsOnce()
        refreshPlayerImage()
        setupMap(project.system.startMapId, project.system.startX, project.system.startY, 2)
        makeEncounterCount()
    }

    public func makeSave() -> GameState {
        var s = state
        s.playerX = player.x; s.playerY = player.y; s.playerDirection = player.direction
        s.actors = actors.mapValues(\.save)
        s.vehicles = vehicles.map(\.save)
        s.bgm = audio.currentBgm; s.bgs = audio.currentBgs
        s.saveCount += 1
        return s
    }

    public func load(_ s: GameState) {
        mainInterpreter.clear()
        message = nil; transferPending = nil; shop = nil; nameInput = nil; battle = nil
        reservedCommonEvents = []; fadeDuration = 0; brightness = 255
        state = s
        actors = [:]
        for (id, a) in s.actors where project.actor(id) != nil { actors[id] = GameActor(project: project, save: a) }
        setupVehicles(s.vehicles)
        loadPluginsOnce()
        refreshPlayerImage()
        setupMap(s.mapId, s.playerX, s.playerY, s.playerDirection)
        if let b = s.bgm { audio.playBgm(b) } else { audio.stopBgm() }
        if let b = s.bgs { audio.playBgs(b) }
        makeEncounterCount()
    }

    func loadPluginsOnce() {
        guard !pluginsLoaded else { return }
        pluginsLoaded = true
        script.loadPlugins(from: project)
    }

    // MARK: party

    public func actor(_ id: Int) -> GameActor? {
        if let a = actors[id] { return a }
        guard project.actor(id) != nil else { return nil }
        let a = GameActor(project: project, actorId: id)
        actors[id] = a
        return a
    }
    /// Battle members (first four), like MZ's maxBattleMembers.
    public var partyMembers: [GameActor] { state.party.prefix(4).compactMap { actor($0) } }
    public var allMembers: [GameActor] { state.party.compactMap { actor($0) } }
    public func addActor(_ id: Int) {
        guard project.actor(id) != nil, !state.party.contains(id) else { return }
        state.party.append(id); state.needsRefresh = true; refreshPlayerImage()
    }
    public func removeActor(_ id: Int) {
        state.party.removeAll { $0 == id }; state.needsRefresh = true; refreshPlayerImage()
    }
    public var isAllDead: Bool { !partyMembers.isEmpty && partyMembers.allSatisfy(\.isDead) }
    func partyHasAbility(_ id: Int) -> Bool {
        partyMembers.contains { a in a.allTraits().contains { $0.code == Trait.partyAbility && $0.dataId == id } }
    }

    func refreshPlayerImage() {
        let members = partyMembers
        let leader = members.first.flatMap { project.actor($0.actorId) }
        player.setImage(leader?.characterName ?? "", leader?.characterIndex ?? 0)
        let others = Array(members.dropFirst())
        while followers.count < others.count {
            let f = GameFollower(); f.world = self; f.locate(player.x, player.y); f.direction = player.direction; followers.append(f)
        }
        if followers.count > others.count { followers.removeLast(followers.count - others.count) }
        for (f, a) in zip(followers, others) {
            let d = project.actor(a.actorId)
            f.setImage(d?.characterName ?? "", d?.characterIndex ?? 0)
        }
    }

    // MARK: map

    func setupMap(_ id: Int, _ x: Int, _ y: Int, _ d: Int) {
        state.mapId = id
        map = project.maps[id] ?? GameMap(width: 17, height: 13)
        tileset = project.tileset(for: map)
        // The running interpreter is kept: commands after Transfer Player continue on the new map (as in MZ).
        player.locate(max(0, min(map.width - 1, x)), max(0, min(map.height - 1, y)))
        if d != 0 { player.direction = d }
        for f in followers { f.locate(player.x, player.y); f.direction = player.direction }
        events = map.liveEvents.map { GameEvent(data: $0, world: self) }
        commonParallels = [:]
        if let v = vehicle { v.mapId = id; v.locate(player.x, player.y); v.direction = player.direction }
        mapGeneration += 1
        if vehicle == nil {
            if map.autoplayBgm { audio.playBgm(map.bgm) }
            if map.autoplayBgs { audio.playBgs(map.bgs) }
        }
        script.emit("mapStart", [id])
    }

    public func changeTileset(_ id: Int) {
        map.tilesetId = id
        tileset = project.tileset(for: map)
        mapGeneration += 1
    }

    public var visibleVehicles: [GameVehicle] { vehicles.filter { $0.mapId == state.mapId && !$0.characterName.isEmpty } }

    // MARK: frame update

    public func update(_ input: InputState) {
        frameCount += 1
        lastInput = input
        state.playFrames += 1
        if mapDamageFlash > 0 { mapDamageFlash -= 1 }
        updateFade()
        state.screen.update()
        if let b = battle {
            if message != nil { updateMessage(input) }
            b.update()
            if b.isFinished { battle = nil }
            return
        }
        if shop != nil || nameInput != nil { return }
        if let t = transferPending, fadeDuration == 0 {
            if brightness > 0 && t.fade == 0 { startFade(to: 0, duration: 12) }
            else {
                transferPending = nil
                setupMap(t.mapId, t.x, t.y, t.d)
                if t.fade == 0 { startFade(to: 255, duration: 12) }
            }
            return
        }
        if state.needsRefresh { refreshEvents() }
        // A press that advanced a message must not also trigger an event (MZ: message stays "busy" while closing).
        let inputConsumed = message != nil
        if inputConsumed { updateMessage(input) }
        updateInterpreter()
        if battle != nil || shop != nil || nameInput != nil { return }
        updateCommonParallels()
        let wasMoving = player.isMoving
        let wasPos = (player.x, player.y)
        if canPlayerMove, input.dir4 != 0, !player.isMoving {
            player.dashing = input.dash && !map.disableDashing && vehicle == nil
            if player.moveStraight(input.dir4) {
                state.steps += 1
                var target = wasPos
                for f in followers { let before = (f.x, f.y); f.chase(target); target = before }
            }
        }
        player.update()
        for f in followers { f.update() }
        for e in events { e.update() }
        for v in vehicles where v.mapId == state.mapId { v.update() }
        if let v = vehicle, boarding == nil { v.locate(player.x, player.y); v.realX = player.realX; v.realY = player.realY; v.direction = player.direction }
        updateVehicleBoarding()
        if canPlayerMove {
            if wasMoving && !player.isMoving {
                onPlayerStep()
                startMapEvent(player.x, player.y, triggers: [1, 2], normal: false)
                if !isEventRunning { updateEncounter() }
            }
            if !isEventRunning && !player.isMoving && input.ok && !inputConsumed { triggerAction() }
        }
        if state.needsRefresh { refreshEvents() }
        script.emit("update")
    }

    public var isEventRunning: Bool { mainInterpreter.isRunning || events.contains { $0.starting } || !reservedCommonEvents.isEmpty }
    var canPlayerMove: Bool {
        !isEventRunning && message == nil && transferPending == nil && fadeDuration == 0 && !player.moveRouteForcing && boarding == nil
    }

    func refreshEvents() {
        state.needsRefresh = false
        for e in events { e.refresh() }
    }

    func updateInterpreter() {
        for _ in 0..<64 {
            mainInterpreter.update(self)
            if mainInterpreter.isRunning { return }
            if mainInterpreter.eventId > 0 { events.first { $0.eventId == mainInterpreter.eventId }?.unlock() }
            mainInterpreter.clear()
            if !setupStartingEvent() { return }
        }
    }

    /// Mirrors Game_Map.setupStartingEvent: reserved common events, starting map events, autorun pages, autorun common events.
    func setupStartingEvent() -> Bool {
        if state.needsRefresh { refreshEvents() }
        if !reservedCommonEvents.isEmpty {
            let id = reservedCommonEvents.removeFirst()
            if let ce = project.commonEvents[safe: id] ?? nil { mainInterpreter.setup(ce.list, eventId: 0, mapId: state.mapId); return true }
        }
        if let e = events.first(where: { $0.starting }) {
            e.clearStartingFlag()
            mainInterpreter.setup(e.list, eventId: e.eventId, mapId: state.mapId)
            return true
        }
        for ce in project.commonEvents.compactMap({ $0 }) where ce.trigger == 1 && state.switchValue(ce.switchId) {
            mainInterpreter.setup(ce.list, eventId: 0, mapId: state.mapId)
            return true
        }
        return false
    }

    public func reserveCommonEvent(_ id: Int) { reservedCommonEvents.append(id) }

    func updateCommonParallels() {
        for ce in project.commonEvents.compactMap({ $0 }) where ce.trigger == 2 {
            guard state.switchValue(ce.switchId) else { commonParallels[ce.id] = nil; continue }
            let i = commonParallels[ce.id] ?? Interpreter()
            commonParallels[ce.id] = i
            if !i.isRunning { i.setup(ce.list, eventId: 0, mapId: state.mapId) }
            i.update(self)
        }
    }

    func startMapEvent(_ x: Int, _ y: Int, triggers: [Int], normal: Bool) {
        guard !isEventRunning, vehicleKind != .airship else { return }
        for e in events where e.x == x && e.y == y && e.isTriggerIn(triggers) && e.isNormalPriority == normal {
            e.start()
        }
    }

    /// Action button: vehicles first, then the same tile (below/above), then the tile in front, reaching over counters.
    func triggerAction() {
        if getOnOffVehicle() { return }
        startMapEvent(player.x, player.y, triggers: [0], normal: false)
        if isEventRunning { return }
        let d = player.direction
        let x2 = GameCharacter.xWith(player.x, d), y2 = GameCharacter.yWith(player.y, d)
        startMapEvent(x2, y2, triggers: [0, 1, 2], normal: true)
        if !isEventRunning && isCounter(x2, y2) {
            startMapEvent(GameCharacter.xWith(x2, d), GameCharacter.yWith(y2, d), triggers: [0, 1, 2], normal: true)
        }
    }

    // MARK: terrain flags (Game_Map.isLadder/isBush/isCounter/isDamageFloor)

    func layeredFlag(_ x: Int, _ y: Int, _ bit: Int) -> Bool {
        guard map.isValid(x, y) else { return false }
        return (0..<4).contains { map.tileId(x, y, $0) > 0 && tileset.flag(map.tileId(x, y, $0)) & bit != 0 }
    }
    public func isLadder(_ x: Int, _ y: Int) -> Bool { layeredFlag(x, y, 0x20) }
    public func isBush(_ x: Int, _ y: Int) -> Bool { layeredFlag(x, y, 0x40) }
    public func isCounter(_ x: Int, _ y: Int) -> Bool { layeredFlag(x, y, 0x80) }
    public func isDamageFloor(_ x: Int, _ y: Int) -> Bool { layeredFlag(x, y, 0x100) }
    public func terrainTag(_ x: Int, _ y: Int) -> Int {
        for z in stride(from: 3, through: 0, by: -1) { let t = tileset.flag(map.tileId(x, y, z)) >> 12; if t > 0 { return t } }
        return 0
    }

    /// Per-step effects: damage floors, walking state removal, and map turn-end every 20 steps (poison/regen).
    func onPlayerStep() {
        guard vehicle == nil else { return }
        if isLadder(player.x, player.y) { player.direction = 8 }
        for a in partyMembers {
            if isDamageFloor(player.x, player.y) {
                let dmg = min(Int((10 * a.fdr).rounded(.down)), project.system.optFloorDeath ? a.hp : max(a.hp - 1, 0))
                if dmg > 0 { a.gainHp(-dmg); mapDamageFlash = 8 }
            }
            for st in a.sortedStates where st.removeByWalking {
                var c = actorStepCounters[a.actorId] ?? [:]
                c[st.id, default: 0] += 1
                if c[st.id]! >= st.stepsToRemove { a.removeState(st.id); c[st.id] = nil }
                actorStepCounters[a.actorId] = c
            }
            if state.steps % 20 == 0 && !a.states.isEmpty {
                let hp = a.hp
                a.onTurnEnd(slipDeath: project.system.optSlipDeath)
                if a.hp < hp { mapDamageFlash = 8 }
            }
        }
        if isAllDead { gameOver = true }
    }

    // MARK: encounters (Game_Player.updateEncounterCount / makeEncounterTroopId)

    func makeEncounterCount() {
        let n = max(1, map.encounterStep)
        encounterCount = rng.next(n) + rng.next(n) + 1
    }

    func updateEncounter() {
        guard state.encounterEnabled, vehicleKind != .airship, !map.encounterList.isEmpty, !partyHasAbility(1) else { return }
        var progress = isBush(player.x, player.y) ? 2.0 : 1.0
        if partyHasAbility(0) { progress *= 0.5 }
        if vehicleKind == .ship { progress *= 0.5 }
        encounterCount -= Int(progress.rounded(.up))
        guard encounterCount <= 0 else { return }
        makeEncounterCount()
        let region = map.regionId(player.x, player.y)
        let list = map.encounterList.filter { $0.regionSet.isEmpty || $0.regionSet.contains(region) }
        let sum = list.reduce(0) { $0 + $1.weight }
        guard sum > 0 else { return }
        var v = rng.next(sum)
        for e in list { v -= e.weight; if v < 0 { startBattle(troopId: e.troopId, canEscape: true, canLose: false, encounter: true); return } }
    }

    // MARK: battle

    public func startBattle(troopId: Int, canEscape: Bool, canLose: Bool, encounter: Bool = false, onEnd: ((BattleManager.Outcome) -> Void)? = nil) {
        guard project.troop(troopId) != nil, !partyMembers.isEmpty else { return }
        let b = BattleManager(world: self, troopId: troopId, canEscape: canEscape, canLose: canLose)
        if encounter {
            let partyAgi = partyMembers.map(\.agi).reduce(0, +) / max(1, partyMembers.count)
            let troopAgi = b.enemies.map(\.agi).reduce(0, +) / max(1, b.enemies.count)
            let pre = (partyAgi >= troopAgi ? 0.05 : 0.03) * (partyHasAbility(3) ? 4 : 1)
            let sur = partyHasAbility(2) ? 0 : (partyAgi >= troopAgi ? 0.03 : 0.05)
            let r = Double(rng.next(1000)) / 1000
            if r < pre { b.preemptive = true } else if r < pre + sur { b.surprise = true }
        }
        b.battleback1 = map.specifyBattleback ? map.battleback1Name : project.system.battleback1Name
        b.battleback2 = map.specifyBattleback ? map.battleback2Name : project.system.battleback2Name
        audio.saveBgm()
        let bgs = audio.currentBgs
        audio.playBgm(state.battleBgm ?? project.system.battleBgm)
        audio.fadeOutBgs(1)
        state.battleCount += 1
        b.onEnd = { [unowned self] o in
            switch o {
            case .win: state.winCount += 1
            case .escape: state.escapeCount += 1
            default: break
            }
            state.screen.clearForBattleEnd()
            if o == .lose && !canLose { gameOver = true }
            audio.replayBgm()
            if let s = bgs { audio.playBgs(s) }
            onEnd?(o)
            state.needsRefresh = true
            script.emit("battleEnd", [o.rawValue])
        }
        battle = b
        script.emit("battleStart", [troopId])
    }

    // MARK: vehicles

    func setupVehicles(_ saves: [VehicleSave]?) {
        let s = project.system
        vehicles = GameVehicle.Kind.allCases.map { k in
            let v = GameVehicle(kind: k, data: [s.boat, s.ship, s.airship][k.rawValue])
            v.world = self
            if let sv = saves, k.rawValue < sv.count { v.mapId = sv[k.rawValue].mapId; v.locate(sv[k.rawValue].x, sv[k.rawValue].y); v.direction = sv[k.rawValue].direction }
            return v
        }
        if let v = vehicle {
            v.driving = true; v.stepAnime = true; v.altitude = v.kind == .airship ? GameVehicle.maxAltitude : 0
            player.transparent = true; player.through = v.kind == .airship; player.moveSpeed = v.moveSpeed
        } else {
            player.transparent = false; player.through = false; player.moveSpeed = 4
        }
    }

    public var vehicle: GameVehicle? { state.vehicleType >= 0 && state.vehicleType < vehicles.count ? vehicles[state.vehicleType] : nil }
    var vehicleKind: GameVehicle.Kind? { vehicle?.kind }
    var vehicleTypeName: String { ["boat", "ship", "airship"][safe: state.vehicleType] ?? "walk" }
    /// Non-nil while boarding (player stepping onto the vehicle / airship ascending) or alighting.
    var boarding: (GameVehicle, Bool)?

    func getOnOffVehicle() -> Bool {
        if let v = vehicle { return getOff(v) }
        let d = player.direction
        let x2 = GameCharacter.xWith(player.x, d), y2 = GameCharacter.yWith(player.y, d)
        let here = visibleVehicles.first { $0.kind == .airship && $0.x == player.x && $0.y == player.y }
        let front = visibleVehicles.first { $0.kind != .airship && $0.x == x2 && $0.y == y2 }
        guard let v = here ?? front else { return false }
        state.vehicleType = v.kind.rawValue
        if v.kind != .airship { player.through = true; player.moveStraight(d); player.through = false }
        boarding = (v, true)
        return true
    }

    func getOff(_ v: GameVehicle) -> Bool {
        guard v.isLandOk(player.x, player.y, player.direction) else { return false }
        if v.kind == .airship { player.direction = 2 }
        v.driving = false
        v.stepAnime = false
        player.moveSpeed = 4; player.through = false
        if v.kind != .airship { player.transparent = false; player.through = true; player.moveStraight(player.direction); player.through = false }
        state.vehicleType = -1
        boarding = (v, false)
        audio.replayBgm()
        makeEncounterCount()
        return true
    }

    func updateVehicleBoarding() {
        guard let (v, on) = boarding else { return }
        if on {
            guard !player.isMoving else { return }
            player.direction = v.direction
            player.moveSpeed = v.moveSpeed
            player.transparent = true
            if v.kind == .airship { player.through = true }
            v.driving = true; v.stepAnime = true
            audio.saveBgm()
            if let b = v.bgm { audio.playBgm(b) }
            boarding = nil
        } else {
            if v.kind == .airship && v.altitude > 0 { return }
            player.transparent = false
            for f in followers { f.locate(player.x, player.y) }
            boarding = nil
        }
    }

    public func setVehicleLocation(_ kind: Int, mapId: Int, x: Int, y: Int) {
        guard kind < vehicles.count else { return }
        vehicles[kind].mapId = mapId; vehicles[kind].locate(x, y)
    }

    // MARK: message window input (Window_Message / Window_ChoiceList / Window_NumberInput / Window_EventItem)

    func updateMessage(_ input: InputState) {
        guard var m = message else { return }
        if m.scrolling {
            m.scrollOffset += Double(m.scrollSpeed) * (input.ok ? 3 : 0.5)
            message = m
            if m.scrollOffset > Double(m.lines.count * 36 + 700) { message = nil }
            return
        }
        if !m.isTextComplete {
            m.visibleChars = input.ok ? m.text.count : m.visibleChars + 1
            message = m
            return
        }
        if m.numberDigits > 0 {
            let place = Int(pow(10, Double(m.numberDigits - 1 - m.numberCursor)))
            let digit = (m.number / place) % 10
            if input.up { m.number += (digit == 9 ? -9 : 1) * place }
            if input.down { m.number += (digit == 0 ? 9 : -1) * place }
            if input.right { m.numberCursor = min(m.numberDigits - 1, m.numberCursor + 1) }
            if input.left { m.numberCursor = max(0, m.numberCursor - 1) }
            message = m
            if input.ok { state.setVariable(m.numberVariable, m.number); message = nil }
            return
        }
        if m.itemChoiceVariable > 0 {
            let n = m.itemChoices.count + 1   // last row = none
            if input.up { m.itemChoiceIndex = (m.itemChoiceIndex + n - 1) % n }
            if input.down { m.itemChoiceIndex = (m.itemChoiceIndex + 1) % n }
            message = m
            if input.ok {
                state.setVariable(m.itemChoiceVariable, m.itemChoiceIndex < m.itemChoices.count ? m.itemChoices[m.itemChoiceIndex] : 0)
                message = nil
            } else if input.cancel { state.setVariable(m.itemChoiceVariable, 0); message = nil }
            return
        }
        if !m.choices.isEmpty {
            if input.up { m.choiceIndex = (m.choiceIndex + m.choices.count - 1) % m.choices.count }
            if input.down { m.choiceIndex = (m.choiceIndex + 1) % m.choices.count }
            message = m
            if input.ok { m.onChoose?(m.choiceIndex); message = nil }
            else if input.cancel && m.choiceCancel != -1 { m.onChoose?(m.choiceCancel); message = nil }
            return
        }
        if input.ok || input.cancel { message = nil }
    }

    /// $gameMessage.add from scripts.
    func addScriptMessage(_ text: String) {
        if message == nil { message = GameMessage() }
        message!.lines.append(convertEscapes(text))
    }

    // MARK: transfer / fade

    func reserveTransfer(mapId: Int, x: Int, y: Int, direction: Int, fadeType: Int) {
        transferPending = (mapId, x, y, direction, fadeType)
    }

    func startFade(to target: Double, duration: Int) {
        fadeTarget = target; fadeDuration = duration
    }

    private func updateFade() {
        guard fadeDuration > 0 else { return }
        brightness = (brightness * Double(fadeDuration - 1) + fadeTarget) / Double(fadeDuration)
        fadeDuration -= 1
    }

    public var screen: GameScreen {
        get { state.screen }
        set { state.screen = newValue }
    }

    // MARK: menu helpers used by the UI

    /// Uses an item or skill from the menu on an actor (Scene_ItemBase.applyItem). Returns true if it had an effect.
    @discardableResult
    public func useInMenu(itemId: Int = 0, skillId: Int = 0, user: GameActor, target: GameActor?) -> Bool {
        let action = skillId > 0 ? GameAction(subject: user, skillId: skillId) : GameAction(subject: user, itemId: itemId)
        guard let item = action.item, user.canUse(item, inBattle: false) else { return false }
        if itemId > 0, state.count(kind: 1, id: itemId) == 0 { return false }
        let targets: [GameBattler] = item.isForAll ? allMembers : [target ?? user]
        var any = false
        for t in targets where action.testApply(t, item) {
            action.apply(to: t, rng: rng, formula: { [unowned self] f, a, b in script.evalFormula(f, a: a, b: b) },
                         onCommonEvent: { [unowned self] in reserveCommonEvent($0) })
            any = any || t.result.isHit
        }
        if item.effects.contains(where: { $0.code == Effect.commonEvent }) { any = true }
        guard any else { playSystemSound(3); return false }
        if let s = item as? Skill { user.paySkillCost(s) }
        if let it = item as? Item, it.consumable { state.gain(kind: 1, id: it.id, -1) }
        playSystemSound(item.isSkill ? 23 : 22)
        return true
    }

    public func equip(actor: GameActor, slot: Int, itemId: Int) {
        guard !actor.isEquipLocked(slot: slot) else { return }
        let kind = slot == 0 ? 2 : 3
        if itemId > 0 {
            guard state.count(kind: kind, id: itemId) > 0, actor.canEquip(slot: slot, id: itemId) else { return }
            state.gain(kind: kind, id: itemId, -1)
        }
        let old = actor.changeEquip(slot: slot, to: itemId)
        if old > 0 { state.gain(kind: kind, id: old, 1) }
        playSystemSound(4)
    }

    public func playSystemSound(_ i: Int) { if let s = project.system.sounds[safe: i] { audio.playSe(s) } }

    // MARK: text escapes (Window_Base.convertEscapeCharacters subset)

    public func convertEscapes(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\\\\", with: "\u{1B}")
        func sub(_ pattern: String, _ f: (Int) -> String) {
            let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            // Two passes so \V[\V[1]] resolves like MZ.
            for _ in 0..<2 {
                let ns = t as NSString
                var out = "", last = 0
                for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                    out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                    out += f(Int(ns.substring(with: m.range(at: 1))) ?? 0)
                    last = m.range.location + m.range.length
                }
                t = out + ns.substring(from: last)
            }
        }
        sub("\\\\V\\[(\\d+)\\]") { String(self.state.variable($0)) }
        sub("\\\\N\\[(\\d+)\\]") { self.actor($0)?.name ?? "" }
        sub("\\\\P\\[(\\d+)\\]") { n in
            let a = n >= 1 && n <= self.state.party.count ? self.state.party[n - 1] : 0
            return self.actor(a)?.name ?? ""
        }
        t = t.replacingOccurrences(of: "\\G", with: project.system.currencyUnit, options: .caseInsensitive)
        // \C[n] colors and \I[n] icons stay for the renderer; other control codes are stripped.
        t = t.replacingOccurrences(of: "\\\\(PX|PY|FS)\\[\\d+\\]|\\\\[{}$.|!><^]", with: "", options: .regularExpression)
        return t.replacingOccurrences(of: "\u{1B}", with: "\\")
    }
}

/// Party members walking behind the player (Game_Follower.chaseCharacter).
public final class GameFollower: GameCharacter {
    override init() { super.init(); through = true; moveSpeed = 4 }
    func chase(_ target: (Int, Int)) {
        let sx = target.0 - x, sy = target.1 - y
        if sx == 0 && sy == 0 { return }
        if let p = world?.player { moveSpeed = p.moveSpeed; dashing = p.dashing }
        moveStraight(abs(sx) > abs(sy) ? (sx > 0 ? 6 : 4) : (sy > 0 ? 2 : 8))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

/// Scene_Shop logic. Goods: kind 0 item / 1 weapon / 2 armor, id, and price.
public struct ShopState {
    public struct Good { public let kind: Int; public let id: Int; public let price: Int
        public init(kind: Int, id: Int, price: Int) { self.kind = kind; self.id = id; self.price = price } }
    public var goods: [Good]
    public var purchaseOnly: Bool
    public init(goods: [Good], purchaseOnly: Bool) { self.goods = goods; self.purchaseOnly = purchaseOnly }

    public static func name(kind: Int, id: Int, _ p: Project) -> String {
        switch kind { case 1: return p.weapon(id)?.name ?? "?"; case 2: return p.armor(id)?.name ?? "?"; default: return p.item(id)?.name ?? "?" }
    }
    public static func basePrice(kind: Int, id: Int, _ p: Project) -> Int {
        switch kind { case 1: return p.weapon(id)?.price ?? 0; case 2: return p.armor(id)?.price ?? 0; default: return p.item(id)?.price ?? 0 }
    }
    /// Inventory kind (1 item, 2 weapon, 3 armor) from shop kind (0, 1, 2).
    public static func stateKind(_ shopKind: Int) -> Int { shopKind + 1 }

    public static func maxBuy(_ g: Good, world: GameWorld) -> Int {
        let owned = world.state.count(kind: stateKind(g.kind), id: g.id)
        let byGold = g.price > 0 ? world.state.gold / g.price : 99
        return max(0, min(99 - owned, byGold))
    }
    public static func buy(_ g: Good, qty: Int, world: GameWorld) {
        guard qty > 0, qty <= maxBuy(g, world: world) else { return }
        world.state.gainGold(-g.price * qty)
        world.state.gain(kind: stateKind(g.kind), id: g.id, qty)
        world.playSystemSound(21)
    }
    /// MZ sells at half the database price, rounded down.
    public static func sell(kind: Int, id: Int, qty: Int, world: GameWorld) {
        guard qty > 0, world.state.count(kind: stateKind(kind), id: id) >= qty else { return }
        world.state.gainGold(basePrice(kind: kind, id: id, world.project) / 2 * qty)
        world.state.gain(kind: stateKind(kind), id: id, -qty)
        world.playSystemSound(21)
    }
}
