import AppKit
import LakonCore
import LakonRender
import SwiftUI

/// Exported games carry their project in Resources/Game and boot straight into the player.
let bundledGame = Bundle.main.resourceURL?.appendingPathComponent("Game")

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--make-sample" {
    // lakon --make-sample <dir>            create the demo project
    do { _ = try SampleProject.create(at: URL(fileURLWithPath: args[2]), title: "Lakon Demo"); print("created \(args[2])"); exit(0) }
    catch { print("error: \(error)"); exit(1) }
} else if args.count >= 5, args[1] == "--render-map" {
    // lakon --render-map <project> <mapId> <out.png>   render a map with its event graphics (docs / CI evidence)
    do {
        let p = try Project.load(from: URL(fileURLWithPath: args[2]))
        let id = Int(args[3]) ?? 1
        guard let m = p.maps[id] else { print("no map \(id)"); exit(1) }
        let ts = p.tileset(for: m)
        let r = TileRenderer(project: p, tileset: ts)
        let ctx = makeCanvas(m.width * tileSize, m.height * tileSize)
        for img in [r.renderMap(m, tileset: ts, x0: 0, y0: 0, cols: m.width, rows: m.height, upper: false)] { if let img { ctx.drawUpright(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height)) } }
        for e in m.liveEvents {
            let im = e.pages[0].image
            guard !im.characterName.isEmpty, let sheet = loadPNG(p.imageURL("characters", im.characterName)),
                  let f = sheet.cropping(to: CharacterSheet.frame(sheet: sheet, name: im.characterName, index: im.characterIndex, direction: im.direction, pattern: im.pattern)) else { continue }
            let shift = im.characterName.hasPrefix("!") ? 0 : 6
            ctx.drawUpright(f, in: CGRect(x: e.x * tileSize, y: e.y * tileSize - shift, width: f.width, height: f.height))
        }
        if let up = r.renderMap(m, tileset: ts, x0: 0, y0: 0, cols: m.width, rows: m.height, upper: true) { ctx.drawUpright(up, in: CGRect(x: 0, y: 0, width: up.width, height: up.height)) }
        try writePNG(ctx.makeImage()!, to: URL(fileURLWithPath: args[4]))
        print("wrote \(args[4])"); exit(0)
    } catch { print("error: \(error)"); exit(1) }
}

if args.count >= 3, args[1] == "--decode-audio" {
    // lakon --decode-audio <file.ogg|wav|m4a>   decoder check: prints format, length and RPG Maker loop tags
    let url = URL(fileURLWithPath: args[2])
    guard let d = url.pathExtension.lowercased() == "ogg" ? AudioPlayer.decodeOgg(url) : AudioPlayer.decodeAV(url) else { print("decode failed"); exit(1) }
    let f = d.buffer.format
    print("\(url.lastPathComponent): \(Int(f.sampleRate)) Hz, \(f.channelCount) ch, \(d.buffer.frameLength) frames (\(String(format: "%.2f", Double(d.buffer.frameLength) / f.sampleRate)) s), LOOPSTART=\(d.loopStart.map(String.init) ?? "-") LOOPLENGTH=\(d.loopLength.map(String.init) ?? "-")")
    exit(0)
}
if args.count >= 4, args[1] == "--export-web" {
    // lakon --export-web <project> <outDir>   HTML5 build for itch.io: <Title>-web/ and <Title>-web.zip
    do {
        let r = try WebExporter.export(project: try Project.load(from: URL(fileURLWithPath: args[2])), to: URL(fileURLWithPath: args[3]))
        print("exported \(r.folder.path) (\(r.images) images, \(r.transcoded) ogg→m4a, \(r.copiedAudio) audio copied)")
        print("zip \(r.zip.path)")
        for w in r.warnings { print("warning: \(w)") }
        exit(0)
    } catch { print("error: \(error.localizedDescription)"); exit(1) }
}
if args.count >= 5, args[1] == "--sim" {
    // lakon --sim <project> <script.json> <out.txt>   headless scripted run; one snapshot line per frame (web parity check)
    do {
        let p = try Project.load(from: URL(fileURLWithPath: args[2]))
        let script = try JSONDecoder().decode(Simulation.Script.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        try (Simulation.run(project: p, script: script).joined(separator: "\n") + "\n").write(toFile: args[4], atomically: true, encoding: .utf8)
        print("wrote \(args[4])"); exit(0)
    } catch { print("error: \(error)"); exit(1) }
}
if args.count >= 4, args[1] == "--import" {
    // lakon --import <mzProject> <newLakonProject>   (source is only read)
    do { let p = try Project.importMZ(from: URL(fileURLWithPath: args[2]), to: URL(fileURLWithPath: args[3]))
         print("imported \(p.maps.count) maps, \(p.tilesets.compactMap { $0 }.count) tilesets, \(p.actors.compactMap { $0 }.count) actors, \(p.commonEvents.compactMap { $0 }.count) common events"); exit(0) }
    catch { print("error: \(error)"); exit(1) }
}
if args.count >= 4, args[1] == "--export" {
    // lakon --export <project> <outDir>    build a standalone <Title>.app (same as Game ▸ Export as Mac App)
    do { let app = try Exporter.exportApp(project: try Project.load(from: URL(fileURLWithPath: args[2])), to: URL(fileURLWithPath: args[3])); print("exported \(app.path)"); exit(0) }
    catch { print("error: \(error)"); exit(1) }
}

if let game = bundledGame, FileManager.default.fileExists(atPath: game.appendingPathComponent("data/System.json").path) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    final class PlayerAppDelegate: NSObject, NSApplicationDelegate {
        let game: URL
        init(game: URL) { self.game = game }
        func applicationDidFinishLaunching(_ n: Notification) {
            do {
                let project = try Project.load(from: game)
                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(Bundle.main.bundleIdentifier ?? project.system.gameTitle)
                PlayerWindowController.open(project: project, saveDir: support, playtest: false)
                if let out = SmokeTest.env["LAKON_SMOKE_OUT"] {   // exported-game smoke: snapshot the title screen
                    Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in SmokeTest.scene()?.update(CACurrentMediaTime()) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        SmokeTest.snapGame(URL(fileURLWithPath: out).appendingPathComponent("10-exported-title.png")); NSApp.terminate(nil)
                    }
                }
            } catch {
                let a = NSAlert(); a.messageText = "Could not load game data"; a.informativeText = error.localizedDescription; a.runModal()
                NSApp.terminate(nil)
            }
        }
        func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    }
    let delegate = PlayerAppDelegate(game: game)
    app.delegate = delegate
    let menu = NSMenu(), appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    app.mainMenu = menu
    app.run()
} else {
    LakonEditorApp.main()
}

struct LakonEditorApp: App {
    @StateObject private var model = AppModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("Lakon", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear { if SmokeTest.enabled { SmokeTest.run(model: model) } }
        }
        .commands { EditorCommands(model: model) }
    }
}
