import AppKit
import LakonCore
import SpriteKit

/// Scripted UI smoke run: LAKON_SMOKE_PROJECT=<dir> LAKON_SMOKE_OUT=<dir> Lakon
/// Opens the project, snapshots the editor, starts a playtest, drives keys, snapshots the game.
/// Uses the app's own rendering (no Screen Recording permission needed).
enum SmokeTest {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var enabled: Bool { env["LAKON_SMOKE_PROJECT"] != nil }

    static func run(model: AppModel) {
        guard let proj = env["LAKON_SMOKE_PROJECT"], let out = env["LAKON_SMOKE_OUT"] else { return }
        let outDir = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        model.openProject(URL(fileURLWithPath: proj))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.setFrame(NSRect(x: 40, y: 40, width: 1500, height: 900), display: true)
        var steps: [(Double, () -> Void)] = []
        func at(_ t: Double, _ f: @escaping () -> Void) { steps.append((t, f)) }
        func key(_ code: UInt16, hold: Double = 0.05, _ t: Double) {
            at(t) {
                if let w = scene()?.world { print(String(format: "t=%.1f key=%d pos=(%d,%d) dir=%d msg=%@ running=%@", t, code, w.player.x, w.player.y, w.player.direction, w.message == nil ? "no" : "yes", w.isEventRunning ? "yes" : "no")) }
                scene()?.keyDown(with: ev(code, down: true))
            }
            at(t + hold) { scene()?.keyUp(with: ev(code, down: false)) }
        }
        at(1.5) { snapEditor(outDir.appendingPathComponent("01-editor-map.png")) }
        at(1.7) { model.doc?.mode = .event }
        at(2.2) { snapEditor(outDir.appendingPathComponent("02-editor-events.png")) }
        at(2.4) { model.doc?.editingEvent = model.doc?.map.events[1] ?? nil }
        at(3.2) { snapSheet(outDir.appendingPathComponent("03-event-editor.png")) }
        at(3.4) { model.doc?.editingEvent = nil; model.doc?.mode = .map }
        if env["LAKON_SMOKE_EDITOR_ONLY"] != nil {
            at(3.6) { capture(outDir.appendingPathComponent("e01-editor-window.png"), sheet: false) }
            at(4.0) { model.doc?.showDatabase = true }
            for (i, tab) in ["Troops", "Animations", "Skills", "Actors", "System"].enumerated() {
                at(5.0 + Double(i) * 2.5) { NotificationCenter.default.post(name: .lakonSelectDatabaseTab, object: tab) }
                at(6.8 + Double(i) * 2.5) { capture(outDir.appendingPathComponent("e1\(i)-db-\(tab.prefix(5)).png"), sheet: true) }
            }
            at(18.0) { model.doc?.showDatabase = false }
            at(18.6) { model.doc?.mapPropertiesFor = 4 }
            at(20.0) { capture(outDir.appendingPathComponent("e20-map-properties.png"), sheet: true) }
            at(20.5) { model.doc?.mapPropertiesFor = nil }
            at(21.0) { NSApp.terminate(nil) }
            for (t, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
            return
        }
        at(4.0) {
            model.doc?.playtest()
            // SKView's display link stops when the display sleeps; tick manually (time-based, so no double steps).
            Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in scene()?.update(CACurrentMediaTime()) }
            guard let sc = scene() else { print("no scene"); return }
            var q: [GameScene.ScriptStep] = []
            func idle(_ n: Int) { q += Array(repeating: .input(InputState()), count: n) }
            func hold(_ d: Int, _ n: Int) { q += Array(repeating: .input(InputState(dir4: d)), count: n) }
            func tap(_ i: InputState) { q.append(.input(i)); idle(2) }
            func snap(_ name: String) { q.append(.action { snapGame(outDir.appendingPathComponent(name)) }) }
            func log(_ tag: String) { q.append(.action {
                let w = sc.world
                print("\(tag): pos=(\(w.player.x),\(w.player.y)) dir=\(w.player.direction) map=\(w.state.mapId) switch1=\(w.state.switchValue(1)) var1=\(w.state.variable(1)) gold=\(w.state.gold) items=\(w.state.items) msg=\(w.message?.text.prefix(40) ?? "-")")
            }) }
            func ui(_ u: UIInput) { q.append(.ui(u)); idle(2) }
            func okUI() { ui(UIInput(ok: true)) }
            idle(70); snap("04-intro-picture.png")
            tap(InputState(ok: true)); tap(InputState(ok: true)); idle(20); snap("05-name-input.png")
            q.append(.action { sc.nameUI?.name = "Bimo"; sc.nameUI?.cursor = NameController.table.count - 1 })
            okUI(); idle(10)
            for _ in 0..<4 { idle(60); tap(InputState(ok: true)); tap(InputState(ok: true)) }
            idle(30); log("after intro")
            // Elder: up, up, left, face up, talk (balloon first).
            hold(8, 1); idle(18); hold(8, 1); idle(18); hold(4, 1); idle(18); hold(8, 1); idle(4)
            tap(InputState(ok: true)); idle(20); snap("06-balloon.png"); idle(120); snap("07-dialogue.png")
            tap(InputState(ok: true)); idle(10); tap(InputState(down: true)); tap(InputState(ok: true))
            for _ in 0..<5 { idle(120); tap(InputState(ok: true)) }
            idle(10); log("after elder")
            // Menu screens
            ui(UIInput(cancel: true)); idle(6); snap("08-menu.png")
            okUI(); okUI(); idle(4); snap("09-menu-items.png"); ui(UIInput(cancel: true)); ui(UIInput(cancel: true))
            ui(UIInput(down: true)); ui(UIInput(down: true)); okUI(); okUI(); idle(4); snap("10-menu-equip.png")
            ui(UIInput(cancel: true)); ui(UIInput(cancel: true)); ui(UIInput(down: true)); okUI(); okUI(); idle(4); snap("11-menu-status.png")
            ui(UIInput(cancel: true)); ui(UIInput(cancel: true)); ui(UIInput(cancel: true)); idle(6)
            // Shop
            q.append(.action {
                sc.world.state.gainGold(500)
                sc.world.shop = ShopState(goods: [(0, 1), (0, 3), (1, 3), (2, 1), (2, 5)].map { ShopState.Good(kind: $0.0, id: $0.1, price: ShopState.basePrice(kind: $0.0, id: $0.1, sc.project)) }, purchaseOnly: false)
            })
            idle(4); okUI(); ui(UIInput(down: true)); ui(UIInput(down: true)); idle(4); snap("12-shop.png")
            ui(UIInput(cancel: true)); ui(UIInput(cancel: true)); idle(4)
            // Battle with Sekar in the party
            q.append(.action { sc.world.addActor(2); sc.world.startBattle(troopId: 2, canEscape: true, canLose: true) })
            idle(150); snap("13-battle-start.png")
            okUI(); idle(4); okUI(); idle(4); snap("14-battle-target.png"); okUI()
            ui(UIInput(down: true)); okUI(); idle(4); snap("15-battle-skills.png"); okUI(); okUI()
            idle(70); snap("16-battle-action.png")
            q.append(.action {
                // Finish the fight quickly for the victory screen.
                for e in sc.world.battle?.enemies ?? [] { e.setHp(0) }
            })
            idle(110)
            snap("17-battle-victory.png"); idle(350); for _ in 0..<4 { okUI(); idle(60) }; log("after battle")
            // World map: rain, ship, airship
            q.append(.action {
                var st = sc.world.makeSave(); st.mapId = 3; st.playerX = 20; st.playerY = 14; st.playerDirection = 6
                sc.world.load(st); sc.world.state.encounterEnabled = false
            })
            idle(140); snap("18-world-rain.png")
            hold(6, 1); idle(20); tap(InputState(ok: true)); idle(40); hold(6, 1); idle(14); hold(6, 1); idle(14); snap("19-ship.png"); log("ship")
            q.append(.action { sc.world.screen.startTint([-68, -68, 0, 68], duration: 0) })
            idle(10); snap("20-tint.png")
            // Sky Ledge: scrolling parallax, Show Animation, Change Parallax.
            q.append(.action {
                sc.world.screen.startTint([0, 0, 0, 0], duration: 0); sc.world.screen.changeWeather("none", power: 0, duration: 0)
                var st = sc.world.makeSave(); st.mapId = 4; st.playerX = 6; st.playerY = 6; st.playerDirection = 8; st.vehicleType = -1
                sc.world.load(st)
            })
            idle(90); snap("21-sky-parallax.png")
            tap(InputState(ok: true)); idle(24); snap("22-map-animation.png"); idle(60)
            idle(90); tap(InputState(ok: true)); idle(80)
            q.append(.action { sc.world.player.locate(10, 6); sc.world.player.direction = 8 })
            idle(4); tap(InputState(ok: true)); idle(150); snap("23-starlit-parallax.png"); log("sky")
            q.append(.action { NSApp.terminate(nil) })
            sc.script = q
        }
        for (t, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
    }

    static func ev(_ code: UInt16, down: Bool) -> NSEvent {
        NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    static func scene() -> GameScene? { PlayerWindowController.open.last.flatMap { ($0.window?.contentView as? SKView)?.scene as? GameScene } }

    static func write(_ rep: NSBitmapImageRep?, _ url: URL) {
        guard let data = rep?.representation(using: .png, properties: [:]) else { print("snapshot failed \(url.lastPathComponent)"); return }
        try? data.write(to: url); print("snapshot \(url.path)")
    }

    static func snap(_ view: NSView, _ url: URL) {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        if let rep { view.cacheDisplay(in: view.bounds, to: rep) }
        write(rep, url)
    }
    static func snapEditor(_ url: URL) {
        guard let w = NSApp.windows.first(where: { $0.title.contains("Lakon") || $0.contentView?.subviews.isEmpty == false }),
              let v = w.contentView?.superview ?? w.contentView else { return }
        snap(v, url)
    }
    static func snapSheet(_ url: URL) {
        guard let sheet = NSApp.windows.compactMap({ $0.attachedSheet }).first, let v = sheet.contentView else { print("no sheet"); return }
        snap(v, url)
    }
    /// Real window capture (needs Screen Recording permission) — includes native controls and toolbars.
    static func capture(_ url: URL, sheet: Bool) {
        let w = sheet ? NSApp.windows.compactMap(\.attachedSheet).first : NSApp.windows.first { $0.isVisible && $0.attachedSheet == nil && $0.title.contains("Lakon") || $0.isMainWindow }
        guard let win = w else { print("no window to capture"); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l\(win.windowNumber)", url.path]
        try? p.run(); p.waitUntilExit()
        print("captured \(url.lastPathComponent) status=\(p.terminationStatus)")
        // Without Screen Recording permission, fall back to the window's own rendering (no native chrome).
        if p.terminationStatus != 0, let v = win.contentView?.superview ?? win.contentView { snap(v, url) }
    }

    static func snapGame(_ url: URL) {
        guard let view = PlayerWindowController.open.last?.window?.contentView as? SKView, let scene = view.scene,
              let tex = view.texture(from: scene) else { print("no game view"); return }
        write(NSBitmapImageRep(cgImage: tex.cgImage()), url)
    }
}
