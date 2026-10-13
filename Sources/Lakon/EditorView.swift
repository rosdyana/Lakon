import AppKit
import LakonCore
import LakonRender
import SwiftUI

final class AppModel: ObservableObject {
    @Published var doc: EditorDocument?
    @Published var error: String?

    func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.nameFieldStringValue = "My RPG"
        panel.prompt = "Create"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let p = try SampleProject.create(at: url, title: url.lastPathComponent)
            doc = EditorDocument(project: p)
            remember(url)
        } catch { self.error = error.localizedDescription }
    }

    func openProject(_ url: URL? = nil) {
        var target = url
        if target == nil {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = true
            panel.allowedContentTypes = []
            panel.message = "Choose a Lakon project folder (or its game.lakon file)"
            guard panel.runModal() == .OK else { return }
            target = panel.url
        }
        guard var dir = target else { return }
        if !dir.hasDirectoryPath && dir.lastPathComponent == Project.markerFile { dir = dir.deletingLastPathComponent() }
        do { doc = EditorDocument(project: try Project.load(from: dir)); remember(dir) }
        catch { self.error = error.localizedDescription }
    }

    func importMZ() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose an RPG Maker MZ / MV project folder (it will only be read)"
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let save = NSSavePanel()
        save.title = "Save Imported Project As"
        save.nameFieldStringValue = src.lastPathComponent + " (Lakon)"
        guard save.runModal() == .OK, let dst = save.url else { return }
        do {
            let p = try Project.importMZ(from: src, to: dst)
            doc = EditorDocument(project: p); remember(dst)
        } catch { self.error = error.localizedDescription }
    }

    var recents: [URL] {
        (UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("data/System.json").path) }
    }
    private func remember(_ url: URL) {
        var r = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
        r.removeAll { $0 == url.path }; r.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(r.prefix(8)), forKey: "recentProjects")
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if let doc = model.doc { EditorView(doc: doc) } else { WelcomeView(model: model) }
        }
        .alert("Error", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "theatermasks.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Lakon").font(.system(size: 40, weight: .bold, design: .rounded))
            Text("A native macOS RPG maker — maps, events, database, playtest, export.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { model.newProject() } label: { Label("New Project…", systemImage: "plus") }.keyboardShortcut("n")
                Button { model.openProject() } label: { Label("Open…", systemImage: "folder") }.keyboardShortcut("o")
                Button { model.importMZ() } label: { Label("Import MZ Project…", systemImage: "square.and.arrow.down") }
            }.controlSize(.large)
            if !model.recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(model.recents, id: \.self) { url in
                        Button(url.lastPathComponent) { model.openProject(url) }.buttonStyle(.link)
                    }
                }.frame(width: 320, alignment: .leading)
            }
        }
        .padding(40)
        .frame(minWidth: 720, minHeight: 480)
    }
}

struct EditorView: View {
    @ObservedObject var doc: EditorDocument
    @State private var tab: PaletteTab = .A

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(PaletteTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().padding(6)
                PaletteView(doc: doc, tab: tab)
                    .frame(minHeight: 200)
                Divider()
                MapTreeView(doc: doc).frame(minHeight: 140, idealHeight: 200)
            }
            .frame(minWidth: 296, idealWidth: 296, maxWidth: 296)

            VStack(spacing: 0) {
                MapCanvas(doc: doc)
                Divider()
                HStack {
                    Text(doc.project.mapName(doc.mapId)).bold()
                    Text("\(doc.map.width)×\(doc.map.height)").foregroundStyle(.secondary)
                    if doc.mode == .region {
                        Stepper("Region \(doc.region)", value: $doc.region, in: 0...255).fixedSize()
                    }
                    Spacer()
                    Text(doc.status).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.callout).padding(.horizontal, 10).padding(.vertical, 5)
            }
            .frame(minWidth: 500)
        }
        .toolbar { toolbar }
        .navigationTitle(doc.title + (doc.dirty ? " — Edited" : ""))
        .sheet(item: $doc.editingEvent) { e in EventEditor(doc: doc, event: e) }
        .sheet(isPresented: $doc.showDatabase) { DatabaseView(doc: doc) }
        .sheet(item: Binding(get: { doc.mapPropertiesFor.map { IdentifiedInt(id: $0) } }, set: { doc.mapPropertiesFor = $0?.id })) { m in
            MapPropertiesSheet(doc: doc, mapId: m.id)
        }
        .focusedSceneValue(\.editorDocument, doc)
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { doc.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }.help("Save (⌘S)")
            Button { doc.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!doc.canUndo)
            Button { doc.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!doc.canRedo)
        }
        ToolbarItemGroup {
            Picker("Mode", selection: $doc.mode) {
                ForEach(EditMode.allCases) { m in Label(m.rawValue, systemImage: m.symbol).tag(m) }
            }.pickerStyle(.segmented).help("Edit mode")
            Picker("Tool", selection: $doc.tool) {
                ForEach(DrawTool.allCases) { t in Label(t.rawValue, systemImage: t.symbol).tag(t) }
            }.pickerStyle(.segmented).disabled(doc.mode == .event).help("Drawing tool (Option-click picks a tile)")
            Picker("Zoom", selection: $doc.zoom) {
                Text("100%").tag(CGFloat(1)); Text("50%").tag(CGFloat(0.5)); Text("25%").tag(CGFloat(0.25))
            }.frame(width: 90)
            Button { doc.showDatabase = true } label: { Label("Database", systemImage: "cylinder.split.1x2") }.help("Database (⌘D)")
            Button { doc.playtest() } label: { Label("Playtest", systemImage: "play.fill") }.help("Playtest (⌘R)")
            Menu {
                Button("Export as Mac App…") { doc.export() }
                Button("Export for Web (itch.io)…") { doc.exportWeb() }
            } label: { Label("Export", systemImage: "shippingbox") }.help("Deploy as a Mac app or an HTML5 build for itch.io")
        }
    }
}

struct IdentifiedInt: Identifiable { let id: Int }

struct MapTreeView: View {
    @ObservedObject var doc: EditorDocument

    struct Node: Identifiable { let id: Int; let name: String; var children: [Node]? }

    func nodes(parent: Int) -> [Node] {
        doc.project.orderedMapInfos.filter { $0.parentId == parent }.map { info in
            let kids = nodes(parent: info.id)
            return Node(id: info.id, name: info.name, children: kids.isEmpty ? nil : kids)
        }
    }

    var body: some View {
        let _ = doc.revision
        List(selection: Binding(get: { doc.mapId }, set: { if let v = $0 { doc.mapId = v; doc.selectedEventId = nil; doc.revision += 1 } })) {
            Section(doc.title) {
                OutlineGroup(nodes(parent: 0), children: \.children) { n in
                    Label(n.name, systemImage: "map").tag(n.id)
                        .contextMenu {
                            Button("Properties…") { doc.mapPropertiesFor = n.id }
                            Button("New Map") { doc.newMap() }
                            Divider()
                            Button("Delete", role: .destructive) { doc.deleteMap(n.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu { Button("New Map") { doc.newMap() } }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { doc.newMap() } label: { Image(systemName: "plus") }.help("New map")
                Button { doc.mapPropertiesFor = doc.mapId } label: { Image(systemName: "slider.horizontal.3") }.help("Map properties")
                Spacer()
            }.buttonStyle(.borderless).padding(6)
        }
    }
}

struct MapPropertiesSheet: View {
    @ObservedObject var doc: EditorDocument
    let mapId: Int
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var width = 17
    @State private var height = 13
    @State private var draft = GameMap(width: 1, height: 1)
    @State private var newTroop = 1

    var body: some View {
        VStack(alignment: .leading) {
            Text("Map Properties").font(.title2.bold())
            ScrollView {
                Form {
                    TextField("Name", text: $name)
                    TextField("Display Name", text: $draft.displayName)
                    Stepper("Width: \(width)", value: $width, in: 1...256)
                    Stepper("Height: \(height)", value: $height, in: 1...256)
                    Picker("Tileset", selection: $draft.tilesetId) {
                        ForEach(doc.project.tilesets.compactMap { $0 }) { t in Text(t.name).tag(t.id) }
                    }
                    Toggle("Disable Dashing", isOn: $draft.disableDashing)
                    Section("Audio") {
                        Toggle("Autoplay BGM", isOn: $draft.autoplayBgm)
                        if draft.autoplayBgm { AudioField(doc: doc, title: "BGM", folder: "bgm", file: $draft.bgm) }
                        Toggle("Autoplay BGS", isOn: $draft.autoplayBgs)
                        if draft.autoplayBgs { AudioField(doc: doc, title: "BGS", folder: "bgs", file: $draft.bgs) }
                    }
                    Section("Parallax Background") {
                        Picker("Image", selection: $draft.parallaxName) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/parallaxes"), id: \.self) { Text($0).tag($0) } }
                        if !draft.parallaxName.isEmpty {
                            HStack { Toggle("Loop Horizontally", isOn: $draft.parallaxLoopX); Stepper("Scroll X: \(draft.parallaxSx)", value: $draft.parallaxSx, in: -32...32).disabled(!draft.parallaxLoopX) }
                            HStack { Toggle("Loop Vertically", isOn: $draft.parallaxLoopY); Stepper("Scroll Y: \(draft.parallaxSy)", value: $draft.parallaxSy, in: -32...32).disabled(!draft.parallaxLoopY) }
                            Toggle("Show in the Editor", isOn: $draft.parallaxShow)
                            Text("Shows through empty tiles. A name starting with \"!\" scrolls with the map instead of the camera.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Battle") {
                        Toggle("Specify Battleback", isOn: $draft.specifyBattleback)
                        if draft.specifyBattleback {
                            Picker("Floor", selection: $draft.battleback1Name) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/battlebacks1"), id: \.self) { Text($0).tag($0) } }
                            Picker("Wall", selection: $draft.battleback2Name) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/battlebacks2"), id: \.self) { Text($0).tag($0) } }
                        }
                        Stepper("Encounter steps (average): \(draft.encounterStep)", value: $draft.encounterStep, in: 1...999)
                        ForEach(draft.encounterList.indices, id: \.self) { i in
                            HStack {
                                Picker("", selection: $draft.encounterList[i].troopId) { ForEach(doc.project.troops.compactMap { $0 }) { Text($0.name).tag($0.id) } }.labelsHidden()
                                Stepper("Weight \(draft.encounterList[i].weight)", value: $draft.encounterList[i].weight, in: 1...100).frame(width: 130)
                                TextField("Regions", text: Binding(get: { draft.encounterList[i].regionSet.map(String.init).joined(separator: ",") },
                                                                   set: { draft.encounterList[i].regionSet = $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }))
                                    .frame(width: 80).help("Region IDs, comma-separated. Empty = whole map.")
                                Button { draft.encounterList.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            }
                        }
                        Button("Add Encounter") { draft.encounterList.append(Encounter(troopId: doc.project.troops.compactMap { $0 }.first?.id ?? 1)) }
                    }
                    TextField("Note", text: $draft.note, axis: .vertical).lineLimit(3...6)
                }
            }
            HStack { Spacer(); Button("Cancel") { doc.stopAudio(); dismiss() }; Button("OK") { apply(); doc.stopAudio(); dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 640, height: 640)
        .onAppear {
            draft = doc.project.maps[mapId] ?? GameMap(width: 17, height: 13)
            name = doc.project.mapName(mapId); width = draft.width; height = draft.height
        }
    }

    func apply() {
        doc.project.mapInfos[mapId]?.name = name
        let prev = doc.mapId
        doc.mapId = mapId
        let d = draft
        doc.edit { m in
            m.displayName = d.displayName; m.tilesetId = d.tilesetId; m.note = d.note; m.disableDashing = d.disableDashing
            m.autoplayBgm = d.autoplayBgm; m.bgm = d.bgm; m.autoplayBgs = d.autoplayBgs; m.bgs = d.bgs
            m.specifyBattleback = d.specifyBattleback; m.battleback1Name = d.battleback1Name; m.battleback2Name = d.battleback2Name
            m.encounterStep = d.encounterStep; m.encounterList = d.encounterList
            m.parallaxName = d.parallaxName; m.parallaxLoopX = d.parallaxLoopX; m.parallaxLoopY = d.parallaxLoopY
            m.parallaxSx = d.parallaxSx; m.parallaxSy = d.parallaxSy; m.parallaxShow = d.parallaxShow
            if m.width != width || m.height != height { m.resize(width: width, height: height) }
        }
        doc.mapId = prev
        doc.reloadImages()
    }
}

// MARK: menu commands

struct EditorDocumentKey: FocusedValueKey { typealias Value = EditorDocument }
extension FocusedValues {
    var editorDocument: EditorDocument? {
        get { self[EditorDocumentKey.self] }
        set { self[EditorDocumentKey.self] = newValue }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.editorDocument) var doc
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { model.newProject() }.keyboardShortcut("n")
            Button("Open Project…") { model.openProject() }.keyboardShortcut("o")
            Button("Import RPG Maker MZ Project…") { model.importMZ() }
            Divider()
            Button("Close Project") { model.doc = nil }.disabled(doc == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { doc?.save() }.keyboardShortcut("s").disabled(doc == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { doc?.undo() }.keyboardShortcut("z").disabled(doc == nil)
            Button("Redo") { doc?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(doc == nil)
        }
        CommandMenu("Game") {
            Button("Playtest") { doc?.playtest() }.keyboardShortcut("r").disabled(doc == nil)
            Button("Database…") { doc?.showDatabase = true }.keyboardShortcut("d").disabled(doc == nil)
            Divider()
            Button("Map Mode") { doc?.mode = .map }.keyboardShortcut("1")
            Button("Event Mode") { doc?.mode = .event }.keyboardShortcut("2")
            Button("Region Mode") { doc?.mode = .region }.keyboardShortcut("3")
            Divider()
            Button("Reload Images") { doc?.reloadImages() }.disabled(doc == nil)
            Button("Export as Mac App…") { doc?.export() }.keyboardShortcut("e").disabled(doc == nil)
            Button("Export for Web (itch.io)…") { doc?.exportWeb() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(doc == nil)
            Button("Reveal Project in Finder") {
                if let d = doc { NSWorkspace.shared.activateFileViewerSelecting([d.project.root]) }
            }.disabled(doc == nil)
        }
    }
}
