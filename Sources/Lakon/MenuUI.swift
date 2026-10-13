import AppKit
import LakonCore
import SpriteKit

/// Scene_Menu and its sub-scenes: Item, Skill, Equip, Status, Options, Save/Load, Game End.
final class MenuController {
    unowned let scene: GameScene
    var closed = false

    enum State {
        case main
        case pickActor(Purpose)
        case itemCategory
        case itemList(category: Int)
        case itemTarget(category: Int, itemId: Int)
        case skillList(actor: Int)
        case skillTarget(actor: Int, skillId: Int)
        case equipSlots(actor: Int)
        case equipItems(actor: Int, slot: Int)
        case status(actor: Int)
        case options
        case files(save: Bool)
        case gameEnd
    }
    enum Purpose { case skill, equip, status }

    var stack: [State] = [.main]
    var cursors: [String: Int] = [:]
    let standalone: Bool

    static let commands = ["Item", "Skill", "Equip", "Status", "Options", "Save", "Game End"]

    init(scene: GameScene, saveOnly: Bool = false, loadOnly: Bool = false, optionsOnly: Bool = false) {
        self.scene = scene
        standalone = saveOnly || loadOnly || optionsOnly
        if saveOnly { stack = [.files(save: true)] }
        if loadOnly { stack = [.files(save: false)] }
        if optionsOnly { stack = [.options] }
    }

    var world: GameWorld { scene.world }
    var project: Project { scene.project }
    var ui: SceneUI { scene.ui }
    var members: [GameActor] { world.allMembers }
    var terms: Terms { project.system.terms }

    func cur(_ k: String) -> Int { cursors[k] ?? 0 }
    func ok() { world.playSystemSound(1) }
    func buzz() { world.playSystemSound(3) }
    func back() {
        world.playSystemSound(2)
        stack.removeLast()
        if stack.isEmpty { closed = true }
    }
    func move(_ k: String, _ n: Int, _ u: UIInput, columns: Int = 1) {
        var c = cur(k)
        if SceneUI.move(&c, count: n, u, columns: columns) { world.playSystemSound(0) }
        cursors[k] = min(c, max(0, n - 1))
    }

    // MARK: lists

    func categoryItems(_ cat: Int) -> [(kind: Int, id: Int)] {
        switch cat {
        case 0: return world.state.items.keys.sorted().filter { project.item($0)?.itypeId == 1 }.map { (1, $0) }
        case 1: return world.state.weapons.keys.sorted().map { (2, $0) }
        case 2: return world.state.armors.keys.sorted().map { (3, $0) }
        default: return world.state.items.keys.sorted().filter { project.item($0)?.itypeId == 2 }.map { (1, $0) }
        }
    }
    func info(_ kind: Int, _ id: Int) -> (name: String, icon: Int, desc: String) {
        switch kind {
        case 2: let w = project.weapon(id); return (w?.name ?? "?", w?.iconIndex ?? 0, w?.description ?? "")
        case 3: let a = project.armor(id); return (a?.name ?? "?", a?.iconIndex ?? 0, a?.description ?? "")
        default: let i = project.item(id); return (i?.name ?? "?", i?.iconIndex ?? 0, i?.description ?? "")
        }
    }

    // MARK: input

    func step(_ u: UIInput) {
        guard let state = stack.last else { closed = true; return }
        switch state {
        case .main:
            move("main", Self.commands.count, u)
            if u.cancel { back(); return }
            guard u.ok else { return }
            switch cur("main") {
            case 0: ok(); stack.append(.itemCategory)
            case 1: ok(); stack.append(.pickActor(.skill))
            case 2: ok(); stack.append(.pickActor(.equip))
            case 3: ok(); stack.append(.pickActor(.status))
            case 4: ok(); stack.append(.options)
            case 5: if world.state.saveEnabled { ok(); stack.append(.files(save: true)) } else { buzz() }
            default: ok(); stack.append(.gameEnd)
            }
        case .pickActor(let purpose):
            move("actor", members.count, u)
            if u.cancel { back(); return }
            guard u.ok, cur("actor") < members.count else { return }
            ok()
            let a = cur("actor")
            switch purpose {
            case .skill: stack.append(.skillList(actor: a))
            case .equip: stack.append(.equipSlots(actor: a))
            case .status: stack.append(.status(actor: a))
            }
        case .itemCategory:
            move("cat", 4, u, columns: 4)
            if u.cancel { back(); return }
            if u.ok { ok(); cursors["items"] = 0; stack.append(.itemList(category: cur("cat"))) }
        case .itemList(let cat):
            let list = categoryItems(cat)
            move("items", list.count, u, columns: 2)
            if u.cancel { back(); return }
            guard u.ok, cur("items") < list.count else { return }
            let (k, id) = list[cur("items")]
            guard k == 1, let it = project.item(id), it.isMenuUsable, it.scope != 0 else { buzz(); return }
            ok()
            if it.isForFriend && !it.isForUser { stack.append(.itemTarget(category: cat, itemId: id)) }
            else if let user = members.first { _ = world.useInMenu(itemId: id, user: user, target: user) }
        case .itemTarget(_, let id):
            move("target", members.count, u)
            if u.cancel { back(); return }
            guard u.ok, let user = members.first else { return }
            let target = members[safe: cur("target")]
            if !world.useInMenu(itemId: id, user: user, target: target) { buzz() }
            if world.state.count(kind: 1, id: id) == 0 { stack.removeLast() }
            if world.isEventRunning { closed = true }   // item triggered a common event
        case .skillList(let ai):
            guard let a = members[safe: ai] else { back(); return }
            let skills = a.skills
            move("skills", skills.count, u, columns: 2)
            if u.pageDown { cursors["actor"] = (ai + 1) % members.count; stack[stack.count - 1] = .skillList(actor: cur("actor")); return }
            if u.cancel { back(); return }
            guard u.ok, let s = skills[safe: cur("skills")] else { return }
            guard s.isMenuUsable, a.canUse(s, inBattle: false) else { buzz(); return }
            ok()
            if s.isForFriend && !s.isForUser { stack.append(.skillTarget(actor: ai, skillId: s.id)) }
            else { _ = world.useInMenu(skillId: s.id, user: a, target: a) }
        case .skillTarget(let ai, let sid):
            move("target", members.count, u)
            if u.cancel { back(); return }
            guard u.ok, let a = members[safe: ai] else { return }
            if !world.useInMenu(skillId: sid, user: a, target: members[safe: cur("target")]) { buzz() }
        case .equipSlots(let ai):
            move("slot", 5, u)
            if u.pageDown { cursors["actor"] = (ai + 1) % members.count; stack[stack.count - 1] = .equipSlots(actor: cur("actor")); return }
            if u.cancel { back(); return }
            guard u.ok, let a = members[safe: ai] else { return }
            if a.isEquipLocked(slot: cur("slot")) { buzz(); return }
            ok(); cursors["equipItem"] = 0
            stack.append(.equipItems(actor: ai, slot: cur("slot")))
        case .equipItems(let ai, let slot):
            guard let a = members[safe: ai] else { back(); return }
            let options = equipOptions(a, slot)
            move("equipItem", options.count, u)
            if u.cancel { back(); return }
            guard u.ok else { return }
            world.equip(actor: a, slot: slot, itemId: options[cur("equipItem")])
            stack.removeLast()
        case .status(let ai):
            if u.pageDown || u.right { cursors["actor"] = (ai + 1) % max(1, members.count); stack[stack.count - 1] = .status(actor: cur("actor")); world.playSystemSound(0) }
            if u.pageUp || u.left { cursors["actor"] = (ai + members.count - 1) % max(1, members.count); stack[stack.count - 1] = .status(actor: cur("actor")); world.playSystemSound(0) }
            if u.cancel || u.ok { back() }
        case .options:
            let keys = ["bgm", "bgs", "me", "se"]
            move("opt", keys.count + 1, u)
            let i = cur("opt")
            if i < keys.count, u.left || u.right {
                let k = keys[i]
                let v = AudioPlayer.volumes[k] ?? 0.9
                AudioPlayer.volumes[k] = max(0, min(1, v + (u.right ? 0.2 : -0.2)))
                UserDefaults.standard.set(AudioPlayer.volumes, forKey: "lakonVolumes")
                world.playSystemSound(0)
            }
            if u.cancel || (u.ok && i == keys.count) { back() }
        case .files(let save):
            move("file", SaveFiles.count, u)
            if u.cancel { back(); return }
            guard u.ok else { return }
            let slot = cur("file") + 1
            if save {
                if scene.saveGame(slot) { scene.toast = ("Saved to File \(slot)", 90); if standalone { closed = true } else { stack.removeLast() } }
            } else {
                if SaveFiles.exists(scene.saveDir, slot) { _ = scene.loadGame(slot); closed = true } else { buzz() }
            }
        case .gameEnd:
            move("end", 2, u)
            if u.cancel { back(); return }
            if u.ok {
                if cur("end") == 0 { ok(); closed = true; world.audio.fadeOutBgm(1); scene.showTitle() } else { back() }
            }
        }
    }

    func equipOptions(_ a: GameActor, _ slot: Int) -> [Int] {
        let pool = slot == 0 ? world.state.weapons : world.state.armors
        return pool.keys.sorted().filter { a.canEquip(slot: slot, id: $0) } + [0]
    }

    // MARK: render

    func render() {
        let W = GameScene.W, H = GameScene.H
        if !standalone { ui.rect("menu.dim", CGRect(x: 0, y: 0, width: W, height: H), color: NSColor(white: 0, alpha: 0.35), z: 18) }
        guard let state = stack.last else { return }
        switch state {
        case .main, .pickActor:
            drawMain(active: { if case .main = state { return true }; return false }())
            if case .pickActor = state { drawPartyStatus(cursor: cur("actor")) } else { drawPartyStatus(cursor: nil) }
        case .itemCategory, .itemList, .itemTarget:
            drawItems(state)
        case .skillList(let ai), .skillTarget(let ai, _):
            drawSkills(ai, state)
        case .equipSlots(let ai), .equipItems(let ai, _):
            drawEquip(ai, state)
        case .status(let ai):
            drawStatus(ai)
        case .options:
            drawOptions()
        case .files(let save):
            drawFiles(save)
        case .gameEnd:
            drawMain(active: false); drawPartyStatus(cursor: nil)
            ui.list("end", CGRect(x: W / 2 - 140, y: H / 2 - 60, width: 280, height: 110), rows: [.init(text: "To Title"), .init(text: "Cancel")], cursor: cur("end"), z: 40)
        }
    }

    func drawMain(active: Bool) {
        let rows = Self.commands.enumerated().map { i, c in SceneUI.Row(text: c, enabled: i != 5 || world.state.saveEnabled) }
        ui.list("main", CGRect(x: 16, y: 120, width: 200, height: 488), rows: rows, cursor: cur("main"), active: active, rowHeight: 44)
        ui.window("gold.w", CGRect(x: 16, y: 16, width: 200, height: 92), z: 20)
        ui.label("gold.v", "\(world.state.gold)", CGPoint(x: 160, y: 50), size: 24, align: .right, z: 22)
        ui.label("gold.u", project.system.currencyUnit, CGPoint(x: 200, y: 50), size: 20, color: SceneUI.systemColor, align: .right, z: 22)
        let mins = world.state.playFrames / 3600, secs = (world.state.playFrames / 60) % 60
        ui.label("gold.t", String(format: "%d:%02d", mins, secs), CGPoint(x: 32, y: 80), size: 16, color: SceneUI.systemColor, z: 22)
    }

    /// Party list (Window_MenuStatus): character sprite, name, class, level, HP/MP/TP gauges, state icons.
    func drawPartyStatus(cursor: Int?, x: CGFloat = 232, width: CGFloat = 568) {
        let r = CGRect(x: x, y: 16, width: width, height: 592)
        ui.window("party.w", r, z: 20)
        for (i, a) in members.prefix(4).enumerated() {
            let top = r.maxY - 12 - CGFloat(i) * 144
            if cursor == i { ui.cursor("party.c", CGRect(x: r.minX + 8, y: top - 140, width: r.width - 16, height: 136), z: 21) }
            drawActorBlock("p\(i)", a, x: r.minX + 20, top: top, width: r.width - 40)
        }
    }

    func drawActorBlock(_ k: String, _ a: GameActor, x: CGFloat, top: CGFloat, width: CGFloat) {
        let data = project.actor(a.actorId)
        if let face = data.flatMap({ scene.faceTexture($0.faceName, $0.faceIndex) }) {
            ui.sprite("\(k).face", face, center: CGPoint(x: x + 56, y: top - 68), size: CGSize(width: 112, height: 112), z: 22, alpha: a.isDead ? 0.5 : 1)
        } else if let tex = data.flatMap({ scene.characterTexture($0.characterName, $0.characterIndex, 2, 1) }) {
            ui.sprite("\(k).ch", tex, center: CGPoint(x: x + 56, y: top - 70), size: CGSize(width: 96, height: 96), z: 22, alpha: a.isDead ? 0.5 : 1)
        }
        let tx = x + 132
        ui.label("\(k).n", a.name, CGPoint(x: tx, y: top - 34), size: 24, color: a.isDead ? SceneUI.textColors[18] : .white, bold: true, z: 22)
        ui.label("\(k).cl", a.currentClass?.name ?? "", CGPoint(x: tx + 190, y: top - 34), size: 20, z: 22)
        ui.label("\(k).lvl", terms.basic[1], CGPoint(x: tx, y: top - 66), size: 18, color: SceneUI.systemColor, z: 22)
        ui.label("\(k).lv", "\(a.level)", CGPoint(x: tx + 60, y: top - 66), size: 20, align: .right, z: 22)
        for (j, s) in a.sortedStates.filter({ $0.iconIndex > 0 }).prefix(4).enumerated() { ui.icon("\(k).st\(j)", s.iconIndex, CGPoint(x: tx + 80 + CGFloat(j) * 30, y: top - 74), z: 22) }
        for p in 0..<8 where a.buffs[p] != 0 { ui.icon("\(k).bf\(p)", (a.buffs[p] > 0 ? 32 : 48) + p, CGPoint(x: tx + 80 + CGFloat(4 + p) * 30, y: top - 74), z: 22) }
        let gw = min(180, width - 150)
        ui.gauge("\(k).hp", CGRect(x: tx + 190, y: top - 74, width: gw, height: 8), rate: a.hpRate, colors: SceneUI.hpColor, label: terms.basic[3], value: "\(a.hp)/\(a.mhp)", z: 22)
        ui.gauge("\(k).mp", CGRect(x: tx + 190, y: top - 104, width: gw, height: 8), rate: a.mpRate, colors: SceneUI.mpColor, label: terms.basic[5], value: "\(a.mp)/\(a.mmp)", z: 22)
        if project.system.optDisplayTp {
            ui.gauge("\(k).tp", CGRect(x: tx, y: top - 104, width: 160, height: 8), rate: Double(a.tp) / 100, colors: SceneUI.tpColor, label: terms.basic[7], value: "\(a.tp)", z: 22)
        }
    }

    func helpWindow(_ text: String) {
        ui.window("help.w", CGRect(x: 16, y: GameScene.H - 92, width: GameScene.W - 32, height: 76), z: 20)
        ui.richText("help.t", text, CGPoint(x: 34, y: GameScene.H - 62), size: 21, z: 22)
    }

    func drawItems(_ state: State) {
        let W = GameScene.W
        let cats = ["Item", "Weapon", "Armor", "Key Item"]
        let catActive: Bool = { if case .itemCategory = state { return true }; return false }()
        ui.window("cat.w", CGRect(x: 16, y: 456, width: W - 32, height: 60), z: 20)
        for (i, c) in cats.enumerated() {
            let x = 28 + CGFloat(i) * (W - 56) / 4
            if i == cur("cat") { ui.cursor("cat.c", CGRect(x: x, y: 466, width: (W - 56) / 4 - 6, height: 40), z: 21) }
            ui.label("cat.\(i)", c, CGPoint(x: x + (W - 56) / 8, y: 478), size: 21, align: .center, z: 22, alpha: catActive || i == cur("cat") ? 1 : 0.6)
        }
        let list = categoryItems(cur("cat"))
        let rows = list.map { k, id -> SceneUI.Row in
            let inf = info(k, id)
            let usable = k == 1 && (project.item(id)?.isMenuUsable ?? false)
            return SceneUI.Row(text: inf.name, icon: inf.icon, right: ":\(world.state.count(kind: k, id: id))", enabled: usable || k != 1)
        }
        let listActive: Bool = { if case .itemList = state { return true }; return false }()
        ui.list("items", CGRect(x: 16, y: 16, width: W - 32, height: 428), rows: rows, cursor: catActive ? nil : cur("items"), active: listActive, columns: 2)
        if !catActive, let (k, id) = list[safe: cur("items")] { helpWindow(info(k, id).desc) } else { helpWindow("Choose a category.") }
        if case .itemTarget = state { drawTargetPicker() }
    }

    func drawTargetPicker() {
        let W = GameScene.W
        let r = CGRect(x: W - 452, y: 16, width: 436, height: 592)
        ui.window("tgt.w", r, z: 40)
        for (i, a) in members.prefix(4).enumerated() {
            let top = r.maxY - 12 - CGFloat(i) * 144
            if cur("target") == i { ui.cursor("tgt.c", CGRect(x: r.minX + 8, y: top - 140, width: r.width - 16, height: 136), z: 41) }
            drawActorBlockCompact("t\(i)", a, x: r.minX + 18, top: top)
        }
    }

    func drawActorBlockCompact(_ k: String, _ a: GameActor, x: CGFloat, top: CGFloat) {
        let data = project.actor(a.actorId)
        if let tex = data.flatMap({ scene.characterTexture($0.characterName, $0.characterIndex, 2, 1) }) {
            ui.sprite("\(k).ch", tex, center: CGPoint(x: x + 36, y: top - 70), size: CGSize(width: 72, height: 72), z: 42)
        }
        ui.label("\(k).n", a.name, CGPoint(x: x + 90, y: top - 36), size: 22, bold: true, z: 42)
        ui.label("\(k).lv", "\(terms.basic[1]) \(a.level)", CGPoint(x: x + 300, y: top - 36), size: 18, z: 42)
        ui.gauge("\(k).hp", CGRect(x: x + 90, y: top - 76, width: 300, height: 8), rate: a.hpRate, colors: SceneUI.hpColor, label: terms.basic[3], value: "\(a.hp)/\(a.mhp)", z: 42)
        ui.gauge("\(k).mp", CGRect(x: x + 90, y: top - 110, width: 300, height: 8), rate: a.mpRate, colors: SceneUI.mpColor, label: terms.basic[5], value: "\(a.mp)/\(a.mmp)", z: 42)
    }

    func drawSkills(_ ai: Int, _ state: State) {
        guard let a = members[safe: ai] else { return }
        let W = GameScene.W
        ui.window("sk.actor", CGRect(x: 16, y: 380, width: W - 32, height: 140), z: 20)
        drawActorBlock("ska", a, x: 32, top: 512, width: W - 64)
        let rows = a.skills.map { s in
            SceneUI.Row(text: s.name, icon: s.iconIndex, right: s.tpCost > 0 ? "\(s.tpCost) TP" : (s.mpCost > 0 ? "\(a.skillMpCost(s))" : ""),
                        enabled: s.isMenuUsable && a.canUse(s, inBattle: false))
        }
        let listActive: Bool = { if case .skillList = state { return true }; return false }()
        ui.list("skills", CGRect(x: 16, y: 16, width: W - 32, height: 352), rows: rows, cursor: cur("skills"), active: listActive, columns: 2,
                title: "Skills — Q/W to switch actor")
        helpWindow(a.skills[safe: cur("skills")]?.description ?? "")
        if case .skillTarget = state { drawTargetPicker() }
    }

    func drawEquip(_ ai: Int, _ state: State) {
        guard let a = members[safe: ai] else { return }
        let W = GameScene.W
        let slotNames = (1...5).map { project.system.equipTypes[safe: $0] ?? "Slot" }
        let rows = (0..<5).map { i -> SceneUI.Row in
            let id = a.equips[safe: i] ?? 0
            let item = id > 0 ? (i == 0 ? project.weapon(id) : project.armor(id)) : nil
            return SceneUI.Row(text: "\(slotNames[i]):  \(item?.name ?? "—")", icon: item?.iconIndex ?? 0, enabled: !a.isEquipLocked(slot: i))
        }
        let slotsActive: Bool = { if case .equipSlots = state { return true }; return false }()
        ui.list("eqslots", CGRect(x: 300, y: 236, width: W - 316, height: 288), rows: rows, cursor: cur("slot"), active: slotsActive, rowHeight: 40,
                title: "\(a.name) — Q/W to switch actor")
        // Parameters with preview of the highlighted candidate.
        var preview: [Int]? = nil
        if case .equipItems(_, let slot) = state {
            let options = equipOptions(a, slot)
            let cand = options[safe: cur("equipItem")] ?? 0
            let old = a.equips[slot]
            let candItem = cand > 0 ? (slot == 0 ? project.weapon(cand) : project.armor(cand)) : nil
            let oldItem = old > 0 ? (slot == 0 ? project.weapon(old) : project.armor(old)) : nil
            preview = (0..<8).map { a.param($0) - (oldItem?.params[$0] ?? 0) + (candItem?.params[$0] ?? 0) }
            let irows = options.map { id -> SceneUI.Row in
                if id == 0 { return SceneUI.Row(text: "(Remove)") }
                let e = slot == 0 ? project.weapon(id) : project.armor(id)
                return SceneUI.Row(text: e?.name ?? "?", icon: e?.iconIndex ?? 0, right: ":\(world.state.count(kind: slot == 0 ? 2 : 3, id: id))")
            }
            ui.list("eqitems", CGRect(x: 300, y: 16, width: W - 316, height: 208), rows: irows, cursor: cur("equipItem"), columns: 2)
            helpWindowSmall(candItem?.description ?? "")
        } else {
            let id = a.equips[safe: cur("slot")] ?? 0
            helpWindowSmall((id > 0 ? (cur("slot") == 0 ? project.weapon(id) : project.armor(id)) : nil)?.description ?? "")
        }
        let r = CGRect(x: 16, y: 16, width: 272, height: 508)
        ui.window("eqp.w", r, z: 20)
        ui.label("eqp.n", a.name, CGPoint(x: 34, y: r.maxY - 40), size: 24, bold: true, z: 22)
        for p in 2..<8 {
            let y = r.maxY - 90 - CGFloat(p - 2) * 40
            ui.label("eqp.l\(p)", terms.params[p], CGPoint(x: 34, y: y), size: 20, color: SceneUI.systemColor, z: 22)
            ui.label("eqp.v\(p)", "\(a.param(p))", CGPoint(x: 200, y: y), size: 20, align: .right, z: 22)
            if let pv = preview {
                let c: NSColor = pv[p] > a.param(p) ? SceneUI.textColors[24] : pv[p] < a.param(p) ? SceneUI.textColors[25] : .white
                ui.label("eqp.p\(p)", "→ \(pv[p])", CGPoint(x: 268, y: y), size: 20, color: c, align: .right, z: 22)
            }
        }
    }

    func helpWindowSmall(_ text: String) {
        ui.window("help.w", CGRect(x: 300, y: GameScene.H - 92, width: GameScene.W - 316, height: 76), z: 20)
        ui.richText("help.t", text, CGPoint(x: 318, y: GameScene.H - 62), size: 19, z: 22)
    }

    func drawStatus(_ ai: Int) {
        guard let a = members[safe: ai] else { return }
        let W = GameScene.W, H = GameScene.H
        ui.window("st.w", CGRect(x: 16, y: 16, width: W - 32, height: H - 32), z: 20)
        drawActorBlock("sta", a, x: 36, top: H - 28, width: W - 72)
        ui.label("st.nick", a.nickname, CGPoint(x: 600, y: H - 62), size: 20, color: SceneUI.systemColor, z: 22)
        let top = H - 200
        for p in 2..<8 {
            let y = top - CGFloat(p - 2) * 36
            ui.label("st.l\(p)", terms.params[p], CGPoint(x: 48, y: y), size: 20, color: SceneUI.systemColor, z: 22)
            ui.label("st.v\(p)", "\(a.param(p))", CGPoint(x: 260, y: y), size: 20, align: .right, z: 22)
        }
        ui.label("st.exp1", terms.message("expTotal", terms.basic[8]), CGPoint(x: 300, y: top), size: 20, color: SceneUI.systemColor, z: 22)
        ui.label("st.exp1v", "\(a.currentExp)", CGPoint(x: 560, y: top), size: 20, align: .right, z: 22)
        ui.label("st.exp2", terms.message("expNext", terms.basic[0]), CGPoint(x: 300, y: top - 36), size: 20, color: SceneUI.systemColor, z: 22)
        ui.label("st.exp2v", "\(a.expToNext)", CGPoint(x: 560, y: top - 36), size: 20, align: .right, z: 22)
        for (i, id) in a.equips.enumerated() where id > 0 {
            let e = i == 0 ? project.weapon(id) : project.armor(id)
            ui.icon("st.ei\(i)", e?.iconIndex ?? 0, CGPoint(x: 580, y: top - 6 - CGFloat(i) * 36), z: 22)
            ui.label("st.e\(i)", e?.name ?? "", CGPoint(x: 616, y: top - CGFloat(i) * 36), size: 20, z: 22)
        }
        ui.richText("st.prof", project.actor(a.actorId)?.profile ?? "", CGPoint(x: 48, y: 60), size: 20, z: 22)
        ui.label("st.hint", "←/→ next member", CGPoint(x: W - 40, y: 30), size: 14, align: .right, z: 22, alpha: 0.6)
    }

    func drawOptions() {
        let keys = ["bgm", "bgs", "me", "se"]
        let names = [terms.messages["bgmVolume"] ?? "BGM Volume", terms.messages["bgsVolume"] ?? "BGS Volume",
                     terms.messages["meVolume"] ?? "ME Volume", terms.messages["seVolume"] ?? "SE Volume"]
        var rows = keys.enumerated().map { i, k in SceneUI.Row(text: names[i], right: "\(Int(((AudioPlayer.volumes[k] ?? 0.9) * 100).rounded()))%") }
        rows.append(.init(text: "Done"))
        ui.list("opt", CGRect(x: GameScene.W / 2 - 220, y: 180, width: 440, height: 250), rows: rows, cursor: cur("opt"), rowHeight: 42, z: 30, title: "Options — ←/→ to change")
    }

    func drawFiles(_ save: Bool) {
        let W = GameScene.W
        ui.window("files.h", CGRect(x: 16, y: GameScene.H - 76, width: W - 32, height: 60), z: 30)
        ui.label("files.ht", terms.messages[save ? "saveMessage" : "loadMessage"] ?? (save ? "Save to which file?" : "Load which file?"),
                 CGPoint(x: 34, y: GameScene.H - 54), size: 22, z: 32)
        let r = CGRect(x: 16, y: 16, width: W - 32, height: GameScene.H - 104)
        ui.window("files.w", r, z: 30)
        let rowH = r.height / CGFloat(SaveFiles.count)
        for i in 0..<SaveFiles.count {
            let top = r.maxY - CGFloat(i) * rowH
            if cur("file") == i { ui.cursor("files.c", CGRect(x: r.minX + 8, y: top - rowH + 4, width: r.width - 16, height: rowH - 8), z: 31) }
            ui.label("files.n\(i)", "\(terms.messages["file"] ?? "File") \(i + 1)", CGPoint(x: 40, y: top - 40), size: 22, color: SceneUI.systemColor, z: 32)
            if let inf = SaveFiles.info(scene.saveDir, i + 1) {
                ui.label("files.m\(i)", inf.mapName, CGPoint(x: 200, y: top - 40), size: 22, z: 32)
                ui.label("files.l\(i)", "\(inf.leader)  \(terms.basic[1]) \(inf.level)", CGPoint(x: 200, y: top - 76), size: 20, z: 32)
                let mins = inf.playFrames / 3600, secs = (inf.playFrames / 60) % 60
                ui.label("files.t\(i)", String(format: "%d:%02d", mins, secs), CGPoint(x: W - 50, y: top - 40), size: 20, align: .right, z: 32)
                ui.label("files.d\(i)", inf.savedAt.formatted(date: .abbreviated, time: .shortened), CGPoint(x: W - 50, y: top - 76), size: 16, align: .right, z: 32, alpha: 0.7)
            } else {
                ui.label("files.m\(i)", "— empty —", CGPoint(x: 200, y: top - 40), size: 20, z: 32, alpha: 0.5)
            }
        }
    }
}
