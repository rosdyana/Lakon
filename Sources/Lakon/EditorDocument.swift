import AppKit
import LakonCore
import LakonRender
import SwiftUI

enum EditMode: String, CaseIterable, Identifiable {
    case map = "Map", event = "Event", region = "Region"
    var id: String { rawValue }
    var symbol: String { ["Map": "square.grid.3x3.fill", "Event": "person.crop.square", "Region": "number.square"][rawValue]! }
}

enum DrawTool: String, CaseIterable, Identifiable {
    case pencil = "Pencil", rectangle = "Rectangle", fill = "Fill", eraser = "Eraser"
    var id: String { rawValue }
    var symbol: String { ["Pencil": "pencil", "Rectangle": "rectangle", "Fill": "drop.fill", "Eraser": "eraser"][rawValue]! }
}

/// All editor state for one open project. Views observe it; canvases call `edit` around mutations for undo.
final class EditorDocument: ObservableObject {
    let project: Project
    @Published var mapId: Int
    @Published var mode: EditMode = .map
    @Published var tool: DrawTool = .pencil
    @Published var zoom: CGFloat = 1
    /// Palette selection as a grid of tile IDs (multi-tile stamps like MZ's rectangular palette selection).
    @Published var brush: [[Int]] = [[DefaultArt.a2(DefaultArt.grass)]]
    @Published var region = 1
    @Published var selectedEventId: Int?
    @Published var dirty = false
    @Published var revision = 0          // bump to force canvases to redraw
    @Published var editingEvent: MapEvent?
    @Published var showDatabase = false
    @Published var mapPropertiesFor: Int?
    @Published var status = ""

    private var undoStack: [(Int, GameMap)] = []
    private var redoStack: [(Int, GameMap)] = []
    private var renderers: [Int: TileRenderer] = [:]
    private var characterSheets: [String: CGImage] = [:]

    init(project: Project) {
        self.project = project
        mapId = project.orderedMapInfos.first?.id ?? 1
    }

    var title: String { project.system.gameTitle }

    var map: GameMap {
        get { project.maps[mapId] ?? GameMap(width: 17, height: 13) }
        set { project.maps[mapId] = newValue }
    }

    var tileset: Tileset { project.tileset(for: map) }

    func renderer(for tileset: Tileset) -> TileRenderer {
        if let r = renderers[tileset.id] { return r }
        let r = TileRenderer(project: project, tileset: tileset)
        renderers[tileset.id] = r
        return r
    }
    var renderer: TileRenderer { renderer(for: tileset) }

    func characterSheet(_ name: String) -> CGImage? {
        guard !name.isEmpty else { return nil }
        if let s = characterSheets[name] { return s }
        let s = loadPNG(project.imageURL("characters", name))
        characterSheets[name] = s
        return s
    }
    func characterSheetCache(_ key: String, _ make: () -> CGImage?) -> CGImage? {
        if let s = characterSheets[key] { return s }
        let s = make()
        characterSheets[key] = s
        return s
    }
    func reloadImages() { renderers = [:]; characterSheets = [:]; revision += 1 }

    func characterNames() -> [String] {
        let dir = project.root.appendingPathComponent("img/characters")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".png") }.map { String($0.dropLast(4)) }.sorted()
    }

    // MARK: editing with undo

    func beginEdit() {
        undoStack.append((mapId, map))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }
    func touched() { dirty = true; revision += 1 }

    func edit(_ f: (inout GameMap) -> Void) {
        beginEdit()
        var m = map; f(&m); map = m
        touched()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func undo() {
        guard let (id, m) = undoStack.popLast() else { return }
        redoStack.append((id, project.maps[id] ?? m))
        project.maps[id] = m; mapId = id; touched()
    }
    func redo() {
        guard let (id, m) = redoStack.popLast() else { return }
        undoStack.append((id, project.maps[id] ?? m))
        project.maps[id] = m; mapId = id; touched()
    }

    // MARK: map operations

    func stamp(at x: Int, _ y: Int, into m: inout GameMap) {
        for (dy, row) in brush.enumerated() { for (dx, id) in row.enumerated() where id > 0 {
            m.place(id, x + dx, y + dy)
        } }
    }

    func newMap() {
        let id = project.createMap(name: String(format: "MAP%03d", (project.mapInfos.compactMap { $0?.id }.max() ?? 0) + 1),
                                   fill: DefaultArt.a2(DefaultArt.grass))
        var m = project.maps[id]!
        if tileset.tilesetNames[1] != "Lakon_A2" { m.data = m.data.map { _ in 0 } }
        for y in 0..<m.height { for x in 0..<m.width { m.refreshAutotile(x, y, 0) } }
        project.maps[id] = m
        mapId = id
        touched()
    }

    func deleteMap(_ id: Int) {
        guard project.maps.count > 1 else { status = "A project needs at least one map."; return }
        project.deleteMap(id)
        if mapId == id { mapId = project.orderedMapInfos.first?.id ?? 1 }
        undoStack.removeAll { $0.0 == id }; redoStack.removeAll { $0.0 == id }
        touched()
    }

    // MARK: events

    /// A draft only; it is added to the map when the event editor's OK is pressed (as in MZ).
    func createEvent(at x: Int, _ y: Int) -> MapEvent {
        MapEvent(id: map.nextEventId(), x: x, y: y)
    }

    func saveEvent(_ e: MapEvent) {
        edit { m in
            while m.events.count <= e.id { m.events.append(nil) }
            m.events[e.id] = e
        }
    }

    func deleteEvent(_ id: Int) {
        edit { m in if id < m.events.count { m.events[id] = nil } }
        while let last = map.events.last, last == nil, map.events.count > 1 { var m = map; m.events.removeLast(); map = m }
        selectedEventId = nil
    }

    func moveEvent(_ id: Int, to x: Int, _ y: Int) {
        guard map.isValid(x, y), map.event(at: x, y) == nil else { return }
        edit { m in m.events[id]?.x = x; m.events[id]?.y = y }
    }

    func setStartPosition(_ x: Int, _ y: Int) {
        project.system.startMapId = mapId; project.system.startX = x; project.system.startY = y
        touched()
    }

    /// MZ-style quick events.
    func quickTreasure(at x: Int, _ y: Int, itemId: Int) {
        var e = MapEvent(id: map.nextEventId(), x: x, y: y)
        e.name = "Treasure"
        var closed = EventPage()
        closed.image = EventImage(characterName: "!Objects", characterIndex: 0, direction: 2)
        closed.priorityType = 1; closed.directionFix = true
        let name = itemId < project.items.count ? project.items[itemId]?.name ?? "item" : "item"
        closed.list = [Cmd.moveRoute(character: 0, [(36, []), (17, []), (15, [3]), (18, []), (15, [3]), (19, []), (35, [])]),
                       Cmd.item(itemId, 1)] + Cmd.text(["Obtained \(name)!"]) + [Cmd.selfSwitch("A", true), .end(0)]
        var open = closed
        open.image.direction = 8
        open.conditions.selfSwitchValid = true
        open.list = [.end(0)]
        e.pages = [closed, open]
        saveEvent(e)
    }
    func quickTransfer(at x: Int, _ y: Int) {
        var e = MapEvent(id: map.nextEventId(), x: x, y: y)
        e.name = "Transfer"
        e.pages[0].trigger = Trigger.playerTouch.rawValue
        e.pages[0].list = [Cmd.transfer(map: mapId, x: x, y: y), .end(0)]
        saveEvent(e)
        editingEvent = map.events[e.id] ?? e
    }

    // MARK: persistence

    func save() {
        do { try project.save(); dirty = false; status = "Saved \(Date().formatted(date: .omitted, time: .standard))" }
        catch { status = "Save failed: \(error.localizedDescription)" }
    }

    func playtest() {
        save()
        do {
            let fresh = try Project.load(from: project.root)
            PlayerWindowController.open(project: fresh, saveDir: project.root.appendingPathComponent("save"), playtest: true)
        } catch { status = "Playtest failed: \(error.localizedDescription)" }
    }

    func exportWeb() {
        save()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the HTML5 build of \(title) (a folder and a .zip for itch.io)"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let r = try WebExporter.export(project: project, to: dir)
            status = "Exported \(r.zip.lastPathComponent)" + (r.warnings.isEmpty ? "" : " — " + r.warnings.joined(separator: " "))
            NSWorkspace.shared.activateFileViewerSelecting([r.zip])
        } catch { status = "Web export failed: \(error.localizedDescription)" }
    }

    func export() {
        save()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for \(title).app"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let app = try Exporter.exportApp(project: project, to: dir)
            status = "Exported \(app.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }
}
