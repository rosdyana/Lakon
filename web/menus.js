// Lakon web runtime — Scene_Menu (Item, Skill, Equip, Status, Options, Save/Load, Game End), Scene_Shop and Scene_Name.
// Port of Sources/Lakon/MenuUI.swift and the Shop/Name controllers in BattleUI.swift.
"use strict";
(function (LK) {
  const W = LK.W, H = LK.H, R = LK.R, UI = LK.SceneUI;
  const { C, white } = LK.Color;
  const TC = UI.textColors;
  const isMenuUsable = i => i.occasion === 0 || i.occasion === 2;

  class Base {
    constructor(scene) { this.scene = scene; this.cursors = {}; }
    get world() { return this.scene.world; }
    get project() { return this.scene.project; }
    get ui() { return this.scene.ui; }
    get terms() { return this.project.system.terms; }
    cur(k) { return this.cursors[k] || 0; }
    move(k, n, u, columns = 1) { const c = UI.move(this.cur(k), n, u, columns); if (c !== this.cur(k)) this.world.playSystemSound(0); this.cursors[k] = Math.min(c, Math.max(0, n - 1)); }
  }

  class MenuController extends Base {
    constructor(scene, o) {
      super(scene);
      this.closed = false;
      this.standalone = !!(o.saveOnly || o.loadOnly || o.optionsOnly);
      this.stack = [{ t: "main" }];
      if (o.saveOnly) this.stack = [{ t: "files", save: true }];
      if (o.loadOnly) this.stack = [{ t: "files", save: false }];
      if (o.optionsOnly) this.stack = [{ t: "options" }];
    }
    get members() { return this.world.allMembers; }
    ok() { this.world.playSystemSound(1); }
    buzz() { this.world.playSystemSound(3); }
    back() { this.world.playSystemSound(2); this.stack.pop(); if (!this.stack.length) this.closed = true; }
    categoryItems(cat) {
      const s = this.world.state, p = this.project, keys = LK.GameState.sortedKeys;
      if (cat === 0) return keys(s.items).filter(id => { const it = p.item(id); return it && it.itypeId === 1; }).map(id => [1, id]);
      if (cat === 1) return keys(s.weapons).map(id => [2, id]);
      if (cat === 2) return keys(s.armors).map(id => [3, id]);
      return keys(s.items).filter(id => { const it = p.item(id); return it && it.itypeId === 2; }).map(id => [1, id]);
    }
    info(kind, id) {
      const x = kind === 2 ? this.project.weapon(id) : kind === 3 ? this.project.armor(id) : this.project.item(id);
      return { name: x ? x.name : "?", icon: x ? x.iconIndex : 0, desc: x ? x.description : "" };
    }
    step(u) {
      const st = this.stack[this.stack.length - 1];
      if (!st) { this.closed = true; return; }
      const w = this.world, members = this.members;
      switch (st.t) {
        case "main": {
          this.move("main", MenuController.commands.length, u);
          if (u.cancel) { this.back(); return; }
          if (!u.ok) return;
          const c = this.cur("main");
          if (c === 0) { this.ok(); this.stack.push({ t: "itemCategory" }); }
          else if (c >= 1 && c <= 3) { this.ok(); this.stack.push({ t: "pickActor", purpose: ["skill", "equip", "status"][c - 1] }); }
          else if (c === 4) { this.ok(); this.stack.push({ t: "options" }); }
          else if (c === 5) { if (w.state.saveEnabled) { this.ok(); this.stack.push({ t: "files", save: true }); } else this.buzz(); }
          else { this.ok(); this.stack.push({ t: "gameEnd" }); }
          break;
        }
        case "pickActor": {
          this.move("actor", members.length, u);
          if (u.cancel) { this.back(); return; }
          if (!u.ok || this.cur("actor") >= members.length) return;
          this.ok();
          const a = this.cur("actor");
          this.stack.push(st.purpose === "skill" ? { t: "skillList", actor: a } : st.purpose === "equip" ? { t: "equipSlots", actor: a } : { t: "status", actor: a });
          break;
        }
        case "itemCategory":
          this.move("cat", 4, u, 4);
          if (u.cancel) { this.back(); return; }
          if (u.ok) { this.ok(); this.cursors.items = 0; this.stack.push({ t: "itemList", category: this.cur("cat") }); }
          break;
        case "itemList": {
          const list = this.categoryItems(st.category);
          this.move("items", list.length, u, 2);
          if (u.cancel) { this.back(); return; }
          if (!u.ok || this.cur("items") >= list.length) return;
          const [k, id] = list[this.cur("items")], it = this.project.item(id);
          if (k !== 1 || !it || !isMenuUsable(it) || it.scope === 0) { this.buzz(); return; }
          this.ok();
          if (LK.usable.isForFriend(it) && !LK.usable.isForUser(it)) this.stack.push({ t: "itemTarget", category: st.category, itemId: id });
          else if (members[0]) w.useInMenu(id, 0, members[0], members[0]);
          break;
        }
        case "itemTarget": {
          this.move("target", members.length, u);
          if (u.cancel) { this.back(); return; }
          if (!u.ok || !members[0]) return;
          if (!w.useInMenu(st.itemId, 0, members[0], members[this.cur("target")] || null)) this.buzz();
          if (w.state.count(1, st.itemId) === 0) this.stack.pop();
          if (w.isEventRunning) this.closed = true;
          break;
        }
        case "skillList": {
          const a = members[st.actor]; if (!a) { this.back(); return; }
          const skills = a.skills;
          this.move("skills", skills.length, u, 2);
          if (u.pageDown) { this.cursors.actor = (st.actor + 1) % members.length; this.stack[this.stack.length - 1] = { t: "skillList", actor: this.cur("actor") }; return; }
          if (u.cancel) { this.back(); return; }
          const s = skills[this.cur("skills")];
          if (!u.ok || !s) return;
          if (!isMenuUsable(s) || !a.canUse(s, false)) { this.buzz(); return; }
          this.ok();
          if (LK.usable.isForFriend(s) && !LK.usable.isForUser(s)) this.stack.push({ t: "skillTarget", actor: st.actor, skillId: s.id });
          else w.useInMenu(0, s.id, a, a);
          break;
        }
        case "skillTarget": {
          this.move("target", members.length, u);
          if (u.cancel) { this.back(); return; }
          const a = members[st.actor];
          if (!u.ok || !a) return;
          if (!w.useInMenu(0, st.skillId, a, members[this.cur("target")] || null)) this.buzz();
          break;
        }
        case "equipSlots": {
          this.move("slot", 5, u);
          if (u.pageDown) { this.cursors.actor = (st.actor + 1) % members.length; this.stack[this.stack.length - 1] = { t: "equipSlots", actor: this.cur("actor") }; return; }
          if (u.cancel) { this.back(); return; }
          const a = members[st.actor];
          if (!u.ok || !a) return;
          if (a.isEquipLocked(this.cur("slot"))) { this.buzz(); return; }
          this.ok(); this.cursors.equipItem = 0;
          this.stack.push({ t: "equipItems", actor: st.actor, slot: this.cur("slot") });
          break;
        }
        case "equipItems": {
          const a = members[st.actor]; if (!a) { this.back(); return; }
          const options = this.equipOptions(a, st.slot);
          this.move("equipItem", options.length, u);
          if (u.cancel) { this.back(); return; }
          if (!u.ok) return;
          w.equip(a, st.slot, options[this.cur("equipItem")]);
          this.stack.pop();
          break;
        }
        case "status": {
          const n = Math.max(1, members.length);
          if (u.pageDown || u.right) { this.cursors.actor = (st.actor + 1) % n; this.stack[this.stack.length - 1] = { t: "status", actor: this.cur("actor") }; w.playSystemSound(0); }
          if (u.pageUp || u.left) { this.cursors.actor = (st.actor + n - 1) % n; this.stack[this.stack.length - 1] = { t: "status", actor: this.cur("actor") }; w.playSystemSound(0); }
          if (u.cancel || u.ok) this.back();
          break;
        }
        case "options": {
          const keys = ["bgm", "bgs", "me", "se"], vol = this.scene.audio.volumes;
          this.move("opt", keys.length + 1, u);
          const i = this.cur("opt");
          if (i < keys.length && (u.left || u.right)) {
            vol[keys[i]] = LK.clamp((vol[keys[i]] === undefined ? 0.9 : vol[keys[i]]) + (u.right ? 0.2 : -0.2), 0, 1);
            this.scene.audio.saveVolumes(); w.playSystemSound(0);
          }
          if (u.cancel || (u.ok && i === keys.length)) this.back();
          break;
        }
        case "files": {
          this.move("file", LK.Game.saveCount, u);
          if (u.cancel) { this.back(); return; }
          if (!u.ok) return;
          const slot = this.cur("file") + 1;
          if (st.save) { if (this.scene.saveGame(slot)) { this.scene.toast = { s: "Saved to File " + slot, n: 90 }; if (this.standalone) this.closed = true; else this.stack.pop(); } }
          else if (this.scene.saveExists(slot)) { this.scene.loadGame(slot); this.closed = true; } else this.buzz();
          break;
        }
        case "gameEnd":
          this.move("end", 2, u);
          if (u.cancel) { this.back(); return; }
          if (u.ok) { if (this.cur("end") === 0) { this.ok(); this.closed = true; w.audio.fadeOutBgm(1); this.scene.showTitle(); } else this.back(); }
          break;
      }
    }
    equipOptions(a, slot) {
      const pool = slot === 0 ? this.world.state.weapons : this.world.state.armors;
      return LK.GameState.sortedKeys(pool).filter(id => a.canEquip(slot, id)).concat([0]);
    }

    render() {
      const ui = this.ui;
      if (!this.standalone) ui.rect("menu.dim", R(0, 0, W, H), C(0, 0, 0, 0.35), 18);
      const st = this.stack[this.stack.length - 1]; if (!st) return;
      switch (st.t) {
        case "main": case "pickActor": this.drawMain(st.t === "main"); this.drawPartyStatus(st.t === "pickActor" ? this.cur("actor") : null); break;
        case "itemCategory": case "itemList": case "itemTarget": this.drawItems(st); break;
        case "skillList": case "skillTarget": this.drawSkills(st.actor, st); break;
        case "equipSlots": case "equipItems": this.drawEquip(st.actor, st); break;
        case "status": this.drawStatus(st.actor); break;
        case "options": this.drawOptions(); break;
        case "files": this.drawFiles(st.save); break;
        case "gameEnd":
          this.drawMain(false); this.drawPartyStatus(null);
          ui.list("end", R(W / 2 - 140, H / 2 - 60, 280, 110), [{ text: "To Title" }, { text: "Cancel" }], this.cur("end"), { z: 40 });
          break;
      }
    }
    drawMain(active) {
      const ui = this.ui, s = this.world.state;
      ui.list("main", R(16, 120, 200, 488), MenuController.commands.map((c, i) => ({ text: c, enabled: i !== 5 || s.saveEnabled })), this.cur("main"), { active, rowHeight: 44 });
      ui.window("gold.w", R(16, 16, 200, 92), 20);
      ui.label("gold.v", String(s.gold), { x: 160, y: 50 }, { size: 24, align: "right", z: 22 });
      ui.label("gold.u", this.project.system.currencyUnit, { x: 200, y: 50 }, { size: 20, color: UI.systemColor, align: "right", z: 22 });
      const mins = Math.floor(s.playFrames / 3600), secs = Math.floor(s.playFrames / 60) % 60;
      ui.label("gold.t", mins + ":" + String(secs).padStart(2, "0"), { x: 32, y: 80 }, { size: 16, color: UI.systemColor, z: 22 });
    }
    drawPartyStatus(cursor, x = 232, width = 568) {
      const r = R(x, 16, width, 592);
      this.ui.window("party.w", r, 20);
      this.members.slice(0, 4).forEach((a, i) => {
        const top = r.maxY - 12 - i * 144;
        if (cursor === i) this.ui.cursor("party.c", R(r.x + 8, top - 140, r.w - 16, 136), 21);
        this.drawActorBlock("p" + i, a, r.x + 20, top, r.w - 40);
      });
    }
    drawActorBlock(k, a, x, top, width) {
      const ui = this.ui, t = this.terms, d = this.project.actor(a.actorId);
      if (!(d && this.scene.drawFace(k + ".face", d.faceName, d.faceIndex, { x: x + 56, y: top - 68 }, 112, 22, a.isDead ? 0.5 : 1)) && d)
        this.scene.drawCharacter(k + ".ch", d.characterName, d.characterIndex, { x: x + 56, y: top - 70 }, 96, 22, a.isDead ? 0.5 : 1);
      const tx = x + 132;
      ui.label(k + ".n", a.name, { x: tx, y: top - 34 }, { size: 24, color: a.isDead ? TC[18] : white, bold: true, z: 22 });
      ui.label(k + ".cl", a.currentClass ? a.currentClass.name : "", { x: tx + 190, y: top - 34 }, { size: 20, z: 22 });
      ui.label(k + ".lvl", t.basic[1], { x: tx, y: top - 66 }, { size: 18, color: UI.systemColor, z: 22 });
      ui.label(k + ".lv", String(a.level), { x: tx + 60, y: top - 66 }, { size: 20, align: "right", z: 22 });
      a.sortedStates.filter(s => s.iconIndex > 0).slice(0, 4).forEach((s, j) => ui.icon(k + ".st" + j, s.iconIndex, { x: tx + 80 + j * 30, y: top - 74 }, 28, 22));
      for (let p = 0; p < 8; p++) if (a.buffs[p] !== 0) ui.icon(k + ".bf" + p, (a.buffs[p] > 0 ? 32 : 48) + p, { x: tx + 80 + (4 + p) * 30, y: top - 74 }, 28, 22);
      const gw = Math.min(180, width - 150);
      ui.gauge(k + ".hp", R(tx + 190, top - 74, gw, 8), a.hpRate, UI.hpColor, t.basic[3], a.hp + "/" + a.mhp, 22);
      ui.gauge(k + ".mp", R(tx + 190, top - 104, gw, 8), a.mpRate, UI.mpColor, t.basic[5], a.mp + "/" + a.mmp, 22);
      if (this.project.system.optDisplayTp) ui.gauge(k + ".tp", R(tx, top - 104, 160, 8), a.tp / 100, UI.tpColor, t.basic[7], String(a.tp), 22);
    }
    helpWindow(text) { this.ui.window("help.w", R(16, H - 92, W - 32, 76), 20); this.ui.richText("help.t", text, { x: 34, y: H - 62 }, 21, 22); }
    drawItems(st) {
      const ui = this.ui, cats = ["Item", "Weapon", "Armor", "Key Item"], catActive = st.t === "itemCategory";
      ui.window("cat.w", R(16, 456, W - 32, 60), 20);
      cats.forEach((c, i) => {
        const x = 28 + i * (W - 56) / 4;
        if (i === this.cur("cat")) ui.cursor("cat.c", R(x, 466, (W - 56) / 4 - 6, 40), 21);
        ui.label("cat." + i, c, { x: x + (W - 56) / 8, y: 478 }, { size: 21, align: "center", z: 22, alpha: catActive || i === this.cur("cat") ? 1 : 0.6 });
      });
      const list = this.categoryItems(this.cur("cat"));
      const rows = list.map(([k, id]) => { const inf = this.info(k, id), it = this.project.item(id); const usable = k === 1 && it && isMenuUsable(it); return { text: inf.name, icon: inf.icon, right: ":" + this.world.state.count(k, id), enabled: usable || k !== 1 }; });
      ui.list("items", R(16, 16, W - 32, 428), rows, catActive ? null : this.cur("items"), { active: st.t === "itemList", columns: 2 });
      const sel = list[this.cur("items")];
      if (!catActive && sel) this.helpWindow(this.info(sel[0], sel[1]).desc); else this.helpWindow("Choose a category.");
      if (st.t === "itemTarget") this.drawTargetPicker();
    }
    drawTargetPicker() {
      const r = R(W - 452, 16, 436, 592);
      this.ui.window("tgt.w", r, 40);
      this.members.slice(0, 4).forEach((a, i) => {
        const top = r.maxY - 12 - i * 144;
        if (this.cur("target") === i) this.ui.cursor("tgt.c", R(r.x + 8, top - 140, r.w - 16, 136), 41);
        this.drawActorBlockCompact("t" + i, a, r.x + 18, top);
      });
    }
    drawActorBlockCompact(k, a, x, top) {
      const ui = this.ui, t = this.terms, d = this.project.actor(a.actorId);
      if (d) this.scene.drawCharacter(k + ".ch", d.characterName, d.characterIndex, { x: x + 36, y: top - 70 }, 72, 42);
      ui.label(k + ".n", a.name, { x: x + 90, y: top - 36 }, { size: 22, bold: true, z: 42 });
      ui.label(k + ".lv", t.basic[1] + " " + a.level, { x: x + 300, y: top - 36 }, { size: 18, z: 42 });
      ui.gauge(k + ".hp", R(x + 90, top - 76, 300, 8), a.hpRate, UI.hpColor, t.basic[3], a.hp + "/" + a.mhp, 42);
      ui.gauge(k + ".mp", R(x + 90, top - 110, 300, 8), a.mpRate, UI.mpColor, t.basic[5], a.mp + "/" + a.mmp, 42);
    }
    drawSkills(ai, st) {
      const a = this.members[ai]; if (!a) return;
      const ui = this.ui;
      ui.window("sk.actor", R(16, 380, W - 32, 140), 20);
      this.drawActorBlock("ska", a, 32, 512, W - 64);
      const rows = a.skills.map(s => ({ text: s.name, icon: s.iconIndex, right: s.tpCost > 0 ? s.tpCost + " TP" : (s.mpCost > 0 ? String(a.skillMpCost(s)) : ""), enabled: isMenuUsable(s) && a.canUse(s, false) }));
      ui.list("skills", R(16, 16, W - 32, 352), rows, this.cur("skills"), { active: st.t === "skillList", columns: 2, title: "Skills — Q/W to switch actor" });
      const s = a.skills[this.cur("skills")];
      this.helpWindow(s ? s.description : "");
      if (st.t === "skillTarget") this.drawTargetPicker();
    }
    drawEquip(ai, st) {
      const a = this.members[ai]; if (!a) return;
      const ui = this.ui, p = this.project, t = this.terms;
      const slotNames = [1, 2, 3, 4, 5].map(i => p.system.equipTypes[i] || "Slot");
      const rows = [0, 1, 2, 3, 4].map(i => { const id = a.equips[i] || 0, item = id > 0 ? (i === 0 ? p.weapon(id) : p.armor(id)) : null; return { text: slotNames[i] + ":  " + (item ? item.name : "—"), icon: item ? item.iconIndex : 0, enabled: !a.isEquipLocked(i) }; });
      ui.list("eqslots", R(300, 236, W - 316, 288), rows, this.cur("slot"), { active: st.t === "equipSlots", rowHeight: 40, title: a.name + " — Q/W to switch actor" });
      let preview = null;
      if (st.t === "equipItems") {
        const options = this.equipOptions(a, st.slot), cand = options[this.cur("equipItem")] || 0, old = a.equips[st.slot];
        const candItem = cand > 0 ? (st.slot === 0 ? p.weapon(cand) : p.armor(cand)) : null, oldItem = old > 0 ? (st.slot === 0 ? p.weapon(old) : p.armor(old)) : null;
        preview = [0, 1, 2, 3, 4, 5, 6, 7].map(i => a.param(i) - (oldItem ? oldItem.params[i] : 0) + (candItem ? candItem.params[i] : 0));
        const irows = options.map(id => { if (id === 0) return { text: "(Remove)" }; const e = st.slot === 0 ? p.weapon(id) : p.armor(id); return { text: e ? e.name : "?", icon: e ? e.iconIndex : 0, right: ":" + this.world.state.count(st.slot === 0 ? 2 : 3, id) }; });
        ui.list("eqitems", R(300, 16, W - 316, 208), irows, this.cur("equipItem"), { columns: 2 });
        this.helpWindowSmall(candItem ? candItem.description : "");
      } else {
        const id = a.equips[this.cur("slot")] || 0, it = id > 0 ? (this.cur("slot") === 0 ? p.weapon(id) : p.armor(id)) : null;
        this.helpWindowSmall(it ? it.description : "");
      }
      const r = R(16, 16, 272, 508);
      ui.window("eqp.w", r, 20);
      ui.label("eqp.n", a.name, { x: 34, y: r.maxY - 40 }, { size: 24, bold: true, z: 22 });
      for (let pi = 2; pi < 8; pi++) {
        const y = r.maxY - 90 - (pi - 2) * 40;
        ui.label("eqp.l" + pi, t.params[pi], { x: 34, y }, { size: 20, color: UI.systemColor, z: 22 });
        ui.label("eqp.v" + pi, String(a.param(pi)), { x: 200, y }, { size: 20, align: "right", z: 22 });
        if (preview) ui.label("eqp.p" + pi, "→ " + preview[pi], { x: 268, y }, { size: 20, color: preview[pi] > a.param(pi) ? TC[24] : preview[pi] < a.param(pi) ? TC[25] : white, align: "right", z: 22 });
      }
    }
    helpWindowSmall(text) { this.ui.window("help.w", R(300, H - 92, W - 316, 76), 20); this.ui.richText("help.t", text, { x: 318, y: H - 62 }, 19, 22); }
    drawStatus(ai) {
      const a = this.members[ai]; if (!a) return;
      const ui = this.ui, t = this.terms, p = this.project;
      ui.window("st.w", R(16, 16, W - 32, H - 32), 20);
      this.drawActorBlock("sta", a, 36, H - 28, W - 72);
      ui.label("st.nick", a.nickname, { x: 600, y: H - 62 }, { size: 20, color: UI.systemColor, z: 22 });
      const top = H - 200;
      for (let pi = 2; pi < 8; pi++) {
        const y = top - (pi - 2) * 36;
        ui.label("st.l" + pi, t.params[pi], { x: 48, y }, { size: 20, color: UI.systemColor, z: 22 });
        ui.label("st.v" + pi, String(a.param(pi)), { x: 260, y }, { size: 20, align: "right", z: 22 });
      }
      ui.label("st.exp1", LK.termMessage(t, "expTotal", t.basic[8]), { x: 300, y: top }, { size: 20, color: UI.systemColor, z: 22 });
      ui.label("st.exp1v", String(a.currentExp), { x: 560, y: top }, { size: 20, align: "right", z: 22 });
      ui.label("st.exp2", LK.termMessage(t, "expNext", t.basic[0]), { x: 300, y: top - 36 }, { size: 20, color: UI.systemColor, z: 22 });
      ui.label("st.exp2v", String(a.expToNext), { x: 560, y: top - 36 }, { size: 20, align: "right", z: 22 });
      a.equips.forEach((id, i) => {
        if (id <= 0) return;
        const e = i === 0 ? p.weapon(id) : p.armor(id);
        ui.icon("st.ei" + i, e ? e.iconIndex : 0, { x: 580, y: top - 6 - i * 36 }, 28, 22);
        ui.label("st.e" + i, e ? e.name : "", { x: 616, y: top - i * 36 }, { size: 20, z: 22 });
      });
      const d = p.actor(a.actorId);
      ui.richText("st.prof", d ? d.profile : "", { x: 48, y: 60 }, 20, 22);
      ui.label("st.hint", "←/→ next member", { x: W - 40, y: 30 }, { size: 14, align: "right", z: 22, alpha: 0.6 });
    }
    drawOptions() {
      const keys = ["bgm", "bgs", "me", "se"], m = this.terms.messages, vol = this.scene.audio.volumes;
      const names = [m.bgmVolume || "BGM Volume", m.bgsVolume || "BGS Volume", m.meVolume || "ME Volume", m.seVolume || "SE Volume"];
      const rows = keys.map((k, i) => ({ text: names[i], right: Math.round((vol[k] === undefined ? 0.9 : vol[k]) * 100) + "%" })).concat([{ text: "Done" }]);
      this.ui.list("opt", R(W / 2 - 220, 180, 440, 250), rows, this.cur("opt"), { rowHeight: 42, z: 30, title: "Options — ←/→ to change" });
    }
    drawFiles(save) {
      const ui = this.ui, m = this.terms.messages;
      ui.window("files.h", R(16, H - 76, W - 32, 60), 30);
      ui.label("files.ht", m[save ? "saveMessage" : "loadMessage"] || (save ? "Save to which file?" : "Load which file?"), { x: 34, y: H - 54 }, { size: 22, z: 32 });
      const r = R(16, 16, W - 32, H - 104);
      ui.window("files.w", r, 30);
      const rowH = r.h / LK.Game.saveCount;
      for (let i = 0; i < LK.Game.saveCount; i++) {
        const top = r.maxY - i * rowH;
        if (this.cur("file") === i) ui.cursor("files.c", R(r.x + 8, top - rowH + 4, r.w - 16, rowH - 8), 31);
        ui.label("files.n" + i, (m.file || "File") + " " + (i + 1), { x: 40, y: top - 40 }, { size: 22, color: UI.systemColor, z: 32 });
        const inf = this.scene.saveInfo(i + 1);
        if (inf) {
          ui.label("files.m" + i, inf.mapName, { x: 200, y: top - 40 }, { size: 22, z: 32 });
          ui.label("files.l" + i, inf.leader + "  " + this.terms.basic[1] + " " + inf.level, { x: 200, y: top - 76 }, { size: 20, z: 32 });
          const mins = Math.floor(inf.playFrames / 3600), secs = Math.floor(inf.playFrames / 60) % 60;
          ui.label("files.t" + i, mins + ":" + String(secs).padStart(2, "0"), { x: W - 50, y: top - 40 }, { size: 20, align: "right", z: 32 });
          ui.label("files.d" + i, new Date(inf.savedAt).toLocaleString(), { x: W - 50, y: top - 76 }, { size: 16, align: "right", z: 32, alpha: 0.7 });
        } else ui.label("files.m" + i, "— empty —", { x: 200, y: top - 40 }, { size: 20, z: 32, alpha: 0.5 });
      }
    }
  }
  MenuController.commands = ["Item", "Skill", "Equip", "Status", "Options", "Save", "Game End"];
  LK.MenuController = MenuController;

  class ShopController extends Base {
    constructor(scene) { super(scene); this.sub = "command"; this.qty = 1; }
    get shop() { return this.world.shop; }
    sellList() {
      const s = this.world.state, p = this.project, keys = LK.GameState.sortedKeys;
      if (this.cur("scat") === 0) return keys(s.items).filter(id => { const it = p.item(id); return it && it.itypeId === 1; }).map(id => [0, id]);
      if (this.cur("scat") === 1) return keys(s.weapons).map(id => [1, id]);
      return keys(s.armors).map(id => [2, id]);
    }
    step(u) {
      const shop = this.shop, w = this.world, Shop = LK.Shop; if (!shop) return;
      switch (this.sub) {
        case "command":
          this.move("cmd", 3, u, 3);
          if (u.cancel) { w.playSystemSound(2); w.shop = null; return; }
          if (u.ok) {
            const c = this.cur("cmd");
            if (c === 0) { w.playSystemSound(1); this.sub = "buy"; }
            else if (c === 1) { if (shop.purchaseOnly) w.playSystemSound(3); else { w.playSystemSound(1); this.sub = "sellCategory"; } }
            else { w.playSystemSound(2); w.shop = null; }
          }
          break;
        case "buy": {
          this.move("buy", shop.goods.length, u);
          if (u.cancel) { w.playSystemSound(2); this.sub = "command"; }
          const g = shop.goods[this.cur("buy")];
          if (u.ok && g) { if (Shop.maxBuy(g, w) > 0) { w.playSystemSound(1); this.qty = 1; this.sub = "buyQty"; } else w.playSystemSound(3); }
          break;
        }
        case "buyQty": {
          const g = shop.goods[this.cur("buy")]; if (!g) { this.sub = "buy"; return; }
          this.adjustQty(u, Shop.maxBuy(g, w));
          if (u.cancel) { w.playSystemSound(2); this.sub = "buy"; }
          if (u.ok) { Shop.buy(g, this.qty, w); this.sub = "buy"; }
          break;
        }
        case "sellCategory":
          this.move("scat", 3, u, 3);
          if (u.cancel) { w.playSystemSound(2); this.sub = "command"; }
          if (u.ok) { w.playSystemSound(1); this.cursors.sell = 0; this.sub = "sell"; }
          break;
        case "sell": {
          const list = this.sellList();
          this.move("sell", list.length, u, 2);
          if (u.cancel) { w.playSystemSound(2); this.sub = "sellCategory"; }
          const it = list[this.cur("sell")];
          if (u.ok && it) { if (Shop.basePrice(it[0], it[1], this.project) > 0) { w.playSystemSound(1); this.qty = 1; this.sub = "sellQty"; } else w.playSystemSound(3); }
          break;
        }
        case "sellQty": {
          const it = this.sellList()[this.cur("sell")]; if (!it) { this.sub = "sell"; return; }
          this.adjustQty(u, w.state.count(it[0] + 1, it[1]));
          if (u.cancel) { w.playSystemSound(2); this.sub = "sell"; }
          if (u.ok) { Shop.sell(it[0], it[1], this.qty, w); this.sub = "sell"; }
          break;
        }
      }
    }
    adjustQty(u, m) {
      const old = this.qty;
      if (u.right) this.qty++; if (u.left) this.qty--; if (u.up) this.qty += 10; if (u.down) this.qty -= 10;
      this.qty = Math.max(1, Math.min(Math.max(1, m), this.qty));
      if (this.qty !== old) this.world.playSystemSound(0);
    }
    info(kind, id) {
      const p = this.project;
      if (kind === 1) { const x = p.weapon(id); return [x ? x.name : "?", x ? x.iconIndex : 0, x ? x.description : "", x ? x.params : null]; }
      if (kind === 2) { const x = p.armor(id); return [x ? x.name : "?", x ? x.iconIndex : 0, x ? x.description : "", x ? x.params : null]; }
      const x = p.item(id); return [x ? x.name : "?", x ? x.iconIndex : 0, x ? x.description : "", null];
    }
    render() {
      const shop = this.shop; if (!shop) return;
      const ui = this.ui, p = this.project, w = this.world, unit = p.system.currencyUnit, t = p.system.terms;
      ui.window("shop.help", R(8, H - 84, W - 16, 76), 20);
      ui.window("shop.cmd", R(8, H - 152, W - 232, 60), 20);
      [t.commands[24] || "Buy", t.commands[25] || "Sell", t.commands[22] || "Cancel"].forEach((c, i) => {
        const x = 20 + i * (W - 256) / 3;
        if (this.cur("cmd") === i) ui.cursor("shop.cc", R(x, H - 142, (W - 256) / 3 - 6, 40), 21);
        ui.label("shop.c" + i, c, { x: x + (W - 256) / 6, y: H - 130 }, { size: 22, align: "center", z: 22, alpha: this.sub === "command" || this.cur("cmd") === i ? 1 : 0.6 });
      });
      ui.window("shop.gold", R(W - 216, H - 152, 208, 60), 20);
      ui.label("shop.g", w.state.gold + " " + unit, { x: W - 26, y: H - 130 }, { size: 22, align: "right", z: 22 });
      let desc = "", owned = null, params = null;
      if (["command", "buy", "buyQty"].includes(this.sub)) {
        const rows = shop.goods.map(g => { const [n, ic] = this.info(g.kind, g.id); return { text: n, icon: ic, right: String(g.price), enabled: g.price <= w.state.gold }; });
        ui.list("shop.buy", R(8, 8, 456, H - 168), rows, this.sub === "command" ? null : this.cur("buy"), { active: this.sub === "buy" });
        const g = shop.goods[this.cur("buy")];
        if (this.sub !== "command" && g) { const i = this.info(g.kind, g.id); desc = i[2]; params = i[3]; owned = w.state.count(g.kind + 1, g.id); }
        if (this.sub === "buyQty" && g) this.qtyWindow(g.price, unit);
      } else {
        ui.window("shop.scat", R(8, H - 220, W - 16, 60), 20);
        ["Item", "Weapon", "Armor"].forEach((c, i) => {
          const x = 20 + i * (W - 40) / 3;
          if (this.cur("scat") === i) ui.cursor("shop.scc", R(x, H - 210, (W - 40) / 3 - 6, 40), 21);
          ui.label("shop.sc" + i, c, { x: x + (W - 40) / 6, y: H - 198 }, { size: 22, align: "center", z: 22 });
        });
        const list = this.sellList();
        const rows = list.map(([k, id]) => { const [n, ic] = this.info(k, id); return { text: n, icon: ic, right: ":" + w.state.count(k + 1, id), enabled: LK.Shop.basePrice(k, id, p) > 0 }; });
        ui.list("shop.sell", R(8, 8, W - 16, H - 236), rows, this.sub === "sellCategory" ? null : this.cur("sell"), { active: this.sub === "sell", columns: 2 });
        const it = list[this.cur("sell")];
        if (this.sub !== "sellCategory" && it) desc = this.info(it[0], it[1])[2];
        if (this.sub === "sellQty" && it) this.qtyWindow(Math.trunc(LK.Shop.basePrice(it[0], it[1], p) / 2), unit);
      }
      ui.richText("shop.desc", desc, { x: 26, y: H - 56 }, 20, 22);
      if (this.sub === "buy" || this.sub === "buyQty") {
        const r = R(472, 8, W - 480, H - 168);
        ui.window("shop.st", r, 20);
        if (owned !== null) ui.label("shop.own", (t.messages.possession || "Possession") + ":  " + owned, { x: r.x + 18, y: r.maxY - 40 }, { size: 20, z: 22 });
        const g = shop.goods[this.cur("buy")];
        if (params && g) w.allMembers.slice(0, 4).forEach((a, i) => {
          const armor = p.armor(g.id), slot = g.kind === 1 ? 0 : Math.max(0, (armor ? armor.etypeId : 2) - 1);
          const can = a.canEquip(slot, g.id), curId = a.equips[slot] || 0;
          const cur = curId > 0 ? (slot === 0 ? p.weapon(curId) : p.armor(curId)) : null;
          const pid = g.kind === 1 ? 2 : 3, diff = params[pid] - (cur ? cur.params[pid] : 0);
          const y = r.maxY - 90 - i * 60;
          ui.label("shop.an" + i, a.name, { x: r.x + 18, y }, { size: 20, z: 22, alpha: can ? 1 : 0.45 });
          ui.label("shop.ad" + i, can ? t.params[pid] + " " + (diff >= 0 ? "+" : "") + diff : "—", { x: r.maxX - 18, y }, { size: 20, color: diff > 0 ? TC[24] : diff < 0 ? TC[25] : white, align: "right", z: 22, alpha: can ? 1 : 0.45 });
        });
      }
    }
    qtyWindow(price, unit) {
      const ui = this.ui, r = R(W / 2 - 200, 200, 400, 120);
      ui.window("shop.q", r, 40);
      ui.label("shop.qn", "×  " + this.qty, { x: r.x + 30, y: r.maxY - 50 }, { size: 26, z: 42 });
      ui.label("shop.qt", price * this.qty + " " + unit, { x: r.maxX - 24, y: r.maxY - 50 }, { size: 26, align: "right", z: 42 });
      ui.label("shop.qh", "←/→ ±1   ↑/↓ ±10   Z buy/sell", { x: r.midX, y: r.y + 18 }, { size: 15, align: "center", z: 42, alpha: 0.7 });
    }
  }
  LK.ShopController = ShopController;

  class NameController extends Base {
    constructor(scene) {
      super(scene);
      const req = scene.world.nameInput || { actorId: 1, maxLength: 8 };
      this.actorId = req.actorId; this.maxLength = req.maxLength; this.cursor = 0;
      const a = scene.world.actor(req.actorId); this.name = a ? a.name : "";
    }
    step(u) {
      const w = this.world, T = NameController.table;
      for (const ch of u.typed || "") if ([...this.name].length < this.maxLength) this.name += ch;
      if (u.backspace) { this.name = [...this.name].slice(0, -1).join(""); return; }
      const c = UI.move(this.cursor, T.length, u, 10); if (c !== this.cursor) w.playSystemSound(0); this.cursor = c;
      if (u.cancel && this.name) { this.name = [...this.name].slice(0, -1).join(""); w.playSystemSound(2); }
      if (u.ok) {
        const k = T[this.cursor];
        if (k === "OK") { if (!this.name.trim()) { w.playSystemSound(3); return; } const a = w.actor(this.actorId); if (a) a.setName(this.name); w.playSystemSound(1); w.nameInput = null; }
        else if (k === "←") this.name = [...this.name].slice(0, -1).join("");
        else if ([...this.name].length < this.maxLength) { this.name += k; w.playSystemSound(0); } else w.playSystemSound(3);
      }
    }
    render() {
      const ui = this.ui, T = NameController.table;
      ui.rect("name.dim", R(0, 0, W, H), C(0, 0, 0, 0.5), 18);
      const top = R(108, 452, W - 216, 140);
      ui.window("name.top", top, 20);
      const a = this.project.actor(this.actorId);
      if (a) this.scene.drawCharacter("name.ch", a.characterName, a.characterIndex, { x: top.x + 70, y: top.midY }, 96, 21);
      const display = this.name + "_".repeat(Math.max(0, this.maxLength - [...this.name].length));
      ui.label("name.v", [...display].join(" "), { x: top.x + 150, y: top.midY - 10 }, { size: 32, z: 22 });
      const r = R(108, 32, W - 216, 404);
      ui.window("name.grid", r, 20);
      T.forEach((k, i) => {
        const x = r.x + 24 + (i % 10) * ((r.w - 48) / 10), y = r.maxY - 56 - Math.floor(i / 10) * 50;
        if (i === this.cursor) ui.cursor("name.c", R(x - 4, y - 12, (r.w - 48) / 10, 44), 21);
        ui.label("name.k" + i, k === " " ? "␣" : k, { x: x + (r.w - 48) / 20 - 4, y }, { size: 24, align: "center", z: 22 });
      });
      ui.label("name.h", "Type or pick letters · Backspace removes · choose OK to confirm", { x: W / 2, y: 44 }, { size: 15, align: "center", z: 22, alpha: 0.7 });
    }
  }
  NameController.table = [..."ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 "].concat(["←", "OK"]);
  LK.NameController = NameController;
})(LK);
