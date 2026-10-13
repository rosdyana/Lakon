import AppKit
import LakonCore
import LakonRender
import SwiftUI

// Database tabs for MZ's battle data: Classes, Skills, Weapons, Armors, Enemies, Troops, States, Audio & Vehicles,
// plus the shared field editors (icons, audio, traits, effects, damage).

// MARK: shared fields

/// Icon index with a live preview from img/system/IconSet.png.
struct IconField: View {
    @ObservedObject var doc: EditorDocument
    @Binding var index: Int
    @State private var picking = false
    var body: some View {
        LabeledContent("Icon") {
            HStack {
                Button { picking = true } label: { IconImage(doc: doc, index: index).frame(width: 32, height: 32) }.buttonStyle(.plain)
                TextField("", value: $index, format: .number).frame(width: 60)
            }
        }
        .popover(isPresented: $picking) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 16), spacing: 2) {
                    ForEach(0..<(doc.iconCount), id: \.self) { i in
                        IconImage(doc: doc, index: i).frame(width: 32, height: 32)
                            .border(i == index ? Color.accentColor : .clear, width: 2)
                            .onTapGesture { index = i; picking = false }
                    }
                }.padding(8)
            }.frame(width: 580, height: 300)
        }
    }
}

struct IconImage: View {
    @ObservedObject var doc: EditorDocument
    let index: Int
    var body: some View {
        if let img = doc.icon(index) { Image(decorative: img, scale: 1).interpolation(.none).resizable() }
        else { Color.gray.opacity(0.15) }
    }
}

extension EditorDocument {
    var iconSheet: CGImage? { characterSheetCache("system/IconSet") { loadPNG(project.imageURL("system", "IconSet")) } }
    var iconCount: Int { iconSheet.map { ($0.width / 32) * ($0.height / 32) } ?? 0 }
    func icon(_ i: Int) -> CGImage? {
        guard i > 0, let s = iconSheet else { return nil }
        let cols = s.width / 32
        return s.cropping(to: CGRect(x: (i % cols) * 32, y: (i / cols) * 32, width: 32, height: 32))
    }
}

/// Audio file (name, volume, pitch, pan) with a list from audio/<folder> and a play button.
struct AudioField: View {
    @ObservedObject var doc: EditorDocument
    let title: String
    let folder: String
    @Binding var file: AudioFile
    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Picker("", selection: $file.name) {
                    Text("(None)").tag("")
                    ForEach(doc.project.assetNames("audio/\(folder)"), id: \.self) { Text($0).tag($0) }
                    if !file.name.isEmpty && !doc.project.assetNames("audio/\(folder)").contains(file.name) { Text(file.name + " (missing)").tag(file.name) }
                }.labelsHidden().frame(width: 170)
                Button { doc.previewAudio(folder, file) } label: { Image(systemName: "play.fill") }.disabled(file.name.isEmpty)
                Button { doc.stopAudio() } label: { Image(systemName: "stop.fill") }
                Text("Vol").font(.caption); TextField("", value: $file.volume, format: .number).frame(width: 40)
                Text("Pitch").font(.caption); TextField("", value: $file.pitch, format: .number).frame(width: 40)
            }
        }
    }
}

extension EditorDocument {
    private static var players: [ObjectIdentifier: AudioPlayer] = [:]
    var audioPlayer: AudioPlayer {
        if let p = Self.players[ObjectIdentifier(self)] { return p }
        let p = AudioPlayer(project: project)
        Self.players[ObjectIdentifier(self)] = p
        return p
    }
    func previewAudio(_ folder: String, _ f: AudioFile) {
        audioPlayer.stopAll()
        switch folder {
        case "bgm": audioPlayer.handle([.playBgm(f, position: 0)])
        case "bgs": audioPlayer.handle([.playBgs(f)])
        case "me": audioPlayer.handle([.playMe(f)])
        default: audioPlayer.handle([.playSe(f)])
        }
    }
    func stopAudio() { audioPlayer.stopAll() }
}

struct IdPicker: View {
    let title: String
    @Binding var id: Int
    let options: [(Int, String)]
    var none: String? = nil
    var body: some View {
        Picker(title, selection: $id) {
            if let n = none { Text(n).tag(0) }
            ForEach(options, id: \.0) { Text(String(format: "%04d %@", $0.0, $0.1)).tag($0.0) }
        }
    }
}

extension EditorDocument {
    func names<T>(_ list: [T?], _ name: (T) -> String, _ id: (T) -> Int) -> [(Int, String)] { list.compactMap { $0 }.map { (id($0), name($0)) } }
    var skillOptions: [(Int, String)] { names(project.skills, \.name, \.id) }
    var stateOptions: [(Int, String)] { names(project.states, \.name, \.id) }
    var itemOptions: [(Int, String)] { names(project.items, \.name, \.id) }
    var weaponOptions: [(Int, String)] { names(project.weapons, \.name, \.id) }
    var armorOptions: [(Int, String)] { names(project.armors, \.name, \.id) }
    var enemyOptions: [(Int, String)] { names(project.enemies, \.name, \.id) }
    var classOptions: [(Int, String)] { names(project.classes, \.name, \.id) }
    var commonEventOptions: [(Int, String)] { names(project.commonEvents, \.name, \.id) }
    func typeOptions(_ list: [String]) -> [(Int, String)] { list.enumerated().dropFirst().map { ($0.offset, $0.element) } }
    func binding<T>(_ kp: ReferenceWritableKeyPath<Project, [T?]>, _ i: Int) -> Binding<T> {
        Binding(get: { self.project[keyPath: kp][i]! }, set: { self.project[keyPath: kp][i] = $0; self.dirty = true; self.objectWillChange.send() })
    }
    func listBinding<T>(_ kp: ReferenceWritableKeyPath<Project, [T?]>) -> Binding<[T?]> {
        Binding(get: { self.project[keyPath: kp] }, set: { self.project[keyPath: kp] = $0; self.dirty = true; self.objectWillChange.send() })
    }
}

let paramNames = ["Max HP", "Max MP", "Attack", "Defense", "M.Attack", "M.Defense", "Agility", "Luck"]
let xparamNames = ["Hit", "Evasion", "Critical", "Crit Evasion", "Magic Evasion", "Magic Reflection", "Counter", "HP Regen", "MP Regen", "TP Regen"]
let sparamNames = ["Target Rate", "Guard Effect", "Recovery", "Pharmacology", "MP Cost", "TP Charge", "Physical Damage", "Magic Damage", "Floor Damage", "EXP Rate"]

/// MZ's Traits list (code / data / value).
struct TraitsEditor: View {
    @ObservedObject var doc: EditorDocument
    @Binding var traits: [Trait]
    static let codes: [(Int, String)] = [
        (11, "Element Rate"), (12, "Debuff Rate"), (13, "State Rate"), (14, "State Resist"), (21, "Parameter"), (22, "Ex-Parameter"),
        (23, "Sp-Parameter"), (31, "Attack Element"), (32, "Attack State"), (33, "Attack Speed"), (34, "Attack Times +"),
        (35, "Attack Skill"), (41, "Add Skill Type"), (42, "Seal Skill Type"), (43, "Add Skill"), (44, "Seal Skill"),
        (51, "Equip Weapon"), (52, "Equip Armor"), (53, "Lock Equip"), (54, "Seal Equip"), (61, "Action Times +"),
        (62, "Special Flag"), (64, "Party Ability"),
    ]

    func dataOptions(_ code: Int) -> [(Int, String)] {
        let s = doc.project.system
        switch code {
        case 11, 31: return doc.typeOptions(s.elements)
        case 12, 21: return paramNames.enumerated().map { ($0.offset, $0.element) }
        case 13, 14, 32: return doc.stateOptions
        case 22: return xparamNames.enumerated().map { ($0.offset, $0.element) }
        case 23: return sparamNames.enumerated().map { ($0.offset, $0.element) }
        case 35, 43, 44: return doc.skillOptions
        case 41, 42: return doc.typeOptions(s.skillTypes)
        case 51: return doc.typeOptions(s.weaponTypes)
        case 52: return doc.typeOptions(s.armorTypes)
        case 53, 54: return doc.typeOptions(s.equipTypes)
        case 62: return [(0, "Auto Battle"), (1, "Guard"), (2, "Substitute"), (3, "Preserve TP")]
        case 64: return [(0, "Encounter Half"), (1, "Encounter None"), (2, "Cancel Surprise"), (3, "Raise Preemptive"), (4, "Gold Double"), (5, "Drop Item Double")]
        default: return []
        }
    }
    func usesValue(_ c: Int) -> Bool { ![14, 31, 35, 41, 42, 43, 44, 51, 52, 53, 54, 62, 64].contains(c) }
    func isPercent(_ c: Int) -> Bool { [11, 12, 13, 21, 22, 23, 32, 61].contains(c) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("Traits").font(.headline); Spacer(); Button { traits.append(Trait(21, 0, 1)) } label: { Image(systemName: "plus") } }
            ForEach(traits.indices, id: \.self) { i in
                HStack {
                    Picker("", selection: $traits[i].code) { ForEach(Self.codes, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 150)
                    let opts = dataOptions(traits[i].code)
                    if !opts.isEmpty {
                        Picker("", selection: $traits[i].dataId) { ForEach(opts, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 150)
                    }
                    if usesValue(traits[i].code) {
                        if isPercent(traits[i].code) {
                            TextField("", value: Binding(get: { (traits[i].value * 100).rounded() }, set: { traits[i].value = $0 / 100 }), format: .number).frame(width: 60)
                            Text("%")
                        } else { TextField("", value: $traits[i].value, format: .number).frame(width: 60) }
                    }
                    Spacer()
                    Button { traits.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
        }
    }
}

/// MZ's Effects list for skills/items.
struct EffectsEditor: View {
    @ObservedObject var doc: EditorDocument
    @Binding var effects: [Effect]
    static let codes: [(Int, String)] = [(11, "Recover HP"), (12, "Recover MP"), (13, "Gain TP"), (21, "Add State"), (22, "Remove State"),
                                         (31, "Add Buff"), (32, "Add Debuff"), (33, "Remove Buff"), (34, "Remove Debuff"), (41, "Special (Escape)"),
                                         (42, "Grow"), (43, "Learn Skill"), (44, "Common Event")]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("Effects").font(.headline); Spacer(); Button { effects.append(Effect(11, 0, 0, 100)) } label: { Image(systemName: "plus") } }
            ForEach(effects.indices, id: \.self) { i in
                HStack {
                    Picker("", selection: $effects[i].code) { ForEach(Self.codes, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 150)
                    switch effects[i].code {
                    case 11, 12:
                        TextField("", value: Binding(get: { (effects[i].value1 * 100).rounded() }, set: { effects[i].value1 = $0 / 100 }), format: .number).frame(width: 50)
                        Text("% +"); TextField("", value: $effects[i].value2, format: .number).frame(width: 60)
                    case 13: TextField("", value: $effects[i].value1, format: .number).frame(width: 60)
                    case 21, 22:
                        Picker("", selection: $effects[i].dataId) { Text("Normal Attack").tag(0); ForEach(doc.stateOptions, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 150)
                        TextField("", value: Binding(get: { (effects[i].value1 * 100).rounded() }, set: { effects[i].value1 = $0 / 100 }), format: .number).frame(width: 50); Text("%")
                    case 31, 32, 33, 34, 42:
                        Picker("", selection: $effects[i].dataId) { ForEach(Array(paramNames.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }.labelsHidden().frame(width: 130)
                        if effects[i].code <= 32 || effects[i].code == 42 { TextField("", value: $effects[i].value1, format: .number).frame(width: 50); Text(effects[i].code == 42 ? "" : "turns") }
                    case 43: Picker("", selection: $effects[i].dataId) { ForEach(doc.skillOptions, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 160)
                    case 44: Picker("", selection: $effects[i].dataId) { ForEach(doc.commonEventOptions, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 160)
                    default: EmptyView()
                    }
                    Spacer()
                    Button { effects.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
        }
    }
}

struct DamageEditor: View {
    @ObservedObject var doc: EditorDocument
    @Binding var damage: Damage
    var body: some View {
        Section("Damage") {
            Picker("Type", selection: $damage.type) {
                ForEach(Array(["None", "HP Damage", "MP Damage", "HP Recover", "MP Recover", "HP Drain", "MP Drain"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
            }
            if damage.type > 0 {
                Picker("Element", selection: $damage.elementId) {
                    Text("Normal Attack").tag(-1); Text("None").tag(0)
                    ForEach(doc.typeOptions(doc.project.system.elements), id: \.0) { Text($0.1).tag($0.0) }
                }
                TextField("Formula", text: $damage.formula).font(.system(.body, design: .monospaced))
                Text("JavaScript: a = user, b = target, v[n] = variables. e.g. a.atk * 4 - b.def * 2").font(.caption).foregroundStyle(.secondary)
                Stepper("Variance: \(damage.variance)%", value: $damage.variance, in: 0...100)
                Toggle("Critical Hits", isOn: $damage.critical)
            }
        }
    }
}

struct UsableFields: View {
    @ObservedObject var doc: EditorDocument
    @Binding var scope: Int
    @Binding var occasion: Int
    @Binding var hitType: Int
    @Binding var speed: Int
    @Binding var successRate: Int
    @Binding var repeats: Int
    @Binding var tpGain: Int
    static let scopes = ["None", "1 Enemy", "All Enemies", "1 Random Enemy", "2 Random Enemies", "3 Random Enemies", "4 Random Enemies",
                         "1 Ally", "All Allies", "1 Ally (Dead)", "All Allies (Dead)", "The User", "1 Ally (Unconditional)", "All Allies (Unconditional)", "Enemies & Allies"]
    var body: some View {
        Picker("Scope", selection: $scope) { ForEach(Array(Self.scopes.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }
        Picker("Occasion", selection: $occasion) { Text("Always").tag(0); Text("Battle Screen").tag(1); Text("Menu Screen").tag(2); Text("Never").tag(3) }
        Picker("Hit Type", selection: $hitType) { Text("Certain Hit").tag(0); Text("Physical Attack").tag(1); Text("Magical Attack").tag(2) }
        HStack {
            TextField("Speed", value: $speed, format: .number)
            TextField("Success %", value: $successRate, format: .number)
            TextField("Repeat", value: $repeats, format: .number)
            TextField("TP Gain", value: $tpGain, format: .number)
        }
    }
}

struct ParamsRow: View {
    @Binding var params: [Int]
    var body: some View {
        Grid(alignment: .leading) {
            GridRow { ForEach(0..<4, id: \.self) { i in VStack(alignment: .leading) { Text(paramNames[i]).font(.caption); TextField("", value: $params[i], format: .number) } } }
            GridRow { ForEach(4..<8, id: \.self) { i in VStack(alignment: .leading) { Text(paramNames[i]).font(.caption); TextField("", value: $params[i], format: .number) } } }
        }
    }
}

// MARK: tabs

struct ClassesTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    @State private var base = [400, 40, 20, 20, 20, 20, 20, 20]
    @State private var growth = [40, 4, 2, 2, 2, 2, 2, 2]

    var body: some View {
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(\.classes), selection: $sel, name: { $0.name },
                   make: { ClassData(id: $0, name: "New Class", base: [400, 40, 20, 20, 20, 20, 20, 20], growth: [40, 4, 2, 2, 2, 2, 2, 2]) })
            Divider()
            if let s = sel, s < doc.project.classes.count, doc.project.classes[s] != nil {
                let c = doc.binding(\.classes, s)
                ScrollView {
                    Form {
                        TextField("Name", text: c.name)
                        Section("EXP Curve") {
                            HStack { ForEach(0..<4, id: \.self) { i in TextField(["Base", "Extra", "Accel A", "Accel B"][i], value: c.expParams[i], format: .number) } }
                            Text("Level 2: \(expAt(c.wrappedValue, 2))  ·  Level 10: \(expAt(c.wrappedValue, 10))  ·  Level 50: \(expAt(c.wrappedValue, 50))").font(.caption)
                        }
                        Section("Parameter Curves (value at Lv 1 / Lv 99)") {
                            Grid(alignment: .leading) {
                                ForEach(0..<8, id: \.self) { p in
                                    GridRow {
                                        Text(paramNames[p]).frame(width: 90, alignment: .leading)
                                        Text("\(c.wrappedValue.params[p][safe: 1] ?? 0) → \(c.wrappedValue.params[p][safe: 99] ?? 0)").monospacedDigit().frame(width: 120, alignment: .leading)
                                        TextField("Lv1", value: $base[p], format: .number).frame(width: 70)
                                        TextField("+/level", value: $growth[p], format: .number).frame(width: 90)
                                    }
                                }
                            }
                            Button("Regenerate curves from Lv1 + growth") {
                                var v = c.wrappedValue
                                v.params = (0..<8).map { p in (0..<100).map { lv in base[p] + growth[p] * max(0, lv - 1) } }
                                c.wrappedValue = v
                            }
                        }
                        Section("Skills to Learn") {
                            ForEach(c.wrappedValue.learnings.indices, id: \.self) { i in
                                HStack {
                                    Stepper("Lv \(c.wrappedValue.learnings[i].level)", value: c.learnings[i].level, in: 1...99).frame(width: 120)
                                    Picker("", selection: c.learnings[i].skillId) { ForEach(doc.skillOptions, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden()
                                    Button { c.wrappedValue.learnings.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                                }
                            }
                            Button("Add Skill") { c.wrappedValue.learnings.append(Learning(level: 1, skillId: 1)) }
                        }
                        TraitsEditor(doc: doc, traits: c.traits)
                    }.padding()
                }
                .onAppear { loadCurve(c.wrappedValue) }
                .onChange(of: sel) { _, _ in if let s = sel, let cl = doc.project.classes[safe: s] ?? nil { loadCurve(cl) } }
            } else { Spacer() }
        }
    }
    func loadCurve(_ c: ClassData) {
        base = (0..<8).map { c.params[$0][safe: 1] ?? 1 }
        growth = (0..<8).map { ((c.params[$0][safe: 99] ?? 1) - (c.params[$0][safe: 1] ?? 1)) / 98 }
    }
    func expAt(_ c: ClassData, _ lv: Int) -> Int {
        let p = c.expParams, l = Double(lv)
        return Int((Double(p[0]) * pow(l - 1, 0.9 + Double(p[2]) / 250) * l * (l + 1) / (6 + pow(l, 2) / 50 / Double(max(1, p[3]))) + (l - 1) * Double(p[1])).rounded())
    }
}

struct SkillsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    var body: some View {
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(\.skills), selection: $sel, name: { $0.name }, make: { Skill(id: $0, name: "New Skill") })
            Divider()
            if let s = sel, s < doc.project.skills.count, doc.project.skills[s] != nil {
                let k = doc.binding(\.skills, s)
                ScrollView {
                    Form {
                        TextField("Name", text: k.name)
                        IconField(doc: doc, index: k.iconIndex)
                        TextField("Description", text: k.description, axis: .vertical).lineLimit(2...3)
                        Picker("Skill Type", selection: k.stypeId) { Text("None").tag(0); ForEach(doc.typeOptions(doc.project.system.skillTypes), id: \.0) { Text($0.1).tag($0.0) } }
                        HStack { TextField("MP Cost", value: k.mpCost, format: .number); TextField("TP Cost", value: k.tpCost, format: .number) }
                        UsableFields(doc: doc, scope: k.scope, occasion: k.occasion, hitType: k.hitType, speed: k.speed, successRate: k.successRate, repeats: k.repeats, tpGain: k.tpGain)
                        TextField("Message", text: k.message1, prompt: Text("%1 casts %2!"))
                        DamageEditor(doc: doc, damage: k.damage)
                        EffectsEditor(doc: doc, effects: k.effects)
                        TextField("Note", text: k.note, axis: .vertical).lineLimit(1...3)
                    }.padding()
                }
            } else { Spacer() }
        }
    }
}

struct EquipTab: View {
    @ObservedObject var doc: EditorDocument
    let weapons: Bool
    @State private var sel: Int? = 1
    var body: some View {
        let kp: ReferenceWritableKeyPath<Project, [EquipItem?]> = weapons ? \.weapons : \.armors
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(kp), selection: $sel, name: { $0.name },
                   make: { EquipItem(id: $0, name: weapons ? "New Weapon" : "New Armor", etypeId: weapons ? 1 : 4) })
            Divider()
            if let s = sel, s < doc.project[keyPath: kp].count, doc.project[keyPath: kp][s] != nil {
                let e = doc.binding(kp, s)
                ScrollView {
                    Form {
                        TextField("Name", text: e.name)
                        IconField(doc: doc, index: e.iconIndex)
                        TextField("Description", text: e.description, axis: .vertical).lineLimit(2...3)
                        if weapons {
                            Picker("Weapon Type", selection: e.wtypeId) { ForEach(doc.typeOptions(doc.project.system.weaponTypes), id: \.0) { Text($0.1).tag($0.0) } }
                        } else {
                            Picker("Armor Type", selection: e.atypeId) { ForEach(doc.typeOptions(doc.project.system.armorTypes), id: \.0) { Text($0.1).tag($0.0) } }
                            Picker("Equipment Type", selection: e.etypeId) { ForEach(doc.typeOptions(doc.project.system.equipTypes).filter { $0.0 > 1 }, id: \.0) { Text($0.1).tag($0.0) } }
                        }
                        TextField("Price", value: e.price, format: .number)
                        Section("Parameter Changes") { ParamsRow(params: e.params) }
                        TraitsEditor(doc: doc, traits: e.traits)
                    }.padding()
                }
            } else { Spacer() }
        }
    }
}

struct EnemiesTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    var body: some View {
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(\.enemies), selection: $sel, name: { $0.name },
                   make: { Enemy(id: $0, name: "New Enemy", battlerName: "", params: [200, 0, 20, 20, 20, 20, 20, 20], exp: 10, gold: 10) })
            Divider()
            if let s = sel, s < doc.project.enemies.count, doc.project.enemies[s] != nil {
                let e = doc.binding(\.enemies, s)
                ScrollView {
                    HStack(alignment: .top) {
                        Form {
                            TextField("Name", text: e.name)
                            Picker("Battler Image", selection: e.battlerName) {
                                Text("(None)").tag("")
                                ForEach(doc.project.assetNames("img/enemies"), id: \.self) { Text($0).tag($0) }
                            }
                            Section("Parameters") { ParamsRow(params: e.params) }
                            HStack { TextField("EXP", value: e.exp, format: .number); TextField("Gold", value: e.gold, format: .number) }
                            Section("Drop Items") {
                                ForEach(e.wrappedValue.dropItems.indices, id: \.self) { i in
                                    HStack {
                                        Picker("", selection: e.dropItems[i].kind) { Text("None").tag(0); Text("Item").tag(1); Text("Weapon").tag(2); Text("Armor").tag(3) }.labelsHidden().frame(width: 90)
                                        let opts = [[], doc.itemOptions, doc.weaponOptions, doc.armorOptions][min(3, e.wrappedValue.dropItems[i].kind)]
                                        Picker("", selection: e.dropItems[i].dataId) { ForEach(opts, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden()
                                        Text("1 /"); TextField("", value: e.dropItems[i].denominator, format: .number).frame(width: 40)
                                        Button { e.wrappedValue.dropItems.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                                    }
                                }
                                Button("Add Drop") { e.wrappedValue.dropItems.append(DropItem(kind: 1, dataId: 1, denominator: 2)) }
                            }
                            Section("Action Patterns") {
                                ForEach(e.wrappedValue.actions.indices, id: \.self) { i in
                                    HStack {
                                        Picker("", selection: e.actions[i].skillId) { ForEach(doc.skillOptions, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 140)
                                        Picker("", selection: e.actions[i].conditionType) {
                                            ForEach(Array(["Always", "Turn", "HP", "MP", "State", "Party Level", "Switch"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                                        }.labelsHidden().frame(width: 100)
                                        if e.wrappedValue.actions[i].conditionType > 0 {
                                            TextField("", value: e.actions[i].conditionParam1, format: .number).frame(width: 46)
                                            TextField("", value: e.actions[i].conditionParam2, format: .number).frame(width: 46)
                                        }
                                        Stepper("R \(e.wrappedValue.actions[i].rating)", value: e.actions[i].rating, in: 1...9).frame(width: 90)
                                        Button { e.wrappedValue.actions.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                                    }
                                }
                                Button("Add Action") { e.wrappedValue.actions.append(EnemyAction(skillId: 1)) }
                                Text("Turn: A + B·X. HP/MP: fraction 0–1. Rating: higher = more likely (within 3 of the best).").font(.caption).foregroundStyle(.secondary)
                            }
                            TraitsEditor(doc: doc, traits: e.traits)
                        }
                        VStack {
                            if let img = loadPNG(doc.project.imageURL("enemies", e.wrappedValue.battlerName)) {
                                Image(decorative: img, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit).frame(width: 220, height: 220)
                                    .background(Color.black.opacity(0.2))
                            }
                        }.frame(width: 230)
                    }.padding()
                }
            } else { Spacer() }
        }
    }
}

struct TroopsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    @State private var page = 0
    @State private var addEnemy = 1
    var body: some View {
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(\.troops), selection: $sel, name: { $0.name }, make: { Troop(id: $0, name: "New Troop", members: []) })
            Divider()
            if let s = sel, s < doc.project.troops.count, doc.project.troops[s] != nil {
                let t = doc.binding(\.troops, s)
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Name", text: t.name).frame(width: 220)
                        Picker("", selection: $addEnemy) { ForEach(doc.enemyOptions, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 160)
                        Button("Add") { t.wrappedValue.members.append(TroopMember(enemyId: addEnemy, x: 408, y: 420)); arrange(t) }
                        Button("Clear") { t.wrappedValue.members = [] }
                        Button("Auto-name") { t.wrappedValue.name = t.wrappedValue.members.compactMap { doc.project.enemy($0.enemyId)?.name }.joined(separator: ", ") }
                        Button("Arrange") { arrange(t) }
                    }
                    TroopPreview(doc: doc, troop: t).frame(height: 230)
                    Text("Drag enemies to place them. Right-click to remove or toggle 'Appear Halfway'.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Picker("Page", selection: $page) { ForEach(t.wrappedValue.pages.indices, id: \.self) { Text("\($0 + 1)").tag($0) } }.pickerStyle(.segmented).frame(width: 240)
                        Button("New Page") { t.wrappedValue.pages.append(TroopPage()); page = t.wrappedValue.pages.count - 1 }
                        Button("Delete Page") { t.wrappedValue.pages.remove(at: page); page = max(0, page - 1) }.disabled(t.wrappedValue.pages.count <= 1)
                    }
                    if page < t.wrappedValue.pages.count {
                        let pg = Binding(get: { t.wrappedValue.pages[page] }, set: { t.wrappedValue.pages[page] = $0 })
                        HStack(alignment: .top) {
                            Form {
                                Toggle("Turn End", isOn: pg.conditions.turnEnding)
                                HStack { Toggle("Turn", isOn: pg.conditions.turnValid); TextField("", value: pg.conditions.turnA, format: .number).frame(width: 40); Text("+ X ×"); TextField("", value: pg.conditions.turnB, format: .number).frame(width: 40) }
                                HStack { Toggle("Enemy #", isOn: pg.conditions.enemyValid); TextField("", value: pg.conditions.enemyIndex, format: .number).frame(width: 30); Text("HP ≤"); TextField("", value: pg.conditions.enemyHp, format: .number).frame(width: 40); Text("%") }
                                HStack { Toggle("Actor", isOn: pg.conditions.actorValid); TextField("", value: pg.conditions.actorId, format: .number).frame(width: 30); Text("HP ≤"); TextField("", value: pg.conditions.actorHp, format: .number).frame(width: 40); Text("%") }
                                HStack { Toggle("Switch", isOn: pg.conditions.switchValid); TextField("", value: pg.conditions.switchId, format: .number).frame(width: 40) }
                                Picker("Span", selection: pg.span) { Text("Battle").tag(0); Text("Turn").tag(1); Text("Moment").tag(2) }
                            }.frame(width: 330)
                            CommandListEditor(doc: doc, list: pg.list)
                        }
                    }
                }.padding()
            } else { Spacer() }
        }
    }
    func arrange(_ t: Binding<Troop>) {
        let n = t.wrappedValue.members.count
        for i in 0..<n { t.wrappedValue.members[i].x = Int(816.0 / Double(n + 1) * Double(i + 1)); t.wrappedValue.members[i].y = 420 }
    }
}

/// Troop layout preview on the system battleback, at half scale; drag to move members.
struct TroopPreview: View {
    @ObservedObject var doc: EditorDocument
    @Binding var troop: Troop
    @State private var dragging: Int?
    let scale: CGFloat = 0.36

    var body: some View {
        let bb1 = loadPNG(doc.project.imageURL("battlebacks1", doc.project.system.battleback1Name))
        let bb2 = loadPNG(doc.project.imageURL("battlebacks2", doc.project.system.battleback2Name))
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.4))
            if let b = bb1 { Image(decorative: b, scale: 1).resizable().frame(width: 1000 * scale, height: 740 * scale).offset(x: -92 * scale, y: -58 * scale) }
            if let b = bb2 { Image(decorative: b, scale: 1).resizable().frame(width: 1000 * scale, height: 740 * scale).offset(x: -92 * scale, y: -58 * scale) }
            ForEach(troop.members.indices, id: \.self) { i in
                let m = troop.members[i]
                if let img = loadPNG(doc.project.imageURL("enemies", doc.project.enemy(m.enemyId)?.battlerName ?? "")) {
                    let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
                    Image(decorative: img, scale: 1).resizable().frame(width: w, height: h)
                        .opacity(m.hidden ? 0.4 : 1)
                        .position(x: CGFloat(m.x) * scale, y: CGFloat(m.y) * scale - h / 2)
                        .gesture(DragGesture().onChanged { v in
                            troop.members[i].x = max(0, min(816, Int(v.location.x / scale)))
                            troop.members[i].y = max(0, min(624, Int((v.location.y + h / 2) / scale)))
                        })
                        .contextMenu {
                            Button(m.hidden ? "Show at start" : "Appear Halfway") { troop.members[i].hidden.toggle() }
                            Button("Remove", role: .destructive) { troop.members.remove(at: i) }
                        }
                }
            }
        }
        .frame(width: 816 * scale, height: 624 * scale)
        .clipped()
        .border(Color.gray.opacity(0.5))
    }
}

struct StatesTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    var body: some View {
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(\.states), selection: $sel, name: { $0.name }, make: { StateData(id: $0, name: "New State") })
            Divider()
            if let s = sel, s < doc.project.states.count, doc.project.states[s] != nil {
                let st = doc.binding(\.states, s)
                ScrollView {
                    Form {
                        TextField("Name", text: st.name)
                        IconField(doc: doc, index: st.iconIndex)
                        Picker("Restriction", selection: st.restriction) {
                            ForEach(Array(["None", "Attack an enemy", "Attack anyone", "Attack an ally", "Cannot move"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                        }
                        Stepper("Priority: \(st.wrappedValue.priority)", value: st.priority, in: 0...100)
                        Section("Removal Conditions") {
                            Toggle("Remove at Battle End", isOn: st.removeAtBattleEnd)
                            Toggle("Remove by Restriction", isOn: st.removeByRestriction)
                            Picker("Auto-removal Timing", selection: st.autoRemovalTiming) { Text("None").tag(0); Text("Action End").tag(1); Text("Turn End").tag(2) }
                            HStack { Text("Duration in Turns"); TextField("", value: st.minTurns, format: .number).frame(width: 40); Text("~"); TextField("", value: st.maxTurns, format: .number).frame(width: 40) }
                            HStack { Toggle("Remove by Damage", isOn: st.removeByDamage); TextField("", value: st.chanceByDamage, format: .number).frame(width: 40); Text("%") }
                            HStack { Toggle("Remove by Walking", isOn: st.removeByWalking); TextField("", value: st.stepsToRemove, format: .number).frame(width: 50); Text("steps") }
                        }
                        Section("Messages (%1 = name)") {
                            TextField("If an actor is inflicted", text: st.message1)
                            TextField("If an enemy is inflicted", text: st.message2)
                            TextField("If the state persists", text: st.message3)
                            TextField("If the state is removed", text: st.message4)
                        }
                        TraitsEditor(doc: doc, traits: st.traits)
                    }.padding()
                }
            } else { Spacer() }
        }
    }
}

/// System 2: music, the 24 system sounds, vehicles, battlebacks, type names.
struct AudioVehiclesTab: View {
    @ObservedObject var doc: EditorDocument
    static let soundNames = ["Cursor", "OK", "Cancel", "Buzzer", "Equip", "Save", "Load", "Battle Start", "Escape", "Enemy Attack", "Enemy Damage",
                             "Enemy Collapse", "Boss Collapse 1", "Boss Collapse 2", "Actor Damage", "Actor Collapse", "Recovery", "Miss", "Evasion",
                             "Magic Evasion", "Magic Reflection", "Shop", "Use Item", "Use Skill"]
    var body: some View {
        let sys = Binding(get: { doc.project.system }, set: { doc.project.system = $0; doc.dirty = true; doc.objectWillChange.send() })
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                Form {
                    Section("Music") {
                        AudioField(doc: doc, title: "Title", folder: "bgm", file: sys.titleBgm)
                        AudioField(doc: doc, title: "Battle", folder: "bgm", file: sys.battleBgm)
                        AudioField(doc: doc, title: "Victory", folder: "me", file: sys.victoryMe)
                        AudioField(doc: doc, title: "Defeat", folder: "me", file: sys.defeatMe)
                        AudioField(doc: doc, title: "Game Over", folder: "me", file: sys.gameoverMe)
                    }
                    Section("Vehicles") {
                        ForEach(0..<3, id: \.self) { i in
                            let kp: WritableKeyPath<SystemData, VehicleData> = [\SystemData.boat, \.ship, \.airship][i]
                            let v = Binding(get: { sys.wrappedValue[keyPath: kp] }, set: { sys.wrappedValue[keyPath: kp] = $0 })
                            VehicleRow(doc: doc, name: ["Boat", "Ship", "Airship"][i], vehicle: v)
                        }
                    }
                    Section("Battlebacks") {
                        Picker("Floor", selection: sys.battleback1Name) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/battlebacks1"), id: \.self) { Text($0).tag($0) } }
                        Picker("Wall", selection: sys.battleback2Name) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/battlebacks2"), id: \.self) { Text($0).tag($0) } }
                        Toggle("Show TP in menus and battle", isOn: sys.optDisplayTp)
                        Toggle("Slip damage can kill", isOn: sys.optSlipDeath)
                        Toggle("Floor damage can kill", isOn: sys.optFloorDeath)
                    }
                }.frame(width: 560)
                Form {
                    Section("System Sounds") {
                        ForEach(0..<24, id: \.self) { i in
                            AudioField(doc: doc, title: Self.soundNames[i], folder: "se", file: sys.sounds[i])
                        }
                    }
                }.frame(width: 560)
            }.padding()
        }
    }
}

struct VehicleRow: View {
    @ObservedObject var doc: EditorDocument
    let name: String
    @Binding var vehicle: VehicleData
    @State private var picking = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(name).bold().frame(width: 70, alignment: .leading)
                Button { picking = true } label: {
                    EventImagePreview(doc: doc, image: EventImage(characterName: vehicle.characterName, characterIndex: vehicle.characterIndex)).frame(width: 44, height: 44)
                }.buttonStyle(.plain)
                Picker("Start", selection: $vehicle.startMapId) { Text("None").tag(0); ForEach(doc.project.orderedMapInfos) { Text($0.name).tag($0.id) } }.frame(width: 190)
                TextField("X", value: $vehicle.startX, format: .number).frame(width: 40)
                TextField("Y", value: $vehicle.startY, format: .number).frame(width: 40)
            }
            AudioField(doc: doc, title: "BGM", folder: "bgm", file: $vehicle.bgm)
        }
        .sheet(isPresented: $picking) {
            ImagePicker(doc: doc, image: Binding(get: { EventImage(characterName: vehicle.characterName, characterIndex: vehicle.characterIndex) },
                                                 set: { vehicle.characterName = $0.characterName; vehicle.characterIndex = $0.characterIndex }))
        }
    }
}
