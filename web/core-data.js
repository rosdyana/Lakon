// Lakon web runtime — data layer. A JavaScript port of Sources/LakonCore (Models, Database, Animation,
// TileID, GameState, Screen). Field names and defaults match the Swift decoders, which match MZ's data/*.json.
"use strict";
var LK = (typeof LK !== "undefined" && LK) || {};
if (typeof module !== "undefined") module.exports = LK;

(function (LK) {
  // ---------- numeric helpers (Swift semantics) ----------
  const idiv = (a, b) => Math.trunc(a / b);                 // Int / Int
  const roundHalfAway = x => (x < 0 ? -Math.round(-x) : Math.round(x)) === 0 ? 0 : (x < 0 ? -Math.round(-x) : Math.round(x));
  const rnd = x => { const r = Math.sign(x) * Math.floor(Math.abs(x) + 0.5); return r === 0 ? 0 : r; }; // Double.rounded()
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  LK.idiv = idiv; LK.rnd = rnd; LK.clamp = clamp; LK._rha = roundHalfAway;
  const v = (o, k, d) => (o && o[k] !== undefined && o[k] !== null ? o[k] : d);
  const num = (o, k, d) => { const x = v(o, k, d); return typeof x === "number" ? x : (typeof x === "boolean" ? (x ? 1 : 0) : (Number(x) || d)); };
  const int = (o, k, d) => Math.trunc(num(o, k, d));
  const str = (o, k, d) => { const x = v(o, k, d); return typeof x === "string" ? x : (x === undefined || x === null ? d : String(x)); };
  const bool = (o, k, d) => { const x = v(o, k, d); return typeof x === "boolean" ? x : !!x; };
  const arr = (o, k, d) => (Array.isArray(o && o[k]) ? o[k] : d);
  LK.v = v; LK.int = int; LK.num = num; LK.str = str; LK.bool = bool; LK.arr = arr;
  // JSONValue accessors for command parameters
  LK.P = {
    int: x => (typeof x === "number" ? Math.trunc(x) : typeof x === "boolean" ? (x ? 1 : 0) : typeof x === "string" ? (parseInt(x, 10) || 0) : 0),
    str: x => (typeof x === "string" ? x : typeof x === "number" ? (Number.isInteger(x) ? String(x) : String(x)) : typeof x === "boolean" ? String(x) : ""),
    bool: x => (typeof x === "boolean" ? x : typeof x === "number" ? x !== 0 : false),
    arr: x => (Array.isArray(x) ? x : []),
  };

  // ---------- records (lenient decoding, same defaults as Swift) ----------
  const N = LK.norm = {};
  N.audio = o => o && typeof o === "object" ? { name: str(o, "name", ""), volume: int(o, "volume", 90), pitch: int(o, "pitch", 100), pan: int(o, "pan", 0) } : null;
  N.audioOr = o => N.audio(o) || { name: "", volume: 90, pitch: 100, pan: 0 };
  N.trait = o => ({ code: int(o, "code", 0), dataId: int(o, "dataId", 0), value: num(o, "value", 0) });
  N.effect = o => ({ code: int(o, "code", 0), dataId: int(o, "dataId", 0), value1: num(o, "value1", 0), value2: num(o, "value2", 0) });
  N.damage = o => ({ type: int(o, "type", 0), elementId: int(o, "elementId", 0), formula: str(o, "formula", "0"), variance: int(o, "variance", 20), critical: bool(o, "critical", false) });
  N.command = o => ({ code: int(o, "code", 0), indent: int(o, "indent", 0), parameters: arr(o, "parameters", []) });
  const list = (o, k) => { const l = arr(o, k, null); const r = l ? l.map(N.command) : [{ code: 0, indent: 0, parameters: [] }]; return r.length ? r : [{ code: 0, indent: 0, parameters: [] }]; };
  N.list = list;
  N.usable = (o, skill) => ({
    id: int(o, "id", 0), name: str(o, "name", ""), description: str(o, "description", ""), iconIndex: int(o, "iconIndex", 0),
    scope: int(o, "scope", skill ? 1 : 7), occasion: int(o, "occasion", skill ? 1 : 0), speed: int(o, "speed", 0), successRate: int(o, "successRate", 100),
    repeats: int(o, "repeats", 1), tpGain: int(o, "tpGain", 0), hitType: int(o, "hitType", skill ? 1 : 0), animationId: int(o, "animationId", 0),
    damage: N.damage(v(o, "damage", {})), effects: arr(o, "effects", []).map(N.effect), note: str(o, "note", ""), isSkill: !!skill,
  });
  N.skill = o => Object.assign(N.usable(o, true), { stypeId: int(o, "stypeId", 1), mpCost: int(o, "mpCost", 0), tpCost: int(o, "tpCost", 0),
    message1: str(o, "message1", ""), message2: str(o, "message2", ""), requiredWtypeId1: int(o, "requiredWtypeId1", 0), requiredWtypeId2: int(o, "requiredWtypeId2", 0) });
  N.item = o => Object.assign(N.usable(o, false), { price: int(o, "price", 0), consumable: bool(o, "consumable", true), itypeId: int(o, "itypeId", 1) });
  N.equip = o => { const p = arr(o, "params", [0, 0, 0, 0, 0, 0, 0, 0]).slice(); while (p.length < 8) p.push(0);
    return { id: int(o, "id", 0), name: str(o, "name", ""), description: str(o, "description", ""), iconIndex: int(o, "iconIndex", 0), price: int(o, "price", 0),
      etypeId: int(o, "etypeId", 1), wtypeId: int(o, "wtypeId", 0), atypeId: int(o, "atypeId", 0), params: p, traits: arr(o, "traits", []).map(N.trait),
      animationId: int(o, "animationId", 0), note: str(o, "note", "") }; };
  N.actor = o => ({ id: int(o, "id", 0), name: str(o, "name", ""), nickname: str(o, "nickname", ""), profile: str(o, "profile", ""), classId: int(o, "classId", 1),
    initialLevel: int(o, "initialLevel", 1), maxLevel: int(o, "maxLevel", 99), characterName: str(o, "characterName", ""), characterIndex: int(o, "characterIndex", 0),
    faceName: str(o, "faceName", ""), faceIndex: int(o, "faceIndex", 0), battlerName: str(o, "battlerName", ""), equips: arr(o, "equips", [0, 0, 0, 0, 0]),
    traits: arr(o, "traits", []).map(N.trait), note: str(o, "note", "") });
  N.class = o => { const p = arr(o, "params", []).slice(); while (p.length < 8) p.push(new Array(100).fill(1));
    return { id: int(o, "id", 0), name: str(o, "name", ""), expParams: arr(o, "expParams", [30, 20, 30, 30]), params: p,
      learnings: arr(o, "learnings", []).map(l => ({ level: int(l, "level", 1), skillId: int(l, "skillId", 1) })), traits: arr(o, "traits", []).map(N.trait), note: str(o, "note", "") }; };
  N.enemy = o => { const p = arr(o, "params", [100, 0, 10, 10, 10, 10, 10, 10]).slice(); while (p.length < 8) p.push(0);
    return { id: int(o, "id", 0), name: str(o, "name", ""), battlerName: str(o, "battlerName", ""), battlerHue: int(o, "battlerHue", 0), params: p,
      exp: int(o, "exp", 0), gold: int(o, "gold", 0), dropItems: arr(o, "dropItems", []).map(d => ({ kind: int(d, "kind", 0), dataId: int(d, "dataId", 1), denominator: int(d, "denominator", 1) })),
      actions: arr(o, "actions", []).map(a => ({ skillId: int(a, "skillId", 1), rating: int(a, "rating", 5), conditionType: int(a, "conditionType", 0),
        conditionParam1: num(a, "conditionParam1", 0), conditionParam2: num(a, "conditionParam2", 0) })),
      traits: arr(o, "traits", []).map(N.trait), note: str(o, "note", "") }; };
  N.troopCond = c => ({ actorHp: int(c, "actorHp", 50), actorId: int(c, "actorId", 1), actorValid: bool(c, "actorValid", false), enemyHp: int(c, "enemyHp", 50),
    enemyIndex: int(c, "enemyIndex", 0), enemyValid: bool(c, "enemyValid", false), switchId: int(c, "switchId", 1), switchValid: bool(c, "switchValid", false),
    turnA: int(c, "turnA", 0), turnB: int(c, "turnB", 0), turnEnding: bool(c, "turnEnding", false), turnValid: bool(c, "turnValid", false) });
  N.troop = o => ({ id: int(o, "id", 0), name: str(o, "name", ""),
    members: arr(o, "members", []).map(m => ({ enemyId: int(m, "enemyId", 1), x: int(m, "x", 408), y: int(m, "y", 312), hidden: bool(m, "hidden", false) })),
    pages: arr(o, "pages", null) ? o.pages.map(p => ({ conditions: N.troopCond(v(p, "conditions", {})), list: list(p, "list"), span: int(p, "span", 0) }))
      : [{ conditions: N.troopCond({}), list: list({}, "list"), span: 0 }] });
  N.state = o => ({ id: int(o, "id", 0), name: str(o, "name", ""), iconIndex: int(o, "iconIndex", 0), restriction: int(o, "restriction", 0), priority: int(o, "priority", 50),
    autoRemovalTiming: int(o, "autoRemovalTiming", 0), minTurns: int(o, "minTurns", 1), maxTurns: int(o, "maxTurns", 1), removeAtBattleEnd: bool(o, "removeAtBattleEnd", false),
    removeByDamage: bool(o, "removeByDamage", false), chanceByDamage: int(o, "chanceByDamage", 100), removeByRestriction: bool(o, "removeByRestriction", false),
    removeByWalking: bool(o, "removeByWalking", false), stepsToRemove: int(o, "stepsToRemove", 100), traits: arr(o, "traits", []).map(N.trait),
    message1: str(o, "message1", ""), message2: str(o, "message2", ""), message3: str(o, "message3", ""), message4: str(o, "message4", ""), note: str(o, "note", ""),
    motion: int(o, "motion", 0), overlay: int(o, "overlay", 0) });
  N.vehicle = o => ({ bgm: N.audioOr(v(o, "bgm", null)), characterIndex: int(o, "characterIndex", 0), characterName: str(o, "characterName", ""),
    startMapId: int(o, "startMapId", 0), startX: int(o, "startX", 0), startY: int(o, "startY", 0) });
  N.defaultTerms = () => ({
    basic: ["Level", "Lv", "HP", "HP", "MP", "MP", "TP", "TP", "EXP", "EXP"],
    commands: ["Fight", "Escape", "Attack", "Guard", "Item", "Skill", "Equip", "Status", "Formation", "Save", "Game End", "Options",
      "Weapon", "Armor", "Key Item", "Equip", "Optimize", "Clear", "New Game", "Continue", "", "To Title", "Cancel", "", "Buy", "Sell"],
    params: ["Max HP", "Max MP", "Attack", "Defense", "M.Attack", "M.Defense", "Agility", "Luck", "Hit", "Evasion"],
    messages: {
      emerge: "%1 emerged!", preemptive: "%1 got the upper hand!", surprise: "%1 was surprised!", escapeStart: "%1 has started to escape!",
      escapeFailure: "However, it was unable to escape!", victory: "%1 was victorious!", defeat: "%1 was defeated.", obtainExp: "%1 %2 received!",
      obtainGold: "%1\\G found!", obtainItem: "%1 found!", levelUp: "%1 is now %2 %3!", obtainSkill: "%1 learned!", actorDamage: "%1 took %2 damage!",
      actorRecovery: "%1 recovered %2 %3!", actorGain: "%1 gained %2 %3!", actorLoss: "%1 lost %2 %3!", actorDrain: "%1 was drained of %2 %3!",
      actorNoDamage: "%1 took no damage!", actorNoHit: "Miss! %1 took no damage!", enemyDamage: "%1 took %2 damage!", enemyRecovery: "%1 recovered %2 %3!",
      enemyGain: "%1 gained %2 %3!", enemyLoss: "%1 lost %2 %3!", enemyDrain: "Drained %2 %3 from %1!", enemyNoDamage: "%1 took no damage!",
      enemyNoHit: "Miss! %1 took no damage!", evasion: "%1 evaded the attack!", criticalToEnemy: "An excellent hit!!", criticalToActor: "A painful blow!!",
      useItem: "%1 uses %2!", partyName: "%1's Party", possession: "Possession", alwaysDash: "Always Dash", commandRemember: "Command Remember",
      bgmVolume: "BGM Volume", bgsVolume: "BGS Volume", meVolume: "ME Volume", seVolume: "SE Volume", saveMessage: "Save to which file?",
      loadMessage: "Load which file?", file: "File", autosave: "Autosave", expTotal: "Current %1", expNext: "To Next %1", buffAdd: "%1's %2 went up!",
      debuffAdd: "%1's %2 went down!", buffRemove: "%1's %2 returned to normal!", actionFailure: "There was no effect on %1!",
    },
  });
  N.terms = o => {
    const d = N.defaultTerms();
    if (!o) return d;
    const t = { basic: arr(o, "basic", d.basic), commands: arr(o, "commands", d.commands).slice(), params: arr(o, "params", d.params), messages: Object.assign({}, d.messages, v(o, "messages", {})) };
    while (t.commands.length < d.commands.length) t.commands.push(d.commands[t.commands.length]);
    return t;
  };
  LK.termMessage = (t, key, ...args) => { let s = t.messages[key] !== undefined ? t.messages[key] : key; args.forEach((a, i) => { s = s.split("%" + (i + 1)).join(String(a)); }); return s; };
  const ATTACK_MOTIONS = [[0, 0], [0, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [2, 7], [2, 8], [2, 9], [0, 10], [0, 11], [0, 12]].map(([t, w]) => ({ type: t, weaponImageId: w }));
  N.system = o => {
    const sounds = arr(o, "sounds", null) ? o.sounds.map(N.audioOr) : new Array(24).fill(0).map(() => N.audioOr(null));
    while (sounds.length < 24) sounds.push(N.audioOr(null));
    return {
      gameTitle: str(o, "gameTitle", "Untitled"), currencyUnit: str(o, "currencyUnit", "G"), startMapId: int(o, "startMapId", 1), startX: int(o, "startX", 0), startY: int(o, "startY", 0),
      partyMembers: arr(o, "partyMembers", [1]), switches: arr(o, "switches", [""]), variables: arr(o, "variables", [""]), windowTone: arr(o, "windowTone", [0, 0, 0, 0]),
      titleBgm: N.audioOr(v(o, "titleBgm", null)), battleBgm: N.audioOr(v(o, "battleBgm", null)), victoryMe: N.audioOr(v(o, "victoryMe", null)),
      defeatMe: N.audioOr(v(o, "defeatMe", null)), gameoverMe: N.audioOr(v(o, "gameoverMe", null)), sounds,
      boat: N.vehicle(v(o, "boat", {})), ship: N.vehicle(v(o, "ship", {})), airship: N.vehicle(v(o, "airship", {})), terms: N.terms(v(o, "terms", null)),
      elements: arr(o, "elements", ["", "Physical"]), skillTypes: arr(o, "skillTypes", ["", "Magic", "Special"]), weaponTypes: arr(o, "weaponTypes", ["", "Dagger", "Sword"]),
      armorTypes: arr(o, "armorTypes", ["", "General Armor", "Magic Armor"]), equipTypes: arr(o, "equipTypes", ["", "Weapon", "Shield", "Head", "Body", "Accessory"]),
      battleback1Name: str(o, "battleback1Name", ""), battleback2Name: str(o, "battleback2Name", ""), optDisplayTp: bool(o, "optDisplayTp", true),
      optSlipDeath: bool(o, "optSlipDeath", false), optFloorDeath: bool(o, "optFloorDeath", false), optExtraExp: bool(o, "optExtraExp", false),
      title1Name: str(o, "title1Name", ""), optSideView: bool(o, "optSideView", false),
      attackMotions: arr(o, "attackMotions", null) ? o.attackMotions.map(m => ({ type: int(m, "type", 0), weaponImageId: int(m, "weaponImageId", 0) })) : ATTACK_MOTIONS,
      magicSkills: arr(o, "magicSkills", [1]),
    };
  };
  N.pageCond = c => ({ actorId: int(c, "actorId", 1), actorValid: bool(c, "actorValid", false), itemId: int(c, "itemId", 1), itemValid: bool(c, "itemValid", false),
    selfSwitchCh: str(c, "selfSwitchCh", "A"), selfSwitchValid: bool(c, "selfSwitchValid", false), switch1Id: int(c, "switch1Id", 1), switch1Valid: bool(c, "switch1Valid", false),
    switch2Id: int(c, "switch2Id", 1), switch2Valid: bool(c, "switch2Valid", false), variableId: int(c, "variableId", 1), variableValid: bool(c, "variableValid", false),
    variableValue: int(c, "variableValue", 0) });
  N.image = i => ({ tileId: int(i, "tileId", 0), characterName: str(i, "characterName", ""), direction: int(i, "direction", 2), pattern: int(i, "pattern", 1), characterIndex: int(i, "characterIndex", 0) });
  N.page = p => ({ conditions: N.pageCond(v(p, "conditions", {})), directionFix: bool(p, "directionFix", false), image: N.image(v(p, "image", {})), list: list(p, "list"),
    moveFrequency: int(p, "moveFrequency", 3), moveRoute: v(p, "moveRoute", null), moveSpeed: int(p, "moveSpeed", 3), moveType: int(p, "moveType", 0),
    priorityType: int(p, "priorityType", 0), stepAnime: bool(p, "stepAnime", false), through: bool(p, "through", false), trigger: int(p, "trigger", 0), walkAnime: bool(p, "walkAnime", true) });
  N.event = e => { const pages = arr(e, "pages", null); return { id: int(e, "id", 0), name: str(e, "name", ""), note: str(e, "note", ""),
    pages: pages && pages.length ? pages.map(N.page) : [N.page({})], x: int(e, "x", 0), y: int(e, "y", 0) }; };
  N.map = o => {
    const w = int(o, "width", 17), h = int(o, "height", 13);
    const data = arr(o, "data", []).slice(); const need = w * h * 6; while (data.length < need) data.push(0);
    const events = arr(o, "events", [null]).map(e => (e ? N.event(e) : null));
    return { displayName: str(o, "displayName", ""), note: str(o, "note", ""), tilesetId: int(o, "tilesetId", 1), width: w, height: h, scrollType: int(o, "scrollType", 0), data,
      events: events.length ? events : [null], autoplayBgm: bool(o, "autoplayBgm", false), bgm: N.audioOr(v(o, "bgm", null)), autoplayBgs: bool(o, "autoplayBgs", false),
      bgs: N.audioOr(v(o, "bgs", null)), encounterList: arr(o, "encounterList", []).map(e => ({ troopId: int(e, "troopId", 1), weight: int(e, "weight", 10), regionSet: arr(e, "regionSet", []) })),
      encounterStep: int(o, "encounterStep", 30), specifyBattleback: bool(o, "specifyBattleback", false), battleback1Name: str(o, "battleback1Name", ""),
      battleback2Name: str(o, "battleback2Name", ""), disableDashing: bool(o, "disableDashing", false), parallaxName: str(o, "parallaxName", ""),
      parallaxLoopX: bool(o, "parallaxLoopX", false), parallaxLoopY: bool(o, "parallaxLoopY", false), parallaxSx: int(o, "parallaxSx", 0), parallaxSy: int(o, "parallaxSy", 0) };
  };
  N.emptyMap = (w, h) => N.map({ width: w, height: h });
  N.tileset = o => { const names = arr(o, "tilesetNames", new Array(9).fill("")).slice(); while (names.length < 9) names.push("");
    const flags = arr(o, "flags", []).slice(); while (flags.length < LK.TileID.max) flags.push(0);
    return { id: int(o, "id", 0), name: str(o, "name", ""), mode: int(o, "mode", 1), tilesetNames: names, flags }; };
  N.commonEvent = o => ({ id: int(o, "id", 0), name: str(o, "name", ""), trigger: int(o, "trigger", 0), switchId: int(o, "switchId", 1), list: list(o, "list") });
  N.animation = o => {
    const a = { id: int(o, "id", 0), name: str(o, "name", ""), displayType: int(o, "displayType", 0), effectName: str(o, "effectName", ""),
      flashTimings: arr(o, "flashTimings", []).map(t => ({ frame: int(t, "frame", 0), duration: int(t, "duration", 10), color: arr(t, "color", [255, 255, 255, 170]) })),
      soundTimings: arr(o, "soundTimings", []).map(t => ({ frame: int(t, "frame", 0), se: N.audioOr(v(t, "se", null)) })),
      offsetX: int(o, "offsetX", 0), offsetY: int(o, "offsetY", 0), rotation: v(o, "rotation", { x: 0, y: 0, z: 0 }), scale: int(o, "scale", 100), speed: int(o, "speed", 100),
      alignBottom: bool(o, "alignBottom", false), frames: Array.isArray(o.frames) ? o.frames : null,
      timings: arr(o, "timings", []).map(t => { const se = N.audio(v(t, "se", null)); return { frame: int(t, "frame", 0), flashScope: int(t, "flashScope", 0),
        flashColor: arr(t, "flashColor", [255, 255, 255, 255]), flashDuration: int(t, "flashDuration", 5), se: se && se.name ? se : null }; }),
      animation1Name: str(o, "animation1Name", ""), animation1Hue: int(o, "animation1Hue", 0), animation2Name: str(o, "animation2Name", ""),
      animation2Hue: int(o, "animation2Hue", 0), position: int(o, "position", 1) };
    return LK.decorateAnimation(a);
  };

  // AnimationData computed properties (Animation.swift)
  LK.Anim = { mvRate: 4, baseDelay: 8, nextDelay: 12, standInFrames: 40 };
  LK.decorateAnimation = a => {
    a.isMV = !!a.frames;
    a.isForEach = a.isMV ? a.position !== 3 : a.displayType === 0;
    a.isScreen = a.isMV ? a.position === 3 : a.displayType === 2;
    a.playFrames = (() => {
      if (a.frames) return a.frames.length * LK.Anim.mvRate + 1;
      const lastFlash = a.flashTimings.length ? Math.max(...a.flashTimings.map(t => t.frame + t.duration)) : 0;
      const lastSound = a.soundTimings.length ? Math.max(...a.soundTimings.map(t => t.frame)) : 0;
      const standIn = a.effectName ? rnd(LK.Anim.standInFrames * 100 / Math.max(10, a.speed)) : 0;
      return Math.max(lastFlash, lastSound + 1, standIn, 1);
    })();
    a.totalFrames = n => LK.Anim.baseDelay + ((a.isForEach ? Math.max(1, n) : 1) - 1) * LK.Anim.nextDelay + a.playFrames;
    return a;
  };

  // ---------- project ----------
  /// `files` maps data file names ("System.json", "Map001.json", …) to parsed JSON.
  LK.Project = class Project {
    constructor(files, assets) {
      const f = n => files[n];
      const L = (n, fn) => (Array.isArray(f(n)) ? f(n).map(x => (x ? fn(x) : null)) : [null]);
      this.system = N.system(f("System.json") || {});
      this.mapInfos = Array.isArray(f("MapInfos.json")) ? f("MapInfos.json") : [null];
      this.tilesets = L("Tilesets.json", N.tileset);
      this.actors = L("Actors.json", N.actor);
      this.items = L("Items.json", N.item);
      this.commonEvents = L("CommonEvents.json", N.commonEvent);
      this.classes = L("Classes.json", N.class);
      this.skills = L("Skills.json", N.skill);
      this.weapons = L("Weapons.json", N.equip);
      this.armors = L("Armors.json", N.equip);
      this.enemies = L("Enemies.json", N.enemy);
      this.troops = L("Troops.json", N.troop);
      this.states = L("States.json", N.state);
      this.animations = L("Animations.json", N.animation);
      this.maps = {};
      for (const info of this.mapInfos) if (info) { const m = f("Map" + String(info.id).padStart(3, "0") + ".json"); if (m) this.maps[info.id] = N.map(m); }
      this.plugins = files.__plugins || [];       // [{name, source, parameters}]
      this.assets = assets || {};                 // e.g. { "img/parallaxes": ["Sky"], audio: {"se/Fire": "se/Fire.m4a"} }
    }
    at(list, id) { return id > 0 && id < list.length ? list[id] : null; }
    actor(id) { return this.at(this.actors, id); }
    classData(id) { return this.at(this.classes, id); }
    skill(id) { return this.at(this.skills, id); }
    item(id) { return this.at(this.items, id); }
    weapon(id) { return this.at(this.weapons, id); }
    armor(id) { return this.at(this.armors, id); }
    enemy(id) { return this.at(this.enemies, id); }
    troop(id) { return this.at(this.troops, id); }
    state(id) { return this.at(this.states, id); }
    animation(id) { return this.at(this.animations, id); }
    tilesetFor(map) { return (map.tilesetId < this.tilesets.length ? this.tilesets[map.tilesetId] : null) || this.tilesets.find(t => t) || N.tileset({ id: 1 }); }
    mapName(id) { const i = id < this.mapInfos.length ? this.mapInfos[id] : null; return (i && i.name) || ("Map " + id); }
  };

  // ---------- tile ids (TileID.swift) ----------
  const T = LK.TileID = { B: 0, C: 256, D: 512, E: 768, A5: 1536, A1: 2048, A2: 2816, A3: 4352, A4: 5888, max: 8192 };
  T.isAutotile = id => id >= T.A1;
  T.isA1 = id => id >= T.A1 && id < T.A2;
  T.isA2 = id => id >= T.A2 && id < T.A3;
  T.isA3 = id => id >= T.A3 && id < T.A4;
  T.isA4 = id => id >= T.A4 && id < T.max;
  T.isA5 = id => id >= T.A5 && id < T.A1;
  T.kind = id => idiv(id - T.A1, 48);
  T.shape = id => (id - T.A1) % 48;
  T.floorTable = [
    [[2, 4], [1, 4], [2, 3], [1, 3]], [[2, 0], [1, 4], [2, 3], [1, 3]], [[2, 4], [3, 0], [2, 3], [1, 3]], [[2, 0], [3, 0], [2, 3], [1, 3]],
    [[2, 4], [1, 4], [2, 3], [3, 1]], [[2, 0], [1, 4], [2, 3], [3, 1]], [[2, 4], [3, 0], [2, 3], [3, 1]], [[2, 0], [3, 0], [2, 3], [3, 1]],
    [[2, 4], [1, 4], [2, 1], [1, 3]], [[2, 0], [1, 4], [2, 1], [1, 3]], [[2, 4], [3, 0], [2, 1], [1, 3]], [[2, 0], [3, 0], [2, 1], [1, 3]],
    [[2, 4], [1, 4], [2, 1], [3, 1]], [[2, 0], [1, 4], [2, 1], [3, 1]], [[2, 4], [3, 0], [2, 1], [3, 1]], [[2, 0], [3, 0], [2, 1], [3, 1]],
    [[0, 4], [1, 4], [0, 3], [1, 3]], [[0, 4], [3, 0], [0, 3], [1, 3]], [[0, 4], [1, 4], [0, 3], [3, 1]], [[0, 4], [3, 0], [0, 3], [3, 1]],
    [[2, 2], [1, 2], [2, 3], [1, 3]], [[2, 2], [1, 2], [2, 3], [3, 1]], [[2, 2], [1, 2], [2, 1], [1, 3]], [[2, 2], [1, 2], [2, 1], [3, 1]],
    [[2, 4], [3, 4], [2, 3], [3, 3]], [[2, 4], [3, 4], [2, 1], [3, 3]], [[2, 0], [3, 4], [2, 3], [3, 3]], [[2, 0], [3, 4], [2, 1], [3, 3]],
    [[2, 4], [1, 4], [2, 5], [1, 5]], [[2, 0], [1, 4], [2, 5], [1, 5]], [[2, 4], [3, 0], [2, 5], [1, 5]], [[2, 0], [3, 0], [2, 5], [1, 5]],
    [[0, 4], [3, 4], [0, 3], [3, 3]], [[2, 2], [1, 2], [2, 5], [1, 5]], [[0, 2], [1, 2], [0, 3], [1, 3]], [[0, 2], [1, 2], [0, 3], [3, 1]],
    [[2, 2], [3, 2], [2, 3], [3, 3]], [[2, 2], [3, 2], [2, 1], [3, 3]], [[2, 4], [3, 4], [2, 5], [3, 5]], [[2, 0], [3, 4], [2, 5], [3, 5]],
    [[0, 4], [1, 4], [0, 5], [1, 5]], [[0, 4], [3, 0], [0, 5], [1, 5]], [[0, 2], [3, 2], [0, 3], [3, 3]], [[0, 2], [1, 2], [0, 5], [1, 5]],
    [[0, 4], [3, 4], [0, 5], [3, 5]], [[2, 2], [3, 2], [2, 5], [3, 5]], [[0, 2], [3, 2], [0, 5], [3, 5]], [[0, 0], [1, 0], [0, 1], [1, 1]],
  ];
  T.wallTable = [
    [[2, 2], [1, 2], [2, 1], [1, 1]], [[0, 2], [1, 2], [0, 1], [1, 1]], [[2, 0], [1, 0], [2, 1], [1, 1]], [[0, 0], [1, 0], [0, 1], [1, 1]],
    [[2, 2], [3, 2], [2, 1], [3, 1]], [[0, 2], [3, 2], [0, 1], [3, 1]], [[2, 0], [3, 0], [2, 1], [3, 1]], [[0, 0], [3, 0], [0, 1], [3, 1]],
    [[2, 2], [1, 2], [2, 3], [1, 3]], [[0, 2], [1, 2], [0, 3], [1, 3]], [[2, 0], [1, 0], [2, 3], [1, 3]], [[0, 0], [1, 0], [0, 3], [1, 3]],
    [[2, 2], [3, 2], [2, 3], [3, 3]], [[0, 2], [3, 2], [0, 3], [3, 3]], [[2, 0], [3, 0], [2, 3], [3, 3]], [[0, 0], [3, 0], [0, 3], [3, 3]],
  ];
  T.waterfallTable = [[[2, 0], [1, 0], [2, 1], [1, 1]], [[0, 0], [1, 0], [0, 1], [1, 1]], [[2, 0], [3, 0], [2, 1], [3, 1]], [[0, 0], [3, 0], [0, 1], [3, 1]]];

  /// Source rects for a tile id: [set, sx, sy, w, h, ox, oy] (TileRenderer.rects).
  T.rects = (tileId, animationFrame) => {
    const w = 48, h = 48;
    if (!T.isAutotile(tileId)) {
      const set = T.isA5(tileId) ? 4 : 5 + idiv(tileId, 256);
      const sx = ((idiv(tileId, 128) % 2) * 8 + tileId % 8) * w;
      const sy = (idiv(tileId % 256, 8) % 16) * h;
      return [[set, sx, sy, w, h, 0, 0]];
    }
    const kind = T.kind(tileId), shape = T.shape(tileId), tx = kind % 8, ty = idiv(kind, 8);
    let set = 0, bx = 0, by = 0, table = T.floorTable;
    if (T.isA1(tileId)) {
      const water = [0, 1, 2, 1][animationFrame % 4];
      switch (kind) {
        case 0: bx = water * 2; by = 0; break;
        case 1: bx = water * 2; by = 3; break;
        case 2: bx = 6; by = 0; break;
        case 3: bx = 6; by = 3; break;
        default:
          bx = idiv(tx, 4) * 8; by = ty * 6 + (idiv(tx, 2) % 2) * 3;
          if (kind % 2 === 0) bx += water * 2; else { bx += 6; table = T.waterfallTable; by += animationFrame % 3; }
      }
    } else if (T.isA2(tileId)) { set = 1; bx = tx * 2; by = (ty - 2) * 3; }
    else if (T.isA3(tileId)) { set = 2; bx = tx * 2; by = (ty - 6) * 2; table = T.wallTable; }
    else { set = 3; bx = tx * 2; by = Math.floor((ty - 10) * 2.5 + (ty % 2 === 1 ? 0.5 : 0)); if (ty % 2 === 1) table = T.wallTable; }
    if (shape >= table.length) return [];
    const q = table[shape], w1 = w / 2, h1 = h / 2;
    return [0, 1, 2, 3].map(i => [set, (bx * 2 + q[i][0]) * w1, (by * 2 + q[i][1]) * h1, w1, h1, (i % 2) * w1, idiv(i, 2) * h1]);
  };

  // Map helpers (GameMap + TileID extension)
  const M = LK.MapUtil = {};
  M.isValid = (m, x, y) => x >= 0 && y >= 0 && x < m.width && y < m.height;
  M.tileId = (m, x, y, z) => (M.isValid(m, x, y) ? m.data[(z * m.height + y) * m.width + x] || 0 : 0);
  M.flag = (ts, id) => (id >= 0 && id < ts.flags.length ? ts.flags[id] : 0);
  M.checkPassage = (m, x, y, bit, ts) => {
    for (let z = 3; z >= 0; z--) {
      const flag = M.flag(ts, M.tileId(m, x, y, z));
      if (flag & 0x10) continue;
      if ((flag & bit) === 0) return true;
      if ((flag & bit) === bit) return false;
    }
    return false;
  };
  M.isPassable = (m, x, y, d, ts) => M.checkPassage(m, x, y, (1 << (d / 2 - 1)) & 0x0f, ts);
  M.regionId = (m, x, y) => M.tileId(m, x, y, 5);
  M.liveEvents = m => m.events.filter(e => e);

  // ---------- RNG (GameState.swift) ----------
  LK.SystemRandom = class { next(upper) { return upper > 0 ? Math.floor(Math.random() * upper) : 0; } };
  /// Same xorshift as Swift's SeededRandom, in 64-bit BigInt (for parity tests).
  LK.SeededRandom = class {
    constructor(seed) { this.s = (BigInt(seed) + 0x9E3779B97F4A7C15n) & 0xFFFFFFFFFFFFFFFFn; }
    next(upper) {
      const M64 = 0xFFFFFFFFFFFFFFFFn;
      let s = this.s;
      s ^= (s << 13n) & M64; s ^= s >> 7n; s ^= (s << 17n) & M64;
      this.s = s;
      return upper > 0 ? Number(s % BigInt(upper)) : 0;
    }
  };

  // ---------- game state ----------
  LK.GameState = class GameState {
    constructor() {
      this.switches = {}; this.variables = {}; this.selfSwitches = {}; this.gold = 0; this.items = {}; this.party = [];
      this.mapId = 1; this.playerX = 0; this.playerY = 0; this.playerDirection = 2; this.steps = 0; this.playFrames = 0;
      this.weapons = {}; this.armors = {}; this.actors = {}; this.screen = new LK.GameScreen(); this.vehicles = []; this.vehicleType = -1;
      this.bgm = null; this.bgs = null; this.battleCount = 0; this.winCount = 0; this.escapeCount = 0; this.saveCount = 0;
      this.encounterEnabled = true; this.menuEnabled = true; this.saveEnabled = true; this.battleBgm = null; this.victoryMe = null;
      this.parallax = new LK.ParallaxState(); this.hasSavedParallax = false; this.needsRefresh = false;
    }
    toJSON() { const o = Object.assign({}, this); delete o.needsRefresh; delete o.hasSavedParallax; return o; }
    static fromJSON(o) {
      const s = new LK.GameState();
      for (const k of Object.keys(s)) if (o[k] !== undefined && k !== "screen" && k !== "parallax") s[k] = o[k];
      s.screen = LK.GameScreen.fromJSON(o.screen || {});
      if (o.parallax) { s.parallax = Object.assign(new LK.ParallaxState(), o.parallax); s.hasSavedParallax = true; }
      s.needsRefresh = false;
      return s;
    }
    switchValue(id) { return !!this.switches[id]; }
    setSwitch(id, val) { if (id > 0) { this.switches[id] = !!val; this.needsRefresh = true; } }
    variable(id) { return this.variables[id] || 0; }
    setVariable(id, val) { if (id > 0) { this.variables[id] = clamp(Math.trunc(val), -99999999, 99999999); this.needsRefresh = true; } }
    static selfKey(m, e, ch) { return m + "," + e + "," + ch; }
    selfSwitch(m, e, ch) { return !!this.selfSwitches[LK.GameState.selfKey(m, e, ch)]; }
    setSelfSwitch(m, e, ch, val) { const k = LK.GameState.selfKey(m, e, ch); if (val) this.selfSwitches[k] = true; else delete this.selfSwitches[k]; this.needsRefresh = true; }
    itemCount(id) { return this.items[id] || 0; }
    gainItem(id, n) { const val = clamp(this.itemCount(id) + n, 0, 99); if (val === 0) delete this.items[id]; else this.items[id] = val; this.needsRefresh = true; }
    gainGold(n) { this.gold = clamp(this.gold + n, 0, 99999999); }
    count(kind, id) { const d = kind === 2 ? this.weapons : kind === 3 ? this.armors : this.items; return d[id] || 0; }
    gain(kind, id, n) {
      if (id <= 0) return;
      const d = kind === 2 ? this.weapons : kind === 3 ? this.armors : this.items;
      const val = clamp((d[id] || 0) + n, 0, 99);
      if (val === 0) delete d[id]; else d[id] = val;
      this.needsRefresh = true;
    }
    static sortedKeys(d) { return Object.keys(d).map(Number).sort((a, b) => a - b); }
  };

  LK.newMessage = () => ({ faceName: "", faceIndex: 0, background: 0, positionType: 2, speakerName: "", lines: [], choices: [], choiceDefault: 0, choiceCancel: -1,
    choiceIndex: 0, visibleChars: 0, onChoose: null, numberVariable: 0, numberDigits: 0, number: 0, numberCursor: 0, itemChoiceVariable: 0, itemChoiceType: 0,
    itemChoices: [], itemChoiceIndex: 0, scrolling: false, scrollSpeed: 2, scrollOffset: 0,
    get text() { return this.lines.join("\n"); }, get isTextComplete() { return this.visibleChars >= [...this.text].length; } });

  LK.newInput = o => Object.assign({ dir4: 0, ok: false, cancel: false, up: false, down: false, left: false, right: false, dash: false, held: new Set() }, o || {});

  // ---------- screen (Screen.swift) ----------
  LK.GamePicture = class GamePicture {
    constructor(name, origin, x, y, scaleX, scaleY, opacity, blendMode) {
      Object.assign(this, { name, origin, x, y, scaleX, scaleY, opacity, blendMode, angle: 0, tone: [0, 0, 0, 0], target: [0, 0, 100, 100, 255],
        duration: 0, wholeDuration: 0, easingType: 0, rotationSpeed: 0, toneTarget: [0, 0, 0, 0], toneDuration: 0 });
    }
    move(o, x, y, sx, sy, op, blend, d, easing) {
      this.origin = o; this.target = [x, y, sx, sy, op]; this.blendMode = blend; this.duration = d; this.wholeDuration = d; this.easingType = easing;
      if (d === 0) { this.x = x; this.y = y; this.scaleX = sx; this.scaleY = sy; this.opacity = op; }
    }
    rotate(s) { this.rotationSpeed = s; }
    tint(t, d) { this.toneTarget = t; this.toneDuration = d; if (d === 0) this.tone = t.slice(); }
    static ease(type, t) {
      const ein = t => t * t, eout = t => 1 - (1 - t) * (1 - t);
      switch (type) { case 1: return ein(t); case 2: return eout(t); case 3: return t < 0.5 ? ein(t * 2) / 2 : eout(t * 2 - 1) / 2 + 0.5; default: return t; }
    }
    applyEasing(cur, target) {
      const d = this.duration, wd = this.wholeDuration;
      const lt = GamePicture.ease(this.easingType, (wd - d) / wd), t = GamePicture.ease(this.easingType, (wd - d + 1) / wd);
      const start = lt < 1 ? (cur - target * lt) / (1 - lt) : target;
      return start + (target - start) * t;
    }
    update() {
      if (this.duration > 0) {
        this.x = this.applyEasing(this.x, this.target[0]); this.y = this.applyEasing(this.y, this.target[1]);
        this.scaleX = this.applyEasing(this.scaleX, this.target[2]); this.scaleY = this.applyEasing(this.scaleY, this.target[3]);
        this.opacity = this.applyEasing(this.opacity, this.target[4]); this.duration--;
      }
      if (this.toneDuration > 0) { const d = this.toneDuration; for (let i = 0; i < 4; i++) this.tone[i] = (this.tone[i] * (d - 1) + this.toneTarget[i]) / d; this.toneDuration--; }
      if (this.rotationSpeed !== 0) this.angle += this.rotationSpeed / 2;
    }
  };
  LK.GameScreen = class GameScreen {
    constructor() {
      this.tone = [0, 0, 0, 0]; this.toneTarget = [0, 0, 0, 0]; this.toneDuration = 0; this.flashColor = [0, 0, 0, 0]; this.flashDuration = 0;
      this.shakePower = 0; this.shakeSpeed = 0; this.shakeDuration = 0; this.shakeDirection = 1; this.shake = 0;
      this.weatherType = "none"; this.weatherPower = 0; this.weatherPowerTarget = 0; this.weatherDuration = 0; this.pictures = {};
    }
    static fromJSON(o) {
      const s = Object.assign(new GameScreen(), o, { pictures: {} });
      for (const k of Object.keys(o.pictures || {})) s.pictures[k] = Object.assign(new LK.GamePicture(), o.pictures[k]);
      return s;
    }
    startTint(t, d) { this.toneTarget = t.slice(0, 4); this.toneDuration = d; if (d <= 0) this.tone = this.toneTarget.slice(); }
    startFlash(c, d) { this.flashColor = c.slice(0, 4); this.flashDuration = Math.max(1, d); }
    startShake(p, s, d) { this.shakePower = p; this.shakeSpeed = s; this.shakeDuration = d; }
    changeWeather(type, power, d) {
      if (type !== "none" || d === 0) this.weatherType = type;
      this.weatherPowerTarget = type === "none" ? 0 : power; this.weatherDuration = d;
      if (d === 0) this.weatherPower = this.weatherPowerTarget;
    }
    update() {
      if (this.toneDuration > 0) { const d = this.toneDuration; for (let i = 0; i < 4; i++) this.tone[i] = (this.tone[i] * (d - 1) + this.toneTarget[i]) / d; this.toneDuration--; }
      if (this.flashDuration > 0) { const d = this.flashDuration; this.flashColor[3] *= (d - 1) / d; this.flashDuration--; }
      if (this.shakeDuration > 0 || this.shake !== 0) {
        const delta = this.shakePower * this.shakeSpeed * this.shakeDirection / 10;
        if (this.shakeDuration <= 1 && this.shake * (this.shake + delta) < 0) this.shake = 0; else this.shake += delta;
        if (this.shake > this.shakePower * 2) this.shakeDirection = -1;
        if (this.shake < -this.shakePower * 2) this.shakeDirection = 1;
        this.shakeDuration--;
      }
      if (this.weatherDuration > 0) {
        const d = this.weatherDuration; this.weatherPower = (this.weatherPower * (d - 1) + this.weatherPowerTarget) / d; this.weatherDuration--;
        if (this.weatherDuration === 0 && this.weatherPowerTarget === 0) this.weatherType = "none";
      }
      for (const k of Object.keys(this.pictures)) this.pictures[k].update();
    }
    clearForBattleEnd() { this.flashColor = [0, 0, 0, 0]; this.flashDuration = 0; this.shake = 0; this.shakeDuration = 0; }
  };

  LK.ParallaxState = class ParallaxState {
    constructor(map) {
      this.name = ""; this.loopX = false; this.loopY = false; this.sx = 0; this.sy = 0; this.autoX = 0; this.autoY = 0;
      if (map) { this.name = map.parallaxName; this.loopX = map.parallaxLoopX; this.loopY = map.parallaxLoopY; this.sx = map.parallaxSx; this.sy = map.parallaxSy; }
    }
    get isZero() { return this.name.startsWith("!"); }
    update() { if (this.loopX) this.autoX += this.sx / 48 / 2; if (this.loopY) this.autoY += this.sy / 48 / 2; }
    change(n, lx, ly, x, y) { if (this.loopX && !lx) this.autoX = 0; if (this.loopY && !ly) this.autoY = 0; Object.assign(this, { name: n, loopX: lx, loopY: ly, sx: x, sy: y }); }
    origin(dx, dy) {
      const px = dx + this.autoX, py = dy + this.autoY;
      return [this.isZero ? px * 48 : this.loopX ? px * 48 / 2 : 0, this.isZero ? py * 48 : this.loopY ? py * 48 / 2 : 0];
    }
  };

  // ---------- audio requests (AudioState) ----------
  const sameAudio = (a, b) => !!a && !!b && a.name === b.name && a.volume === b.volume && a.pitch === b.pitch && a.pan === b.pan;
  LK.AudioState = class AudioState {
    constructor() { this.pending = []; this.currentBgm = null; this.currentBgs = null; this.savedBgm = null; }
    playBgm(f) { if (!f || !f.name) { this.stopBgm(); return; } if (sameAudio(this.currentBgm, f)) return; this.currentBgm = f; this.pending.push({ t: "playBgm", f }); }
    stopBgm() { this.currentBgm = null; this.pending.push({ t: "stopBgm" }); }
    fadeOutBgm(s) { this.currentBgm = null; this.pending.push({ t: "fadeOutBgm", s }); }
    playBgs(f) { if (!f || !f.name) { this.currentBgs = null; this.pending.push({ t: "stopBgs" }); return; } if (sameAudio(this.currentBgs, f)) return; this.currentBgs = f; this.pending.push({ t: "playBgs", f }); }
    fadeOutBgs(s) { this.currentBgs = null; this.pending.push({ t: "fadeOutBgs", s }); }
    playMe(f) { if (f && f.name) this.pending.push({ t: "playMe", f }); }
    playSe(f) { if (f && f.name) this.pending.push({ t: "playSe", f }); }
    stopSe() { this.pending.push({ t: "stopSe" }); }
    saveBgm() { this.savedBgm = this.currentBgm; }
    replayBgm() { if (this.savedBgm) { this.currentBgm = null; this.playBgm(this.savedBgm); } else this.stopBgm(); }
    drain() { const p = this.pending; this.pending = []; return p; }
  };
})(LK);
