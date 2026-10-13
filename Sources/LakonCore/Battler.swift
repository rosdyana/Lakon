import Foundation

/// Port of MZ's Game_BattlerBase/Game_Battler: params = (base + plus) × trait rate × buff rate,
/// x-params are trait sums, s-params are trait products, state 1 is death.
public class GameBattler {
    public static let deathStateId = 1
    public static let attackSkillId = 1
    public static let guardSkillId = 2

    unowned let project: Project
    public internal(set) var hp = 1
    public internal(set) var mp = 0
    public internal(set) var tp = 0
    public internal(set) var states: [Int] = []
    var stateTurns: [Int: Int] = [:]
    public internal(set) var buffs = [Int](repeating: 0, count: 8)
    var buffTurns = [Int](repeating: 0, count: 8)
    var paramPlusExtra = [Int](repeating: 0, count: 8)
    public var result = ActionResult()
    var actions: [GameAction] = []
    var speed = 0
    public internal(set) var hidden = false
    /// Game_Battler._actionState: "undecided", "inputting", "waiting", "acting", "done". Drives side-view motions.
    public internal(set) var actionState = ""
    /// The world's random source (seeded in tests, so battles replay exactly).
    var rng: RandomSource = SystemRandom()

    init(project: Project) { self.project = project }

    // MARK: overridables
    public var name: String { "" }
    public var isActor: Bool { false }
    func paramBase(_ id: Int) -> Int { 1 }
    func paramPlus(_ id: Int) -> Int { paramPlusExtra[id] }
    func paramMax(_ id: Int) -> Int { id == 0 ? 999_999 : 9999 }
    func ownTraits() -> [Trait] { [] }

    // MARK: traits
    public func allTraits() -> [Trait] {
        ownTraits() + states.compactMap { project.state($0) }.flatMap(\.traits)
    }
    func traits(_ code: Int) -> [Trait] { allTraits().filter { $0.code == code } }
    func traitsWith(_ code: Int, _ id: Int) -> [Trait] { allTraits().filter { $0.code == code && $0.dataId == id } }
    func traitsPi(_ code: Int, _ id: Int) -> Double { traitsWith(code, id).reduce(1) { $0 * $1.value } }
    func traitsSum(_ code: Int, _ id: Int) -> Double { traitsWith(code, id).reduce(0) { $0 + $1.value } }
    func traitsSumAll(_ code: Int) -> Double { traits(code).reduce(0) { $0 + $1.value } }
    func traitsSet(_ code: Int) -> [Int] { traits(code).map(\.dataId) }

    // MARK: params
    public func param(_ id: Int) -> Int {
        let rate = traitsPi(Trait.param, id) * (Double(buffs[id]) * 0.25 + 1)
        let v = Double(paramBase(id) + paramPlus(id)) * rate
        return Int(max(Double(id == 0 ? 1 : 0), min(Double(paramMax(id)), v)).rounded())
    }
    public var mhp: Int { param(0) }
    public var mmp: Int { param(1) }
    public var atk: Int { param(2) }
    public var def: Int { param(3) }
    public var mat: Int { param(4) }
    public var mdf: Int { param(5) }
    public var agi: Int { param(6) }
    public var luk: Int { param(7) }
    public func xparam(_ id: Int) -> Double { traitsSum(Trait.xparam, id) }
    public func sparam(_ id: Int) -> Double { traitsPi(Trait.sparam, id) }
    public var hit: Double { xparam(0) }
    public var eva: Double { xparam(1) }
    public var cri: Double { xparam(2) }
    public var cev: Double { xparam(3) }
    public var mev: Double { xparam(4) }
    public var hrg: Double { xparam(7) }
    public var mrg: Double { xparam(8) }
    public var trg: Double { xparam(9) }
    public var grd: Double { sparam(1) }
    public var rec: Double { sparam(2) }
    public var pha: Double { sparam(3) }
    public var mcr: Double { sparam(4) }
    public var tcr: Double { sparam(5) }
    public var pdr: Double { sparam(6) }
    public var mdr: Double { sparam(7) }
    public var fdr: Double { sparam(8) }
    public var exr: Double { sparam(9) }
    public var maxTp: Int { 100 }
    public var hpRate: Double { mhp > 0 ? Double(hp) / Double(mhp) : 0 }
    public var mpRate: Double { mmp > 0 ? Double(mp) / Double(mmp) : 0 }

    public func elementRate(_ e: Int) -> Double { traitsPi(Trait.elementRate, e) }
    public func stateRate(_ s: Int) -> Double { traitsPi(Trait.stateRate, s) }
    public var stateResistSet: [Int] { traitsSet(Trait.stateResist) }
    public var attackElements: [Int] { traitsSet(Trait.attackElement) }
    public var attackStates: [(Int, Double)] { traits(Trait.attackState).map { ($0.dataId, $0.value) } }
    public var attackSpeed: Int { Int(traitsSumAll(Trait.attackSpeed)) }
    public var attackTimesAdd: Int { max(Int(traitsSumAll(Trait.attackTimes)), 0) }
    public var attackSkill: Int { traits(Trait.attackSkill).last?.dataId ?? Self.attackSkillId }
    func specialFlag(_ id: Int) -> Bool { allTraits().contains { $0.code == Trait.specialFlag && $0.dataId == id } }
    public var isGuarding: Bool { specialFlag(1) && canMove }
    public var isAutoBattle: Bool { specialFlag(0) }
    public var preservesTp: Bool { specialFlag(3) }
    var actionPlusSet: [Double] { traits(Trait.actionPlus).map(\.value) }

    // MARK: life & states
    public var isDead: Bool { states.contains(Self.deathStateId) }
    public var isAlive: Bool { !isDead && !hidden }
    public var isAppeared: Bool { !hidden }
    public func isStateAffected(_ id: Int) -> Bool { states.contains(id) }
    public var restriction: Int { states.compactMap { project.state($0)?.restriction }.max() ?? 0 }
    public var canMove: Bool { isAppeared && !isDead && restriction < 4 }
    public var canInput: Bool { isAppeared && !isDead && restriction == 0 && !isAutoBattle && isActor }
    public var isConfused: Bool { isAppeared && (1...3).contains(restriction) }
    public var sortedStates: [StateData] {
        states.compactMap { project.state($0) }.sorted { $0.priority > $1.priority }
    }

    public func setHp(_ v: Int) { hp = v; refresh() }
    public func setMp(_ v: Int) { mp = v; refresh() }
    public func setTp(_ v: Int) { tp = max(0, min(maxTp, v)) }
    public func gainHp(_ v: Int) { result.hpDamage = -v; result.hpAffected = true; setHp(hp + v) }
    public func gainMp(_ v: Int) { result.mpDamage = -v; setMp(mp + v) }
    public func gainTp(_ v: Int) { result.tpDamage = -v; setTp(tp + v) }
    public func gainSilentTp(_ v: Int) { setTp(tp + v) }

    func refresh() {
        hp = max(0, min(mhp, hp)); mp = max(0, min(mmp, mp)); tp = max(0, min(maxTp, tp))
        for s in stateResistSet where isStateAffected(s) { eraseState(s) }
        if hp == 0 { addState(Self.deathStateId) } else { removeState(Self.deathStateId) }
    }

    func isStateAddable(_ id: Int) -> Bool {
        guard project.state(id) != nil, !stateResistSet.contains(id) else { return false }
        if id != Self.deathStateId && isDead { return false }
        return true
    }

    public func addState(_ id: Int) {
        guard isStateAddable(id) else { return }
        if !isStateAffected(id) {
            if id == Self.deathStateId { die() }
            states.append(id)
            if let s = project.state(id), s.restriction > 0 {
                actions = []
                for st in states where project.state(st)?.removeByRestriction == true { eraseState(st) }
            }
            refreshAfterStateChange()
        }
        if let s = project.state(id) {
            stateTurns[id] = s.minTurns + rng.next(max(0, s.maxTurns - s.minTurns) + 1)
        }
        result.addedStates.append(id)
    }

    public func removeState(_ id: Int) {
        guard isStateAffected(id) else { return }
        if id == Self.deathStateId { revive() }
        eraseState(id)
        refreshAfterStateChange()
        result.removedStates.append(id)
    }
    func eraseState(_ id: Int) { states.removeAll { $0 == id }; stateTurns[id] = nil }
    func refreshAfterStateChange() {
        hp = max(0, min(mhp, hp)); mp = max(0, min(mmp, mp))
    }
    func die() { hp = 0; states = []; stateTurns = [:]; buffs = Array(repeating: 0, count: 8); buffTurns = Array(repeating: 0, count: 8) }
    func revive() { if hp == 0 { hp = 1 } }

    public func recoverAll() {
        states = []; stateTurns = [:]; hp = mhp; mp = mmp
    }

    func removeStatesAuto(_ timing: Int) {
        for s in sortedStates where (stateTurns[s.id] ?? 0) <= 0 && s.autoRemovalTiming == timing { removeState(s.id) }
    }
    func removeStatesByDamage() {
        for s in sortedStates where s.removeByDamage && rng.next(100) < s.chanceByDamage { removeState(s.id) }
    }
    func removeBattleStates() {
        for s in sortedStates where s.removeAtBattleEnd { removeState(s.id) }
    }
    func updateStateTurns() { for id in states where (stateTurns[id] ?? 0) > 0 { stateTurns[id]! -= 1 } }

    public func addBuff(_ id: Int, _ turns: Int) {
        guard isAlive else { return }
        if buffs[id] < 2 { buffs[id] += 1 }
        buffTurns[id] = max(buffTurns[id], turns)
        result.addedBuffs.append(id); refresh()
    }
    public func addDebuff(_ id: Int, _ turns: Int) {
        guard isAlive else { return }
        if buffs[id] > -2 { buffs[id] -= 1 }
        buffTurns[id] = max(buffTurns[id], turns)
        result.addedDebuffs.append(id); refresh()
    }
    public func removeBuff(_ id: Int) {
        guard buffs[id] != 0 else { return }
        buffs[id] = 0; buffTurns[id] = 0; result.removedBuffs.append(id); refresh()
    }
    func updateBuffTurns() {
        for i in 0..<8 where buffTurns[i] > 0 {
            buffTurns[i] -= 1
            if buffTurns[i] == 0 { removeBuff(i) }
        }
    }

    // MARK: costs & usability
    public func skillMpCost(_ s: Skill) -> Int { Int((Double(s.mpCost) * mcr).rounded(.down)) }
    public func canPaySkillCost(_ s: Skill) -> Bool { tp >= s.tpCost && mp >= skillMpCost(s) }
    func paySkillCost(_ s: Skill) { mp -= skillMpCost(s); tp -= s.tpCost }
    public func isSkillSealed(_ id: Int) -> Bool { traitsSet(Trait.skillSeal).contains(id) }
    public func isSkillTypeSealed(_ id: Int) -> Bool { traitsSet(Trait.stypeSeal).contains(id) }
    public func canUse(_ item: UsableItem, inBattle: Bool) -> Bool {
        guard canMove || !inBattle else { return false }
        if inBattle ? !item.isBattleUsable : !item.isMenuUsable { return false }
        if let s = item as? Skill {
            return canPaySkillCost(s) && !isSkillSealed(s.id) && !isSkillTypeSealed(s.stypeId)
        }
        return true
    }

    // MARK: battle hooks
    func onBattleStart(preemptive: Bool) {
        if !preservesTp { tp = rng.next(25) }
        actionState = "undecided"
        if preemptive { /* MZ: nothing extra */ }
    }
    func onBattleEnd() {
        result = ActionResult(); removeBattleStates(); buffs = Array(repeating: 0, count: 8); buffTurns = Array(repeating: 0, count: 8)
        actions = []; if !preservesTp { tp = 0 }
        if isDead == false { /* stay */ }
    }
    func onTurnEnd(slipDeath: Bool) {
        result = ActionResult()
        if isAlive {
            let minRecover = slipDeath ? -hp : -(hp - 1)
            let hpv = max(Int((Double(mhp) * hrg).rounded(.down)), minRecover)
            if hpv != 0 { gainHp(hpv) }
            let mpv = Int((Double(mmp) * mrg).rounded(.down))
            if mpv != 0 { gainMp(mpv) }
            gainSilentTp(Int((100 * trg).rounded(.down)))
        }
        updateStateTurns(); updateBuffTurns(); removeStatesAuto(2)
    }
    func onDamage(_ value: Int) {
        removeStatesByDamage()
        let rate = Double(value) / Double(max(mhp, 1))
        gainSilentTp(Int((50 * rate * tcr).rounded(.down)))
    }
    var numActions: Int {
        actionPlusSet.reduce(1) { r, p in Double(rng.next(1_000_000)) / 1_000_000 < p ? r + 1 : r }
    }

    // MARK: side-view sprite state (Game_BattlerBase.stateMotionIndex/stateOverlayIndex, Game_Battler.isChanting…)
    public var stateMotionIndex: Int { sortedStates.first?.motion ?? 0 }
    public var stateOverlayIndex: Int { sortedStates.first?.overlay ?? 0 }
    public var isDying: Bool { isAlive && Double(hp) < Double(mhp) / 4 }
    public var isInputting: Bool { actionState == "inputting" }
    public var isActing: Bool { actionState == "acting" }
    public var isUndecided: Bool { actionState == "undecided" }
    public var isChanting: Bool { actionState == "waiting" && actions.contains { $0.isMagicSkill } }
    public var isGuardWaiting: Bool { actionState == "waiting" && actions.contains { $0.isGuard } }
}

public struct ActionResult {
    public var used = false
    public var missed = false
    public var evaded = false
    public var physical = false
    public var drain = false
    public var critical = false
    public var success = false
    public var hpAffected = false
    public var hpDamage = 0
    public var mpDamage = 0
    public var tpDamage = 0
    public var addedStates: [Int] = []
    public var removedStates: [Int] = []
    public var addedBuffs: [Int] = []
    public var addedDebuffs: [Int] = []
    public var removedBuffs: [Int] = []
    public var isHit: Bool { used && !missed && !evaded }
    public init() {}
}

/// Persisted actor state (Game_Actor fields that a save must carry).
public struct ActorSave: Codable {
    public var actorId: Int
    public var name: String
    public var nickname: String
    public var classId: Int
    public var level: Int
    public var exp: [Int: Int]
    public var hp: Int
    public var mp: Int
    public var tp: Int
    public var states: [Int]
    public var stateTurns: [Int: Int]
    public var skills: [Int]
    public var equips: [Int]
    public var paramPlus: [Int]
}

public final class GameActor: GameBattler {
    public let actorId: Int
    public var actorName: String
    public var nickname: String
    public internal(set) var classId: Int
    public internal(set) var level: Int
    var exp: [Int: Int] = [:]
    public internal(set) var learnedSkills: [Int] = []
    /// Item ids per equip slot. Slot 0 is the weapon (Weapons.json), other slots are armors.
    public internal(set) var equips: [Int]

    init(project: Project, actorId: Int, rng: RandomSource = SystemRandom()) {
        self.actorId = actorId
        let a = project.actor(actorId)
        actorName = a?.name ?? "Actor \(actorId)"
        nickname = a?.nickname ?? ""
        classId = a?.classId ?? 1
        level = max(1, a?.initialLevel ?? 1)
        equips = Array((a?.equips ?? []) + Array(repeating: 0, count: 5)).prefix(5).map { $0 }
        super.init(project: project)
        self.rng = rng
        exp[classId] = expForLevel(level)
        for l in project.classData(classId)?.learnings ?? [] where l.level <= level { learnSkill(l.skillId) }
        // Drop initial equipment the actor can't wear.
        for i in equips.indices where equips[i] > 0 && !canEquip(slot: i, id: equips[i]) { equips[i] = 0 }
        recoverAll()
    }

    init(project: Project, save s: ActorSave) {
        actorId = s.actorId; actorName = s.name; nickname = s.nickname; classId = s.classId; level = s.level
        exp = s.exp; learnedSkills = s.skills; equips = s.equips
        super.init(project: project)
        hp = s.hp; mp = s.mp; tp = s.tp; states = s.states; stateTurns = s.stateTurns; paramPlusExtra = s.paramPlus
    }

    var save: ActorSave {
        ActorSave(actorId: actorId, name: actorName, nickname: nickname, classId: classId, level: level, exp: exp, hp: hp, mp: mp, tp: tp,
                  states: states, stateTurns: stateTurns, skills: learnedSkills, equips: equips, paramPlus: paramPlusExtra)
    }

    public override var name: String { actorName }
    public override var isActor: Bool { true }
    public var data: Actor? { project.actor(actorId) }
    public var currentClass: ClassData? { project.classData(classId) }
    /// Side-view battler sheet (img/sv_actors).
    public var battlerName: String { data?.battlerName ?? "" }
    /// Game_Actor.attackAnimationId1: the weapon's animation, or 1 for bare hands.
    public var attackAnimationId: Int { equips.first.flatMap { $0 > 0 ? project.weapon($0) : nil }?.animationId ?? 1 }
    /// System.attackMotions entry for the equipped weapon type (0 = bare hands).
    public var attackMotion: AttackMotion? {
        let wtype = equips.first.flatMap { $0 > 0 ? project.weapon($0)?.wtypeId : nil } ?? 0
        return project.system.attackMotions[safe: wtype]
    }
    public var maxLevel: Int { data?.maxLevel ?? 99 }

    override func paramBase(_ id: Int) -> Int {
        guard let c = currentClass, id < c.params.count, !c.params[id].isEmpty else { return id == 0 ? 100 : 10 }
        return c.params[id][min(level, c.params[id].count - 1)]
    }
    override func paramPlus(_ id: Int) -> Int {
        super.paramPlus(id) + equipItems.reduce(0) { $0 + $1.params[id] }
    }
    override func paramMax(_ id: Int) -> Int { id == 0 ? 9999 : 999 }
    override func ownTraits() -> [Trait] {
        (data?.traits ?? []) + (currentClass?.traits ?? []) + equipItems.flatMap(\.traits)
    }

    public var equipItems: [EquipItem] {
        equips.enumerated().compactMap { i, id in id > 0 ? (i == 0 ? project.weapon(id) : project.armor(id)) : nil }
    }
    /// MZ default slots: weapon, shield, head, body, accessory → etypeIds 1...5.
    public static let slotEtypes = [1, 2, 3, 4, 5]
    public func canEquip(slot: Int, id: Int) -> Bool {
        if slot == 0 {
            guard let w = project.weapon(id) else { return false }
            return traitsSet(Trait.equipWtype).contains(w.wtypeId) && !traitsSet(Trait.equipSeal).contains(1)
        }
        guard let a = project.armor(id), a.etypeId == Self.slotEtypes[slot] else { return false }
        return traitsSet(Trait.equipAtype).contains(a.atypeId) && !traitsSet(Trait.equipSeal).contains(a.etypeId)
    }
    public func isEquipLocked(slot: Int) -> Bool { traitsSet(Trait.equipLock).contains(Self.slotEtypes[slot]) }

    // MARK: exp & level (Game_Actor.expForLevel)
    public func expForLevel(_ lv: Int) -> Int {
        let p = currentClass?.expParams ?? [30, 20, 30, 30]
        let basis = Double(p[0]), extra = Double(p[1]), accA = Double(p[2]), accB = Double(max(p[3], 1))
        let l = Double(lv)
        return Int((basis * pow(l - 1, 0.9 + accA / 250) * l * (l + 1) / (6 + pow(l, 2) / 50 / accB) + (l - 1) * extra).rounded())
    }
    public var currentExp: Int { exp[classId] ?? 0 }
    public var nextLevelExp: Int { expForLevel(level + 1) }
    public var expToNext: Int { level >= maxLevel ? 0 : nextLevelExp - currentExp }

    /// Returns names of skills learned through level-ups (for battle messages).
    @discardableResult
    public func changeExp(_ value: Int) -> (levels: Int, newSkills: [Int]) {
        let lastLevel = level, lastSkills = Set(learnedSkills)
        exp[classId] = max(value, 0)
        while level < maxLevel && currentExp >= nextLevelExp { levelUp() }
        while level > 1 && currentExp < expForLevel(level) { level -= 1 }
        refresh()
        return (level - lastLevel, learnedSkills.filter { !lastSkills.contains($0) })
    }
    public func gainExp(_ v: Int) -> (levels: Int, newSkills: [Int]) {
        changeExp(currentExp + Int((Double(v) * exr).rounded()))
    }
    func levelUp() {
        level += 1
        for l in currentClass?.learnings ?? [] where l.level == level { learnSkill(l.skillId) }
    }
    public func changeLevel(_ lv: Int) { changeExp(expForLevel(max(1, min(maxLevel, lv)))) }

    public func learnSkill(_ id: Int) { if !learnedSkills.contains(id) { learnedSkills.append(id); learnedSkills.sort() } }
    public func forgetSkill(_ id: Int) { learnedSkills.removeAll { $0 == id } }
    public var skills: [Skill] {
        Array(Set(learnedSkills + traitsSet(Trait.skillAdd))).sorted().compactMap { project.skill($0) }
    }
    public var addedSkillTypes: [Int] { Array(Set(traitsSet(Trait.stypeAdd))).sorted() }
    public func setName(_ n: String) { actorName = n }
    public func changeClass(_ id: Int, keepExp: Bool) {
        let e = currentExp
        classId = id
        if keepExp { exp[id] = e } else if exp[id] == nil { exp[id] = 0 }
        changeExp(exp[id] ?? 0)
    }

    /// Swap equipment; returns the previously equipped item id (goes back to the party inventory).
    @discardableResult
    public func changeEquip(slot: Int, to id: Int) -> Int {
        let old = equips[slot]
        equips[slot] = id
        refresh()
        return old
    }
}

public final class GameEnemy: GameBattler {
    public let enemyId: Int
    public let index: Int
    public let screenX: Int
    public let screenY: Int
    public var letter = ""
    var turnCount = 0

    init(project: Project, enemyId: Int, index: Int, x: Int, y: Int, hidden: Bool) {
        self.enemyId = enemyId; self.index = index; screenX = x; screenY = y
        super.init(project: project)
        self.hidden = hidden
        recoverAll()
    }
    public var data: Enemy? { project.enemy(enemyId) }
    public override var name: String { (data?.name ?? "Enemy") + letter }
    public var battlerName: String { data?.battlerName ?? "" }
    public var battlerHue: Int { data?.battlerHue ?? 0 }
    /// Trait 63 Collapse Effect: 0 normal, 1 boss, 2 instant, 3 no disappear.
    public var collapseType: Int { traits(Trait.collapseType).map(\.dataId).max() ?? 0 }
    override func paramBase(_ id: Int) -> Int { data.map { id < $0.params.count ? $0.params[id] : 1 } ?? 1 }
    override func ownTraits() -> [Trait] { data?.traits ?? [] }
    public var exp: Int { data?.exp ?? 0 }
    public var gold: Int { data?.gold ?? 0 }

    public func appear() { hidden = false }
    public func transform(_ id: Int) -> GameEnemy {
        let e = GameEnemy(project: project, enemyId: id, index: index, x: screenX, y: screenY, hidden: false)
        e.rng = rng; e.letter = letter; e.hp = min(hp, e.mhp); e.mp = min(mp, e.mmp)
        return e
    }

    func meetsCondition(_ a: EnemyAction, partyLevel: Int, switches: (Int) -> Bool) -> Bool {
        let p1 = a.conditionParam1, p2 = a.conditionParam2
        switch a.conditionType {
        case 1:
            let n = Double(turnCount)
            return p2 == 0 ? n == p1 : (n > 0 && n >= p1 && Int(n) % Int(p2) == Int(p1) % Int(p2))
        case 2: return hpRate >= p1 && hpRate <= p2
        case 3: return mpRate >= p1 && mpRate <= p2
        case 4: return isStateAffected(Int(p1))
        case 5: return Double(partyLevel) >= p1
        case 6: return switches(Int(p1))
        default: return true
        }
    }

    /// Rating-weighted pick among actions within 3 of the best rating (Game_Enemy.selectAllActions).
    func makeActions(rng: RandomSource, partyLevel: Int, switches: (Int) -> Bool) {
        actions = []
        guard canMove else { return }
        let valid = (data?.actions ?? []).filter { a in
            meetsCondition(a, partyLevel: partyLevel, switches: switches) && project.skill(a.skillId).map { canUse($0, inBattle: true) } == true
        }
        guard let maxRating = valid.map(\.rating).max() else { return }
        let zero = maxRating - 3
        let pool = valid.filter { $0.rating > zero }
        for _ in 0..<numActions {
            let sum = pool.reduce(0) { $0 + $1.rating - zero }
            var v = rng.next(max(sum, 1))
            var chosen = pool.first!
            for a in pool { v -= a.rating - zero; if v < 0 { chosen = a; break } }
            let act = GameAction(subject: self, skillId: chosen.skillId)
            act.targetIndex = -1
            actions.append(act)
        }
    }
}

extension Project {
    public func actor(_ id: Int) -> Actor? { id > 0 && id < actors.count ? actors[id] : nil }
    public func classData(_ id: Int) -> ClassData? { id > 0 && id < classes.count ? classes[id] : nil }
    public func skill(_ id: Int) -> Skill? { id > 0 && id < skills.count ? skills[id] : nil }
    public func item(_ id: Int) -> Item? { id > 0 && id < items.count ? items[id] : nil }
    public func weapon(_ id: Int) -> EquipItem? { id > 0 && id < weapons.count ? weapons[id] : nil }
    public func armor(_ id: Int) -> EquipItem? { id > 0 && id < armors.count ? armors[id] : nil }
    public func enemy(_ id: Int) -> Enemy? { id > 0 && id < enemies.count ? enemies[id] : nil }
    public func troop(_ id: Int) -> Troop? { id > 0 && id < troops.count ? troops[id] : nil }
    public func state(_ id: Int) -> StateData? { id > 0 && id < states.count ? states[id] : nil }
}
