import AppKit
import LakonCore
import LakonRender
import SwiftUI

/// MZ's event editor: pages (conditions → graphic → movement → options → priority/trigger) plus the command list.
struct EventEditor: View {
    @ObservedObject var doc: EditorDocument
    @State var event: MapEvent
    @State private var page = 0
    @Environment(\.dismiss) var dismiss

    init(doc: EditorDocument, event: MapEvent) {
        self.doc = doc
        _event = State(initialValue: event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Event \(String(format: "%03d", event.id))").font(.title2.bold())
                TextField("Name", text: $event.name).frame(width: 180)
                TextField("Note", text: $event.note)
                Text("(\(event.x), \(event.y))").foregroundStyle(.secondary)
            }
            HStack {
                Picker("Page", selection: $page) {
                    ForEach(event.pages.indices, id: \.self) { Text("\($0 + 1)").tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 360)
                Button("New Page") { event.pages.append(EventPage()); page = event.pages.count - 1 }
                Button("Copy Page") { event.pages.insert(event.pages[page], at: page + 1); page += 1 }
                Button("Delete Page") { event.pages.remove(at: page); page = max(0, page - 1) }.disabled(event.pages.count <= 1)
                Spacer()
            }
            if page < event.pages.count {
                PageEditor(doc: doc, page: $event.pages[page], eventId: event.id)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { doc.saveEvent(event); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 1000, height: 700)
    }
}

struct PageEditor: View {
    @ObservedObject var doc: EditorDocument
    @Binding var page: EventPage
    var eventId: Int
    @State private var pickingImage = false

    var switches: [(Int, String)] { (1..<max(2, doc.project.system.switches.count)).map { ($0, String(format: "%04d %@", $0, doc.project.system.switches[safe: $0] ?? "")) } }
    var variables: [(Int, String)] { (1..<max(2, doc.project.system.variables.count)).map { ($0, String(format: "%04d %@", $0, doc.project.system.variables[safe: $0] ?? "")) } }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Conditions") {
                        VStack(alignment: .leading, spacing: 4) {
                            condRow("Switch", $page.conditions.switch1Valid) { idPicker($page.conditions.switch1Id, switches) }
                            condRow("Switch", $page.conditions.switch2Valid) { idPicker($page.conditions.switch2Id, switches) }
                            condRow("Variable", $page.conditions.variableValid) {
                                HStack { idPicker($page.conditions.variableId, variables); Text("≥"); TextField("", value: $page.conditions.variableValue, format: .number).frame(width: 60) }
                            }
                            condRow("Self Switch", $page.conditions.selfSwitchValid) {
                                Picker("", selection: $page.conditions.selfSwitchCh) { ForEach(["A", "B", "C", "D"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 60)
                            }
                            condRow("Item", $page.conditions.itemValid) {
                                idPicker($page.conditions.itemId, doc.project.items.compactMap { $0 }.map { ($0.id, $0.name) })
                            }
                            condRow("Actor", $page.conditions.actorValid) {
                                idPicker($page.conditions.actorId, doc.project.actors.compactMap { $0 }.map { ($0.id, $0.name) })
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top) {
                        GroupBox("Image") {
                            Button { pickingImage = true } label: {
                                EventImagePreview(doc: doc, image: page.image).frame(width: 72, height: 72)
                            }.buttonStyle(.plain).help("Click to choose a character or tile")
                        }
                        GroupBox("Autonomous Movement") {
                            Form {
                                Picker("Type", selection: $page.moveType) { ForEach(MoveType.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) } }
                                Picker("Speed", selection: $page.moveSpeed) {
                                    ForEach(1...6, id: \.self) { Text(["", "1: x8 Slower", "2: x4 Slower", "3: x2 Slower", "4: Normal", "5: x2 Faster", "6: x4 Faster"][$0]).tag($0) }
                                }
                                Picker("Freq", selection: $page.moveFrequency) {
                                    ForEach(1...5, id: \.self) { Text(["", "1: Lowest", "2: Lower", "3: Normal", "4: Higher", "5: Highest"][$0]).tag($0) }
                                }
                            }
                        }
                    }
                    HStack(alignment: .top) {
                        GroupBox("Options") {
                            VStack(alignment: .leading) {
                                Toggle("Walking", isOn: $page.walkAnime)
                                Toggle("Stepping", isOn: $page.stepAnime)
                                Toggle("Direction Fix", isOn: $page.directionFix)
                                Toggle("Through", isOn: $page.through)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack {
                            GroupBox("Priority") {
                                Picker("", selection: $page.priorityType) { ForEach(Priority.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) } }.labelsHidden()
                            }
                            GroupBox("Trigger") {
                                Picker("", selection: $page.trigger) { ForEach(Trigger.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) } }.labelsHidden()
                            }
                        }
                    }
                }
            }
            .frame(width: 400)
            CommandListEditor(doc: doc, list: $page.list)
        }
        .sheet(isPresented: $pickingImage) { ImagePicker(doc: doc, image: $page.image) }
    }

    func condRow<C: View>(_ label: String, _ on: Binding<Bool>, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Toggle(label, isOn: on).frame(width: 110, alignment: .leading)
            content().disabled(!on.wrappedValue)
        }
    }

    func idPicker(_ v: Binding<Int>, _ options: [(Int, String)]) -> some View {
        Picker("", selection: v) { ForEach(options, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(maxWidth: 220)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

struct EventImagePreview: View {
    @ObservedObject var doc: EditorDocument
    var image: EventImage
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.2)))
            if let cg = render() {
                let r = CGRect(x: (size.width - CGFloat(cg.width)) / 2, y: (size.height - CGFloat(cg.height)) / 2, width: CGFloat(cg.width), height: CGFloat(cg.height))
                ctx.draw(Image(decorative: cg, scale: 1).interpolation(.none), in: r)
            }
        }
    }
    func render() -> CGImage? {
        if image.tileId > 0 {
            let c = makeCanvas(48, 48)
            doc.renderer.draw(image.tileId, in: c, x: 0, y: 0)
            return c.makeImage()
        }
        guard let sheet = doc.characterSheet(image.characterName) else { return nil }
        return sheet.cropping(to: CharacterSheet.frame(sheet: sheet, name: image.characterName, index: image.characterIndex, direction: image.direction, pattern: image.pattern))
    }
}

/// Character sheet / tile picker (MZ's "Image Selection").
struct ImagePicker: View {
    @ObservedObject var doc: EditorDocument
    @Binding var image: EventImage
    @Environment(\.dismiss) var dismiss
    @State private var sheetName = ""
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading) {
            Text("Image").font(.title2.bold())
            HStack(alignment: .top) {
                List(selection: $sheetName) {
                    Text("(None)").tag("")
                    Text("(Tileset B)").tag("::B")
                    ForEach(doc.characterNames(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 180)
                if sheetName == "::B" {
                    PaletteView(doc: doc, tab: .B, cellSize: 40)
                        .onReceive(doc.$brush) { b in
                            if let id = b.first?.first, TileID.isUpperSet(id) { image = EventImage(tileId: id) }
                        }
                } else if let sheet = doc.characterSheet(sheetName) {
                    SheetGrid(sheet: sheet, name: sheetName, image: $image)
                } else {
                    Text("No image").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                Text("Direction")
                Picker("", selection: $image.direction) { Text("Down").tag(2); Text("Left").tag(4); Text("Right").tag(6); Text("Up").tag(8) }
                    .pickerStyle(.segmented).frame(width: 260).labelsHidden()
                Picker("Pattern", selection: $image.pattern) { Text("Left").tag(0); Text("Middle").tag(1); Text("Right").tag(2) }
                    .pickerStyle(.segmented).frame(width: 260)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 900, height: 560)
        .onAppear { sheetName = image.tileId > 0 ? "::B" : image.characterName }
        .onChange(of: sheetName) { _, n in
            if n.isEmpty { image = EventImage() }
            else if n != "::B", image.characterName != n { image.characterName = n; image.characterIndex = 0; image.tileId = 0 }
        }
    }
}

struct SheetGrid: View {
    let sheet: CGImage
    let name: String
    @Binding var image: EventImage

    var big: Bool { name.range(of: "^[!$]*\\$", options: .regularExpression) != nil }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / CGFloat(sheet.width), geo.size.height / CGFloat(sheet.height), 1.5)
            let w = CGFloat(sheet.width) * scale, h = CGFloat(sheet.height) * scale
            ZStack(alignment: .topLeading) {
                Image(decorative: sheet, scale: 1).interpolation(.none).resizable().frame(width: w, height: h)
                let cw = big ? w : w / 4, ch = big ? h : h / 2
                Rectangle().stroke(Color.yellow, lineWidth: 3)
                    .frame(width: cw, height: ch)
                    .offset(x: big ? 0 : CGFloat(image.characterIndex % 4) * cw, y: big ? 0 : CGFloat(image.characterIndex / 4) * ch)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture { p in
                image.tileId = 0; image.characterName = name
                image.characterIndex = big ? 0 : Int(p.x / (w / 4)) + Int(p.y / (h / 2)) * 4
            }
        }
    }
}

// MARK: command list

struct CommandListEditor: View {
    @ObservedObject var doc: EditorDocument
    @Binding var list: [EventCommand]
    @State private var selection: Int?
    @State private var inserting: CommandKind?
    @State private var editing: (Int, CommandKind)?
    @State private var showEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Contents").font(.headline)
            List(selection: $selection) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                    Text(String(repeating: "    ", count: c.indent) + Cmd.describe(c, project: doc.project))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(color(c.code))
                        .lineLimit(1)
                        .tag(i)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: Int.self) { _ in
                Button("Edit…") { editSelected() }
                Button("Delete") { deleteSelected() }
            } primaryAction: { items in
                if let i = items.first { selection = headerIndex(i); editSelected() }
            }
            .onChange(of: selection) { _, s in
                if let s, s < list.count, headerIndex(s) != s { selection = headerIndex(s) }
            }
            .onDeleteCommand { deleteSelected() }
            HStack {
                Menu("Insert Command…") {
                    ForEach(CommandKind.groups, id: \.0) { group in
                        Section(group.0) {
                            ForEach(group.1) { k in Button(k.rawValue) { inserting = k } }
                        }
                    }
                }.frame(width: 180).disabled(!canInsert)
                Button("Edit") { editSelected() }.disabled(selection.map { CommandKind.editable(list[$0].code) == nil } ?? true)
                Button("Delete") { deleteSelected() }.disabled(!canDelete)
                Spacer()
                Text("Select a ◆ line, then insert above it. Double-click to edit.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $inserting) { k in
            CommandForm(doc: doc, kind: k, existing: nil) { cmds in insert(cmds) }
        }
        .sheet(isPresented: $showEdit) {
            if let (i, k) = editing {
                CommandForm(doc: doc, kind: k, existing: Array(list[Cmd.blockRange(list, at: i)])) { cmds in replace(i, k, cmds) }
            }
        }
    }

    func color(_ code: Int) -> Color {
        switch code {
        case 101, 401, 102, 402, 403, 404: return .primary
        case 111, 411, 412, 112, 413, 113: return .blue
        case 121, 122, 123: return .red
        case 201, 205, 203: return .purple
        case 108, 408: return .green
        default: return .primary
        }
    }

    func headerIndex(_ i: Int) -> Int {
        var j = i
        while j > 0, [401, 408].contains(list[j].code) { j -= 1 }
        return j
    }

    var insertIndex: Int { selection ?? (list.count - 1) }
    var canInsert: Bool {
        guard insertIndex < list.count else { return false }
        return ![402, 403, 404, 411, 412, 413, 401, 408].contains(list[insertIndex].code)
    }
    var canDelete: Bool {
        guard let s = selection, s < list.count else { return false }
        return !Cmd.continuation.contains(list[s].code) && !(list[s].code == 0)
    }

    func insert(_ cmds: [EventCommand]) {
        let at = insertIndex, indent = list[at].indent
        let shifted = cmds.map { c -> EventCommand in var c = c; c.indent += indent; return c }
        list.insert(contentsOf: shifted, at: at)
        selection = at + shifted.count
    }

    func deleteSelected() {
        guard canDelete, let s = selection else { return }
        list.removeSubrange(Cmd.blockRange(list, at: s))
    }

    func editSelected() {
        guard let s = selection, s < list.count, let k = CommandKind.editable(list[s].code) else { return }
        editing = (s, k); showEdit = true
    }

    func replace(_ i: Int, _ k: CommandKind, _ cmds: [EventCommand]) {
        let indent = list[i].indent
        if k == .branch {
            // Only the condition changes; bodies stay.
            list[i].parameters = cmds[0].parameters
            return
        }
        let shifted = cmds.map { c -> EventCommand in var c = c; c.indent += indent; return c }
        list.replaceSubrange(Cmd.blockRange(list, at: i), with: shifted)
    }
}
