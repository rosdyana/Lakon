import Foundation
import JavaScriptCore

/// JavaScript for damage formulas (`a.atk * 4 - b.def * 2`), the Script command (355/655), script conditions,
/// script variable operands, move-route scripts, and plugins. Runs on macOS's built-in JavaScriptCore.
///
/// Exposes an MZ-shaped subset: $gameVariables, $gameSwitches, $gameSelfSwitches, $gameParty, $gameActors,
/// $gamePlayer, $gameMap, $gameMessage, $gameScreen, $gameTemp, AudioManager, PluginManager.registerCommand,
/// $dataActors/$dataItems/$dataWeapons/$dataArmors/$dataSkills/$dataEnemies/$dataStates/$dataSystem, Math.randomInt.
/// MZ plugins that patch Scene_/Window_/Sprite_ classes cannot run (there is no PixiJS runtime); plugins that only
/// use the API above and PluginManager.registerCommand do.
public final class ScriptEngine {
    let ctx: JSContext
    weak var world: GameWorld?
    /// Interpreter currently running a script (for `this.wait(n)`, `this.eventId()`).
    weak var currentInterpreter: Interpreter?
    public private(set) var log: [String] = []
    public private(set) var loadedPlugins: [String] = []

    init(world: GameWorld) {
        self.world = world
        ctx = JSContext()!
        ctx.name = "Lakon"
        ctx.exceptionHandler = { [weak self] _, exc in self?.appendLog("[js error] \(exc?.toString() ?? "?")") }
        installBridge()
        ctx.evaluateScript(Self.prelude)
        installData()
    }

    func appendLog(_ s: String) {
        log.append(s)
        if log.count > 200 { log.removeFirst(log.count - 200) }
        #if DEBUG
        print(s)
        #endif
    }

    // MARK: public entry points

    @discardableResult
    func run(_ code: String, interpreter: Interpreter?) -> JSValue? {
        currentInterpreter = interpreter
        defer { currentInterpreter = nil }
        let fn = ctx.objectForKeyedSubscript("__runScript")
        return fn?.call(withArguments: [code, interpreterProxy(interpreter)])
    }

    func evalBool(_ code: String, interpreter: Interpreter?) -> Bool {
        run("return !!(" + code + ")", interpreter: interpreter)?.toBool() ?? false
    }
    func evalNumber(_ code: String, interpreter: Interpreter?) -> Int {
        let v = run("return (" + code + ")", interpreter: interpreter)
        guard let v, v.isNumber else { return 0 }
        let d = v.toDouble()
        return d.isFinite ? Int(d) : 0
    }

    func evalFormula(_ formula: String, a: GameBattler, b: GameBattler) -> Double {
        let fa = battlerObject(a), fb = battlerObject(b)
        let r = ctx.objectForKeyedSubscript("__formula")?.call(withArguments: [formula, fa, fb])
        let d = r?.toDouble() ?? 0
        return d.isFinite ? d : 0
    }

    func callPluginCommand(plugin: String, command: String, args: [String: JSONValue], interpreter: Interpreter?) {
        currentInterpreter = interpreter
        defer { currentInterpreter = nil }
        let obj = JSValue(object: args.mapValues { $0.string }, in: ctx)!
        ctx.objectForKeyedSubscript("PluginManager")?.invokeMethod("callCommand", withArguments: [interpreterProxy(interpreter), plugin, command, obj])
    }

    /// Lakon.on(name, fn) hooks: "mapStart", "update", "battleStart", "battleEnd".
    func emit(_ event: String, _ args: [Any] = []) {
        ctx.objectForKeyedSubscript("Lakon")?.invokeMethod("_emit", withArguments: [event] + args)
    }

    /// Loads plugins/plugins.json ([{name, status, parameters}] like MZ's $plugins) and plugins/<name>.js.
    /// Without plugins.json, every plugins/*.js loads in name order.
    func loadPlugins(from project: Project) {
        let dir = project.root.appendingPathComponent("plugins")
        var entries: [(String, [String: String])] = []
        if let data = try? Data(contentsOf: dir.appendingPathComponent("plugins.json")),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for e in list where (e["status"] as? Bool) ?? true {
                if let n = e["name"] as? String { entries.append((n, (e["parameters"] as? [String: String]) ?? [:])) }
            }
        } else {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".js") }.sorted()
            entries = files.map { (String($0.dropLast(3)), [:]) }
        }
        for (name, params) in entries {
            guard let src = try? String(contentsOf: dir.appendingPathComponent(name + ".js"), encoding: .utf8) else {
                appendLog("[plugin] missing \(name).js"); continue
            }
            ctx.objectForKeyedSubscript("PluginManager")?.objectForKeyedSubscript("_params")?
                .setObject(params, forKeyedSubscript: name as NSString)
            ctx.objectForKeyedSubscript("__setCurrentPlugin")?.call(withArguments: [name])
            ctx.evaluateScript(src, withSourceURL: dir.appendingPathComponent(name + ".js"))
            loadedPlugins.append(name)
            appendLog("[plugin] loaded \(name)")
        }
    }

    // MARK: object marshalling

    func battlerObject(_ b: GameBattler) -> JSValue {
        var d: [String: Any] = [
            "hp": b.hp, "mp": b.mp, "tp": b.tp, "mhp": b.mhp, "mmp": b.mmp, "atk": b.atk, "def": b.def, "mat": b.mat,
            "mdf": b.mdf, "agi": b.agi, "luk": b.luk, "hit": b.hit, "eva": b.eva, "cri": b.cri, "states": b.states,
            "name": b.name, "_isActor": b.isActor, "level": 1,
        ]
        if let a = b as? GameActor { d["level"] = a.level; d["actorId"] = a.actorId }
        if let e = b as? GameEnemy { d["enemyId"] = e.enemyId; d["index"] = e.index }
        return ctx.objectForKeyedSubscript("__mkBattler").call(withArguments: [d])
    }

    func interpreterProxy(_ i: Interpreter?) -> Any {
        let d: [String: Any] = ["_eventId": i?.eventId ?? 0, "_mapId": i?.mapId ?? 0]
        return ctx.objectForKeyedSubscript("__mkInterpreter").call(withArguments: [d]) as Any
    }

    private func installData() {
        guard let p = world?.project else { return }
        func json<T: Encodable>(_ v: T) -> String { (try? String(data: JSONEncoder().encode(v), encoding: .utf8) ?? "null") ?? "null" }
        let sets: [(String, String)] = [
            ("$dataActors", json(p.actors)), ("$dataItems", json(p.items)), ("$dataWeapons", json(p.weapons)),
            ("$dataArmors", json(p.armors)), ("$dataSkills", json(p.skills)), ("$dataEnemies", json(p.enemies)),
            ("$dataStates", json(p.states)), ("$dataClasses", json(p.classes)), ("$dataSystem", json(p.system)),
            ("$dataCommonEvents", json(p.commonEvents)), ("$dataTroops", json(p.troops)),
        ]
        for (name, s) in sets {
            ctx.setObject(s, forKeyedSubscript: "__tmp" as NSString)
            ctx.evaluateScript("var \(name) = JSON.parse(__tmp);")
        }
    }

    // MARK: bridge

    private func fn(_ name: String, _ f: @escaping ([JSValue]) -> Any) {
        let block: @convention(block) () -> Any = {
            let args = (JSContext.currentArguments() as? [JSValue]) ?? []
            return f(args)
        }
        ctx.setObject(block, forKeyedSubscript: name as NSString)
    }

    private func installBridge() {
        func i(_ a: [JSValue], _ n: Int) -> Int { n < a.count ? Int(a[n].toInt32()) : 0 }
        func d(_ a: [JSValue], _ n: Int) -> Double { n < a.count ? a[n].toDouble() : 0 }
        func s(_ a: [JSValue], _ n: Int) -> String { n < a.count ? (a[n].toString() ?? "") : "" }
        func b(_ a: [JSValue], _ n: Int) -> Bool { n < a.count ? a[n].toBool() : false }

        fn("__log") { [weak self] a in self?.appendLog(s(a, 0)); return NSNull() }
        fn("__var") { [weak self] a in self?.world?.state.variable(i(a, 0)) ?? 0 }
        fn("__setVar") { [weak self] a in
            let v = a.count > 1 ? a[1] : JSValue()
            self?.world?.state.setVariable(i(a, 0), v.isNumber ? Int(v.toDouble()) : (v.isBoolean ? (v.toBool() ? 1 : 0) : Int(v.toString() ?? "") ?? 0))
            return NSNull()
        }
        fn("__sw") { [weak self] a in self?.world?.state.switchValue(i(a, 0)) ?? false }
        fn("__setSw") { [weak self] a in self?.world?.state.setSwitch(i(a, 0), b(a, 1)); return NSNull() }
        fn("__selfSw") { [weak self] a in self?.world?.state.selfSwitch(i(a, 0), i(a, 1), s(a, 2)) ?? false }
        fn("__setSelfSw") { [weak self] a in self?.world?.state.setSelfSwitch(i(a, 0), i(a, 1), s(a, 2), b(a, 3)); return NSNull() }
        fn("__gold") { [weak self] _ in self?.world?.state.gold ?? 0 }
        fn("__gainGold") { [weak self] a in self?.world?.state.gainGold(i(a, 0)); return NSNull() }
        fn("__party") { [weak self] _ in self?.world?.state.party ?? [] }
        fn("__partyAdd") { [weak self] a in self?.world?.addActor(i(a, 0)); return NSNull() }
        fn("__partyRemove") { [weak self] a in self?.world?.removeActor(i(a, 0)); return NSNull() }
        fn("__numItems") { [weak self] a in self?.world?.state.count(kind: i(a, 0), id: i(a, 1)) ?? 0 }
        fn("__gainItem") { [weak self] a in self?.world?.state.gain(kind: i(a, 0), id: i(a, 1), i(a, 2)); return NSNull() }
        fn("__inBattle") { [weak self] _ in self?.world?.battle != nil }
        fn("__actorExists") { [weak self] a in self?.world?.project.actor(i(a, 0)) != nil }
        fn("__a") { [weak self] a in
            guard let actor = self?.world?.actor(i(a, 0)) else { return NSNull() }
            switch s(a, 1) {
            case "name": return actor.name
            case "nickname": return actor.nickname
            case "level": return actor.level
            case "exp": return actor.currentExp
            case "classId": return actor.classId
            case "isDead": return actor.isDead
            case "isStateAffected": return actor.isStateAffected(i(a, 2))
            case "hasSkill": return actor.learnedSkills.contains(i(a, 2))
            case "hp": return actor.hp
            case "mp": return actor.mp
            case "tp": return actor.tp
            case let k: return ["mhp": 0, "mmp": 1, "atk": 2, "def": 3, "mat": 4, "mdf": 5, "agi": 6, "luk": 7][k].map { actor.param($0) } ?? NSNull()
            }
        }
        fn("__aCall") { [weak self] a in
            guard let actor = self?.world?.actor(i(a, 0)) else { return NSNull() }
            switch s(a, 1) {
            case "setName": actor.setName(s(a, 2))
            case "setNickname": actor.nickname = s(a, 2)
            case "gainHp": actor.gainHp(i(a, 2))
            case "gainMp": actor.gainMp(i(a, 2))
            case "gainTp": actor.gainTp(i(a, 2))
            case "setHp": actor.setHp(i(a, 2))
            case "setMp": actor.setMp(i(a, 2))
            case "recoverAll": actor.recoverAll()
            case "addState": actor.addState(i(a, 2))
            case "removeState": actor.removeState(i(a, 2))
            case "learnSkill": actor.learnSkill(i(a, 2))
            case "forgetSkill": actor.forgetSkill(i(a, 2))
            case "changeExp": actor.changeExp(i(a, 2))
            case "changeLevel": actor.changeLevel(i(a, 2))
            default: break
            }
            return NSNull()
        }
        fn("__player") { [weak self] a in
            guard let p = self?.world?.player else { return 0 }
            switch s(a, 0) { case "x": return p.x; case "y": return p.y; case "d": return p.direction; default: return self?.world?.vehicleTypeName ?? "walk" }
        }
        fn("__playerLocate") { [weak self] a in self?.world?.player.locate(i(a, 0), i(a, 1)); return NSNull() }
        fn("__transfer") { [weak self] a in
            self?.world?.reserveTransfer(mapId: i(a, 0), x: i(a, 1), y: i(a, 2), direction: i(a, 3), fadeType: i(a, 4)); return NSNull()
        }
        fn("__map") { [weak self] a in
            guard let w = self?.world else { return 0 }
            switch s(a, 0) { case "id": return w.state.mapId; case "w": return w.map.width; case "h": return w.map.height; default: return w.map.displayName }
        }
        fn("__region") { [weak self] a in self?.world?.map.regionId(i(a, 0), i(a, 1)) ?? 0 }
        fn("__ev") { [weak self] a in
            guard let e = self?.world?.events.first(where: { $0.eventId == i(a, 0) }) else { return NSNull() }
            switch s(a, 1) { case "x": return e.x; case "y": return e.y; case "d": return e.direction; default: return NSNull() }
        }
        fn("__evDo") { [weak self] a in
            guard let e = self?.world?.events.first(where: { $0.eventId == i(a, 0) }) else { return NSNull() }
            switch s(a, 1) {
            case "locate": e.locate(i(a, 2), i(a, 3))
            case "dir": e.setDirection(i(a, 2))
            case "erase": e.erase()
            default: break
            }
            return NSNull()
        }
        fn("__msg") { [weak self] a in self?.world?.addScriptMessage(s(a, 0)); return NSNull() }
        fn("__screen") { [weak self] a in
            guard let w = self?.world else { return NSNull() }
            let arr = a.count > 1 ? (a[1].toArray() ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 } : []
            let dur = i(a, 2)
            switch s(a, 0) {
            case "tint": w.screen.startTint(arr + Array(repeating: 0, count: max(0, 4 - arr.count)), duration: dur)
            case "flash": w.screen.startFlash(arr + Array(repeating: 0, count: max(0, 4 - arr.count)), duration: dur)
            case "shake": w.screen.startShake(power: Int(arr.first ?? 5), speed: Int(arr.dropFirst().first ?? 5), duration: dur)
            case "weather": w.screen.changeWeather(["none", "rain", "storm", "snow"][min(3, Int(arr.first ?? 0))], power: Int(arr.dropFirst().first ?? 5), duration: dur)
            default: break
            }
            return NSNull()
        }
        fn("__weather") { [weak self] a in self?.world?.screen.changeWeather(s(a, 0), power: i(a, 1), duration: i(a, 2)); return NSNull() }
        fn("__commonEvent") { [weak self] a in self?.world?.reserveCommonEvent(i(a, 0)); return NSNull() }
        fn("__audio") { [weak self] a in
            guard let w = self?.world else { return NSNull() }
            let obj = a.count > 1 ? a[1] : JSValue()
            let file = AudioFile(obj.forProperty("name")?.toString() ?? "",
                                 volume: obj.hasProperty("volume") ? Int(obj.forProperty("volume").toInt32()) : 90,
                                 pitch: obj.hasProperty("pitch") ? Int(obj.forProperty("pitch").toInt32()) : 100,
                                 pan: obj.hasProperty("pan") ? Int(obj.forProperty("pan").toInt32()) : 0)
            switch s(a, 0) {
            case "se": w.audio.playSe(file)
            case "bgm": w.audio.playBgm(file)
            case "bgs": w.audio.playBgs(file)
            case "me": w.audio.playMe(file)
            case "stopbgm": w.audio.stopBgm()
            case "fadebgm": w.audio.fadeOutBgm(Int(obj.forProperty("volume")?.toInt32() ?? 1))
            default: break
            }
            return NSNull()
        }
        fn("__wait") { [weak self] a in self?.currentInterpreter?.waitCount = i(a, 0); return NSNull() }
        fn("__setCurrentPlugin") { _ in NSNull() }
    }

    static let prelude = #"""
    var console = { log: (...a) => __log(a.map(String).join(' ')), warn: (...a) => __log('[warn] ' + a.join(' ')), error: (...a) => __log('[error] ' + a.join(' ')) };
    Math.randomInt = n => Math.floor(Math.random() * n);
    Number.prototype.clamp = function(a, b) { return Math.min(Math.max(this, a), b); };
    var Lakon = { _hooks: {}, on(e, f) { (this._hooks[e] = this._hooks[e] || []).push(f); },
      _emit(e, ...args) { for (const f of (this._hooks[e] || [])) { try { f(...args); } catch (x) { __log('[js error] ' + e + ': ' + x); } } } };
    var PluginManager = { _commands: {}, _params: {},
      registerCommand(p, c, f) { this._commands[p + ':' + c] = f; },
      parameters(n) { return this._params[n] || {}; },
      callCommand(self, p, c, args) { const f = this._commands[p + ':' + c]; if (f) f.call(self, args); else __log('[plugin] no command ' + p + ':' + c); } };
    var $gameVariables = { value: id => __var(id), setValue: (id, v) => __setVar(id, v),
      _data: new Proxy({}, { get: (t, k) => __var(Number(k)), set: (t, k, v) => { __setVar(Number(k), v); return true; } }) };
    var $gameSwitches = { value: id => __sw(id), setValue: (id, v) => __setSw(id, !!v) };
    var $gameSelfSwitches = { value: k => __selfSw(k[0], k[1], k[2]), setValue: (k, v) => __setSelfSw(k[0], k[1], k[2], !!v) };
    class Game_Actor {
      constructor(id) { this._actorId = id; }
      actorId() { return this._actorId; }
      name() { return __a(this._actorId, 'name'); }
      nickname() { return __a(this._actorId, 'nickname'); }
      get level() { return __a(this._actorId, 'level'); }
      get hp() { return __a(this._actorId, 'hp'); } get mp() { return __a(this._actorId, 'mp'); } get tp() { return __a(this._actorId, 'tp'); }
      get mhp() { return __a(this._actorId, 'mhp'); } get mmp() { return __a(this._actorId, 'mmp'); }
      get atk() { return __a(this._actorId, 'atk'); } get def() { return __a(this._actorId, 'def'); }
      get mat() { return __a(this._actorId, 'mat'); } get mdf() { return __a(this._actorId, 'mdf'); }
      get agi() { return __a(this._actorId, 'agi'); } get luk() { return __a(this._actorId, 'luk'); }
      currentExp() { return __a(this._actorId, 'exp'); }
      isDead() { return __a(this._actorId, 'isDead'); } isAlive() { return !this.isDead(); }
      isStateAffected(s) { return __a(this._actorId, 'isStateAffected', s); }
      hasSkill(s) { return __a(this._actorId, 'hasSkill', s); }
      setName(n) { __aCall(this._actorId, 'setName', n); } setNickname(n) { __aCall(this._actorId, 'setNickname', n); }
      gainHp(v) { __aCall(this._actorId, 'gainHp', v); } gainMp(v) { __aCall(this._actorId, 'gainMp', v); } gainTp(v) { __aCall(this._actorId, 'gainTp', v); }
      setHp(v) { __aCall(this._actorId, 'setHp', v); } setMp(v) { __aCall(this._actorId, 'setMp', v); }
      recoverAll() { __aCall(this._actorId, 'recoverAll'); }
      addState(s) { __aCall(this._actorId, 'addState', s); } removeState(s) { __aCall(this._actorId, 'removeState', s); }
      learnSkill(s) { __aCall(this._actorId, 'learnSkill', s); } forgetSkill(s) { __aCall(this._actorId, 'forgetSkill', s); }
      changeExp(v) { __aCall(this._actorId, 'changeExp', v); } changeLevel(v) { __aCall(this._actorId, 'changeLevel', v); }
    }
    var $gameActors = { actor: id => __actorExists(id) ? new Game_Actor(id) : null };
    function __kind(it) { return it == null ? 1 : (it.wtypeId !== undefined ? 2 : (it.atypeId !== undefined ? 3 : 1)); }
    var $gameParty = {
      gold: () => __gold(), gainGold: n => __gainGold(n), loseGold: n => __gainGold(-n),
      members: () => __party().map(id => new Game_Actor(id)), battleMembers() { return this.members(); },
      leader() { return this.members()[0] || null; }, size: () => __party().length,
      numItems: it => it ? __numItems(__kind(it), it.id) : 0, hasItem: it => !!it && __numItems(__kind(it), it.id) > 0,
      gainItem: (it, n) => __gainItem(__kind(it), it.id, n), loseItem: (it, n) => __gainItem(__kind(it), it.id, -n),
      addActor: id => __partyAdd(id), removeActor: id => __partyRemove(id), inBattle: () => __inBattle() };
    var $gamePlayer = { get x() { return __player('x'); }, get y() { return __player('y'); }, direction: () => __player('d'),
      locate: (x, y) => __playerLocate(x, y), reserveTransfer: (m, x, y, d, f) => __transfer(m, x, y, d || 0, f || 0),
      isInVehicle: () => __player('v') !== 'walk' };
    var $gameMap = { mapId: () => __map('id'), width: () => __map('w'), height: () => __map('h'), displayName: () => __map('name'),
      regionId: (x, y) => __region(x, y),
      event: id => __ev(id, 'x') === null ? null : { eventId: () => id, get x() { return __ev(id, 'x'); }, get y() { return __ev(id, 'y'); },
        direction: () => __ev(id, 'd'), locate: (x, y) => __evDo(id, 'locate', x, y), setDirection: d => __evDo(id, 'dir', d), erase: () => __evDo(id, 'erase') } };
    var $gameMessage = { add: t => __msg(String(t)) };
    var $gameScreen = { startTint: (t, d) => __screen('tint', t, d), startFlash: (c, d) => __screen('flash', c, d),
      startShake: (p, s, d) => __screen('shake', [p, s], d), changeWeather: (t, p, d) => __weather(String(t), p, d) };
    var $gameTemp = { reserveCommonEvent: id => __commonEvent(id) };
    var AudioManager = { playSe: a => __audio('se', a), playBgm: a => __audio('bgm', a), playBgs: a => __audio('bgs', a), playMe: a => __audio('me', a),
      stopBgm: () => __audio('stopbgm', {}), fadeOutBgm: s => __audio('fadebgm', { volume: s }) };
    function __mkBattler(o) {
      o.isStateAffected = id => o.states.indexOf(id) >= 0; o.isActor = () => o._isActor; o.isEnemy = () => !o._isActor;
      o.isDead = () => o.hp <= 0; o.isAlive = () => o.hp > 0; return o;
    }
    function __mkInterpreter(o) {
      o.eventId = () => o._eventId; o.wait = n => __wait(n);
      o.character = id => id < 0 ? $gamePlayer : $gameMap.event(id === 0 ? o._eventId : id);
      return o;
    }
    function __formula(f, a, b) { const v = $gameVariables._data; try { const r = Math.max(eval(f), 0); return isNaN(r) ? 0 : r; } catch (e) { __log('[formula] ' + f + ': ' + e); return 0; } }
    function __runScript(code, self) { return (new Function(code)).call(self); }
    """#
}
