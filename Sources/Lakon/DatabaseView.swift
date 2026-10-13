import LakonCore
import LakonRender
import SwiftUI

/// MZ's Database window (subset): Actors, Items, Tilesets (passage ○×☆), Common Events, System.
struct DatabaseView: View {
    @ObservedObject var doc: EditorDocument
    @Environment(\.dismiss) var dismiss
    @State private var tab = "Actors"
    static let tabs = ["Actors", "Classes", "Skills", "Items", "Weapons", "Armors", "Enemies", "Troops", "States",
                       "Tilesets", "Common Events", "System", "Audio & Vehicles"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(Self.tabs, id: \.self, selection: $tab) { Text($0).tag($0) }
                    .listStyle(.sidebar).frame(width: 170)
                Divider()
                Group {
                    switch tab {
                    case "Actors": ActorsTab(doc: doc)
                    case "Classes": ClassesTab(doc: doc)
                    case "Skills": SkillsTab(doc: doc)
                    case "Items": ItemsTab(doc: doc)
                    case "Weapons": EquipTab(doc: doc, weapons: true).id("w")
                    case "Armors": EquipTab(doc: doc, weapons: false).id("a")
                    case "Enemies": EnemiesTab(doc: doc)
                    case "Troops": TroopsTab(doc: doc)
                    case "States": StatesTab(doc: doc)
                    case "Tilesets": TilesetsTab(doc: doc)
                    case "Common Events": CommonEventsTab(doc: doc)
                    case "Audio & Vehicles": AudioVehiclesTab(doc: doc)
                    default: SystemTab(doc: doc)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Spacer(); Button("Close") { doc.stopAudio(); doc.touched(); dismiss() }.keyboardShortcut(.defaultAction) }.padding(10)
        }
        .frame(width: 1240, height: 760)
        .onReceive(NotificationCenter.default.publisher(for: .lakonSelectDatabaseTab)) { n in if let t = n.object as? String { tab = t } }
    }
}

/// Shared left-hand list with Add / Delete, mirroring MZ's numbered database lists.
struct DBList<T: Identifiable>: View where T.ID == Int {
    @Binding var items: [T?]
    @Binding var selection: Int?
    var name: (T) -> String
    var make: (Int) -> T

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(items.compactMap { $0 }) { it in Text(String(format: "%04d: %@", it.id, name(it))).tag(it.id) }
            }
            HStack {
                Button { let id = items.count; items.append(make(id)); selection = id } label: { Image(systemName: "plus") }
                Button {
                    if let s = selection, s < items.count, items.compactMap({ $0 }).count > 1 { items[s] = nil; selection = items.compactMap { $0 }.first?.id }
                } label: { Image(systemName: "minus") }
                Spacer()
            }.buttonStyle(.borderless).padding(6)
        }.frame(width: 230)
    }
}

struct ActorsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    @State private var picking = false

    var body: some View {
        HStack(spacing: 0) {
            DBList(items: Binding(get: { doc.project.actors }, set: { doc.project.actors = $0; doc.dirty = true; doc.objectWillChange.send() }),
                   selection: $sel, name: { $0.name }, make: { Actor(id: $0, name: "New Actor", characterName: "Actor1", characterIndex: 0) })
            Divider()
            if let s = sel, s < doc.project.actors.count, doc.project.actors[s] != nil {
                let a = Binding(get: { doc.project.actors[s]! }, set: { doc.project.actors[s] = $0; doc.dirty = true; doc.objectWillChange.send() })
                Form {
                    TextField("Name", text: a.name)
                    TextField("Nickname", text: a.nickname)
                    TextField("Profile", text: a.profile, axis: .vertical).lineLimit(2...4)
                    Picker("Class", selection: a.classId) { ForEach(doc.classOptions, id: \.0) { Text($0.1).tag($0.0) } }
                    Stepper("Initial Level: \(a.wrappedValue.initialLevel)", value: a.initialLevel, in: 1...99)
                    Stepper("Max Level: \(a.wrappedValue.maxLevel)", value: a.maxLevel, in: 1...99)
                    Section("Initial Equipment") {
                        ForEach(0..<5, id: \.self) { i in
                            Picker(doc.project.system.equipTypes[safe: i + 1] ?? "Slot", selection: Binding(
                                get: { a.wrappedValue.equips[safe: i] ?? 0 },
                                set: { v in while a.wrappedValue.equips.count < 5 { a.wrappedValue.equips.append(0) }; a.wrappedValue.equips[i] = v })) {
                                Text("None").tag(0)
                                ForEach(i == 0 ? doc.weaponOptions : doc.project.armors.compactMap { $0 }.filter { $0.etypeId == i + 1 }.map { ($0.id, $0.name) }, id: \.0) { Text($0.1).tag($0.0) }
                            }
                        }
                    }
                    TraitsEditor(doc: doc, traits: a.traits)
                    LabeledContent("Walking Character") {
                        Button {
                            picking = true
                        } label: {
                            EventImagePreview(doc: doc, image: EventImage(characterName: a.wrappedValue.characterName, characterIndex: a.wrappedValue.characterIndex)).frame(width: 64, height: 64)
                        }.buttonStyle(.plain)
                    }
                    Toggle("In starting party", isOn: Binding(
                        get: { doc.project.system.partyMembers.contains(s) },
                        set: { v in
                            doc.project.system.partyMembers.removeAll { $0 == s }
                            if v { doc.project.system.partyMembers.append(s) }
                            doc.dirty = true; doc.objectWillChange.send()
                        }))
                }
                .padding()
                .sheet(isPresented: $picking) {
                    ImagePicker(doc: doc, image: Binding(
                        get: { EventImage(characterName: a.wrappedValue.characterName, characterIndex: a.wrappedValue.characterIndex) },
                        set: { a.wrappedValue.characterName = $0.characterName; a.wrappedValue.characterIndex = $0.characterIndex }))
                }
            } else { Spacer() }
        }
    }
}

struct ItemsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1

    var body: some View {
        HStack(spacing: 0) {
            DBList(items: Binding(get: { doc.project.items }, set: { doc.project.items = $0; doc.dirty = true; doc.objectWillChange.send() }),
                   selection: $sel, name: { $0.name }, make: { Item(id: $0, name: "New Item") })
            Divider()
            if let s = sel, s < doc.project.items.count, doc.project.items[s] != nil {
                let it = Binding(get: { doc.project.items[s]! }, set: { doc.project.items[s] = $0; doc.dirty = true; doc.objectWillChange.send() })
                ScrollView {
                    Form {
                        TextField("Name", text: it.name)
                        IconField(doc: doc, index: it.iconIndex)
                        TextField("Description", text: it.description, axis: .vertical).lineLimit(2...3)
                        Picker("Item Type", selection: it.itypeId) { Text("Regular Item").tag(1); Text("Key Item").tag(2); Text("Hidden Item A").tag(3); Text("Hidden Item B").tag(4) }
                        TextField("Price", value: it.price, format: .number)
                        Toggle("Consumable", isOn: it.consumable)
                        UsableFields(doc: doc, scope: it.scope, occasion: it.occasion, hitType: it.hitType, speed: it.speed, successRate: it.successRate, repeats: it.repeats, tpGain: it.tpGain)
                        DamageEditor(doc: doc, damage: it.damage)
                        EffectsEditor(doc: doc, effects: it.effects)
                    }.padding()
                }
            } else { Spacer() }
        }
    }
}

struct TilesetsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    @State private var tab: PaletteTab = .A

    var body: some View {
        HStack(spacing: 0) {
            DBList(items: Binding(get: { doc.project.tilesets }, set: { doc.project.tilesets = $0; doc.dirty = true; doc.objectWillChange.send() }),
                   selection: $sel, name: { $0.name }, make: { Tileset(id: $0, name: "New Tileset", names: []) })
            Divider()
            if let s = sel, s < doc.project.tilesets.count, let ts = doc.project.tilesets[s] {
                let t = Binding(get: { doc.project.tilesets[s]! }, set: { doc.project.tilesets[s] = $0; doc.dirty = true; doc.reloadImages() })
                HStack(alignment: .top) {
                    Form {
                        TextField("Name", text: t.name)
                        ForEach(0..<9, id: \.self) { i in
                            TextField(["A1", "A2", "A3", "A4", "A5", "B", "C", "D", "E"][i], text: t.tilesetNames[i])
                        }
                        Text("Image names refer to img/tilesets/<name>.png in MZ's sheet layouts.").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 300).padding()
                    VStack {
                        Picker("", selection: $tab) { ForEach(PaletteTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                        Text("Passage — click to cycle ○ passable → × blocked → ☆ above characters").font(.caption)
                        PaletteView(doc: doc, tab: tab, cellSize: 40, tileset: ts) { id in
                            var tt = doc.project.tilesets[s]!
                            let ids = TileID.isAutotile(id) ? (0..<48).map { TileID.make(kind: TileID.kind(id), shape: $0) } : [id]
                            let f = tt.flags[ids[0]]
                            let next = f & 0x10 != 0 ? 0 : (f & 0x0f) == 0x0f ? 0x10 : 0x0f
                            for i in ids { tt.flags[i] = (tt.flags[i] & ~0x1f) | next }
                            doc.project.tilesets[s] = tt
                            doc.dirty = true; doc.revision += 1
                        }
                    }.padding()
                }
            } else { Spacer() }
        }
    }
}

struct CommonEventsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1

    var body: some View {
        HStack(spacing: 0) {
            DBList(items: Binding(get: { doc.project.commonEvents }, set: { doc.project.commonEvents = $0; doc.dirty = true; doc.objectWillChange.send() }),
                   selection: $sel, name: { $0.name }, make: { CommonEvent(id: $0, name: "New Common Event") })
            Divider()
            if let s = sel, s < doc.project.commonEvents.count, doc.project.commonEvents[s] != nil {
                let ce = Binding(get: { doc.project.commonEvents[s]! }, set: { doc.project.commonEvents[s] = $0; doc.dirty = true; doc.objectWillChange.send() })
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Name", text: ce.name).frame(width: 220)
                        Picker("Trigger", selection: ce.trigger) { Text("None").tag(0); Text("Autorun").tag(1); Text("Parallel").tag(2) }.frame(width: 200)
                        Picker("Switch", selection: ce.switchId) {
                            ForEach(1..<max(2, doc.project.system.switches.count), id: \.self) { i in
                                Text(String(format: "%04d %@", i, doc.project.system.switches[safe: i] ?? "")).tag(i)
                            }
                        }.disabled(ce.wrappedValue.trigger == 0)
                    }
                    CommandListEditor(doc: doc, list: ce.list)
                }.padding()
            } else { Spacer() }
        }
    }
}

struct SystemTab: View {
    @ObservedObject var doc: EditorDocument

    var body: some View {
        let sys = Binding(get: { doc.project.system }, set: { doc.project.system = $0; doc.dirty = true; doc.objectWillChange.send() })
        HStack(alignment: .top, spacing: 20) {
            Form {
                TextField("Game Title", text: sys.gameTitle)
                TextField("Currency", text: sys.currencyUnit)
                LabeledContent("Start Position", value: "\(doc.project.mapName(sys.wrappedValue.startMapId)) (\(sys.wrappedValue.startX), \(sys.wrappedValue.startY))")
                Text("Right-click the map in Event mode → Set Player Starting Position.").font(.caption).foregroundStyle(.secondary)
            }.frame(width: 360)
            NameList(title: "Switches", names: sys.switches)
            NameList(title: "Variables", names: sys.variables)
        }.padding()
    }
}

struct NameList: View {
    let title: String
    @Binding var names: [String]
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Stepper("\(max(0, names.count - 1))", onIncrement: { names += Array(repeating: "", count: 10) },
                        onDecrement: { if names.count > 11 { names.removeLast(10) } })
            }
            List {
                ForEach(1..<max(1, names.count), id: \.self) { i in
                    HStack {
                        Text(String(format: "%04d", i)).monospacedDigit().foregroundStyle(.secondary)
                        TextField("", text: Binding(get: { names[safe: i] ?? "" }, set: { if i < names.count { names[i] = $0 } }))
                    }
                }
            }
        }.frame(width: 260)
    }
}

extension Notification.Name {
    /// Lets automation (smoke runs) switch the database tab.
    static let lakonSelectDatabaseTab = Notification.Name("lakonSelectDatabaseTab")
}
