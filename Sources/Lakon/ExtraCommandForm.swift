import LakonCore
import SwiftUI

/// Forms for the battle/audio/picture/screen/vehicle/script commands, in MZ's parameter encoding.
struct ExtraCommandForm: View {
    @ObservedObject var doc: EditorDocument
    let kind: CommandKind
    let existing: [EventCommand]?
    let done: ([EventCommand]) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var id = 1
    @State private var id2 = 1
    @State private var actor = 0            // 0 = entire party
    @State private var op = 0
    @State private var operandType = 0
    @State private var value = 1
    @State private var flag = false
    @State private var flag2 = false
    @State private var text = ""
    @State private var text2 = ""
    @State private var audio = AudioFile("", volume: 90)
    @State private var x = 0
    @State private var y = 0
    @State private var center = true
    @State private var scale = 100
    @State private var opacity = 255
    @State private var blend = 0
    @State private var duration = 60
    @State private var wait = true
    @State private var easing = 0
    @State private var tone = [0, 0, 0, 0]
    @State private var weatherType = "rain"
    @State private var goods: [(Int, Int)] = [(0, 1)]
    @State private var character = 0
    @State private var access = 0

    var p: Project { doc.project }
    var variables: [(Int, String)] { (1..<max(2, p.system.variables.count)).map { ($0, p.system.variables[safe: $0] ?? "") } }
    var actors: [(Int, String)] { doc.names(p.actors, \.name, \.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.rawValue).font(.title2.bold())
            Form { fields }
            HStack {
                Spacer()
                Button("Cancel") { doc.stopAudio(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { doc.stopAudio(); done(build()); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18).frame(width: 560)
        .onAppear(perform: load)
    }

    func actorPicker() -> some View {
        Picker("Actor", selection: $actor) { Text("Entire Party").tag(0); ForEach(actors, id: \.0) { Text($0.1).tag($0.0) } }
    }
    func operand(_ label: String = "Value") -> some View {
        Group {
            Picker("Operation", selection: $op) { Text("Increase").tag(0); Text("Decrease").tag(1) }.pickerStyle(.segmented)
            Picker("Operand", selection: $operandType) { Text("Constant").tag(0); Text("Variable").tag(1) }.pickerStyle(.segmented)
            if operandType == 0 { TextField(label, value: $value, format: .number) }
            else { Picker("Variable", selection: $value) { ForEach(variables, id: \.0) { Text(String(format: "%04d %@", $0.0, $0.1)).tag($0.0) } } }
        }
    }
    func characterPicker() -> some View {
        Picker("Character", selection: $character) {
            Text("Player").tag(-1); Text("This Event").tag(0)
            ForEach(doc.map.liveEvents) { e in Text("\(e.id): \(e.name)").tag(e.id) }
        }
    }
    func durationWait() -> some View {
        HStack { TextField("Duration (frames)", value: $duration, format: .number); Toggle("Wait for Completion", isOn: $wait) }
    }

    @ViewBuilder var fields: some View {
        switch kind {
        case .numberInput:
            Picker("Variable", selection: $id) { ForEach(variables, id: \.0) { Text(String(format: "%04d %@", $0.0, $0.1)).tag($0.0) } }
            Stepper("Digits: \(value)", value: $value, in: 1...8)
        case .selectItem:
            Picker("Variable", selection: $id) { ForEach(variables, id: \.0) { Text(String(format: "%04d %@", $0.0, $0.1)).tag($0.0) } }
            Picker("Item Type", selection: $value) { Text("Regular Item").tag(1); Text("Key Item").tag(2); Text("Hidden Item A").tag(3); Text("Hidden Item B").tag(4) }
        case .balloon:
            characterPicker()
            Picker("Balloon", selection: $value) {
                ForEach(Array(["Exclamation", "Question", "Music Note", "Heart", "Anger", "Sweat", "Frustration", "Silence", "Light Bulb", "Zzz"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset + 1) }
            }
            Toggle("Wait for Completion", isOn: $wait)
        case .changeHP, .changeMP:
            actorPicker(); operand()
            if kind == .changeHP { Toggle("Allow Knockout", isOn: $flag) }
        case .changeState:
            actorPicker()
            Picker("Operation", selection: $op) { Text("Add").tag(0); Text("Remove").tag(1) }.pickerStyle(.segmented)
            IdPicker(title: "State", id: $id, options: doc.stateOptions)
        case .recoverAll: actorPicker()
        case .changeEXP, .changeLevel:
            actorPicker(); operand()
            Toggle("Show Level Up", isOn: $flag)
        case .changeSkill:
            actorPicker()
            Picker("Operation", selection: $op) { Text("Learn").tag(0); Text("Forget").tag(1) }.pickerStyle(.segmented)
            IdPicker(title: "Skill", id: $id, options: doc.skillOptions)
        case .changeEquip:
            IdPicker(title: "Actor", id: $actor, options: actors)
            Picker("Slot", selection: $id2) { ForEach(1..<6, id: \.self) { Text(p.system.equipTypes[safe: $0] ?? "Slot").tag($0) } }
            Picker("Item", selection: $id) {
                Text("None").tag(0)
                ForEach(id2 == 1 ? doc.weaponOptions : p.armors.compactMap { $0 }.filter { $0.etypeId == id2 }.map { ($0.id, $0.name) }, id: \.0) { Text($0.1).tag($0.0) }
            }
        case .changeName:
            IdPicker(title: "Actor", id: $actor, options: actors)
            TextField("Name", text: $text)
        case .battle:
            Picker("Troop", selection: $operandType) { Text("Direct").tag(0); Text("Variable").tag(1); Text("Same as Random Encounters").tag(2) }
            if operandType == 0 { Picker("Troop", selection: $id) { ForEach(p.troops.compactMap { $0 }) { Text($0.name).tag($0.id) } } }
            if operandType == 1 { Picker("Variable", selection: $id) { ForEach(variables, id: \.0) { Text($0.1).tag($0.0) } } }
            Toggle("Can Escape", isOn: $flag)
            Toggle("Continue When Loss", isOn: $flag2)
            Text("Escape/Loss branches are added when enabled.").font(.caption).foregroundStyle(.secondary)
        case .shop:
            ForEach(goods.indices, id: \.self) { i in
                HStack {
                    Picker("", selection: Binding(get: { goods[i].0 }, set: { goods[i].0 = $0; goods[i].1 = 1 })) { Text("Item").tag(0); Text("Weapon").tag(1); Text("Armor").tag(2) }.labelsHidden().frame(width: 100)
                    Picker("", selection: Binding(get: { goods[i].1 }, set: { goods[i].1 = $0 })) {
                        ForEach([doc.itemOptions, doc.weaponOptions, doc.armorOptions][goods[i].0], id: \.0) { Text($0.1).tag($0.0) }
                    }.labelsHidden()
                    Text("\(ShopState.basePrice(kind: goods[i].0, id: goods[i].1, p)) \(p.system.currencyUnit)").frame(width: 70)
                    Button { goods.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Merchandise") { goods.append((0, 1)) }
            Toggle("Purchase Only", isOn: $flag)
        case .nameInput:
            IdPicker(title: "Actor", id: $actor, options: actors)
            Stepper("Max Characters: \(value)", value: $value, in: 1...16)
        case .openMenu, .openSave, .saveBgm, .resumeBgm, .stopSe, .getOnOff:
            Text("No parameters.").foregroundStyle(.secondary)
        case .access:
            Picker("Setting", selection: $access) { Text("Save Access").tag(134); Text("Menu Access").tag(135); Text("Encounter").tag(136) }
            Picker("", selection: $op) { Text("Enable").tag(0); Text("Disable").tag(1) }.pickerStyle(.segmented)
        case .playBgm, .battleBgm: AudioField(doc: doc, title: "BGM", folder: "bgm", file: $audio)
        case .playBgs: AudioField(doc: doc, title: "BGS", folder: "bgs", file: $audio)
        case .playMe: AudioField(doc: doc, title: "ME", folder: "me", file: $audio)
        case .playSe: AudioField(doc: doc, title: "SE", folder: "se", file: $audio)
        case .fadeBgm, .fadeBgs: Stepper("Duration: \(value) sec", value: $value, in: 0...60)
        case .showPicture, .movePicture:
            Stepper("Picture #\(id)", value: $id, in: 1...100)
            if kind == .showPicture {
                Picker("Image", selection: $text) { Text("(None)").tag(""); ForEach(p.assetNames("img/pictures"), id: \.self) { Text($0).tag($0) } }
            }
            Picker("Origin", selection: $center) { Text("Upper Left").tag(false); Text("Center").tag(true) }.pickerStyle(.segmented)
            HStack { TextField("X", value: $x, format: .number); TextField("Y", value: $y, format: .number) }
            HStack { TextField("Scale %", value: $scale, format: .number); TextField("Opacity", value: $opacity, format: .number) }
            Picker("Blend", selection: $blend) { Text("Normal").tag(0); Text("Additive").tag(1); Text("Multiply").tag(2); Text("Screen").tag(3) }
            if kind == .movePicture {
                durationWait()
                Picker("Easing", selection: $easing) { Text("Constant").tag(0); Text("Slow Start").tag(1); Text("Slow End").tag(2); Text("Slow Start and End").tag(3) }
            }
            Text("Screen is 816 × 624.").font(.caption).foregroundStyle(.secondary)
        case .rotatePicture:
            Stepper("Picture #\(id)", value: $id, in: 1...100)
            Stepper("Speed: \(value)", value: $value, in: -90...90)
        case .erasePicture: Stepper("Picture #\(id)", value: $id, in: 1...100)
        case .tint, .flash:
            ForEach(0..<4, id: \.self) { i in
                let names = kind == .tint ? ["Red", "Green", "Blue", "Gray"] : ["Red", "Green", "Blue", "Intensity"]
                HStack { Text(names[i]).frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { Double(tone[i]) }, set: { tone[i] = Int($0) }), in: kind == .tint && i < 3 ? -255...255 : 0...255)
                    Text("\(tone[i])").monospacedDigit().frame(width: 40) }
            }
            if kind == .tint {
                HStack {
                    Button("Normal") { tone = [0, 0, 0, 0] }; Button("Dark") { tone = [-68, -68, -68, 0] }
                    Button("Sepia") { tone = [34, -34, -68, 170] }; Button("Sunset") { tone = [68, -34, -34, 0] }; Button("Night") { tone = [-68, -68, 0, 68] }
                }
            }
            durationWait()
        case .shake:
            Stepper("Power: \(value)", value: $value, in: 1...9)
            Stepper("Speed: \(id)", value: $id, in: 1...9)
            durationWait()
        case .weather:
            Picker("Type", selection: $weatherType) { Text("None").tag("none"); Text("Rain").tag("rain"); Text("Storm").tag("storm"); Text("Snow").tag("snow") }.pickerStyle(.segmented)
            Stepper("Power: \(value)", value: $value, in: 1...9)
            durationWait()
        case .vehicleLocation:
            Picker("Vehicle", selection: $id2) { Text("Boat").tag(0); Text("Ship").tag(1); Text("Airship").tag(2) }.pickerStyle(.segmented)
            Picker("Map", selection: $id) { ForEach(p.orderedMapInfos) { Text($0.name).tag($0.id) } }
            HStack { TextField("X", value: $x, format: .number); TextField("Y", value: $y, format: .number) }
        case .script:
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 180)
            Text("JavaScript with $gameVariables, $gameSwitches, $gameParty, $gameActors, $gamePlayer, $gameMap, $gameMessage, $gameScreen, AudioManager.")
                .font(.caption).foregroundStyle(.secondary)
        case .plugin:
            TextField("Plugin", text: $text)
            TextField("Command", text: $text2)
            TextEditor(text: $weatherType).font(.system(.body, design: .monospaced)).frame(height: 80)
            Text("Arguments: one key=value per line. Plugins live in the project's plugins/ folder.").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    func actorParams() -> [JSONValue] { [0, .int(actor)] }
    func audioJSON() -> JSONValue { audio.json }

    func build() -> [EventCommand] {
        func c(_ code: Int, _ params: [JSONValue]) -> EventCommand { EventCommand(code: code, indent: 0, parameters: params) }
        switch kind {
        case .numberInput: return [c(103, [.int(id), .int(value)])]
        case .selectItem: return [c(104, [.int(id), .int(value)])]
        case .balloon: return [Cmd.balloon(character: character, value, wait: wait)]
        case .changeHP: return [c(311, actorParams() + [.int(op), .int(operandType), .int(value), .bool(flag)])]
        case .changeMP: return [c(312, actorParams() + [.int(op), .int(operandType), .int(value)])]
        case .changeState: return [c(313, actorParams() + [.int(op), .int(id)])]
        case .recoverAll: return [c(314, actorParams())]
        case .changeEXP: return [c(315, actorParams() + [.int(op), .int(operandType), .int(value), .bool(flag)])]
        case .changeLevel: return [c(316, actorParams() + [.int(op), .int(operandType), .int(value), .bool(flag)])]
        case .changeSkill: return [c(318, actorParams() + [.int(op), .int(id)])]
        case .changeEquip: return [c(319, [.int(actor), .int(id2), .int(id)])]
        case .changeName: return [c(320, [.int(actor), .string(text)])]
        case .battle:
            var out = Cmd.battle(troop: id, canEscape: flag, canLose: flag2)
            out[0].parameters[0] = .int(operandType)
            return out
        case .shop: return Cmd.shop(goods, purchaseOnly: flag)
        case .nameInput: return [Cmd.nameInput(actor: actor, maxLength: value)]
        case .openMenu: return [c(351, [])]
        case .openSave: return [c(352, [])]
        case .access: return [c(access, [.int(op)])]
        case .playBgm: return [c(241, [audioJSON()])]
        case .battleBgm: return [c(132, [audioJSON()])]
        case .playBgs: return [c(245, [audioJSON()])]
        case .playMe: return [c(249, [audioJSON()])]
        case .playSe: return [c(250, [audioJSON()])]
        case .fadeBgm: return [c(242, [.int(value)])]
        case .fadeBgs: return [c(246, [.int(value)])]
        case .saveBgm: return [c(243, [])]
        case .resumeBgm: return [c(244, [])]
        case .stopSe: return [c(251, [])]
        case .showPicture:
            return [c(231, [.int(id), .string(text), .int(center ? 1 : 0), 0, .int(x), .int(y), .int(scale), .int(scale), .int(opacity), .int(blend)])]
        case .movePicture:
            return [c(232, [.int(id), 0, .int(center ? 1 : 0), 0, .int(x), .int(y), .int(scale), .int(scale), .int(opacity), .int(blend), .int(duration), .bool(wait), .int(easing)])]
        case .rotatePicture: return [c(233, [.int(id), .int(value)])]
        case .erasePicture: return [Cmd.erasePicture(id)]
        case .tint: return [Cmd.tint(tone, duration: duration, wait: wait)]
        case .flash: return [Cmd.flash(tone, duration: duration, wait: wait)]
        case .shake: return [Cmd.shake(power: value, speed: id, duration: duration, wait: wait)]
        case .weather: return [Cmd.weather(weatherType, power: value, duration: duration, wait: wait)]
        case .vehicleLocation: return [c(202, [.int(id2), 0, .int(id), .int(x), .int(y)])]
        case .getOnOff: return [c(206, [])]
        case .script: return Cmd.script(text)
        case .plugin:
            var args: [String: String] = [:]
            for line in weatherType.split(separator: "\n") {
                let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { args[kv[0]] = kv[1] }
            }
            return [Cmd.pluginCommand(text, text2, args: args)]
        default: return []
        }
    }

    func load() {
        if kind == .plugin { weatherType = "" }
        if [.changeEquip, .changeName, .nameInput].contains(kind) { actor = actors.first?.0 ?? 1 }
        if kind == .nameInput { value = 8 }
        if kind == .changeEquip { id2 = 1; id = 0 }
        if kind == .access { access = 134 }
        if kind == .battle { id = p.troops.compactMap { $0 }.first?.id ?? 1; flag = true }
        if kind == .tint || kind == .flash { tone = kind == .tint ? [0, 0, 0, 0] : [255, 255, 255, 170]; duration = kind == .tint ? 60 : 8; wait = false }
        if kind == .shake { value = 5; id = 5; duration = 30 }
        if kind == .weather { value = 5 }
        if kind == .showPicture { x = 408; y = 312 }
        if kind == .balloon { value = 1; character = 0 }
        if kind == .vehicleLocation { id = doc.mapId }
        guard let e = existing, let h = e.first else { return }
        let q = h.parameters
        switch h.code {
        case 103, 104: id = q[p: 0].int; value = q[p: 1].int
        case 213: character = q[p: 0].int; value = q[p: 1].int; wait = q[p: 2].bool
        case 311, 312, 315, 316: actor = q[p: 1].int; op = q[p: 2].int; operandType = q[p: 3].int; value = q[p: 4].int; flag = q[p: 5].bool
        case 313, 318: actor = q[p: 1].int; op = q[p: 2].int; id = q[p: 3].int
        case 314: actor = q[p: 1].int
        case 319: actor = q[p: 0].int; id2 = q[p: 1].int; id = q[p: 2].int
        case 320: actor = q[p: 0].int; text = q[p: 1].string
        case 302: goods = e.map { ($0.parameters[p: 0].int, $0.parameters[p: 1].int) }; flag = q[p: 4].bool
        case 303: actor = q[p: 0].int; value = q[p: 1].int
        case 241, 245, 249, 250, 132: audio = AudioFile(q[p: 0]) ?? AudioFile()
        case 242, 246: value = q[p: 0].int
        case 231, 232:
            id = q[p: 0].int; text = q[p: 1].string; center = q[p: 2].int == 1; x = q[p: 4].int; y = q[p: 5].int
            scale = q[p: 6].int; opacity = q[p: 8].int; blend = q[p: 9].int
            if h.code == 232 { duration = q[p: 10].int; wait = q[p: 11].bool; easing = q[p: 12].int }
        case 233: id = q[p: 0].int; value = q[p: 1].int
        case 235: id = q[p: 0].int
        case 223, 224: tone = q[p: 0].array.map(\.int) + Array(repeating: 0, count: max(0, 4 - q[p: 0].array.count)); duration = q[p: 1].int; wait = q[p: 2].bool
        case 225: value = q[p: 0].int; id = q[p: 1].int; duration = q[p: 2].int; wait = q[p: 3].bool
        case 236: weatherType = q[p: 0].string; value = q[p: 1].int; duration = q[p: 2].int; wait = q[p: 3].bool
        case 202: id2 = q[p: 0].int; id = q[p: 2].int; x = q[p: 3].int; y = q[p: 4].int
        case 355: text = e.map { $0.parameters[p: 0].string }.joined(separator: "\n")
        case 357:
            text = q[p: 0].string; text2 = q[p: 1].string
            if case .object(let o) = q[p: 3] { weatherType = o.map { "\($0.key)=\($0.value.string)" }.sorted().joined(separator: "\n") }
        default: break
        }
    }
}
