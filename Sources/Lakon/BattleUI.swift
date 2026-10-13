import AppKit
import LakonCore
import LakonRender
import SpriteKit

/// Scene_Battle (front view): battlebacks, enemy sprites, battle log, party/actor command windows,
/// skill/item lists, target selection, status window, damage popups, collapse and shake effects.
final class BattleController {
    unowned let scene: GameScene
    enum Sub: Equatable {
        case party, actor
        case skills(stype: Int)
        case items
        case enemyTarget(kind: Kind)
        case actorTarget(kind: Kind)
    }
    enum Kind: Equatable { case attack, skill(Int), item(Int) }

    var sub: Sub = .party
    var cursors: [String: Int] = [:]
    var lastCue = 0
    var popups: [(text: String, color: NSColor, x: CGFloat, y: CGFloat, age: Int, id: Int)] = []
    var actorFlash: [Int: Int] = [:]
    var shake = 0
    var svActors: [SVActorSprite] = (0..<4).map { SVActorSprite(index: $0) }
    var enemyFx: [Int: EnemySpriteEffect] = [:]
    var animations: [AnimationPlayback] = []
    var selectionCount = 0
    var lastInputActor: Int?

    init(scene: GameScene) { self.scene = scene }

    var world: GameWorld { scene.world }
    var battle: BattleManager? { world.battle }
    var ui: SceneUI { scene.ui }
    var terms: Terms { scene.project.system.terms }

    func cur(_ k: String) -> Int { cursors[k] ?? 0 }
    func move(_ k: String, _ n: Int, _ u: UIInput, columns: Int = 1) {
        var c = cur(k)
        if SceneUI.move(&c, count: n, u, columns: columns) { world.playSystemSound(0) }
        cursors[k] = min(c, max(0, n - 1))
    }

    func actorCommands(_ a: GameActor) -> [(String, Sub?)] {
        var out: [(String, Sub?)] = [(terms.commands[2], .enemyTarget(kind: .attack))]
        for t in a.addedSkillTypes { out.append((scene.project.system.skillTypes[safe: t] ?? "Skill", .skills(stype: t))) }
        out.append((terms.commands[3], nil))
        out.append((terms.commands[4], .items))
        return out
    }

    // MARK: input → returns true if it consumed the input

    func step(_ u: UIInput) -> Bool {
        guard let b = battle, b.phase == .input, !b.isBusy else { return false }
        if b.waitingForPartyCommand {
            if sub != .party { sub = .party }
            move("party", 2, u)
            if u.ok {
                if cur("party") == 0 { world.playSystemSound(1); b.commandFight(); sub = .actor; cursors["actor"] = 0 }
                else if b.canEscape { world.playSystemSound(1); b.commandEscape() } else { world.playSystemSound(3) }
            }
            return true
        }
        guard let a = b.inputActor else { return true }
        if lastInputActor != b.inputIndex { lastInputActor = b.inputIndex; sub = .actor; cursors["actor"] = 0 }
        switch sub {
        case .party: sub = .actor
        case .actor:
            let cmds = actorCommands(a)
            move("actor", cmds.count, u)
            if u.cancel { world.playSystemSound(2); b.cancelInput(); lastInputActor = b.inputIndex; if b.waitingForPartyCommand { sub = .party } }
            if u.ok {
                world.playSystemSound(1)
                if let next = cmds[cur("actor")].1 {
                    if case .enemyTarget = next { cursors["enemy"] = firstAliveEnemy() }
                    sub = next; cursors["list"] = 0
                } else { b.commandGuard(); sub = .actor }
            }
        case .skills(let stype):
            let skills = b.usableSkills(a).filter { $0.stypeId == stype }
            move("list", skills.count, u, columns: 2)
            if u.cancel { world.playSystemSound(2); sub = .actor }
            if u.ok, let s = skills[safe: cur("list")] {
                guard a.canUse(s, inBattle: true) else { world.playSystemSound(3); return true }
                world.playSystemSound(1)
                choose(.skill(s.id), item: s, b)
            }
        case .items:
            let items = b.usableItems()
            move("list", items.count, u, columns: 2)
            if u.cancel { world.playSystemSound(2); sub = .actor }
            if u.ok, let it = items[safe: cur("list")] { world.playSystemSound(1); choose(.item(it.id), item: it, b) }
        case .enemyTarget(let kind):
            let alive = b.enemies.indices.filter { b.enemies[$0].isAlive }
            if u.right || u.down { cursors["enemy"] = alive.first { $0 > cur("enemy") } ?? alive.first ?? 0; world.playSystemSound(0) }
            if u.left || u.up { cursors["enemy"] = alive.last { $0 < cur("enemy") } ?? alive.last ?? 0; world.playSystemSound(0) }
            if u.cancel { world.playSystemSound(2); sub = back(kind) }
            if u.ok { world.playSystemSound(1); submit(kind, target: cur("enemy"), b) }
        case .actorTarget(let kind):
            move("ally", b.members.count, u)
            if u.cancel { world.playSystemSound(2); sub = back(kind) }
            if u.ok { world.playSystemSound(1); submit(kind, target: cur("ally"), b) }
        }
        return true
    }

    func back(_ k: Kind) -> Sub {
        switch k {
        case .attack: return .actor
        case .skill(let id): return .skills(stype: scene.project.skill(id)?.stypeId ?? 1)
        case .item: return .items
        }
    }

    func choose(_ k: Kind, item: UsableItem, _ b: BattleManager) {
        if item.needsTargetSelection {
            if item.isForOpponent { cursors["enemy"] = firstAliveEnemy(); sub = .enemyTarget(kind: k) }
            else { cursors["ally"] = 0; sub = .actorTarget(kind: k) }
        } else { submit(k, target: -1, b) }
    }

    func submit(_ k: Kind, target: Int, _ b: BattleManager) {
        switch k {
        case .attack: b.commandAttack(target: target)
        case .skill(let id): b.commandSkill(id, target: target)
        case .item(let id): b.commandItem(id, target: target)
        }
        sub = .actor; cursors["actor"] = 0; lastInputActor = b.inputIndex
    }

    func firstAliveEnemy() -> Int { battle?.enemies.firstIndex { $0.isAlive } ?? 0 }

    // MARK: render

    var sideView: Bool { scene.project.system.optSideView }

    /// Feet position (SpriteKit coordinates) and height of a cue target: enemy index ≥ 0, actor −(index + 1).
    func targetFrame(_ t: Int, _ b: BattleManager) -> (x: CGFloat, y: CGFloat, h: CGFloat)? {
        let H = GameScene.H
        if t >= 0 {
            guard let e = b.enemies.first(where: { $0.index == t }) else { return nil }
            let h = enemyTexture(e)?.size().height ?? 100
            return (CGFloat(e.screenX), H - CGFloat(e.screenY), h)
        }
        let ai = -t - 1
        if sideView, ai < svActors.count { return (CGFloat(svActors[ai].x), H - CGFloat(svActors[ai].y), 64) }
        return (300, 142 - CGFloat(ai) * 40 + 4, 40)     // front view: the actor's status row
    }

    func enemyTexture(_ e: GameEnemy) -> SKTexture? {
        (sideView ? scene.texture("sv_enemies", e.battlerName) : nil) ?? scene.texture("enemies", e.battlerName)
    }

    func render() {
        guard let b = battle else { return }
        let W = GameScene.W, H = GameScene.H
        consumeCues(b)
        let sx = shake > 0 ? CGFloat(Int.random(in: -6...6)) : 0
        if shake > 0 { shake -= 1 }
        // Battlebacks (1000×740, centred like MZ's Spriteset_Battle).
        let bb1 = scene.texture("battlebacks1", b.battleback1), bb2 = scene.texture("battlebacks2", b.battleback2)
        if bb1 == nil && bb2 == nil {
            ui.rect("b.bg", CGRect(x: 0, y: 0, width: W, height: H), color: NSColor(red: 0.18, green: 0.22, blue: 0.3, alpha: 1), z: -20)
        }
        ui.sprite("b.bb1", bb1, center: CGPoint(x: W / 2 + sx, y: H / 2), size: CGSize(width: 1000, height: 740), z: -19)
        ui.sprite("b.bb2", bb2, center: CGPoint(x: W / 2 + sx, y: H / 2), size: CGSize(width: 1000, height: 740), z: -18)

        // Animations first: their target flashes and "hide target" apply to the battler sprites drawn below.
        var targetFlash: [Int: [Double]] = [:], hidden = Set<Int>()
        for a in animations {
            for se in a.update() { scene.audio.handle([.playSe(se)]) }
            for t in a.targets {
                if a.flashColor[3] > 0 { targetFlash[t] = a.flashColor }
                if a.hidingTargets { hidden.insert(t) }
            }
        }
        animations.removeAll { !$0.isPlaying }
        selectionCount += 1

        // Enemies (Sprite_Enemy): appear / whiten / blink / collapse effects.
        let targeting: Int? = { if case .enemyTarget = sub, b.phase == .input, !b.isBusy { return cur("enemy") }; return nil }()
        for e in b.enemies {
            let i = e.index
            guard let tex = enemyTexture(e) else {
                if e.isAlive { ui.label("b.en\(i)", e.name, CGPoint(x: CGFloat(e.screenX) + sx, y: H - CGFloat(e.screenY) + 40), size: 24, align: .center, z: 2) }
                continue
            }
            let fx = enemyFx[i] ?? { let f = EnemySpriteEffect(alive: e.isAlive, bitmapHeight: Int(tex.size().height)); enemyFx[i] = f; return f }()
            if e.isDead && fx.appeared && !fx.isEffecting {      // killed without a collapse cue (e.g. Change Enemy HP)
                fx.start(["collapse", "bossCollapse", "instantCollapse"][safe: e.collapseType] ?? "collapse")
            }
            fx.update(alive: e.isAlive, hidden: e.hidden)
            if fx.wantsBossSound { world.playSystemSound(13) }
            if fx.opacity <= 0 || hidden.contains(i) { continue }
            var drawTex = tex, size = tex.size()
            if fx.bossCollapseHeight >= 0 {
                let h = CGFloat(max(1, fx.bossCollapseHeight))
                drawTex = SKTexture(rect: CGRect(x: 0, y: 1 - h / size.height, width: 1, height: h / size.height), in: tex)
                size.height = h
            }
            let p = CGPoint(x: CGFloat(e.screenX) + sx + CGFloat(fx.shake), y: H - CGFloat(e.screenY))
            let anchor = CGPoint(x: 0.5, y: 0)
            ui.sprite("b.e\(i)", drawTex, center: p, size: size, z: 1 + CGFloat(e.screenY) / 1000, alpha: CGFloat(fx.opacity / 255), anchor: anchor,
                      blend: fx.additive ? .add : .alpha)
            var flashRGBA = fx.blendColor
            if let f = targetFlash[i], f[3] > flashRGBA[3] { flashRGBA = f }
            if targeting == i && selectionCount % 30 < 15 { flashRGBA = [255, 255, 255, max(64, flashRGBA[3])] }
            ui.flashSprite("b.ef\(i)", drawTex, center: p, size: size, z: 1.01 + CGFloat(e.screenY) / 1000, anchor: anchor, rgba: flashRGBA)
            if targeting == i {
                ui.label("b.tn", e.name, CGPoint(x: CGFloat(e.screenX), y: H - CGFloat(e.screenY) + tex.size().height + 10), size: 22, align: .center, bold: true, z: 30)
            }
        }

        // Side-view actors (Sprite_Actor): shadow, body, weapon, state overlay.
        if sideView { drawActors(b, targetFlash: targetFlash, hidden: hidden, sx: sx) }

        // Animation cells.
        drawAnimations(b)

        // Battle log (Window_BattleLog): dark band at the top.
        if !b.log.isEmpty {
            let lh: CGFloat = 34
            let r = CGRect(x: 8, y: H - 8 - CGFloat(b.log.count) * lh - 16, width: W - 16, height: CGFloat(b.log.count) * lh + 16)
            ui.rect("b.logbg", r, color: NSColor(white: 0, alpha: 0.55), z: 10, corner: 6)
            for (i, l) in b.log.enumerated() {
                ui.richText("b.log\(i)", l, CGPoint(x: 26, y: r.maxY - 34 - CGFloat(i) * lh), size: 22, z: 11)
            }
        }

        drawStatus(b)
        drawCommands(b)
        drawPopups()
    }

    func drawActors(_ b: BattleManager, targetFlash: [Int: [Double]], hidden: Set<Int>, sx: CGFloat) {
        let H = GameScene.H
        let members = b.members
        let ended = b.phase == .ending || b.phase == .done
        for (i, s) in svActors.enumerated() {
            s.setActor(i < members.count ? members[i] : nil)
            guard i < members.count else { continue }
            let a = members[i]
            s.update(escaped: b.escaped, battleEnded: ended)
            let t = -(i + 1)
            let feet = CGPoint(x: CGFloat(s.x) + sx, y: H - CGFloat(s.y))
            let z = 2 + CGFloat(s.y) / 1000
            if let sh = scene.texture("system", "Shadow2") { ui.sprite("b.ash\(i)", sh, center: CGPoint(x: feet.x, y: feet.y + 2), z: z - 0.01) }
            if hidden.contains(t) { continue }
            if let sheet = scene.sheet("sv_actors", a.battlerName) {
                let cw = sheet.width / 9, ch = sheet.height / 6, f = s.frame
                let tex = scene.subTexture("sv_actors", a.battlerName, CGRect(x: f.col * cw, y: f.row * ch, width: cw, height: ch))
                ui.sprite("b.a\(i)", tex, center: feet, size: CGSize(width: cw, height: ch), z: z, anchor: CGPoint(x: 0.5, y: 0))
                var flash = targetFlash[t] ?? [0, 0, 0, 0]
                if b.inputIndex == i && b.phase == .input, case .actorTarget = sub, cur("ally") == i, selectionCount % 30 < 15 { flash = [255, 255, 255, 64] }
                ui.flashSprite("b.af\(i)", tex, center: feet, size: CGSize(width: cw, height: ch), z: z + 0.001, anchor: CGPoint(x: 0.5, y: 0), rgba: flash)
            }
            if s.weaponImageId > 0 {
                let page = (s.weaponImageId - 1) / 12 + 1, idx = (s.weaponImageId - 1) % 12
                let col = (idx / 6) * 3 + s.weaponPattern, row = idx % 6
                if scene.sheet("system", "Weapons\(page)") != nil {
                    let tex = scene.subTexture("system", "Weapons\(page)", CGRect(x: col * 96, y: row * 64, width: 96, height: 64))
                    ui.sprite("b.aw\(i)", tex, center: CGPoint(x: feet.x - 16, y: feet.y), size: CGSize(width: 96, height: 64), z: z - 0.005, anchor: CGPoint(x: 0.5, y: 0))
                }
            }
            let overlay = a.stateOverlayIndex
            if overlay > 0, scene.sheet("system", "States") != nil {
                let pattern = (selectionCount / 8) % 8
                let tex = scene.subTexture("system", "States", CGRect(x: pattern * 96, y: (overlay - 1) * 96, width: 96, height: 96))
                ui.sprite("b.ao\(i)", tex, center: feet, size: CGSize(width: 96, height: 96), z: z + 0.002, anchor: CGPoint(x: 0.5, y: 0))
            }
        }
    }

    func drawAnimations(_ b: BattleManager) {
        let W = GameScene.W, H = GameScene.H
        for (n, a) in animations.enumerated() where a.started {
            let d = a.animation
            // Origin in SpriteKit coordinates (Sprite_AnimationMV.updatePosition / Sprite_Animation.targetPosition).
            var ox = W / 2, oy = H / 2
            let frames = a.targets.compactMap { targetFrame($0, b) }
            if !d.isScreen, !frames.isEmpty {
                ox = frames.map(\.x).reduce(0, +) / CGFloat(frames.count)
                let ys = frames.map { f -> CGFloat in
                    if d.isMV { return d.position == 0 ? f.y + f.h : d.position == 1 ? f.y + f.h / 2 : f.y }
                    return d.alignBottom ? f.y : f.y + f.h / 2
                }
                oy = ys.reduce(0, +) / CGFloat(ys.count)
            }
            if !d.isMV { ox += CGFloat(d.offsetX); oy -= CGFloat(d.offsetY) }
            for (k, c) in a.cells.enumerated() {
                guard let tex = cellTexture(d, c) else { continue }
                ui.sprite("b.an\(n).\(k)", tex, center: CGPoint(x: ox + CGFloat(c.x), y: oy - CGFloat(c.y)), size: CGSize(width: 192, height: 192), z: 5,
                          alpha: CGFloat(c.opacity / 255), rotation: -CGFloat(c.rotation), xScale: CGFloat(c.scaleX), yScale: CGFloat(c.scaleY),
                          blend: [.alpha, .add, .multiply, .screen][max(0, min(3, c.blend))])
            }
            if let t = a.standInProgress { drawStandIn("b.si\(n)", d, t, CGPoint(x: ox, y: oy), z: 5) }
            if a.screenFlashColor[3] > 0.5 {
                let f = a.screenFlashColor
                ui.rect("b.sf\(n)", CGRect(x: 0, y: 0, width: W, height: H), color: NSColor(red: f[0] / 255, green: f[1] / 255, blue: f[2] / 255, alpha: f[3] / 255), z: 6)
            }
        }
    }

    /// Effekseer stand-in: a coloured glow and an expanding ring tinted by the animation's flash colour.
    func drawStandIn(_ key: String, _ d: AnimationData, _ t: Double, _ p: CGPoint, z: CGFloat) {
        let col = AnimationArt.standInColor(d)
        let s = CGFloat(d.scale) / 100
        ui.sprite(key + ".g", AnimationArt.glow, center: p, size: CGSize(width: 220 * s, height: 220 * s), z: z, alpha: CGFloat(sin(t * .pi)), blend: .add)
        ui.flashSprite(key + ".gc", AnimationArt.glow, center: p, size: CGSize(width: 220 * s, height: 220 * s), z: z + 0.01, anchor: CGPoint(x: 0.5, y: 0.5),
                       rgba: [col.0, col.1, col.2, 200 * (1 - t)], blend: .add)
        let r = (40 + 160 * CGFloat(t)) * s
        ui.flashSprite(key + ".r", AnimationArt.ring, center: p, size: CGSize(width: r, height: r), z: z + 0.02, anchor: CGPoint(x: 0.5, y: 0.5),
                       rgba: [col.0, col.1, col.2, 255 * (1 - t)], blend: .add)
    }

    func cellTexture(_ d: AnimationData, _ c: AnimationPlayback.Cell) -> SKTexture? {
        let name = c.sheet == 1 ? d.animation1Name : d.animation2Name
        guard !name.isEmpty, scene.sheet("animations", name) != nil else { return nil }
        return scene.subTexture("animations", name, CGRect(x: (c.pattern % 5) * 192, y: (c.pattern / 5) * 192, width: 192, height: 192))
    }

    func consumeCues(_ b: BattleManager) {
        let H = GameScene.H
        for c in b.cues where c.id > lastCue {
            lastCue = c.id
            var x = GameScene.W / 2, y = H / 2
            if let t = c.target, let f = targetFrame(t, b) {
                x = f.x + (t < 0 && sideView ? -32 : 0)
                y = t >= 0 ? f.y + f.h * 0.6 : f.y + (sideView ? 40 : 26)
            }
            switch c.kind {
            case .damage(let v): popups.append(("\(v)", .white, x, y, 0, c.id))
            case .recover(let v): popups.append(("\(v)", SceneUI.textColors[24], x, y, 0, c.id))
            case .mpDamage(let v): popups.append(("\(abs(v))", v > 0 ? SceneUI.textColors[23] : SceneUI.textColors[4], x, y, 0, c.id))
            case .miss: popups.append(("Miss", SceneUI.textColors[8], x, y, 0, c.id))
            case .critical: popups.append(("Critical!", SceneUI.textColors[18], x, y + 26, 0, c.id))
            case .collapse:
                if let t = c.target, t >= 0, let e = b.enemies.first(where: { $0.index == t }) {
                    let type = ["collapse", "bossCollapse", "instantCollapse"][safe: e.collapseType]
                    if let type, enemyFx[t]?.appeared == true { enemyFx[t]?.start(type) }
                }
            case .flash: if let t = c.target, t >= 0 { enemyFx[t]?.start("whiten") }
            case .effect(let type): if let t = c.target, t >= 0 { enemyFx[t]?.start(type) }
            case .shake: shake = 18
            case .actorAct: if !sideView, let t = c.target { actorFlash[t] = 14 }
            case .motion(let m): if let t = c.target, t < 0, -t - 1 < svActors.count { svActors[-t - 1].requestMotion(m) }
            case .weapon(let w): if let t = c.target, t < 0, -t - 1 < svActors.count { svActors[-t - 1].startWeapon(w) }
            case .animation(let id, let mirror, let delay):
                if let a = scene.project.animation(id) { animations.append(AnimationPlayback(a, targets: c.targets, mirror: mirror, delay: delay)) }
            }
        }
    }

    func drawPopups() {
        popups = popups.compactMap { p in
            var p = p
            p.age += 1
            guard p.age < 70 else { return nil }
            let rise = p.age < 10 ? CGFloat(p.age) * 2.4 : 24
            ui.label("b.pop\(p.id)", p.text, CGPoint(x: p.x, y: p.y + rise), size: 34, color: p.color, align: .center, bold: true, z: 40,
                     alpha: p.age > 50 ? CGFloat(70 - p.age) / 20 : 1)
            return p
        }
    }

    /// Window_BattleStatus as rows: name, HP/MP/TP, states. The commanding actor is highlighted.
    func drawStatus(_ b: BattleManager) {
        let W = GameScene.W
        let r = CGRect(x: 240, y: 8, width: W - 248, height: 180)
        ui.window("b.st", r, z: 20)
        let targetingAlly: Int? = { if case .actorTarget = sub, b.phase == .input { return cur("ally") }; return nil }()
        for (i, a) in b.members.prefix(4).enumerated() {
            let y = r.maxY - 46 - CGFloat(i) * 40
            if b.inputIndex == i && b.phase == .input && !b.isBusy { ui.rect("b.sel", CGRect(x: r.minX + 6, y: y - 10, width: r.width - 12, height: 38), color: NSColor(white: 1, alpha: 0.12), z: 21, corner: 6) }
            if targetingAlly == i { ui.cursor("b.allyc", CGRect(x: r.minX + 6, y: y - 10, width: r.width - 12, height: 38), z: 21) }
            if let f = actorFlash[i] {
                actorFlash[i] = f > 0 ? f - 1 : nil
                ui.rect("b.afl\(i)", CGRect(x: r.minX + 6, y: y - 10, width: r.width - 12, height: 38), color: NSColor(white: 1, alpha: CGFloat(f) / 28), z: 21, corner: 6)
            }
            ui.label("b.sn\(i)", a.name, CGPoint(x: r.minX + 18, y: y), size: 21, color: a.isDead ? SceneUI.textColors[18] : (a.hpRate < 0.25 ? SceneUI.textColors[17] : .white), z: 22, maxWidth: 110)
            for (j, s) in a.sortedStates.filter({ $0.iconIndex > 0 }).prefix(2).enumerated() { ui.icon("b.ss\(i).\(j)", s.iconIndex, CGPoint(x: r.minX + 128 + CGFloat(j) * 26, y: y - 6), size: 24, z: 22) }
            let gx = r.minX + 186, gw: CGFloat = 112
            ui.gauge("b.hp\(i)", CGRect(x: gx, y: y - 2, width: gw, height: 8), rate: a.hpRate, colors: SceneUI.hpColor, label: terms.basic[3], value: "\(a.hp)", z: 22)
            ui.gauge("b.mp\(i)", CGRect(x: gx + gw + 14, y: y - 2, width: 90, height: 8), rate: a.mpRate, colors: SceneUI.mpColor, label: terms.basic[5], value: "\(a.mp)", z: 22)
            if scene.project.system.optDisplayTp {
                ui.gauge("b.tp\(i)", CGRect(x: gx + gw + 118, y: y - 2, width: 70, height: 8), rate: Double(a.tp) / 100, colors: SceneUI.tpColor, label: terms.basic[7], value: "\(a.tp)", z: 22)
            }
        }
    }

    func drawCommands(_ b: BattleManager) {
        guard b.phase == .input, !b.isBusy, world.message == nil else { return }
        let W = GameScene.W
        if b.waitingForPartyCommand {
            ui.list("b.party", CGRect(x: 8, y: 8, width: 224, height: 180),
                    rows: [.init(text: terms.commands[0]), .init(text: terms.commands[1], enabled: b.canEscape)], cursor: cur("party"), rowHeight: 42)
            return
        }
        guard let a = b.inputActor else { return }
        let cmds = actorCommands(a)
        ui.list("b.actor", CGRect(x: 8, y: 8, width: 224, height: 180), rows: cmds.map { SceneUI.Row(text: $0.0) }, cursor: cur("actor"), active: sub == .actor, rowHeight: 38)
        let listRect = CGRect(x: 8, y: 196, width: W - 16, height: 200)
        switch sub {
        case .skills(let stype):
            let skills = b.usableSkills(a).filter { $0.stypeId == stype }
            ui.list("b.list", listRect, rows: skills.map { s in
                SceneUI.Row(text: s.name, icon: s.iconIndex, right: s.tpCost > 0 ? "\(s.tpCost)TP" : (s.mpCost > 0 ? "\(a.skillMpCost(s))" : ""), enabled: a.canUse(s, inBattle: true))
            }, cursor: cur("list"), columns: 2)
            help(skills[safe: cur("list")]?.description ?? "")
        case .items:
            let items = b.usableItems()
            ui.list("b.list", listRect, rows: items.map { SceneUI.Row(text: $0.name, icon: $0.iconIndex, right: ":\(world.state.count(kind: 1, id: $0.id))") }, cursor: cur("list"), columns: 2)
            help(items[safe: cur("list")]?.description ?? "")
        default: break
        }
    }

    func help(_ t: String) {
        let W = GameScene.W
        ui.window("b.help", CGRect(x: 8, y: 404, width: W - 16, height: 64), z: 20)
        ui.richText("b.helpt", t, CGPoint(x: 28, y: 428), size: 20, z: 22)
    }
}

/// Shared textures for animation stand-ins (soft glow, ring) and their colours.
enum AnimationArt {
    static let glow: SKTexture = {
        let ctx = makeCanvas(128, 128)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }()
    static let ring: SKTexture = {
        let ctx = makeCanvas(128, 128)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(6); ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: 116, height: 116))
        return SKTexture(cgImage: ctx.makeImage()!)
    }()
    /// The first flash colour, else a colour derived from the effect name.
    static func standInColor(_ d: AnimationData) -> (Double, Double, Double) {
        if let f = d.flashTimings.first, f.color.count >= 3, f.color[0] + f.color[1] + f.color[2] > 0 { return (Double(f.color[0]), Double(f.color[1]), Double(f.color[2])) }
        let h = d.effectName.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        return (Double(140 + h % 116), Double(140 + (h / 7) % 116), Double(140 + (h / 49) % 116))
    }
}

/// Scene_Shop: Buy / Sell / Cancel, quantity window, gold, owned count and equipment comparison.
final class ShopController {
    unowned let scene: GameScene
    enum Sub { case command, buy, buyQty, sellCategory, sell, sellQty }
    var sub: Sub = .command
    var cursors: [String: Int] = [:]
    var qty = 1

    init(scene: GameScene) { self.scene = scene }
    var world: GameWorld { scene.world }
    var ui: SceneUI { scene.ui }
    var shop: ShopState? { world.shop }
    var project: Project { scene.project }
    func cur(_ k: String) -> Int { cursors[k] ?? 0 }
    func move(_ k: String, _ n: Int, _ u: UIInput, columns: Int = 1) {
        var c = cur(k)
        if SceneUI.move(&c, count: n, u, columns: columns) { world.playSystemSound(0) }
        cursors[k] = min(c, max(0, n - 1))
    }

    func sellList() -> [(kind: Int, id: Int)] {
        switch cur("scat") {
        case 0: return world.state.items.keys.sorted().filter { project.item($0)?.itypeId == 1 }.map { (0, $0) }
        case 1: return world.state.weapons.keys.sorted().map { (1, $0) }
        default: return world.state.armors.keys.sorted().map { (2, $0) }
        }
    }

    func step(_ u: UIInput) {
        guard let shop else { return }
        switch sub {
        case .command:
            move("cmd", 3, u, columns: 3)
            if u.cancel { world.playSystemSound(2); world.shop = nil; return }
            if u.ok {
                switch cur("cmd") {
                case 0: world.playSystemSound(1); sub = .buy
                case 1: if shop.purchaseOnly { world.playSystemSound(3) } else { world.playSystemSound(1); sub = .sellCategory }
                default: world.playSystemSound(2); world.shop = nil
                }
            }
        case .buy:
            move("buy", shop.goods.count, u)
            if u.cancel { world.playSystemSound(2); sub = .command }
            if u.ok, let g = shop.goods[safe: cur("buy")] {
                if ShopState.maxBuy(g, world: world) > 0 { world.playSystemSound(1); qty = 1; sub = .buyQty } else { world.playSystemSound(3) }
            }
        case .buyQty:
            guard let g = shop.goods[safe: cur("buy")] else { sub = .buy; return }
            adjustQty(u, max: ShopState.maxBuy(g, world: world))
            if u.cancel { world.playSystemSound(2); sub = .buy }
            if u.ok { ShopState.buy(g, qty: qty, world: world); sub = .buy }
        case .sellCategory:
            move("scat", 3, u, columns: 3)
            if u.cancel { world.playSystemSound(2); sub = .command }
            if u.ok { world.playSystemSound(1); cursors["sell"] = 0; sub = .sell }
        case .sell:
            let list = sellList()
            move("sell", list.count, u, columns: 2)
            if u.cancel { world.playSystemSound(2); sub = .sellCategory }
            if u.ok, let (k, id) = list[safe: cur("sell")] {
                if ShopState.basePrice(kind: k, id: id, project) > 0 { world.playSystemSound(1); qty = 1; sub = .sellQty } else { world.playSystemSound(3) }
            }
        case .sellQty:
            guard let (k, id) = sellList()[safe: cur("sell")] else { sub = .sell; return }
            adjustQty(u, max: world.state.count(kind: ShopState.stateKind(k), id: id))
            if u.cancel { world.playSystemSound(2); sub = .sell }
            if u.ok { ShopState.sell(kind: k, id: id, qty: qty, world: world); sub = .sell }
        }
    }

    func adjustQty(_ u: UIInput, max m: Int) {
        let old = qty
        if u.right { qty += 1 }
        if u.left { qty -= 1 }
        if u.up { qty += 10 }
        if u.down { qty -= 10 }
        qty = max(1, min(max(1, m), qty))
        if qty != old { world.playSystemSound(0) }
    }

    func info(_ kind: Int, _ id: Int) -> (String, Int, String, [Int]?) {
        switch kind {
        case 1: let w = project.weapon(id); return (w?.name ?? "?", w?.iconIndex ?? 0, w?.description ?? "", w?.params)
        case 2: let a = project.armor(id); return (a?.name ?? "?", a?.iconIndex ?? 0, a?.description ?? "", a?.params)
        default: let i = project.item(id); return (i?.name ?? "?", i?.iconIndex ?? 0, i?.description ?? "", nil)
        }
    }

    func render() {
        guard let shop else { return }
        let W = GameScene.W, H = GameScene.H
        let unit = project.system.currencyUnit
        let t = project.system.terms
        ui.window("shop.help", CGRect(x: 8, y: H - 84, width: W - 16, height: 76), z: 20)
        ui.window("shop.cmd", CGRect(x: 8, y: H - 152, width: W - 232, height: 60), z: 20)
        for (i, c) in [t.commands[safe: 24] ?? "Buy", t.commands[safe: 25] ?? "Sell", t.commands[safe: 22] ?? "Cancel"].enumerated() {
            let x = 20 + CGFloat(i) * (W - 256) / 3
            if cur("cmd") == i { ui.cursor("shop.cc", CGRect(x: x, y: H - 142, width: (W - 256) / 3 - 6, height: 40), z: 21) }
            ui.label("shop.c\(i)", c, CGPoint(x: x + (W - 256) / 6, y: H - 130), size: 22, align: .center, z: 22, alpha: sub == .command || cur("cmd") == i ? 1 : 0.6)
        }
        ui.window("shop.gold", CGRect(x: W - 216, y: H - 152, width: 208, height: 60), z: 20)
        ui.label("shop.g", "\(world.state.gold) \(unit)", CGPoint(x: W - 26, y: H - 130), size: 22, align: .right, z: 22)

        var desc = "", owned: Int?, params: [Int]?
        switch sub {
        case .command, .buy, .buyQty:
            let rows = shop.goods.map { g -> SceneUI.Row in
                let (n, ic, _, _) = info(g.kind, g.id)
                return SceneUI.Row(text: n, icon: ic, right: "\(g.price)", enabled: g.price <= world.state.gold)
            }
            ui.list("shop.buy", CGRect(x: 8, y: 8, width: 456, height: H - 168), rows: rows, cursor: sub == .command ? nil : cur("buy"), active: sub == .buy)
            if sub != .command, let g = shop.goods[safe: cur("buy")] {
                let i = info(g.kind, g.id); desc = i.2; params = i.3
                owned = world.state.count(kind: ShopState.stateKind(g.kind), id: g.id)
            }
            if sub == .buyQty, let g = shop.goods[safe: cur("buy")] { qtyWindow(price: g.price, unit: unit) }
        case .sellCategory, .sell, .sellQty:
            ui.window("shop.scat", CGRect(x: 8, y: H - 220, width: W - 16, height: 60), z: 20)
            for (i, c) in ["Item", "Weapon", "Armor"].enumerated() {
                let x = 20 + CGFloat(i) * (W - 40) / 3
                if cur("scat") == i { ui.cursor("shop.scc", CGRect(x: x, y: H - 210, width: (W - 40) / 3 - 6, height: 40), z: 21) }
                ui.label("shop.sc\(i)", c, CGPoint(x: x + (W - 40) / 6, y: H - 198), size: 22, align: .center, z: 22)
            }
            let list = sellList()
            let rows = list.map { k, id -> SceneUI.Row in
                let (n, ic, _, _) = info(k, id)
                return SceneUI.Row(text: n, icon: ic, right: ":\(world.state.count(kind: ShopState.stateKind(k), id: id))", enabled: ShopState.basePrice(kind: k, id: id, project) > 0)
            }
            ui.list("shop.sell", CGRect(x: 8, y: 8, width: W - 16, height: H - 236), rows: rows, cursor: sub == .sellCategory ? nil : cur("sell"), active: sub == .sell, columns: 2)
            if sub != .sellCategory, let (k, id) = list[safe: cur("sell")] { desc = info(k, id).2 }
            if sub == .sellQty, let (k, id) = list[safe: cur("sell")] { qtyWindow(price: ShopState.basePrice(kind: k, id: id, project) / 2, unit: unit) }
        }
        ui.richText("shop.desc", desc, CGPoint(x: 26, y: H - 56), size: 20, z: 22)
        // Status window: owned + parameter comparison against each member's current gear.
        if sub == .buy || sub == .buyQty {
            let r = CGRect(x: 472, y: 8, width: W - 480, height: H - 168)
            ui.window("shop.st", r, z: 20)
            if let o = owned { ui.label("shop.own", "\(t.messages["possession"] ?? "Possession"):  \(o)", CGPoint(x: r.minX + 18, y: r.maxY - 40), size: 20, z: 22) }
            if let p = params, let g = shop.goods[safe: cur("buy")] {
                for (i, a) in world.allMembers.prefix(4).enumerated() {
                    let slot = g.kind == 1 ? 0 : max(0, (project.armor(g.id)?.etypeId ?? 2) - 1)
                    let can = a.canEquip(slot: slot, id: g.id)
                    let curId = a.equips[safe: slot] ?? 0
                    let curParams = curId > 0 ? (slot == 0 ? project.weapon(curId) : project.armor(curId))?.params : nil
                    let pid = g.kind == 1 ? 2 : 3
                    let diff = p[pid] - (curParams?[pid] ?? 0)
                    let y = r.maxY - 90 - CGFloat(i) * 60
                    ui.label("shop.an\(i)", a.name, CGPoint(x: r.minX + 18, y: y), size: 20, z: 22, alpha: can ? 1 : 0.45)
                    ui.label("shop.ad\(i)", can ? "\(t.params[pid]) \(diff >= 0 ? "+" : "")\(diff)" : "—", CGPoint(x: r.maxX - 18, y: y), size: 20,
                             color: diff > 0 ? SceneUI.textColors[24] : diff < 0 ? SceneUI.textColors[25] : .white, align: .right, z: 22, alpha: can ? 1 : 0.45)
                }
            }
        }
    }

    func qtyWindow(price: Int, unit: String) {
        let W = GameScene.W
        let r = CGRect(x: W / 2 - 200, y: 200, width: 400, height: 120)
        ui.window("shop.q", r, z: 40)
        ui.label("shop.qn", "×  \(qty)", CGPoint(x: r.minX + 30, y: r.maxY - 50), size: 26, z: 42)
        ui.label("shop.qt", "\(price * qty) \(unit)", CGPoint(x: r.maxX - 24, y: r.maxY - 50), size: 26, align: .right, z: 42)
        ui.label("shop.qh", "←/→ ±1   ↑/↓ ±10   Z buy/sell", CGPoint(x: r.midX, y: r.minY + 18), size: 15, align: .center, z: 42, alpha: 0.7)
    }
}

/// Scene_Name: type with the keyboard or pick letters from the grid; Enter/OK on "OK" (or Return) confirms.
final class NameController {
    unowned let scene: GameScene
    var name: String
    var cursor = 0
    let maxLength: Int
    let actorId: Int
    static let table: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ").map(String.init) + ["←", "OK"]

    init(scene: GameScene) {
        self.scene = scene
        let req = scene.world.nameInput ?? (1, 8)
        actorId = req.actorId; maxLength = req.maxLength
        name = scene.world.actor(req.actorId)?.name ?? ""
    }

    func step(_ u: UIInput) {
        let w = scene.world
        if !u.typed.isEmpty { for ch in u.typed where name.count < maxLength { name.append(ch) } }
        if u.backspace { if !name.isEmpty { name.removeLast() } ; return }
        var c = cursor
        if SceneUI.move(&c, count: Self.table.count, u, columns: 10) { w.playSystemSound(0) }
        cursor = c
        if u.cancel && !name.isEmpty { name.removeLast(); w.playSystemSound(2) }
        if u.ok {
            let k = Self.table[cursor]
            if k == "OK" {
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { w.playSystemSound(3); return }
                w.actor(actorId)?.setName(name); w.playSystemSound(1); w.nameInput = nil
            } else if k == "←" { if !name.isEmpty { name.removeLast() } }
            else if name.count < maxLength { name.append(contentsOf: k); w.playSystemSound(0) } else { w.playSystemSound(3) }
        }
    }

    func render() {
        let ui = scene.ui, W = GameScene.W
        ui.rect("name.dim", CGRect(x: 0, y: 0, width: W, height: GameScene.H), color: NSColor(white: 0, alpha: 0.5), z: 18)
        let top = CGRect(x: 108, y: 452, width: W - 216, height: 140)
        ui.window("name.top", top, z: 20)
        if let a = scene.project.actor(actorId), let tex = scene.characterTexture(a.characterName, a.characterIndex, 2, 1) {
            ui.sprite("name.ch", tex, center: CGPoint(x: top.minX + 70, y: top.midY), size: CGSize(width: 96, height: 96), z: 21)
        }
        let display = name + String(repeating: "_", count: max(0, maxLength - name.count))
        ui.label("name.v", display.map { String($0) }.joined(separator: " "), CGPoint(x: top.minX + 150, y: top.midY - 10), size: 32, z: 22)
        let r = CGRect(x: 108, y: 32, width: W - 216, height: 404)
        ui.window("name.grid", r, z: 20)
        for (i, k) in Self.table.enumerated() {
            let x = r.minX + 24 + CGFloat(i % 10) * ((r.width - 48) / 10)
            let y = r.maxY - 56 - CGFloat(i / 10) * 50
            if i == cursor { ui.cursor("name.c", CGRect(x: x - 4, y: y - 12, width: (r.width - 48) / 10, height: 44), z: 21) }
            ui.label("name.k\(i)", k == " " ? "␣" : k, CGPoint(x: x + (r.width - 48) / 20 - 4, y: y), size: 24, align: .center, z: 22)
        }
        ui.label("name.h", "Type or pick letters · Delete removes · choose OK to confirm", CGPoint(x: W / 2, y: 44), size: 15, align: .center, z: 22, alpha: 0.7)
    }
}
