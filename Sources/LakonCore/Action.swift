import Foundation

/// Port of MZ's Game_Action: targeting by scope, hit/evade/critical rolls, damage formula
/// (JavaScript, evaluated by the world's ScriptEngine), variance, guard, element rate, then effects.
public final class GameAction {
    public unowned let subject: GameBattler
    public internal(set) var skillId = 0
    public internal(set) var itemId = 0
    public var targetIndex = -1
    var forcing = false

    init(subject: GameBattler, skillId: Int) { self.subject = subject; self.skillId = skillId }
    init(subject: GameBattler, itemId: Int) { self.subject = subject; self.itemId = itemId }

    var project: Project { subject.project }
    public var item: UsableItem? { skillId > 0 ? project.skill(skillId) : project.item(itemId) }
    public var isSkill: Bool { skillId > 0 }
    public var isItem: Bool { itemId > 0 }
    public var isAttack: Bool { skillId == subject.attackSkill }
    public var isGuard: Bool { skillId == GameBattler.guardSkillId }
    /// Game_Action.isMagicSkill: a skill whose type is in System.magicSkills.
    public var isMagicSkill: Bool { isSkill && project.system.magicSkills.contains(project.skill(skillId)?.stypeId ?? -1) }

    public func speed(_ rng: RandomSource) -> Int {
        let agi = subject.agi
        var s = agi + rng.next(max(1, 5 + agi / 4))
        s += item?.speed ?? 0
        if isAttack { s += subject.attackSpeed }
        return s
    }

    var numRepeats: Int {
        var n = item?.repeats ?? 1
        if isAttack { n += subject.attackTimesAdd }
        return max(n, 1)
    }

    // MARK: targets

    func makeTargets(friends: [GameBattler], opponents: [GameBattler], rng: RandomSource) -> [GameBattler] {
        guard let it = item else { return [] }
        var targets: [GameBattler] = []
        if !forcing && subject.isConfused {
            let pool: [GameBattler]
            switch subject.restriction {
            case 1: pool = opponents
            case 3: pool = friends
            default: pool = rng.next(2) == 0 ? opponents : friends
            }
            if let t = randomTarget(pool.filter(\.isAlive), rng) { targets = [t] }
        } else if it.scope == 14 {
            targets = opponents.filter(\.isAlive) + friends.filter(\.isAlive)
        } else if it.isForOpponent {
            let alive = opponents.filter(\.isAlive)
            if it.isForRandom {
                targets = (0..<(it.scope - 2)).compactMap { _ in randomTarget(alive, rng) }
            } else if it.isForAll {
                targets = alive
            } else if let t = smoothTarget(opponents, targetIndex, rng) { targets = [t] }
        } else if it.isForFriend {
            if it.isForUser { targets = [subject] }
            else if it.isForDeadFriend {
                let dead = friends.filter { $0.isDead }
                if it.isForAll { targets = dead } else if targetIndex >= 0, targetIndex < friends.count, friends[targetIndex].isDead { targets = [friends[targetIndex]] } else if let d = dead.first { targets = [d] }
            } else if it.scope == 12 || it.scope == 13 {
                targets = it.isForAll ? friends : (targetIndex >= 0 && targetIndex < friends.count ? [friends[targetIndex]] : [subject])
            } else if it.isForAll {
                targets = friends.filter(\.isAlive)
            } else if let t = smoothTarget(friends, targetIndex, rng) { targets = [t] }
        }
        // Repeats
        var out: [GameBattler] = []
        for t in targets { for _ in 0..<numRepeats { out.append(t) } }
        return out
    }

    func randomTarget(_ alive: [GameBattler], _ rng: RandomSource) -> GameBattler? {
        alive.isEmpty ? nil : alive[rng.next(alive.count)]
    }
    func smoothTarget(_ unit: [GameBattler], _ index: Int, _ rng: RandomSource) -> GameBattler? {
        if index >= 0, index < unit.count, unit[index].isAlive { return unit[index] }
        if index >= 0 { return unit.first(where: \.isAlive) }
        return randomTarget(unit.filter(\.isAlive), rng)
    }

    // MARK: apply

    /// `formula` evaluates a damage formula string with a = subject, b = target.
    func apply(to target: GameBattler, rng: RandomSource, formula: (String, GameBattler, GameBattler) -> Double,
               onCommonEvent: (Int) -> Void) {
        guard let it = item else { return }
        subject.result = ActionResult()
        target.result = ActionResult()
        var r = ActionResult()
        r.used = testApply(target, it)
        let hitRate = it.isPhysical ? Double(it.successRate) * 0.01 * subject.hit : Double(it.successRate) * 0.01
        r.missed = r.used && Self.rand(rng) >= hitRate
        let evaRate = it.isPhysical ? target.eva : it.isMagical ? target.mev : 0
        r.evaded = !r.missed && Self.rand(rng) < evaRate
        r.physical = it.isPhysical
        r.drain = it.damage.type == 5 || it.damage.type == 6
        target.result = r
        guard target.result.isHit else { return }
        if it.damage.type > 0 {
            let criRate = it.damage.critical ? subject.cri * (1 - target.cev) : 0
            target.result.critical = Self.rand(rng) < criRate
            let value = makeDamageValue(target, it, critical: target.result.critical, rng: rng, formula: formula)
            executeDamage(target, it, value)
        }
        for e in it.effects { applyEffect(target, it, e, rng: rng, onCommonEvent: onCommonEvent) }
        subject.gainSilentTp(Int((Double(it.tpGain) * subject.tcr).rounded(.down)))
    }

    static func rand(_ rng: RandomSource) -> Double { Double(rng.next(1_000_000)) / 1_000_000 }

    func testApply(_ target: GameBattler, _ it: UsableItem) -> Bool {
        if it.isForDeadFriend != target.isDead { return false }
        if it.damage.type > 0 || it.scope == 0 || !it.isForFriend { return true }
        // Healing-only items on friends: usable if they'd do something.
        if it.effects.contains(where: { $0.code == Effect.recoverHp }) && target.hp < target.mhp { return true }
        if it.effects.contains(where: { $0.code == Effect.recoverMp }) && target.mp < target.mmp { return true }
        if it.effects.contains(where: { $0.code == Effect.addState && !target.isStateAffected($0.dataId) }) { return true }
        if it.effects.contains(where: { $0.code == Effect.removeState && target.isStateAffected($0.dataId) }) { return true }
        if it.effects.contains(where: { [Effect.gainTp, Effect.addBuff, Effect.addDebuff, Effect.grow, Effect.learnSkill, Effect.commonEvent, Effect.special].contains($0.code) }) { return true }
        return it.effects.isEmpty
    }

    func makeDamageValue(_ target: GameBattler, _ it: UsableItem, critical: Bool, rng: RandomSource,
                         formula: (String, GameBattler, GameBattler) -> Double) -> Int {
        let sign: Double = [3, 4].contains(it.damage.type) ? -1 : 1
        var base = max(formula(it.damage.formula, subject, target), 0) * sign
        if base.isNaN { base = 0 }
        var value = base * elementRate(target, it)
        if it.isPhysical { value *= target.pdr }
        if it.isMagical { value *= target.mdr }
        if base < 0 { value *= target.rec }
        if critical { value *= 3 }
        let amp = Int(max(abs(value) * Double(it.damage.variance) / 100, 0).rounded(.down))
        let v = rng.next(amp + 1) + rng.next(amp + 1) - amp
        value = value >= 0 ? value + Double(v) : value - Double(v)
        if value > 0 && target.isGuarding { value /= 2 * target.grd }
        return Int(value.rounded())
    }

    func elementRate(_ target: GameBattler, _ it: UsableItem) -> Double {
        if it.damage.elementId < 0 {
            let els = subject.attackElements
            return els.isEmpty ? 1 : els.map { target.elementRate($0) }.max() ?? 1
        }
        return target.elementRate(it.damage.elementId)
    }

    func executeDamage(_ target: GameBattler, _ it: UsableItem, _ v: Int) {
        var value = v
        if value == 0 { target.result.critical = false }
        switch it.damage.type {
        case 1, 3, 5:
            if it.damage.type == 5 { value = min(target.hp, value) }
            target.result.success = true
            target.gainHp(-value)
            if value > 0 { target.onDamage(value) }
            if it.damage.type == 5 { subject.gainHp(value); subject.result = ActionResult() }
        case 2, 4, 6:
            if !(it.damage.type == 4) { value = min(target.mp, value) }
            if value != 0 { target.result.success = true }
            target.gainMp(-value)
            if it.damage.type == 6 { subject.gainMp(value); subject.result = ActionResult() }
        default: break
        }
    }

    func applyEffect(_ target: GameBattler, _ it: UsableItem, _ e: Effect, rng: RandomSource, onCommonEvent: (Int) -> Void) {
        switch e.code {
        case Effect.recoverHp:
            var v = (Double(target.mhp) * e.value1 + e.value2) * target.rec
            if !it.isSkill { v *= subject.pha }
            let n = Int(v.rounded(.down))
            if n != 0 { target.gainHp(n); target.result.success = true }
        case Effect.recoverMp:
            var v = (Double(target.mmp) * e.value1 + e.value2) * target.rec
            if !it.isSkill { v *= subject.pha }
            let n = Int(v.rounded(.down))
            if n != 0 { target.gainMp(n); target.result.success = true }
        case Effect.gainTp:
            let n = Int(e.value1.rounded(.down))
            if n != 0 { target.gainTp(n); target.result.success = true }
        case Effect.addState:
            let luk = max(1.0 + Double(subject.luk - target.luk) * 0.001, 0)
            if e.dataId == 0 {
                for (sid, rate) in subject.attackStates {
                    var chance = e.value1 * target.stateRate(sid) * rate * luk
                    if it.hitType == 0 { chance = e.value1 }
                    if Self.rand(rng) < chance { target.addState(sid); target.result.success = true }
                }
            } else {
                var chance = e.value1
                if it.hitType != 0 { chance *= target.stateRate(e.dataId) * luk }
                if Self.rand(rng) < chance { target.addState(e.dataId); target.result.success = true }
            }
        case Effect.removeState:
            if Self.rand(rng) < e.value1 { target.removeState(e.dataId); target.result.success = true }
        case Effect.addBuff: target.addBuff(e.dataId, Int(e.value1)); target.result.success = true
        case Effect.addDebuff:
            let chance = target.traitsPi(Trait.debuffRate, e.dataId) * max(1.0 + Double(subject.luk - target.luk) * 0.001, 0)
            if Self.rand(rng) < chance { target.addDebuff(e.dataId, Int(e.value1)); target.result.success = true }
        case Effect.removeBuff: if target.buffs[e.dataId] > 0 { target.removeBuff(e.dataId); target.result.success = true }
        case Effect.removeDebuff: if target.buffs[e.dataId] < 0 { target.removeBuff(e.dataId); target.result.success = true }
        case Effect.grow:
            target.paramPlusExtra[e.dataId] += Int(e.value1.rounded(.down)); target.refresh(); target.result.success = true
        case Effect.learnSkill:
            if let a = target as? GameActor { a.learnSkill(e.dataId); target.result.success = true }
        case Effect.commonEvent:
            onCommonEvent(e.dataId)
        default: break
        }
    }
}
