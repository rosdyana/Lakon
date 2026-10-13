// Lakon web runtime — characters, vehicles, GameWorld and the event interpreter.
// Port of Sources/LakonCore/Character.swift, Vehicle.swift, World.swift, Interpreter.swift.
"use strict";
(function (LK) {
  const { idiv, rnd, P } = LK;
  const M = LK.MapUtil;
  const xWith = (x, d) => (d === 6 ? x + 1 : d === 4 ? x - 1 : x);
  const yWith = (y, d) => (d === 2 ? y + 1 : d === 8 ? y - 1 : y);
  const reverse = d => 10 - d;
  LK.dir = { xWith, yWith, reverse };

  const routeList = r => (r && typeof r === "object" && Array.isArray(r.list) ? r.list.filter(o => o && typeof o === "object").map(o => ({ code: P.int(o.code), indent: 0, parameters: P.arr(o.parameters) })) : []);
  LK.routeList = routeList;

  class GameCharacter {
    constructor() {
      Object.assign(this, { x: 0, y: 0, realX: 0, realY: 0, direction: 2, moveSpeed: 4, moveFrequency: 6, pattern: 1, animationCount: 0, stopCount: 0,
        priorityType: 1, through: false, walkAnime: true, stepAnime: false, directionFix: false, transparent: false, characterName: "", characterIndex: 0,
        tileId: 0, movementSucceeded: true, dashing: false, balloonId: 0, balloonFrames: 0, animationId: 0, animationFrames: 0, animationSerial: 0,
        moveRoute: [], moveRouteRepeat: false, moveRouteSkippable: false, moveRouteIndex: 0, moveRouteForcing: false, routeWait: 0, world: null });
      LK.GameCharacter.serial = (LK.GameCharacter.serial || 0) + 1; this.uid = LK.GameCharacter.serial;
    }
    get isMoving() { return this.realX !== this.x || this.realY !== this.y; }
    get isObjectCharacter() { return this.characterName.startsWith("!") || this.characterName.startsWith("$!"); }
    get isNormalPriority() { return this.priorityType === 1; }
    get patternIndex() { return this.pattern < 3 ? this.pattern : 1; }
    get realMoveSpeed() { return this.moveSpeed + (this.dashing ? 1 : 0); }
    get distancePerFrame() { return Math.pow(2, this.realMoveSpeed) / 256; }
    get animationWait() { return (9 - this.realMoveSpeed) * 3; }
    locate(x, y) { this.x = x; this.y = y; this.realX = x; this.realY = y; }
    setDirection(d) { if (!this.directionFix && d !== 0) this.direction = d; }
    setImage(n, i) { this.characterName = n; this.characterIndex = i; this.tileId = 0; }
    startAnimation(id, frames) { if (frames <= 0) return; this.animationId = id; this.animationFrames = frames; this.animationSerial++; }
    update() {
      if (this.balloonFrames > 0) { this.balloonFrames--; if (this.balloonFrames === 0) this.balloonId = 0; }
      if (this.animationFrames > 0) { this.animationFrames--; if (this.animationFrames === 0) this.animationId = 0; }
      if (!this.isMoving) this.stopCount++;
      if (this.isMoving) this.updateMove();
      else if (this.moveRouteForcing) this.updateRoutineMove();
      else this.updateSelfMovement();
      this.updateAnimation();
    }
    updateSelfMovement() {}
    updateMove() {
      const d = this.distancePerFrame;
      if (this.x < this.realX) this.realX = Math.max(this.realX - d, this.x);
      if (this.x > this.realX) this.realX = Math.min(this.realX + d, this.x);
      if (this.y < this.realY) this.realY = Math.max(this.realY - d, this.y);
      if (this.y > this.realY) this.realY = Math.min(this.realY + d, this.y);
    }
    updateAnimation() {
      if (this.isMoving && this.walkAnime) this.animationCount += 1.5;
      else if (this.stepAnime || this.pattern !== 1) this.animationCount += 1;
      if (this.animationCount >= this.animationWait) {
        if (!this.stepAnime && this.stopCount > 0) this.pattern = 1; else this.pattern = (this.pattern + 1) % 4;
        this.animationCount = 0;
      }
    }
    canPass(x, y, d) {
      const w = this.world; if (!w) return false;
      const x2 = xWith(x, d), y2 = yWith(y, d);
      if (!M.isValid(w.map, x2, y2)) return false;
      if (this.through) return true;
      if (!M.isPassable(w.map, x, y, d, w.tileset) || !M.isPassable(w.map, x2, y2, reverse(d), w.tileset)) return false;
      return !this.isCollided(x2, y2);
    }
    isCollided(x, y) {
      const w = this.world; if (!w) return false;
      return w.events.some(e => e !== this && e.x === x && e.y === y && !e.through && e.isNormalPriority && e.pageIndex >= 0);
    }
    moveStraight(d) {
      this.movementSucceeded = this.canPass(this.x, this.y, d);
      if (this.movementSucceeded) { this.setDirection(d); this.x = xWith(this.x, d); this.y = yWith(this.y, d); this.stopCount = 0; }
      else { this.setDirection(d); this.checkEventTriggerTouchFront(d); }
      return this.movementSucceeded;
    }
    checkEventTriggerTouchFront() {}
    moveRandom() { this.moveStraight([2, 4, 6, 8][this.world ? this.world.rng.next(4) : 0]); }
    moveToward(c) {
      const sx = this.x - c.x, sy = this.y - c.y;
      if (sx === 0 && sy === 0) return;
      if (Math.abs(sx) > Math.abs(sy)) { if (!this.moveStraight(sx > 0 ? 4 : 6) && sy !== 0) this.moveStraight(sy > 0 ? 8 : 2); }
      else if (!this.moveStraight(sy > 0 ? 8 : 2) && sx !== 0) this.moveStraight(sx > 0 ? 4 : 6);
    }
    moveAway(c) { const sx = this.x - c.x, sy = this.y - c.y; if (Math.abs(sx) > Math.abs(sy)) this.moveStraight(sx > 0 ? 6 : 4); else this.moveStraight(sy > 0 ? 2 : 8); }
    turnToward(c) { const sx = this.x - c.x, sy = this.y - c.y; if (Math.abs(sx) > Math.abs(sy)) this.setDirection(sx > 0 ? 4 : 6); else if (sy !== 0) this.setDirection(sy > 0 ? 8 : 2); }
    forceMoveRoute(list, rep, skip) { this.moveRoute = list; this.moveRouteRepeat = rep; this.moveRouteSkippable = skip; this.moveRouteIndex = 0; this.moveRouteForcing = true; this.routeWait = 0; }
    setCustomRoute(list, rep, skip) { this.moveRoute = list; this.moveRouteRepeat = rep; this.moveRouteSkippable = skip; this.moveRouteIndex = 0; }
    updateRoutineMove() {
      if (this.routeWait > 0) { this.routeWait--; return; }
      this.movementSucceeded = true;
      if (this.moveRouteIndex >= this.moveRoute.length) { this.moveRouteForcing = false; return; }
      this.processMoveCommand(this.moveRoute[this.moveRouteIndex]);
      if (this.movementSucceeded || this.moveRouteSkippable) {
        this.moveRouteIndex++;
        if (this.moveRouteRepeat && this.moveRouteIndex >= this.moveRoute.length - 1) this.moveRouteIndex = 0;
      }
    }
    processMoveCommand(c) {
      const p = c.parameters, w = this.world; if (!w) return;
      const rot = { 2: 4, 4: 8, 6: 2, 8: 6 }, rotR = { 2: 6, 4: 2, 6: 8, 8: 4 };
      switch (c.code) {
        case 0: if (this.moveRouteRepeat) this.moveRouteIndex = -1; else if (this.moveRouteForcing) this.moveRouteForcing = false; break;
        case 1: this.moveStraight(2); break; case 2: this.moveStraight(4); break; case 3: this.moveStraight(6); break; case 4: this.moveStraight(8); break;
        case 9: this.moveRandom(); break; case 10: this.moveToward(w.player); break; case 11: this.moveAway(w.player); break;
        case 12: this.moveStraight(this.direction); break;
        case 13: { const d = this.direction, fix = this.directionFix; this.directionFix = true; this.moveStraight(reverse(d)); this.directionFix = fix; break; }
        case 15: this.routeWait = Math.max(0, P.int(p[0]) - 1); break;
        case 16: this.setDirection(2); break; case 17: this.setDirection(4); break; case 18: this.setDirection(6); break; case 19: this.setDirection(8); break;
        case 22: this.setDirection(reverse(this.direction)); break;
        case 24: this.setDirection([2, 4, 6, 8][w.rng.next(4)]); break;
        case 25: this.turnToward(w.player); break;
        case 27: w.state.setSwitch(P.int(p[0]), true); break; case 28: w.state.setSwitch(P.int(p[0]), false); break;
        case 29: this.moveSpeed = P.int(p[0]); break; case 30: this.moveFrequency = P.int(p[0]); break;
        case 31: this.walkAnime = true; break; case 32: this.walkAnime = false; break; case 33: this.stepAnime = true; break; case 34: this.stepAnime = false; break;
        case 35: this.directionFix = true; break; case 36: this.directionFix = false; break; case 37: this.through = true; break; case 38: this.through = false; break;
        case 39: this.transparent = true; break; case 40: this.transparent = false; break;
        case 41: this.setImage(P.str(p[0]), P.int(p[1])); break;
        case 44: { const f = LK.norm.audio(p[0]); if (f) w.audio.playSe(f); break; }
        case 45: w.script.run(P.str(p[0]), null); break;
        case 14: break;
        case 5: case 6: case 7: case 8: {
          const [h, vv] = [[4, 2], [6, 2], [4, 8], [6, 8]][c.code - 5];
          if (this.canPass(this.x, this.y, h) && this.canPass(xWith(this.x, h), this.y, vv)) { this.moveStraight(h); this.moveStraight(vv); } else this.movementSucceeded = false;
          break;
        }
        case 20: this.setDirection(rot[this.direction] || this.direction); break;
        case 21: this.setDirection(rotR[this.direction] || this.direction); break;
        case 23: this.setDirection(w.rng.next(2) === 0 ? (rot[this.direction] || this.direction) : (rotR[this.direction] || this.direction)); break;
        case 26: this.turnToward(w.player); this.setDirection(reverse(this.direction)); break;
        default: break;
      }
      if (this.moveRouteIndex < 0) { this.moveRouteIndex = 0; this.movementSucceeded = false; }
    }
  }
  LK.GameCharacter = GameCharacter;

  class GamePlayer extends GameCharacter {
    constructor() { super(); this.moveSpeed = 4; this.priorityType = 1; }
    checkEventTriggerTouchFront(d) { if (this.world && !this.world.vehicle) this.world.startMapEvent(xWith(this.x, d), yWith(this.y, d), [1, 2], true); }
    canPass(x, y, d) {
      const w = this.world; const v = w && w.vehicle;
      if (!w || !v || this.through) return super.canPass(x, y, d);
      const x2 = xWith(x, d), y2 = yWith(y, d);
      if (!M.isValid(w.map, x2, y2)) return false;
      if (v.kind === 2) return true;
      return v.isPassableAt(x2, y2) && !this.isCollided(x2, y2);
    }
  }
  LK.GamePlayer = GamePlayer;

  class GameFollower extends GameCharacter {
    constructor() { super(); this.through = true; this.moveSpeed = 4; }
    chase(tx, ty) {
      const sx = tx - this.x, sy = ty - this.y;
      if (sx === 0 && sy === 0) return;
      const p = this.world && this.world.player; if (p) { this.moveSpeed = p.moveSpeed; this.dashing = p.dashing; }
      this.moveStraight(Math.abs(sx) > Math.abs(sy) ? (sx > 0 ? 6 : 4) : (sy > 0 ? 2 : 8));
    }
  }
  LK.GameFollower = GameFollower;

  class GameEvent extends GameCharacter {
    constructor(data, world) {
      super();
      this.eventId = data.id; this.data = data; this.pageIndex = -1; this.erased = false; this.starting = false; this.locked = false;
      this.prelockDirection = 0; this.trigger = -1; this.moveType = 0; this.parallel = null; this.world = world;
      this.locate(data.x, data.y);
      this.refresh();
    }
    get page() { return this.pageIndex >= 0 ? this.data.pages[this.pageIndex] : null; }
    get list() { return this.page ? this.page.list : []; }
    refresh() { const n = this.erased ? -1 : this.findProperPageIndex(); if (n !== this.pageIndex) { this.pageIndex = n; this.setupPage(); } }
    findProperPageIndex() { for (let i = this.data.pages.length - 1; i >= 0; i--) if (this.meetsConditions(this.data.pages[i])) return i; return -1; }
    meetsConditions(page) {
      const w = this.world, c = page.conditions, s = w.state;
      if (c.switch1Valid && !s.switchValue(c.switch1Id)) return false;
      if (c.switch2Valid && !s.switchValue(c.switch2Id)) return false;
      if (c.variableValid && s.variable(c.variableId) < c.variableValue) return false;
      if (c.selfSwitchValid && !s.selfSwitch(s.mapId, this.eventId, c.selfSwitchCh)) return false;
      if (c.itemValid && s.itemCount(c.itemId) === 0) return false;
      if (c.actorValid && !s.party.includes(c.actorId)) return false;
      return true;
    }
    setupPage() {
      this.parallel = null;
      const p = this.page;
      if (!p) { this.characterName = ""; this.tileId = 0; this.priorityType = 0; this.trigger = -1; this.through = true; this.moveRouteForcing = false; return; }
      this.tileId = p.image.tileId; this.characterName = p.image.characterName; this.characterIndex = p.image.characterIndex;
      if (p.image.direction !== 0) this.direction = p.image.direction;
      this.pattern = p.image.pattern; this.moveSpeed = p.moveSpeed; this.moveFrequency = p.moveFrequency;
      this.priorityType = p.priorityType; this.walkAnime = p.walkAnime; this.stepAnime = p.stepAnime; this.directionFix = p.directionFix; this.through = p.through;
      this.moveType = p.moveType; this.trigger = p.trigger;
      if (this.moveType === 3 && p.moveRoute && typeof p.moveRoute === "object") {
        this.setCustomRoute(routeList(p.moveRoute), p.moveRoute.repeat === undefined ? true : P.bool(p.moveRoute.repeat), P.bool(p.moveRoute.skippable));
      }
      if (this.trigger === 4) this.parallel = new LK.Interpreter(0);
    }
    isTriggerIn(t) { return t.includes(this.trigger); }
    start() { const l = this.list; if (!l.length || (l.length <= 1 && l[0].code === 0)) return; this.starting = true; if (this.isTriggerIn([0, 1, 2])) this.lock(); }
    clearStartingFlag() { this.starting = false; }
    lock() { if (this.locked || !this.world) return; this.prelockDirection = this.direction; this.turnToward(this.world.player); this.locked = true; }
    unlock() { if (!this.locked) return; this.locked = false; this.setDirection(this.prelockDirection); }
    erase() { this.erased = true; this.refresh(); }
    update() {
      super.update();
      if (this.trigger === 3) this.start();
      if (this.parallel && this.world) { if (!this.parallel.isRunning) this.parallel.setup(this.list, this.eventId); this.parallel.update(this.world); }
    }
    updateSelfMovement() {
      const w = this.world;
      if (this.locked || !w || this.pageIndex < 0) return;
      if (this.stopCount > 30 * (5 - this.moveFrequency)) {
        switch (this.moveType) {
          case 1: { const r = w.rng.next(6); if (r <= 1) this.moveRandom(); else if (r <= 4) this.moveStraight(this.direction); else this.stopCount = 0; break; }
          case 2: this.moveToward(w.player); break;
          case 3: if (this.moveRoute.length) this.updateRoutineMove(); break;
        }
      }
    }
    isCollided(x, y) {
      if (super.isCollided(x, y)) return true;
      const p = this.world && this.world.player;
      if (!p || !this.isNormalPriority) return false;
      return !p.through && p.x === x && p.y === y;
    }
    checkEventTriggerTouchFront(d) {
      const w = this.world;
      if (!w || w.isEventRunning || this.trigger !== 2 || !this.isNormalPriority) return;
      if (w.player.x === xWith(this.x, d) && w.player.y === yWith(this.y, d)) this.start();
    }
  }
  LK.GameEvent = GameEvent;

  class GameVehicle extends GameCharacter {
    constructor(kind, data) {
      super();
      this.kind = kind; this.mapId = 0; this.driving = false; this.altitude = 0;
      this.setImage(data.characterName, data.characterIndex); this.mapId = data.startMapId; this.locate(data.startX, data.startY);
      this.moveSpeed = [4, 5, 6][kind]; this.priorityType = kind === 2 ? 2 : 1; this.walkAnime = true; this.stepAnime = false;
    }
    get bgm() { const s = this.world && this.world.project.system; return s ? [s.boat, s.ship, s.airship][this.kind].bgm : null; }
    isPassableAt(x, y) {
      const w = this.world; if (!w || !M.isValid(w.map, x, y)) return false;
      if (this.kind === 0) return M.checkPassage(w.map, x, y, 0x200, w.tileset);
      if (this.kind === 1) return M.checkPassage(w.map, x, y, 0x400, w.tileset);
      return true;
    }
    isLandOk(x, y, d) {
      const w = this.world;
      if (this.kind === 2) return M.checkPassage(w.map, x, y, 0x800, w.tileset) && M.checkPassage(w.map, x, y, 0x0f, w.tileset) && !w.events.some(e => e.x === x && e.y === y && e.pageIndex >= 0);
      const x2 = xWith(x, d), y2 = yWith(y, d);
      if (!M.isValid(w.map, x2, y2) || !M.isPassable(w.map, x2, y2, reverse(d), w.tileset)) return false;
      return !w.events.some(e => e.x === x2 && e.y === y2 && e.isNormalPriority && !e.through && e.pageIndex >= 0);
    }
    update() { super.update(); if (this.kind === 2) this.altitude = this.driving ? Math.min(48, this.altitude + 1) : Math.max(0, this.altitude - 1); }
    get save() { return { mapId: this.mapId, x: this.x, y: this.y, direction: this.direction }; }
  }
  LK.GameVehicle = GameVehicle;

  // ---------- GameWorld ----------
  class GameWorld {
    constructor(project, rng) {
      this.project = project; this.rng = rng || new LK.SystemRandom();
      this.state = new LK.GameState(); this.map = LK.norm.emptyMap(1, 1); this.tileset = LK.norm.tileset({});
      this.player = new GamePlayer(); this.player.world = this; this.followers = []; this.events = []; this.vehicles = [];
      this.message = null; this.transferPending = null; this.brightness = 255; this.fadeTarget = 255; this.fadeDuration = 0;
      this.gameOver = false; this.returnToTitle = false; this.mapGeneration = 0; this.frameCount = 0; this.audio = new LK.AudioState();
      this.battle = null; this.shop = null; this.nameInput = null; this.requestMenu = false; this.requestSave = false; this.mapDamageFlash = 0;
      this.lastInput = LK.newInput(); this.followersVisible = true; this.lastActions = [0, 0, 0, 0, 0, 0];
      this.mainInterpreter = new LK.Interpreter(0); this.commonParallels = {}; this.reservedCommonEvents = []; this.actors = {};
      this.encounterCount = 0; this.pluginsLoaded = false; this.actorStepCounters = {}; this.boarding = null;
      this._script = null;
    }
    get script() { if (!this._script) this._script = new LK.ScriptEngine(this); return this._script; }
    get animationFrame() { return idiv(this.frameCount, 30); }
    lastActionData(i) { return this.lastActions[i] || 0; }

    newGame() {
      this.mainInterpreter.clear(); this.state = new LK.GameState(); this.actors = {};
      this.state.party = this.project.system.partyMembers.filter(id => this.project.actor(id));
      for (const id of this.state.party) this.actor(id);
      this.setupVehicles(null); this.loadPluginsOnce(); this.refreshPlayerImage();
      this.setupMap(this.project.system.startMapId, this.project.system.startX, this.project.system.startY, 2);
      this.makeEncounterCount();
    }
    makeSave() {
      const s = LK.GameState.fromJSON(JSON.parse(JSON.stringify(this.state)));
      s.playerX = this.player.x; s.playerY = this.player.y; s.playerDirection = this.player.direction;
      s.actors = {}; for (const k of Object.keys(this.actors)) s.actors[k] = this.actors[k].save;
      s.vehicles = this.vehicles.map(v => v.save); s.bgm = this.audio.currentBgm; s.bgs = this.audio.currentBgs; s.saveCount++;
      return s;
    }
    load(s) {
      this.mainInterpreter.clear();
      this.message = null; this.transferPending = null; this.shop = null; this.nameInput = null; this.battle = null;
      this.reservedCommonEvents = []; this.fadeDuration = 0; this.brightness = 255;
      this.state = s; this.actors = {};
      for (const id of Object.keys(s.actors || {})) if (this.project.actor(Number(id))) { const a = LK.GameActor.fromSave(this.project, s.actors[id]); a.rng = this.rng; this.actors[id] = a; }
      this.setupVehicles(s.vehicles); this.loadPluginsOnce(); this.refreshPlayerImage();
      const par = s.parallax, had = s.hasSavedParallax;
      this.setupMap(s.mapId, s.playerX, s.playerY, s.playerDirection);
      if (had) this.state.parallax = par;
      if (s.bgm) this.audio.playBgm(s.bgm); else this.audio.stopBgm();
      if (s.bgs) this.audio.playBgs(s.bgs);
      this.makeEncounterCount();
    }
    loadPluginsOnce() { if (this.pluginsLoaded) return; this.pluginsLoaded = true; this.script.loadPlugins(this.project); }
    actor(id) {
      if (this.actors[id]) return this.actors[id];
      if (!this.project.actor(id)) return null;
      return (this.actors[id] = new LK.GameActor(this.project, id, this.rng));
    }
    get partyMembers() { return this.state.party.slice(0, 4).map(id => this.actor(id)).filter(a => a); }
    get allMembers() { return this.state.party.map(id => this.actor(id)).filter(a => a); }
    addActor(id) { if (!this.project.actor(id) || this.state.party.includes(id)) return; this.state.party.push(id); this.state.needsRefresh = true; this.refreshPlayerImage(); }
    removeActor(id) { this.state.party = this.state.party.filter(x => x !== id); this.state.needsRefresh = true; this.refreshPlayerImage(); }
    get isAllDead() { const m = this.partyMembers; return m.length > 0 && m.every(a => a.isDead); }
    partyHasAbility(id) { return this.partyMembers.some(a => a.allTraits().some(t => t.code === 64 && t.dataId === id)); }
    refreshPlayerImage() {
      const members = this.partyMembers;
      const leader = members[0] ? this.project.actor(members[0].actorId) : null;
      this.player.setImage(leader ? leader.characterName : "", leader ? leader.characterIndex : 0);
      const others = members.slice(1);
      while (this.followers.length < others.length) { const f = new GameFollower(); f.world = this; f.locate(this.player.x, this.player.y); f.direction = this.player.direction; this.followers.push(f); }
      if (this.followers.length > others.length) this.followers.length = others.length;
      others.forEach((a, i) => { const d = this.project.actor(a.actorId); this.followers[i].setImage(d ? d.characterName : "", d ? d.characterIndex : 0); });
    }
    setupMap(id, x, y, d) {
      this.state.mapId = id;
      this.map = this.project.maps[id] || LK.norm.emptyMap(17, 13);
      this.tileset = this.project.tilesetFor(this.map);
      this.player.locate(LK.clamp(x, 0, this.map.width - 1), LK.clamp(y, 0, this.map.height - 1));
      if (d !== 0) this.player.direction = d;
      for (const f of this.followers) { f.locate(this.player.x, this.player.y); f.direction = this.player.direction; }
      this.events = M.liveEvents(this.map).map(e => new GameEvent(e, this));
      this.state.parallax = new LK.ParallaxState(this.map);
      this.commonParallels = {};
      const v = this.vehicle; if (v) { v.mapId = id; v.locate(this.player.x, this.player.y); v.direction = this.player.direction; }
      this.mapGeneration++;
      if (!v) { if (this.map.autoplayBgm) this.audio.playBgm(this.map.bgm); if (this.map.autoplayBgs) this.audio.playBgs(this.map.bgs); }
      this.script.emit("mapStart", [id]);
    }
    changeTileset(id) { this.map = Object.assign({}, this.map, { tilesetId: id }); this.tileset = this.project.tilesetFor(this.map); this.mapGeneration++; }
    get visibleVehicles() { return this.vehicles.filter(v => v.mapId === this.state.mapId && v.characterName); }

    update(input) {
      this.frameCount++; this.lastInput = input; this.state.playFrames++;
      if (this.mapDamageFlash > 0) this.mapDamageFlash--;
      this.updateFade(); this.state.screen.update();
      if (this.battle) {
        const b = this.battle;
        if (this.message) this.updateMessage(input);
        b.update();
        if (b.isFinished) this.battle = null;
        return;
      }
      if (this.shop || this.nameInput) return;
      this.state.parallax.update();
      const t = this.transferPending;
      if (t && this.fadeDuration === 0) {
        if (this.brightness > 0 && t.fade === 0) this.startFade(0, 12);
        else { this.transferPending = null; this.setupMap(t.mapId, t.x, t.y, t.d); if (t.fade === 0) this.startFade(255, 12); }
        return;
      }
      if (this.state.needsRefresh) this.refreshEvents();
      const inputConsumed = this.message !== null;
      if (inputConsumed) this.updateMessage(input);
      this.updateInterpreter();
      if (this.battle || this.shop || this.nameInput) return;
      this.updateCommonParallels();
      const wasMoving = this.player.isMoving, wpx = this.player.x, wpy = this.player.y;
      if (this.canPlayerMove && input.dir4 !== 0 && !this.player.isMoving) {
        this.player.dashing = input.dash && !this.map.disableDashing && !this.vehicle;
        if (this.player.moveStraight(input.dir4)) {
          this.state.steps++;
          let tx = wpx, ty = wpy;
          for (const f of this.followers) { const bx = f.x, by = f.y; f.chase(tx, ty); tx = bx; ty = by; }
        }
      }
      this.player.update();
      for (const f of this.followers) f.update();
      for (const e of this.events) e.update();
      for (const v of this.vehicles) if (v.mapId === this.state.mapId) v.update();
      const veh = this.vehicle;
      if (veh && !this.boarding) { veh.locate(this.player.x, this.player.y); veh.realX = this.player.realX; veh.realY = this.player.realY; veh.direction = this.player.direction; }
      this.updateVehicleBoarding();
      if (this.canPlayerMove) {
        if (wasMoving && !this.player.isMoving) {
          this.onPlayerStep();
          this.startMapEvent(this.player.x, this.player.y, [1, 2], false);
          if (!this.isEventRunning) this.updateEncounter();
        }
        if (!this.isEventRunning && !this.player.isMoving && input.ok && !inputConsumed) this.triggerAction();
      }
      if (this.state.needsRefresh) this.refreshEvents();
      this.script.emit("update");
    }
    get isEventRunning() { return this.mainInterpreter.isRunning || this.events.some(e => e.starting) || this.reservedCommonEvents.length > 0; }
    get canPlayerMove() { return !this.isEventRunning && !this.message && !this.transferPending && this.fadeDuration === 0 && !this.player.moveRouteForcing && !this.boarding; }
    refreshEvents() { this.state.needsRefresh = false; for (const e of this.events) e.refresh(); }
    updateInterpreter() {
      for (let i = 0; i < 64; i++) {
        this.mainInterpreter.update(this);
        if (this.mainInterpreter.isRunning) return;
        if (this.mainInterpreter.eventId > 0) { const e = this.events.find(ev => ev.eventId === this.mainInterpreter.eventId); if (e) e.unlock(); }
        this.mainInterpreter.clear();
        if (!this.setupStartingEvent()) return;
      }
    }
    setupStartingEvent() {
      if (this.state.needsRefresh) this.refreshEvents();
      if (this.reservedCommonEvents.length) {
        const id = this.reservedCommonEvents.shift(); const ce = this.project.commonEvents[id];
        if (ce) { this.mainInterpreter.setup(ce.list, 0, this.state.mapId); return true; }
      }
      const e = this.events.find(ev => ev.starting);
      if (e) { e.clearStartingFlag(); this.mainInterpreter.setup(e.list, e.eventId, this.state.mapId); return true; }
      for (const ce of this.project.commonEvents) if (ce && ce.trigger === 1 && this.state.switchValue(ce.switchId)) { this.mainInterpreter.setup(ce.list, 0, this.state.mapId); return true; }
      return false;
    }
    reserveCommonEvent(id) { this.reservedCommonEvents.push(id); }
    updateCommonParallels() {
      for (const ce of this.project.commonEvents) {
        if (!ce || ce.trigger !== 2) continue;
        if (!this.state.switchValue(ce.switchId)) { delete this.commonParallels[ce.id]; continue; }
        const i = this.commonParallels[ce.id] || (this.commonParallels[ce.id] = new LK.Interpreter(0));
        if (!i.isRunning) i.setup(ce.list, 0, this.state.mapId);
        i.update(this);
      }
    }
    startMapEvent(x, y, triggers, normal) {
      if (this.isEventRunning || (this.vehicle && this.vehicle.kind === 2)) return;
      for (const e of this.events) if (e.x === x && e.y === y && e.isTriggerIn(triggers) && e.isNormalPriority === normal) e.start();
    }
    triggerAction() {
      if (this.getOnOffVehicle()) return;
      this.startMapEvent(this.player.x, this.player.y, [0], false);
      if (this.isEventRunning) return;
      const d = this.player.direction, x2 = xWith(this.player.x, d), y2 = yWith(this.player.y, d);
      this.startMapEvent(x2, y2, [0, 1, 2], true);
      if (!this.isEventRunning && this.isCounter(x2, y2)) this.startMapEvent(xWith(x2, d), yWith(y2, d), [0, 1, 2], true);
    }
    layeredFlag(x, y, bit) {
      if (!M.isValid(this.map, x, y)) return false;
      for (let z = 0; z < 4; z++) { const id = M.tileId(this.map, x, y, z); if (id > 0 && (M.flag(this.tileset, id) & bit)) return true; }
      return false;
    }
    isLadder(x, y) { return this.layeredFlag(x, y, 0x20); }
    isBush(x, y) { return this.layeredFlag(x, y, 0x40); }
    isCounter(x, y) { return this.layeredFlag(x, y, 0x80); }
    isDamageFloor(x, y) { return this.layeredFlag(x, y, 0x100); }
    terrainTag(x, y) { for (let z = 3; z >= 0; z--) { const t = M.flag(this.tileset, M.tileId(this.map, x, y, z)) >> 12; if (t > 0) return t; } return 0; }
    onPlayerStep() {
      if (this.vehicle) return;
      if (this.isLadder(this.player.x, this.player.y)) this.player.direction = 8;
      for (const a of this.partyMembers) {
        if (this.isDamageFloor(this.player.x, this.player.y)) {
          const dmg = Math.min(Math.floor(10 * a.fdr), this.project.system.optFloorDeath ? a.hp : Math.max(a.hp - 1, 0));
          if (dmg > 0) { a.gainHp(-dmg); this.mapDamageFlash = 8; }
        }
        for (const st of a.sortedStates) {
          if (!st.removeByWalking) continue;
          const c = this.actorStepCounters[a.actorId] || (this.actorStepCounters[a.actorId] = {});
          c[st.id] = (c[st.id] || 0) + 1;
          if (c[st.id] >= st.stepsToRemove) { a.removeState(st.id); delete c[st.id]; }
        }
        if (this.state.steps % 20 === 0 && a.states.length) { const hp = a.hp; a.onTurnEnd(this.project.system.optSlipDeath); if (a.hp < hp) this.mapDamageFlash = 8; }
      }
      if (this.isAllDead) this.gameOver = true;
    }
    makeEncounterCount() { const n = Math.max(1, this.map.encounterStep); this.encounterCount = this.rng.next(n) + this.rng.next(n) + 1; }
    updateEncounter() {
      const vk = this.vehicle ? this.vehicle.kind : -1;
      if (!this.state.encounterEnabled || vk === 2 || !this.map.encounterList.length || this.partyHasAbility(1)) return;
      let progress = this.isBush(this.player.x, this.player.y) ? 2 : 1;
      if (this.partyHasAbility(0)) progress *= 0.5;
      if (vk === 1) progress *= 0.5;
      this.encounterCount -= Math.ceil(progress);
      if (this.encounterCount > 0) return;
      this.makeEncounterCount();
      const region = M.regionId(this.map, this.player.x, this.player.y);
      const list = this.map.encounterList.filter(e => !e.regionSet.length || e.regionSet.includes(region));
      const sum = list.reduce((a, e) => a + e.weight, 0);
      if (sum <= 0) return;
      let val = this.rng.next(sum);
      for (const e of list) { val -= e.weight; if (val < 0) { this.startBattle(e.troopId, true, false, true); return; } }
    }
    startBattle(troopId, canEscape, canLose, encounter, onEnd) {
      if (!this.project.troop(troopId) || !this.partyMembers.length) return;
      const b = new LK.BattleManager(this, troopId, canEscape, canLose);
      if (encounter) {
        const pm = this.partyMembers;
        const partyAgi = idiv(pm.reduce((s, a) => s + a.agi, 0), Math.max(1, pm.length));
        const troopAgi = idiv(b.enemies.reduce((s, e) => s + e.agi, 0), Math.max(1, b.enemies.length));
        const pre = (partyAgi >= troopAgi ? 0.05 : 0.03) * (this.partyHasAbility(3) ? 4 : 1);
        const sur = this.partyHasAbility(2) ? 0 : (partyAgi >= troopAgi ? 0.03 : 0.05);
        const r = this.rng.next(1000) / 1000;
        if (r < pre) b.preemptive = true; else if (r < pre + sur) b.surprise = true;
      }
      b.battleback1 = this.map.specifyBattleback ? this.map.battleback1Name : this.project.system.battleback1Name;
      b.battleback2 = this.map.specifyBattleback ? this.map.battleback2Name : this.project.system.battleback2Name;
      this.audio.saveBgm();
      const bgs = this.audio.currentBgs;
      this.audio.playBgm(this.state.battleBgm || this.project.system.battleBgm);
      this.audio.fadeOutBgs(1);
      this.state.battleCount++;
      b.onEnd = o => {
        if (o === 0) this.state.winCount++; else if (o === 1) this.state.escapeCount++;
        this.state.screen.clearForBattleEnd();
        if (o === 2 && !canLose) this.gameOver = true;
        this.audio.replayBgm();
        if (bgs) this.audio.playBgs(bgs);
        if (onEnd) onEnd(o);
        this.state.needsRefresh = true;
        this.script.emit("battleEnd", [o]);
      };
      this.battle = b;
      this.script.emit("battleStart", [troopId]);
    }
    setupVehicles(saves) {
      const s = this.project.system;
      this.vehicles = [0, 1, 2].map(k => {
        const v = new GameVehicle(k, [s.boat, s.ship, s.airship][k]); v.world = this;
        if (saves && k < saves.length) { v.mapId = saves[k].mapId; v.locate(saves[k].x, saves[k].y); v.direction = saves[k].direction; }
        return v;
      });
      const v = this.vehicle;
      if (v) { v.driving = true; v.stepAnime = true; v.altitude = v.kind === 2 ? 48 : 0; this.player.transparent = true; this.player.through = v.kind === 2; this.player.moveSpeed = v.moveSpeed; }
      else { this.player.transparent = false; this.player.through = false; this.player.moveSpeed = 4; }
    }
    get vehicle() { const t = this.state.vehicleType; return t >= 0 && t < this.vehicles.length ? this.vehicles[t] : null; }
    get vehicleTypeName() { return ["boat", "ship", "airship"][this.state.vehicleType] || "walk"; }
    getOnOffVehicle() {
      const cur = this.vehicle; if (cur) return this.getOff(cur);
      const d = this.player.direction, x2 = xWith(this.player.x, d), y2 = yWith(this.player.y, d);
      const here = this.visibleVehicles.find(v => v.kind === 2 && v.x === this.player.x && v.y === this.player.y);
      const front = this.visibleVehicles.find(v => v.kind !== 2 && v.x === x2 && v.y === y2);
      const v = here || front; if (!v) return false;
      this.state.vehicleType = v.kind;
      if (v.kind !== 2) { this.player.through = true; this.player.moveStraight(d); this.player.through = false; }
      this.boarding = { v, on: true };
      return true;
    }
    getOff(v) {
      if (!v.isLandOk(this.player.x, this.player.y, this.player.direction)) return false;
      if (v.kind === 2) this.player.direction = 2;
      v.driving = false; v.stepAnime = false; this.player.moveSpeed = 4; this.player.through = false;
      if (v.kind !== 2) { this.player.transparent = false; this.player.through = true; this.player.moveStraight(this.player.direction); this.player.through = false; }
      this.state.vehicleType = -1; this.boarding = { v, on: false }; this.audio.replayBgm(); this.makeEncounterCount();
      return true;
    }
    updateVehicleBoarding() {
      const b = this.boarding; if (!b) return;
      const v = b.v;
      if (b.on) {
        if (this.player.isMoving) return;
        this.player.direction = v.direction; this.player.moveSpeed = v.moveSpeed; this.player.transparent = true;
        if (v.kind === 2) this.player.through = true;
        v.driving = true; v.stepAnime = true; this.audio.saveBgm(); if (v.bgm) this.audio.playBgm(v.bgm);
        this.boarding = null;
      } else {
        if (v.kind === 2 && v.altitude > 0) return;
        this.player.transparent = false;
        for (const f of this.followers) f.locate(this.player.x, this.player.y);
        this.boarding = null;
      }
    }
    setVehicleLocation(kind, mapId, x, y) { if (kind < this.vehicles.length) { this.vehicles[kind].mapId = mapId; this.vehicles[kind].locate(x, y); } }
    updateMessage(input) {
      const m = this.message; if (!m) return;
      if (m.scrolling) { m.scrollOffset += m.scrollSpeed * (input.ok ? 3 : 0.5); if (m.scrollOffset > m.lines.length * 36 + 700) this.message = null; return; }
      if (!m.isTextComplete) { m.visibleChars = input.ok ? [...m.text].length : m.visibleChars + 1; return; }
      if (m.numberDigits > 0) {
        const place = Math.pow(10, m.numberDigits - 1 - m.numberCursor), digit = idiv(m.number, place) % 10;
        if (input.up) m.number += (digit === 9 ? -9 : 1) * place;
        if (input.down) m.number += (digit === 0 ? 9 : -1) * place;
        if (input.right) m.numberCursor = Math.min(m.numberDigits - 1, m.numberCursor + 1);
        if (input.left) m.numberCursor = Math.max(0, m.numberCursor - 1);
        if (input.ok) { this.state.setVariable(m.numberVariable, m.number); this.message = null; }
        return;
      }
      if (m.itemChoiceVariable > 0) {
        const n = m.itemChoices.length + 1;
        if (input.up) m.itemChoiceIndex = (m.itemChoiceIndex + n - 1) % n;
        if (input.down) m.itemChoiceIndex = (m.itemChoiceIndex + 1) % n;
        if (input.ok) { this.state.setVariable(m.itemChoiceVariable, m.itemChoiceIndex < m.itemChoices.length ? m.itemChoices[m.itemChoiceIndex] : 0); this.message = null; }
        else if (input.cancel) { this.state.setVariable(m.itemChoiceVariable, 0); this.message = null; }
        return;
      }
      if (m.choices.length) {
        if (input.up) m.choiceIndex = (m.choiceIndex + m.choices.length - 1) % m.choices.length;
        if (input.down) m.choiceIndex = (m.choiceIndex + 1) % m.choices.length;
        if (input.ok) { if (m.onChoose) m.onChoose(m.choiceIndex); this.message = null; }
        else if (input.cancel && m.choiceCancel !== -1) { if (m.onChoose) m.onChoose(m.choiceCancel); this.message = null; }
        return;
      }
      if (input.ok || input.cancel) this.message = null;
    }
    addScriptMessage(t) { if (!this.message) this.message = LK.newMessage(); this.message.lines.push(this.convertEscapes(t)); }
    reserveTransfer(mapId, x, y, d, fade) { this.transferPending = { mapId, x, y, d, fade }; }
    startFade(target, d) { this.fadeTarget = target; this.fadeDuration = d; }
    updateFade() { if (this.fadeDuration <= 0) return; this.brightness = (this.brightness * (this.fadeDuration - 1) + this.fadeTarget) / this.fadeDuration; this.fadeDuration--; }
    get screen() { return this.state.screen; }
    useInMenu(itemId, skillId, user, target) {
      const action = skillId > 0 ? new LK.GameAction(user, skillId, 0) : new LK.GameAction(user, 0, itemId);
      const item = action.item;
      if (!item || !user.canUse(item, false)) return false;
      if (itemId > 0 && this.state.count(1, itemId) === 0) return false;
      const targets = LK.usable.isForAll(item) ? this.allMembers : [target || user];
      let any = false;
      for (const t of targets) {
        if (!action.testApply(t, item)) continue;
        action.apply(t, this.rng, (f, a, b) => this.script.evalFormula(f, a, b), id => this.reserveCommonEvent(id));
        any = any || t.result.isHit;
      }
      if (item.effects.some(e => e.code === 44)) any = true;
      if (!any) { this.playSystemSound(3); return false; }
      if (item.isSkill) user.paySkillCost(item);
      if (!item.isSkill && item.consumable) this.state.gain(1, item.id, -1);
      this.playSystemSound(item.isSkill ? 23 : 22);
      return true;
    }
    equip(actor, slot, itemId) {
      if (actor.isEquipLocked(slot)) return;
      const kind = slot === 0 ? 2 : 3;
      if (itemId > 0) { if (this.state.count(kind, itemId) <= 0 || !actor.canEquip(slot, itemId)) return; this.state.gain(kind, itemId, -1); }
      const old = actor.changeEquip(slot, itemId);
      if (old > 0) this.state.gain(kind, old, 1);
      this.playSystemSound(4);
    }
    playSystemSound(i) { const s = this.project.system.sounds[i]; if (s) this.audio.playSe(s); }
    convertEscapes(text) {
      let t = text.split("\\\\").join("\u001B");
      const sub = (re, f) => { for (let k = 0; k < 2; k++) t = t.replace(re, (_, n) => f(parseInt(n, 10) || 0)); };
      sub(/\\V\[(\d+)\]/gi, n => String(this.state.variable(n)));
      sub(/\\N\[(\d+)\]/gi, n => { const a = this.actor(n); return a ? a.name : ""; });
      sub(/\\P\[(\d+)\]/gi, n => { const id = n >= 1 && n <= this.state.party.length ? this.state.party[n - 1] : 0; const a = this.actor(id); return a ? a.name : ""; });
      t = t.replace(/\\G/gi, this.project.system.currencyUnit);
      t = t.replace(/\\(PX|PY|FS)\[\d+\]|\\[{}$.|!><^]/g, "");
      return t.split("\u001B").join("\\");
    }
  }
  LK.GameWorld = GameWorld;

  LK.Shop = {
    name: (kind, id, p) => { const x = kind === 1 ? p.weapon(id) : kind === 2 ? p.armor(id) : p.item(id); return x ? x.name : "?"; },
    basePrice: (kind, id, p) => { const x = kind === 1 ? p.weapon(id) : kind === 2 ? p.armor(id) : p.item(id); return x ? x.price : 0; },
    stateKind: k => k + 1,
    maxBuy: (g, w) => { const owned = w.state.count(g.kind + 1, g.id); const byGold = g.price > 0 ? idiv(w.state.gold, g.price) : 99; return Math.max(0, Math.min(99 - owned, byGold)); },
    buy: (g, qty, w) => { if (qty <= 0 || qty > LK.Shop.maxBuy(g, w)) return; w.state.gainGold(-g.price * qty); w.state.gain(g.kind + 1, g.id, qty); w.playSystemSound(21); },
    sell: (kind, id, qty, w) => { if (qty <= 0 || w.state.count(kind + 1, id) < qty) return; w.state.gainGold(idiv(LK.Shop.basePrice(kind, id, w.project), 2) * qty); w.state.gain(kind + 1, id, -qty); w.playSystemSound(21); },
  };

  // ---------- Interpreter ----------
  class Interpreter {
    constructor(depth) { this.depth = depth || 0; this.clear(); }
    get isRunning() { return this.list.length > 0; }
    setup(list, eventId, mapId) { this.clear(); this.list = list; this.eventId = eventId || 0; this.mapId = mapId || 0; }
    clear() { this.list = []; this.index = 0; this.eventId = 0; this.mapId = this.mapId || 0; this.indent = 0; this.branch = {}; this.waitCount = 0; this.waitMode = null; this.child = null; }
    update(w) {
      let guard = 0;
      while (this.isRunning) {
        if (this.child) { if (this.child.isRunning) { this.child.update(w); if (this.child.isRunning) return; } this.child = null; }
        if (this.updateWait(w)) return;
        if (!this.execute(w)) return;
        if (++guard > 100000) { this.clear(); return; }
      }
    }
    updateWait(w) {
      if (this.waitCount > 0) { this.waitCount--; return true; }
      const m = this.waitMode;
      if (!m) return false;
      let waiting = false;
      switch (m.t) {
        case "message": waiting = !!w.message; break;
        case "transfer": waiting = !!w.transferPending; break;
        case "fade": waiting = w.fadeDuration > 0; break;
        case "route": waiting = m.c.moveRouteForcing; break;
        case "battle": waiting = !!w.battle; break;
        case "scene": waiting = !!(w.shop || w.nameInput || w.requestMenu || w.requestSave); break;
        case "balloon": waiting = m.c.balloonFrames > 0; break;
        case "animation": waiting = m.c.animationFrames > 0; break;
      }
      if (waiting) return true;
      this.waitMode = null;
      return false;
    }
    execute(w) {
      if (this.index >= this.list.length) { this.list = []; return true; }
      const cmd = this.list[this.index];
      this.indent = cmd.indent;
      if (!this.command(cmd.code, cmd.parameters, w)) return false;
      this.index++;
      return true;
    }
    skipBranch() { while (this.index + 1 < this.list.length && this.list[this.index + 1].indent > this.indent) this.index++; }
    nextCode() { return this.index + 1 < this.list.length ? this.list[this.index + 1].code : 0; }
    character(id, w) { if (id < 0) return w.player; const eid = id === 0 ? this.eventId : id; return w.events.find(e => e.eventId === eid) || null; }
    operand(op, type, value, w) { const x = type === 0 ? value : w.state.variable(value); return op === 0 ? x : -x; }
    command(code, p, w) {
      const I = i => P.int(p[i]), S = i => P.str(p[i]), B = i => P.bool(p[i]), A = i => P.arr(p[i]);
      const audioOf = i => LK.norm.audio(p[i]);
      switch (code) {
        case 101: {
          if (w.message) return false;
          const m = LK.newMessage();
          m.faceName = S(0); m.faceIndex = I(1); m.background = I(2); m.positionType = I(3); m.speakerName = w.convertEscapes(S(4));
          while (this.nextCode() === 401) { this.index++; m.lines.push(w.convertEscapes(P.str(this.list[this.index].parameters[0]))); }
          if (this.nextCode() === 102) { this.index++; this.setupChoices(this.list[this.index].parameters, m, w); }
          else if (this.nextCode() === 103) { this.index++; this.setupNumberInput(this.list[this.index].parameters, m, w); }
          else if (this.nextCode() === 104) { this.index++; this.setupItemChoice(this.list[this.index].parameters, m, w); }
          w.message = m; this.waitMode = { t: "message" };
          break;
        }
        case 102: { if (w.message) return false; const m = LK.newMessage(); this.setupChoices(p, m, w); w.message = m; this.waitMode = { t: "message" }; break; }
        case 402: if (this.branch[this.indent] !== I(0)) this.skipBranch(); break;
        case 403: if (this.branch[this.indent] !== -2) this.skipBranch(); break;
        case 103: { if (w.message) return false; const m = LK.newMessage(); this.setupNumberInput(p, m, w); w.message = m; this.waitMode = { t: "message" }; break; }
        case 104: { if (w.message) return false; const m = LK.newMessage(); this.setupItemChoice(p, m, w); w.message = m; this.waitMode = { t: "message" }; break; }
        case 105: {
          if (w.message) return false;
          const m = LK.newMessage(); m.scrolling = true; m.scrollSpeed = Math.max(1, I(0));
          while (this.nextCode() === 405) { this.index++; m.lines.push(w.convertEscapes(P.str(this.list[this.index].parameters[0]))); }
          m.visibleChars = [...m.text].length; w.message = m; this.waitMode = { t: "message" };
          break;
        }
        case 108: case 408: case 404: case 412: case 0: break;
        case 111: { const r = this.conditionalBranch(p, w); this.branch[this.indent] = r ? 1 : 0; if (!r) this.skipBranch(); break; }
        case 411: if (this.branch[this.indent] !== 0) this.skipBranch(); break;
        case 112: break;
        case 413: do { this.index--; } while (this.index > 0 && this.list[this.index].indent !== this.indent); break;
        case 113: {
          let depth = 0;
          while (this.index < this.list.length - 1) {
            this.index++;
            const c = this.list[this.index];
            if (c.code === 112) depth++;
            if (c.code === 413) { if (depth > 0) depth--; else break; }
          }
          break;
        }
        case 115: this.index = this.list.length; break;
        case 117: {
          const id = I(0), ce = w.project.commonEvents[id];
          if (this.depth < 100 && ce) { const c = new Interpreter(this.depth + 1); c.setup(ce.list, this.eventId, this.mapId); this.child = c; }
          break;
        }
        case 121: for (let i = I(0); i <= Math.max(I(0), I(1)); i++) w.state.setSwitch(i, I(2) === 0); break;
        case 122: {
          let value;
          switch (I(3)) {
            case 0: value = I(4); break;
            case 1: value = w.state.variable(I(4)); break;
            case 2: { const lo = I(4), hi = I(5); value = lo + w.rng.next(Math.max(1, hi - lo + 1)); break; }
            case 3: value = this.gameData(I(4), I(5), I(6), w); break;
            case 4: value = w.script.evalNumber(S(4), this); break;
            default: value = 0;
          }
          for (let i = I(0); i <= Math.max(I(0), I(1)); i++) {
            const old = w.state.variable(i); let n;
            switch (I(2)) {
              case 1: n = old + value; break; case 2: n = old - value; break; case 3: n = old * value; break;
              case 4: n = value === 0 ? old : idiv(old, value); break; case 5: n = value === 0 ? old : old % value; break;
              default: n = value;
            }
            w.state.setVariable(i, n);
          }
          break;
        }
        case 123: if (this.eventId > 0) w.state.setSelfSwitch(this.mapId, this.eventId, S(0), I(1) === 0); break;
        case 125: w.state.gainGold(this.operand(I(0), I(1), I(2), w)); break;
        case 126: w.state.gainItem(I(0), this.operand(I(1), I(2), I(3), w)); break;
        case 129: { const a = I(0); if (I(1) === 0) { if (B(2)) delete w.actors[a]; w.addActor(a); } else w.removeActor(a); break; }
        case 132: { const f = audioOf(0); if (f) w.state.battleBgm = f; break; }
        case 133: { const f = audioOf(0); if (f) w.state.victoryMe = f; break; }
        case 134: w.state.saveEnabled = I(0) === 0; break;
        case 135: w.state.menuEnabled = I(0) === 0; break;
        case 136: w.state.encounterEnabled = I(0) === 0; break;
        case 202: {
          const direct = I(1) === 0;
          const m = direct ? I(2) : w.state.variable(I(2)), x = direct ? I(3) : w.state.variable(I(3)), y = direct ? I(4) : w.state.variable(I(4));
          w.setVehicleLocation(I(0), m, x, y);
          break;
        }
        case 206: w.getOnOffVehicle(); break;
        case 212: {
          const c = this.character(I(0), w);
          if (c) { const a = w.project.animation(I(1)); c.startAnimation(I(1), a ? a.totalFrames(1) : 0); if (B(2)) this.waitMode = { t: "animation", c }; }
          break;
        }
        case 213: { const c = this.character(I(0), w); if (c) { c.balloonId = I(1); c.balloonFrames = 64; if (B(2)) this.waitMode = { t: "balloon", c }; } break; }
        case 216: w.followersVisible = I(0) === 0; break;
        case 217: break;
        case 223: w.screen.startTint(A(0).map(P.int), I(1)); if (B(2)) this.waitCount = I(1); break;
        case 224: w.screen.startFlash(A(0).map(P.int), I(1)); if (B(2)) this.waitCount = I(1); break;
        case 225: w.screen.startShake(I(0), I(1), I(2)); if (B(3)) this.waitCount = I(2); break;
        case 231: { const [x, y] = this.picturePoint(p, w); w.screen.pictures[I(0)] = new LK.GamePicture(S(1), I(2), x, y, I(6), I(7), I(8), I(9)); break; }
        case 232: {
          const [x, y] = this.picturePoint(p, w), pic = w.screen.pictures[I(0)];
          if (pic) pic.move(I(2), x, y, I(6), I(7), I(8), I(9), I(10), I(12));
          if (B(11)) this.waitCount = I(10);
          break;
        }
        case 233: { const pic = w.screen.pictures[I(0)]; if (pic) pic.rotate(I(1)); break; }
        case 234: { const pic = w.screen.pictures[I(0)]; if (pic) pic.tint(A(1).map(P.int), I(2)); if (B(3)) this.waitCount = I(2); break; }
        case 235: delete w.screen.pictures[I(0)]; break;
        case 236: if (!w.battle) { w.screen.changeWeather(S(0), I(1), I(2)); if (B(3)) this.waitCount = I(2); } break;
        case 241: { const f = audioOf(0); if (f) w.audio.playBgm(f); break; }
        case 242: w.audio.fadeOutBgm(I(0)); break;
        case 243: w.audio.saveBgm(); break;
        case 244: w.audio.replayBgm(); break;
        case 245: { const f = audioOf(0); if (f) w.audio.playBgs(f); break; }
        case 246: w.audio.fadeOutBgs(I(0)); break;
        case 249: { const f = audioOf(0); if (f) w.audio.playMe(f); break; }
        case 250: { const f = audioOf(0); if (f) w.audio.playSe(f); break; }
        case 251: w.audio.stopSe(); break;
        case 282: w.changeTileset(I(0)); break;
        case 283: if (w.battle) { w.battle.battleback1 = S(0); w.battle.battleback2 = S(1); } break;
        case 284: w.state.parallax.change(S(0), B(1), B(2), I(3), I(4)); break;
        case 285: {
          const direct = I(2) === 0;
          let x = direct ? I(3) : w.state.variable(I(3)), y = direct ? I(4) : w.state.variable(I(4));
          if (I(2) === 2) { const c = this.character(I(3), w); if (c) { x = c.x; y = c.y; } }
          let val;
          switch (I(1)) {
            case 0: val = w.terrainTag(x, y); break;
            case 1: { const e = w.events.find(ev => ev.x === x && ev.y === y); val = e ? e.eventId : 0; break; }
            case 2: case 3: case 4: case 5: val = M.tileId(w.map, x, y, I(1) - 2); break;
            default: val = M.regionId(w.map, x, y);
          }
          w.state.setVariable(I(0), val);
          break;
        }
        case 301: {
          let troopId;
          switch (I(0)) { case 0: troopId = I(1); break; case 1: troopId = w.state.variable(I(1)); break; default: troopId = w.map.encounterList.length ? w.map.encounterList[0].troopId : 0; }
          if (w.project.troop(troopId)) {
            const ind = this.indent;
            w.startBattle(troopId, B(2), B(3), false, o => { this.branch[ind] = o === 3 ? 0 : o; });
            this.waitMode = { t: "battle" };
          }
          break;
        }
        case 601: if (this.branch[this.indent] !== 0) this.skipBranch(); break;
        case 602: if (this.branch[this.indent] !== 1) this.skipBranch(); break;
        case 603: if (this.branch[this.indent] !== 2) this.skipBranch(); break;
        case 302: {
          const goods = [p];
          while (this.nextCode() === 605) { this.index++; goods.push(this.list[this.index].parameters); }
          w.shop = { goods: goods.map(g => { const k = P.int(g[0]), id = P.int(g[1]); return { kind: k, id, price: P.int(g[2]) === 0 ? LK.Shop.basePrice(k, id, w.project) : P.int(g[3]) }; }), purchaseOnly: B(4) };
          this.waitMode = { t: "scene" };
          break;
        }
        case 303: if (w.project.actor(I(0))) { w.nameInput = { actorId: I(0), maxLength: Math.max(1, I(1)) }; this.waitMode = { t: "scene" }; } break;
        case 311: {
          const val = this.operand(I(2), I(3), I(4), w);
          for (const a of this.actorsOf(I(0), I(1), w)) { if (!B(5) && a.hp + val <= 0) a.setHp(Math.max(1, a.hp + val)); else a.gainHp(val); }
          if (!w.battle && w.isAllDead) w.gameOver = true;
          break;
        }
        case 312: { const val = this.operand(I(2), I(3), I(4), w); for (const a of this.actorsOf(I(0), I(1), w)) a.gainMp(val); break; }
        case 326: { const val = this.operand(I(2), I(3), I(4), w); for (const a of this.actorsOf(I(0), I(1), w)) a.gainTp(val); break; }
        case 313: for (const a of this.actorsOf(I(0), I(1), w)) { if (I(2) === 0) a.addState(I(3)); else a.removeState(I(3)); } break;
        case 314: for (const a of this.actorsOf(I(0), I(1), w)) a.recoverAll(); break;
        case 315: {
          const val = this.operand(I(2), I(3), I(4), w);
          for (const a of this.actorsOf(I(0), I(1), w)) { const r = a.changeExp(a.currentExp + val); if (B(5) && r.levels > 0) this.levelUpMessage(a, r.newSkills, w); }
          break;
        }
        case 316: {
          const val = this.operand(I(2), I(3), I(4), w);
          for (const a of this.actorsOf(I(0), I(1), w)) {
            const last = new Set(a.learnedSkills), lv = a.level;
            a.changeLevel(a.level + val);
            if (B(5) && a.level > lv) this.levelUpMessage(a, a.learnedSkills.filter(s => !last.has(s)), w);
          }
          break;
        }
        case 317: { const val = this.operand(I(3), I(4), I(5), w); for (const a of this.actorsOf(I(0), I(1), w)) { a.paramPlusExtra[I(2)] += val; a.refresh(); } break; }
        case 318: for (const a of this.actorsOf(I(0), I(1), w)) { if (I(2) === 0) a.learnSkill(I(3)); else a.forgetSkill(I(3)); } break;
        case 319: {
          const a = w.actor(I(0));
          if (a) { const slot = Math.max(0, I(1) - 1), id = I(2); if (id > 0) w.state.gain(slot === 0 ? 2 : 3, id, 1); w.equip(a, slot, id); }
          break;
        }
        case 320: { const a = w.actor(I(0)); if (a) a.setName(S(1)); break; }
        case 321: { const a = w.actor(I(0)); if (a) a.changeClass(I(1), B(2)); break; }
        case 322: case 323: case 325: break;
        case 324: { const a = w.actor(I(0)); if (a) a.nickname = S(1); break; }
        case 331: case 332: case 342: {
          const val = this.operand(I(1), I(2), I(3), w);
          for (const e of this.enemiesOf(I(0), w)) {
            if (code === 331) { if (!B(4) && e.hp + val <= 0) e.setHp(1); else e.gainHp(val); }
            else if (code === 332) e.gainMp(val); else e.gainTp(val);
          }
          break;
        }
        case 333: for (const e of this.enemiesOf(I(0), w)) { if (I(1) === 0) e.addState(I(2)); else e.removeState(I(2)); } break;
        case 334: for (const e of this.enemiesOf(I(0), w)) e.recoverAll(); break;
        case 335: for (const e of this.enemiesOf(I(0), w)) e.appear(); break;
        case 336: { const b = w.battle, e = this.enemiesOf(I(0), w)[0]; if (b && e) b.replaceEnemy(e, e.transform(I(1))); break; }
        case 337: if (w.battle) w.battle.cueAnimation(B(2) ? -1 : I(0), I(1)); break;
        case 339: if (w.battle) w.battle.forceAction(I(0) === 0, I(1), I(2), I(3)); break;
        case 340: if (w.battle) w.battle.abort(); break;
        case 351: w.requestMenu = true; this.waitMode = { t: "scene" }; break;
        case 352: w.requestSave = true; this.waitMode = { t: "scene" }; break;
        case 355: {
          let src = S(0) + "\n";
          while (this.nextCode() === 655) { this.index++; src += P.str(this.list[this.index].parameters[0]) + "\n"; }
          w.script.run(src, this);
          break;
        }
        case 356: { const parts = S(0).split(" ").filter(x => x); if (parts.length) w.script.emit("pluginCommandMV", [parts[0], parts.slice(1)]); break; }
        case 357: w.script.callPluginCommand(S(0), S(1), p[3] && typeof p[3] === "object" && !Array.isArray(p[3]) ? p[3] : {}, this); break;
        case 201: {
          if (w.message) return false;
          const direct = I(0) === 0;
          const m = direct ? I(1) : w.state.variable(I(1)), x = direct ? I(2) : w.state.variable(I(2)), y = direct ? I(3) : w.state.variable(I(3));
          w.reserveTransfer(m, x, y, I(4), I(5)); this.waitMode = { t: "transfer" };
          break;
        }
        case 203: { const c = this.character(I(0), w); if (c && I(1) === 0) { c.locate(I(2), I(3)); if (I(4) > 0) c.setDirection(I(4)); } break; }
        case 205: {
          const c = this.character(I(0), w), r = p[1];
          if (c && r && typeof r === "object") { c.forceMoveRoute(routeList(r), P.bool(r.repeat), P.bool(r.skippable)); if (r.wait === true) this.waitMode = { t: "route", c }; }
          break;
        }
        case 211: w.player.transparent = I(0) === 0; break;
        case 214: { const e = w.events.find(ev => ev.eventId === this.eventId); if (e && this.mapId === w.state.mapId) e.erase(); break; }
        case 221: if (w.message) return false; w.startFade(0, 24); this.waitMode = { t: "fade" }; break;
        case 222: if (w.message) return false; w.startFade(255, 24); this.waitMode = { t: "fade" }; break;
        case 230: this.waitCount = I(0); break;
        case 353: w.gameOver = true; break;
        case 354: w.returnToTitle = true; break;
        default: break;
      }
      return true;
    }
    setupNumberInput(p, m, w) { m.numberVariable = P.int(p[0]); m.numberDigits = LK.clamp(P.int(p[1]), 1, 8); m.number = LK.clamp(w.state.variable(m.numberVariable), 0, Math.pow(10, m.numberDigits) - 1); }
    setupItemChoice(p, m, w) {
      m.itemChoiceVariable = P.int(p[0]); m.itemChoiceType = Math.max(1, P.int(p[1]));
      m.itemChoices = LK.GameState.sortedKeys(w.state.items).filter(id => { const it = w.project.item(id); return it && it.itypeId === m.itemChoiceType; });
    }
    picturePoint(p, w) { return P.int(p[3]) === 1 ? [w.state.variable(P.int(p[4])), w.state.variable(P.int(p[5]))] : [P.int(p[4]), P.int(p[5])]; }
    actorsOf(designation, id, w) { const aid = designation === 0 ? id : w.state.variable(id); if (aid === 0) return w.allMembers; const a = w.actor(aid); return a ? [a] : []; }
    enemiesOf(index, w) { const b = w.battle; if (!b) return []; return index < 0 ? b.enemies : index < b.enemies.length ? [b.enemies[index]] : []; }
    levelUpMessage(a, skills, w) {
      const t = w.project.system.terms;
      w.addScriptMessage(LK.termMessage(t, "levelUp", a.name, t.basic[0], String(a.level)));
      for (const s of skills) { const sk = w.project.skill(s); if (sk) w.addScriptMessage(LK.termMessage(t, "obtainSkill", sk.name)); }
      this.waitMode = { t: "message" };
    }
    gameData(type, p1, p2, w) {
      switch (type) {
        case 0: return w.state.count(1, p1); case 1: return w.state.count(2, p1); case 2: return w.state.count(3, p1);
        case 3: {
          const a = w.actor(p1); if (!a) return 0;
          if (p2 === 0) return a.level; if (p2 === 1) return a.currentExp; if (p2 === 2) return a.hp; if (p2 === 3) return a.mp;
          if (p2 >= 4 && p2 <= 11) return a.param(p2 - 4); if (p2 === 12) return a.tp; return 0;
        }
        case 4: {
          const b = w.battle; if (!b || p1 >= b.enemies.length) return 0; const e = b.enemies[p1];
          if (p2 === 0) return e.hp; if (p2 === 1) return e.mp; if (p2 >= 2 && p2 <= 9) return e.param(p2 - 2); if (p2 === 10) return e.tp; return 0;
        }
        case 5: {
          const c = this.character(p1, w); if (!c) return 0;
          return [c.x, c.y, c.direction, Math.trunc(c.realX * 48 + 24), Math.trunc(c.realY * 48 + 48)][p2] || 0;
        }
        case 6: { const id = w.state.party[p1]; const a = id !== undefined ? w.actor(id) : null; return a ? a.actorId : 0; }
        case 7: {
          const s = w.state;
          return { 0: s.mapId, 1: s.party.length, 2: s.gold, 3: s.steps, 4: idiv(s.playFrames, 60), 6: s.saveCount, 7: s.battleCount, 8: s.winCount, 9: s.escapeCount }[p1] || 0;
        }
        case 8: return w.lastActionData(p1);
        default: return 0;
      }
    }
    setupChoices(p, m, w) {
      const choices = P.arr(p[0]).map(c => w.convertEscapes(P.str(c)));
      const cancelType = P.int(p[1]);
      m.choices = choices; m.choiceCancel = cancelType < choices.length ? cancelType : -2;
      m.choiceDefault = LK.clamp(P.int(p[2]), 0, choices.length - 1); m.choiceIndex = m.choiceDefault;
      const ind = this.indent; m.onChoose = n => { this.branch[ind] = n; };
    }
    conditionalBranch(p, w) {
      const I = i => P.int(p[i]), S = i => P.str(p[i]), B = i => P.bool(p[i]);
      switch (I(0)) {
        case 0: return w.state.switchValue(I(1)) === (I(2) === 0);
        case 1: {
          const a = w.state.variable(I(1)), b = I(2) === 0 ? I(3) : w.state.variable(I(3));
          switch (I(4)) { case 0: return a === b; case 1: return a >= b; case 2: return a <= b; case 3: return a > b; case 4: return a < b; default: return a !== b; }
        }
        case 2: return this.eventId > 0 && w.state.selfSwitch(this.mapId, this.eventId, S(1)) === (I(2) === 0);
        case 4: {
          const a = w.actor(I(1)); if (!a) return false;
          switch (I(2)) {
            case 0: return w.state.party.includes(a.actorId); case 1: return a.name === S(3); case 2: return a.classId === I(3);
            case 3: return a.learnedSkills.includes(I(3)); case 4: return a.equips[0] === I(3); case 5: return a.equips.slice(1).includes(I(3));
            case 6: return a.isStateAffected(I(3)); default: return false;
          }
        }
        case 5: { const b = w.battle; if (!b || I(1) >= b.enemies.length) return false; const e = b.enemies[I(1)]; return I(2) === 0 ? e.isAlive : e.isStateAffected(I(3)); }
        case 9: return w.state.count(2, I(1)) > 0 || (B(2) && w.partyMembers.some(a => a.equips[0] === I(1)));
        case 10: return w.state.count(3, I(1)) > 0 || (B(2) && w.partyMembers.some(a => a.equips.slice(1).includes(I(1))));
        case 11: {
          const name = S(1), i = w.lastInput;
          if (name === "ok") return i.ok || i.held.has("ok");
          if (name === "cancel") return i.cancel || i.held.has("cancel");
          return i.held.has(name);
        }
        case 12: return w.script.evalBool(S(1), this);
        case 13: return w.state.vehicleType === I(1);
        case 6: { const c = this.character(I(1), w); return !!c && c.direction === I(2); }
        case 7: { const g = w.state.gold, val = I(1); return I(2) === 0 ? g >= val : I(2) === 1 ? g <= val : g < val; }
        case 8: return w.state.itemCount(I(1)) > 0;
        default: return false;
      }
    }
  }
  LK.Interpreter = Interpreter;
})(typeof LK !== "undefined" ? LK : require("./core-data.js"));
