import Foundation

/// Headless scripted run used to check that the web runtime (web/sim.js) behaves exactly like LakonCore.
/// Both sides apply the same driver rules and print the same per-frame snapshot line.
///
/// Script: `{"seed": 1, "steps": [{"frames": 30, "dir": 6, "ok": false}, …]}`. Driver rules each frame:
/// name input → "Hero"; shops and menu/save requests are closed; in battle input, Fight then attack the first
/// living enemy; OK is pressed on even frames while a finished message is showing.
public enum Simulation {
    public struct Step: Decodable {
        public var frames = 1, dir = 0, ok = false, cancel = false, dash = false
        enum CodingKeys: String, CodingKey { case frames, dir, ok, cancel, dash }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            frames = c.v(.frames, 1); dir = c.v(.dir, 0); ok = c.v(.ok, false); cancel = c.v(.cancel, false); dash = c.v(.dash, false)
        }
    }
    public struct Script: Decodable {
        public var seed: UInt64 = 1, steps: [Step] = []
        enum CodingKeys: String, CodingKey { case seed, steps }
        public init(from d: Decoder) throws { let c = try d.container(keyedBy: CodingKeys.self); seed = c.v(.seed, 1); steps = c.v(.steps, []) }
    }

    public static func run(project: Project, script: Script) -> [String] {
        let w = GameWorld(project: project, rng: SeededRandom(script.seed))
        w.newGame()
        var out: [String] = [], frame = 0
        for step in script.steps {
            for _ in 0..<max(0, step.frames) {
                drive(w)
                var i = InputState(dir4: step.dir, ok: step.ok, cancel: step.cancel, dash: step.dash)
                if let m = w.message, m.isTextComplete, frame % 2 == 0 { i.ok = true }
                w.update(i)
                frame += 1
                out.append(snapshot(w, frame))
            }
        }
        return out
    }

    static func drive(_ w: GameWorld) {
        if let n = w.nameInput { w.actor(n.actorId)?.setName("Hero"); w.nameInput = nil }
        if w.shop != nil { w.shop = nil }
        if w.requestMenu || w.requestSave { w.requestMenu = false; w.requestSave = false }
        if let b = w.battle, b.phase == .input, !b.isBusy {
            if b.waitingForPartyCommand { b.commandFight() }
            else if b.inputActor != nil { b.commandAttack(target: b.enemies.firstIndex { $0.isAlive } ?? 0) }
        }
    }

    /// Fixed-point text via schoolbook rounding (printf rounds ties to even; this matches web/sim.js exactly).
    static func fx(_ x: Double, _ digits: Int) -> String {
        let scale = pow(10, Double(digits)), n = Int((x * scale).rounded())
        let sign = n < 0 ? "-" : "", a = abs(n), ip = a / Int(scale), fp = a % Int(scale)
        return sign + String(ip) + "." + String(repeating: "0", count: digits - String(fp).count) + String(fp)
    }

    public static func snapshot(_ w: GameWorld, _ frame: Int) -> String {
        let s = w.state
        let sw = s.switches.filter(\.value).keys.sorted().map(String.init).joined(separator: ",")
        let vars = s.variables.keys.sorted().map { "\($0):\(s.variables[$0]!)" }.joined(separator: ",")
        let items = s.items.keys.sorted().map { "\($0):\(s.items[$0]!)" }.joined(separator: ",")
        let selfs = s.selfSwitches.sorted().joined(separator: ";")
        let party = w.allMembers.map { "\($0.actorId):\($0.hp)/\($0.mp)/\($0.tp)/L\($0.level)/E\($0.currentExp)/\($0.states.map(String.init).joined(separator: "."))" }.joined(separator: ",")
        let evs = w.events.map { "\($0.eventId)@\($0.x),\($0.y),\($0.direction),\($0.pageIndex)" }.joined(separator: " ")
        var line = "f=\(frame) m=\(s.mapId) p=\(w.player.x),\(w.player.y),\(w.player.direction) r=\(fx(w.player.realX, 4)),\(fx(w.player.realY, 4))"
        line += " g=\(s.gold) sw=[\(sw)] v=[\(vars)] it=[\(items)] ss=[\(selfs)] party=[\(party)] ev=[\(evs)]"
        line += " msg=\(w.message.map { $0.text.replacingOccurrences(of: "\n", with: "/") + "#\($0.visibleChars)" } ?? "-")"
        if let b = w.battle {
            line += " battle=\(b.phase) t\(b.turnCount) log=\(b.log.joined(separator: "|")) en=[\(b.enemies.map { "\($0.hp)" }.joined(separator: ","))]"
        }
        let pics = s.screen.pictures.keys.sorted().map { k -> String in let p = s.screen.pictures[k]!; return "\(k):\(p.name)@\(fx(p.x, 2)),\(fx(p.y, 2)),\(fx(p.opacity, 1))" }.joined(separator: ",")
        line += " pic=[\(pics)] par=\(s.parallax.name):\(fx(s.parallax.autoX, 4)) bright=\(fx(w.brightness, 2))"
        return line
    }
}
