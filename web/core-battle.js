// Lakon web runtime — battlers, actions, the battle manager and sprite logic.
// Port of Sources/LakonCore/Battler.swift, Action.swift, Battle.swift, BattleSprites.swift.
"use strict";
(function (LK) {
  const { idiv, rnd } = LK;
  const U = LK.usable = {
    isForOpponent: i => (i.scope >= 1 && i.scope <= 6) || i.scope === 14,
    isForFriend: i => (i.scope >= 7 && i.scope <= 13) || i.scope === 14,
    isForOne: i => [1, 3, 7, 9, 11, 12].includes(i.scope),
    isForAll: i => [2, 8, 10, 13, 14].includes(i.scope),
    isForRandom: i => i.scope >= 3 && i.scope <= 6,
    isForUser: i => i.scope === 11,
    isForDeadFriend: i => i.scope === 9 || i.scope === 10,
    needsTargetSelection: i => [1, 7, 9, 12].includes(i.scope),
    isBattleUsable: i => i.occasion === 0 || i.occasion === 1,
    isMenuUsable: i => i.occasion === 0 || i.occasion === 2,
  };
  const newResult = () => ({ used: false, missed: false, evaded: false, physical: false, drain: false, critical: false, success: false, hpAffected: false,
    hpDamage: 0, mpDamage: 0, tpDamage: 0, addedStates: [], removedStates: [], addedBuffs: [], addedDebuffs: [], removedBuffs: [],
    get isHit() { return this.used && !this.missed && !this.evaded; } });
  LK.newResult = newResult;

  class GameBattler {
    constructor(project) {
      this.project = project; this.hp = 1; this.mp = 0; this.tp = 0; this.states = []; this.stateTurns = {};
      this.buffs = [0, 0, 0, 0, 0, 0, 0, 0]; this.buffTurns = [0, 0, 0, 0, 0, 0, 0, 0]; this.paramPlusExtra = [0, 0, 0, 0, 0, 0, 0, 0];
      this.result = newResult(); this.actions = []; this.speed = 0; this.hidden = false; this.actionState = ""; this.rng = new LK.SystemRandom();
    }
    get name() { return ""; }
    get isActor() { return false; }
    paramBase() { return 1; }
    paramPlus(id) { return this.paramPlusExtra[id]; }
    paramMax(id) { return id === 0 ? 999999 : 9999; }
    ownTraits() { return []; }
    allTraits() { const out = this.ownTraits().slice(); for (const s of this.states) { const st = this.project.state(s); if (st) out.push(...st.traits); } return out; }
    traits(code) { return this.allTraits().filter(t => t.code === code); }
    traitsWith(code, id) { return this.allTraits().filter(t => t.code === code && t.dataId === id); }
    traitsPi(code, id) { return this.traitsWith(code, id).reduce((a, t) => a * t.value, 1); }
    traitsSum(code, id) { return this.traitsWith(code, id).reduce((a, t) => a + t.value, 0); }
    traitsSumAll(code) { return this.traits(code).reduce((a, t) => a + t.value, 0); }
    traitsSet(code) { return this.traits(code).map(t => t.dataId); }
    param(id) {
      const rate = this.traitsPi(21, id) * (this.buffs[id] * 0.25 + 1);
      const val = (this.paramBase(id) + this.paramPlus(id)) * rate;
      return rnd(Math.max(id === 0 ? 1 : 0, Math.min(this.paramMax(id), val)));
    }
    get mhp() { return this.param(0); } get mmp() { return this.param(1); } get atk() { return this.param(2); } get def() { return this.param(3); }
    get mat() { return this.param(4); } get mdf() { return this.param(5); } get agi() { return this.param(6); } get luk() { return this.param(7); }
    xparam(id) { return this.traitsSum(22, id); }
    sparam(id) { return this.traitsPi(23, id); }
    get hit() { return this.xparam(0); } get eva() { return this.xparam(1); } get cri() { return this.xparam(2); } get cev() { return this.xparam(3); } get mev() { return this.xparam(4); }
    get hrg() { return this.xparam(7); } get mrg() { return this.xparam(8); } get trg() { return this.xparam(9); }
    get grd() { return this.sparam(1); } get rec() { return this.sparam(2); } get pha() { return this.sparam(3); } get mcr() { return this.sparam(4); } get tcr() { return this.sparam(5); }
    get pdr() { return this.sparam(6); } get mdr() { return this.sparam(7); } get fdr() { return this.sparam(8); } get exr() { return this.sparam(9); }
    get maxTp() { return 100; }
    get hpRate() { const m = this.mhp; return m > 0 ? this.hp / m : 0; }
    get mpRate() { const m = this.mmp; return m > 0 ? this.mp / m : 0; }
    elementRate(e) { return this.traitsPi(11, e); }
    stateRate(s) { return this.traitsPi(13, s); }
    get stateResistSet() { return this.traitsSet(14); }
    get attackElements() { return this.traitsSet(31); }
    get attackStates() { return this.traits(32).map(t => [t.dataId, t.value]); }
    get attackSpeed() { return Math.trunc(this.traitsSumAll(33)); }
    get attackTimesAdd() { return Math.max(Math.trunc(this.traitsSumAll(34)), 0); }
    get attackSkill() { const t = this.traits(35); return t.length ? t[t.length - 1].dataId : 1; }
    specialFlag(id) { return this.allTraits().some(t => t.code === 62 && t.dataId === id); }
    get isGuarding() { return this.specialFlag(1) && this.canMove; }
    get isAutoBattle() { return this.specialFlag(0); }
    get preservesTp() { return this.specialFlag(3); }
    get actionPlusSet() { return this.traits(61).map(t => t.value); }
    get isDead() { return this.states.includes(1); }
    get isAlive() { return !this.isDead && !this.hidden; }
    get isAppeared() { return !this.hidden; }
    isStateAffected(id) { return this.states.includes(id); }
    get restriction() { let r = 0; for (const s of this.states) { const st = this.project.state(s); if (st && st.restriction > r) r = st.restriction; } return r; }
    get canMove() { return this.isAppeared && !this.isDead && this.restriction < 4; }
    get canInput() { return this.isAppeared && !this.isDead && this.restriction === 0 && !this.isAutoBattle && this.isActor; }
    get isConfused() { return this.isAppeared && this.restriction >= 1 && this.restriction <= 3; }
    get sortedStates() { return this.states.map(s => this.project.state(s)).filter(s => s).sort((a, b) => b.priority - a.priority); }
    setHp(val) { this.hp = val; this.refresh(); }
    setMp(val) { this.mp = val; this.refresh(); }
    setTp(val) { this.tp = Math.max(0, Math.min(this.maxTp, val)); }
    gainHp(val) { this.result.hpDamage = -val; this.result.hpAffected = true; this.setHp(this.hp + val); }
    gainMp(val) { this.result.mpDamage = -val; this.setMp(this.mp + val); }
    gainTp(val) { this.result.tpDamage = -val; this.setTp(this.tp + val); }
    gainSilentTp(val) { this.setTp(this.tp + val); }
    refresh() {
      this.hp = Math.max(0, Math.min(this.mhp, this.hp)); this.mp = Math.max(0, Math.min(this.mmp, this.mp)); this.tp = Math.max(0, Math.min(this.maxTp, this.tp));
      for (const s of this.stateResistSet) if (this.isStateAffected(s)) this.eraseState(s);
      if (this.hp === 0) this.addState(1); else this.removeState(1);
    }
    isStateAddable(id) { if (!this.project.state(id) || this.stateResistSet.includes(id)) return false; if (id !== 1 && this.isDead) return false; return true; }
    addState(id) {
      if (!this.isStateAddable(id)) return;
      if (!this.isStateAffected(id)) {
        if (id === 1) this.die();
        this.states.push(id);
        const s = this.project.state(id);
        if (s && s.restriction > 0) { this.actions = []; for (const st of this.states.slice()) { const sd = this.project.state(st); if (sd && sd.removeByRestriction) this.eraseState(st); } }
        this.refreshAfterStateChange();
      }
      const s = this.project.state(id);
      if (s) this.stateTurns[id] = s.minTurns + this.rng.next(Math.max(0, s.maxTurns - s.minTurns) + 1);
      this.result.addedStates.push(id);
    }
    removeState(id) {
      if (!this.isStateAffected(id)) return;
      if (id === 1) this.revive();
      this.eraseState(id); this.refreshAfterStateChange(); this.result.removedStates.push(id);
    }
    eraseState(id) { this.states = this.states.filter(s => s !== id); delete this.stateTurns[id]; }
    refreshAfterStateChange() { this.hp = Math.max(0, Math.min(this.mhp, this.hp)); this.mp = Math.max(0, Math.min(this.mmp, this.mp)); }
    die() { this.hp = 0; this.states = []; this.stateTurns = {}; this.buffs = [0, 0, 0, 0, 0, 0, 0, 0]; this.buffTurns = [0, 0, 0, 0, 0, 0, 0, 0]; }
    revive() { if (this.hp === 0) this.hp = 1; }
    recoverAll() { this.states = []; this.stateTurns = {}; this.hp = this.mhp; this.mp = this.mmp; }
    removeStatesAuto(timing) { for (const s of this.sortedStates) if ((this.stateTurns[s.id] || 0) <= 0 && s.autoRemovalTiming === timing) this.removeState(s.id); }
    removeStatesByDamage() { for (const s of this.sortedStates) if (s.removeByDamage && this.rng.next(100) < s.chanceByDamage) this.removeState(s.id); }
    removeBattleStates() { for (const s of this.sortedStates) if (s.removeAtBattleEnd) this.removeState(s.id); }
    updateStateTurns() { for (const id of this.states) if ((this.stateTurns[id] || 0) > 0) this.stateTurns[id]--; }
    addBuff(id, turns) { if (!this.isAlive) return; if (this.buffs[id] < 2) this.buffs[id]++; this.buffTurns[id] = Math.max(this.buffTurns[id], turns); this.result.addedBuffs.push(id); this.refresh(); }
    addDebuff(id, turns) { if (!this.isAlive) return; if (this.buffs[id] > -2) this.buffs[id]--; this.buffTurns[id] = Math.max(this.buffTurns[id], turns); this.result.addedDebuffs.push(id); this.refresh(); }
    removeBuff(id) { if (this.buffs[id] === 0) return; this.buffs[id] = 0; this.buffTurns[id] = 0; this.result.removedBuffs.push(id); this.refresh(); }
    updateBuffTurns() { for (let i = 0; i < 8; i++) if (this.buffTurns[i] > 0) { this.buffTurns[i]--; if (this.buffTurns[i] === 0) this.removeBuff(i); } }
    skillMpCost(s) { return Math.floor(s.mpCost * this.mcr); }
    canPaySkillCost(s) { return this.tp >= s.tpCost && this.mp >= this.skillMpCost(s); }
    paySkillCost(s) { this.mp -= this.skillMpCost(s); this.tp -= s.tpCost; }
    isSkillSealed(id) { return this.traitsSet(44).includes(id); }
    isSkillTypeSealed(id) { return this.traitsSet(42).includes(id); }
    canUse(item, inBattle) {
      if (!this.canMove && inBattle) return false;
      if (inBattle ? !U.isBattleUsable(item) : !U.isMenuUsable(item)) return false;
      if (item.isSkill) return this.canPaySkillCost(item) && !this.isSkillSealed(item.id) && !this.isSkillTypeSealed(item.stypeId);
      return true;
    }
    onBattleStart() { if (!this.preservesTp) this.tp = this.rng.next(25); this.actionState = "undecided"; }
    onBattleEnd() { this.result = newResult(); this.removeBattleStates(); this.buffs = [0, 0, 0, 0, 0, 0, 0, 0]; this.buffTurns = [0, 0, 0, 0, 0, 0, 0, 0]; this.actions = []; if (!this.preservesTp) this.tp = 0; }
    onTurnEnd(slipDeath) {
      this.result = newResult();
      if (this.isAlive) {
        const minRecover = slipDeath ? -this.hp : -(this.hp - 1);
        const hpv = Math.max(Math.floor(this.mhp * this.hrg), minRecover);
        if (hpv !== 0) this.gainHp(hpv);
        const mpv = Math.floor(this.mmp * this.mrg);
        if (mpv !== 0) this.gainMp(mpv);
        this.gainSilentTp(Math.floor(100 * this.trg));
      }
      this.updateStateTurns(); this.updateBuffTurns(); this.removeStatesAuto(2);
    }
    onDamage(value) { this.removeStatesByDamage(); const rate = value / Math.max(this.mhp, 1); this.gainSilentTp(Math.floor(50 * rate * this.tcr)); }
    get numActions() { return this.actionPlusSet.reduce((r, p) => (this.rng.next(1000000) / 1000000 < p ? r + 1 : r), 1); }
    get stateMotionIndex() { const s = this.sortedStates[0]; return s ? s.motion : 0; }
    get stateOverlayIndex() { const s = this.sortedStates[0]; return s ? s.overlay : 0; }
    get isDying() { return this.isAlive && this.hp < this.mhp / 4; }
    get isInputting() { return this.actionState === "inputting"; }
    get isActing() { return this.actionState === "acting"; }
    get isUndecided() { return this.actionState === "undecided"; }
    get isChanting() { return this.actionState === "waiting" && this.actions.some(a => a.isMagicSkill); }
    get isGuardWaiting() { return this.actionState === "waiting" && this.actions.some(a => a.isGuard); }
  }
  LK.GameBattler = GameBattler;

  class GameActor extends GameBattler {
    constructor(project, actorId, rng, save) {
      super(project);
      this.actorId = actorId;
      if (rng) this.rng = rng;
      if (save) {
        Object.assign(this, { actorName: save.name, nickname: save.nickname, classId: save.classId, level: save.level, exp: Object.assign({}, save.exp),
          learnedSkills: save.skills.slice(), equips: save.equips.slice(), hp: save.hp, mp: save.mp, tp: save.tp, states: save.states.slice(),
          stateTurns: Object.assign({}, save.stateTurns), paramPlusExtra: save.paramPlus.slice() });
        return;
      }
      const a = project.actor(actorId);
      this.actorName = a ? a.name : "Actor " + actorId; this.nickname = a ? a.nickname : ""; this.classId = a ? a.classId : 1;
      this.level = Math.max(1, a ? a.initialLevel : 1);
      this.equips = (a ? a.equips : []).concat([0, 0, 0, 0, 0]).slice(0, 5);
      this.exp = {}; this.learnedSkills = [];
      this.exp[this.classId] = this.expForLevel(this.level);
      const c = project.classData(this.classId);
      for (const l of c ? c.learnings : []) if (l.level <= this.level) this.learnSkill(l.skillId);
      for (let i = 0; i < this.equips.length; i++) if (this.equips[i] > 0 && !this.canEquip(i, this.equips[i])) this.equips[i] = 0;
      this.recoverAll();
    }
    static fromSave(project, s) { return new GameActor(project, s.actorId, null, s); }
    get save() {
      return { actorId: this.actorId, name: this.actorName, nickname: this.nickname, classId: this.classId, level: this.level, exp: this.exp, hp: this.hp, mp: this.mp,
        tp: this.tp, states: this.states, stateTurns: this.stateTurns, skills: this.learnedSkills, equips: this.equips, paramPlus: this.paramPlusExtra };
    }
    get name() { return this.actorName; }
    get isActor() { return true; }
    get data() { return this.project.actor(this.actorId); }
    get currentClass() { return this.project.classData(this.classId); }
    get maxLevel() { return this.data ? this.data.maxLevel : 99; }
    get battlerName() { return this.data ? this.data.battlerName : ""; }
    get attackAnimationId() { const w = this.equips[0] > 0 ? this.project.weapon(this.equips[0]) : null; return w ? w.animationId : 1; }
    get attackMotion() { const w = this.equips[0] > 0 ? this.project.weapon(this.equips[0]) : null; return this.project.system.attackMotions[w ? w.wtypeId : 0] || null; }
    paramBase(id) {
      const c = this.currentClass;
      if (!c || id >= c.params.length || !c.params[id].length) return id === 0 ? 100 : 10;
      return c.params[id][Math.min(this.level, c.params[id].length - 1)];
    }
    paramPlus(id) { return super.paramPlus(id) + this.equipItems.reduce((s, e) => s + e.params[id], 0); }
    paramMax(id) { return id === 0 ? 9999 : 999; }
    ownTraits() { const d = this.data, c = this.currentClass; return (d ? d.traits : []).concat(c ? c.traits : [], ...this.equipItems.map(e => e.traits)); }
    get equipItems() { return this.equips.map((id, i) => (id > 0 ? (i === 0 ? this.project.weapon(id) : this.project.armor(id)) : null)).filter(x => x); }
    canEquip(slot, id) {
      if (slot === 0) { const w = this.project.weapon(id); return !!w && this.traitsSet(51).includes(w.wtypeId) && !this.traitsSet(54).includes(1); }
      const a = this.project.armor(id); if (!a || a.etypeId !== [1, 2, 3, 4, 5][slot]) return false;
      return this.traitsSet(52).includes(a.atypeId) && !this.traitsSet(54).includes(a.etypeId);
    }
    isEquipLocked(slot) { return this.traitsSet(53).includes([1, 2, 3, 4, 5][slot]); }
    expForLevel(lv) {
      const c = this.currentClass, p = c ? c.expParams : [30, 20, 30, 30];
      const basis = p[0], extra = p[1], accA = p[2], accB = Math.max(p[3], 1), l = lv;
      return rnd(basis * Math.pow(l - 1, 0.9 + accA / 250) * l * (l + 1) / (6 + Math.pow(l, 2) / 50 / accB) + (l - 1) * extra);
    }
    get currentExp() { return this.exp[this.classId] || 0; }
    get nextLevelExp() { return this.expForLevel(this.level + 1); }
    get expToNext() { return this.level >= this.maxLevel ? 0 : this.nextLevelExp - this.currentExp; }
    changeExp(value) {
      const lastLevel = this.level, last = new Set(this.learnedSkills);
      this.exp[this.classId] = Math.max(value, 0);
      while (this.level < this.maxLevel && this.currentExp >= this.nextLevelExp) this.levelUp();
      while (this.level > 1 && this.currentExp < this.expForLevel(this.level)) this.level--;
      this.refresh();
      return { levels: this.level - lastLevel, newSkills: this.learnedSkills.filter(s => !last.has(s)) };
    }
    gainExp(v) { return this.changeExp(this.currentExp + rnd(v * this.exr)); }
    levelUp() { this.level++; const c = this.currentClass; for (const l of c ? c.learnings : []) if (l.level === this.level) this.learnSkill(l.skillId); }
    changeLevel(lv) { this.changeExp(this.expForLevel(Math.max(1, Math.min(this.maxLevel, lv)))); }
    learnSkill(id) { if (!this.learnedSkills.includes(id)) { this.learnedSkills.push(id); this.learnedSkills.sort((a, b) => a - b); } }
    forgetSkill(id) { this.learnedSkills = this.learnedSkills.filter(s => s !== id); }
    get skills() { return [...new Set(this.learnedSkills.concat(this.traitsSet(43)))].sort((a, b) => a - b).map(id => this.project.skill(id)).filter(s => s); }
    get addedSkillTypes() { return [...new Set(this.traitsSet(41))].sort((a, b) => a - b); }
    setName(n) { this.actorName = n; }
    changeClass(id, keepExp) {
      const e = this.currentExp; this.classId = id;
      if (keepExp) this.exp[id] = e; else if (this.exp[id] === undefined) this.exp[id] = 0;
      this.changeExp(this.exp[id] || 0);
    }
    changeEquip(slot, id) { const old = this.equips[slot]; this.equips[slot] = id; this.refresh(); return old; }
  }
  LK.GameActor = GameActor;

  class GameEnemy extends GameBattler {
    constructor(project, enemyId, index, x, y, hidden) {
      super(project);
      this.enemyId = enemyId; this.index = index; this.screenX = x; this.screenY = y; this.letter = ""; this.turnCount = 0;
      this.hidden = hidden; this.recoverAll();
    }
    get data() { return this.project.enemy(this.enemyId); }
    get name() { return (this.data ? this.data.name : "Enemy") + this.letter; }
    get battlerName() { return this.data ? this.data.battlerName : ""; }
    get battlerHue() { return this.data ? this.data.battlerHue : 0; }
    get collapseType() { const t = this.traits(63).map(t => t.dataId); return t.length ? Math.max(...t) : 0; }
    paramBase(id) { const d = this.data; return d ? (id < d.params.length ? d.params[id] : 1) : 1; }
    ownTraits() { return this.data ? this.data.traits : []; }
    get exp() { return this.data ? this.data.exp : 0; }
    get gold() { return this.data ? this.data.gold : 0; }
    appear() { this.hidden = false; }
    transform(id) {
      const e = new GameEnemy(this.project, id, this.index, this.screenX, this.screenY, false);
      e.rng = this.rng; e.letter = this.letter; e.hp = Math.min(this.hp, e.mhp); e.mp = Math.min(this.mp, e.mmp);
      return e;
    }
    meetsCondition(a, partyLevel, switches) {
      const p1 = a.conditionParam1, p2 = a.conditionParam2;
      switch (a.conditionType) {
        case 1: { const n = this.turnCount; return p2 === 0 ? n === p1 : (n > 0 && n >= p1 && Math.trunc(n) % Math.trunc(p2) === Math.trunc(p1) % Math.trunc(p2)); }
        case 2: return this.hpRate >= p1 && this.hpRate <= p2;
        case 3: return this.mpRate >= p1 && this.mpRate <= p2;
        case 4: return this.isStateAffected(Math.trunc(p1));
        case 5: return partyLevel >= p1;
        case 6: return switches(Math.trunc(p1));
        default: return true;
      }
    }
    makeActions(rng, partyLevel, switches) {
      this.actions = [];
      if (!this.canMove) return;
      const valid = (this.data ? this.data.actions : []).filter(a => { if (!this.meetsCondition(a, partyLevel, switches)) return false; const s = this.project.skill(a.skillId); return !!s && this.canUse(s, true); });
      if (!valid.length) return;
      const maxRating = Math.max(...valid.map(a => a.rating)), zero = maxRating - 3;
      const pool = valid.filter(a => a.rating > zero);
      const n = this.numActions;
      for (let k = 0; k < n; k++) {
        const sum = pool.reduce((s, a) => s + a.rating - zero, 0);
        let val = rng.next(Math.max(sum, 1)), chosen = pool[0];
        for (const a of pool) { val -= a.rating - zero; if (val < 0) { chosen = a; break; } }
        const act = new GameAction(this, chosen.skillId, 0); act.targetIndex = -1; this.actions.push(act);
      }
    }
  }
  LK.GameEnemy = GameEnemy;

  class GameAction {
    constructor(subject, skillId, itemId) { this.subject = subject; this.skillId = skillId || 0; this.itemId = itemId || 0; this.targetIndex = -1; this.forcing = false; }
    get project() { return this.subject.project; }
    get item() { return this.skillId > 0 ? this.project.skill(this.skillId) : this.project.item(this.itemId); }
    get isSkill() { return this.skillId > 0; }
    get isItem() { return this.itemId > 0; }
    get isAttack() { return this.skillId === this.subject.attackSkill; }
    get isGuard() { return this.skillId === 2; }
    get isMagicSkill() { if (!this.isSkill) return false; const s = this.project.skill(this.skillId); return this.project.system.magicSkills.includes(s ? s.stypeId : -1); }
    speed(rng) {
      const agi = this.subject.agi;
      let s = agi + rng.next(Math.max(1, 5 + idiv(agi, 4)));
      const it = this.item; s += it ? it.speed : 0;
      if (this.isAttack) s += this.subject.attackSpeed;
      return s;
    }
    get numRepeats() { const it = this.item; let n = it ? it.repeats : 1; if (this.isAttack) n += this.subject.attackTimesAdd; return Math.max(n, 1); }
    makeTargets(friends, opponents, rng) {
      const it = this.item; if (!it) return [];
      let targets = [];
      const alive = u => u.filter(b => b.isAlive);
      if (!this.forcing && this.subject.isConfused) {
        let pool;
        switch (this.subject.restriction) { case 1: pool = opponents; break; case 3: pool = friends; break; default: pool = rng.next(2) === 0 ? opponents : friends; }
        const t = this.randomTarget(alive(pool), rng); if (t) targets = [t];
      } else if (it.scope === 14) targets = alive(opponents).concat(alive(friends));
      else if (U.isForOpponent(it)) {
        const al = alive(opponents);
        if (U.isForRandom(it)) { for (let i = 0; i < it.scope - 2; i++) { const t = this.randomTarget(al, rng); if (t) targets.push(t); } }
        else if (U.isForAll(it)) targets = al;
        else { const t = this.smoothTarget(opponents, this.targetIndex, rng); if (t) targets = [t]; }
      } else if (U.isForFriend(it)) {
        if (U.isForUser(it)) targets = [this.subject];
        else if (U.isForDeadFriend(it)) {
          const dead = friends.filter(b => b.isDead);
          if (U.isForAll(it)) targets = dead;
          else if (this.targetIndex >= 0 && this.targetIndex < friends.length && friends[this.targetIndex].isDead) targets = [friends[this.targetIndex]];
          else if (dead.length) targets = [dead[0]];
        } else if (it.scope === 12 || it.scope === 13) {
          targets = U.isForAll(it) ? friends : (this.targetIndex >= 0 && this.targetIndex < friends.length ? [friends[this.targetIndex]] : [this.subject]);
        } else if (U.isForAll(it)) targets = alive(friends);
        else { const t = this.smoothTarget(friends, this.targetIndex, rng); if (t) targets = [t]; }
      }
      const out = [];
      for (const t of targets) for (let i = 0; i < this.numRepeats; i++) out.push(t);
      return out;
    }
    randomTarget(al, rng) { return al.length ? al[rng.next(al.length)] : null; }
    smoothTarget(unit, index, rng) {
      if (index >= 0 && index < unit.length && unit[index].isAlive) return unit[index];
      if (index >= 0) return unit.find(b => b.isAlive) || null;
      return this.randomTarget(unit.filter(b => b.isAlive), rng);
    }
    static rand(rng) { return rng.next(1000000) / 1000000; }
    apply(target, rng, formula, onCommonEvent) {
      const it = this.item; if (!it) return;
      this.subject.result = newResult(); target.result = newResult();
      const r = newResult();
      r.used = this.testApply(target, it);
      const physical = it.hitType === 1, magical = it.hitType === 2;
      const hitRate = physical ? it.successRate * 0.01 * this.subject.hit : it.successRate * 0.01;
      r.missed = r.used && GameAction.rand(rng) >= hitRate;
      const evaRate = physical ? target.eva : magical ? target.mev : 0;
      r.evaded = !r.missed && GameAction.rand(rng) < evaRate;
      r.physical = physical; r.drain = it.damage.type === 5 || it.damage.type === 6;
      target.result = r;
      if (!target.result.isHit) return;
      if (it.damage.type > 0) {
        const criRate = it.damage.critical ? this.subject.cri * (1 - target.cev) : 0;
        target.result.critical = GameAction.rand(rng) < criRate;
        const value = this.makeDamageValue(target, it, target.result.critical, rng, formula);
        this.executeDamage(target, it, value);
      }
      for (const e of it.effects) this.applyEffect(target, it, e, rng, onCommonEvent);
      this.subject.gainSilentTp(Math.floor(it.tpGain * this.subject.tcr));
    }
    testApply(target, it) {
      if (U.isForDeadFriend(it) !== target.isDead) return false;
      if (it.damage.type > 0 || it.scope === 0 || !U.isForFriend(it)) return true;
      const ef = it.effects;
      if (ef.some(e => e.code === 11) && target.hp < target.mhp) return true;
      if (ef.some(e => e.code === 12) && target.mp < target.mmp) return true;
      if (ef.some(e => e.code === 21 && !target.isStateAffected(e.dataId))) return true;
      if (ef.some(e => e.code === 22 && target.isStateAffected(e.dataId))) return true;
      if (ef.some(e => [13, 31, 32, 42, 43, 44, 41].includes(e.code))) return true;
      return ef.length === 0;
    }
    makeDamageValue(target, it, critical, rng, formula) {
      const sign = [3, 4].includes(it.damage.type) ? -1 : 1;
      let base = Math.max(formula(it.damage.formula, this.subject, target), 0) * sign;
      if (Number.isNaN(base)) base = 0;
      let value = base * this.elementRate(target, it);
      if (it.hitType === 1) value *= target.pdr;
      if (it.hitType === 2) value *= target.mdr;
      if (base < 0) value *= target.rec;
      if (critical) value *= 3;
      const amp = Math.floor(Math.max(Math.abs(value) * it.damage.variance / 100, 0));
      const vv = rng.next(amp + 1) + rng.next(amp + 1) - amp;
      value = value >= 0 ? value + vv : value - vv;
      if (value > 0 && target.isGuarding) value /= 2 * target.grd;
      return rnd(value);
    }
    elementRate(target, it) {
      if (it.damage.elementId < 0) { const els = this.subject.attackElements; return els.length ? Math.max(...els.map(e => target.elementRate(e))) : 1; }
      return target.elementRate(it.damage.elementId);
    }
    executeDamage(target, it, v) {
      let value = v;
      if (value === 0) target.result.critical = false;
      switch (it.damage.type) {
        case 1: case 3: case 5:
          if (it.damage.type === 5) value = Math.min(target.hp, value);
          target.result.success = true; target.gainHp(-value);
          if (value > 0) target.onDamage(value);
          if (it.damage.type === 5) { this.subject.gainHp(value); this.subject.result = newResult(); }
          break;
        case 2: case 4: case 6:
          if (it.damage.type !== 4) value = Math.min(target.mp, value);
          if (value !== 0) target.result.success = true;
          target.gainMp(-value);
          if (it.damage.type === 6) { this.subject.gainMp(value); this.subject.result = newResult(); }
          break;
      }
    }
    applyEffect(target, it, e, rng, onCommonEvent) {
      const R = () => GameAction.rand(rng);
      switch (e.code) {
        case 11: { let v = (target.mhp * e.value1 + e.value2) * target.rec; if (!it.isSkill) v *= this.subject.pha; const n = Math.floor(v); if (n !== 0) { target.gainHp(n); target.result.success = true; } break; }
        case 12: { let v = (target.mmp * e.value1 + e.value2) * target.rec; if (!it.isSkill) v *= this.subject.pha; const n = Math.floor(v); if (n !== 0) { target.gainMp(n); target.result.success = true; } break; }
        case 13: { const n = Math.floor(e.value1); if (n !== 0) { target.gainTp(n); target.result.success = true; } break; }
        case 21: {
          const luk = Math.max(1 + (this.subject.luk - target.luk) * 0.001, 0);
          if (e.dataId === 0) {
            for (const [sid, rate] of this.subject.attackStates) {
              let chance = e.value1 * target.stateRate(sid) * rate * luk;
              if (it.hitType === 0) chance = e.value1;
              if (R() < chance) { target.addState(sid); target.result.success = true; }
            }
          } else {
            let chance = e.value1;
            if (it.hitType !== 0) chance *= target.stateRate(e.dataId) * luk;
            if (R() < chance) { target.addState(e.dataId); target.result.success = true; }
          }
          break;
        }
        case 22: if (R() < e.value1) { target.removeState(e.dataId); target.result.success = true; } break;
        case 31: target.addBuff(e.dataId, Math.trunc(e.value1)); target.result.success = true; break;
        case 32: { const chance = target.traitsPi(12, e.dataId) * Math.max(1 + (this.subject.luk - target.luk) * 0.001, 0); if (R() < chance) { target.addDebuff(e.dataId, Math.trunc(e.value1)); target.result.success = true; } break; }
        case 33: if (target.buffs[e.dataId] > 0) { target.removeBuff(e.dataId); target.result.success = true; } break;
        case 34: if (target.buffs[e.dataId] < 0) { target.removeBuff(e.dataId); target.result.success = true; } break;
        case 42: target.paramPlusExtra[e.dataId] += Math.floor(e.value1); target.refresh(); target.result.success = true; break;
        case 43: if (target.isActor) { target.learnSkill(e.dataId); target.result.success = true; } break;
        case 44: onCommonEvent(e.dataId); break;
      }
    }
  }
  LK.GameAction = GameAction;

  // ---------- BattleManager ----------
  const Phase = { start: "start", input: "input", turn: "turn", turnEnd: "turnEnd", ending: "ending", done: "done" };
  class BattleManager {
    constructor(world, troopId, canEscape, canLose) {
      Object.assign(this, { world, troopId, canEscape, canLose, enemies: [], phase: Phase.start, outcome: null, log: [], cues: [], turnCount: 0,
        preemptive: false, surprise: false, inputIndex: null, waitingForPartyCommand: false, rewards: { exp: 0, gold: 0, items: [] },
        battleback1: "", battleback2: "", escaped: false, frame: 0, animationBusyUntil: 0, queue: [], waitCount: 0, cueCounter: 0,
        actionBattlers: [], subject: null, escapeRatio: 0.5, interpreter: new LK.Interpreter(0), pageDone: [], turnEndingCheck: false, onEnd: null, collapsed: new Set() });
      const troop = world.project.troop(troopId);
      (troop ? troop.members : []).forEach((m, i) => { if (world.project.enemy(m.enemyId)) this.enemies.push(new GameEnemy(world.project, m.enemyId, i, m.x, m.y, m.hidden)); });
      for (const e of this.enemies) e.rng = world.rng;
      const names = this.enemies.map(e => (e.data ? e.data.name : ""));
      for (const name of new Set(names)) if (names.filter(n => n === name).length > 1) { let n = 0; for (const e of this.enemies) if (e.data && e.data.name === name) { e.letter = " " + String.fromCharCode(65 + n); n++; } }
      this.pageDone = new Array(troop ? troop.pages.length : 0).fill(false);
      const m = this.members;
      const partyAgi = m.length ? idiv(m.reduce((s, a) => s + a.agi, 0), m.length) : 1;
      const troopAgi = this.enemies.length ? idiv(this.enemies.reduce((s, e) => s + e.agi, 0), Math.max(1, this.enemies.length)) : 1;
      this.escapeRatio = 0.5 * partyAgi / Math.max(1, troopAgi);
    }
    get members() { return this.world.partyMembers; }
    get terms() { return this.world.project.system.terms; }
    get sideView() { return this.world.project.system.optSideView; }
    get isBusy() { return this.queue.length > 0 || this.waitCount > 0 || this.interpreter.isRunning || !!this.world.message || this.frame < this.animationBusyUntil; }
    get inputActor() { return this.inputIndex !== null && this.inputIndex < this.members.length ? this.members[this.inputIndex] : null; }
    get isFinished() { return this.phase === Phase.done; }
    msg(k, ...a) { return LK.termMessage(this.terms, k, ...a); }
    start() {
      for (const b of this.members.concat(this.enemies)) b.onBattleStart(this.preemptive);
      for (const e of this.enemies) if (!e.hidden) this.push({ t: "log", s: this.msg("emerge", e.name) });
      if (this.preemptive) this.push({ t: "log", s: this.msg("preemptive", this.partyName) });
      if (this.surprise) this.push({ t: "log", s: this.msg("surprise", this.partyName) });
      this.push({ t: "wait", n: 20 }, { t: "clearLog" });
      this.world.audio.playSe(this.sound(7));
    }
    get partyName() { const m = this.members[0]; return m ? this.msg("partyName", m.name) : "Party"; }
    sound(i) { return this.world.project.system.sounds[i] || { name: "", volume: 90, pitch: 100, pan: 0 }; }
    update() {
      this.frame++;
      if (this.waitCount > 0) { this.waitCount--; return; }
      if (this.world.message) return;
      if (this.interpreter.isRunning) { this.interpreter.update(this.world); if (this.interpreter.isRunning || this.world.message) return; }
      while (this.queue.length) {
        const s = this.queue.shift();
        switch (s.t) {
          case "log": this.log.push(s.s); if (this.log.length > 6) this.log.shift(); this.waitCount = 16; return;
          case "clearLog": this.log = []; break;
          case "wait": this.waitCount = s.n; return;
          case "cue": this.addCue(s.k, s.targets); break;
          case "waitForAnimation": if (this.frame < this.animationBusyUntil) { this.waitCount = this.animationBusyUntil - this.frame - 1; return; } break;
          case "se": if (s.f) this.world.audio.playSe(s.f); break;
          case "run": s.f(); break;
        }
      }
      if (this.phase !== Phase.ending && this.phase !== Phase.done) { if (this.setupBattleEvent()) return; if (this.checkBattleEnd()) return; }
      switch (this.phase) {
        case Phase.start: this.start(); this.phase = Phase.input; if (this.surprise) { this.surprise = false; this.startTurn(); } else this.startInput(); break;
        case Phase.turn: this.processTurn(); break;
        case Phase.turnEnd: this.endTurn(); break;
        case Phase.ending: this.phase = Phase.done; this.finish(); break;
      }
    }
    push(...steps) { this.queue.push(...steps); }
    cue(kind, target) { return { t: "cue", k: kind, targets: target === null || target === undefined ? [] : [target] }; }
    addCue(k, targets) {
      this.cueCounter++;
      this.cues.push({ id: this.cueCounter, kind: k, target: targets.length ? targets[0] : null, targets });
      if (this.cues.length > 60) this.cues.splice(0, 20);
      if (k.t === "animation") { const a = this.world.project.animation(k.id); if (a) this.animationBusyUntil = Math.max(this.animationBusyUntil, this.frame + k.delay + a.playFrames); }
    }
    startInput() {
      this.phase = Phase.input;
      for (const e of this.enemies) if (e.isAlive) { e.turnCount = this.turnCount + 1; e.makeActions(this.world.rng, Math.max(1, ...this.members.map(a => a.level)), id => this.world.state.switchValue(id)); }
      for (const a of this.members) { a.actions = []; a.actionState = a.canInput ? "undecided" : "waiting"; }
      if (this.preemptive) this.preemptive = false;
      this.waitingForPartyCommand = this.members.some(a => a.canInput);
      this.inputIndex = null;
      if (!this.waitingForPartyCommand) this.startTurn();
    }
    commandFight() { if (this.phase !== Phase.input || !this.waitingForPartyCommand) return; this.waitingForPartyCommand = false; this.selectNextActor(-1); }
    commandEscape() {
      if (this.phase !== Phase.input || !this.waitingForPartyCommand || !this.canEscape) return;
      this.waitingForPartyCommand = false;
      this.world.audio.playSe(this.sound(8));
      this.push({ t: "log", s: this.msg("escapeStart", this.partyName) });
      const success = this.preemptive || this.world.rng.next(1000) / 1000 < this.escapeRatio;
      this.members.forEach((a, i) => { if (a.canMove) this.push(this.cue({ t: "motion", m: "escape" }, -(i + 1))); });
      if (success) { this.escaped = true; this.push({ t: "wait", n: 30 }, { t: "run", f: () => this.endBattle(1) }); }
      else { this.escapeRatio += 0.1; this.push({ t: "log", s: this.msg("escapeFailure") }, { t: "wait", n: 20 }, { t: "clearLog" }); for (const a of this.members) a.actions = []; this.startTurn(); }
    }
    selectNextActor(i) {
      let n = i + 1; const m = this.members;
      while (n < m.length && !m[n].canInput) n++;
      if (n < m.length) { this.inputIndex = n; m[n].actionState = "inputting"; } else { this.inputIndex = null; this.startTurn(); }
    }
    cancelInput() {
      if (this.phase !== Phase.input || this.inputIndex === null) return;
      const i = this.inputIndex, m = this.members; let n = i - 1;
      while (n >= 0 && !m[n].canInput) n--;
      m[i].actionState = "undecided";
      if (n >= 0) { m[n].actions = []; m[n].actionState = "inputting"; this.inputIndex = n; } else { this.inputIndex = null; this.waitingForPartyCommand = true; }
    }
    get currentInputActor() { return this.inputActor || this.members[0]; }
    commandAttack(target) { const a = this.currentInputActor; this.submit(new GameAction(a, a.attackSkill, 0), target); }
    commandGuard() { this.submit(new GameAction(this.currentInputActor, 2, 0), -1); }
    commandSkill(id, target) { this.submit(new GameAction(this.currentInputActor, id, 0), target); }
    commandItem(id, target) { this.submit(new GameAction(this.currentInputActor, 0, id), target); }
    submit(a, target) {
      if (this.phase !== Phase.input || this.inputIndex === null) return;
      const i = this.inputIndex, m = this.members;
      a.targetIndex = target; m[i].actions = [a];
      const n = Math.max(1, m[i].numActions);
      for (let k = 1; k < n; k++) { const x = new GameAction(a.subject, a.skillId, a.itemId); x.targetIndex = target; m[i].actions.push(x); }
      m[i].actionState = "waiting";
      this.selectNextActor(i);
    }
    usableSkills(a) { return a.skills.filter(s => a.addedSkillTypes.includes(s.stypeId) || s.stypeId === 0); }
    usableItems() { return LK.GameState.sortedKeys(this.world.state.items).map(id => this.world.project.item(id)).filter(it => it && U.isBattleUsable(it) && it.itypeId === 1); }
    startTurn() {
      this.phase = Phase.turn; this.turnCount++;
      const troop = this.world.project.troop(this.troopId);
      (troop ? troop.pages : []).forEach((p, i) => { if (p.span === 1) this.pageDone[i] = false; });
      for (const a of this.members) if (a.canMove && !a.actions.length) { const act = new GameAction(a, a.attackSkill, 0); act.targetIndex = -1; a.actions = [act]; }
      for (const a of this.members) if (a.actionState !== "waiting" && a.canMove) a.actionState = "waiting";
      this.actionBattlers = this.members.concat(this.enemies).filter(b => b.isAlive && b.actions.length);
      for (const b of this.actionBattlers) b.speed = Math.min(...b.actions.map(a => a.speed(this.world.rng)));
      this.actionBattlers = this.stableSortBySpeed(this.actionBattlers);
      this.subject = null;
    }
    /// Swift's sort isn't stable either; ties keep insertion order here, which matches it for the small arrays used.
    stableSortBySpeed(list) { return list.map((b, i) => [b, i]).sort((a, b) => b[0].speed - a[0].speed || a[1] - b[1]).map(x => x[0]); }
    processTurn() {
      if (!this.subject) {
        while (this.actionBattlers.length && !(this.actionBattlers[0].isAlive && this.actionBattlers[0].canMove && this.actionBattlers[0].actions.length)) this.actionBattlers.shift();
        if (!this.actionBattlers.length) { this.phase = Phase.turnEnd; this.turnEndingCheck = true; return; }
        this.subject = this.actionBattlers.shift();
      }
      const s = this.subject;
      const action = s.actions[0];
      if (!action) { s.result = newResult(); this.subject = null; return; }
      s.actions.shift();
      const last = !s.actions.length;
      this.perform(action);
      if (last) this.subject = null;
    }
    perform(action) {
      const s = action.subject, item = action.item, w = this.world;
      if (!item || !(s.canUse(item, true) || action.forcing)) return;
      if (item.isSkill) s.paySkillCost(item);
      if (!item.isSkill && item.consumable) w.state.gain(1, item.id, -1);
      const friends = s.isActor ? this.members : this.enemies, opponents = s.isActor ? this.enemies : this.members;
      const targets = action.makeTargets(friends, opponents, w.rng);
      if (!action.isGuard) s.actionState = "acting";
      if (!s.isActor) this.push(this.cue({ t: "effect", e: "whiten" }, s.index));
      if (this.sideView && s.isActor && !action.isGuard) this.push({ t: "wait", n: 12 });
      if (s.isActor) {
        const idx = this.memberIndex(s);
        if (idx !== null) {
          const t = -(idx + 1);
          this.push(this.cue({ t: "actorAct" }, idx));
          if (action.isAttack) {
            const m = s.attackMotion;
            if (m) { this.push(this.cue({ t: "motion", m: ["thrust", "swing", "missile"][m.type] || "thrust" }, t)); if (m.weaponImageId > 0) this.push(this.cue({ t: "weapon", w: m.weaponImageId }, t)); }
          } else if (action.isGuard) this.push(this.cue({ t: "motion", m: "guard" }, t));
          else if (action.isMagicSkill) this.push(this.cue({ t: "motion", m: "spell" }, t));
          else if (action.isSkill) this.push(this.cue({ t: "motion", m: "skill" }, t));
          else this.push(this.cue({ t: "motion", m: "item" }, t));
        }
      }
      const animated = this.showAnimation(s, targets, item.animationId);
      if (item.animationId < 0 && !s.isActor) this.push({ t: "se", f: this.sound(9) });
      else if (!animated && !action.isAttack) this.push({ t: "se", f: this.sound(item.isSkill ? 23 : 22) });
      this.push({ t: "log", s: this.actionMessage(s, item) });
      if (item.isSkill && item.message2) this.push({ t: "log", s: item.message2.split("%1").join(s.name).split("%2").join(item.name) });
      this.push({ t: "waitForAnimation" });
      for (const t of targets) {
        this.push({ t: "run", f: () => {
          action.apply(t, w.rng, (f, a, b) => w.script.evalFormula(f, a, b), id => w.reserveCommonEvent(id));
          this.queue.unshift(...this.resultSteps(t));
        } });
      }
      this.push({ t: "run", f: () => { s.removeStatesAuto(1); for (const e of this.enemies) if (e.isDead && !this.collapsed.has(e.index)) this.collapsed.add(e.index); } },
        { t: "wait", n: 12 }, { t: "clearLog" }, { t: "run", f: () => { if (!s.actions.length) s.actionState = "done"; } });
    }
    showAnimation(s, targets, id) { if (id < 0) return s.isActor ? this.showNormalAnimation(targets, s.attackAnimationId, false) : false; return this.showNormalAnimation(targets, id, false); }
    showNormalAnimation(targets, id, mirror) {
      const anim = this.world.project.animation(id);
      if (!anim || !targets.length) return false;
      const ids = targets.map(t => this.cueTarget(t)).filter(x => x !== null);
      const m = targets[0].isActor ? !mirror : mirror;
      if (anim.isForEach) ids.forEach((t, i) => this.push(this.cue({ t: "animation", id, mirror: m, delay: LK.Anim.baseDelay + i * LK.Anim.nextDelay }, t)));
      else this.push({ t: "cue", k: { t: "animation", id, mirror: m, delay: LK.Anim.baseDelay }, targets: ids });
      return true;
    }
    memberIndex(b) { const i = this.members.indexOf(b); return i >= 0 ? i : null; }
    cueTarget(b) { if (!b.isActor) return b.index; const i = this.memberIndex(b); return i === null ? null : -(i + 1); }
    actionMessage(s, item) {
      if (item.isSkill) { const m = item.message1 || "%1 uses %2!"; return m.includes("%1") ? m.split("%1").join(s.name).split("%2").join(item.name) : s.name + m; }
      return this.msg("useItem", s.name, item.name);
    }
    resultSteps(t) {
      const r = t.result, out = [], ct = this.cueTarget(t), actor = t.isActor, terms = this.terms;
      const c = (k, tg) => this.cue(k, tg);
      if (!r.used) return out;
      if (r.missed || r.evaded) {
        out.push(c({ t: "miss" }, ct));
        if (r.evaded && actor) out.push(c({ t: "motion", m: "evade" }, ct));
        out.push({ t: "se", f: this.sound(r.evaded ? 18 : 17) });
        out.push({ t: "log", s: r.evaded ? this.msg("evasion", t.name) : this.msg(actor ? "actorNoHit" : "enemyNoHit", t.name) });
        return out;
      }
      if (r.critical) { out.push({ t: "log", s: this.msg(actor ? "criticalToActor" : "criticalToEnemy") }); out.push(c({ t: "critical" }, ct)); }
      if (r.hpAffected) {
        const hpName = terms.basic[3];
        if (r.hpDamage > 0 && !r.drain) {
          out.push({ t: "se", f: this.sound(actor ? 14 : 10) });
          out.push(c({ t: "damage", v: r.hpDamage }, ct));
          if (actor) out.push(this.sideView ? c({ t: "motion", m: "damage" }, ct) : c({ t: "shake" }, null)); else out.push(c({ t: "effect", e: "blink" }, ct));
          out.push({ t: "log", s: this.msg(actor ? "actorDamage" : "enemyDamage", t.name, String(r.hpDamage)) });
        } else if (r.hpDamage > 0 && r.drain) {
          out.push(c({ t: "damage", v: r.hpDamage }, ct));
          out.push({ t: "log", s: this.msg(actor ? "actorDrain" : "enemyDrain", t.name, hpName, String(r.hpDamage)) });
        } else if (r.hpDamage < 0) {
          out.push({ t: "se", f: this.sound(16) });
          out.push(c({ t: "recover", v: -r.hpDamage }, ct));
          out.push({ t: "log", s: this.msg(actor ? "actorRecovery" : "enemyRecovery", t.name, hpName, String(-r.hpDamage)) });
        } else if (r.mpDamage === 0 && !r.addedStates.length && !r.removedStates.length) out.push({ t: "log", s: this.msg(actor ? "actorNoDamage" : "enemyNoDamage", t.name) });
      }
      if (r.mpDamage !== 0) {
        out.push(c({ t: "mpDamage", v: r.mpDamage }, ct));
        out.push({ t: "log", s: this.msg(r.mpDamage > 0 ? (actor ? "actorLoss" : "enemyLoss") : (actor ? "actorGain" : "enemyGain"), t.name, terms.basic[5], String(Math.abs(r.mpDamage))) });
      }
      for (const sid of r.addedStates) {
        const st = this.world.project.state(sid); if (!st) continue;
        const m = actor ? st.message1 : st.message2;
        if (m) out.push({ t: "log", s: m.includes("%1") ? m.split("%1").join(t.name) : t.name + m });
        if (sid === 1) { out.push(c({ t: "collapse" }, ct)); out.push({ t: "se", f: this.sound(actor ? 15 : 11) }); }
      }
      for (const sid of r.removedStates) {
        if (sid === 1) continue;
        const st = this.world.project.state(sid);
        if (st && st.message4) out.push({ t: "log", s: st.message4.includes("%1") ? st.message4.split("%1").join(t.name) : t.name + st.message4 });
      }
      for (const p of r.addedBuffs) out.push({ t: "log", s: this.msg("buffAdd", t.name, terms.params[p]) });
      for (const p of r.addedDebuffs) out.push({ t: "log", s: this.msg("debuffAdd", t.name, terms.params[p]) });
      if (!r.success && !r.hpAffected && r.mpDamage === 0) out.push({ t: "log", s: this.msg("actionFailure", t.name) });
      return out;
    }
    endTurn() {
      this.turnEndingCheck = true;
      if (this.setupBattleEvent()) return;
      this.turnEndingCheck = false;
      for (const b of this.members.concat(this.enemies)) {
        b.onTurnEnd(this.world.project.system.optSlipDeath || !b.isActor);
        if (b.result.hpAffected && b.result.hpDamage > 0) this.push(this.cue({ t: "damage", v: b.result.hpDamage }, this.cueTarget(b)));
        if (b.isDead && b.result.addedStates.includes(1)) this.push(this.cue({ t: "collapse" }, this.cueTarget(b)));
      }
      const troop = this.world.project.troop(this.troopId);
      (troop ? troop.pages : []).forEach((p, i) => { if (p.span === 1) this.pageDone[i] = false; });
      this.startInput();
    }
    setupBattleEvent() {
      const troop = this.world.project.troop(this.troopId);
      if (this.interpreter.isRunning || !troop) return false;
      for (let i = 0; i < troop.pages.length; i++) {
        const page = troop.pages[i];
        if (this.pageDone[i] || !this.meets(page.conditions)) continue;
        this.interpreter.setup(page.list, 0, this.world.state.mapId);
        if (page.span <= 1) this.pageDone[i] = true;
        return true;
      }
      return false;
    }
    meets(c) {
      if (!c.turnEnding && !c.turnValid && !c.enemyValid && !c.actorValid && !c.switchValid) return false;
      if (c.turnEnding && !this.turnEndingCheck) return false;
      if (c.turnValid) { const n = this.turnCount, a = c.turnA, b = c.turnB; if (b === 0 && n !== a) return false; if (b > 0 && (n < 1 || n < a || n % b !== a % b)) return false; }
      if (c.enemyValid) { if (c.enemyIndex >= this.enemies.length || this.enemies[c.enemyIndex].hpRate * 100 > c.enemyHp) return false; }
      if (c.actorValid) { const a = this.world.actor(c.actorId); if (!a || a.hpRate * 100 > c.actorHp) return false; }
      if (c.switchValid && !this.world.state.switchValue(c.switchId)) return false;
      return true;
    }
    checkBattleEnd() {
      if (this.phase === Phase.start) return false;
      if (this.members.every(a => !a.isAlive)) { this.processDefeat(); return true; }
      if (this.enemies.every(e => !e.isAlive)) { this.processVictory(); return true; }
      return false;
    }
    processVictory() {
      const w = this.world, p = w.project;
      this.phase = Phase.ending; this.outcome = 0;
      for (const b of this.members) b.removeBattleStates();
      this.members.forEach((a, i) => { a.actionState = "done"; if (a.canMove) this.push(this.cue({ t: "motion", m: "victory" }, -(i + 1))); });
      w.audio.playMe(w.state.victoryMe || p.system.victoryMe);
      const dead = this.enemies.filter(e => e.isDead);
      const exp = dead.reduce((s, e) => s + e.exp, 0);
      const gold = dead.reduce((s, e) => s + e.gold, 0) * (w.partyHasAbility(4) ? 2 : 1);
      const drops = [], dropRate = w.partyHasAbility(5) ? 2 : 1;
      for (const e of dead) for (const d of e.data ? e.data.dropItems : []) if (d.kind > 0 && w.rng.next(1000) / 1000 * d.denominator < dropRate) drops.push([d.kind, d.dataId]);
      this.rewards = { exp, gold, items: drops };
      this.push({ t: "clearLog" }, { t: "log", s: this.msg("victory", this.partyName) });
      if (exp > 0) this.push({ t: "log", s: this.msg("obtainExp", String(exp), this.terms.basic[8]) });
      if (gold > 0) this.push({ t: "log", s: this.msg("obtainGold", String(gold)).split("\\G").join(" " + p.system.currencyUnit) });
      w.state.gainGold(gold);
      for (const [k, id] of drops) {
        w.state.gain(k, id, 1);
        const x = k === 1 ? p.item(id) : k === 2 ? p.weapon(id) : p.armor(id);
        this.push({ t: "log", s: this.msg("obtainItem", x ? x.name : "?") });
      }
      for (const a of this.members) {
        const r = a.gainExp(exp);
        if (r.levels > 0) {
          this.push({ t: "log", s: this.msg("levelUp", a.name, this.terms.basic[0], String(a.level)) });
          for (const sid of r.newSkills) { const s = p.skill(sid); if (s) this.push({ t: "log", s: this.msg("obtainSkill", s.name) }); }
        }
      }
      this.push({ t: "wait", n: 90 });
    }
    processDefeat() {
      this.phase = Phase.ending; this.outcome = 2;
      this.world.audio.playMe(this.world.project.system.defeatMe);
      this.push({ t: "clearLog" }, { t: "log", s: this.msg("defeat", this.partyName) }, { t: "wait", n: 90 });
      if (this.canLose) this.push({ t: "run", f: () => { for (const a of this.members) if (a.isDead) { a.removeState(1); a.setHp(1); } } });
    }
    endBattle(o) { this.outcome = o; this.phase = Phase.ending; }
    replaceEnemy(old, ne) { const i = this.enemies.indexOf(old); if (i >= 0) { this.enemies[i] = ne; this.push(this.cue({ t: "effect", e: "whiten" }, ne.index)); } }
    cueAnimation(enemyIndex, id) { this.showNormalAnimation(this.enemies.filter(e => e.isAlive && (enemyIndex < 0 || e.index === enemyIndex)), id, false); }
    forceAction(isEnemy, id, skillId, target) {
      const s = isEnemy ? this.enemies[id] : this.world.actor(id);
      if (!s || !s.isAlive) return;
      const a = new GameAction(s, skillId, 0); a.forcing = true; a.targetIndex = target < 0 ? -1 : target;
      this.perform(a);
    }
    abort() { this.outcome = 3; this.queue = []; this.phase = Phase.ending; }
    finish() { for (const b of this.members) b.onBattleEnd(); const o = this.outcome === null ? 3 : this.outcome; if (this.onEnd) this.onEnd(o); }
  }
  LK.BattleManager = BattleManager;

  // ---------- sprite logic (BattleSprites.swift) ----------
  class AnimationPlayback {
    constructor(a, targets, mirror, delay) {
      Object.assign(this, { animation: a, targets, mirror, delay, cells: [], flashColor: [0, 0, 0, 0], screenFlashColor: [0, 0, 0, 0], hidingTargets: false,
        isPlaying: true, frameIndex: 0, started: false, duration: 0, flashDuration: 0, screenFlashDuration: 0, hidingDuration: 0, maxTimingFrames: 0 });
      if (a.frames) this.duration = a.frames.length * LK.Anim.mvRate + 1;
      else this.maxTimingFrames = Math.max(0, ...a.flashTimings.map(t => t.frame), ...a.soundTimings.map(t => t.frame));
    }
    get standInLength() { return this.animation.effectName ? rnd(LK.Anim.standInFrames * 100 / Math.max(10, this.animation.speed)) : 0; }
    get standInProgress() { const l = this.standInLength; return !this.animation.isMV && this.started && l > 0 && this.frameIndex <= l ? this.frameIndex / l : null; }
    update() {
      const sounds = [];
      if (this.animation.isMV) this.updateMV(sounds); else this.updateMZ(sounds);
      if (this.flashDuration > 0) { const d = this.flashDuration--; this.flashColor[3] *= (d - 1) / d; }
      if (this.screenFlashDuration > 0) { const d = this.screenFlashDuration--; this.screenFlashColor[3] *= (d - 1) / d; }
      if (this.hidingDuration > 0) { this.hidingDuration--; if (this.hidingDuration === 0) this.hidingTargets = false; }
      return sounds;
    }
    updateMV(sounds) {
      const frames = this.animation.frames;
      if (!this.isPlaying || !frames) return;
      if (this.delay > 0) { this.delay--; return; }
      this.started = true; this.duration--;
      const rate = LK.Anim.mvRate;
      if (this.duration % rate === 0 && this.duration > 0) {
        const index = frames.length - idiv(this.duration + rate - 1, rate);
        if (index >= 0 && index < frames.length) {
          this.cells = frames[index].map(c => this.makeCell(c)).filter(c => c);
          for (const t of this.animation.timings) {
            if (t.frame !== index) continue;
            const d = t.flashDuration * rate;
            if (t.flashScope === 1) { this.flashColor = t.flashColor.slice(); this.flashDuration = d; }
            else if (t.flashScope === 2) { this.screenFlashColor = t.flashColor.slice(); this.screenFlashDuration = d; }
            else if (t.flashScope === 3) { this.hidingTargets = true; this.hidingDuration = d; }
            if (t.se) sounds.push(t.se);
          }
        }
      }
      if (this.duration <= 0) {
        this.isPlaying = false; this.cells = []; this.flashDuration = 0; this.screenFlashDuration = 0; this.hidingDuration = 0; this.hidingTargets = false;
        this.flashColor = [0, 0, 0, 0]; this.screenFlashColor = [0, 0, 0, 0];
      }
    }
    makeCell(c) {
      if (!Array.isArray(c) || c.length < 8 || c[0] < 0) return null;
      const pattern = Math.trunc(c[0]);
      const cell = { pattern: pattern % 100, sheet: pattern < 100 ? 1 : 2, x: c[1], y: c[2], scaleX: c[3] / 100, scaleY: c[3] / 100, rotation: c[4] * Math.PI / 180, opacity: c[6], blend: Math.trunc(c[7]) };
      if (c[5]) cell.scaleX *= -1;
      if (this.mirror) { cell.x *= -1; cell.rotation *= -1; cell.scaleX *= -1; }
      return cell;
    }
    updateMZ(sounds) {
      if (!this.isPlaying) return;
      if (this.delay > 0) { this.delay--; return; }
      this.started = true;
      for (const t of this.animation.soundTimings) if (t.frame === this.frameIndex) sounds.push(t.se);
      for (const t of this.animation.flashTimings) if (t.frame === this.frameIndex) { this.flashColor = t.color.slice(); this.flashDuration = t.duration; }
      this.frameIndex++;
      if (this.frameIndex > this.maxTimingFrames && this.flashDuration === 0 && this.frameIndex > this.standInLength && !(this.effectHandle && this.effectHandle.exists)) this.isPlaying = false;
    }
  }
  LK.AnimationPlayback = AnimationPlayback;

  const MOTIONS = { walk: [0, true], wait: [1, true], chant: [2, true], guard: [3, true], damage: [4, false], evade: [5, false], thrust: [6, false], swing: [7, false],
    missile: [8, false], skill: [9, false], spell: [10, false], item: [11, false], escape: [12, true], victory: [13, true], dying: [14, true], abnormal: [15, true], sleep: [16, true], dead: [17, true] };
  class SVActorSprite {
    constructor(index) {
      Object.assign(this, { index, homeX: 600 + index * 32, homeY: 280 + index * 48, offsetX: 0, offsetY: 0, targetOffsetX: NaN, targetOffsetY: NaN, movementDuration: 0,
        motion: "wait", motionCount: 0, pattern: 0, weaponImageId: 0, weaponPattern: 0, weaponCount: 0, lastActionState: "", lastStateMotion: -1, actor: null });
      this.startMove(300, 0, 0);
    }
    get x() { return this.homeX + this.offsetX; }
    get y() { return this.homeY + this.offsetY; }
    get isMoving() { return this.movementDuration > 0; }
    get frame() { const m = (MOTIONS[this.motion] || [1])[0]; return { col: idiv(m, 6) * 3 + (this.pattern < 3 ? this.pattern : 1), row: m % 6 }; }
    startMove(x, y, d) { if (this.targetOffsetX !== x || this.targetOffsetY !== y) { this.targetOffsetX = x; this.targetOffsetY = y; this.movementDuration = d; if (d === 0) { this.offsetX = x; this.offsetY = y; } } }
    startMotion(n) { if (this.motion !== n) { this.motion = n; this.motionCount = 0; this.pattern = 0; } }
    requestMotion(n) { this.startMotion(n); if (this.actor) { this.lastActionState = this.actor.actionState; this.lastStateMotion = this.actor.stateMotionIndex; } }
    startWeapon(id) { this.weaponImageId = id; this.weaponCount = 0; this.weaponPattern = 0; }
    setActor(a) {
      if (a !== this.actor) {
        this.actor = a;
        if (a && a.canMove) { this.startMotion("walk"); this.startMove(0, 0, 30); } else if (!this.isMoving) { this.refreshMotion(); this.startMove(0, 0, 0); }
      }
    }
    refreshMotion() {
      const a = this.actor; if (!a) return;
      const sm = a.stateMotionIndex;
      if (a.isInputting || a.isActing) this.startMotion("walk");
      else if (sm === 3 || a.isDead) this.startMotion("dead");
      else if (sm === 2) this.startMotion("sleep");
      else if (a.isChanting) this.startMotion("chant");
      else if (a.isGuardWaiting || (a.isGuarding && a.actionState !== "done")) this.startMotion("guard");
      else if (sm === 1) this.startMotion("abnormal");
      else if (a.isDying) this.startMotion("dying");
      else if (a.isUndecided) this.startMotion("walk");
      else this.startMotion("wait");
    }
    update(escaped, battleEnded) {
      const a = this.actor; if (!a) return;
      if (this.movementDuration > 0) {
        const d = this.movementDuration;
        this.offsetX = (this.offsetX * (d - 1) + this.targetOffsetX) / d; this.offsetY = (this.offsetY * (d - 1) + this.targetOffsetY) / d;
        this.movementDuration--;
        if (this.movementDuration === 0 && !battleEnded) this.refreshMotion();
      }
      if (!this.isMoving) {
        if (a.canMove && escaped) this.startMove(300, 0, 30);
        else if (a.isInputting || a.isActing) this.startMove(-48, 0, 12);
        else if (!(this.offsetX === 0 && this.offsetY === 0)) this.startMove(0, 0, 12);
      }
      if (a.actionState !== this.lastActionState || a.stateMotionIndex !== this.lastStateMotion || (this.motion === "dead") !== a.isDead) {
        this.lastActionState = a.actionState; this.lastStateMotion = a.stateMotionIndex;
        const m = MOTIONS[this.motion];
        if (!(m && m[1] === false && this.motionCount > 0 && !a.isDead) || a.isDead) this.refreshMotion();
      }
      this.motionCount++;
      if (this.motionCount >= 12) {
        const m = MOTIONS[this.motion];
        if (!m || m[1]) this.pattern = (this.pattern + 1) % 4; else if (this.pattern < 2) this.pattern++; else this.refreshMotion();
        this.motionCount = 0;
      }
      if (this.weaponImageId > 0) { this.weaponCount++; if (this.weaponCount >= 12) { this.weaponPattern++; this.weaponCount = 0; if (this.weaponPattern >= 3) this.weaponImageId = 0; } }
    }
  }
  LK.SVActorSprite = SVActorSprite;

  class EnemySpriteEffect {
    constructor(alive, bitmapHeight) { Object.assign(this, { effectType: null, duration: 0, opacity: alive ? 255 : 0, blendColor: [0, 0, 0, 0], additive: false, shake: 0, appeared: alive, bitmapHeight: Math.max(1, bitmapHeight), wantsBossSound: false }); }
    get isEffecting() { return this.effectType !== null; }
    get bossCollapseHeight() { return this.effectType === "bossCollapse" ? this.duration : -1; }
    get isCollapseEffect() { return ["collapse", "bossCollapse", "instantCollapse"].includes(this.effectType); }
    start(type) {
      this.effectType = type;
      switch (type) {
        case "appear": this.duration = 16; this.appeared = true; break;
        case "disappear": this.duration = 32; this.appeared = false; break;
        case "whiten": this.duration = 16; break;
        case "blink": this.duration = 20; break;
        case "collapse": this.duration = 32; this.appeared = false; break;
        case "bossCollapse": this.duration = this.bitmapHeight; this.appeared = false; break;
        case "instantCollapse": this.duration = 16; this.appeared = false; break;
        default: this.effectType = null;
      }
      this.shake = 0; this.additive = false; this.opacity = 255; this.blendColor = [0, 0, 0, 0];
    }
    update(alive, hidden) {
      this.wantsBossSound = false;
      if (!this.appeared && alive && !hidden && !this.isCollapseEffect) this.start("appear");
      else if (this.appeared && hidden) this.start("disappear");
      if (this.duration <= 0 || !this.effectType) return;
      const t = this.effectType;
      this.duration--;
      switch (t) {
        case "whiten": this.blendColor = [255, 255, 255, 128 - (16 - this.duration) * 8]; break;
        case "blink": this.opacity = this.duration % 10 < 5 ? 255 : 0; break;
        case "appear": this.opacity = (16 - this.duration) * 16; break;
        case "disappear": this.opacity = 256 - (32 - this.duration) * 10; break;
        case "collapse": this.additive = true; this.blendColor = [255, 128, 128, 128]; this.opacity *= this.duration / (this.duration + 1); break;
        case "bossCollapse": this.shake = (this.duration % 2) * 4 - 2; this.additive = true; this.opacity *= this.duration / (this.duration + 1); this.blendColor = [255, 255, 255, 255 - this.opacity]; if (this.duration % 20 === 19) this.wantsBossSound = true; break;
        case "instantCollapse": this.opacity = 0; break;
      }
      if (this.duration === 0) {
        this.effectType = null;
        if (t === "whiten" || t === "blink") { this.blendColor = [0, 0, 0, 0]; this.opacity = 255; }
        if (["collapse", "bossCollapse", "instantCollapse", "disappear"].includes(t)) this.opacity = 0;
      }
    }
  }
  LK.EnemySpriteEffect = EnemySpriteEffect;
})(typeof LK !== "undefined" ? LK : require("./core-data.js"));
