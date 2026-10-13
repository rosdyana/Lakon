// Lakon web runtime — scripts and plugins. Port of Sources/LakonCore/ScriptEngine.swift: the same MZ-shaped
// API ($gameVariables, $gameSwitches, $gameParty, $gameActors, $gamePlayer, $gameMap, $gameMessage, $gameScreen,
// $gameTemp, AudioManager, PluginManager.registerCommand, Lakon.on hooks, $data*), here backed directly by GameWorld.
"use strict";
(function (LK) {
  const G = typeof globalThis !== "undefined" ? globalThis : window;

  class ScriptEngine {
    constructor(world) {
      this.world = world; this.log = []; this.loadedPlugins = []; this.currentInterpreter = null;
      this.hooks = {}; this.commands = {}; this.params = {};
      this.install();
    }
    appendLog(s) { this.log.push(s); if (this.log.length > 200) this.log.splice(0, this.log.length - 200); if (G.LAKON_DEBUG) console.log(s); }

    install() {
      const eng = this, w = () => this.world;
      const state = () => w().state;
      class Game_Actor {
        constructor(id) { this._actorId = id; }
        get _a() { return w().actor(this._actorId); }
        actorId() { return this._actorId; }
        name() { return this._a.name; } nickname() { return this._a.nickname; }
        get level() { return this._a.level; } get hp() { return this._a.hp; } get mp() { return this._a.mp; } get tp() { return this._a.tp; }
        get mhp() { return this._a.mhp; } get mmp() { return this._a.mmp; } get atk() { return this._a.atk; } get def() { return this._a.def; }
        get mat() { return this._a.mat; } get mdf() { return this._a.mdf; } get agi() { return this._a.agi; } get luk() { return this._a.luk; }
        currentExp() { return this._a.currentExp; } isDead() { return this._a.isDead; } isAlive() { return !this._a.isDead; }
        isStateAffected(s) { return this._a.isStateAffected(s); } hasSkill(s) { return this._a.learnedSkills.includes(s); }
        setName(n) { this._a.setName(String(n)); } setNickname(n) { this._a.nickname = String(n); }
        gainHp(v) { this._a.gainHp(Math.trunc(v)); } gainMp(v) { this._a.gainMp(Math.trunc(v)); } gainTp(v) { this._a.gainTp(Math.trunc(v)); }
        setHp(v) { this._a.setHp(Math.trunc(v)); } setMp(v) { this._a.setMp(Math.trunc(v)); } recoverAll() { this._a.recoverAll(); }
        addState(s) { this._a.addState(s); } removeState(s) { this._a.removeState(s); } learnSkill(s) { this._a.learnSkill(s); } forgetSkill(s) { this._a.forgetSkill(s); }
        changeExp(v) { this._a.changeExp(Math.trunc(v)); } changeLevel(v) { this._a.changeLevel(Math.trunc(v)); }
      }
      const kind = it => (it == null ? 1 : it.wtypeId !== undefined && it.etypeId === 1 ? 2 : it.atypeId !== undefined && it.etypeId !== undefined ? 3 : 1);
      const toInt = x => (typeof x === "number" ? Math.trunc(x) : typeof x === "boolean" ? (x ? 1 : 0) : (parseInt(String(x), 10) || 0));
      const audio = o => ({ name: String((o && o.name) || ""), volume: o && o.volume !== undefined ? toInt(o.volume) : 90, pitch: o && o.pitch !== undefined ? toInt(o.pitch) : 100, pan: o && o.pan !== undefined ? toInt(o.pan) : 0 });
      const api = {
        console: G.console,
        Lakon: { on: (e, f) => { (eng.hooks[e] = eng.hooks[e] || []).push(f); } },
        PluginManager: { registerCommand: (p, c, f) => { eng.commands[p + ":" + c] = f; }, parameters: n => eng.params[n] || {} },
        $gameVariables: { value: id => state().variable(id), setValue: (id, v) => state().setVariable(id, toInt(v)),
          _data: new Proxy({}, { get: (t, k) => state().variable(Number(k)), set: (t, k, v) => { state().setVariable(Number(k), toInt(v)); return true; } }) },
        $gameSwitches: { value: id => state().switchValue(id), setValue: (id, v) => state().setSwitch(id, !!v) },
        $gameSelfSwitches: { value: k => state().selfSwitch(k[0], k[1], k[2]), setValue: (k, v) => state().setSelfSwitch(k[0], k[1], k[2], !!v) },
        $gameActors: { actor: id => (w().project.actor(id) ? new Game_Actor(id) : null) },
        $gameParty: {
          gold: () => state().gold, gainGold: n => state().gainGold(toInt(n)), loseGold: n => state().gainGold(-toInt(n)),
          members: () => state().party.map(id => new Game_Actor(id)), battleMembers() { return this.members(); },
          leader() { return this.members()[0] || null; }, size: () => state().party.length,
          numItems: it => (it ? state().count(kind(it), it.id) : 0), hasItem: it => !!it && state().count(kind(it), it.id) > 0,
          gainItem: (it, n) => state().gain(kind(it), it.id, toInt(n)), loseItem: (it, n) => state().gain(kind(it), it.id, -toInt(n)),
          addActor: id => w().addActor(id), removeActor: id => w().removeActor(id), inBattle: () => !!w().battle,
        },
        $gamePlayer: { get x() { return w().player.x; }, get y() { return w().player.y; }, direction: () => w().player.direction,
          locate: (x, y) => w().player.locate(x, y), reserveTransfer: (m, x, y, d, f) => w().reserveTransfer(m, x, y, d || 0, f || 0),
          isInVehicle: () => w().vehicleTypeName !== "walk" },
        $gameMap: { mapId: () => state().mapId, width: () => w().map.width, height: () => w().map.height, displayName: () => w().map.displayName,
          regionId: (x, y) => LK.MapUtil.regionId(w().map, x, y),
          event: id => { const e = w().events.find(ev => ev.eventId === id); if (!e) return null;
            return { eventId: () => id, get x() { return e.x; }, get y() { return e.y; }, direction: () => e.direction,
              locate: (x, y) => e.locate(x, y), setDirection: d => e.setDirection(d), erase: () => e.erase() }; } },
        $gameMessage: { add: t => w().addScriptMessage(String(t)) },
        $gameScreen: { startTint: (t, d) => w().screen.startTint(pad4(t), d), startFlash: (c, d) => w().screen.startFlash(pad4(c), d),
          startShake: (p, s, d) => w().screen.startShake(p, s, d), changeWeather: (t, p, d) => w().screen.changeWeather(String(t), p, d) },
        $gameTemp: { reserveCommonEvent: id => w().reserveCommonEvent(id) },
        AudioManager: { playSe: a => w().audio.playSe(audio(a)), playBgm: a => w().audio.playBgm(audio(a)), playBgs: a => w().audio.playBgs(audio(a)),
          playMe: a => w().audio.playMe(audio(a)), stopBgm: () => w().audio.stopBgm(), fadeOutBgm: s => w().audio.fadeOutBgm(toInt(s)) },
        Game_Actor,
      };
      const pad4 = a => { const r = (a || []).map(Number); while (r.length < 4) r.push(0); return r; };
      const p = w().project;
      Object.assign(api, { $dataActors: p.actors, $dataItems: p.items, $dataWeapons: p.weapons, $dataArmors: p.armors, $dataSkills: p.skills,
        $dataEnemies: p.enemies, $dataStates: p.states, $dataClasses: p.classes, $dataSystem: p.system, $dataCommonEvents: p.commonEvents, $dataTroops: p.troops,
        $dataAnimations: p.animations });
      if (!Math.randomInt) Math.randomInt = n => Math.floor(Math.random() * n);
      // eslint-disable-next-line no-extend-native
      if (!Number.prototype.clamp) Number.prototype.clamp = function (a, b) { return Math.min(Math.max(this, a), b); };
      this.api = api;
      this.names = Object.keys(api);
    }
    /// Scripts see the API as free variables (like MZ's globals) without leaking into the page's globals.
    compile(body) { return new Function(...this.names, body); }
    call(fn, self, extra) { return fn.apply(self, this.names.map(n => this.api[n]).concat(extra || [])); }

    interpreterProxy(i) {
      const eng = this;
      return { _eventId: i ? i.eventId : 0, _mapId: i ? i.mapId : 0, eventId() { return this._eventId; },
        wait: n => { if (eng.currentInterpreter) eng.currentInterpreter.waitCount = Math.trunc(n); },
        character: id => (id < 0 ? eng.api.$gamePlayer : eng.api.$gameMap.event(id === 0 ? (i ? i.eventId : 0) : id)) };
    }
    run(code, interp) {
      this.currentInterpreter = interp;
      try { return this.call(this.compile(code), this.interpreterProxy(interp)); }
      catch (e) { this.appendLog("[js error] " + e); return undefined; }
      finally { this.currentInterpreter = null; }
    }
    evalBool(code, interp) { return !!this.run("return !!(" + code + ")", interp); }
    evalNumber(code, interp) { const v = this.run("return (" + code + ")", interp); return typeof v === "number" && isFinite(v) ? Math.trunc(v) : 0; }
    battler(b) {
      const o = { hp: b.hp, mp: b.mp, tp: b.tp, mhp: b.mhp, mmp: b.mmp, atk: b.atk, def: b.def, mat: b.mat, mdf: b.mdf, agi: b.agi, luk: b.luk,
        hit: b.hit, eva: b.eva, cri: b.cri, states: b.states.slice(), name: b.name, _isActor: b.isActor, level: b.isActor ? b.level : 1 };
      if (b.isActor) o.actorId = b.actorId; else { o.enemyId = b.enemyId; o.index = b.index; }
      o.isStateAffected = id => o.states.indexOf(id) >= 0; o.isActor = () => o._isActor; o.isEnemy = () => !o._isActor;
      o.isDead = () => o.hp <= 0; o.isAlive = () => o.hp > 0;
      return o;
    }
    evalFormula(f, a, b) {
      try {
        if (!this.formulaCache) this.formulaCache = {};
        const fn = this.formulaCache[f] || (this.formulaCache[f] = new Function(...this.names, "a", "b", "v", "return (" + f + ");"));
        const r = Math.max(this.call(fn, null, [this.battler(a), this.battler(b), this.api.$gameVariables._data]), 0);
        return Number.isFinite(r) ? r : 0;
      } catch (e) { this.appendLog("[formula] " + f + ": " + e); return 0; }
    }
    callPluginCommand(plugin, command, args, interp) {
      this.currentInterpreter = interp;
      try {
        const f = this.commands[plugin + ":" + command];
        const a = {}; for (const k of Object.keys(args || {})) a[k] = LK.P.str(args[k]);
        if (f) f.call(this.interpreterProxy(interp), a); else this.appendLog("[plugin] no command " + plugin + ":" + command);
      } catch (e) { this.appendLog("[js error] " + e); } finally { this.currentInterpreter = null; }
    }
    emit(event, args) {
      for (const f of this.hooks[event] || []) { try { f(...(args || [])); } catch (e) { this.appendLog("[js error] " + event + ": " + e); } }
    }
    loadPlugins(project) {
      for (const pl of project.plugins || []) {
        this.params[pl.name] = pl.parameters || {};
        try { this.call(this.compile(pl.source), null); this.loadedPlugins.push(pl.name); this.appendLog("[plugin] loaded " + pl.name); }
        catch (e) { this.appendLog("[plugin] " + pl.name + ": " + e); }
      }
    }
  }
  LK.ScriptEngine = ScriptEngine;
})(typeof LK !== "undefined" ? LK : require("./core-data.js"));
