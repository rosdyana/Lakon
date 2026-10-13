import Foundation

/// Visual cue emitted by the battle for the renderer.
public struct BattleCue {
    public enum Kind {
        case damage(Int), recover(Int), mpDamage(Int), miss, critical, collapse, flash, shake, actorAct
        /// Play data/Animations.json entry `id` on the targets after `delay` frames (Spriteset_Base.createAnimation).
        case animation(Int, mirror: Bool, delay: Int)
        /// Side-view actor motion (Sprite_Actor.MOTIONS key) and weapon swing image (Weapons1-3 index).
        case motion(String)
        case weapon(Int)
        /// Enemy sprite effect: "whiten", "blink", "appear", "disappear".
        case effect(String)
    }
    public let id: Int
    public let kind: Kind
    /// Enemy index (>= 0) or actor index encoded as -(index + 1). nil = whole screen.
    public let target: Int?
    /// All targets, for animations shown once at the centre of several battlers.
    public let targets: [Int]
}

/// Turn-based battle, MZ default ("Turn Based") flow: party command → actor commands → actions ordered by speed →
/// turn end (regen, state turns) → repeat; victory/defeat/escape with rewards. Headless: the UI calls the
/// `command…` methods and reads `log`, `cues`, `enemies`, `members`.
public final class BattleManager {
    public enum Phase: Equatable { case start, input, turn, turnEnd, ending, done }
    public enum Outcome: Int { case win = 0, escape = 1, lose = 2, abort = 3 }

    unowned let world: GameWorld
    public let troopId: Int
    public let canEscape: Bool
    public let canLose: Bool
    public private(set) var enemies: [GameEnemy] = []
    public private(set) var phase: Phase = .start
    public private(set) var outcome: Outcome?
    public private(set) var log: [String] = []
    public private(set) var cues: [BattleCue] = []
    public private(set) var turnCount = 0
    public var preemptive = false
    public var surprise = false
    /// nil → party command (Fight/Escape) is showing; otherwise index into `members` being commanded.
    public private(set) var inputIndex: Int?
    public private(set) var waitingForPartyCommand = false
    public private(set) var rewards: (exp: Int, gold: Int, items: [(Int, Int)]) = (0, 0, [])
    public var battleback1: String = ""
    public var battleback2: String = ""
    /// Escaped successfully: side-view actors run off to the right (Sprite_Actor.retreat).
    public private(set) var escaped = false
    /// Frames since the battle started; animations keep the battle busy until `animationBusyUntil`.
    public private(set) var frame = 0
    var animationBusyUntil = 0
    public var sideView: Bool { world.project.system.optSideView }

    var queue: [Step] = []
    var waitCount = 0
    var cueCounter = 0
    var actionBattlers: [GameBattler] = []
    var subject: GameBattler?
    var escapeRatio = 0.5
    let interpreter = Interpreter()
    var pageDone: [Bool] = []
    var turnEndingCheck = false
    var onEnd: ((Outcome) -> Void)?

    enum Step { case log(String), clearLog, wait(Int), cue(BattleCue.Kind, Int?), cueAll(BattleCue.Kind, [Int]), se(AudioFile?), run(() -> Void), waitForAnimation }

    init(world: GameWorld, troopId: Int, canEscape: Bool, canLose: Bool) {
        self.world = world; self.troopId = troopId; self.canEscape = canEscape; self.canLose = canLose
        let troop = world.project.troop(troopId)
        enemies = (troop?.members ?? []).enumerated().compactMap { i, m in
            world.project.enemy(m.enemyId) == nil ? nil : GameEnemy(project: world.project, enemyId: m.enemyId, index: i, x: m.x, y: m.y, hidden: m.hidden)
        }
        for e in enemies { e.rng = world.rng }
        // Duplicate names get letters A, B, C… (Game_Troop.makeUniqueNames)
        let names = enemies.map { $0.data?.name ?? "" }
        for name in Set(names) where names.filter({ $0 == name }).count > 1 {
            var n = 0
            for e in enemies where e.data?.name == name { e.letter = " " + String(UnicodeScalar(65 + n)!); n += 1 }
        }
        pageDone = Array(repeating: false, count: troop?.pages.count ?? 0)
        let partyAgi = members.isEmpty ? 1 : members.map(\.agi).reduce(0, +) / members.count
        let troopAgi = enemies.isEmpty ? 1 : enemies.map(\.agi).reduce(0, +) / max(1, enemies.count)
        escapeRatio = 0.5 * Double(partyAgi) / Double(max(1, troopAgi))
    }

    public var members: [GameActor] { world.partyMembers }
    public var terms: Terms { world.project.system.terms }
    public var isBusy: Bool { !queue.isEmpty || waitCount > 0 || interpreter.isRunning || world.message != nil || frame < animationBusyUntil }
    public var inputActor: GameActor? { inputIndex.flatMap { $0 < members.count ? members[$0] : nil } }
    public var isFinished: Bool { phase == .done }

    // MARK: setup

    func start() {
        for b in members as [GameBattler] + enemies { b.onBattleStart(preemptive: preemptive) }
        for e in enemies where !e.hidden { push(.log(terms.message("emerge", e.name))) }
        if preemptive { push(.log(terms.message("preemptive", partyName))) }
        if surprise { push(.log(terms.message("surprise", partyName))) }
        push(.wait(20), .clearLog)
        world.audio.playSe(sound(7))
    }

    var partyName: String { members.first.map { terms.message("partyName", $0.name) } ?? "Party" }
    func sound(_ i: Int) -> AudioFile { i < world.project.system.sounds.count ? world.project.system.sounds[i] : AudioFile() }

    // MARK: frame update

    func update() {
        frame += 1
        if waitCount > 0 { waitCount -= 1; return }
        if world.message != nil { return }
        if interpreter.isRunning {
            interpreter.update(world)
            if interpreter.isRunning || world.message != nil { return }
        }
        while !queue.isEmpty {
            let s = queue.removeFirst()
            switch s {
            case .log(let t): log.append(t); if log.count > 6 { log.removeFirst() }; waitCount = 16; return
            case .clearLog: log = []
            case .wait(let n): waitCount = n; return
            case .cue(let k, let t): addCue(k, t.map { [$0] } ?? [])
            case .cueAll(let k, let ts): addCue(k, ts)
            case .waitForAnimation:
                if frame < animationBusyUntil { waitCount = animationBusyUntil - frame - 1; return }
            case .se(let f): if let f { world.audio.playSe(f) }
            case .run(let f): f()
            }
        }
        if phase != .ending && phase != .done {
            if setupBattleEvent() { return }
            if checkBattleEnd() { return }
        }
        switch phase {
        case .start:
            start()
            phase = .input
            if surprise { surprise = false; startTurn() } else { startInput() }
        case .input:
            break // waiting for the UI
        case .turn: processTurn()
        case .turnEnd: endTurn()
        case .ending:
            phase = .done
            finish()
        case .done: break
        }
    }

    func push(_ steps: Step...) { queue.append(contentsOf: steps) }

    func addCue(_ k: BattleCue.Kind, _ targets: [Int]) {
        cueCounter += 1
        cues.append(BattleCue(id: cueCounter, kind: k, target: targets.first, targets: targets))
        if cues.count > 60 { cues.removeFirst(20) }
        if case .animation(let id, _, let delay) = k, let a = world.project.animation(id) {
            animationBusyUntil = max(animationBusyUntil, frame + delay + a.playFrames)
        }
    }

    // MARK: input

    func startInput() {
        phase = .input
        for e in enemies where e.isAlive {
            e.turnCount = turnCount + 1
            e.makeActions(rng: world.rng, partyLevel: members.map(\.level).max() ?? 1, switches: { [unowned self] in world.state.switchValue($0) })
        }
        for a in members { a.actions = []; a.actionState = a.canInput ? "undecided" : "waiting" }
        if preemptive { preemptive = false }
        waitingForPartyCommand = members.contains(where: \.canInput)
        inputIndex = nil
        if !waitingForPartyCommand { startTurn() }
    }

    public func commandFight() {
        guard phase == .input, waitingForPartyCommand else { return }
        waitingForPartyCommand = false
        selectNextActor(from: -1)
    }

    public func commandEscape() {
        guard phase == .input, waitingForPartyCommand, canEscape else { return }
        waitingForPartyCommand = false
        world.audio.playSe(sound(8))
        push(.log(terms.message("escapeStart", partyName)))
        let success = preemptive || Double(world.rng.next(1000)) / 1000 < escapeRatio
        for (i, a) in members.enumerated() where a.canMove { push(.cue(.motion("escape"), -(i + 1))) }
        if success {
            escaped = true
            push(.wait(30), .run { [unowned self] in endBattle(.escape) })
        } else {
            escapeRatio += 0.1
            push(.log(terms.message("escapeFailure")), .wait(20), .clearLog)
            for a in members { a.actions = [] }
            startTurn()
        }
    }

    func selectNextActor(from i: Int) {
        var n = i + 1
        while n < members.count, !members[n].canInput { n += 1 }
        if n < members.count { inputIndex = n; members[n].actionState = "inputting" } else { inputIndex = nil; startTurn() }
    }

    /// Back: previous actor, or the party command.
    public func cancelInput() {
        guard phase == .input, let i = inputIndex else { return }
        var n = i - 1
        while n >= 0, !members[n].canInput { n -= 1 }
        members[i].actionState = "undecided"
        if n >= 0 { members[n].actions = []; members[n].actionState = "inputting"; inputIndex = n } else { inputIndex = nil; waitingForPartyCommand = true }
    }

    public func commandAttack(target: Int) { submit(GameAction(subject: currentInputActor, skillId: currentInputActor.attackSkill), target) }
    public func commandGuard() { submit(GameAction(subject: currentInputActor, skillId: GameBattler.guardSkillId), -1) }
    public func commandSkill(_ id: Int, target: Int) { submit(GameAction(subject: currentInputActor, skillId: id), target) }
    public func commandItem(_ id: Int, target: Int) { submit(GameAction(subject: currentInputActor, itemId: id), target) }

    var currentInputActor: GameActor { inputActor ?? members[0] }

    func submit(_ a: GameAction, _ target: Int) {
        guard phase == .input, let i = inputIndex else { return }
        a.targetIndex = target
        members[i].actions = [a]
        // Extra actions from Action Times+ repeat the chosen action (simplification of MZ's per-action input).
        for _ in 1..<max(1, members[i].numActions) { let x = GameAction(subject: a.subject, skillId: a.skillId); x.itemId = a.itemId; x.targetIndex = target; members[i].actions.append(x) }
        members[i].actionState = "waiting"
        selectNextActor(from: i)
    }

    public func usableSkills(_ a: GameActor) -> [Skill] {
        a.skills.filter { s in a.addedSkillTypes.contains(s.stypeId) || s.stypeId == 0 }
    }
    public func usableItems() -> [Item] {
        world.state.items.keys.sorted().compactMap { world.project.item($0) }.filter { $0.isBattleUsable && $0.itypeId == 1 }
    }

    // MARK: turn

    func startTurn() {
        phase = .turn
        turnCount += 1
        for (i, p) in (world.project.troop(troopId)?.pages ?? []).enumerated() where p.span == 1 { pageDone[i] = false }
        // Auto-battle / confused actors attack at random.
        for a in members where a.canMove && a.actions.isEmpty {
            let act = GameAction(subject: a, skillId: a.attackSkill); act.targetIndex = -1; a.actions = [act]
        }
        for a in members where a.actionState != "waiting" && a.canMove { a.actionState = "waiting" }
        actionBattlers = (members as [GameBattler] + enemies).filter { $0.isAlive && !$0.actions.isEmpty }
        for b in actionBattlers { b.speed = b.actions.map { $0.speed(world.rng) }.min() ?? 0 }
        actionBattlers.sort { $0.speed > $1.speed }
        subject = nil
    }

    func processTurn() {
        if subject == nil {
            while let b = actionBattlers.first, !(b.isAlive && b.canMove && !b.actions.isEmpty) { actionBattlers.removeFirst() }
            guard !actionBattlers.isEmpty else { phase = .turnEnd; turnEndingCheck = true; return }
            subject = actionBattlers.removeFirst()
        }
        guard let s = subject else { return }
        guard let action = s.actions.first else { s.result = ActionResult(); subject = nil; return }
        s.actions.removeFirst()
        let last = s.actions.isEmpty
        perform(action)
        if last { subject = nil }
    }

    /// BattleManager.startAction + Window_BattleLog.startAction: step forward, motion, animation, message, then wait
    /// for the animation before the results (BattleManager.isBusy includes Spriteset_Battle.isAnimationPlaying).
    func perform(_ action: GameAction) {
        let s = action.subject
        guard let item = action.item, s.canUse(item, inBattle: true) || action.forcing else { return }
        if let sk = item as? Skill { s.paySkillCost(sk) }
        if let it = item as? Item, it.consumable { world.state.gain(kind: 1, id: it.id, -1) }
        let friends: [GameBattler] = s.isActor ? members : enemies
        let opponents: [GameBattler] = s.isActor ? enemies : members
        let targets = action.makeTargets(friends: friends, opponents: opponents, rng: world.rng)
        // performActionStart
        if !action.isGuard { s.actionState = "acting" }
        if let e = s as? GameEnemy { push(.cue(.effect("whiten"), e.index)) }
        if sideView && s.isActor && !action.isGuard { push(.wait(12)) }          // waitForMovement (stepForward is 12 frames)
        // performAction
        if let a = s as? GameActor, let idx = memberIndex(a) {
            let t = -(idx + 1)
            push(.cue(.actorAct, idx))
            if action.isAttack {
                if let m = a.attackMotion {
                    push(.cue(.motion(["thrust", "swing", "missile"][safe: m.type] ?? "thrust"), t))
                    if m.weaponImageId > 0 { push(.cue(.weapon(m.weaponImageId), t)) }
                }
            } else if action.isGuard { push(.cue(.motion("guard"), t)) }
            else if action.isMagicSkill { push(.cue(.motion("spell"), t)) }
            else if action.isSkill { push(.cue(.motion("skill"), t)) }
            else { push(.cue(.motion("item"), t)) }
        }
        // showAnimation
        let animated = showAnimation(s, targets, item.animationId)
        if item.animationId < 0 && !s.isActor { push(.se(sound(9))) }            // showEnemyAttackAnimation
        else if !animated && !action.isAttack { push(.se(sound(item.isSkill ? 23 : 22))) }
        // displayAction
        push(.log(actionMessage(s, item)))
        if let sk = item as? Skill, !sk.message2.isEmpty { push(.log(sk.message2.replacingOccurrences(of: "%1", with: s.name).replacingOccurrences(of: "%2", with: sk.name))) }
        push(.waitForAnimation)
        for t in targets {
            push(.run { [unowned self] in
                action.apply(to: t, rng: self.world.rng, formula: { [unowned self] f, a, b in self.world.script.evalFormula(f, a: a, b: b) },
                             onCommonEvent: { [unowned self] id in self.world.reserveCommonEvent(id) })
                queue.insert(contentsOf: resultSteps(t), at: 0)
            })
        }
        push(.run { [unowned self] in
            s.removeStatesAuto(1)
            for e in enemies where e.isDead && !collapsed.contains(e.index) { collapsed.insert(e.index) }
        }, .wait(12), .clearLog, .run { if s.actions.isEmpty { s.actionState = "done" } })
    }

    /// Window_BattleLog.showAnimation: -1 = normal attack (actor: weapon animation; enemy: just the attack SE).
    @discardableResult
    func showAnimation(_ s: GameBattler, _ targets: [GameBattler], _ id: Int) -> Bool {
        if id < 0 { return (s as? GameActor).map { showNormalAnimation(targets, $0.attackAnimationId, mirror: false) } ?? false }
        return showNormalAnimation(targets, id, mirror: false)
    }

    /// Spriteset_Base.createAnimation: per-target sprites start 8 frames in, each next target 12 frames later;
    /// animations on actors are mirrored (animationShouldMirror).
    @discardableResult
    func showNormalAnimation(_ targets: [GameBattler], _ id: Int, mirror: Bool) -> Bool {
        guard let anim = world.project.animation(id), !targets.isEmpty else { return false }
        let ids = targets.compactMap(cueTarget)
        let m = targets.first?.isActor == true ? !mirror : mirror
        if anim.isForEach {
            for (i, t) in ids.enumerated() { push(.cue(.animation(id, mirror: m, delay: AnimationData.baseDelay + i * AnimationData.nextDelay), t)) }
        } else {
            push(.cueAll(.animation(id, mirror: m, delay: AnimationData.baseDelay), ids))
        }
        return true
    }
    var collapsed = Set<Int>()

    func memberIndex(_ b: GameBattler) -> Int? { members.firstIndex { $0 === b } }
    func cueTarget(_ b: GameBattler) -> Int? {
        if let e = b as? GameEnemy { return e.index }
        return memberIndex(b).map { -($0 + 1) }
    }

    func actionMessage(_ s: GameBattler, _ item: UsableItem) -> String {
        if let sk = item as? Skill {
            let m = sk.message1.isEmpty ? "%1 uses %2!" : sk.message1
            return m.contains("%1") ? m.replacingOccurrences(of: "%1", with: s.name).replacingOccurrences(of: "%2", with: sk.name) : s.name + m
        }
        return terms.message("useItem", s.name, item.name)
    }

    /// Window_BattleLog.displayActionResults
    func resultSteps(_ t: GameBattler) -> [Step] {
        let r = t.result
        var out: [Step] = []
        let ct = cueTarget(t)
        let actor = t.isActor
        guard r.used else { return out }
        if r.missed || r.evaded {
            out.append(.cue(.miss, ct))
            if r.evaded && actor { out.append(.cue(.motion("evade"), ct)) }
            out.append(.se(sound(r.evaded ? 18 : 17)))
            out.append(.log(r.evaded ? terms.message("evasion", t.name) : terms.message(actor ? "actorNoHit" : "enemyNoHit", t.name)))
            return out
        }
        if r.critical { out.append(.log(terms.message(actor ? "criticalToActor" : "criticalToEnemy"))); out.append(.cue(.critical, ct)) }
        if r.hpAffected {
            let hpName = terms.basic[3]
            if r.hpDamage > 0 && !r.drain {
                out.append(.se(sound(actor ? 14 : 10)))
                out.append(.cue(.damage(r.hpDamage), ct))
                if actor { out.append(sideView ? .cue(.motion("damage"), ct) : .cue(.shake, nil)) }
                else { out.append(.cue(.effect("blink"), ct)) }
                out.append(.log(terms.message(actor ? "actorDamage" : "enemyDamage", t.name, String(r.hpDamage))))
            } else if r.hpDamage > 0 && r.drain {
                out.append(.cue(.damage(r.hpDamage), ct))
                out.append(.log(terms.message(actor ? "actorDrain" : "enemyDrain", t.name, hpName, String(r.hpDamage))))
            } else if r.hpDamage < 0 {
                out.append(.se(sound(16)))
                out.append(.cue(.recover(-r.hpDamage), ct))
                out.append(.log(terms.message(actor ? "actorRecovery" : "enemyRecovery", t.name, hpName, String(-r.hpDamage))))
            } else if r.mpDamage == 0 && r.addedStates.isEmpty && r.removedStates.isEmpty {
                out.append(.log(terms.message(actor ? "actorNoDamage" : "enemyNoDamage", t.name)))
            }
        }
        if r.mpDamage != 0 {
            let mpName = terms.basic[5]
            out.append(.cue(.mpDamage(r.mpDamage), ct))
            out.append(.log(terms.message(r.mpDamage > 0 ? (actor ? "actorLoss" : "enemyLoss") : (actor ? "actorGain" : "enemyGain"), t.name, mpName, String(abs(r.mpDamage)))))
        }
        for sid in r.addedStates {
            guard let st = world.project.state(sid) else { continue }
            let m = actor ? st.message1 : st.message2
            if !m.isEmpty { out.append(.log(m.contains("%1") ? m.replacingOccurrences(of: "%1", with: t.name) : t.name + m)) }
            if sid == GameBattler.deathStateId {
                out.append(.cue(.collapse, ct))
                out.append(.se(sound(actor ? 15 : 11)))
            }
        }
        for sid in r.removedStates where sid != GameBattler.deathStateId {
            if let m = world.project.state(sid)?.message4, !m.isEmpty { out.append(.log(m.contains("%1") ? m.replacingOccurrences(of: "%1", with: t.name) : t.name + m)) }
        }
        for p in r.addedBuffs { out.append(.log(terms.message("buffAdd", t.name, terms.params[p]))) }
        for p in r.addedDebuffs { out.append(.log(terms.message("debuffAdd", t.name, terms.params[p]))) }
        if !r.success && !r.hpAffected && r.mpDamage == 0 { out.append(.log(terms.message("actionFailure", t.name))) }
        return out
    }

    func endTurn() {
        turnEndingCheck = true
        if setupBattleEvent() { return }
        turnEndingCheck = false
        for b in members as [GameBattler] + enemies {
            b.onTurnEnd(slipDeath: world.project.system.optSlipDeath || !b.isActor)
            if b.result.hpAffected && b.result.hpDamage > 0 { push(.cue(.damage(b.result.hpDamage), cueTarget(b))) }
            if b.isDead, b.result.addedStates.contains(GameBattler.deathStateId) { push(.cue(.collapse, cueTarget(b))) }
        }
        for (i, p) in (world.project.troop(troopId)?.pages ?? []).enumerated() where p.span == 1 { pageDone[i] = false }
        startInput()
    }

    // MARK: troop events (Game_Troop.setupBattleEvent)

    func setupBattleEvent() -> Bool {
        guard !interpreter.isRunning, let pages = world.project.troop(troopId)?.pages else { return false }
        for (i, page) in pages.enumerated() where !pageDone[i] && meets(page.conditions) {
            interpreter.setup(page.list, eventId: 0, mapId: world.state.mapId)
            if page.span <= 1 { pageDone[i] = true }
            return true
        }
        return false
    }

    func meets(_ c: TroopPageConditions) -> Bool {
        if !c.turnEnding && !c.turnValid && !c.enemyValid && !c.actorValid && !c.switchValid { return false }
        if c.turnEnding && !turnEndingCheck { return false }
        if c.turnValid {
            let n = turnCount, a = c.turnA, b = c.turnB
            if b == 0 && n != a { return false }
            if b > 0 && (n < 1 || n < a || n % b != a % b) { return false }
        }
        if c.enemyValid {
            guard c.enemyIndex < enemies.count, enemies[c.enemyIndex].hpRate * 100 <= Double(c.enemyHp) else { return false }
        }
        if c.actorValid {
            guard let a = world.actor(c.actorId), a.hpRate * 100 <= Double(c.actorHp) else { return false }
        }
        if c.switchValid && !world.state.switchValue(c.switchId) { return false }
        return true
    }

    // MARK: end

    func checkBattleEnd() -> Bool {
        guard phase != .start else { return false }
        if members.allSatisfy({ !$0.isAlive }) { processDefeat(); return true }
        if enemies.allSatisfy({ !$0.isAlive }) { processVictory(); return true }
        return false
    }

    func processVictory() {
        phase = .ending
        outcome = .win
        for b in members { b.removeBattleStatesNow() }
        for (i, a) in members.enumerated() {
            a.actionState = "done"
            if a.canMove { push(.cue(.motion("victory"), -(i + 1))) }
        }
        world.audio.playMe(world.state.victoryMe ?? world.project.system.victoryMe)
        let dead = enemies.filter(\.isDead)
        let exp = dead.reduce(0) { $0 + $1.exp }
        let goldRate = world.partyHasAbility(4) ? 2 : 1
        let gold = dead.reduce(0) { $0 + $1.gold } * goldRate
        var drops: [(Int, Int)] = []
        let dropRate = world.partyHasAbility(5) ? 2.0 : 1.0
        for e in dead { for d in e.data?.dropItems ?? [] where d.kind > 0 && Double(world.rng.next(1000)) / 1000 * Double(d.denominator) < dropRate { drops.append((d.kind, d.dataId)) } }
        rewards = (exp, gold, drops)
        push(.clearLog, .log(terms.message("victory", partyName)))
        if exp > 0 { push(.log(terms.message("obtainExp", String(exp), terms.basic[8]))) }
        if gold > 0 { push(.log(terms.message("obtainGold", String(gold)).replacingOccurrences(of: "\\G", with: " " + world.project.system.currencyUnit))) }
        world.state.gainGold(gold)
        for (k, id) in drops {
            world.state.gain(kind: k, id: id, 1)
            let n = k == 1 ? world.project.item(id)?.name : k == 2 ? world.project.weapon(id)?.name : world.project.armor(id)?.name
            push(.log(terms.message("obtainItem", n ?? "?")))
        }
        for a in members {
            let r = a.gainExp(exp)
            if r.levels > 0 {
                push(.log(terms.message("levelUp", a.name, terms.basic[0], String(a.level))))
                for sid in r.newSkills { if let s = world.project.skill(sid) { push(.log(terms.message("obtainSkill", s.name))) } }
            }
        }
        push(.wait(90))
    }

    func processDefeat() {
        phase = .ending
        outcome = .lose
        world.audio.playMe(world.project.system.defeatMe)
        push(.clearLog, .log(terms.message("defeat", partyName)), .wait(90))
        if canLose { push(.run { [unowned self] in for a in members where a.isDead { a.removeState(GameBattler.deathStateId); a.setHp(1) } }) }
    }

    func endBattle(_ o: Outcome) {
        outcome = o
        phase = .ending
    }

    func replaceEnemy(_ old: GameEnemy, with new: GameEnemy) {
        if let i = enemies.firstIndex(where: { $0 === old }) { enemies[i] = new; push(.cue(.effect("whiten"), new.index)) }
    }
    /// Show Battle Animation (337): enemyIndex < 0 = the whole troop.
    func cueAnimation(enemyIndex: Int, animationId: Int) {
        showNormalAnimation(enemies.filter { $0.isAlive && (enemyIndex < 0 || $0.index == enemyIndex) }, animationId, mirror: false)
    }
    /// Force Action (339): the battler acts immediately with the given skill.
    func forceAction(isEnemy: Bool, id: Int, skillId: Int, target: Int) {
        let subject: GameBattler? = isEnemy ? enemies[safe: id] : world.actor(id)
        guard let s = subject, s.isAlive else { return }
        let a = GameAction(subject: s, skillId: skillId)
        a.forcing = true
        a.targetIndex = target < 0 ? -1 : target
        perform(a)
    }

    public func abort() { outcome = .abort; queue = []; phase = .ending }

    func finish() {
        for b in members { b.onBattleEnd() }
        let o = outcome ?? .abort
        onEnd?(o)
    }
}

extension GameBattler {
    func removeBattleStatesNow() { removeBattleStates() }
}
