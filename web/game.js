// Lakon web runtime — the player. Port of Sources/Lakon/GameScene.swift (title, map, characters, parallax,
// pictures, weather, tint/flash/fade, message window, map animations), plus input, saves and the main loop.
"use strict";
(function (LK) {
  const W = LK.W, H = LK.H, TS = 48;
  const { C, rgba, white } = LK.Color;
  const R = LK.R;
  const M = LK.MapUtil;

  /// Image cache over img/<folder>/<name>.png; null until loaded.
  class Images {
    constructor(base) { this.base = base; this.cache = {}; }
    get(folder, name) {
      if (!name) return null;
      const k = folder + "/" + name;
      let e = this.cache[k];
      if (!e) {
        const img = new Image();
        e = this.cache[k] = { img, ok: false, failed: false };
        img.onload = () => { e.ok = true; };
        img.onerror = () => { e.failed = true; };
        img.src = this.base + "img/" + folder + "/" + encodeURIComponent(name) + ".png";
      }
      return e.ok ? e.img : null;
    }
    pending() { return Object.values(this.cache).some(e => !e.ok && !e.failed); }
    preload(list) { for (const [f, n] of list) this.get(f, n); }
  }
  LK.Images = Images;

  const characterFrame = (img, name, index, dir, pattern) => {
    const big = /^[!$]*\$/.test(name);
    const pw = big ? img.width / 3 : img.width / 12, ph = big ? img.height / 4 : img.height / 8;
    const bx = big ? 0 : (index % 4) * 3, by = big ? 0 : Math.floor(index / 4) * 4;
    const row = LK.clamp(Math.trunc((dir - 2) / 2), 0, 3);
    return [(bx + pattern) * pw, (by + row) * ph, pw, ph];
  };
  LK.characterFrame = characterFrame;

  class Game {
    constructor(canvas, game) {
      this.canvas = canvas; this.ctx = canvas.getContext("2d");
      this.gameData = game;
      this.project = new LK.Project(game.data, game.assets);
      this.images = new Images(game.base || "");
      this.audio = new LK.AudioPlayer(game.audio);
      this.world = new LK.GameWorld(this.project);
      this.ui = new LK.SceneUI(this.ctx);
      this.ui.windowTone = this.project.system.windowTone;
      this.saveKey = "lakon:" + (game.id || this.project.system.gameTitle) + ":";
      this.worldCanvas = document.createElement("canvas"); this.worldCanvas.width = W; this.worldCanvas.height = H;
      this.wctx = this.worldCanvas.getContext("2d");
      this.mode = "title"; this.titleCursor = 0; this.titleOptions = false;
      this.menuUI = null; this.shopUI = null; this.nameUI = null; this.battleUI = null;
      this.chunks = {}; this.chunkOrder = []; this.animatedChunks = new Set(); this.builtGeneration = -1;
      this.weather = []; this.mapNameTimer = 0; this.toast = null; this.scroll = { x: 0, y: 0 };
      this.mapAnims = []; this.animSerials = new Map(); this.animFlash = new Map(); this.animHidden = new Set();
      this.held = new Set(); this.dirOrder = []; this.pending = {}; this.shift = false; this.typed = "";
      this.lastTime = 0; this.acc = 0;
      this.installInput();
    }
    start() {
      this.ui.iconSheet = null;
      this.showTitle();
      // Keep running after an exception (reported once per message) so one bad frame doesn't freeze the game.
      const seen = new Set();
      const loop = t => {
        try { this.tick(t / 1000); } catch (e) { const m = String(e && e.stack || e); if (!seen.has(m)) { seen.add(m); console.error(m); } this.acc = 0; }
        requestAnimationFrame(loop);
      };
      requestAnimationFrame(loop);
    }

    // ---------- input ----------
    installInput() {
      const dirFor = { ArrowLeft: 4, ArrowRight: 6, ArrowDown: 2, ArrowUp: 8 };
      window.addEventListener("keydown", e => {
        this.audio.unlock();
        const k = e.key;
        this.shift = e.shiftKey;
        if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " ", "Tab", "Backspace"].includes(k)) e.preventDefault();
        if (k === "F4" || (k === "f" && (e.metaKey || e.ctrlKey))) { this.toggleFullscreen(); e.preventDefault(); return; }
        const lower = k.length === 1 ? k.toLowerCase() : k;
        const typing = !!this.nameUI && ["z", "x", " "].includes(lower);   // in name entry these keys type letters
        if (["z", "Enter", " "].includes(lower) && !e.repeat && !typing) this.pending.ok = true;
        if (["x", "Escape"].includes(lower) && !e.repeat && !typing) this.pending.cancel = true;
        if (k === "Backspace") { this.pending.backspace = true; if (!e.repeat && !this.nameUI) this.pending.cancel = true; }
        if (k === "ArrowUp") this.pending.up = true;
        if (k === "ArrowDown") this.pending.down = true;
        if (k === "ArrowLeft") this.pending.left = true;
        if (k === "ArrowRight") this.pending.right = true;
        if (lower === "q" || k === "PageUp") this.pending.pageUp = true;
        if (lower === "w" || k === "PageDown") this.pending.pageDown = true;
        if (this.nameUI && k.length === 1 && /[A-Za-z0-9 ]/.test(k)) this.typed += k;
        const d = dirFor[k];
        if (d && !this.held.has(k)) { this.dirOrder = this.dirOrder.filter(x => x !== d); this.dirOrder.push(d); }
        this.held.add(lower);
      });
      window.addEventListener("keyup", e => {
        const k = e.key, lower = k.length === 1 ? k.toLowerCase() : k;
        this.held.delete(lower); this.held.delete(k);
        const d = dirFor[k]; if (d) this.dirOrder = this.dirOrder.filter(x => x !== d);
        this.shift = e.shiftKey;
      });
      window.addEventListener("blur", () => { this.held.clear(); this.dirOrder = []; });
      this.canvas.addEventListener("pointerdown", () => this.audio.unlock());
      this.canvas.addEventListener("dblclick", () => this.toggleFullscreen());
    }
    toggleFullscreen() {
      const el = document.documentElement;
      if (!document.fullscreenElement) { if (el.requestFullscreen) el.requestFullscreen(); } else if (document.exitFullscreen) document.exitFullscreen();
    }
    pollGamepad(u) {
      const pads = navigator.getGamepads ? navigator.getGamepads() : [];
      const p = pads && pads[0]; if (!p) return;
      const b = i => !!(p.buttons[i] && p.buttons[i].pressed);
      const prev = this.padPrev || {}, now = { ok: b(0), cancel: b(1) || b(9), up: b(12) || p.axes[1] < -0.5, down: b(13) || p.axes[1] > 0.5, left: b(14) || p.axes[0] < -0.5, right: b(15) || p.axes[0] > 0.5, dash: b(2) };
      for (const k of ["ok", "cancel", "up", "down", "left", "right"]) if (now[k] && !prev[k]) u[k] = true;
      this.padDir = now.up ? 8 : now.down ? 2 : now.left ? 4 : now.right ? 6 : 0;
      this.padDash = now.dash; this.padPrev = now;
      if (now.ok || now.cancel) this.audio.unlock();
    }
    worldInput(u) {
      const i = LK.newInput({ dir4: this.dirOrder.length ? this.dirOrder[this.dirOrder.length - 1] : (this.padDir || 0), ok: u.ok, cancel: u.cancel, up: u.up, down: u.down, left: u.left, right: u.right, dash: this.shift || !!this.padDash });
      const h = i.held;
      if (["z", "Enter", " "].some(k => this.held.has(k))) h.add("ok");
      if (["x", "Escape"].some(k => this.held.has(k))) h.add("cancel");
      if (this.shift) h.add("shift");
      for (const [k, n] of [["ArrowUp", "up"], ["ArrowDown", "down"], ["ArrowLeft", "left"], ["ArrowRight", "right"], ["q", "pageup"], ["w", "pagedown"]]) if (this.held.has(k)) h.add(n);
      return i;
    }

    // ---------- loop ----------
    tick(t) {
      if (!this.lastTime) this.lastTime = t;
      this.acc = Math.min(this.acc + Math.max(0, t - this.lastTime), 0.25);
      this.lastTime = Math.max(this.lastTime, t);
      let stepped = false;
      while (this.acc >= 1 / 60) { this.acc -= 1 / 60; this.step(); stepped = true; }
      if (stepped) this.render();
    }
    step() {
      const u = Object.assign({ up: false, down: false, left: false, right: false, ok: false, cancel: false, pageUp: false, pageDown: false, backspace: false }, this.pending);
      u.typed = this.typed; this.typed = ""; this.pending = {};
      this.pollGamepad(u);
      const wi = this.worldInput(u);
      if (this.mode === "title") this.titleStep(u);
      else if (this.mode === "gameOver") { if (u.ok) this.showTitle(); }
      else this.mapStep(u, wi);
      this.audio.handle(this.world.audio.drain());
      this.audio.update();
      if (LK.Effects) LK.Effects.update();
      if (this.toast) { this.toast.n--; if (this.toast.n <= 0) this.toast = null; }
    }
    mapStep(u, wi) {
      const w = this.world;
      if (w.battle) {
        this.menuUI = null;
        if (!this.battleUI) this.battleUI = new LK.BattleController(this);
        const consumed = !w.message ? this.battleUI.step(u) : false;
        w.update(consumed ? LK.newInput() : wi);
        if (!w.battle) this.battleUI = null;
      } else if (w.shop) {
        if (!this.shopUI) this.shopUI = new LK.ShopController(this);
        this.shopUI.step(u);
        if (!w.shop) { this.shopUI = null; w.update(LK.newInput()); }
      } else if (w.nameInput) {
        if (!this.nameUI) this.nameUI = new LK.NameController(this);
        this.nameUI.step(u);
        if (!w.nameInput) { this.nameUI = null; w.update(LK.newInput()); }
      } else if (this.menuUI) {
        this.menuUI.step(u);
        if (this.menuUI.closed) { this.menuUI = null; w.requestMenu = false; w.requestSave = false; }
      } else if (w.requestMenu || w.requestSave) {
        this.menuUI = new LK.MenuController(this, { saveOnly: w.requestSave && !w.requestMenu });
      } else if (u.cancel && !w.message && !w.isEventRunning && !w.player.isMoving && w.state.menuEnabled && !w.transferPending) {
        w.playSystemSound(1); this.menuUI = new LK.MenuController(this, {});
      } else w.update(wi);
      if (w.gameOver) { w.gameOver = false; this.mode = "gameOver"; w.audio.stopBgm(); w.audio.playMe(this.project.system.gameoverMe); }
      if (w.returnToTitle) { w.returnToTitle = false; this.showTitle(); }
    }

    // ---------- title ----------
    get hasAnySave() { for (let i = 1; i <= Game.saveCount; i++) if (this.saveExists(i)) return true; return false; }
    showTitle() {
      this.mode = "title"; this.titleCursor = this.hasAnySave ? 1 : 0;
      this.menuUI = null; this.battleUI = null; this.shopUI = null; this.nameUI = null; this.builtGeneration = -1; this.weather = [];
      this.world.audio.fadeOutBgs(0); this.world.audio.playBgm(this.project.system.titleBgm);
    }
    titleStep(u) {
      if (this.titleOptions) { if (this.menuUI) { this.menuUI.step(u); if (this.menuUI.closed) { this.menuUI = null; this.titleOptions = false; } } return; }
      const n = 3, w = this.world;
      if (u.up) { this.titleCursor = (this.titleCursor + n - 1) % n; w.playSystemSound(0); }
      if (u.down) { this.titleCursor = (this.titleCursor + 1) % n; w.playSystemSound(0); }
      if (!u.ok) return;
      this.audio.unlock();
      if (this.titleCursor === 0) { w.playSystemSound(1); this.startNewGame(); }
      else if (this.titleCursor === 1) { if (this.hasAnySave) { w.playSystemSound(1); this.menuUI = new LK.MenuController(this, { loadOnly: true }); this.titleOptions = true; } else w.playSystemSound(3); }
      else { w.playSystemSound(1); this.menuUI = new LK.MenuController(this, { optionsOnly: true }); this.titleOptions = true; }
    }
    startNewGame() { this.world.audio.stopBgm(); this.world.newGame(); this.mode = "map"; this.menuUI = null; }

    // ---------- saves (localStorage; MZ uses localforage in browsers) ----------
    saveExists(slot) { return localStorage.getItem(this.saveKey + "file" + slot) !== null; }
    saveInfo(slot) { try { return JSON.parse(localStorage.getItem(this.saveKey + "file" + slot)).info; } catch (e) { return null; } }
    saveGame(slot) {
      try {
        const w = this.world, s = w.makeSave(), leader = w.partyMembers[0];
        const info = { title: this.project.system.gameTitle, mapName: w.map.displayName || this.project.mapName(s.mapId), playFrames: s.playFrames,
          leader: leader ? leader.name : "", level: leader ? leader.level : 1, savedAt: new Date().toISOString() };
        localStorage.setItem(this.saveKey + "file" + slot, JSON.stringify({ info, state: s }));
        w.playSystemSound(5); return true;
      } catch (e) { this.toast = { s: "Save failed: " + e.message, n: 180 }; this.world.playSystemSound(3); return false; }
    }
    loadGame(slot) {
      try {
        const o = JSON.parse(localStorage.getItem(this.saveKey + "file" + slot));
        this.world.load(LK.GameState.fromJSON(o.state)); this.mode = "map"; this.menuUI = null; this.titleOptions = false;
        this.world.playSystemSound(6); return true;
      } catch (e) { this.toast = { s: "Could not load file " + slot, n: 120 }; return false; }
    }

    // ---------- rendering ----------
    img(folder, name) { return this.images.get(folder, name); }
    render() {
      const ctx = this.ctx, ui = this.ui, w = this.world;
      if (!ui.iconSheet) ui.iconSheet = this.img("system", "IconSet");
      ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = "#000"; ctx.fillRect(0, 0, W, H);
      ui.begin();
      if (this.mode === "title") { this.drawTitle(); if (this.titleOptions && this.menuUI) this.menuUI.render(); }
      else if (this.mode === "gameOver") {
        ctx.globalAlpha = 0.25; ctx.drawImage(this.worldCanvas, 0, 0); ctx.globalAlpha = 1;
        ui.label("go", "GAME OVER", { x: W / 2, y: H / 2 }, { size: 64, align: "center", bold: true });
        ui.label("go2", "Press Z / Enter", { x: W / 2, y: H / 2 - 60 }, { size: 18, align: "center", alpha: 0.7 });
      } else {
        if (this.battleUI && w.battle) { this.battleUI.render(); this.renderPictures(); }
        else {
          this.renderMap();
          ctx.drawImage(this.worldCanvas, 0, 0);
          this.renderWeather();
          this.renderPictures();
          this.renderScreenEffects();
          if (this.mapNameTimer > 0 && w.map.displayName) this.drawMapName(w.map.displayName);
          if (w.mapDamageFlash > 0) ui.rect("dmg", R(0, 0, W, H), C(1, 0, 0, w.mapDamageFlash / 24), -1);
        }
        if (w.message) this.drawMessage(w.message);
        if (this.shopUI) this.shopUI.render();
        if (this.nameUI) this.nameUI.render();
        if (this.menuUI) this.menuUI.render();
      }
      if (this.toast) { ui.window("toast", R(W - 316, H - 64, 300, 48), 30); ui.label("toast.t", this.toast.s, { x: W - 166, y: H - 46 }, { size: 20, align: "center", z: 31, maxWidth: 280 }); }
      ui.end();
    }
    drawTitle() {
      const ui = this.ui, p = this.project;
      ui.rect("title.bg", R(0, 0, W, H), C(0.08, 0.1, 0.2), -10);
      const t = this.img("titles1", p.system.title1Name);
      if (t) ui.sprite("title.img", t, { x: W / 2, y: H / 2 }, { size: { w: W, h: H }, z: -9 });
      for (let i = 0; i < 40; i++) {
        const tw = 0.3 + 0.3 * Math.sin((ui.frame + i * 13) / 30);
        ui.rect("s" + i, R((i * 197) % 816, 260 + (i * 83) % 360, 1 + i % 3, 1 + i % 3), C(1, 1, 1, tw), -8);
      }
      ui.label("title.t", p.system.gameTitle, { x: W / 2, y: 420 }, { size: 56, align: "center", bold: true, maxWidth: 760 });
      const options = ["New Game", "Continue", "Options"];
      ui.window("title.w", R(W / 2 - 120, 120, 240, 140));
      options.forEach((o, i) => {
        const y = 226 - i * 40;
        if (i === this.titleCursor && !this.titleOptions) ui.cursor("title.c", R(W / 2 - 108, y - 12, 216, 34));
        ui.label("title.o" + i, o, { x: W / 2, y: y - 4 }, { size: 22, align: "center", alpha: i === 1 && !this.hasAnySave ? 0.4 : 1 });
      });
      ui.label("title.h", "Arrows move · Z / Enter confirm · X / Esc menu · Shift dash · F4 fullscreen", { x: W / 2, y: 40 }, { size: 14, align: "center", alpha: 0.55 });
    }
    drawMapName(name) {
      const a = Math.min(1, this.mapNameTimer / 30);
      this.ui.rect("mapname.bg", R(0, H - 80, 360, 48), C(0, 0, 0, 0.55 * a), 5);
      this.ui.label("mapname", name, { x: 24, y: H - 66 }, { size: 24, z: 6, alpha: a });
    }

    // ---------- map ----------
    resetMap() {
      const w = this.world;
      this.builtGeneration = w.mapGeneration; this.chunks = {}; this.chunkOrder = []; this.animatedChunks = new Set();
      this.mapAnims = []; this.animSerials = new Map();
      const c = Game.chunk;
      for (let cy = 0; cy < w.map.height; cy += c) for (let cx = 0; cx < w.map.width; cx += c) {
        let anim = false;
        for (let y = cy; y < Math.min(w.map.height, cy + c) && !anim; y++) for (let x = cx; x < Math.min(w.map.width, cx + c) && !anim; x++)
          for (let z = 0; z < 4; z++) if (LK.TileID.isA1(M.tileId(w.map, x, y, z))) { anim = true; break; }
        if (anim) this.animatedChunks.add(cx + "," + cy);
      }
      this.mapNameTimer = 150;
    }
    tilesetImages() { return this.world.tileset.tilesetNames.map(n => (n ? this.img("tilesets", n) : null)); }
    tilesetReady() { return this.world.tileset.tilesetNames.every(n => !n || this.img("tilesets", n) || (this.images.cache["tilesets/" + n] || {}).failed); }
    drawTile(ctx, id, dx, dy, frame, sheets) {
      if (id <= 0 || id >= LK.TileID.max) return;
      for (const [set, sx, sy, w, h, ox, oy] of LK.TileID.rects(id, frame)) {
        const s = sheets[set];
        if (s && sx + w <= s.width && sy + h <= s.height) ctx.drawImage(s, sx, sy, w, h, dx + ox, dy + oy, w, h);
      }
    }
    chunkCanvas(cx, cy, upper, frame) {
      const key = cx + "," + cy + (upper ? "U" : "L") + ":" + frame;
      if (this.chunks[key]) return this.chunks[key];
      if (!this.tilesetReady()) return null;
      const w = this.world, c = Game.chunk, cv = document.createElement("canvas");
      cv.width = c * TS; cv.height = c * TS;
      const g = cv.getContext("2d"), sheets = this.tilesetImages();
      for (let y = cy; y < Math.min(w.map.height, cy + c); y++) for (let x = cx; x < Math.min(w.map.width, cx + c); x++) for (let z = 0; z < 4; z++) {
        const id = M.tileId(w.map, x, y, z); if (id <= 0) continue;
        const star = (M.flag(w.tileset, id) & 0x10) !== 0;
        if (star === upper) this.drawTile(g, id, (x - cx) * TS, (y - cy) * TS, frame, sheets);
      }
      this.chunks[key] = cv; this.chunkOrder.push(key);
      if (this.chunkOrder.length > 200) delete this.chunks[this.chunkOrder.shift()];
      return cv;
    }
    renderMap() {
      const w = this.world, g = this.wctx;
      if (this.builtGeneration !== w.mapGeneration) this.resetMap();
      if (this.mapNameTimer > 0) this.mapNameTimer--;
      const m = w.map, mapW = m.width * TS, mapH = m.height * TS;
      let sx = w.player.realX * TS + TS / 2 - W / 2, sy = w.player.realY * TS + TS / 2 - H / 2;
      sx = mapW <= W ? (mapW - W) / 2 : LK.clamp(sx, 0, mapW - W);
      sy = mapH <= H ? (mapH - H) / 2 : LK.clamp(sy, 0, mapH - H);
      this.scroll = { x: Math.round(sx), y: Math.round(sy) };
      const shake = w.screen.shake, ox = -this.scroll.x + shake, oy = -this.scroll.y;
      g.setTransform(1, 0, 0, 1, 0, 0); g.globalAlpha = 1; g.globalCompositeOperation = "source-over";
      g.fillStyle = "#000"; g.fillRect(0, 0, W, H);
      this.renderParallax(g);
      // Draw list in MZ screen-z order: lower tiles 0, characters priority*2+1 (+y/1000), upper (☆) tiles 4, animations 9.
      const draws = [];
      const c = Game.chunk, frameKey = w.animationFrame % 12;
      const x0 = Math.max(0, (Math.floor(this.scroll.x / TS / c) - 1) * c), y0 = Math.max(0, (Math.floor(this.scroll.y / TS / c) - 1) * c);
      const x1 = Math.min(m.width, Math.floor((this.scroll.x + W) / TS) + c), y1 = Math.min(m.height, Math.floor((this.scroll.y + H) / TS) + c);
      for (let cy = y0; cy < y1; cy += c) for (let cx = x0; cx < x1; cx += c) for (const upper of [false, true]) {
        const fk = this.animatedChunks.has(cx + "," + cy) ? frameKey : 0;
        const cv = this.chunkCanvas(cx, cy, upper, fk);
        if (cv) draws.push({ z: upper ? 4 : 0, f: () => g.drawImage(cv, cx * TS + ox, cy * TS + oy) });
      }
      this.updateMapAnimations();
      this.characterDraws(draws, ox, oy);
      draws.push({ z: 9, f: () => this.drawMapAnimations(g, ox, oy) });
      draws.map((d, i) => [d, i]).sort((a, b) => a[0].z - b[0].z || a[1] - b[1]).forEach(([d]) => { g.save(); d.f(); g.restore(); });
      this.applyTone(g);
    }
    renderParallax(g) {
      const par = this.world.state.parallax;
      const img = par.name ? this.img("parallaxes", par.name) : null;
      if (!img) return;
      const [ox, oy] = par.origin(this.scroll.x / TS, this.scroll.y / TS);
      const w = img.width, h = img.height; if (!w || !h) return;
      let fx = ox % w, fy = oy % h; if (fx < 0) fx += w; if (fy < 0) fy += h;
      const shake = this.world.screen.shake;
      for (let y = -fy; y < H; y += h) for (let x = -fx + shake; x < W + w; x += w) g.drawImage(img, Math.round(x), Math.round(y));
    }
    characterDraws(draws, ox, oy) {
      const w = this.world;
      let chars = [w.player].concat(w.events, w.visibleVehicles);
      if (w.followersVisible && !w.vehicle) chars = chars.concat(w.followers);
      this.charPos = new Map();
      for (const c of chars) {
        if (c instanceof LK.GameEvent && (c.pageIndex < 0 || c.erased)) continue;
        if (c instanceof LK.GameFollower && c.x === w.player.x && c.y === w.player.y && !c.isMoving) continue;
        if (c.transparent) continue;
        let src = null, img = null;
        if (c.tileId > 0) { const s = LK.TileID.rects(c.tileId, 0)[0]; img = s ? this.tilesetImages()[s[0]] : null; src = s ? [s[1], s[2], 48, 48] : null; if (LK.TileID.isAutotile(c.tileId)) img = null; }
        else if (c.characterName) { img = this.img("characters", c.characterName); if (img) src = characterFrame(img, c.characterName, c.characterIndex, c.direction, c.patternIndex); }
        if (!img && !c.balloonId) continue;
        const alt = c instanceof LK.GameVehicle ? c.altitude : 0;
        const shift = c.tileId > 0 || c.isObjectCharacter ? 0 : 6;
        const fx = Math.round(c.realX * TS + TS / 2) + ox, fy = Math.round(c.realY * TS + TS - shift) + oy - alt;
        const z = c.priorityType * 2 + 1 + c.realY / 1000 + (alt > 0 ? 5 : 0);
        const bush = !(c instanceof LK.GameVehicle) && c.tileId === 0 && w.isBush(c.x, c.y) && !c.isMoving;
        const flash = this.animFlash.get(c.uid), hidden = this.animHidden.has(c.uid);
        const hgt = src ? src[3] : 48;
        this.charPos.set(c.uid, { x: fx, y: fy, h: hgt });
        draws.push({ z, f: () => {
          const g = this.wctx;
          if (alt > 0) { g.fillStyle = "rgba(0,0,0,0.3)"; g.beginPath(); g.ellipse(fx, fy + alt - 4, 14, 5, 0, 0, Math.PI * 2); g.fill(); }
          if (img && src && !hidden) {
            const [sx, sy, sw, sh] = src;
            if (bush) {
              g.drawImage(img, sx, sy, sw, sh - 12, fx - sw / 2, fy - sh, sw, sh - 12);
              g.globalAlpha = 0.5; g.drawImage(img, sx, sy + sh - 12, sw, 12, fx - sw / 2, fy - 12, sw, 12); g.globalAlpha = 1;
            } else g.drawImage(img, sx, sy, sw, sh, fx - sw / 2, fy - sh, sw, sh);
            if (flash && flash[3] > 0.5) LK.SceneUI.drawFlash(g, img, src, fx - sw / 2, fy - sh, sw, sh, flash);
          }
          if (c.balloonId > 0) this.drawBalloon(g, c, fx, fy - hgt - 18);
        } });
      }
    }
    drawBalloon(g, c, x, y) {
      const glyphs = ["", "!", "?", "♪", "♥", "💢", "💧", "～", "…", "💡", "Zz"];
      const colors = ["#000", "#e33", "#36f", "#93c", "#e5a", "#e33", "#36f", "#555", "#555", "#f90", "#539"];
      const pop = c.balloonFrames > 56 ? (64 - c.balloonFrames) / 8 : 1, s = Math.max(0.2, pop);
      g.save(); g.translate(x, y); g.scale(s, s);
      g.fillStyle = "#fff"; g.strokeStyle = "#333"; g.lineWidth = 2;
      g.beginPath(); if (g.roundRect) g.roundRect(-17, -15, 34, 30, 9); else g.rect(-17, -15, 34, 30); g.fill(); g.stroke();
      g.fillStyle = colors[c.balloonId] || "#000"; g.font = "800 20px " + '"Avenir Next", Arial, sans-serif'; g.textAlign = "center"; g.textBaseline = "middle";
      g.fillText(glyphs[c.balloonId] || "!", 0, 1);
      g.restore();
    }
    updateMapAnimations() {
      const w = this.world;
      const chars = [w.player].concat(w.events, w.followers, w.visibleVehicles).filter(c => c.animationId > 0);
      for (const c of chars) {
        if (this.animSerials.get(c.uid) !== c.animationSerial) {
          const a = this.project.animation(c.animationId);
          if (a) {
            this.animSerials.set(c.uid, c.animationSerial);
            const pb = new LK.AnimationPlayback(a, [0], false, LK.Anim.baseDelay);
            if (LK.Effects) LK.Effects.attach(pb);
            this.mapAnims.push({ pb, target: c.uid });
          }
        }
      }
      this.animFlash = new Map(); this.animHidden = new Set();
      for (const m of this.mapAnims) {
        const sounds = m.pb.update();
        if (sounds.length) this.audio.handle(sounds.map(f => ({ t: "playSe", f })));
        if (m.pb.flashColor[3] > 0) this.animFlash.set(m.target, m.pb.flashColor);
        if (m.pb.hidingTargets) this.animHidden.add(m.target);
      }
      this.mapAnims = this.mapAnims.filter(m => m.pb.isPlaying);
    }
    drawMapAnimations(g, ox, oy) {
      for (const m of this.mapAnims) {
        const pb = m.pb, d = pb.animation; if (!pb.started) continue;
        const t = this.charPos && this.charPos.get(m.target); if (!t) continue;
        let x = t.x, y = t.y;
        if (d.isScreen) { x = W / 2; y = H / 2; }
        else if (d.isMV) y -= d.position === 0 ? t.h : d.position === 1 ? t.h / 2 : 0;
        else { y -= d.alignBottom ? 0 : t.h / 2; x += d.offsetX; y += d.offsetY; }
        LK.drawAnimation(this, g, pb, x, y);
        const f = pb.screenFlashColor;
        if (f[3] > 0.5) this.ui.rect("map.anflash", R(0, 0, W, H), C(f[0] / 255, f[1] / 255, f[2] / 255, f[3] / 255), -40);
      }
    }
    /// MZ's ColorFilter tone on the map layer: gray desaturates, positive RGB adds, negative subtracts.
    applyTone(g) {
      const t = this.world.screen.tone;
      if (!t.some(x => Math.abs(x) > 0.5)) return;
      g.save(); g.setTransform(1, 0, 0, 1, 0, 0);
      if (t[3] > 0.5) { g.globalCompositeOperation = "saturation"; g.fillStyle = `rgba(128,128,128,${t[3] / 255})`; g.fillRect(0, 0, W, H); }
      const pos = t.slice(0, 3).map(x => Math.max(0, Math.round(x))), neg = t.slice(0, 3).map(x => Math.max(0, Math.round(-x)));
      if (pos.some(x => x > 0)) { g.globalCompositeOperation = "lighter"; g.fillStyle = `rgb(${pos.join(",")})`; g.fillRect(0, 0, W, H); }
      if (neg.some(x => x > 0)) {
        g.globalCompositeOperation = "difference"; g.fillStyle = "#fff"; g.fillRect(0, 0, W, H);
        g.globalCompositeOperation = "lighter"; g.fillStyle = `rgb(${neg.join(",")})`; g.fillRect(0, 0, W, H);
        g.globalCompositeOperation = "difference"; g.fillStyle = "#fff"; g.fillRect(0, 0, W, H);
      }
      g.restore();
    }
    renderPictures() {
      const pics = this.world.screen.pictures;
      for (const id of Object.keys(pics).map(Number).sort((a, b) => a - b)) {
        const p = pics[id], img = this.img("pictures", p.name); if (!img) continue;
        this.ui.push(-50 + id / 1000, ctx => {
          ctx.globalAlpha = LK.clamp(p.opacity / 255, 0, 1);
          ctx.globalCompositeOperation = LK.SceneUI.blendOp(p.blendMode);
          ctx.translate(p.x, p.y); ctx.rotate(p.angle * Math.PI / 180); ctx.scale(p.scaleX / 100, p.scaleY / 100);
          const dx = p.origin === 1 ? -img.width / 2 : 0, dy = p.origin === 1 ? -img.height / 2 : 0;
          if (p.tone.some(x => x !== 0)) {
            ctx.drawImage(img, dx, dy);
            const col = p.tone.slice(0, 3).map(x => LK.clamp(128 + x, 0, 255));
            LK.SceneUI.drawFlash(ctx, img, [0, 0, img.width, img.height], dx, dy, img.width, img.height, col.concat([128]));
          } else ctx.drawImage(img, dx, dy);
        });
      }
    }
    renderWeather() {
      const scr = this.world.screen, type = scr.weatherType;
      const count = type === "none" ? 0 : Math.trunc(scr.weatherPower * (type === "storm" ? 20 : 10));
      while (this.weather.length < count) this.weather.push({ x: Math.random() * W, y: Math.random() * H });
      if (this.weather.length > count) this.weather.length = count;
      const g = this.ctx;
      this.ui.push(-60, () => {
        if (type !== "none") { g.fillStyle = `rgba(0,0,0,${scr.weatherPower * (type === "storm" ? 0.04 : 0.02)})`; g.fillRect(0, 0, W, H); }
        g.fillStyle = "rgba(255,255,255,0.85)"; g.strokeStyle = "rgba(255,255,255,0.55)";
        this.weather.forEach((s, i) => {
          if (type === "snow") { s.x += -1 + Math.sin((this.ui.frame + i * 7) / 20) * 0.8; s.y += 1.6; g.fillRect(s.x - 2.5, s.y - 2.5, 5, 5); }
          else if (type === "storm") { s.x -= 9; s.y += 18; g.lineWidth = 2; g.beginPath(); g.moveTo(s.x, s.y); g.lineTo(s.x + 17, s.y - 36); g.stroke(); }
          else { s.x -= 4; s.y += 14; g.lineWidth = 1.5; g.beginPath(); g.moveTo(s.x, s.y); g.lineTo(s.x + 6.5, s.y - 29); g.stroke(); }
          if (s.y > H + 40) s.y -= H + 80; if (s.x < -40) s.x += W + 80; if (s.x > W + 40) s.x -= W + 80;
        });
      });
    }
    renderScreenEffects() {
      const w = this.world, f = w.screen.flashColor;
      if (f[3] > 0.5) this.ui.push(-40, g => { g.globalCompositeOperation = "lighter"; g.fillStyle = `rgba(${f[0]},${f[1]},${f[2]},${f[3] / 255})`; g.fillRect(0, 0, W, H); });
      const fade = 1 - w.brightness / 255;
      if (fade > 0.002) this.ui.push(-10, g => { g.fillStyle = `rgba(0,0,0,${fade})`; g.fillRect(0, 0, W, H); });
    }
    faceImage(name) { return this.img("faces", name); }
    drawFace(key, name, index, center, size, z, alpha) {
      const img = this.faceImage(name); if (!img) return false;
      const fw = img.width / 4, fh = img.height / 2;
      this.ui.sprite(key, img, center, { src: [(index % 4) * fw, Math.floor(index / 4) * fh, fw, fh], size: { w: size, h: size }, z, alpha });
      return true;
    }
    drawCharacter(key, name, index, center, size, z, alpha) {
      const img = this.img("characters", name); if (!img) return false;
      this.ui.sprite(key, img, center, { src: characterFrame(img, name, index, 2, 1), size: { w: size, h: size }, z, alpha, smooth: false });
      return true;
    }
    drawMessage(m) {
      const ui = this.ui, p = this.project;
      if (m.scrolling) {
        ui.rect("scroll.bg", R(0, 0, W, H), C(0, 0, 0, 0.6), 9);
        m.lines.forEach((line, i) => { const y = m.scrollOffset - i * 36; if (y > -40 && y < H + 40) ui.richText("scroll." + i, line, { x: 60, y }, 26, 10); });
        return;
      }
      const h = 180, y = m.positionType === 0 ? H - h - 8 : m.positionType === 1 ? (H - h) / 2 : 8;
      const rect = R(8, y, W - 16, h);
      const hasText = m.lines.length > 0 || !!m.speakerName;
      if (hasText) {
        if (m.background === 0) ui.window("msg.w", rect, 10); else if (m.background === 1) ui.rect("msg.dim", rect, C(0, 0, 0, 0.6), 10);
        let textX = rect.x + 22;
        if (m.faceName && this.drawFace("msg.face", m.faceName, m.faceIndex, { x: rect.x + 18 + 72, y: rect.midY }, 144, 11)) textX += 160;
        if (m.speakerName) {
          const nr = R(rect.x, rect.maxY + 4, [...m.speakerName].length * 13 + 44, 44);
          ui.window("msg.nw", nr, 10);
          ui.label("msg.name", m.speakerName, { x: nr.x + 20, y: nr.y + 13 }, { size: 22, bold: true, z: 11 });
        }
        LK.SceneUI.visiblePrefix(m.text, m.visibleChars).split("\n").slice(0, 4).forEach((line, i) => ui.richText("msg.l" + i, line, { x: textX, y: rect.maxY - 46 - i * 36 }, 24, 11));
        if (m.isTextComplete && !m.choices.length && m.numberDigits === 0 && m.itemChoiceVariable === 0 && Math.floor(ui.frame / 20) % 2 === 0)
          ui.label("msg.pause", "▼", { x: rect.midX, y: rect.y + 6 }, { size: 18, align: "center", z: 11 });
      }
      if (!m.isTextComplete) return;
      if (m.choices.length) {
        const w = Math.max(180, Math.max(...m.choices.map(c => [...c].length)) * 13 + 64), ch = m.choices.length * 40 + 24;
        const cy = hasText ? (m.positionType === 2 ? rect.maxY + 4 : rect.y - ch - 4) : 8;
        const cr = R(W - 8 - w, cy, w, ch);
        ui.window("choice.w", cr, 12);
        m.choices.forEach((c, i) => {
          const yy = cr.maxY - 32 - i * 40;
          if (i === m.choiceIndex) ui.cursor("choice.c", R(cr.x + 8, yy - 10, w - 16, 34), 13);
          ui.richText("choice." + i, c, { x: cr.x + 22, y: yy - 2 }, 22, 14);
        });
      }
      if (m.numberDigits > 0) {
        const w = m.numberDigits * 34 + 40, nr = R((W - w) / 2, hasText ? rect.maxY + 6 : 220, w, 64);
        ui.window("num.w", nr, 12);
        const s = String(m.number).padStart(m.numberDigits, "0");
        [...s].forEach((ch, i) => {
          const x = nr.x + 20 + i * 34;
          if (i === m.numberCursor) ui.cursor("num.c", R(x - 2, nr.y + 12, 32, 40), 13);
          ui.label("num." + i, ch, { x: x + 14, y: nr.y + 22 }, { size: 28, align: "center", z: 14 });
        });
      }
      if (m.itemChoiceVariable > 0) {
        const names = m.itemChoices.map(id => { const it = p.item(id); return it ? it.name : "?"; }).concat(["(none)"]);
        const ir = R(8, hasText ? rect.maxY + 4 : 8, W - 16, Math.min(6, names.length) * 38 + 24);
        ui.window("isel.w", ir, 12);
        names.slice(0, 6).forEach((n, i) => {
          const yy = ir.maxY - 32 - i * 38;
          if (i === m.itemChoiceIndex) ui.cursor("isel.c", R(ir.x + 8, yy - 10, ir.w - 16, 34), 13);
          if (i < m.itemChoices.length) {
            const it = p.item(m.itemChoices[i]);
            ui.icon("isel.i" + i, it ? it.iconIndex : 0, { x: ir.x + 18, y: yy - 6 }, 28, 14);
            ui.label("isel.n" + i, n + "  ×" + this.world.state.count(1, m.itemChoices[i]), { x: ir.x + 54, y: yy }, { size: 22, z: 14 });
          } else ui.label("isel.n" + i, n, { x: ir.x + 54, y: yy }, { size: 22, z: 14, alpha: 0.7 });
        });
      }
    }
  }
  Game.chunk = 8;
  Game.saveCount = 4;
  LK.Game = Game;

  /// Draws one AnimationPlayback's cells (or its Effekseer stand-in / real effect) with origin (x, y) in canvas pixels.
  LK.drawAnimation = (game, g, pb, x, y) => {
    const d = pb.animation;
    for (const c of pb.cells) {
      const name = c.sheet === 1 ? d.animation1Name : d.animation2Name;
      const img = game.img("animations", name); if (!img) continue;
      g.save();
      g.globalAlpha = LK.clamp(c.opacity / 255, 0, 1);
      g.globalCompositeOperation = LK.SceneUI.blendOp(c.blend);
      g.translate(x + c.x, y + c.y); g.rotate(c.rotation); g.scale(c.scaleX, c.scaleY);
      g.drawImage(img, (c.pattern % 5) * 192, Math.floor(c.pattern / 5) * 192, 192, 192, -96, -96, 192, 192);
      g.restore();
    }
    if (LK.Effects && LK.Effects.canDraw(pb)) { LK.Effects.draw(g, pb, x, y); return; }
    const t = pb.standInProgress;
    if (t !== null) {
      const col = LK.standInColor(d), s = d.scale / 100;
      g.save(); g.globalCompositeOperation = "lighter";
      const r = 110 * s, grad = g.createRadialGradient(x, y, 0, x, y, r);
      grad.addColorStop(0, `rgba(${col.join(",")},${0.9 * Math.sin(t * Math.PI)})`); grad.addColorStop(1, `rgba(${col.join(",")},0)`);
      g.fillStyle = grad; g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
      g.strokeStyle = `rgba(${col.join(",")},${1 - t})`; g.lineWidth = 5; g.beginPath(); g.arc(x, y, (20 + 80 * t) * s, 0, Math.PI * 2); g.stroke();
      g.restore();
    }
  };
  LK.standInColor = d => {
    const f = d.flashTimings[0];
    if (f && f.color.length >= 3 && f.color[0] + f.color[1] + f.color[2] > 0) return f.color.slice(0, 3);
    let h = 7; for (const ch of d.effectName) h = (h * 31 + ch.codePointAt(0)) >>> 0;
    return [140 + h % 116, 140 + Math.floor(h / 7) % 116, 140 + Math.floor(h / 49) % 116];
  };
})(LK);
