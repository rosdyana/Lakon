import Foundation

/// Builders and display text for event commands, in MZ's encoding (codes/params as in rmmz_objects.js).
public enum Cmd {
    public static func text(_ lines: [String], face: String = "", faceIndex: Int = 0, speaker: String = "", indent: Int = 0) -> [EventCommand] {
        [EventCommand(code: 101, indent: indent, parameters: [.string(face), .int(faceIndex), 0, 2, .string(speaker)])]
            + lines.map { EventCommand(code: 401, indent: indent, parameters: [.string($0)]) }
    }
    /// Choices with one body per choice; `cancel` -1 disallow, else index (or choices.count for "Branch").
    public static func choices(_ options: [(String, [EventCommand])], cancel: Int = -1, indent: Int = 0) -> [EventCommand] {
        var out = [EventCommand(code: 102, indent: indent, parameters: [.array(options.map { .string($0.0) }), .int(cancel), 0, 2, 0])]
        for (i, (name, body)) in options.enumerated() {
            out.append(EventCommand(code: 402, indent: indent, parameters: [.int(i), .string(name)]))
            out += reindent(body, to: indent + 1)
            out.append(.end(indent + 1))
        }
        out.append(EventCommand(code: 404, indent: indent))
        return out
    }
    public static func branch(_ condition: [JSONValue], then: [EventCommand], else elseBody: [EventCommand]? = nil, indent: Int = 0) -> [EventCommand] {
        var out = [EventCommand(code: 111, indent: indent, parameters: condition)]
        out += reindent(then, to: indent + 1); out.append(.end(indent + 1))
        if let e = elseBody {
            out.append(EventCommand(code: 411, indent: indent))
            out += reindent(e, to: indent + 1); out.append(.end(indent + 1))
        }
        out.append(EventCommand(code: 412, indent: indent))
        return out
    }
    public static func ifSwitch(_ id: Int, on: Bool = true) -> [JSONValue] { [0, .int(id), .int(on ? 0 : 1)] }
    public static func ifSelfSwitch(_ ch: String, on: Bool = true) -> [JSONValue] { [2, .string(ch), .int(on ? 0 : 1)] }
    public static func ifVariable(_ id: Int, _ op: Int, _ value: Int) -> [JSONValue] { [1, .int(id), 0, .int(value), .int(op)] }
    public static func ifGold(_ amount: Int, _ op: Int = 0) -> [JSONValue] { [7, .int(amount), .int(op)] }
    public static func ifItem(_ id: Int) -> [JSONValue] { [8, .int(id)] }

    public static func switches(_ id: Int, _ on: Bool, indent: Int = 0) -> EventCommand { EventCommand(code: 121, indent: indent, parameters: [.int(id), .int(id), .int(on ? 0 : 1)]) }
    public static func variable(_ id: Int, op: Int = 0, constant: Int, indent: Int = 0) -> EventCommand {
        EventCommand(code: 122, indent: indent, parameters: [.int(id), .int(id), .int(op), 0, .int(constant)])
    }
    public static func selfSwitch(_ ch: String, _ on: Bool, indent: Int = 0) -> EventCommand { EventCommand(code: 123, indent: indent, parameters: [.string(ch), .int(on ? 0 : 1)]) }
    public static func gold(_ n: Int, indent: Int = 0) -> EventCommand { EventCommand(code: 125, indent: indent, parameters: [.int(n < 0 ? 1 : 0), 0, .int(abs(n))]) }
    public static func item(_ id: Int, _ n: Int, indent: Int = 0) -> EventCommand { EventCommand(code: 126, indent: indent, parameters: [.int(id), .int(n < 0 ? 1 : 0), 0, .int(abs(n))]) }
    public static func transfer(map: Int, x: Int, y: Int, direction: Int = 0, indent: Int = 0) -> EventCommand {
        EventCommand(code: 201, indent: indent, parameters: [0, .int(map), .int(x), .int(y), .int(direction), 0])
    }
    public static func wait(_ frames: Int, indent: Int = 0) -> EventCommand { EventCommand(code: 230, indent: indent, parameters: [.int(frames)]) }
    public static func commonEvent(_ id: Int, indent: Int = 0) -> EventCommand { EventCommand(code: 117, indent: indent, parameters: [.int(id)]) }
    public static func comment(_ text: String, indent: Int = 0) -> EventCommand { EventCommand(code: 108, indent: indent, parameters: [.string(text)]) }
    public static func eraseEvent(indent: Int = 0) -> EventCommand { EventCommand(code: 214, indent: indent) }
    public static func fadeOut(indent: Int = 0) -> EventCommand { EventCommand(code: 221, indent: indent) }
    public static func fadeIn(indent: Int = 0) -> EventCommand { EventCommand(code: 222, indent: indent) }
    public static func moveRoute(character: Int, _ codes: [(Int, [JSONValue])], wait: Bool = true, indent: Int = 0) -> EventCommand {
        let list: [JSONValue] = codes.map { .object(["code": .int($0.0), "indent": .null, "parameters": .array($0.1)]) } + [.object(["code": 0, "parameters": []])]
        return EventCommand(code: 205, indent: indent, parameters: [.int(character), .object(["list": .array(list), "repeat": false, "skippable": false, "wait": .bool(wait)])])
    }
    public static func gameOver(indent: Int = 0) -> EventCommand { EventCommand(code: 353, indent: indent) }

    public static func playBgm(_ name: String, volume: Int = 90) -> EventCommand { EventCommand(code: 241, indent: 0, parameters: [AudioFile(name, volume: volume).json]) }
    public static func playBgs(_ name: String, volume: Int = 90) -> EventCommand { EventCommand(code: 245, indent: 0, parameters: [AudioFile(name, volume: volume).json]) }
    public static func fadeOutBgs(_ s: Int) -> EventCommand { EventCommand(code: 246, indent: 0, parameters: [.int(s)]) }
    public static func playMe(_ name: String) -> EventCommand { EventCommand(code: 249, indent: 0, parameters: [AudioFile(name).json]) }
    public static func playSe(_ name: String, volume: Int = 90, pitch: Int = 100) -> EventCommand { EventCommand(code: 250, indent: 0, parameters: [AudioFile(name, volume: volume, pitch: pitch).json]) }
    public static func showPicture(_ id: Int, _ name: String, center: Bool = true, x: Int, y: Int, scale: Int = 100, opacity: Int = 255) -> EventCommand {
        EventCommand(code: 231, indent: 0, parameters: [.int(id), .string(name), .int(center ? 1 : 0), 0, .int(x), .int(y), .int(scale), .int(scale), .int(opacity), 0])
    }
    public static func movePicture(_ id: Int, center: Bool = true, x: Int, y: Int, scale: Int = 100, opacity: Int = 255, duration: Int, wait: Bool = true, easing: Int = 0) -> EventCommand {
        EventCommand(code: 232, indent: 0, parameters: [.int(id), 0, .int(center ? 1 : 0), 0, .int(x), .int(y), .int(scale), .int(scale), .int(opacity), 0, .int(duration), .bool(wait), .int(easing)])
    }
    public static func erasePicture(_ id: Int) -> EventCommand { EventCommand(code: 235, indent: 0, parameters: [.int(id)]) }
    public static func tint(_ tone: [Int], duration: Int, wait: Bool = true) -> EventCommand {
        EventCommand(code: 223, indent: 0, parameters: [.array(tone.map { .int($0) }), .int(duration), .bool(wait)])
    }
    public static func flash(_ color: [Int], duration: Int, wait: Bool = false) -> EventCommand {
        EventCommand(code: 224, indent: 0, parameters: [.array(color.map { .int($0) }), .int(duration), .bool(wait)])
    }
    public static func shake(power: Int, speed: Int, duration: Int, wait: Bool = true) -> EventCommand {
        EventCommand(code: 225, indent: 0, parameters: [.int(power), .int(speed), .int(duration), .bool(wait)])
    }
    public static func weather(_ type: String, power: Int, duration: Int, wait: Bool = false) -> EventCommand {
        EventCommand(code: 236, indent: 0, parameters: [.string(type), .int(power), .int(duration), .bool(wait)])
    }
    public static func showAnimation(character: Int, _ id: Int, wait: Bool = true) -> EventCommand {
        EventCommand(code: 212, indent: 0, parameters: [.int(character), .int(id), .bool(wait)])
    }
    public static func changeParallax(_ name: String, loopX: Bool = false, loopY: Bool = false, sx: Int = 0, sy: Int = 0) -> EventCommand {
        EventCommand(code: 284, indent: 0, parameters: [.string(name), .bool(loopX), .bool(loopY), .int(sx), .int(sy)])
    }
    public static func balloon(character: Int, _ id: Int, wait: Bool = true) -> EventCommand {
        EventCommand(code: 213, indent: 0, parameters: [.int(character), .int(id), .bool(wait)])
    }
    public static func addPartyMember(_ id: Int) -> EventCommand { EventCommand(code: 129, indent: 0, parameters: [.int(id), 0, .bool(false)]) }
    public static func recoverAll() -> EventCommand { EventCommand(code: 314, indent: 0, parameters: [0, 0]) }
    public static func nameInput(actor: Int, maxLength: Int = 8) -> EventCommand { EventCommand(code: 303, indent: 0, parameters: [.int(actor), .int(maxLength)]) }
    public static func numberInput(variable: Int, digits: Int) -> EventCommand { EventCommand(code: 103, indent: 0, parameters: [.int(variable), .int(digits)]) }
    public static func randomVariable(_ id: Int, _ lo: Int, _ hi: Int) -> EventCommand {
        EventCommand(code: 122, indent: 0, parameters: [.int(id), .int(id), 0, 2, .int(lo), .int(hi)])
    }
    public static func script(_ code: String) -> [EventCommand] {
        let lines = code.components(separatedBy: "\n")
        return [EventCommand(code: 355, indent: 0, parameters: [.string(lines[0])])] + lines.dropFirst().map { EventCommand(code: 655, indent: 0, parameters: [.string($0)]) }
    }
    public static func pluginCommand(_ plugin: String, _ command: String, args: [String: String] = [:]) -> EventCommand {
        EventCommand(code: 357, indent: 0, parameters: [.string(plugin), .string(command), .string(command), .object(args.mapValues { .string($0) })])
    }
    /// Battle Processing with Win/Escape/Lose branches (601/602/603).
    public static func battle(troop: Int, canEscape: Bool, canLose: Bool, win: [EventCommand] = [], escape: [EventCommand]? = nil, lose: [EventCommand]? = nil) -> [EventCommand] {
        var out = [EventCommand(code: 301, indent: 0, parameters: [0, .int(troop), .bool(canEscape), .bool(canLose)])]
        guard canEscape || canLose else { return out }
        out.append(EventCommand(code: 601, indent: 0)); out += reindent(win, to: 1); out.append(.end(1))
        if canEscape { out.append(EventCommand(code: 602, indent: 0)); out += reindent(escape ?? [], to: 1); out.append(.end(1)) }
        if canLose { out.append(EventCommand(code: 603, indent: 0)); out += reindent(lose ?? [], to: 1); out.append(.end(1)) }
        out.append(EventCommand(code: 604, indent: 0))
        return out
    }
    /// Shop Processing: goods are (kind 0 item / 1 weapon / 2 armor, id).
    public static func shop(_ goods: [(Int, Int)], purchaseOnly: Bool = false) -> [EventCommand] {
        guard let first = goods.first else { return [] }
        return [EventCommand(code: 302, indent: 0, parameters: [.int(first.0), .int(first.1), 0, 0, .bool(purchaseOnly)])]
            + goods.dropFirst().map { EventCommand(code: 605, indent: 0, parameters: [.int($0.0), .int($0.1), 0, 0]) }
    }

    static func reindent(_ cmds: [EventCommand], to base: Int) -> [EventCommand] {
        let minIndent = cmds.map(\.indent).min() ?? 0
        return cmds.map { var c = $0; c.indent = c.indent - minIndent + base; return c }
    }

    // MARK: list structure helpers for the editor

    /// Codes that are continuation lines or block terminators — not selectable as standalone commands.
    public static let continuation: Set<Int> = [401, 402, 403, 404, 405, 408, 411, 412, 413, 601, 602, 603, 604, 605, 655]

    /// Range of a command including its continuation lines and nested block (what MZ deletes/copies as a unit).
    public static func blockRange(_ list: [EventCommand], at i: Int) -> Range<Int> {
        guard i < list.count else { return i..<i }
        let c = list[i]
        var end = i + 1
        switch c.code {
        case 101: while end < list.count, list[end].code == 401 { end += 1 }
        case 105: while end < list.count, list[end].code == 405 { end += 1 }
        case 108: while end < list.count, list[end].code == 408 { end += 1 }
        case 302: while end < list.count, list[end].code == 605 { end += 1 }
        case 355: while end < list.count, list[end].code == 655 { end += 1 }
        case 301:
            if end < list.count, [601, 602, 603].contains(list[end].code) {
                while end < list.count, !(list[end].indent == c.indent && list[end].code == 604) { end += 1 }
                end = min(list.count, end + 1)
            }
        case 102, 111, 112:
            let terminator = c.code == 102 ? 404 : c.code == 111 ? 412 : 413
            while end < list.count, !(list[end].indent == c.indent && list[end].code == terminator) { end += 1 }
            end = min(list.count, end + 1)
        default: break
        }
        return i..<end
    }

    static let dirNames = [0: "Retain", 2: "Down", 4: "Left", 6: "Right", 8: "Up"]

    /// One-line description like MZ's event list ("◆Text : None, Window, Bottom").
    public static func describe(_ c: EventCommand, project: Project?) -> String {
        let p = c.parameters
        func sw(_ id: Int) -> String {
            let n = project.flatMap { id < $0.system.switches.count ? $0.system.switches[id] : nil } ?? ""
            return String(format: "#%04d %@", id, n)
        }
        func va(_ id: Int) -> String {
            let n = project.flatMap { id < $0.system.variables.count ? $0.system.variables[id] : nil } ?? ""
            return String(format: "#%04d %@", id, n)
        }
        func itemName(_ id: Int) -> String { project.flatMap { id < $0.items.count ? $0.items[id]?.name : nil } ?? "Item \(id)" }
        switch c.code {
        case 0: return "◆"
        case 101: return "◆Text : \(p[p: 0].string.isEmpty ? "None" : p[p: 0].string)" + (p[p: 4].string.isEmpty ? "" : ", \(p[p: 4].string)")
        case 401: return "  :      : \(p[p: 0].string)"
        case 102: return "◆Show Choices : " + p[p: 0].array.map(\.string).joined(separator: ", ")
        case 402: return ": When \(p[p: 1].string)"
        case 403: return ": When Cancel"
        case 404: return ": End"
        case 108: return "◆Comment : \(p[p: 0].string)"
        case 408: return "  :          : \(p[p: 0].string)"
        case 111:
            switch p[p: 0].int {
            case 0: return "◆If : \(sw(p[p: 1].int)) is \(p[p: 2].int == 0 ? "ON" : "OFF")"
            case 1:
                let ops = ["=", "≥", "≤", ">", "<", "≠"]
                let rhs = p[p: 2].int == 0 ? p[p: 3].string : va(p[p: 3].int)
                return "◆If : \(va(p[p: 1].int)) \(ops[min(5, p[p: 4].int)]) \(rhs)"
            case 2: return "◆If : Self Switch \(p[p: 1].string) is \(p[p: 2].int == 0 ? "ON" : "OFF")"
            case 4: return "◆If : Actor \(p[p: 1].int) is in the party"
            case 6: return "◆If : Character \(p[p: 1].int) is facing \(dirNames[p[p: 2].int] ?? "?")"
            case 7: return "◆If : Gold \(["≥", "≤", "<"][min(2, p[p: 2].int)]) \(p[p: 1].int)"
            case 8: return "◆If : Party has \(itemName(p[p: 1].int))"
            default: return "◆If : (condition type \(p[p: 0].int))"
            }
        case 411: return ": Else"
        case 412: return ": End"
        case 112: return "◆Loop"
        case 413: return ": Repeat Above"
        case 113: return "◆Break Loop"
        case 115: return "◆Exit Event Processing"
        case 117:
            let id = p[p: 0].int
            let n = project.flatMap { id < $0.commonEvents.count ? $0.commonEvents[id]?.name : nil } ?? ""
            return "◆Common Event : \(n.isEmpty ? "#\(id)" : n)"
        case 121:
            let r = p[p: 0].int == p[p: 1].int ? sw(p[p: 0].int) : "#\(p[p: 0].int)..\(p[p: 1].int)"
            return "◆Control Switches : \(r) = \(p[p: 2].int == 0 ? "ON" : "OFF")"
        case 122:
            let ops = ["=", "+=", "-=", "*=", "/=", "%="]
            let rhs: String
            switch p[p: 3].int {
            case 0: rhs = p[p: 4].string
            case 1: rhs = va(p[p: 4].int)
            case 2: rhs = "Random \(p[p: 4].int)..\(p[p: 5].int)"
            default: rhs = "(game data)"
            }
            return "◆Control Variables : \(va(p[p: 0].int)) \(ops[min(5, p[p: 2].int)]) \(rhs)"
        case 123: return "◆Control Self Switch : \(p[p: 0].string) = \(p[p: 1].int == 0 ? "ON" : "OFF")"
        case 125: return "◆Change Gold : \(p[p: 0].int == 0 ? "+" : "-") \(p[p: 1].int == 0 ? p[p: 2].string : va(p[p: 2].int))"
        case 126: return "◆Change Items : \(itemName(p[p: 0].int)) \(p[p: 1].int == 0 ? "+" : "-") \(p[p: 2].int == 0 ? p[p: 3].string : va(p[p: 3].int))"
        case 129: return "◆Change Party Member : \(p[p: 1].int == 0 ? "Add" : "Remove") Actor \(p[p: 0].int)"
        case 201:
            let name = project?.mapName(p[p: 1].int) ?? "Map \(p[p: 1].int)"
            return p[p: 0].int == 0
                ? "◆Transfer Player : \(name) (\(p[p: 2].int),\(p[p: 3].int)) \(dirNames[p[p: 4].int] ?? "")"
                : "◆Transfer Player : {variables}"
        case 203: return "◆Set Event Location : \(p[p: 0].int == 0 ? "This Event" : "Event \(p[p: 0].int)") (\(p[p: 2].int),\(p[p: 3].int))"
        case 205:
            let who = p[p: 0].int < 0 ? "Player" : p[p: 0].int == 0 ? "This Event" : "Event \(p[p: 0].int)"
            if case .object(let r) = p[p: 1] {
                let n = max(0, (r["list"]?.array.count ?? 1) - 1)
                return "◆Set Movement Route : \(who) (\(n) steps\(r["wait"]?.bool == true ? ", Wait" : ""))"
            }
            return "◆Set Movement Route : \(who)"
        case 211: return "◆Change Transparency : \(p[p: 0].int == 0 ? "ON" : "OFF")"
        case 214: return "◆Erase Event"
        case 221: return "◆Fadeout Screen"
        case 222: return "◆Fadein Screen"
        case 230: return "◆Wait : \(p[p: 0].int) frames"
        case 353: return "◆Game Over"
        case 354: return "◆Return to Title Screen"
        case 103: return "◆Input Number : \(va(p[p: 0].int)), \(p[p: 1].int) digits"
        case 104: return "◆Select Item : \(va(p[p: 0].int))"
        case 105: return "◆Text (Scroll) : Speed \(p[p: 0].int)"
        case 405: return "  :              : \(p[p: 0].string)"
        case 132: return "◆Change Battle BGM : \(AudioFile(p[p: 0])?.name ?? "")"
        case 133: return "◆Change Victory ME : \(AudioFile(p[p: 0])?.name ?? "")"
        case 134: return "◆Change Save Access : \(p[p: 0].int == 0 ? "Enable" : "Disable")"
        case 135: return "◆Change Menu Access : \(p[p: 0].int == 0 ? "Enable" : "Disable")"
        case 136: return "◆Change Encounter : \(p[p: 0].int == 0 ? "Enable" : "Disable")"
        case 202: return "◆Set Vehicle Location : \(["Boat", "Ship", "Airship"][min(2, max(0, p[p: 0].int))]), \(project?.mapName(p[p: 2].int) ?? "") (\(p[p: 3].int),\(p[p: 4].int))"
        case 206: return "◆Get on/off Vehicle"
        case 212:
            let an = project.flatMap { $0.animation(p[p: 1].int)?.name } ?? "#\(p[p: 1].int)"
            return "◆Show Animation : \(p[p: 0].int < 0 ? "Player" : p[p: 0].int == 0 ? "This Event" : "Event \(p[p: 0].int)"), \(an)" + (p[p: 2].bool ? " (Wait)" : "")
        case 213:
            let names = ["", "Exclamation", "Question", "Music Note", "Heart", "Anger", "Sweat", "Frustration", "Silence", "Light Bulb", "Zzz"]
            return "◆Show Balloon Icon : \(p[p: 0].int < 0 ? "Player" : p[p: 0].int == 0 ? "This Event" : "Event \(p[p: 0].int)"), \(names[safe: p[p: 1].int] ?? "?")"
        case 216: return "◆Change Player Followers : \(p[p: 0].int == 0 ? "ON" : "OFF")"
        case 223: return "◆Tint Screen : (\(p[p: 0].array.map(\.string).joined(separator: ","))), \(p[p: 1].int) frames"
        case 224: return "◆Flash Screen : (\(p[p: 0].array.map(\.string).joined(separator: ","))), \(p[p: 1].int) frames"
        case 225: return "◆Shake Screen : \(p[p: 0].int), \(p[p: 1].int), \(p[p: 2].int) frames"
        case 231: return "◆Show Picture : #\(p[p: 0].int), \(p[p: 1].string), (\(p[p: 4].int),\(p[p: 5].int))"
        case 232: return "◆Move Picture : #\(p[p: 0].int), (\(p[p: 4].int),\(p[p: 5].int)), \(p[p: 10].int) frames"
        case 233: return "◆Rotate Picture : #\(p[p: 0].int), \(p[p: 1].int)"
        case 234: return "◆Tint Picture : #\(p[p: 0].int), \(p[p: 2].int) frames"
        case 235: return "◆Erase Picture : #\(p[p: 0].int)"
        case 236: return "◆Set Weather Effect : \(p[p: 0].string.capitalized), \(p[p: 1].int), \(p[p: 2].int) frames"
        case 241: return "◆Play BGM : \(AudioFile(p[p: 0])?.name ?? "None")"
        case 242: return "◆Fadeout BGM : \(p[p: 0].int) sec"
        case 243: return "◆Save BGM"
        case 244: return "◆Resume BGM"
        case 245: return "◆Play BGS : \(AudioFile(p[p: 0])?.name ?? "None")"
        case 246: return "◆Fadeout BGS : \(p[p: 0].int) sec"
        case 249: return "◆Play ME : \(AudioFile(p[p: 0])?.name ?? "None")"
        case 250: return "◆Play SE : \(AudioFile(p[p: 0])?.name ?? "None")"
        case 251: return "◆Stop SE"
        case 282: return "◆Change Tileset : #\(p[p: 0].int)"
        case 283: return "◆Change Battle Background : \(p[p: 0].string) & \(p[p: 1].string)"
        case 284: return "◆Change Parallax : \(p[p: 0].string.isEmpty ? "None" : p[p: 0].string)" + (p[p: 1].bool || p[p: 2].bool ? " (loop \(p[p: 3].int), \(p[p: 4].int))" : "")
        case 285: return "◆Get Location Info : \(va(p[p: 0].int))"
        case 301:
            let tn = project.flatMap { p[p: 1].int < $0.troops.count ? $0.troops[p[p: 1].int]?.name : nil } ?? "#\(p[p: 1].int)"
            return "◆Battle Processing : \(p[p: 0].int == 0 ? tn : p[p: 0].int == 1 ? "{variable}" : "Same as Random Encounters")"
        case 601: return ": If Win"
        case 602: return ": If Escape"
        case 603: return ": If Lose"
        case 604: return ": End"
        case 302, 605:
            let kind = p[p: 0].int, id = p[p: 1].int
            let n = project.map { ShopState.name(kind: kind, id: id, $0) } ?? "#\(id)"
            return c.code == 302 ? "◆Shop Processing : \(n)" : "  :                       : \(n)"
        case 303: return "◆Name Input Processing : Actor \(p[p: 0].int), \(p[p: 1].int) characters"
        case 311, 312, 326, 315, 316:
            let what = [311: "HP", 312: "MP", 326: "TP", 315: "EXP", 316: "Level"][c.code]!
            let who = p[p: 0].int == 0 ? (p[p: 1].int == 0 ? "Entire Party" : "Actor \(p[p: 1].int)") : "{variable}"
            return "◆Change \(what) : \(who), \(p[p: 2].int == 0 ? "+" : "-") \(p[p: 3].int == 0 ? p[p: 4].string : va(p[p: 4].int))"
        case 313:
            let who = p[p: 1].int == 0 ? "Entire Party" : "Actor \(p[p: 1].int)"
            let st = project.flatMap { p[p: 3].int < $0.states.count ? $0.states[p[p: 3].int]?.name : nil } ?? "#\(p[p: 3].int)"
            return "◆Change State : \(who), \(p[p: 2].int == 0 ? "+" : "-") \(st)"
        case 314: return "◆Recover All : \(p[p: 1].int == 0 ? "Entire Party" : "Actor \(p[p: 1].int)")"
        case 317: return "◆Change Parameter : Actor \(p[p: 1].int), param \(p[p: 2].int)"
        case 318:
            let sk = project.flatMap { p[p: 3].int < $0.skills.count ? $0.skills[p[p: 3].int]?.name : nil } ?? "#\(p[p: 3].int)"
            return "◆Change Skill : Actor \(p[p: 1].int), \(p[p: 2].int == 0 ? "+" : "-") \(sk)"
        case 319: return "◆Change Equipment : Actor \(p[p: 0].int), slot \(p[p: 1].int) = #\(p[p: 2].int)"
        case 320: return "◆Change Name : Actor \(p[p: 0].int), \(p[p: 1].string)"
        case 321: return "◆Change Class : Actor \(p[p: 0].int), class \(p[p: 1].int)"
        case 324: return "◆Change Nickname : Actor \(p[p: 0].int), \(p[p: 1].string)"
        case 331: return "◆Change Enemy HP : #\(p[p: 0].int + 1)"
        case 333: return "◆Change Enemy State : #\(p[p: 0].int + 1)"
        case 334: return "◆Enemy Recover All : #\(p[p: 0].int + 1)"
        case 335: return "◆Enemy Appear : #\(p[p: 0].int + 1)"
        case 336: return "◆Enemy Transform : #\(p[p: 0].int + 1) → \(p[p: 1].int)"
        case 337:
            let an = project.flatMap { $0.animation(p[p: 1].int)?.name } ?? "#\(p[p: 1].int)"
            return "◆Show Battle Animation : \(p[p: 2].bool ? "Entire Troop" : "#\(p[p: 0].int + 1)"), \(an)"
        case 339: return "◆Force Action"
        case 340: return "◆Abort Battle"
        case 351: return "◆Open Menu Screen"
        case 352: return "◆Open Save Screen"
        case 355: return "◆Script : \(p[p: 0].string)"
        case 655: return "  :          : \(p[p: 0].string)"
        case 356: return "◆Plugin Command (MV) : \(p[p: 0].string)"
        case 357: return "◆Plugin Command : \(p[p: 0].string), \(p[p: 1].string)"
        default: return "◆(MZ command \(c.code) — not executed by Lakon)"
        }
    }
}
