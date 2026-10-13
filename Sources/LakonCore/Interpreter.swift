import Foundation

/// Event command interpreter. Same model as rmmz_objects.js Game_Interpreter:
/// a flat list of {code, indent, parameters}; block structure is expressed by `indent`,
/// a branch is skipped by advancing while the next command's indent is deeper (skipBranch),
/// and each command returns false to "block" (retry next frame).
public final class Interpreter {
    public private(set) var list: [EventCommand] = []
    public private(set) var index = 0
    public private(set) var eventId = 0
    var mapId = 0
    var indent = 0
    var branch: [Int: Int] = [:]   // indent → result (1 true, 0 false, choice index, -2 cancel)
    var waitCount = 0
    var waitMode: WaitMode = .none
    var child: Interpreter?
    let depth: Int

    enum WaitMode { case none, message, transfer, fade, route(GameCharacter), battle, scene, balloon(GameCharacter), animation(GameCharacter) }

    public init(depth: Int = 0) { self.depth = depth }

    public var isRunning: Bool { !list.isEmpty }

    public func setup(_ list: [EventCommand], eventId: Int, mapId: Int = 0) {
        clear()
        self.list = list; self.eventId = eventId; self.mapId = mapId
    }
    public func clear() {
        list = []; index = 0; eventId = 0; indent = 0; branch = [:]; waitCount = 0; waitMode = .none; child = nil
    }

    func update(_ w: GameWorld) {
        var guardCount = 0
        while isRunning {
            if let c = child {
                if c.isRunning { c.update(w); if c.isRunning { return } }
                child = nil
            }
            if updateWait(w) { return }
            if !execute(w) { return }
            guardCount += 1
            if guardCount > 100_000 { clear(); return } // freeze guard (Game_Interpreter.checkFreeze)
        }
    }

    private func updateWait(_ w: GameWorld) -> Bool {
        if waitCount > 0 { waitCount -= 1; return true }
        switch waitMode {
        case .none: return false
        case .message: if w.message != nil { return true }
        case .transfer: if w.transferPending != nil { return true }
        case .fade: if w.fadeDuration > 0 { return true }
        case .route(let c): if c.moveRouteForcing { return true }
        case .battle: if w.battle != nil { return true }
        case .scene: if w.shop != nil || w.nameInput != nil || w.requestMenu || w.requestSave { return true }
        case .balloon(let c): if c.balloonFrames > 0 { return true }
        case .animation(let c): if c.animationFrames > 0 { return true }
        }
        waitMode = .none
        return false
    }

    private func execute(_ w: GameWorld) -> Bool {
        guard index < list.count else { terminate(w); return true }
        let cmd = list[index]
        indent = cmd.indent
        if !command(cmd.code, cmd.parameters, w) { return false }
        index += 1
        return true
    }

    private func terminate(_ w: GameWorld) {
        list = []
    }

    private func skipBranch() {
        while index + 1 < list.count && list[index + 1].indent > indent { index += 1 }
    }

    private func nextCode() -> Int { index + 1 < list.count ? list[index + 1].code : 0 }

    private func character(_ id: Int, _ w: GameWorld) -> GameCharacter? {
        if id < 0 { return w.player }
        return w.events.first { $0.eventId == (id == 0 ? eventId : id) }
    }

    private func operand(_ op: Int, _ type: Int, _ value: Int, _ w: GameWorld) -> Int {
        let v = type == 0 ? value : w.state.variable(value)
        return op == 0 ? v : -v
    }

    // MARK: commands

    private func command(_ code: Int, _ p: [JSONValue], _ w: GameWorld) -> Bool {
        switch code {
        case 101: // Show Text [face, faceIndex, background, position, speakerName]
            if w.message != nil { return false }
            var m = GameMessage()
            m.faceName = p[p: 0].string; m.faceIndex = p[p: 1].int
            m.background = p[p: 2].int; m.positionType = p[p: 3].int; m.speakerName = w.convertEscapes(p[p: 4].string)
            while nextCode() == 401 {
                index += 1
                m.lines.append(w.convertEscapes(list[index].parameters[p: 0].string))
            }
            if nextCode() == 102 { index += 1; setupChoices(list[index].parameters, &m, w) }
            else if nextCode() == 103 { index += 1; setupNumberInput(list[index].parameters, &m, w) }
            else if nextCode() == 104 { index += 1; setupItemChoice(list[index].parameters, &m, w) }
            w.message = m
            waitMode = .message
        case 102: // Show Choices [choices, cancelType, defaultType, positionType, background]
            if w.message != nil { return false }
            var m = GameMessage()
            setupChoices(p, &m, w)
            w.message = m
            waitMode = .message
        case 402: // When [index, name]
            if branch[indent] != p[p: 0].int { skipBranch() }
        case 403: // When Cancel
            if branch[indent] != -2 { skipBranch() }
        case 103: // Input Number [variableId, digits]
            if w.message != nil { return false }
            var m = GameMessage(); setupNumberInput(p, &m, w); w.message = m; waitMode = .message
        case 104: // Select Item [variableId, itypeId]
            if w.message != nil { return false }
            var m = GameMessage(); setupItemChoice(p, &m, w); w.message = m; waitMode = .message
        case 105: // Show Scrolling Text [speed, noFast] + 405 lines
            if w.message != nil { return false }
            var m = GameMessage(); m.scrolling = true; m.scrollSpeed = max(1, p[p: 0].int)
            while nextCode() == 405 { index += 1; m.lines.append(w.convertEscapes(list[index].parameters[p: 0].string)) }
            m.visibleChars = m.text.count
            w.message = m; waitMode = .message
        case 108, 408, 404, 412, 0: // comments / block ends
            break
        case 111: // Conditional Branch
            let r = conditionalBranch(p, w)
            branch[indent] = r ? 1 : 0
            if !r { skipBranch() }
        case 411: // Else
            if branch[indent] != 0 { skipBranch() }
        case 112: break // Loop
        case 413: // Repeat Above
            repeat { index -= 1 } while index > 0 && list[index].indent != indent
        case 113: // Break Loop
            var depthCount = 0
            while index < list.count - 1 {
                index += 1
                let c = list[index]
                if c.code == 112 { depthCount += 1 }
                if c.code == 413 {
                    if depthCount > 0 { depthCount -= 1 } else { break }
                }
            }
        case 115: // Exit Event Processing
            index = list.count
        case 117: // Common Event
            let id = p[p: 0].int
            if depth < 100, id < w.project.commonEvents.count, let ce = w.project.commonEvents[id] {
                let c = Interpreter(depth: depth + 1)
                c.setup(ce.list, eventId: eventId, mapId: mapId)
                child = c
            }
        case 121: // Control Switches [start, end, 0=ON]
            for i in p[p: 0].int...max(p[p: 0].int, p[p: 1].int) { w.state.setSwitch(i, p[p: 2].int == 0) }
        case 122: // Control Variables [start, end, op, operandType, a, b]
            let value: Int
            switch p[p: 3].int {
            case 0: value = p[p: 4].int
            case 1: value = w.state.variable(p[p: 4].int)
            case 2: let lo = p[p: 4].int, hi = p[p: 5].int; value = lo + w.rng.next(max(1, hi - lo + 1))
            case 3: value = gameData(p[p: 4].int, p[p: 5].int, p[p: 6].int, w)
            case 4: value = w.script.evalNumber(p[p: 4].string, interpreter: self)
            default: value = 0
            }
            for i in p[p: 0].int...max(p[p: 0].int, p[p: 1].int) {
                let old = w.state.variable(i)
                let n: Int
                switch p[p: 2].int {
                case 1: n = old + value
                case 2: n = old - value
                case 3: n = old * value
                case 4: n = value == 0 ? old : old / value
                case 5: n = value == 0 ? old : old % value
                default: n = value
                }
                w.state.setVariable(i, n)
            }
        case 123: // Control Self Switch [ch, 0=ON]
            if eventId > 0 { w.state.setSelfSwitch(mapId, eventId, p[p: 0].string, p[p: 1].int == 0) }
        case 125: // Change Gold [op, operandType, operand]
            w.state.gainGold(operand(p[p: 0].int, p[p: 1].int, p[p: 2].int, w))
        case 126: // Change Items [itemId, op, operandType, operand]
            w.state.gainItem(p[p: 0].int, operand(p[p: 1].int, p[p: 2].int, p[p: 3].int, w))
        case 129: // Change Party Member [actorId, 0 add / 1 remove, initialize]
            let a = p[p: 0].int
            if p[p: 1].int == 0 {
                if p[p: 2].bool { w.actors[a] = nil }
                w.addActor(a)
            } else { w.removeActor(a) }
        case 132: if let f = AudioFile(p[p: 0]) { w.state.battleBgm = f }       // Change Battle BGM
        case 133: if let f = AudioFile(p[p: 0]) { w.state.victoryMe = f }       // Change Victory ME
        case 134: w.state.saveEnabled = p[p: 0].int == 0                         // Change Save Access
        case 135: w.state.menuEnabled = p[p: 0].int == 0                         // Change Menu Access
        case 136: w.state.encounterEnabled = p[p: 0].int == 0                    // Change Encounter
        case 202: // Set Vehicle Location [vehicle, designation, mapId, x, y]
            let direct = p[p: 1].int == 0
            let m = direct ? p[p: 2].int : w.state.variable(p[p: 2].int)
            let x = direct ? p[p: 3].int : w.state.variable(p[p: 3].int)
            let y = direct ? p[p: 4].int : w.state.variable(p[p: 4].int)
            w.setVehicleLocation(p[p: 0].int, mapId: m, x: x, y: y)
        case 206: _ = w.getOnOffVehicle()                                        // Get on/off Vehicle
        case 212: // Show Animation [characterId, animationId, wait]
            if let c = character(p[p: 0].int, w) {
                c.startAnimation(p[p: 1].int, frames: w.project.animation(p[p: 1].int)?.totalFrames(targets: 1) ?? 0)
                if p[p: 2].bool { waitMode = .animation(c) }
            }
        case 213: // Show Balloon Icon [characterId, balloonId, wait]
            if let c = character(p[p: 0].int, w) { c.balloonId = p[p: 1].int; c.balloonFrames = 64; if p[p: 2].bool { waitMode = .balloon(c) } }
        case 216: w.followersVisible = p[p: 0].int == 0                         // Change Player Followers
        case 217: break                                                          // Gather Followers
        case 223: // Tint Screen [tone, duration, wait]
            w.screen.startTint(p[p: 0].array.map { Double($0.int) }, duration: p[p: 1].int)
            if p[p: 2].bool { waitCount = p[p: 1].int }
        case 224: // Flash Screen [color, duration, wait]
            w.screen.startFlash(p[p: 0].array.map { Double($0.int) }, duration: p[p: 1].int)
            if p[p: 2].bool { waitCount = p[p: 1].int }
        case 225: // Shake Screen [power, speed, duration, wait]
            w.screen.startShake(power: p[p: 0].int, speed: p[p: 1].int, duration: p[p: 2].int)
            if p[p: 3].bool { waitCount = p[p: 2].int }
        case 231: // Show Picture [id, name, origin, designation, x, y, scaleX, scaleY, opacity, blend]
            let (x, y) = picturePoint(p, w)
            w.screen.pictures[p[p: 0].int] = GamePicture(name: p[p: 1].string, origin: p[p: 2].int, x: x, y: y,
                                                          scaleX: Double(p[p: 6].int), scaleY: Double(p[p: 7].int), opacity: Double(p[p: 8].int), blendMode: p[p: 9].int)
        case 232: // Move Picture [id, _, origin, designation, x, y, scaleX, scaleY, opacity, blend, duration, wait, easing]
            let (x, y) = picturePoint(p, w)
            w.screen.pictures[p[p: 0].int]?.move(origin: p[p: 2].int, x: x, y: y, scaleX: Double(p[p: 6].int), scaleY: Double(p[p: 7].int),
                                                  opacity: Double(p[p: 8].int), blendMode: p[p: 9].int, duration: p[p: 10].int, easing: p[p: 12].int)
            if p[p: 11].bool { waitCount = p[p: 10].int }
        case 233: w.screen.pictures[p[p: 0].int]?.rotate(Double(p[p: 1].int))   // Rotate Picture
        case 234: // Tint Picture [id, tone, duration, wait]
            w.screen.pictures[p[p: 0].int]?.tint(p[p: 1].array.map { Double($0.int) }, duration: p[p: 2].int)
            if p[p: 3].bool { waitCount = p[p: 2].int }
        case 235: w.screen.pictures[p[p: 0].int] = nil                          // Erase Picture
        case 236: // Set Weather Effect [type, power, duration, wait]
            if w.battle == nil {
                w.screen.changeWeather(p[p: 0].string, power: p[p: 1].int, duration: p[p: 2].int)
                if p[p: 3].bool { waitCount = p[p: 2].int }
            }
        case 241: if let f = AudioFile(p[p: 0]) { w.audio.playBgm(f) }          // Play BGM
        case 242: w.audio.fadeOutBgm(p[p: 0].int)                               // Fadeout BGM
        case 243: w.audio.saveBgm()                                             // Save BGM
        case 244: w.audio.replayBgm()                                           // Resume BGM
        case 245: if let f = AudioFile(p[p: 0]) { w.audio.playBgs(f) }          // Play BGS
        case 246: w.audio.fadeOutBgs(p[p: 0].int)                               // Fadeout BGS
        case 249: if let f = AudioFile(p[p: 0]) { w.audio.playMe(f) }           // Play ME
        case 250: if let f = AudioFile(p[p: 0]) { w.audio.playSe(f) }           // Play SE
        case 251: w.audio.stopSe()                                              // Stop SE
        case 282: w.changeTileset(p[p: 0].int)                                  // Change Tileset
        case 283: w.battle?.battleback1 = p[p: 0].string; w.battle?.battleback2 = p[p: 1].string  // Change Battle Background
        case 284: // Change Parallax [name, loopX, loopY, sx, sy]
            w.state.parallax.change(name: p[p: 0].string, loopX: p[p: 1].bool, loopY: p[p: 2].bool, sx: p[p: 3].int, sy: p[p: 4].int)
        case 285: // Get Location Info [variableId, infoType, designation, x, y]
            let direct = p[p: 2].int == 0
            var x = direct ? p[p: 3].int : w.state.variable(p[p: 3].int)
            var y = direct ? p[p: 4].int : w.state.variable(p[p: 4].int)
            if p[p: 2].int == 2, let c = character(p[p: 3].int, w) { x = c.x; y = c.y }
            let v: Int
            switch p[p: 1].int {
            case 0: v = w.terrainTag(x, y)
            case 1: v = w.events.first { $0.x == x && $0.y == y }?.eventId ?? 0
            case 2, 3, 4, 5: v = w.map.tileId(x, y, p[p: 1].int - 2)
            default: v = w.map.regionId(x, y)
            }
            w.state.setVariable(p[p: 0].int, v)
        case 301: // Battle Processing [designation, troopId, canEscape, canLose] + 601/602/603 branches
            let troopId: Int
            switch p[p: 0].int {
            case 0: troopId = p[p: 1].int
            case 1: troopId = w.state.variable(p[p: 1].int)
            default: troopId = w.map.encounterList.first?.troopId ?? 0
            }
            if w.project.troop(troopId) != nil {
                let ind = indent
                w.startBattle(troopId: troopId, canEscape: p[p: 2].bool, canLose: p[p: 3].bool) { [weak self] o in
                    self?.branch[ind] = o == .abort ? 0 : o.rawValue
                }
                waitMode = .battle
            }
        case 601: if branch[indent] != 0 { skipBranch() }                       // If Win
        case 602: if branch[indent] != 1 { skipBranch() }                       // If Escape
        case 603: if branch[indent] != 2 { skipBranch() }                       // If Lose
        case 302: // Shop Processing [kind, id, priceType, price, purchaseOnly] + 605 goods
            var goods = [p]
            while nextCode() == 605 { index += 1; goods.append(list[index].parameters) }
            w.shop = ShopState(goods: goods.map { g in
                let k = g[p: 0].int, id = g[p: 1].int
                return ShopState.Good(kind: k, id: id, price: g[p: 2].int == 0 ? ShopState.basePrice(kind: k, id: id, w.project) : g[p: 3].int)
            }, purchaseOnly: p[p: 4].bool)
            waitMode = .scene
        case 303: // Name Input Processing [actorId, maxLength]
            if w.project.actor(p[p: 0].int) != nil { w.nameInput = (p[p: 0].int, max(1, p[p: 1].int)); waitMode = .scene }
        case 311: // Change HP [designation, actorId, op, operandType, operand, allowDeath]
            let v = operand(p[p: 2].int, p[p: 3].int, p[p: 4].int, w)
            for a in actors(p[p: 0].int, p[p: 1].int, w) {
                if !p[p: 5].bool && a.hp + v <= 0 { a.setHp(max(1, a.hp + v)) } else { a.gainHp(v) }
            }
            if w.battle == nil && w.isAllDead { w.gameOver = true }
        case 312: let v = operand(p[p: 2].int, p[p: 3].int, p[p: 4].int, w); for a in actors(p[p: 0].int, p[p: 1].int, w) { a.gainMp(v) }
        case 326: let v = operand(p[p: 2].int, p[p: 3].int, p[p: 4].int, w); for a in actors(p[p: 0].int, p[p: 1].int, w) { a.gainTp(v) }
        case 313: // Change State [designation, actorId, op, stateId]
            for a in actors(p[p: 0].int, p[p: 1].int, w) { if p[p: 2].int == 0 { a.addState(p[p: 3].int) } else { a.removeState(p[p: 3].int) } }
        case 314: for a in actors(p[p: 0].int, p[p: 1].int, w) { a.recoverAll() }   // Recover All
        case 315: // Change EXP [designation, actorId, op, operandType, operand, showLevelUp]
            let v = operand(p[p: 2].int, p[p: 3].int, p[p: 4].int, w)
            for a in actors(p[p: 0].int, p[p: 1].int, w) {
                let r = a.changeExp(a.currentExp + v)
                if p[p: 5].bool && r.levels > 0 { levelUpMessage(a, r.newSkills, w) }
            }
        case 316: // Change Level
            let v = operand(p[p: 2].int, p[p: 3].int, p[p: 4].int, w)
            for a in actors(p[p: 0].int, p[p: 1].int, w) {
                let lastSkills = Set(a.learnedSkills), lv = a.level
                a.changeLevel(a.level + v)
                if p[p: 5].bool && a.level > lv { levelUpMessage(a, a.learnedSkills.filter { !lastSkills.contains($0) }, w) }
            }
        case 317: // Change Parameter [designation, actorId, paramId, op, operandType, operand]
            let v = operand(p[p: 3].int, p[p: 4].int, p[p: 5].int, w)
            for a in actors(p[p: 0].int, p[p: 1].int, w) { a.paramPlusExtra[p[p: 2].int] += v; a.refresh() }
        case 318: // Change Skill [designation, actorId, op, skillId]
            for a in actors(p[p: 0].int, p[p: 1].int, w) { if p[p: 2].int == 0 { a.learnSkill(p[p: 3].int) } else { a.forgetSkill(p[p: 3].int) } }
        case 319: // Change Equipment [actorId, etypeId, itemId]
            if let a = w.actor(p[p: 0].int) {
                let slot = max(0, p[p: 1].int - 1)
                let id = p[p: 2].int
                if id > 0 { w.state.gain(kind: slot == 0 ? 2 : 3, id: id, 1) }
                w.equip(actor: a, slot: slot, itemId: id)
            }
        case 320: w.actor(p[p: 0].int)?.setName(p[p: 1].string)                // Change Name
        case 321: w.actor(p[p: 0].int)?.changeClass(p[p: 1].int, keepExp: p[p: 2].bool)  // Change Class
        case 322: break                                                          // Change Actor Images (sheet names live in data)
        case 323: break                                                          // Change Vehicle Image
        case 324: w.actor(p[p: 0].int)?.nickname = p[p: 1].string               // Change Nickname
        case 325: break                                                          // Change Profile
        case 331, 332, 342: // Change Enemy HP/MP/TP [enemyIndex, op, operandType, operand, allowDeath]
            let v = operand(p[p: 1].int, p[p: 2].int, p[p: 3].int, w)
            for e in enemies(p[p: 0].int, w) {
                if code == 331 { if !p[p: 4].bool && e.hp + v <= 0 { e.setHp(1) } else { e.gainHp(v) } }
                else if code == 332 { e.gainMp(v) } else { e.gainTp(v) }
            }
        case 333: for e in enemies(p[p: 0].int, w) { if p[p: 1].int == 0 { e.addState(p[p: 2].int) } else { e.removeState(p[p: 2].int) } }
        case 334: for e in enemies(p[p: 0].int, w) { e.recoverAll() }
        case 335: for e in enemies(p[p: 0].int, w) { e.appear() }
        case 336: // Enemy Transform [index, enemyId]
            if let b = w.battle, let e = enemies(p[p: 0].int, w).first { b.replaceEnemy(e, with: e.transform(p[p: 1].int)) }
        case 337: // Show Battle Animation [enemyIndex, animationId, allEnemies]
            w.battle?.cueAnimation(enemyIndex: p[p: 2].bool ? -1 : p[p: 0].int, animationId: p[p: 1].int)
        case 339: // Force Action [subjectType, subjectId, skillId, targetIndex]
            w.battle?.forceAction(isEnemy: p[p: 0].int == 0, id: p[p: 1].int, skillId: p[p: 2].int, target: p[p: 3].int)
        case 340: w.battle?.abort()                                              // Abort Battle
        case 351: w.requestMenu = true; waitMode = .scene                        // Open Menu Screen
        case 352: w.requestSave = true; waitMode = .scene                        // Open Save Screen
        case 355: // Script (+ 655 lines)
            var code = p[p: 0].string + "\n"
            while nextCode() == 655 { index += 1; code += list[index].parameters[p: 0].string + "\n" }
            w.script.run(code, interpreter: self)
        case 356: // Plugin Command (MV) "name args…"
            let parts = p[p: 0].string.split(separator: " ").map(String.init)
            if let first = parts.first { w.script.emit("pluginCommandMV", [first, Array(parts.dropFirst())]) }
        case 357: // Plugin Command (MZ) [pluginName, commandName, commandText, args]
            var args: [String: JSONValue] = [:]
            if case .object(let o) = p[p: 3] { args = o }
            w.script.callPluginCommand(plugin: p[p: 0].string, command: p[p: 1].string, args: args, interpreter: self)
        case 201: // Transfer Player [designation, mapId, x, y, direction, fadeType]
            if w.message != nil { return false }
            let direct = p[p: 0].int == 0
            let m = direct ? p[p: 1].int : w.state.variable(p[p: 1].int)
            let x = direct ? p[p: 2].int : w.state.variable(p[p: 2].int)
            let y = direct ? p[p: 3].int : w.state.variable(p[p: 3].int)
            w.reserveTransfer(mapId: m, x: x, y: y, direction: p[p: 4].int, fadeType: p[p: 5].int)
            waitMode = .transfer
        case 203: // Set Event Location [id, designation, x, y, dir] — direct designation only
            if let c = character(p[p: 0].int, w), p[p: 1].int == 0 {
                c.locate(p[p: 2].int, p[p: 3].int)
                if p[p: 4].int > 0 { c.setDirection(p[p: 4].int) }
            }
        case 205: // Set Movement Route [characterId, route]
            if let c = character(p[p: 0].int, w), case .object(let r) = p[p: 1] {
                let cmds = (r["list"]?.array ?? []).compactMap { v -> EventCommand? in
                    guard case .object(let o) = v else { return nil }
                    return EventCommand(code: o["code"]?.int ?? 0, indent: 0, parameters: o["parameters"]?.array ?? [])
                }
                c.forceMoveRoute(cmds, repeat: r["repeat"]?.bool ?? false, skippable: r["skippable"]?.bool ?? false)
                if r["wait"]?.bool == true { waitMode = .route(c) }
            }
        case 211: // Change Transparency [0 = ON]
            w.player.transparent = p[p: 0].int == 0
        case 214: // Erase Event
            if let e = w.events.first(where: { $0.eventId == eventId }), mapId == w.state.mapId { e.erase() }
        case 221: // Fadeout Screen
            if w.message != nil { return false }
            w.startFade(to: 0, duration: 24); waitMode = .fade
        case 222: // Fadein Screen
            if w.message != nil { return false }
            w.startFade(to: 255, duration: 24); waitMode = .fade
        case 230: // Wait [frames]
            waitCount = p[p: 0].int
        case 353: // Game Over
            w.gameOver = true
        case 354: // Return to Title
            w.returnToTitle = true
        default:
            break // Unsupported codes are skipped, exactly like MZ when command<code> is missing.
        }
        return true
    }

    private func setupNumberInput(_ p: [JSONValue], _ m: inout GameMessage, _ w: GameWorld) {
        m.numberVariable = p[p: 0].int
        m.numberDigits = max(1, min(8, p[p: 1].int))
        m.number = max(0, min(Int(pow(10, Double(m.numberDigits))) - 1, w.state.variable(m.numberVariable)))
    }

    private func setupItemChoice(_ p: [JSONValue], _ m: inout GameMessage, _ w: GameWorld) {
        m.itemChoiceVariable = p[p: 0].int
        m.itemChoiceType = max(1, p[p: 1].int)
        m.itemChoices = w.state.items.keys.sorted().filter { w.project.item($0)?.itypeId == m.itemChoiceType }
    }

    private func picturePoint(_ p: [JSONValue], _ w: GameWorld) -> (Double, Double) {
        switch p[p: 3].int {
        case 0: return (Double(p[p: 4].int), Double(p[p: 5].int))
        case 1: return (Double(w.state.variable(p[p: 4].int)), Double(w.state.variable(p[p: 5].int)))
        default: return (Double(p[p: 4].int), Double(p[p: 5].int))
        }
    }

    /// iterateActorEx: designation 0 = fixed actor (0 → whole party), 1 = actor id from a variable.
    private func actors(_ designation: Int, _ id: Int, _ w: GameWorld) -> [GameActor] {
        let actorId = designation == 0 ? id : w.state.variable(id)
        return actorId == 0 ? w.allMembers : (w.actor(actorId).map { [$0] } ?? [])
    }
    private func enemies(_ index: Int, _ w: GameWorld) -> [GameEnemy] {
        guard let b = w.battle else { return [] }
        return index < 0 ? b.enemies : (index < b.enemies.count ? [b.enemies[index]] : [])
    }

    private func levelUpMessage(_ a: GameActor, _ skills: [Int], _ w: GameWorld) {
        let t = w.project.system.terms
        w.addScriptMessage(t.message("levelUp", a.name, t.basic[0], String(a.level)))
        for s in skills { if let sk = w.project.skill(s) { w.addScriptMessage(t.message("obtainSkill", sk.name)) } }
        waitMode = .message
    }

    /// Control Variables "Game Data" operand (Game_Interpreter.gameDataOperand).
    private func gameData(_ type: Int, _ p1: Int, _ p2: Int, _ w: GameWorld) -> Int {
        switch type {
        case 0: return w.state.count(kind: 1, id: p1)
        case 1: return w.state.count(kind: 2, id: p1)
        case 2: return w.state.count(kind: 3, id: p1)
        case 3:
            guard let a = w.actor(p1) else { return 0 }
            switch p2 {
            case 0: return a.level
            case 1: return a.currentExp
            case 2: return a.hp
            case 3: return a.mp
            case 4...11: return a.param(p2 - 4)
            case 12: return a.tp
            default: return 0
            }
        case 4:
            guard let b = w.battle, p1 < b.enemies.count else { return 0 }
            let e = b.enemies[p1]
            switch p2 { case 0: return e.hp; case 1: return e.mp; case 2...9: return e.param(p2 - 2); case 10: return e.tp; default: return 0 }
        case 5:
            guard let c = character(p1, w) else { return 0 }
            switch p2 { case 0: return c.x; case 1: return c.y; case 2: return c.direction
            case 3: return Int(c.realX * 48 + 24); case 4: return Int(c.realY * 48 + 48); default: return 0 }
        case 6: return w.state.party[safe: p1].flatMap { w.actor($0)?.actorId } ?? 0
        case 7:
            switch p1 {
            case 0: return w.state.mapId
            case 1: return w.state.party.count
            case 2: return w.state.gold
            case 3: return w.state.steps
            case 4: return w.state.playFrames / 60
            case 6: return w.state.saveCount
            case 7: return w.state.battleCount
            case 8: return w.state.winCount
            case 9: return w.state.escapeCount
            default: return 0
            }
        case 8: return w.lastActionData(p1)
        default: return 0
        }
    }

    private func setupChoices(_ p: [JSONValue], _ m: inout GameMessage, _ w: GameWorld) {
        let choices = p[p: 0].array.map { w.convertEscapes($0.string) }
        let cancelType = p[p: 1].int
        m.choices = choices
        m.choiceCancel = cancelType < choices.count ? cancelType : -2
        m.choiceDefault = max(0, min(choices.count - 1, p[p: 2].int))
        m.choiceIndex = m.choiceDefault
        let ind = indent
        m.onChoose = { [weak self] n in self?.branch[ind] = n }
    }

    private func conditionalBranch(_ p: [JSONValue], _ w: GameWorld) -> Bool {
        switch p[p: 0].int {
        case 0: return w.state.switchValue(p[p: 1].int) == (p[p: 2].int == 0)
        case 1:
            let a = w.state.variable(p[p: 1].int)
            let b = p[p: 2].int == 0 ? p[p: 3].int : w.state.variable(p[p: 3].int)
            switch p[p: 4].int {
            case 0: return a == b
            case 1: return a >= b
            case 2: return a <= b
            case 3: return a > b
            case 4: return a < b
            default: return a != b
            }
        case 2: return eventId > 0 && w.state.selfSwitch(mapId, eventId, p[p: 1].string) == (p[p: 2].int == 0)
        case 4: // Actor [4, actorId, type, value]
            guard let a = w.actor(p[p: 1].int) else { return false }
            switch p[p: 2].int {
            case 0: return w.state.party.contains(a.actorId)
            case 1: return a.name == p[p: 3].string
            case 2: return a.classId == p[p: 3].int
            case 3: return a.learnedSkills.contains(p[p: 3].int)
            case 4: return a.equips.first == p[p: 3].int
            case 5: return a.equips.dropFirst().contains(p[p: 3].int)
            case 6: return a.isStateAffected(p[p: 3].int)
            default: return false
            }
        case 5: // Enemy [5, index, 0 appeared / 1 state, stateId]
            guard let b = w.battle, p[p: 1].int < b.enemies.count else { return false }
            let e = b.enemies[p[p: 1].int]
            return p[p: 2].int == 0 ? e.isAlive : e.isStateAffected(p[p: 3].int)
        case 9: // Weapon [9, id, includeEquipped]
            return w.state.count(kind: 2, id: p[p: 1].int) > 0 || (p[p: 2].bool && w.partyMembers.contains { $0.equips.first == p[p: 1].int })
        case 10: // Armor
            return w.state.count(kind: 3, id: p[p: 1].int) > 0 || (p[p: 2].bool && w.partyMembers.contains { $0.equips.dropFirst().contains(p[p: 1].int) })
        case 11: // Button [11, name, 0 pressed / 1 triggered / 2 repeated]
            let name = p[p: 1].string
            let i = w.lastInput
            switch name {
            case "ok": return i.ok || i.held.contains("ok")
            case "cancel": return i.cancel || i.held.contains("cancel")
            default: return i.held.contains(name)
            }
        case 12: return w.script.evalBool(p[p: 1].string, interpreter: self)
        case 13: return w.state.vehicleType == p[p: 1].int
        case 6: // Character facing [characterId, direction]
            return character(p[p: 1].int, w)?.direction == p[p: 2].int
        case 7:
            let g = w.state.gold, v = p[p: 1].int
            switch p[p: 2].int { case 0: return g >= v; case 1: return g <= v; default: return g < v }
        case 8: return w.state.itemCount(p[p: 1].int) > 0
        default: return false
        }
    }
}
