import AppKit
import CoreImage
import LakonCore
import LakonRender
import SpriteKit

/// Input for menus: triggered (with key repeat) this frame.
struct UIInput {
    var up = false, down = false, left = false, right = false, ok = false, cancel = false, pageUp = false, pageDown = false
    var typed: String = ""
    var backspace = false
    var any: Bool { up || down || left || right || ok || cancel || pageUp || pageDown }
}

/// SpriteKit renderer + input for `GameWorld`: the roles of MZ's Scene_Title / Scene_Map / Spriteset_Map /
/// Window_Message, plus menuUI, battle, shop and name screens (see MenuUI/BattleUI/ShopUI).
/// 816×624 (MZ default), fixed 60 Hz simulation.
final class GameScene: SKScene {
    static let W: CGFloat = 816, H: CGFloat = 624
    static let screenW = W, screenH = H

    let project: Project
    let world: GameWorld
    let audio: AudioPlayer
    let saveDir: URL
    let playtest: Bool
    var onQuit: () -> Void = {}

    enum Mode { case title, map, gameOver }
    private(set) var mode: Mode = .title
    var titleCursor = 0
    var titleOptions = false

    let ui = SceneUI()
    var menuUI: MenuController?
    var shopUI: ShopController?
    var nameUI: NameController?
    var battleUI: BattleController?

    // World layers
    let effect = SKEffectNode()
    let worldNode = SKNode()
    let pictureLayer = SKNode()
    let weatherLayer = SKNode()
    let fadeNode = SKSpriteNode(color: .black, size: CGSize(width: W, height: H))
    let flashNode = SKSpriteNode(color: .white, size: CGSize(width: W, height: H))
    let toneFilter = CIFilter(name: "CIColorMatrix")!

    private var chunkNodes: [String: SKSpriteNode] = [:]
    private var chunkTextures: [String: SKTexture] = [:]
    private var chunkOrder: [String] = []
    private var animatedChunks = Set<String>()
    private var builtGeneration = -1
    var renderer: TileRenderer?
    private var charNodes: [ObjectIdentifier: CharacterSprite] = [:]
    private var pictureNodes: [Int: SKSpriteNode] = [:]
    private var weatherSprites: [SKSpriteNode] = []
    private var textures: [String: SKTexture] = [:]
    private var sheets: [String: CGImage] = [:]
    var mapNameTimer = 0

    // Input
    private var held: Set<UInt16> = []
    private var dirOrder: [Int] = []
    private var pending = UIInput()
    private var shift = false
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    var toast: (String, Int)?
    var script: [ScriptStep] = []
    enum ScriptStep { case input(InputState), ui(UIInput), action(() -> Void) }

    init(project: Project, saveDir: URL, playtest: Bool) {
        self.project = project
        world = GameWorld(project: project)
        audio = AudioPlayer(project: project)
        self.saveDir = saveDir
        self.playtest = playtest
        super.init(size: CGSize(width: Self.W, height: Self.H))
        scaleMode = .aspectFit
        backgroundColor = .black
        effect.addChild(worldNode)
        effect.shouldRasterize = false
        effect.shouldEnableEffects = false
        effect.filter = toneFilter
        addChild(effect)
        weatherLayer.zPosition = 40; addChild(weatherLayer)
        pictureLayer.zPosition = 50; addChild(pictureLayer)
        flashNode.anchorPoint = .zero; flashNode.zPosition = 60; flashNode.blendMode = .add; flashNode.alpha = 0; addChild(flashNode)
        fadeNode.anchorPoint = .zero; fadeNode.zPosition = 90; fadeNode.alpha = 0; addChild(fadeNode)
        addChild(ui.root)
        ui.windowTone = project.system.windowTone
        if let icons = loadPNG(project.imageURL("system", "IconSet")) { ui.iconSheet = SKTexture(cgImage: icons); ui.iconSheet?.filteringMode = .nearest }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        if playtest { startNewGame() } else { showTitle() }
    }

    override func willMove(from view: SKView) { audio.stopAll() }

    // MARK: input

    override func keyDown(with e: NSEvent) {
        let k = e.keyCode
        shift = e.modifierFlags.contains(.shift)
        switch k {
        case 6, 36, 49, 76: if !e.isARepeat { pending.ok = true }
        case 7, 53: if !e.isARepeat { pending.cancel = true }
        case 51: pending.backspace = true; if !e.isARepeat && nameUI == nil { pending.cancel = true }
        case 126: pending.up = true
        case 125: pending.down = true
        case 123: pending.left = true
        case 124: pending.right = true
        case 12: pending.pageUp = true
        case 13: pending.pageDown = true
        default: break
        }
        if nameUI != nil, let chars = e.characters, !chars.isEmpty, chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " }) {
            pending.typed += chars
        }
        if let d = Self.dirFor(k), !held.contains(k) { dirOrder.removeAll { $0 == d }; dirOrder.append(d) }
        held.insert(k)
    }
    override func keyUp(with e: NSEvent) {
        held.remove(e.keyCode)
        if let d = Self.dirFor(e.keyCode) { dirOrder.removeAll { $0 == d } }
    }
    override func flagsChanged(with e: NSEvent) { shift = e.modifierFlags.contains(.shift) }
    static func dirFor(_ k: UInt16) -> Int? { [123: 4, 124: 6, 125: 2, 126: 8][k] }

    func worldInput(_ u: UIInput) -> InputState {
        var i = InputState(dir4: dirOrder.last ?? 0, ok: u.ok, cancel: u.cancel, up: u.up, down: u.down, left: u.left, right: u.right, dash: shift)
        var h: Set<String> = []
        if held.contains(6) || held.contains(36) || held.contains(49) { h.insert("ok") }
        if held.contains(7) || held.contains(53) { h.insert("cancel") }
        if shift { h.insert("shift") }
        for (k, n) in [126: "up", 125: "down", 123: "left", 124: "right", 12: "pageup", 13: "pagedown"] as [UInt16: String] where held.contains(k) { h.insert(n) }
        i.held = h
        return i
    }

    // MARK: loop

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        // Clamp: never negative (mixed time sources), never a huge catch-up after a stall.
        accumulator = min(accumulator + max(0, currentTime - lastTime), 0.25)
        lastTime = max(lastTime, currentTime)
        var stepped = false
        while accumulator >= 1.0 / 60 {
            accumulator -= 1.0 / 60
            step()
            stepped = true
        }
        if stepped { render() }
    }

    private func step() {
        var u = pending
        pending = UIInput()
        var wi = worldInput(u)
        while case .action(let f)? = script.first { script.removeFirst(); render(); f() }
        if case .input(let i)? = script.first { script.removeFirst(); wi = i; u = UIInput(up: i.up, down: i.down, left: i.left, right: i.right, ok: i.ok, cancel: i.cancel) }
        else if case .ui(let x)? = script.first { script.removeFirst(); u = x; wi = InputState(ok: x.ok, cancel: x.cancel, up: x.up, down: x.down, left: x.left, right: x.right) }

        switch mode {
        case .title: titleStep(u)
        case .gameOver: if u.ok { showTitle() }
        case .map: mapStep(u, wi)
        }
        audio.handle(world.audio.drain())
        audio.update()
        if let t = toast { toast = t.1 > 1 ? (t.0, t.1 - 1) : nil }
    }

    private func mapStep(_ u: UIInput, _ wi: InputState) {
        if world.battle != nil {
            menuUI = nil
            if battleUI == nil { battleUI = BattleController(scene: self) }
            let consumed = world.message == nil ? battleUI!.step(u) : false
            world.update(consumed ? InputState() : wi)
            if world.battle == nil { battleUI = nil }
        } else if world.shop != nil {
            if shopUI == nil { shopUI = ShopController(scene: self) }
            shopUI!.step(u)
            if world.shop == nil { shopUI = nil; world.update(InputState()) }
        } else if world.nameInput != nil {
            if nameUI == nil { nameUI = NameController(scene: self) }
            nameUI!.step(u)
            if world.nameInput == nil { nameUI = nil; world.update(InputState()) }
        } else if let m = menuUI {
            m.step(u)
            if m.closed { menuUI = nil; world.requestMenu = false; world.requestSave = false }
        } else if world.requestMenu || world.requestSave {
            menuUI = MenuController(scene: self, saveOnly: world.requestSave && !world.requestMenu)
        } else if u.cancel && world.message == nil && !world.isEventRunning && !world.player.isMoving && world.state.menuEnabled && world.transferPending == nil {
            world.playSystemSound(1)
            menuUI = MenuController(scene: self, saveOnly: false)
        } else {
            world.update(wi)
        }
        if world.gameOver {
            world.gameOver = false
            mode = .gameOver
            world.audio.stopBgm()
            world.audio.playMe(project.system.gameoverMe)
        }
        if world.returnToTitle { world.returnToTitle = false; showTitle() }
    }

    // MARK: title

    var hasAnySave: Bool { (1...SaveFiles.count).contains { SaveFiles.exists(saveDir, $0) } }

    func showTitle() {
        mode = .title; titleCursor = hasAnySave ? 1 : 0; menuUI = nil; battleUI = nil; shopUI = nil; nameUI = nil
        worldNode.removeAllChildren(); charNodes = [:]; chunkNodes = [:]; builtGeneration = -1
        pictureNodes.values.forEach { $0.removeFromParent() }; pictureNodes = [:]
        weatherSprites.forEach { $0.removeFromParent() }; weatherSprites = []
        world.audio.fadeOutBgs(0)
        world.audio.playBgm(project.system.titleBgm)
    }

    private func titleStep(_ u: UIInput) {
        if titleOptions {
            if let m = menuUI { m.step(u); if m.closed { menuUI = nil; titleOptions = false } }
            return
        }
        let n = 4
        if u.up { titleCursor = (titleCursor + n - 1) % n; world.playSystemSound(0) }
        if u.down { titleCursor = (titleCursor + 1) % n; world.playSystemSound(0) }
        guard u.ok else { return }
        switch titleCursor {
        case 0: world.playSystemSound(1); startNewGame()
        case 1:
            if hasAnySave { world.playSystemSound(1); menuUI = MenuController(scene: self, loadOnly: true); titleOptions = true } else { world.playSystemSound(3) }
        case 2: world.playSystemSound(1); menuUI = MenuController(scene: self, optionsOnly: true); titleOptions = true
        default: onQuit()
        }
    }

    func startNewGame() {
        world.audio.stopBgm()
        world.newGame()
        mode = .map
        menuUI = nil
    }

    func loadGame(_ slot: Int) -> Bool {
        guard let s = SaveFiles.load(saveDir, slot) else { toast = ("Could not load file \(slot)", 120); return false }
        world.load(s); mode = .map; menuUI = nil; titleOptions = false
        world.playSystemSound(6)
        return true
    }

    func saveGame(_ slot: Int) -> Bool {
        do { try SaveFiles.save(world.makeSave(), world: world, dir: saveDir, slot: slot); world.playSystemSound(5); return true }
        catch { toast = ("Save failed: \(error.localizedDescription)", 180); world.playSystemSound(3); return false }
    }

    // MARK: rendering

    func render() {
        ui.begin()
        switch mode {
        case .title:
            effect.isHidden = true; pictureLayer.isHidden = true; weatherLayer.isHidden = true
            fadeNode.alpha = 0; flashNode.alpha = 0
            drawTitle()
            if titleOptions { menuUI?.render() }
        case .gameOver:
            effect.isHidden = false; effect.alpha = 0.25; fadeNode.alpha = 0
            ui.label("go", "GAME OVER", CGPoint(x: Self.W / 2, y: Self.H / 2), size: 64, align: .center, bold: true)
            ui.label("go2", "Press Z / Enter", CGPoint(x: Self.W / 2, y: Self.H / 2 - 60), size: 18, align: .center, alpha: 0.7)
        case .map:
            if let b = battleUI, world.battle != nil {
                effect.isHidden = true; weatherLayer.isHidden = true; pictureLayer.isHidden = false
                fadeNode.alpha = 0
                b.render()
                renderPictures()
            } else {
                effect.isHidden = false; effect.alpha = 1; weatherLayer.isHidden = false; pictureLayer.isHidden = false
                renderMap()
                renderPictures()
                renderWeather()
                renderScreenEffects()
                if let name = mapNameBanner { drawMapName(name) }
                if world.mapDamageFlash > 0 { ui.rect("dmgflash", CGRect(x: 0, y: 0, width: Self.W, height: Self.H), color: NSColor(red: 1, green: 0, blue: 0, alpha: CGFloat(world.mapDamageFlash) / 24), z: -1) }
            }
            if let m = world.message { drawMessage(m) }
            shopUI?.render()
            nameUI?.render()
            menuUI?.render()
        }
        if let t = toast {
            ui.window("toast", CGRect(x: Self.W - 316, y: Self.H - 64, width: 300, height: 48), z: 30)
            ui.label("toast.t", t.0, CGPoint(x: Self.W - 166, y: Self.H - 46), size: 20, align: .center, z: 31, maxWidth: 280)
        }
        ui.end()
    }

    private func drawTitle() {
        ui.rect("title.bg", CGRect(x: 0, y: 0, width: Self.W, height: Self.H), color: NSColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 1), z: -10)
        if let t = titleTexture { ui.sprite("title.img", t, center: CGPoint(x: Self.W / 2, y: Self.H / 2), size: CGSize(width: Self.W, height: Self.H), z: -9) }
        for i in 0..<40 {
            let tw = 0.3 + 0.3 * sin(Double(ui.frame + i * 13) / 30)
            ui.rect("title.s\(i)", CGRect(x: CGFloat((i * 197) % 816), y: CGFloat(260 + (i * 83) % 360), width: CGFloat(1 + i % 3), height: CGFloat(1 + i % 3)), color: NSColor(white: 1, alpha: tw), z: -8)
        }
        ui.label("title.t", project.system.gameTitle, CGPoint(x: Self.W / 2, y: 420), size: 56, align: .center, bold: true, maxWidth: 760)
        let options = ["New Game", "Continue", "Options", playtest ? "Close Playtest" : "Quit"]
        ui.window("title.w", CGRect(x: Self.W / 2 - 120, y: 100, width: 240, height: 180))
        for (i, o) in options.enumerated() {
            let y = 246 - CGFloat(i) * 40
            if i == titleCursor && !titleOptions { ui.cursor("title.c", CGRect(x: Self.W / 2 - 108, y: y - 12, width: 216, height: 34)) }
            ui.label("title.o\(i)", o, CGPoint(x: Self.W / 2, y: y - 4), size: 22, align: .center, alpha: i == 1 && !hasAnySave ? 0.4 : 1)
        }
    }
    private lazy var titleTexture: SKTexture? = {
        guard !project.system.title1Name.isEmpty, let img = loadPNG(project.imageURL("titles1", project.system.title1Name)) else { return nil }
        return SKTexture(cgImage: img)
    }()

    private var mapNameBanner: String? { mapNameTimer > 0 && !world.map.displayName.isEmpty ? world.map.displayName : nil }

    private func drawMapName(_ name: String) {
        let a = min(1, CGFloat(mapNameTimer) / 30)
        ui.rect("mapname.bg", CGRect(x: 0, y: Self.H - 80, width: 360, height: 48), color: NSColor(white: 0, alpha: 0.55 * a), z: 5)
        ui.label("mapname", name, CGPoint(x: 24, y: Self.H - 66), size: 24, z: 6, alpha: a)
    }

    // MARK: map

    var scroll = CGPoint.zero

    private func renderMap() {
        if builtGeneration != world.mapGeneration { resetMap() }
        if mapNameTimer > 0 { mapNameTimer -= 1 }
        let ts = CGFloat(tileSize)
        let m = world.map
        let mapW = CGFloat(m.width) * ts, mapH = CGFloat(m.height) * ts
        var sx = CGFloat(world.player.realX) * ts + ts / 2 - Self.W / 2
        var sy = CGFloat(world.player.realY) * ts + ts / 2 - Self.H / 2
        sx = mapW <= Self.W ? (mapW - Self.W) / 2 : max(0, min(mapW - Self.W, sx))
        sy = mapH <= Self.H ? (mapH - Self.H) / 2 : max(0, min(mapH - Self.H, sy))
        scroll = CGPoint(x: sx.rounded(), y: sy.rounded())
        worldNode.position = CGPoint(x: -scroll.x + CGFloat(world.screen.shake), y: Self.H + scroll.y)
        updateChunks()
        renderCharacters()
    }

    private func resetMap() {
        builtGeneration = world.mapGeneration
        chunkNodes.values.forEach { $0.removeFromParent() }; chunkNodes = [:]
        chunkTextures = [:]; chunkOrder = []; animatedChunks = []
        charNodes.values.forEach { $0.removeFromParent() }; charNodes = [:]
        renderer = TileRenderer(project: project, tileset: world.tileset)
        textures = textures.filter { !$0.key.hasPrefix("tile:") }
        // Chunks containing A1 (animated water) re-render on frame changes.
        let chunk = Self.chunk
        for cy in stride(from: 0, to: world.map.height, by: chunk) { for cx in stride(from: 0, to: world.map.width, by: chunk) {
            var anim = false
            outer: for y in cy..<min(world.map.height, cy + chunk) { for x in cx..<min(world.map.width, cx + chunk) {
                for z in 0..<4 where TileID.isA1(world.map.tileId(x, y, z)) { anim = true; break outer }
            } }
            if anim { animatedChunks.insert("\(cx),\(cy)") }
        } }
        mapNameTimer = 150
    }

    static let chunk = 8

    /// Creates/updates chunk sprites around the camera; textures are cached (LRU) per animation frame.
    private func updateChunks() {
        guard let r = renderer else { return }
        let ts = tileSize, c = Self.chunk
        let x0 = max(0, (Int(scroll.x) / ts / c - 1) * c), y0 = max(0, (Int(scroll.y) / ts / c - 1) * c)
        let x1 = min(world.map.width, (Int(scroll.x) + Int(Self.W)) / ts + c), y1 = min(world.map.height, (Int(scroll.y) + Int(Self.H)) / ts + c)
        var visible = Set<String>()
        let frameKey = world.animationFrame % 12
        for cy in stride(from: y0, to: y1, by: c) { for cx in stride(from: x0, to: x1, by: c) {
            for upper in [false, true] {
                let pos = "\(cx),\(cy)"
                let nodeKey = pos + (upper ? "U" : "L")
                visible.insert(nodeKey)
                let fk = animatedChunks.contains(pos) ? frameKey : 0
                let texKey = nodeKey + ":\(fk)"
                let tex: SKTexture
                if let t = chunkTextures[texKey] { tex = t }
                else {
                    r.animationFrame = fk
                    guard let img = r.renderMap(world.map, tileset: world.tileset, x0: cx, y0: cy, cols: c, rows: c, upper: upper) else { continue }
                    tex = SKTexture(cgImage: img); tex.filteringMode = .nearest
                    chunkTextures[texKey] = tex; chunkOrder.append(texKey)
                    if chunkOrder.count > 200 { let old = chunkOrder.removeFirst(); chunkTextures[old] = nil }
                }
                let n = chunkNodes[nodeKey] ?? {
                    let n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0, y: 1)
                    n.position = CGPoint(x: cx * ts, y: -cy * ts); n.zPosition = upper ? 4 : 0
                    worldNode.addChild(n); chunkNodes[nodeKey] = n; return n
                }()
                if n.texture !== tex { n.texture = tex; n.size = tex.size() }
            }
        } }
        for (k, n) in chunkNodes where !visible.contains(k) { n.removeFromParent(); chunkNodes[k] = nil }
    }

    private func renderCharacters() {
        let ts = CGFloat(tileSize)
        var seen = Set<ObjectIdentifier>()
        var chars: [GameCharacter] = [world.player] + world.events + world.visibleVehicles
        if world.followersVisible && world.vehicle == nil { chars += world.followers }
        for c in chars {
            let key = ObjectIdentifier(c)
            seen.insert(key)
            let node = charNodes[key] ?? { let n = CharacterSprite(); worldNode.addChild(n); charNodes[key] = n; return n }()
            if let e = c as? GameEvent, e.pageIndex < 0 || e.erased { node.isHidden = true; continue }
            if let f = c as? GameFollower, f.x == world.player.x && f.y == world.player.y && !f.isMoving { node.isHidden = true; continue }
            var tex: SKTexture?
            if c.tileId > 0 { tex = tileTexture(c.tileId) }
            else if !c.characterName.isEmpty { tex = characterTexture(c.characterName, c.characterIndex, c.direction, c.patternIndex) }
            node.isHidden = c.transparent || (tex == nil && c.balloonId == 0 && c.animationId == 0)
            let altitude = (c as? GameVehicle)?.altitude ?? 0
            let shift: CGFloat = c.tileId > 0 || c.isObjectCharacter ? 0 : 6
            node.position = CGPoint(x: (CGFloat(c.realX) * ts + ts / 2).rounded(), y: -(CGFloat(c.realY) * ts + ts - shift).rounded() + CGFloat(altitude))
            // MZ screenZ = priority * 2 + 1; same-priority characters sort by y.
            node.zPosition = CGFloat(c.priorityType * 2 + 1) + CGFloat(c.realY) / 1000 + (altitude > 0 ? 5 : 0)
            let bush = !(c is GameVehicle) && c.tileId == 0 && world.isBush(c.x, c.y) && !c.isMoving
            node.update(texture: tex, bush: bush, balloon: c.balloonId, balloonFrames: c.balloonFrames,
                        animation: c.animationId, animationFrames: c.animationFrames, shadow: altitude, frame: ui.frame)
        }
        for (k, n) in charNodes where !seen.contains(k) { n.removeFromParent(); charNodes[k] = nil }
    }

    func sheet(_ folder: String, _ name: String) -> CGImage? {
        let key = folder + "/" + name
        if let s = sheets[key] { return s }
        let img = loadPNG(project.imageURL(folder, name))
        sheets[key] = img
        return img
    }

    func texture(_ folder: String, _ name: String) -> SKTexture? {
        let key = "img:\(folder)/\(name)"
        if let t = textures[key] { return t }
        guard let img = sheet(folder, name) else { return nil }
        let t = SKTexture(cgImage: img); t.filteringMode = .linear
        textures[key] = t
        return t
    }

    func characterTexture(_ name: String, _ index: Int, _ dir: Int, _ pattern: Int) -> SKTexture? {
        let key = "char:\(name):\(index):\(dir):\(pattern)"
        if let t = textures[key] { return t }
        guard let s = sheet("characters", name), let img = s.cropping(to: CharacterSheet.frame(sheet: s, name: name, index: index, direction: dir, pattern: pattern)) else { return nil }
        let t = SKTexture(cgImage: img); t.filteringMode = .nearest
        textures[key] = t
        return t
    }

    func faceTexture(_ name: String, _ index: Int) -> SKTexture? {
        let key = "face:\(name):\(index)"
        if let t = textures[key] { return t }
        guard let s = sheet("faces", name) else { return nil }
        let fw = s.width / 4, fh = s.height / 2
        guard let img = s.cropping(to: CGRect(x: (index % 4) * fw, y: (index / 4) * fh, width: fw, height: fh)) else { return nil }
        let t = SKTexture(cgImage: img); textures[key] = t
        return t
    }

    private func tileTexture(_ id: Int) -> SKTexture? {
        let key = "tile:\(id)"
        if let t = textures[key] { return t }
        guard let r = renderer else { return nil }
        let c = makeCanvas(tileSize, tileSize)
        r.draw(id, in: c, x: 0, y: 0)
        guard let img = c.makeImage() else { return nil }
        let t = SKTexture(cgImage: img); t.filteringMode = .nearest
        textures[key] = t
        return t
    }

    // MARK: pictures, weather, tint/flash/fade

    private func renderPictures() {
        let pics = world.screen.pictures
        for (id, n) in pictureNodes where pics[id] == nil { n.removeFromParent(); pictureNodes[id] = nil }
        for (id, p) in pics {
            guard let tex = texture("pictures", p.name) else { continue }
            let n = pictureNodes[id] ?? { let n = SKSpriteNode(); pictureLayer.addChild(n); pictureNodes[id] = n; return n }()
            if n.texture !== tex { n.texture = tex; n.size = tex.size() }
            n.anchorPoint = p.origin == 1 ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 0, y: 1)
            n.position = CGPoint(x: p.x, y: Self.H - p.y)
            n.xScale = p.scaleX / 100; n.yScale = p.scaleY / 100
            n.alpha = p.opacity / 255
            n.zRotation = -CGFloat(p.angle) * .pi / 180
            n.zPosition = CGFloat(id)
            n.blendMode = [.alpha, .add, .multiply, .screen][min(3, max(0, p.blendMode))]
            let tone = p.tone
            if tone.contains(where: { $0 != 0 }) {
                n.color = NSColor(red: CGFloat(max(0, min(255, 128 + tone[0]))) / 255, green: CGFloat(max(0, min(255, 128 + tone[1]))) / 255,
                                  blue: CGFloat(max(0, min(255, 128 + tone[2]))) / 255, alpha: 1)
                n.colorBlendFactor = 0.5
            } else { n.colorBlendFactor = 0 }
        }
    }

    /// Port of MZ's Weather sprites: rain = slanted streaks, storm = more and faster, snow = drifting flakes.
    private func renderWeather() {
        let type = world.screen.weatherType
        let count = type == "none" ? 0 : Int(world.screen.weatherPower * (type == "storm" ? 20 : 10))
        while weatherSprites.count < count {
            let s = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 2))
            s.position = CGPoint(x: CGFloat.random(in: 0...Self.W), y: CGFloat.random(in: 0...Self.H))
            weatherLayer.addChild(s); weatherSprites.append(s)
        }
        while weatherSprites.count > count { weatherSprites.removeLast().removeFromParent() }
        for (i, s) in weatherSprites.enumerated() {
            switch type {
            case "snow":
                s.size = CGSize(width: 5, height: 5); s.zRotation = 0; s.alpha = 0.85
                s.position.x += -1 + sin(CGFloat(ui.frame + i * 7) / 20) * 0.8; s.position.y -= 1.6
            case "storm":
                s.size = CGSize(width: 2, height: 40); s.zRotation = -0.45; s.alpha = 0.5
                s.position.x -= 9; s.position.y -= 18
            default:
                s.size = CGSize(width: 1.5, height: 30); s.zRotation = -0.22; s.alpha = 0.55
                s.position.x -= 4; s.position.y -= 14
            }
            if s.position.y < -40 { s.position.y += Self.H + 80 }
            if s.position.x < -40 { s.position.x += Self.W + 80 }
            if s.position.x > Self.W + 40 { s.position.x -= Self.W + 80 }
        }
        // Darken during rain/storms like MZ's weather dimmer.
        if type != "none" {
            ui.rect("weather.dim", CGRect(x: 0, y: 0, width: Self.W, height: Self.H),
                    color: NSColor(white: 0, alpha: CGFloat(world.screen.weatherPower) * (type == "storm" ? 0.04 : 0.02)), z: -50)
        }
    }

    private func renderScreenEffects() {
        // Tone: one CIColorMatrix does RGB offsets and desaturation (gray).
        let t = world.screen.tone
        let on = t.contains { abs($0) > 0.5 }
        effect.shouldEnableEffects = on
        if on {
            let s = 1 - CGFloat(t[3]) / 255
            let lr: CGFloat = 0.299, lg: CGFloat = 0.587, lb: CGFloat = 0.114
            toneFilter.setValue(CIVector(x: lr * (1 - s) + s, y: lg * (1 - s), z: lb * (1 - s), w: 0), forKey: "inputRVector")
            toneFilter.setValue(CIVector(x: lr * (1 - s), y: lg * (1 - s) + s, z: lb * (1 - s), w: 0), forKey: "inputGVector")
            toneFilter.setValue(CIVector(x: lr * (1 - s), y: lg * (1 - s), z: lb * (1 - s) + s, w: 0), forKey: "inputBVector")
            toneFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            toneFilter.setValue(CIVector(x: CGFloat(t[0]) / 255, y: CGFloat(t[1]) / 255, z: CGFloat(t[2]) / 255, w: 0), forKey: "inputBiasVector")
        }
        let f = world.screen.flashColor
        flashNode.color = NSColor(red: CGFloat(f[0]) / 255, green: CGFloat(f[1]) / 255, blue: CGFloat(f[2]) / 255, alpha: 1)
        flashNode.alpha = CGFloat(f[3]) / 255
        fadeNode.alpha = 1 - CGFloat(world.brightness / 255)
    }

    // MARK: message window (Window_Message, choices, number input, item select, scrolling text)

    func drawMessage(_ m: GameMessage) {
        if m.scrolling {
            ui.rect("scroll.bg", CGRect(x: 0, y: 0, width: Self.W, height: Self.H), color: NSColor(white: 0, alpha: 0.6), z: 9)
            for (i, line) in m.lines.enumerated() {
                let y = CGFloat(m.scrollOffset) - CGFloat(i) * 36
                if y > -40 && y < Self.H + 40 { ui.richText("scroll.\(i)", line, CGPoint(x: 60, y: y), size: 26, z: 10) }
            }
            return
        }
        let h: CGFloat = 180
        let y: CGFloat = m.positionType == 0 ? Self.H - h - 8 : m.positionType == 1 ? (Self.H - h) / 2 : 8
        let rect = CGRect(x: 8, y: y, width: Self.W - 16, height: h)
        let hasText = !m.lines.isEmpty || !m.speakerName.isEmpty
        if hasText {
            if m.background == 0 { ui.window("msg.w", rect, z: 10) }
            else if m.background == 1 { ui.rect("msg.dim", rect, color: NSColor(white: 0, alpha: 0.6), z: 10) }
            var textX = rect.minX + 22
            if !m.faceName.isEmpty, let tex = faceTexture(m.faceName, m.faceIndex) {
                ui.sprite("msg.face", tex, center: CGPoint(x: rect.minX + 18 + 72, y: rect.midY), size: CGSize(width: 144, height: 144), z: 11)
                textX += 160
            }
            if !m.speakerName.isEmpty {
                let nr = CGRect(x: rect.minX, y: rect.maxY + 4, width: CGFloat(m.speakerName.count) * 13 + 44, height: 44)
                ui.window("msg.nw", nr, z: 10)
                ui.label("msg.name", m.speakerName, CGPoint(x: nr.minX + 20, y: nr.minY + 13), size: 22, bold: true, z: 11)
            }
            let shown = SceneUI.visiblePrefix(m.text, m.visibleChars)
            for (i, line) in shown.components(separatedBy: "\n").prefix(4).enumerated() {
                ui.richText("msg.l\(i)", line, CGPoint(x: textX, y: rect.maxY - 46 - CGFloat(i) * 36), size: 24, z: 11)
            }
            if m.isTextComplete && m.choices.isEmpty && m.numberDigits == 0 && m.itemChoiceVariable == 0 && (ui.frame / 20) % 2 == 0 {
                ui.label("msg.pause", "▼", CGPoint(x: rect.midX, y: rect.minY + 6), size: 18, align: .center, z: 11)
            }
        }
        guard m.isTextComplete else { return }
        if !m.choices.isEmpty {
            let w = max(180, CGFloat(m.choices.map(\.count).max() ?? 0) * 13 + 64)
            let ch = CGFloat(m.choices.count) * 40 + 24
            let cy = hasText ? (m.positionType == 2 ? rect.maxY + 4 : rect.minY - ch - 4) : 8
            let cr = CGRect(x: Self.W - 8 - w, y: cy, width: w, height: ch)
            ui.window("choice.w", cr, z: 12)
            for (i, c) in m.choices.enumerated() {
                let yy = cr.maxY - 32 - CGFloat(i) * 40
                if i == m.choiceIndex { ui.cursor("choice.c", CGRect(x: cr.minX + 8, y: yy - 10, width: w - 16, height: 34), z: 13) }
                ui.richText("choice.\(i)", c, CGPoint(x: cr.minX + 22, y: yy - 2), size: 22, z: 14)
            }
        }
        if m.numberDigits > 0 {
            let w = CGFloat(m.numberDigits) * 34 + 40
            let nr = CGRect(x: (Self.W - w) / 2, y: hasText ? rect.maxY + 6 : 220, width: w, height: 64)
            ui.window("num.w", nr, z: 12)
            let s = String(format: "%0\(m.numberDigits)d", m.number)
            for (i, ch) in s.enumerated() {
                let x = nr.minX + 20 + CGFloat(i) * 34
                if i == m.numberCursor { ui.cursor("num.c", CGRect(x: x - 2, y: nr.minY + 12, width: 32, height: 40), z: 13) }
                ui.label("num.\(i)", String(ch), CGPoint(x: x + 14, y: nr.minY + 22), size: 28, align: .center, z: 14)
            }
        }
        if m.itemChoiceVariable > 0 {
            let names = m.itemChoices.map { project.item($0)?.name ?? "?" } + ["(none)"]
            let ir = CGRect(x: 8, y: hasText ? rect.maxY + 4 : 8, width: Self.W - 16, height: CGFloat(min(6, names.count)) * 38 + 24)
            ui.window("isel.w", ir, z: 12)
            for (i, n) in names.prefix(6).enumerated() {
                let yy = ir.maxY - 32 - CGFloat(i) * 38
                if i == m.itemChoiceIndex { ui.cursor("isel.c", CGRect(x: ir.minX + 8, y: yy - 10, width: ir.width - 16, height: 34), z: 13) }
                if i < m.itemChoices.count {
                    ui.icon("isel.i\(i)", project.item(m.itemChoices[i])?.iconIndex ?? 0, CGPoint(x: ir.minX + 18, y: yy - 6), z: 14)
                    ui.label("isel.n\(i)", "\(n)  ×\(world.state.count(kind: 1, id: m.itemChoices[i]))", CGPoint(x: ir.minX + 54, y: yy), size: 22, z: 14)
                } else { ui.label("isel.n\(i)", n, CGPoint(x: ir.minX + 54, y: yy), size: 22, z: 14, alpha: 0.7) }
            }
        }
    }
}

/// A map character: main sprite, optional bush overlay (lower 12 px at half opacity), shadow for the airship,
/// balloon icon, and a generic animation burst.
final class CharacterSprite: SKNode {
    let body = SKSpriteNode()
    let bushPart = SKSpriteNode()
    let shadow = SKShapeNode(ellipseOf: CGSize(width: 28, height: 10))
    let balloon = SKNode()
    let balloonBg = SKShapeNode(rectOf: CGSize(width: 34, height: 30), cornerRadius: 9)
    let balloonText = SKLabelNode()
    let burst = SKShapeNode(circleOfRadius: 20)

    override init() {
        super.init()
        body.anchorPoint = CGPoint(x: 0.5, y: 0); addChild(body)
        bushPart.anchorPoint = CGPoint(x: 0.5, y: 0); bushPart.alpha = 0.5; bushPart.zPosition = 0.01; addChild(bushPart)
        shadow.fillColor = NSColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear; shadow.zPosition = -0.5; addChild(shadow)
        balloonBg.fillColor = .white; balloonBg.strokeColor = NSColor(white: 0.2, alpha: 1); balloonBg.lineWidth = 2
        balloonText.fontName = "Avenir Next Heavy"; balloonText.fontSize = 20; balloonText.verticalAlignmentMode = .center
        balloon.addChild(balloonBg); balloon.addChild(balloonText); balloon.zPosition = 2; addChild(balloon)
        burst.strokeColor = NSColor(red: 1, green: 0.9, blue: 0.5, alpha: 1); burst.lineWidth = 3; burst.fillColor = NSColor(white: 1, alpha: 0.15)
        burst.zPosition = 3; addChild(burst)
    }
    required init?(coder: NSCoder) { fatalError() }

    static let balloonGlyphs = ["", "!", "?", "♪", "♥", "💢", "💧", "～", "…", "💡", "Zz"]
    static let balloonColors: [NSColor] = [.black, .systemRed, .systemBlue, .systemPurple, .systemPink, .systemRed, .systemBlue, .darkGray, .darkGray, .systemOrange, .systemIndigo]

    func update(texture: SKTexture?, bush: Bool, balloon id: Int, balloonFrames: Int, animation: Int, animationFrames: Int, shadow alt: Double, frame: Int) {
        body.texture = texture
        if let t = texture {
            let full = t.size()
            if bush {
                let cut = 12 / full.height
                body.texture = SKTexture(rect: CGRect(x: 0, y: cut, width: 1, height: 1 - cut), in: t)
                body.size = CGSize(width: full.width, height: full.height - 12)
                body.position = CGPoint(x: 0, y: 12)
                bushPart.texture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: cut), in: t)
                bushPart.size = CGSize(width: full.width, height: 12); bushPart.isHidden = false
            } else {
                body.size = full; body.position = .zero; bushPart.isHidden = true
            }
        } else { body.size = .zero; bushPart.isHidden = true }
        shadow.isHidden = alt <= 0
        shadow.position = CGPoint(x: 0, y: -CGFloat(alt) + 4)
        balloon.isHidden = id == 0
        if id > 0 {
            balloonText.text = Self.balloonGlyphs[safe: id] ?? "!"
            balloonText.fontColor = Self.balloonColors[safe: id] ?? .black
            let pop = balloonFrames > 56 ? CGFloat(64 - balloonFrames) / 8 : 1
            balloon.setScale(max(0.2, pop))
            balloon.position = CGPoint(x: 0, y: (texture?.size().height ?? 48) + 18)
        }
        burst.isHidden = animation == 0
        if animation != 0 {
            let t = CGFloat(40 - animationFrames) / 40
            burst.setScale(0.4 + t * 1.6); burst.alpha = 1 - t
            burst.position = CGPoint(x: 0, y: 24)
        }
    }
}

/// Save slots as JSON in the save folder (MZ: file1.rmmzsave …), each with a small info header.
enum SaveFiles {
    static let count = 4
    struct Info: Codable { var title: String; var mapName: String; var playFrames: Int; var leader: String; var level: Int; var savedAt: Date }
    struct Wrapper: Codable { var info: Info; var state: GameState }

    static func url(_ dir: URL, _ slot: Int) -> URL { dir.appendingPathComponent("file\(slot).json") }
    static func exists(_ dir: URL, _ slot: Int) -> Bool { FileManager.default.fileExists(atPath: url(dir, slot).path) }
    static func save(_ s: GameState, world: GameWorld, dir: URL, slot: Int) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let leader = world.partyMembers.first
        let info = Info(title: world.project.system.gameTitle, mapName: world.map.displayName.isEmpty ? world.project.mapName(s.mapId) : world.map.displayName,
                        playFrames: s.playFrames, leader: leader?.name ?? "", level: leader?.level ?? 1, savedAt: Date())
        try JSONEncoder().encode(Wrapper(info: info, state: s)).write(to: url(dir, slot), options: .atomic)
    }
    static func load(_ dir: URL, _ slot: Int) -> GameState? {
        guard let d = try? Data(contentsOf: url(dir, slot)) else { return nil }
        if let w = try? JSONDecoder().decode(Wrapper.self, from: d) { return w.state }
        return try? JSONDecoder().decode(GameState.self, from: d)   // older single-state saves
    }
    static func info(_ dir: URL, _ slot: Int) -> Info? {
        guard let d = try? Data(contentsOf: url(dir, slot)) else { return nil }
        return (try? JSONDecoder().decode(Wrapper.self, from: d))?.info
    }
}

/// Hosts a GameScene in its own window — playtest from the editor, or the whole app in exported games.
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    static var open: [PlayerWindowController] = []

    static func open(project: Project, saveDir: URL, playtest: Bool) {
        let scene = GameScene(project: project, saveDir: saveDir, playtest: playtest)
        let view = SKView(frame: NSRect(x: 0, y: 0, width: GameScene.W, height: GameScene.H))
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = playtest ? "Playtest — \(project.system.gameTitle)" : project.system.gameTitle
        window.contentView = view
        window.contentAspectRatio = NSSize(width: GameScene.W, height: GameScene.H)
        window.center()
        window.collectionBehavior = [.fullScreenPrimary]
        let c = PlayerWindowController(window: window)
        window.delegate = c
        scene.onQuit = { [weak window] in
            window?.close()
            if !playtest { NSApp.terminate(nil) }
        }
        view.presentScene(scene)
        open.append(c)
        c.showWindow(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        ((window?.contentView as? SKView)?.scene as? GameScene)?.audio.stopAll()
        (window?.contentView as? SKView)?.presentScene(nil)
        Self.open.removeAll { $0 === self }
    }
}
