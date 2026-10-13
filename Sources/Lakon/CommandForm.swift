import LakonCore
import SwiftUI

enum CommandKind: String, Identifiable, CaseIterable {
    case text = "Show Text", choices = "Show Choices", comment = "Comment"
    case branch = "Conditional Branch", loop = "Loop", breakLoop = "Break Loop", exit = "Exit Event Processing", common = "Common Event"
    case switches = "Control Switches", variables = "Control Variables", selfSwitch = "Control Self Switch"
    case gold = "Change Gold", items = "Change Items", party = "Change Party Member"
    case transfer = "Transfer Player", route = "Set Movement Route", transparency = "Change Transparency", erase = "Erase Event"
    case fadeOut = "Fadeout Screen", fadeIn = "Fadein Screen", wait = "Wait"
    case gameOver = "Game Over", title = "Return to Title Screen"
    // Extra commands (ExtraCommandForm)
    case numberInput = "Input Number", selectItem = "Select Item", balloon = "Show Balloon Icon"
    case changeHP = "Change HP", changeMP = "Change MP", changeState = "Change State", recoverAll = "Recover All"
    case changeEXP = "Change EXP", changeLevel = "Change Level", changeSkill = "Change Skill", changeEquip = "Change Equipment", changeName = "Change Name"
    case battle = "Battle Processing", shop = "Shop Processing", nameInput = "Name Input Processing", openMenu = "Open Menu Screen", openSave = "Open Save Screen"
    case access = "Change Save/Menu/Encounter Access"
    case playBgm = "Play BGM", fadeBgm = "Fadeout BGM", saveBgm = "Save BGM", resumeBgm = "Resume BGM", playBgs = "Play BGS", fadeBgs = "Fadeout BGS"
    case playMe = "Play ME", playSe = "Play SE", stopSe = "Stop SE", battleBgm = "Change Battle BGM"
    case showPicture = "Show Picture", movePicture = "Move Picture", rotatePicture = "Rotate Picture", erasePicture = "Erase Picture"
    case tint = "Tint Screen", flash = "Flash Screen", shake = "Shake Screen", weather = "Set Weather Effect"
    case vehicleLocation = "Set Vehicle Location", getOnOff = "Get on/off Vehicle"
    case script = "Script", plugin = "Plugin Command"
    var id: String { rawValue }
    var isExtra: Bool { CommandKind.allCases.firstIndex(of: self)! >= CommandKind.allCases.firstIndex(of: .numberInput)! }

    static let groups: [(String, [CommandKind])] = [
        ("Message", [.text, .choices, .numberInput, .selectItem, .comment]),
        ("Flow Control", [.branch, .loop, .breakLoop, .exit, .common]),
        ("Game Progression", [.switches, .variables, .selfSwitch]),
        ("Party", [.gold, .items, .party]),
        ("Actor", [.changeHP, .changeMP, .changeState, .recoverAll, .changeEXP, .changeLevel, .changeSkill, .changeEquip, .changeName]),
        ("Movement", [.transfer, .vehicleLocation, .route, .getOnOff]),
        ("Character", [.transparency, .balloon, .erase]),
        ("Picture", [.showPicture, .movePicture, .rotatePicture, .erasePicture]),
        ("Screen & Timing", [.fadeOut, .fadeIn, .tint, .flash, .shake, .weather, .wait]),
        ("Audio", [.playBgm, .fadeBgm, .saveBgm, .resumeBgm, .playBgs, .fadeBgs, .playMe, .playSe, .stopSe]),
        ("Scene Control", [.battle, .shop, .nameInput, .openMenu, .openSave, .gameOver, .title]),
        ("System", [.battleBgm, .access]),
        ("Advanced", [.script, .plugin]),
    ]

    static func editable(_ code: Int) -> CommandKind? {
        [101: .text, 108: .comment, 111: .branch, 117: .common, 121: .switches, 122: .variables, 123: .selfSwitch,
         125: .gold, 126: .items, 129: .party, 201: .transfer, 205: .route, 211: .transparency, 230: .wait,
         103: .numberInput, 104: .selectItem, 213: .balloon, 311: .changeHP, 312: .changeMP, 313: .changeState, 314: .recoverAll,
         315: .changeEXP, 316: .changeLevel, 318: .changeSkill, 319: .changeEquip, 320: .changeName, 302: .shop, 303: .nameInput,
         241: .playBgm, 242: .fadeBgm, 245: .playBgs, 246: .fadeBgs, 249: .playMe, 250: .playSe, 132: .battleBgm,
         231: .showPicture, 232: .movePicture, 233: .rotatePicture, 235: .erasePicture, 223: .tint, 224: .flash, 225: .shake,
         236: .weather, 202: .vehicleLocation, 355: .script, 357: .plugin][code]
    }
}

/// Form for one command; emits commands at indent 0 (the list editor shifts them).
struct CommandForm: View {
    @ObservedObject var doc: EditorDocument
    let kind: CommandKind
    let existing: [EventCommand]?
    let done: ([EventCommand]) -> Void
    @Environment(\.dismiss) var dismiss

    // Message
    @State private var text = ""
    @State private var speaker = ""
    @State private var face = ""
    @State private var background = 0
    @State private var position = 2
    @State private var choices = ["Yes", "No", "", "", "", ""]
    @State private var cancelType = 1
    // Branch
    @State private var condType = 0
    @State private var condId = 1
    @State private var condOn = true
    @State private var condOp = 0
    @State private var condValue = 0
    @State private var condCh = "A"
    @State private var withElse = true
    // Values
    @State private var idA = 1
    @State private var idB = 1
    @State private var on = true
    @State private var op = 0
    @State private var operandType = 0
    @State private var valueA = 1
    @State private var valueB = 100
    @State private var ch = "A"
    // Transfer
    @State private var mapId = 1
    @State private var x = 0
    @State private var y = 0
    @State private var direction = 0
    // Route
    @State private var target = -1
    @State private var steps: [Int] = []
    @State private var routeWait = true
    @State private var routeRepeat = false
    @State private var routeSkip = false

    static let routeCodes: [(Int, String)] = [
        (1, "Move Down"), (2, "Move Left"), (3, "Move Right"), (4, "Move Up"), (9, "Move at Random"), (10, "Move toward Player"),
        (11, "Move away from Player"), (12, "1 Step Forward"), (13, "1 Step Backward"), (15, "Wait 15 frames"),
        (16, "Turn Down"), (17, "Turn Left"), (18, "Turn Right"), (19, "Turn Up"), (22, "Turn 180°"), (24, "Turn at Random"),
        (25, "Turn toward Player"), (29, "Speed 3"), (37, "Through ON"), (38, "Through OFF"), (35, "Direction Fix ON"),
        (36, "Direction Fix OFF"), (39, "Transparent ON"), (40, "Transparent OFF"), (33, "Stepping ON"), (34, "Stepping OFF"),
    ]

    var p: Project { doc.project }
    var switchOptions: [(Int, String)] { (1..<max(2, p.system.switches.count)).map { ($0, String(format: "%04d %@", $0, p.system.switches[safe: $0] ?? "")) } }
    var variableOptions: [(Int, String)] { (1..<max(2, p.system.variables.count)).map { ($0, String(format: "%04d %@", $0, p.system.variables[safe: $0] ?? "")) } }
    var itemOptions: [(Int, String)] { p.items.compactMap { $0 }.map { ($0.id, $0.name) } }
    var actorOptions: [(Int, String)] { p.actors.compactMap { $0 }.map { ($0.id, $0.name) } }
    var commonOptions: [(Int, String)] { p.commonEvents.compactMap { $0 }.map { ($0.id, $0.name) } }
    var mapOptions: [(Int, String)] { p.orderedMapInfos.map { ($0.id, $0.name) } }

    var body: some View {
        if kind.isExtra { ExtraCommandForm(doc: doc, kind: kind, existing: existing, done: done) } else { basicBody }
    }

    var basicBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.rawValue).font(.title2.bold())
            Form { fields }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { done(build()); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .onAppear(perform: load)
    }

    func picker(_ title: String, _ v: Binding<Int>, _ opts: [(Int, String)]) -> some View {
        Picker(title, selection: v) { ForEach(opts, id: \.0) { Text($0.1).tag($0.0) } }
    }

    @ViewBuilder var fields: some View {
        switch kind {
        case .text:
            TextField("Face (img/faces)", text: $face)
            TextField("Name", text: $speaker)
            Picker("Background", selection: $background) { Text("Window").tag(0); Text("Dim").tag(1); Text("Transparent").tag(2) }
            Picker("Position", selection: $position) { Text("Top").tag(0); Text("Middle").tag(1); Text("Bottom").tag(2) }
            TextField("Text", text: $text, axis: .vertical).lineLimit(4...8).font(.system(.body, design: .monospaced))
            Text("Codes: \\V[n] variable, \\N[n] actor name, \\P[n] party member, \\G currency").font(.caption).foregroundStyle(.secondary)
        case .choices:
            ForEach(0..<6, id: \.self) { i in TextField("Choice #\(i + 1)", text: $choices[i]) }
            Picker("Cancel", selection: $cancelType) {
                Text("Disallow").tag(-1)
                ForEach(0..<6, id: \.self) { i in Text("Choice #\(i + 1)").tag(i) }
                Text("Branch").tag(6)
            }
        case .comment:
            TextField("Comment", text: $text, axis: .vertical).lineLimit(3...6)
        case .branch:
            Picker("Condition", selection: $condType) {
                Text("Switch").tag(0); Text("Variable").tag(1); Text("Self Switch").tag(2); Text("Actor in party").tag(4)
                Text("Gold").tag(7); Text("Item").tag(8)
            }
            switch condType {
            case 0: picker("Switch", $condId, switchOptions); Toggle("is ON", isOn: $condOn)
            case 1:
                picker("Variable", $condId, variableOptions)
                Picker("Operator", selection: $condOp) { ForEach(Array(["=", "≥", "≤", ">", "<", "≠"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }
                TextField("Constant", value: $condValue, format: .number)
            case 2: Picker("Self Switch", selection: $condCh) { ForEach(["A", "B", "C", "D"], id: \.self) { Text($0) } }; Toggle("is ON", isOn: $condOn)
            case 4: picker("Actor", $condId, actorOptions)
            case 7:
                Picker("Operator", selection: $condOp) { Text("≥").tag(0); Text("≤").tag(1); Text("<").tag(2) }
                TextField("Gold", value: $condValue, format: .number)
            default: picker("Item", $condId, itemOptions)
            }
            if existing == nil { Toggle("Create Else branch", isOn: $withElse) }
        case .loop, .breakLoop, .exit, .erase, .fadeIn, .fadeOut, .gameOver, .title:
            Text("No parameters.").foregroundStyle(.secondary)
        case .common:
            picker("Common Event", $idA, commonOptions)
        case .switches:
            picker("Switch", $idA, switchOptions)
            Toggle("ON", isOn: $on)
        case .variables:
            picker("Variable", $idA, variableOptions)
            Picker("Operation", selection: $op) { ForEach(Array(["Set", "Add", "Sub", "Mul", "Div", "Mod"].enumerated()), id: \.offset) { Text($0.element).tag($0.offset) } }
            Picker("Operand", selection: $operandType) { Text("Constant").tag(0); Text("Variable").tag(1); Text("Random").tag(2) }
            if operandType == 1 { picker("Source", $valueA, variableOptions) }
            else { TextField(operandType == 2 ? "Min" : "Value", value: $valueA, format: .number) }
            if operandType == 2 { TextField("Max", value: $valueB, format: .number) }
        case .selfSwitch:
            Picker("Self Switch", selection: $ch) { ForEach(["A", "B", "C", "D"], id: \.self) { Text($0) } }
            Toggle("ON", isOn: $on)
        case .gold:
            Picker("Operation", selection: $op) { Text("Increase").tag(0); Text("Decrease").tag(1) }
            TextField("Amount", value: $valueA, format: .number)
        case .items:
            picker("Item", $idA, itemOptions)
            Picker("Operation", selection: $op) { Text("Increase").tag(0); Text("Decrease").tag(1) }
            TextField("Amount", value: $valueA, format: .number)
        case .party:
            picker("Actor", $idA, actorOptions)
            Picker("Operation", selection: $op) { Text("Add").tag(0); Text("Remove").tag(1) }
        case .transfer:
            picker("Map", $mapId, mapOptions)
            HStack {
                TextField("X", value: $x, format: .number)
                TextField("Y", value: $y, format: .number)
            }
            Picker("Direction", selection: $direction) { Text("Retain").tag(0); Text("Down").tag(2); Text("Left").tag(4); Text("Right").tag(6); Text("Up").tag(8) }
            Text("Tip: hover the map to read coordinates in the status bar.").font(.caption).foregroundStyle(.secondary)
        case .route:
            Picker("Character", selection: $target) {
                Text("Player").tag(-1); Text("This Event").tag(0)
                ForEach(doc.map.liveEvents) { e in Text("\(e.id): \(e.name)").tag(e.id) }
            }
            HStack(alignment: .top) {
                List { ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack {
                        Text("◇" + (Self.routeCodes.first { $0.0 == s }?.1 ?? "\(s)"))
                        Spacer()
                        Button { steps.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                } }.frame(height: 180)
                Menu("Add Step") { ForEach(Self.routeCodes, id: \.0) { c in Button(c.1) { steps.append(c.0) } } }.frame(width: 120)
            }
            Toggle("Wait for Completion", isOn: $routeWait)
            Toggle("Repeat Movements", isOn: $routeRepeat)
            Toggle("Skip If Cannot Move", isOn: $routeSkip)
        case .transparency:
            Toggle("Transparent", isOn: $on)
        case .wait:
            TextField("Frames (1/60 sec)", value: $valueA, format: .number)
        default: EmptyView()
        }
    }

    func build() -> [EventCommand] {
        switch kind {
        case .text:
            let lines = text.components(separatedBy: "\n")
            return [EventCommand(code: 101, indent: 0, parameters: [.string(face), 0, .int(background), .int(position), .string(speaker)])]
                + lines.map { EventCommand(code: 401, indent: 0, parameters: [.string($0)]) }
        case .choices:
            let opts = choices.filter { !$0.isEmpty }
            let cancel = cancelType == 6 ? opts.count : min(cancelType, opts.count - 1)
            var out = Cmd.choices(opts.map { ($0, []) }, cancel: cancel)
            if cancelType == 6 {
                out.insert(contentsOf: [EventCommand(code: 403, indent: 0, parameters: [.int(6), .null]), .end(1)], at: out.count - 1)
            }
            return out
        case .comment:
            let lines = text.components(separatedBy: "\n")
            return [Cmd.comment(lines[0])] + lines.dropFirst().map { EventCommand(code: 408, indent: 0, parameters: [.string($0)]) }
        case .branch:
            let cond: [JSONValue]
            switch condType {
            case 0: cond = Cmd.ifSwitch(condId, on: condOn)
            case 1: cond = Cmd.ifVariable(condId, condOp, condValue)
            case 2: cond = Cmd.ifSelfSwitch(condCh, on: condOn)
            case 4: cond = [4, .int(condId), 0]
            case 7: cond = Cmd.ifGold(condValue, condOp)
            default: cond = Cmd.ifItem(condId)
            }
            return Cmd.branch(cond, then: [], else: withElse ? [] : nil)
        case .loop: return [EventCommand(code: 112, indent: 0), .end(1), EventCommand(code: 413, indent: 0)]
        case .breakLoop: return [EventCommand(code: 113, indent: 0)]
        case .exit: return [EventCommand(code: 115, indent: 0)]
        case .common: return [Cmd.commonEvent(idA)]
        case .switches: return [Cmd.switches(idA, on)]
        case .variables:
            return [EventCommand(code: 122, indent: 0, parameters: [.int(idA), .int(idA), .int(op), .int(operandType), .int(valueA), .int(valueB)])]
        case .selfSwitch: return [Cmd.selfSwitch(ch, on)]
        case .gold: return [Cmd.gold(op == 0 ? valueA : -valueA)]
        case .items: return [Cmd.item(idA, op == 0 ? valueA : -valueA)]
        case .party: return [EventCommand(code: 129, indent: 0, parameters: [.int(idA), .int(op), 0])]
        case .transfer: return [Cmd.transfer(map: mapId, x: x, y: y, direction: direction)]
        case .route:
            var cmd = Cmd.moveRoute(character: target, steps.map { ($0, $0 == 15 ? [15] : $0 == 29 ? [3] : []) }, wait: routeWait)
            if case .object(var r) = cmd.parameters[1] {
                r["repeat"] = .bool(routeRepeat); r["skippable"] = .bool(routeSkip)
                cmd.parameters[1] = .object(r)
            }
            return [cmd]
        case .transparency: return [EventCommand(code: 211, indent: 0, parameters: [.int(on ? 0 : 1)])]
        case .erase: return [Cmd.eraseEvent()]
        case .fadeOut: return [Cmd.fadeOut()]
        case .fadeIn: return [Cmd.fadeIn()]
        case .wait: return [Cmd.wait(max(1, valueA))]
        case .gameOver: return [Cmd.gameOver()]
        case .title: return [EventCommand(code: 354, indent: 0)]
        default: return []
        }
    }

    func load() {
        mapId = doc.mapId
        if kind == .wait { valueA = 60 }
        if kind == .switches || kind == .variables { idA = 1 }
        guard let e = existing, let h = e.first else { return }
        let q = h.parameters
        switch h.code {
        case 101:
            face = q[p: 0].string; background = q[p: 2].int; position = q[p: 3].int; speaker = q[p: 4].string
            text = e.dropFirst().filter { $0.code == 401 }.map { $0.parameters[p: 0].string }.joined(separator: "\n")
        case 108: text = ([h] + e.dropFirst().filter { $0.code == 408 }).map { $0.parameters[p: 0].string }.joined(separator: "\n")
        case 111:
            condType = q[p: 0].int
            switch condType {
            case 0: condId = q[p: 1].int; condOn = q[p: 2].int == 0
            case 1: condId = q[p: 1].int; condValue = q[p: 3].int; condOp = q[p: 4].int
            case 2: condCh = q[p: 1].string; condOn = q[p: 2].int == 0
            case 7: condValue = q[p: 1].int; condOp = q[p: 2].int
            default: condId = q[p: 1].int
            }
        case 117: idA = q[p: 0].int
        case 121: idA = q[p: 0].int; on = q[p: 2].int == 0
        case 122: idA = q[p: 0].int; op = q[p: 2].int; operandType = min(2, q[p: 3].int); valueA = q[p: 4].int; valueB = q[p: 5].int
        case 123: ch = q[p: 0].string; on = q[p: 1].int == 0
        case 125: op = q[p: 0].int; valueA = q[p: 2].int
        case 126: idA = q[p: 0].int; op = q[p: 1].int; valueA = q[p: 3].int
        case 129: idA = q[p: 0].int; op = q[p: 1].int
        case 201: mapId = q[p: 1].int; x = q[p: 2].int; y = q[p: 3].int; direction = q[p: 4].int
        case 205:
            target = q[p: 0].int
            if case .object(let r) = q[p: 1] {
                steps = (r["list"]?.array ?? []).compactMap { if case .object(let o) = $0 { return o["code"]?.int } else { return nil } }.filter { $0 != 0 }
                routeWait = r["wait"]?.bool ?? false; routeRepeat = r["repeat"]?.bool ?? false; routeSkip = r["skippable"]?.bool ?? false
            }
        case 211: on = q[p: 0].int == 0
        case 230: valueA = q[p: 0].int
        default: break
        }
    }
}
