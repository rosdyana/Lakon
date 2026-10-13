import CoreGraphics
import Foundation
import LakonCore

/// Side-view battle, animation, state-overlay and parallax art in MZ's sheet layouts, drawn procedurally
/// (MZ's RTP is licensed, so none of it ships):
/// - img/sv_actors/<name>.png: 576×384, 9×6 cells of 64×64. Motion m → column (m / 6) × 3 + pattern, row m % 6
///   (rmmz_sprites.js Sprite_Actor.updateFrame). Characters face left.
/// - img/system/Weapons1.png: 576×384, 96×64 cells. Image id i (1–12) → column ((i-1) / 6) × 3 + pattern, row (i-1) % 6
///   (Sprite_Weapon.updateFrame). Drawn to line up with the hand positions of the sv_actors poses.
/// - img/animations/<name>.png: 192×192 cells, 5 per row (Sprite_AnimationMV.updateCellSprite).
/// - img/system/States.png: 96×96 cells, 8 frames per row, row = overlay − 1 (Sprite_StateOverlay).
/// - img/system/Shadow2.png and img/parallaxes/*.png.
extension DefaultArt {

    // MARK: side-view actors

    /// A pose in 2-px grid units within a 32×32 grid (64×64 px cell); feet rest on y = 30.
    struct SVPose {
        var bx = 0.0, by = 0.0          // whole-body offset
        var crouch = 0.0                // lowers the hip, bends the knees forward
        var lean = 0.0                  // shoulders relative to hip (+ = back / right)
        var frontArm = 100.0            // degrees, y-down: 90 down, 180 forward (left), -90 up
        var backArm = 80.0
        var frontFoot = -1.5, backFoot = 1.5
        var kneel = false
        var lying = false
        var facingRight = false
        var eyes = 0                    // 0 open, 1 closed, 2 X
        var holdItem = false
        var gray = false
        var mark = ""                   // "z", "swirl", "sweat", "spark"
    }

    static let svMotionNames = ["walk", "wait", "chant", "guard", "damage", "evade", "thrust", "swing", "missile",
                                "skill", "spell", "item", "escape", "victory", "dying", "abnormal", "sleep", "dead"]

    static func svPose(_ motion: Int, _ p: Int) -> SVPose {
        var s = SVPose()
        switch motion {
        case 0, 12:                                               // walk / escape
            s.frontFoot = [-3.5, -1.5, 0.5][p]; s.backFoot = [3.5, 1.5, -0.5][p]
            s.frontArm = [70, 95, 120][p]; s.backArm = [120, 85, 60][p]; s.by = p == 1 ? 0 : -0.5
            s.facingRight = motion == 12
        case 1: s.by = p == 1 ? 0.5 : 0                           // wait (breathing)
        case 2: s.frontArm = 165; s.backArm = 150; s.by = p == 1 ? 0.5 : 0; s.mark = p == 1 ? "" : "spark"   // chant
        case 3: s.crouch = 1.5; s.lean = -0.5; s.frontArm = 182; s.backArm = 160                               // guard
        case 4: s.bx = [1, 2, 2][p]; s.lean = 1.5; s.frontArm = -40; s.backArm = -10; s.eyes = 1               // damage
        case 5: s.bx = [2.5, 4, 3][p]; s.crouch = [0.5, 1.5, 0.5][p]; s.lean = 1; s.frontArm = 50; s.backArm = 20   // evade
        case 6: s.bx = [1, -1, -2][p]; s.lean = [0.5, -1, -1][p]; s.frontArm = [70, 176, 178][p]; s.backArm = [100, 60, 60][p]; s.frontFoot = [-1.5, -3.5, -3.5][p]   // thrust
        case 7: s.lean = [0.8, 0, -1][p]; s.frontArm = [-60, -140, 150][p]; s.backArm = [110, 90, 60][p]; s.frontFoot = [-1.5, -2.5, -3.5][p]   // swing
        case 8: s.frontArm = 180; s.backArm = [170, 178, 185][p]; s.lean = [0, 0.3, 0.5][p]                    // missile
        case 9: s.lean = -0.5; s.frontArm = [-120, -150, -165][p]; s.backArm = 110                              // skill
        case 10: s.frontArm = [-115, -105, -100][p]; s.backArm = [-65, -75, -80][p]; s.by = p == 1 ? -0.5 : 0; s.mark = "spark"   // spell
        case 11: s.frontArm = [-110, -125, -120][p]; s.backArm = 100; s.holdItem = true                         // item
        case 13: s.frontArm = [-95, -88, -95][p]; s.backArm = 120; s.by = [0, -1, 0][p]                        // victory
        case 14: s.kneel = true; s.lean = -1.5; s.frontArm = 120; s.backArm = 100; s.by = p == 1 ? 0.3 : 0; s.mark = "sweat"   // dying
        case 15: s.kneel = true; s.lean = [-1, 0, -1][p]; s.frontArm = 110; s.backArm = 95; s.mark = "swirl"    // abnormal
        case 16: s.lying = true; s.eyes = 1; s.mark = "z"                                                         // sleep
        default: s.lying = true; s.eyes = 2; s.gray = true                                                        // dead
        }
        return s
    }

    static func svHip(_ s: SVPose) -> CGPoint { CGPoint(x: 16 + s.bx, y: (s.kneel ? 26.5 : 23 + s.crouch) + s.by) }
    static func svShoulder(_ s: SVPose) -> CGPoint { let h = svHip(s); return CGPoint(x: h.x + s.lean, y: h.y - 7) }
    static let armLength = 6.5
    /// Front hand in pixels within the 64×64 cell (used to place weapons).
    static func svHand(_ s: SVPose) -> CGPoint {
        let sh = svShoulder(s), a = s.frontArm * .pi / 180
        return CGPoint(x: (sh.x + cos(a) * armLength) * 2, y: (sh.y + 1 + sin(a) * armLength) * 2)
    }

    static func grayed(_ c: UInt32) -> UInt32 {
        let r = Double((c >> 16) & 0xff), g = Double((c >> 8) & 0xff), b = Double(c & 0xff)
        let l = (r * 0.3 + g * 0.59 + b * 0.11) * 0.8
        let mix = { (v: Double) in UInt32(max(0, min(255, v * 0.25 + l * 0.75))) }
        return mix(r) << 16 | mix(g) << 8 | mix(b)
    }

    static func drawSV(_ ctx: CGContext, _ ox: CGFloat, _ oy: CGFloat, _ lookIn: Look, motion: Int, pattern: Int) {
        let s = svPose(motion, pattern)
        var look = lookIn
        if s.gray { look.skin = grayed(look.skin); look.hair = grayed(look.hair); look.top = grayed(look.top); look.bottom = grayed(look.bottom); look.accent = grayed(look.accent) }
        let outline: UInt32 = 0x2a1f2e
        ctx.saveGState()
        if s.facingRight { ctx.translateBy(x: ox * 2 + 64, y: 0); ctx.scaleBy(x: -1, y: 1) }
        if s.lying {
            // Rotate the standing figure 90° so it lies with the head to the left.
            ctx.translateBy(x: ox + 58, y: oy + 52); ctx.rotate(by: -.pi / 2); ctx.translateBy(x: -(ox + 32), y: -(oy + 60))
        }
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + CGFloat(x * 2), y: oy + CGFloat(y * 2)) }
        func seg(_ a: CGPoint, _ b: CGPoint, _ col: UInt32, _ w: Double) {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(c(outline)); ctx.setLineWidth(CGFloat(w + 1.2) * 2)
            ctx.move(to: P(a.x, a.y)); ctx.addLine(to: P(b.x, b.y)); ctx.strokePath()
            ctx.setStrokeColor(c(col)); ctx.setLineWidth(CGFloat(w) * 2)
            ctx.move(to: P(a.x, a.y)); ctx.addLine(to: P(b.x, b.y)); ctx.strokePath()
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ col: UInt32) {
            ctx.setFillColor(c(col)); ctx.fill(CGRect(x: ox + CGFloat(x * 2), y: oy + CGFloat(y * 2), width: CGFloat(w * 2), height: CGFloat(h * 2)))
        }
        let hip = svHip(s), sh = svShoulder(s)
        let ground = 30 + s.by
        func leg(_ footDX: Double, kneeOnGround: Bool) {
            let foot = CGPoint(x: hip.x + footDX, y: ground)
            var knee = CGPoint(x: (hip.x + foot.x) / 2 - (s.crouch * 0.9), y: (hip.y + foot.y) / 2)
            if s.kneel { knee = kneeOnGround ? CGPoint(x: hip.x + 1, y: ground - 0.5) : CGPoint(x: hip.x - 3, y: hip.y - 0.5) }
            let f = s.kneel && kneeOnGround ? CGPoint(x: hip.x + 5, y: ground - 0.5) : (s.kneel ? CGPoint(x: hip.x - 3, y: ground) : foot)
            seg(hip, knee, look.bottom, 2.2); seg(knee, f, look.bottom, 2)
            rect(f.x - 1.6, f.y - 0.6, 2.6, 1.3, 0x3a2a22)
        }
        func arm(_ angle: Double, front: Bool) {
            let a = angle * .pi / 180
            let from = CGPoint(x: sh.x, y: sh.y + 1)
            let elbow = CGPoint(x: from.x + cos(a) * armLength * 0.55, y: from.y + sin(a) * armLength * 0.55)
            let hand = CGPoint(x: from.x + cos(a) * armLength, y: from.y + sin(a) * armLength)
            seg(from, elbow, look.top, 2); seg(elbow, hand, front ? look.top : look.top, 1.7)
            ctx.setFillColor(c(outline)); ctx.fillEllipse(in: CGRect(x: ox + CGFloat((hand.x - 1.3) * 2), y: oy + CGFloat((hand.y - 1.3) * 2), width: 5.2, height: 5.2))
            ctx.setFillColor(c(look.skin)); ctx.fillEllipse(in: CGRect(x: ox + CGFloat((hand.x - 0.9) * 2), y: oy + CGFloat((hand.y - 0.9) * 2), width: 3.6, height: 3.6))
            if front && s.holdItem {
                rect(hand.x - 1.2, hand.y - 4.2, 2.4, 3.2, outline); rect(hand.x - 0.8, hand.y - 3.8, 1.6, 2.4, 0x7fd0ff); rect(hand.x - 0.4, hand.y - 4.8, 0.8, 0.8, 0xe0b44c)
            }
        }
        // shadow
        if !s.lying { ctx.setFillColor(c(0x000000, 0.22)); ctx.fillEllipse(in: CGRect(x: ox + CGFloat(hip.x * 2) - 14, y: oy + CGFloat(ground * 2) - 3, width: 28, height: 6)) }
        arm(s.backArm, front: false)
        leg(s.backFoot, kneeOnGround: true)
        leg(s.frontFoot, kneeOnGround: false)
        // torso
        seg(hip, CGPoint(x: sh.x, y: sh.y + 1.5), look.top, 6)
        rect(min(hip.x, sh.x) - 3, hip.y - 1.5, 6.5, 1, look.accent)
        // head
        let hx = sh.x - 5 + s.lean * 0.2, hy = sh.y - 9.5
        rect(hx - 0.6, hy - 0.6, 11.2, 10.2, outline)
        rect(hx, hy, 10, 9, look.skin)
        rect(hx, hy - 0.4, 10, 3, look.hair)                     // fringe
        rect(hx + 6.5, hy, 3.5, 7, look.hair)                    // back of the head (facing left)
        if look.longHair { rect(hx + 7, hy + 6, 3.5, 6, look.hair) }
        if let hat = look.hat { rect(hx - 1, hy - 1.5, 12, 2, hat); rect(hx + 1, hy - 3, 8, 2, hat) }
        switch s.eyes {
        case 1: rect(hx + 1.5, hy + 5, 2, 0.6, outline)
        case 2: rect(hx + 1.2, hy + 4.2, 0.7, 0.7, outline); rect(hx + 2.6, hy + 4.2, 0.7, 0.7, outline); rect(hx + 1.9, hy + 4.9, 0.7, 0.7, outline)
                rect(hx + 1.2, hy + 5.6, 0.7, 0.7, outline); rect(hx + 2.6, hy + 5.6, 0.7, 0.7, outline)
        default: rect(hx + 1.6, hy + 4, 1, 2, outline)
        }
        rect(hx + 0.2, hy + 7, 1.2, 0.5, 0xd88a7a)              // mouth
        arm(s.frontArm, front: true)
        ctx.restoreGState()
        // Marks are drawn upright (not rotated with lying bodies).
        switch s.mark {
        case "z":
            let k = Double(pattern)
            NSAttributedStringShim.draw("z", in: ctx, at: CGPoint(x: ox + 12 + CGFloat(k * 4), y: oy + 18 - CGFloat(k * 5)), size: CGFloat(10 + k * 3), color: c(0x6fa8ff))
        case "swirl":
            for i in 0..<3 {
                let a = Double(pattern) * 2.1 + Double(i) * 2.09
                ctx.setFillColor(c(0xffe04a)); ctx.fillEllipse(in: CGRect(x: ox + 32 + CGFloat(cos(a) * 9) - 2, y: oy + 6 + CGFloat(sin(a) * 3) - 2, width: 4, height: 4))
            }
        case "sweat":
            ctx.setFillColor(c(0x8fd0ff, 0.9)); ctx.fillEllipse(in: CGRect(x: ox + 40, y: oy + 22 + CGFloat(pattern * 2), width: 4, height: 6))
        case "spark":
            let hand = svHand(s)
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + Double(pattern)
                ctx.setFillColor(c(0xbfe6ff, 0.9)); ctx.fill(CGRect(x: ox + hand.x + CGFloat(cos(a) * 6) - 1, y: oy + hand.y + CGFloat(sin(a) * 6) - 1, width: 3, height: 3))
            }
        default: break
        }
    }

    /// One img/sv_actors sheet for a look (MZ names them e.g. Actor1_1).
    static func makeSVActor(_ look: Look) -> CGImage {
        let ctx = makeCanvas(576, 384)
        for m in 0..<18 { for p in 0..<3 {
            let col = (m / 6) * 3 + p, row = m % 6
            drawSV(ctx, CGFloat(col * 64), CGFloat(row * 64), look, motion: m, pattern: p)
        } }
        return ctx.makeImage()!
    }

    static let actorLooks: [Look] = [
        Look(hair: 0x2a1f2e, top: 0x3f5fa8, bottom: 0x3a2f2a, accent: 0xe0b44c),
        Look(hair: 0xb5443a, top: 0x2f7d3b, bottom: 0x5a3b1c, accent: 0xf4f1e8, longHair: true),
        Look(hair: 0xe0b44c, top: 0x7a3a8a, bottom: 0x2b2b33, accent: 0xe0b44c),
        Look(skin: 0xc68b5e, hair: 0x101018, top: 0xa53a3a, bottom: 0x2b2b33, accent: 0xe0b44c, longHair: true),
        Look(hair: 0x6b4423, top: 0xb07a45, bottom: 0x3a2f2a),
        Look(hair: 0xf4f1e8, top: 0x5f6170, bottom: 0x2b2b33),
        Look(skin: 0xc68b5e, hair: 0x3a2410, top: 0x3f8f8a, bottom: 0x3a2f2a),
        Look(hair: 0x8f7ae8, top: 0xf4f1e8, bottom: 0x3f5fa8, longHair: true),
    ]

    // MARK: weapons (img/system/Weapons1.png)

    /// Weapon image ids: 1 dagger, 2 sword, 3 flail, 4 axe, 5 whip, 6 staff, 7 bow, 8 crossbow, 9 gun, 10 claw, 11 glove, 12 spear.
    /// Motion per id follows MZ's default System.attackMotions.
    public static func makeWeapons() -> CGImage {
        let ctx = makeCanvas(576, 384)
        let motionFor = [0: 6, 1: 6, 2: 7, 3: 7, 4: 7, 5: 7, 6: 7, 7: 8, 8: 8, 9: 8, 10: 6, 11: 6, 12: 6]
        for i in 1...12 { for p in 0..<3 {
            let col = ((i - 1) / 6) * 3 + p, row = (i - 1) % 6
            let pose = svPose(motionFor[i] ?? 7, p)
            // Weapon cell spans actorX − 64 … actorX + 32 (Sprite_Weapon x = −16, 96 wide); actor cell starts at actorX − 32.
            let hand = svHand(pose)
            let origin = CGPoint(x: CGFloat(col * 96) + hand.x + 32, y: CGFloat(row * 64) + hand.y)
            drawWeapon(ctx, i, at: origin, angle: pose.frontArm, pattern: p)
        } }
        return ctx.makeImage()!
    }

    static func drawWeapon(_ ctx: CGContext, _ kind: Int, at o: CGPoint, angle: Double, pattern: Int) {
        let a = angle * .pi / 180
        let d = CGPoint(x: cos(a), y: sin(a)), n = CGPoint(x: -sin(a), y: cos(a))
        func pt(_ along: Double, _ side: Double = 0) -> CGPoint { CGPoint(x: o.x + d.x * along + n.x * side, y: o.y + d.y * along + n.y * side) }
        func line(_ p1: CGPoint, _ p2: CGPoint, _ col: UInt32, _ w: CGFloat) {
            ctx.setLineCap(.round); ctx.setStrokeColor(c(0x1a1420)); ctx.setLineWidth(w + 2); ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
            ctx.setStrokeColor(c(col)); ctx.setLineWidth(w); ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
        }
        func poly(_ pts: [CGPoint], _ col: UInt32) {
            let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath()
            ctx.addPath(p); ctx.setFillColor(c(col)); ctx.fillPath()
            ctx.addPath(p); ctx.setStrokeColor(c(0x1a1420)); ctx.setLineWidth(1.5); ctx.strokePath()
        }
        let steel: UInt32 = 0xd8dde6, wood: UInt32 = 0x8a5a30, gold: UInt32 = 0xe0b44c
        switch kind {
        case 1:  // dagger
            line(pt(-3), pt(3), 0x4a2f17, 3); line(pt(2, -3), pt(2, 3), gold, 2)
            poly([pt(3, -2), pt(15, 0), pt(3, 2)], steel)
        case 2:  // sword
            line(pt(-4), pt(3), 0x4a2f17, 3); line(pt(3, -5), pt(3, 5), gold, 2.5)
            poly([pt(4, -2.2), pt(26, -1.2), pt(30, 0), pt(26, 1.2), pt(4, 2.2)], steel)
        case 3:  // flail
            line(pt(-3), pt(12), wood, 3)
            let ball = pt(20, pattern == 2 ? 4 : -3)
            line(pt(12), ball, 0x9aa0aa, 1.5)
            ctx.setFillColor(c(0x5f6170)); ctx.fillEllipse(in: CGRect(x: ball.x - 5, y: ball.y - 5, width: 10, height: 10))
        case 4:  // axe
            line(pt(-4), pt(20), wood, 3.5)
            poly([pt(14, -1), pt(12, -10), pt(22, -9), pt(20, -1)], steel)
        case 5:  // whip
            let p = CGMutablePath(); p.move(to: pt(-2)); p.addQuadCurve(to: pt(30, pattern == 2 ? 8 : -6), control: pt(14, pattern == 1 ? -10 : 8))
            ctx.addPath(p); ctx.setStrokeColor(c(0x5a3b1c)); ctx.setLineWidth(2.5); ctx.strokePath()
        case 6:  // staff
            line(pt(-8), pt(24), wood, 3)
            ctx.setFillColor(c(0x7fd0ff)); let tip = pt(27); ctx.fillEllipse(in: CGRect(x: tip.x - 4.5, y: tip.y - 4.5, width: 9, height: 9))
        case 7:  // bow (held vertically at the hand)
            let top = CGPoint(x: o.x - 2, y: o.y - 16), bot = CGPoint(x: o.x - 2, y: o.y + 16)
            let p = CGMutablePath(); p.move(to: top); p.addQuadCurve(to: bot, control: CGPoint(x: o.x - 14, y: o.y))
            ctx.addPath(p); ctx.setStrokeColor(c(wood)); ctx.setLineWidth(3); ctx.strokePath()
            let pull = CGFloat([4, 10, 1][pattern])
            ctx.setStrokeColor(c(0xf4f1e8)); ctx.setLineWidth(1); ctx.move(to: top); ctx.addLine(to: CGPoint(x: o.x + pull, y: o.y)); ctx.addLine(to: bot); ctx.strokePath()
            if pattern < 2 { line(CGPoint(x: o.x + pull, y: o.y), CGPoint(x: o.x - 20, y: o.y), 0xc08d55, 1.5) }
        case 8:  // crossbow
            line(pt(-6), pt(14), wood, 4); line(pt(10, -9), pt(10, 9), 0x5a3b1c, 2.5)
        case 9:  // gun
            poly([pt(-3, -2), pt(18, -2), pt(18, 1.5), pt(2, 1.5), pt(0, 6), pt(-4, 6)], 0x4a4f5a)
            if pattern == 1 { ctx.setFillColor(c(0xffd04a)); let m = pt(22); ctx.fillEllipse(in: CGRect(x: m.x - 4, y: m.y - 4, width: 8, height: 8)) }
        case 10: // claw
            for side in [-3.0, 0, 3] { poly([pt(2, side - 1), pt(13, side * 1.3), pt(2, side + 1)], steel) }
        case 11: // glove
            let f = pt(3); ctx.setFillColor(c(0xa53a3a)); ctx.fillEllipse(in: CGRect(x: f.x - 5, y: f.y - 5, width: 10, height: 10))
            ctx.setStrokeColor(c(0x1a1420)); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: CGRect(x: f.x - 5, y: f.y - 5, width: 10, height: 10))
        default: // spear
            line(pt(-14), pt(26), wood, 2.5)
            poly([pt(25, -3), pt(36, 0), pt(25, 3)], steel)
        }
    }

    // MARK: animation sheets (img/animations, MV cell format)

    /// Draws `count` frames of an effect into 192×192 cells, 5 per row.
    static func animationSheet(_ count: Int, _ draw: (CGContext, CGPoint, Int, Double) -> Void) -> CGImage {
        let rows = (count + 4) / 5
        let ctx = makeCanvas(960, rows * 192)
        for i in 0..<count {
            let o = CGPoint(x: (i % 5) * 192 + 96, y: (i / 5) * 192 + 96)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: o.x - 96, y: o.y - 96, width: 192, height: 192))
            draw(ctx, o, i, count > 1 ? Double(i) / Double(count - 1) : 0)
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }

    static func glow(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: UInt32, _ alpha: CGFloat) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let rr = CGFloat((col >> 16) & 0xff) / 255, gg = CGFloat((col >> 8) & 0xff) / 255, bb = CGFloat(col & 0xff) / 255
        guard r > 0, let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: rr, green: gg, blue: bb, alpha: alpha), CGColor(red: rr, green: gg, blue: bb, alpha: 0)] as CFArray, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    }

    static func star(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: UInt32, points: Int = 4, inner: CGFloat = 0.25, rot: Double = 0) {
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let a = rot + Double(i) * .pi / Double(points)
            let rad = i % 2 == 0 ? r : r * inner
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * rad, y: p.y + CGFloat(sin(a)) * rad)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath(); ctx.addPath(path); ctx.setFillColor(c(col)); ctx.fillPath()
    }

    static let animationSheetNames = ["Hit", "Slash", "Fire", "Ice", "Thunder", "Heal", "Poison", "Sleep", "Darkness", "Wind", "Sparkle"]

    public static func makeAnimationSheet(_ name: String) -> CGImage {
        switch name {
        case "Hit":
            return animationSheet(5) { ctx, o, i, t in
                glow(ctx, o, 30 + CGFloat(t) * 50, 0xfff2b0, 0.9 * (1 - CGFloat(t) * 0.8))
                star(ctx, o, 22 + CGFloat(t) * 46, 0xffffff, points: 6, inner: 0.22, rot: Double(i) * 0.3)
                ctx.setStrokeColor(c(0xffe080, 1 - t * 0.9)); ctx.setLineWidth(3)
                for k in 0..<8 {
                    let a = Double(k) * .pi / 4 + 0.2, r1 = 20 + t * 40, r2 = 34 + t * 60
                    ctx.move(to: CGPoint(x: o.x + CGFloat(cos(a) * r1), y: o.y + CGFloat(sin(a) * r1))); ctx.addLine(to: CGPoint(x: o.x + CGFloat(cos(a) * r2), y: o.y + CGFloat(sin(a) * r2)))
                }
                ctx.strokePath()
            }
        case "Slash":
            return animationSheet(5) { ctx, o, i, t in
                let sweep = 0.4 + t * 2.2
                for k in 0..<3 {
                    let w = CGFloat(12 - k * 4), alpha = CGFloat(1 - t * 0.7) * CGFloat(1 - Double(k) * 0.3)
                    ctx.setLineCap(.round); ctx.setStrokeColor(c(k == 0 ? 0xffffff : 0x9fd8ff, alpha)); ctx.setLineWidth(w)
                    ctx.addArc(center: CGPoint(x: o.x + 30, y: o.y + 30), radius: CGFloat(80 - k * 6), startAngle: CGFloat(-2.6), endAngle: CGFloat(-2.6 + sweep), clockwise: false)
                    ctx.strokePath()
                }
                glow(ctx, CGPoint(x: o.x - 10, y: o.y - 10), 50, 0xbfe6ff, 0.5 * (1 - CGFloat(t)))
            }
        case "Fire":
            return animationSheet(8) { ctx, o, i, t in
                glow(ctx, CGPoint(x: o.x, y: o.y + 20), 90, 0xff6a20, 0.7 * CGFloat(sin(t * .pi) + 0.2))
                for k in 0..<7 {
                    let ph = Double(k) * 1.7 + t * 6
                    let x = o.x + CGFloat(sin(ph) * 40), y = o.y + 50 - CGFloat((t * 90 + Double(k * 13)).truncatingRemainder(dividingBy: 110))
                    let s = CGFloat(18 + (k % 3) * 8) * CGFloat(1 - t * 0.5)
                    let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: y - s * 1.6))
                    p.addQuadCurve(to: CGPoint(x: x, y: y + s * 0.6), control: CGPoint(x: x + s * 1.2, y: y))
                    p.addQuadCurve(to: CGPoint(x: x, y: y - s * 1.6), control: CGPoint(x: x - s * 1.2, y: y)); p.closeSubpath()
                    ctx.addPath(p); ctx.setFillColor(c(k % 2 == 0 ? 0xff7a1a : 0xffc23a, 0.85)); ctx.fillPath()
                    glow(ctx, CGPoint(x: x, y: y), s * 0.7, 0xfff0a0, 0.8)
                }
            }
        case "Ice":
            return animationSheet(8) { ctx, o, i, t in
                let grow = min(1, t * 2), shatter = max(0, t * 2 - 1)
                glow(ctx, o, 90, 0x9fe8ff, 0.5 * CGFloat(1 - shatter))
                for k in 0..<8 {
                    let a = Double(k) * .pi / 4 + 0.3
                    let r = 20 + shatter * 70
                    let p = CGPoint(x: o.x + CGFloat(cos(a) * r), y: o.y + CGFloat(sin(a) * r))
                    let len = CGFloat(10 + 26 * grow) * CGFloat(1 - shatter * 0.6)
                    let path = CGMutablePath()
                    path.addLines(between: [CGPoint(x: p.x + CGFloat(cos(a)) * len, y: p.y + CGFloat(sin(a)) * len),
                                            CGPoint(x: p.x + CGFloat(cos(a + 1.6)) * 6, y: p.y + CGFloat(sin(a + 1.6)) * 6),
                                            CGPoint(x: p.x - CGFloat(cos(a)) * len * 0.3, y: p.y - CGFloat(sin(a)) * len * 0.3),
                                            CGPoint(x: p.x + CGFloat(cos(a - 1.6)) * 6, y: p.y + CGFloat(sin(a - 1.6)) * 6)])
                    path.closeSubpath(); ctx.addPath(path); ctx.setFillColor(c(k % 2 == 0 ? 0xdff8ff : 0x8fd8ff, 0.9 - CGFloat(shatter) * 0.6)); ctx.fillPath()
                }
                star(ctx, o, 20 * CGFloat(1 - shatter) + 4, 0xffffff, points: 6, inner: 0.4)
            }
        case "Thunder":
            return animationSheet(6) { ctx, o, i, t in
                if i < 4 {
                    var x = o.x + CGFloat(i % 2 == 0 ? -6 : 6), y = o.y - 96
                    let path = CGMutablePath(); path.move(to: CGPoint(x: x, y: y))
                    var seed = i * 7 + 3
                    while y < o.y + 40 { seed = (seed * 1103 + 12345) % 1000; x += CGFloat(seed % 40 - 20); y += 18; path.addLine(to: CGPoint(x: x, y: y)) }
                    ctx.addPath(path); ctx.setStrokeColor(c(0x8fb8ff, 0.8)); ctx.setLineWidth(9); ctx.strokePath()
                    ctx.addPath(path); ctx.setStrokeColor(c(0xffffff)); ctx.setLineWidth(3.5); ctx.strokePath()
                }
                glow(ctx, CGPoint(x: o.x, y: o.y + 40), 70 + CGFloat(t) * 20, 0xfff8a0, 0.9 * CGFloat(1 - t))
            }
        case "Heal":
            return animationSheet(8) { ctx, o, i, t in
                glow(ctx, o, 80, 0x9fffb0, 0.45 * CGFloat(sin(t * .pi)))
                for k in 0..<10 {
                    let x = o.x + CGFloat((k * 37) % 120 - 60), y = o.y + 60 - CGFloat((t * 120 + Double(k * 23)).truncatingRemainder(dividingBy: 140))
                    star(ctx, CGPoint(x: x, y: y), CGFloat(5 + k % 3 * 3), k % 2 == 0 ? 0xffffff : 0xb8ffc8, points: 4, inner: 0.3, rot: t * 4)
                }
                ctx.setStrokeColor(c(0xd8ffe0, 0.8 * (1 - t))); ctx.setLineWidth(3)
                ctx.strokeEllipse(in: CGRect(x: o.x - 30 - CGFloat(t) * 40, y: o.y + 30 - CGFloat(t) * 12, width: 60 + CGFloat(t) * 80, height: 24 + CGFloat(t) * 24))
            }
        case "Poison":
            return animationSheet(6) { ctx, o, i, t in
                for k in 0..<9 {
                    let x = o.x + CGFloat((k * 29) % 100 - 50), y = o.y + 40 - CGFloat((t * 90 + Double(k * 17)).truncatingRemainder(dividingBy: 100))
                    let r = CGFloat(6 + k % 3 * 4)
                    ctx.setFillColor(c(0xa060e0, 0.75)); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    ctx.setFillColor(c(0xe0c0ff, 0.9)); ctx.fillEllipse(in: CGRect(x: x - r * 0.4, y: y - r * 0.6, width: r * 0.5, height: r * 0.5))
                }
                glow(ctx, o, 70, 0x7a2aa0, 0.4 * CGFloat(1 - t))
            }
        case "Sleep":
            return animationSheet(6) { ctx, o, i, t in
                glow(ctx, o, 80, 0xb090ff, 0.35)
                for k in 0..<3 {
                    let tt = (t + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    NSAttributedStringShim.draw("Z", in: ctx, at: CGPoint(x: o.x - 30 + CGFloat(k * 22) + CGFloat(tt * 20), y: o.y + 10 - CGFloat(tt * 70)),
                                                size: CGFloat(18 + tt * 22), color: c(k % 2 == 0 ? 0xdcd0ff : 0x9fc8ff, 1 - tt * 0.6))
                }
            }
        case "Darkness":
            return animationSheet(6) { ctx, o, i, t in
                for k in 0..<6 {
                    let a = Double(k) * 1.05 + t * 3
                    let r = 30 + t * 30
                    glow(ctx, CGPoint(x: o.x + CGFloat(cos(a) * r), y: o.y + CGFloat(sin(a) * r * 0.6)), 40, 0x30203a, 0.8 * CGFloat(1 - t * 0.6))
                }
                glow(ctx, o, 50, 0x120818, 0.9 * CGFloat(sin(t * .pi)))
            }
        case "Wind":
            return animationSheet(8) { ctx, o, i, t in
                for k in 0..<5 {
                    let r = CGFloat(30 + k * 12), start = CGFloat(t * 6 + Double(k))
                    ctx.setLineCap(.round); ctx.setStrokeColor(c(0xe8fff0, 0.7 - CGFloat(k) * 0.1)); ctx.setLineWidth(CGFloat(5 - k / 2))
                    ctx.addArc(center: o, radius: r, startAngle: start, endAngle: start + 2, clockwise: false); ctx.strokePath()
                }
                for k in 0..<4 {
                    let a = t * 8 + Double(k) * 1.6
                    let p = CGPoint(x: o.x + CGFloat(cos(a) * 60), y: o.y + CGFloat(sin(a) * 30))
                    let leaf = CGRect(x: p.x - 6, y: p.y - 3, width: 12, height: 6)
                    ctx.setFillColor(c(0x6fbf5a)); ctx.fillEllipse(in: leaf)
                }
            }
        default: // Sparkle
            return animationSheet(6) { ctx, o, i, t in
                for k in 0..<12 {
                    let a = Double(k) * 0.52 + t * 1.5
                    let r = 20 + t * 70 * (0.6 + Double(k % 3) * 0.2)
                    star(ctx, CGPoint(x: o.x + CGFloat(cos(a) * r), y: o.y + CGFloat(sin(a) * r)), CGFloat(10 - t * 6), k % 2 == 0 ? 0xfff6c0 : 0xffffff, points: 4, inner: 0.2, rot: t * 3)
                }
                glow(ctx, o, 60, 0xfff0a0, 0.6 * CGFloat(1 - t))
            }
        }
    }

    // MARK: sample Animations.json (MV format)

    static func cells(_ frames: Int, start: Int = 0, x: Double = 0, y: Double = 0, scale: Double = 100, blend: Double = 1,
                      extra: (Int) -> [[Double]] = { _ in [] }) -> [[[Double]]] {
        (0..<frames).map { f in [[Double(start + f), x, y, scale, 0, 0, 255, blend]] + extra(f) }
    }

    /// Frames that show cells 0…count−1 of a sheet in turn, centred and additive (the editor's "rebuild frames").
    public static func sheetCells(_ sheet: String, _ count: Int) -> [[[Double]]] { cells(max(1, count)) }

    public static func animations() -> [AnimationData?] {
        func mv(_ id: Int, _ name: String, _ sheet: String, _ frames: [[[Double]]], position: Int = 1, timings: [AnimationData.MVTiming]) -> AnimationData {
            var a = AnimationData(id: id, name: name)
            a.frames = frames; a.animation1Name = sheet; a.animation2Name = ""; a.position = position; a.timings = timings
            return a
        }
        typealias T = AnimationData.MVTiming
        func se(_ n: String, _ v: Int = 90, _ p: Int = 100) -> AudioFile { AudioFile(n, volume: v, pitch: p) }
        return [nil,
            mv(1, "Hit Physical", "Hit", cells(5), timings: [T(frame: 0, se: se("Blow")), T(frame: 1, flashScope: 1, flashColor: [255, 255, 255, 170], flashDuration: 2)]),
            mv(2, "Slash Physical", "Slash", cells(5, extra: { f in f >= 2 ? [[Double(f - 2), 10, 10, 80, 0, 0, 200, 1]] : [] }),
               timings: [T(frame: 0, se: se("Slash")), T(frame: 2, flashScope: 1, flashColor: [255, 255, 255, 170], flashDuration: 2), T(frame: 2, se: se("Blow", 70))]),
            mv(3, "Fire One", "Fire", cells(8, y: -8, scale: 110, extra: { f in f >= 3 ? [[Double(f - 3), -36, 18, 60, 0, 0, 180, 1], [Double(f - 3), 38, 22, 55, 0, 1, 180, 1]] : [] }),
               timings: [T(frame: 0, se: se("Fire")), T(frame: 2, flashScope: 1, flashColor: [255, 136, 51, 170], flashDuration: 4), T(frame: 3, flashScope: 2, flashColor: [255, 102, 0, 60], flashDuration: 3)]),
            mv(4, "Thunder One", "Thunder", cells(6, y: -30, scale: 120),
               timings: [T(frame: 0, se: se("Thunder")), T(frame: 0, flashScope: 2, flashColor: [255, 255, 255, 136], flashDuration: 2), T(frame: 1, flashScope: 1, flashColor: [255, 255, 160, 200], flashDuration: 3)]),
            mv(5, "Ice One", "Ice", cells(8),
               timings: [T(frame: 0, se: se("Ice")), T(frame: 4, flashScope: 1, flashColor: [160, 220, 255, 170], flashDuration: 3), T(frame: 4, se: se("Ice", 70, 130))]),
            mv(6, "Heal One", "Heal", cells(8, y: -10), timings: [T(frame: 0, se: se("Recovery")), T(frame: 2, flashScope: 1, flashColor: [160, 255, 170, 136], flashDuration: 4)]),
            mv(7, "Poison", "Poison", cells(6, blend: 0), timings: [T(frame: 0, se: se("Darkness", 70, 140)), T(frame: 1, flashScope: 1, flashColor: [160, 80, 220, 136], flashDuration: 3)]),
            mv(8, "Sleep", "Sleep", cells(6, y: -40, blend: 0), position: 0, timings: [T(frame: 0, se: se("Skill", 70, 80))]),
            mv(9, "Darkness", "Darkness", cells(6, blend: 0), timings: [T(frame: 0, se: se("Darkness")), T(frame: 2, flashScope: 1, flashColor: [0, 0, 0, 170], flashDuration: 3)]),
            mv(10, "Wind", "Wind", cells(8), timings: [T(frame: 0, se: se("Wind"))]),
            mv(11, "Sparkle", "Sparkle", cells(6, y: -20), timings: [T(frame: 0, se: se("Item", 80))]),
            mv(12, "Spirit Burst", "Heal", cells(8, scale: 160, extra: { f in f < 6 ? [[Double(f), 0, -30, 120, 0, 0, 255, 1]] : [] }),
               timings: [T(frame: 0, se: se("Wind", 90, 70)), T(frame: 1, flashScope: 2, flashColor: [120, 255, 160, 120], flashDuration: 4), T(frame: 3, se: se("Recovery", 90, 80))]),
        ]
    }

    // MARK: state overlays, shadow

    /// img/system/States.png: overlay 1 poison, 2 blind, 3 silence, 4 rage, 5 confusion, 6 fascination,
    /// 7 sleep, 8 paralyze, 9 curse, 10 fear (MZ's row order).
    public static func makeStateOverlays() -> CGImage {
        let ctx = makeCanvas(768, 960)
        for row in 0..<10 { for f in 0..<8 {
            let o = CGPoint(x: f * 96 + 48, y: row * 96)
            let t = Double(f) / 8
            switch row {
            case 0:
                for k in 0..<4 { let y = o.y + 70 - CGFloat((t * 60 + Double(k * 15)).truncatingRemainder(dividingBy: 60)); ctx.setFillColor(c(0xb070f0, 0.8)); ctx.fillEllipse(in: CGRect(x: o.x - 20 + CGFloat(k * 12), y: y, width: 7, height: 7)) }
            case 1: glow(ctx, CGPoint(x: o.x, y: o.y + 34), 22, 0x101018, 0.75)
            case 2: for k in 0..<3 { ctx.setFillColor(c(0xffffff, (f / 2 + k) % 3 == 0 ? 1 : 0.4)); ctx.fillEllipse(in: CGRect(x: o.x - 14 + CGFloat(k * 10), y: o.y + 18, width: 6, height: 6)) }
            case 3: star(ctx, CGPoint(x: o.x + 14, y: o.y + 22), CGFloat(8 + f % 2 * 2), 0xff3030, points: 4, inner: 0.35, rot: 0.78)
            case 4:
                for k in 0..<3 { let a = t * 2 * .pi + Double(k) * 2.09; star(ctx, CGPoint(x: o.x + CGFloat(cos(a) * 18), y: o.y + 22 + CGFloat(sin(a) * 5)), 6, 0xffe04a, points: 5, inner: 0.45) }
            case 5: NSAttributedStringShim.draw("♥", in: ctx, at: CGPoint(x: o.x + 4, y: o.y + 8 - CGFloat(f % 4)), size: 16, color: c(0xff6fa8))
            case 6: NSAttributedStringShim.draw("z", in: ctx, at: CGPoint(x: o.x + 8 + CGFloat(f % 4) * 2, y: o.y + 18 - CGFloat(f % 4) * 3), size: CGFloat(12 + f % 4 * 2), color: c(0x9fc8ff))
            case 7: ctx.setStrokeColor(c(0xfff060, f % 2 == 0 ? 1 : 0.5)); ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: o.x - 20, y: o.y + 40)); ctx.addLine(to: CGPoint(x: o.x - 12, y: o.y + 48)); ctx.addLine(to: CGPoint(x: o.x - 18, y: o.y + 52)); ctx.addLine(to: CGPoint(x: o.x - 8, y: o.y + 60)); ctx.strokePath()
            case 8: glow(ctx, CGPoint(x: o.x + CGFloat(sin(t * 6) * 10), y: o.y + 30), 18, 0x6a2a8a, 0.7)
            default: ctx.setFillColor(c(0x8fd0ff, 0.9)); ctx.fillEllipse(in: CGRect(x: o.x + 14, y: o.y + 20 + CGFloat(f % 4 * 3), width: 6, height: 9))
            }
        } }
        return ctx.makeImage()!
    }

    public static func makeShadow() -> CGImage {
        let ctx = makeCanvas(48, 16)
        ctx.setFillColor(c(0x000000, 0.35)); ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 44, height: 12))
        return ctx.makeImage()!
    }

    // MARK: parallaxes

    /// 16-bit hash in 0..<m (noise() is only 8 bits, too narrow for screen-sized scatter).
    static func wide(_ i: Int, _ a: Int, _ seed: Int, _ m: Int) -> Int { (noise(i, a, seed) << 8 | noise(i, a + 50, seed)) % m }

    /// "Sky": seamless horizontally (for loop-X scrolling). "!Starlit": a "!" (zero) parallax that moves with the map.
    public static func makeParallax(_ name: String) -> CGImage {
        let w = 816, h = 624
        let ctx = makeCanvas(w, h)
        if name == "Sky" {
            for y in stride(from: 0, to: h, by: 4) {
                let t = Double(y) / Double(h)
                ctx.setFillColor(CGColor(red: 0.35 + 0.45 * t, green: 0.6 + 0.3 * t, blue: 0.95, alpha: 1)); ctx.fill(CGRect(x: 0, y: y, width: w, height: 4))
            }
            for i in 0..<14 {
                let cx = Double(i * w / 14 + wide(i, 1, 11, 50)), cy = 50 + Double(wide(i, 2, 11, 500)), s = 0.5 + Double(noise(i, 3, 11) % 60) / 80
                for dx in [-Double(w), 0, Double(w)] {   // draw wrapped copies so the image tiles seamlessly
                    for (ox, r) in [(0.0, 34.0), (38, 44), (84, 30), (40, 30)] {
                        ctx.setFillColor(c(0xffffff, 0.85)); ctx.fillEllipse(in: CGRect(x: cx + dx + ox * s, y: cy - r * s / 2 + (ox == 40 && r == 30 ? 14 * s : 0), width: r * 2 * s, height: r * 1.2 * s))
                    }
                }
            }
        } else {
            ctx.setFillColor(c(0x0c1030)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            glow(ctx, CGPoint(x: 600, y: 160), 260, 0x3a2a6a, 0.6)
            glow(ctx, CGPoint(x: 200, y: 480), 220, 0x1a3a6a, 0.5)
            for i in 0..<220 {
                let x = Double(wide(i, 4, 7, w)), y = Double(wide(i, 5, 7, h)), r = 1 + Double(noise(i, 6, 7) % 3)
                ctx.setFillColor(c(i % 7 == 0 ? 0xfff0c0 : 0xffffff, 0.5 + Double(noise(i, 8, 7) % 50) / 100)); ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            star(ctx, CGPoint(x: 640, y: 120), 26, 0xfff6d0, points: 4, inner: 0.15)
        }
        return ctx.makeImage()!
    }

    /// Writes the side-view / animation / overlay / parallax assets into a project.
    public static func writeBattleArt(to project: Project) throws {
        for (i, look) in actorLooks.enumerated() { try writePNG(makeSVActor(look), to: project.imageURL("sv_actors", "Actor1_\(i + 1)")) }
        try writePNG(makeWeapons(), to: project.imageURL("system", "Weapons1"))
        try writePNG(makeStateOverlays(), to: project.imageURL("system", "States"))
        try writePNG(makeShadow(), to: project.imageURL("system", "Shadow2"))
        for n in animationSheetNames { try writePNG(makeAnimationSheet(n), to: project.imageURL("animations", n)) }
        for n in ["Sky", "!Starlit"] { try writePNG(makeParallax(n), to: project.imageURL("parallaxes", n)) }
        for n in ["Slime", "Bat", "Snake", "Forest_Spirit"] { try writePNG(makeEnemy(n), to: project.imageURL("sv_enemies", n)) }
    }
}
