// Lakon web runtime — Scene_Battle: party/actor commands, target selection, enemies and side-view actors,
// animations, damage popups, log and status. Port of BattleController in Sources/Lakon/BattleUI.swift.
"use strict";
(function (LK) {
  const W = LK.W, H = LK.H, R = LK.R, UI = LK.SceneUI;
  const { C, white } = LK.Color;
  const TC = UI.textColors;

  class BattleController {
    constructor(scene) {
      this.scene = scene; this.sub = { t: "party" }; this.cursors = {}; this.lastCue = 0; this.popups = []; this.actorFlash = {}; this.shake = 0;
      this.svActors = [0, 1, 2, 3].map(i => new LK.SVActorSprite(i)); this.enemyFx = {}; this.animations = []; this.selectionCount = 0; this.lastInputActor = null;
    }
    get world() { return this.scene.world; }
    get battle() { return this.world.battle; }
    get ui() { return this.scene.ui; }
    get project() { return this.scene.project; }
    get terms() { return this.project.system.terms; }
    get sideView() { return this.project.system.optSideView; }
    cur(k) { return this.cursors[k] || 0; }
    move(k, n, u, columns = 1) { const c = UI.move(this.cur(k), n, u, columns); if (c !== this.cur(k)) this.world.playSystemSound(0); this.cursors[k] = Math.min(c, Math.max(0, n - 1)); }
    actorCommands(a) {
      const out = [[this.terms.commands[2], { t: "enemyTarget", kind: { t: "attack" } }]];
      for (const t of a.addedSkillTypes) out.push([this.project.system.skillTypes[t] || "Skill", { t: "skills", stype: t }]);
      out.push([this.terms.commands[3], null]);
      out.push([this.terms.commands[4], { t: "items" }]);
      return out;
    }

    step(u) {
      const b = this.battle, w = this.world;
      if (!b || b.phase !== "input" || b.isBusy) return false;
      if (b.waitingForPartyCommand) {
        if (this.sub.t !== "party") this.sub = { t: "party" };
        this.move("party", 2, u);
        if (u.ok) {
          if (this.cur("party") === 0) { w.playSystemSound(1); b.commandFight(); this.sub = { t: "actor" }; this.cursors.actor = 0; }
          else if (b.canEscape) { w.playSystemSound(1); b.commandEscape(); } else w.playSystemSound(3);
        }
        return true;
      }
      const a = b.inputActor; if (!a) return true;
      if (this.lastInputActor !== b.inputIndex) { this.lastInputActor = b.inputIndex; this.sub = { t: "actor" }; this.cursors.actor = 0; }
      switch (this.sub.t) {
        case "party": this.sub = { t: "actor" }; break;
        case "actor": {
          const cmds = this.actorCommands(a);
          this.move("actor", cmds.length, u);
          if (u.cancel) { w.playSystemSound(2); b.cancelInput(); this.lastInputActor = b.inputIndex; if (b.waitingForPartyCommand) this.sub = { t: "party" }; }
          if (u.ok) {
            w.playSystemSound(1);
            const next = cmds[this.cur("actor")][1];
            if (next) { if (next.t === "enemyTarget") this.cursors.enemy = this.firstAliveEnemy(); this.sub = next; this.cursors.list = 0; }
            else { b.commandGuard(); this.sub = { t: "actor" }; }
          }
          break;
        }
        case "skills": {
          const skills = b.usableSkills(a).filter(s => s.stypeId === this.sub.stype);
          this.move("list", skills.length, u, 2);
          if (u.cancel) { w.playSystemSound(2); this.sub = { t: "actor" }; }
          const s = skills[this.cur("list")];
          if (u.ok && s) { if (!a.canUse(s, true)) { w.playSystemSound(3); return true; } w.playSystemSound(1); this.choose({ t: "skill", id: s.id }, s, b); }
          break;
        }
        case "items": {
          const items = b.usableItems();
          this.move("list", items.length, u, 2);
          if (u.cancel) { w.playSystemSound(2); this.sub = { t: "actor" }; }
          const it = items[this.cur("list")];
          if (u.ok && it) { w.playSystemSound(1); this.choose({ t: "item", id: it.id }, it, b); }
          break;
        }
        case "enemyTarget": {
          const alive = b.enemies.map((e, i) => (e.isAlive ? i : -1)).filter(i => i >= 0);
          if (u.right || u.down) { this.cursors.enemy = alive.find(i => i > this.cur("enemy")) ?? (alive[0] || 0); w.playSystemSound(0); }
          if (u.left || u.up) { const l = alive.filter(i => i < this.cur("enemy")); this.cursors.enemy = l.length ? l[l.length - 1] : (alive[alive.length - 1] || 0); w.playSystemSound(0); }
          if (u.cancel) { w.playSystemSound(2); this.sub = this.back(this.sub.kind); }
          if (u.ok) { w.playSystemSound(1); this.submit(this.sub.kind, this.cur("enemy"), b); }
          break;
        }
        case "actorTarget":
          this.move("ally", b.members.length, u);
          if (u.cancel) { w.playSystemSound(2); this.sub = this.back(this.sub.kind); }
          if (u.ok) { w.playSystemSound(1); this.submit(this.sub.kind, this.cur("ally"), b); }
          break;
      }
      return true;
    }
    back(k) { if (k.t === "attack") return { t: "actor" }; if (k.t === "skill") { const s = this.project.skill(k.id); return { t: "skills", stype: s ? s.stypeId : 1 }; } return { t: "items" }; }
    choose(k, item, b) {
      if (LK.usable.needsTargetSelection(item)) {
        if (LK.usable.isForOpponent(item)) { this.cursors.enemy = this.firstAliveEnemy(); this.sub = { t: "enemyTarget", kind: k }; }
        else { this.cursors.ally = 0; this.sub = { t: "actorTarget", kind: k }; }
      } else this.submit(k, -1, b);
    }
    submit(k, target, b) {
      if (k.t === "attack") b.commandAttack(target); else if (k.t === "skill") b.commandSkill(k.id, target); else b.commandItem(k.id, target);
      this.sub = { t: "actor" }; this.cursors.actor = 0; this.lastInputActor = b.inputIndex;
    }
    firstAliveEnemy() { const b = this.battle; const i = b ? b.enemies.findIndex(e => e.isAlive) : -1; return i < 0 ? 0 : i; }

    // ---------- render ----------
    enemyImage(e) { return (this.sideView ? this.scene.img("sv_enemies", e.battlerName) : null) || this.scene.img("enemies", e.battlerName); }
    /// Feet position (y-up UI coordinates) and height of a cue target.
    targetFrame(t, b) {
      if (t >= 0) { const e = b.enemies.find(x => x.index === t); if (!e) return null; const img = this.enemyImage(e); return { x: e.screenX, y: H - e.screenY, h: img ? img.height : 100 }; }
      const ai = -t - 1;
      if (this.sideView && ai < this.svActors.length) return { x: this.svActors[ai].x, y: H - this.svActors[ai].y, h: 64 };
      return { x: 300, y: 142 - ai * 40 + 4, h: 40 };
    }
    render() {
      const b = this.battle; if (!b) return;
      const ui = this.ui, scene = this.scene;
      this.consumeCues(b);
      const sx = this.shake > 0 ? Math.floor(Math.random() * 13) - 6 : 0; if (this.shake > 0) this.shake--;
      const bb1 = scene.img("battlebacks1", b.battleback1), bb2 = scene.img("battlebacks2", b.battleback2);
      if (!bb1 && !bb2) ui.rect("b.bg", R(0, 0, W, H), C(0.18, 0.22, 0.3), -20);
      if (bb1) ui.sprite("b.bb1", bb1, { x: W / 2 + sx, y: H / 2 }, { size: { w: 1000, h: 740 }, z: -19 });
      if (bb2) ui.sprite("b.bb2", bb2, { x: W / 2 + sx, y: H / 2 }, { size: { w: 1000, h: 740 }, z: -18 });
      const targetFlash = {}, hidden = new Set();
      for (const a of this.animations) {
        const s = a.update(); if (s.length) scene.audio.handle(s.map(f => ({ t: "playSe", f })));
        for (const t of a.targets) { if (a.flashColor[3] > 0) targetFlash[t] = a.flashColor; if (a.hidingTargets) hidden.add(t); }
      }
      this.animations = this.animations.filter(a => a.isPlaying);
      this.selectionCount++;
      const targeting = this.sub.t === "enemyTarget" && b.phase === "input" && !b.isBusy ? this.cur("enemy") : null;
      for (const e of b.enemies) {
        const i = e.index, img = this.enemyImage(e);
        if (!img) { if (e.isAlive) ui.label("b.en" + i, e.name, { x: e.screenX + sx, y: H - e.screenY + 40 }, { size: 24, align: "center", z: 2 }); continue; }
        let fx = this.enemyFx[i];
        if (!fx) fx = this.enemyFx[i] = new LK.EnemySpriteEffect(e.isAlive, img.height);
        if (e.isDead && fx.appeared && !fx.isEffecting) fx.start(["collapse", "bossCollapse", "instantCollapse"][e.collapseType] || "collapse");
        fx.update(e.isAlive, e.hidden);
        if (fx.wantsBossSound) this.world.playSystemSound(13);
        if (fx.opacity <= 0 || hidden.has(i)) continue;
        let h = img.height;
        if (fx.bossCollapseHeight >= 0) h = Math.max(1, fx.bossCollapseHeight);
        let flash = fx.blendColor;
        if (targetFlash[i] && targetFlash[i][3] > flash[3]) flash = targetFlash[i];
        if (targeting === i && this.selectionCount % 30 < 15) flash = [255, 255, 255, Math.max(64, flash[3])];
        ui.sprite("b.e" + i, img, { x: e.screenX + sx + fx.shake, y: H - e.screenY }, { src: [0, 0, img.width, h], size: { w: img.width, h }, z: 1 + e.screenY / 1000,
          alpha: fx.opacity / 255, anchor: { x: 0.5, y: 0 }, blend: fx.additive ? 1 : 0, flash });
        if (targeting === i) ui.label("b.tn", e.name, { x: e.screenX, y: H - e.screenY + img.height + 10 }, { size: 22, align: "center", bold: true, z: 30 });
      }
      if (this.sideView) this.drawActors(b, targetFlash, hidden, sx);
      this.drawAnimations(b);
      if (b.log.length) {
        const lh = 34, r = R(8, H - 8 - b.log.length * lh - 16, W - 16, b.log.length * lh + 16);
        ui.rect("b.logbg", r, C(0, 0, 0, 0.55), 10, 6);
        b.log.forEach((l, i) => ui.richText("b.log" + i, l, { x: 26, y: r.maxY - 34 - i * lh }, 22, 11));
      }
      this.drawStatus(b); this.drawCommands(b); this.drawPopups();
    }
    drawActors(b, targetFlash, hidden, sx) {
      const ui = this.ui, scene = this.scene, members = b.members, ended = b.phase === "ending" || b.phase === "done";
      this.svActors.forEach((s, i) => {
        s.setActor(i < members.length ? members[i] : null);
        if (i >= members.length) return;
        const a = members[i];
        s.update(b.escaped, ended);
        const t = -(i + 1), feet = { x: s.x + sx, y: H - s.y }, z = 2 + s.y / 1000;
        const sh = scene.img("system", "Shadow2");
        if (sh) ui.sprite("b.ash" + i, sh, { x: feet.x, y: feet.y + 2 }, { z: z - 0.01 });
        if (hidden.has(t)) return;
        const sheet = scene.img("sv_actors", a.battlerName);
        if (sheet) {
          const cw = sheet.width / 9, ch = sheet.height / 6, f = s.frame;
          let flash = targetFlash[t] || null;
          if (this.sub.t === "actorTarget" && this.cur("ally") === i && this.selectionCount % 30 < 15) flash = [255, 255, 255, 64];
          ui.sprite("b.a" + i, sheet, feet, { src: [f.col * cw, f.row * ch, cw, ch], size: { w: cw, h: ch }, z, anchor: { x: 0.5, y: 0 }, flash });
        }
        if (s.weaponImageId > 0) {
          const page = Math.floor((s.weaponImageId - 1) / 12) + 1, idx = (s.weaponImageId - 1) % 12;
          const img = scene.img("system", "Weapons" + page);
          if (img) ui.sprite("b.aw" + i, img, { x: feet.x - 16, y: feet.y }, { src: [(Math.floor(idx / 6) * 3 + s.weaponPattern) * 96, (idx % 6) * 64, 96, 64], size: { w: 96, h: 64 }, z: z - 0.005, anchor: { x: 0.5, y: 0 } });
        }
        const ov = a.stateOverlayIndex, st = scene.img("system", "States");
        if (ov > 0 && st) ui.sprite("b.ao" + i, st, feet, { src: [(Math.floor(this.selectionCount / 8) % 8) * 96, (ov - 1) * 96, 96, 96], size: { w: 96, h: 96 }, z: z + 0.002, anchor: { x: 0.5, y: 0 } });
      });
    }
    drawAnimations(b) {
      this.animations.forEach((a, n) => {
        if (!a.started) return;
        const d = a.animation;
        let ox = W / 2, oy = H / 2;
        const frames = a.targets.map(t => this.targetFrame(t, b)).filter(f => f);
        if (!d.isScreen && frames.length) {
          ox = frames.reduce((s, f) => s + f.x, 0) / frames.length;
          oy = frames.map(f => (d.isMV ? (d.position === 0 ? f.y + f.h : d.position === 1 ? f.y + f.h / 2 : f.y) : (d.alignBottom ? f.y : f.y + f.h / 2))).reduce((s, y) => s + y, 0) / frames.length;
        }
        if (!d.isMV) { ox += d.offsetX; oy -= d.offsetY; }
        this.ui.push(5, g => LK.drawAnimation(this.scene, g, a, ox, H - oy));
        const f = a.screenFlashColor;
        if (f[3] > 0.5) this.ui.rect("b.sf" + n, R(0, 0, W, H), C(f[0] / 255, f[1] / 255, f[2] / 255, f[3] / 255), 6);
      });
    }
    consumeCues(b) {
      for (const c of b.cues) {
        if (c.id <= this.lastCue) continue;
        this.lastCue = c.id;
        let x = W / 2, y = H / 2;
        if (c.target !== null) { const f = this.targetFrame(c.target, b); if (f) { x = f.x + (c.target < 0 && this.sideView ? -32 : 0); y = c.target >= 0 ? f.y + f.h * 0.6 : f.y + (this.sideView ? 40 : 26); } }
        const k = c.kind, t = c.target;
        switch (k.t) {
          case "damage": this.popups.push({ text: String(k.v), color: white, x, y, age: 0 }); break;
          case "recover": this.popups.push({ text: String(k.v), color: TC[24], x, y, age: 0 }); break;
          case "mpDamage": this.popups.push({ text: String(Math.abs(k.v)), color: k.v > 0 ? TC[23] : TC[4], x, y, age: 0 }); break;
          case "miss": this.popups.push({ text: "Miss", color: TC[8], x, y, age: 0 }); break;
          case "critical": this.popups.push({ text: "Critical!", color: TC[18], x, y: y + 26, age: 0 }); break;
          case "collapse": if (t !== null && t >= 0) { const e = b.enemies.find(x2 => x2.index === t); const fx = this.enemyFx[t]; const type = e ? ["collapse", "bossCollapse", "instantCollapse"][e.collapseType] : null; if (type && fx && fx.appeared) fx.start(type); } break;
          case "effect": if (t !== null && t >= 0 && this.enemyFx[t]) this.enemyFx[t].start(k.e); break;
          case "shake": this.shake = 18; break;
          case "actorAct": if (!this.sideView && t !== null) this.actorFlash[t] = 14; break;
          case "motion": if (t !== null && t < 0 && -t - 1 < 4) this.svActors[-t - 1].requestMotion(k.m); break;
          case "weapon": if (t !== null && t < 0 && -t - 1 < 4) this.svActors[-t - 1].startWeapon(k.w); break;
          case "animation": { const a = this.project.animation(k.id); if (a) { const pb = new LK.AnimationPlayback(a, c.targets, k.mirror, k.delay); if (LK.Effects) LK.Effects.attach(pb); this.animations.push(pb); } break; }
        }
      }
    }
    drawPopups() {
      this.popups = this.popups.filter(p => {
        p.age++;
        if (p.age >= 70) return false;
        const rise = p.age < 10 ? p.age * 2.4 : 24;
        this.ui.label("b.pop", p.text, { x: p.x, y: p.y + rise }, { size: 34, color: p.color, align: "center", bold: true, z: 40, alpha: p.age > 50 ? (70 - p.age) / 20 : 1 });
        return true;
      });
    }
    drawStatus(b) {
      const ui = this.ui, t = this.terms, r = R(240, 8, W - 248, 180);
      ui.window("b.st", r, 20);
      const targetingAlly = this.sub.t === "actorTarget" && b.phase === "input" ? this.cur("ally") : null;
      b.members.slice(0, 4).forEach((a, i) => {
        const y = r.maxY - 46 - i * 40;
        if (b.inputIndex === i && b.phase === "input" && !b.isBusy) ui.rect("b.sel", R(r.x + 6, y - 10, r.w - 12, 38), C(1, 1, 1, 0.12), 21, 6);
        if (targetingAlly === i) ui.cursor("b.allyc", R(r.x + 6, y - 10, r.w - 12, 38), 21);
        const f = this.actorFlash[i];
        if (f !== undefined) { this.actorFlash[i] = f > 0 ? f - 1 : undefined; if (f <= 0) delete this.actorFlash[i]; ui.rect("b.afl" + i, R(r.x + 6, y - 10, r.w - 12, 38), C(1, 1, 1, f / 28), 21, 6); }
        ui.label("b.sn" + i, a.name, { x: r.x + 18, y }, { size: 21, color: a.isDead ? TC[18] : (a.hpRate < 0.25 ? TC[17] : white), z: 22, maxWidth: 110 });
        a.sortedStates.filter(s => s.iconIndex > 0).slice(0, 2).forEach((s, j) => ui.icon("b.ss" + i + "." + j, s.iconIndex, { x: r.x + 128 + j * 26, y: y - 6 }, 24, 22));
        const gx = r.x + 186, gw = 112;
        ui.gauge("b.hp" + i, R(gx, y - 2, gw, 8), a.hpRate, UI.hpColor, t.basic[3], String(a.hp), 22);
        ui.gauge("b.mp" + i, R(gx + gw + 14, y - 2, 90, 8), a.mpRate, UI.mpColor, t.basic[5], String(a.mp), 22);
        if (this.project.system.optDisplayTp) ui.gauge("b.tp" + i, R(gx + gw + 118, y - 2, 70, 8), a.tp / 100, UI.tpColor, t.basic[7], String(a.tp), 22);
      });
    }
    drawCommands(b) {
      if (b.phase !== "input" || b.isBusy || this.world.message) return;
      const ui = this.ui, t = this.terms;
      if (b.waitingForPartyCommand) { ui.list("b.party", R(8, 8, 224, 180), [{ text: t.commands[0] }, { text: t.commands[1], enabled: b.canEscape }], this.cur("party"), { rowHeight: 42 }); return; }
      const a = b.inputActor; if (!a) return;
      const cmds = this.actorCommands(a);
      ui.list("b.actor", R(8, 8, 224, 180), cmds.map(c => ({ text: c[0] })), this.cur("actor"), { active: this.sub.t === "actor", rowHeight: 38 });
      const listRect = R(8, 196, W - 16, 200);
      if (this.sub.t === "skills") {
        const skills = b.usableSkills(a).filter(s => s.stypeId === this.sub.stype);
        ui.list("b.list", listRect, skills.map(s => ({ text: s.name, icon: s.iconIndex, right: s.tpCost > 0 ? s.tpCost + "TP" : (s.mpCost > 0 ? String(a.skillMpCost(s)) : ""), enabled: a.canUse(s, true) })), this.cur("list"), { columns: 2 });
        const s = skills[this.cur("list")]; this.help(s ? s.description : "");
      } else if (this.sub.t === "items") {
        const items = b.usableItems();
        ui.list("b.list", listRect, items.map(it => ({ text: it.name, icon: it.iconIndex, right: ":" + this.world.state.count(1, it.id) })), this.cur("list"), { columns: 2 });
        const it = items[this.cur("list")]; this.help(it ? it.description : "");
      }
    }
    help(text) { this.ui.window("b.help", R(8, 404, W - 16, 64), 20); this.ui.richText("b.helpt", text, { x: 28, y: 428 }, 20, 22); }
  }
  LK.BattleController = BattleController;
})(LK);
