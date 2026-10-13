import CoreGraphics
import Foundation
import LakonCore

/// Second batch of procedural art: battlers, battlebacks, vehicles, the icon sheet, a picture, extra terrain.
extension DefaultArt {
    // Extra A2 kinds
    public static let tallGrass = 6, deepWater = 11, swamp = 12, mountainGround = 13
    // Extra A5
    public static let a5Counter = 8, a5Lava = 9
    // Extra B
    public static let bMountain = 21, bPine = 22, bShrine = 23, bSignBoard = 25, bCampfire = 26, bTent = 27, bDock = 28

    static let extraA2: [Int: Ground] = [
        tallGrass: Ground(base: 0x4f9a3c, dark: 0x3b7f2d, light: 0x7cc25b, edge: 0x2f6a25, overlay: true, pattern: .leaves),
        deepWater: Ground(base: 0x23559a, dark: 0x1a447e, light: 0x5d8fd0, edge: 0x3d7fc4, pattern: .waves),
        swamp: Ground(base: 0x5b6b3a, dark: 0x4a5a2c, light: 0x8a7fb0, edge: 0x3c4a24, pattern: .speckle),
        mountainGround: Ground(base: 0x9c8a6a, dark: 0x7c6a4e, light: 0xbcae8e, edge: 0x5e4e36),
    ]

    // MARK: icons (img/system/IconSet.png, 32 px, 16 per row — MZ layout)
    public static let iconPotion = 1, iconEther = 2, iconAntidote = 3, iconKey = 4, iconSword = 5, iconDagger = 6, iconShield = 7
    public static let iconVest = 8, iconRobe = 9, iconBandana = 10, iconCharm = 11, iconFire = 12, iconIce = 13, iconThunder = 14
    public static let iconHeal = 15, iconSlash = 16, iconScroll = 17, iconPoison = 18, iconSleep = 19, iconBlind = 20
    public static let iconKnockout = 21, iconGold = 23, iconGuard = 24, iconConfuse = 25

    public static func makeIconSet() -> CGImage {
        let ctx = makeCanvas(512, 128)
        func r(_ i: Int) -> CGRect { CGRect(x: (i % 16) * 32, y: (i / 16) * 32, width: 32, height: 32) }
        func flask(_ i: Int, _ liquid: UInt32) {
            let b = r(i)
            ctx.setFillColor(c(0xdfe6ee)); ctx.fill(CGRect(x: b.minX + 13, y: b.minY + 4, width: 6, height: 8))
            ctx.setFillColor(c(0x8a5a30)); ctx.fill(CGRect(x: b.minX + 12, y: b.minY + 3, width: 8, height: 3))
            ctx.setFillColor(c(0xdfe6ee)); ctx.fillEllipse(in: CGRect(x: b.minX + 6, y: b.minY + 10, width: 20, height: 19))
            ctx.setFillColor(c(liquid)); ctx.fillEllipse(in: CGRect(x: b.minX + 8, y: b.minY + 14, width: 16, height: 13))
            ctx.setFillColor(c(0xffffff, 0.7)); ctx.fillEllipse(in: CGRect(x: b.minX + 10, y: b.minY + 15, width: 4, height: 4))
        }
        flask(iconPotion, 0xd93f3f); flask(iconEther, 0x3f7fd9); flask(iconAntidote, 0x4fbf4f)
        do { let b = r(iconKey)
            ctx.setFillColor(c(0xe0b44c)); ctx.fillEllipse(in: CGRect(x: b.minX + 4, y: b.minY + 4, width: 12, height: 12))
            ctx.setFillColor(c(0x000000, 0)); ctx.clear(CGRect(x: b.minX + 8, y: b.minY + 8, width: 4, height: 4))
            ctx.setFillColor(c(0xe0b44c)); ctx.fill(CGRect(x: b.minX + 14, y: b.minY + 9, width: 14, height: 3)); ctx.fill(CGRect(x: b.minX + 22, y: b.minY + 12, width: 3, height: 6)); ctx.fill(CGRect(x: b.minX + 26, y: b.minY + 12, width: 2, height: 4)) }
        func blade(_ i: Int, _ len: CGFloat, _ col: UInt32) {
            let b = r(i)
            ctx.saveGState(); ctx.translateBy(x: b.midX, y: b.midY); ctx.rotate(by: -.pi / 4)
            ctx.setFillColor(c(col)); ctx.fill(CGRect(x: -2.5, y: -len / 2 - 2, width: 5, height: len))
            ctx.setFillColor(c(0xffffff, 0.6)); ctx.fill(CGRect(x: -2.5, y: -len / 2 - 2, width: 1.5, height: len))
            ctx.setFillColor(c(0xe0b44c)); ctx.fill(CGRect(x: -7, y: len / 2 - 3, width: 14, height: 3))
            ctx.setFillColor(c(0x6b4423)); ctx.fill(CGRect(x: -2, y: len / 2, width: 4, height: 7))
            ctx.restoreGState()
        }
        blade(iconSword, 24, 0xc8d0dc); blade(iconDagger, 15, 0xc8d0dc); blade(iconSlash, 24, 0xffe28a)
        do { let b = r(iconShield)
            let p = CGMutablePath(); p.move(to: CGPoint(x: b.minX + 6, y: b.minY + 5)); p.addLine(to: CGPoint(x: b.maxX - 6, y: b.minY + 5))
            p.addLine(to: CGPoint(x: b.maxX - 6, y: b.minY + 16)); p.addQuadCurve(to: CGPoint(x: b.midX, y: b.maxY - 3), control: CGPoint(x: b.maxX - 8, y: b.maxY - 6))
            p.addQuadCurve(to: CGPoint(x: b.minX + 6, y: b.minY + 16), control: CGPoint(x: b.minX + 8, y: b.maxY - 6)); p.closeSubpath()
            ctx.addPath(p); ctx.setFillColor(c(0x8a5a30)); ctx.fillPath()
            ctx.setFillColor(c(0xc8d0dc)); ctx.fill(CGRect(x: b.midX - 1.5, y: b.minY + 6, width: 3, height: 20)); ctx.fill(CGRect(x: b.minX + 8, y: b.minY + 13, width: 16, height: 3)) }
        func garment(_ i: Int, _ col: UInt32, long: Bool) {
            let b = r(i)
            ctx.setFillColor(c(col)); ctx.fill(CGRect(x: b.minX + 9, y: b.minY + 6, width: 14, height: long ? 22 : 17))
            ctx.fill(CGRect(x: b.minX + 4, y: b.minY + 6, width: 24, height: 7))
            ctx.setFillColor(c(0x000000, 0.25)); ctx.fill(CGRect(x: b.minX + 15, y: b.minY + 6, width: 2, height: long ? 22 : 17))
        }
        garment(iconVest, 0x9a6b3c, long: false); garment(iconRobe, 0x5a4aa8, long: true)
        do { let b = r(iconBandana); ctx.setFillColor(c(0xa53a3a)); ctx.fillEllipse(in: CGRect(x: b.minX + 5, y: b.minY + 8, width: 22, height: 14)); ctx.fill(CGRect(x: b.minX + 22, y: b.minY + 16, width: 6, height: 10)) }
        do { let b = r(iconCharm); ctx.setStrokeColor(c(0xe0b44c)); ctx.setLineWidth(2); ctx.strokeEllipse(in: CGRect(x: b.minX + 9, y: b.minY + 2, width: 14, height: 12))
            ctx.setFillColor(c(0x4fbf9f)); ctx.fillEllipse(in: CGRect(x: b.minX + 8, y: b.minY + 13, width: 16, height: 16)) }
        func burst(_ i: Int, _ a: UInt32, _ b2: UInt32) {
            let b = r(i)
            ctx.setFillColor(c(a)); ctx.fillEllipse(in: b.insetBy(dx: 5, dy: 5))
            ctx.setFillColor(c(b2)); ctx.fillEllipse(in: b.insetBy(dx: 10, dy: 10))
        }
        do { let b = r(iconFire)
            let p = CGMutablePath(); p.move(to: CGPoint(x: b.midX, y: b.minY + 3)); p.addQuadCurve(to: CGPoint(x: b.maxX - 6, y: b.maxY - 8), control: CGPoint(x: b.maxX - 2, y: b.minY + 14))
            p.addQuadCurve(to: CGPoint(x: b.minX + 6, y: b.maxY - 8), control: CGPoint(x: b.midX, y: b.maxY + 4)); p.addQuadCurve(to: CGPoint(x: b.midX, y: b.minY + 3), control: CGPoint(x: b.minX + 2, y: b.minY + 14))
            ctx.addPath(p); ctx.setFillColor(c(0xe8602a)); ctx.fillPath()
            ctx.setFillColor(c(0xffd04a)); ctx.fillEllipse(in: CGRect(x: b.midX - 5, y: b.midY, width: 10, height: 10)) }
        do { let b = r(iconIce)
            ctx.setStrokeColor(c(0x9fd4f0)); ctx.setLineWidth(3)
            for k in 0..<3 { let a = CGFloat(k) * .pi / 3; ctx.move(to: CGPoint(x: b.midX + cos(a) * 12, y: b.midY + sin(a) * 12)); ctx.addLine(to: CGPoint(x: b.midX - cos(a) * 12, y: b.midY - sin(a) * 12)) }
            ctx.strokePath() }
        do { let b = r(iconThunder)
            let p = CGMutablePath(); p.addLines(between: [CGPoint(x: b.minX + 18, y: b.minY + 2), CGPoint(x: b.minX + 8, y: b.minY + 17), CGPoint(x: b.minX + 15, y: b.minY + 17),
                                                         CGPoint(x: b.minX + 11, y: b.maxY - 2), CGPoint(x: b.minX + 24, y: b.minY + 13), CGPoint(x: b.minX + 17, y: b.minY + 13)])
            p.closeSubpath(); ctx.addPath(p); ctx.setFillColor(c(0xf2d24b)); ctx.fillPath() }
        do { let b = r(iconHeal); ctx.setFillColor(c(0x4fbf4f)); ctx.fill(CGRect(x: b.midX - 4, y: b.minY + 5, width: 8, height: 22)); ctx.fill(CGRect(x: b.minX + 5, y: b.midY - 4, width: 22, height: 8)) }
        do { let b = r(iconScroll); ctx.setFillColor(c(0xf3e3b0)); ctx.fill(CGRect(x: b.minX + 6, y: b.minY + 8, width: 20, height: 16))
            ctx.setFillColor(c(0xc08d55)); ctx.fillEllipse(in: CGRect(x: b.minX + 3, y: b.minY + 6, width: 6, height: 20)); ctx.fillEllipse(in: CGRect(x: b.maxX - 9, y: b.minY + 6, width: 6, height: 20))
            ctx.setFillColor(c(0xa53a3a)); ctx.fill(CGRect(x: b.minX + 11, y: b.minY + 13, width: 10, height: 2)); ctx.fill(CGRect(x: b.minX + 11, y: b.minY + 17, width: 8, height: 2)) }
        do { let b = r(iconPoison); ctx.setFillColor(c(0x8f4fbf)); ctx.fillEllipse(in: CGRect(x: b.minX + 7, y: b.minY + 5, width: 18, height: 16)); ctx.fill(CGRect(x: b.minX + 11, y: b.minY + 18, width: 10, height: 8))
            ctx.setFillColor(c(0x1a1a22)); ctx.fillEllipse(in: CGRect(x: b.minX + 10, y: b.minY + 11, width: 5, height: 5)); ctx.fillEllipse(in: CGRect(x: b.minX + 17, y: b.minY + 11, width: 5, height: 5)) }
        do { let b = r(iconSleep)
            let s = NSAttributedStringShim.draw("Zz", in: ctx, at: CGPoint(x: b.minX + 5, y: b.minY + 4), size: 18, color: c(0x9fd4f0)); _ = s }
        burst(iconBlind, 0x2b2b33, 0x5f6170)
        do { let b = r(iconKnockout); ctx.setStrokeColor(c(0xd93f3f)); ctx.setLineWidth(4)
            ctx.move(to: CGPoint(x: b.minX + 7, y: b.minY + 7)); ctx.addLine(to: CGPoint(x: b.maxX - 7, y: b.maxY - 7))
            ctx.move(to: CGPoint(x: b.maxX - 7, y: b.minY + 7)); ctx.addLine(to: CGPoint(x: b.minX + 7, y: b.maxY - 7)); ctx.strokePath() }
        burst(iconGold, 0xc8961e, 0xf2d24b)
        do { let b = r(iconGuard); ctx.setFillColor(c(0x5f87c8)); ctx.fillEllipse(in: b.insetBy(dx: 5, dy: 5)); ctx.setFillColor(c(0xc8d8f0)); ctx.fillEllipse(in: b.insetBy(dx: 11, dy: 11)) }
        burst(iconConfuse, 0xe8607a, 0xf2d24b)
        // Buff (32+) and debuff (48+) arrows per param.
        for p in 0..<8 {
            for (base, up) in [(32, true), (48, false)] {
                let b = r(base + p)
                let col: UInt32 = up ? 0xe8602a : 0x3f7fd9
                let path = CGMutablePath()
                if up { path.addLines(between: [CGPoint(x: b.midX, y: b.minY + 4), CGPoint(x: b.maxX - 5, y: b.midY), CGPoint(x: b.minX + 5, y: b.midY)]) }
                else { path.addLines(between: [CGPoint(x: b.midX, y: b.maxY - 4), CGPoint(x: b.maxX - 5, y: b.midY), CGPoint(x: b.minX + 5, y: b.midY)]) }
                path.closeSubpath(); ctx.addPath(path); ctx.setFillColor(c(col)); ctx.fillPath()
                ctx.fill(CGRect(x: b.midX - 4, y: up ? b.midY : b.minY + 6, width: 8, height: b.height / 2 - 6))
            }
        }
        return ctx.makeImage()!
    }

    // MARK: enemies (img/enemies, front view)

    public static func makeEnemy(_ name: String) -> CGImage {
        switch name {
        case "Slime":
            let ctx = makeCanvas(160, 130)
            ctx.setFillColor(c(0x000000, 0.25)); ctx.fillEllipse(in: CGRect(x: 18, y: 108, width: 124, height: 18))
            let p = CGMutablePath(); p.move(to: CGPoint(x: 14, y: 112))
            p.addCurve(to: CGPoint(x: 80, y: 12), control1: CGPoint(x: 6, y: 50), control2: CGPoint(x: 52, y: 14))
            p.addCurve(to: CGPoint(x: 146, y: 112), control1: CGPoint(x: 108, y: 14), control2: CGPoint(x: 154, y: 50))
            p.closeSubpath()
            ctx.addPath(p); ctx.setFillColor(c(0x3f9fe0)); ctx.fillPath()
            ctx.addPath(p); ctx.setStrokeColor(c(0x1f5f9a)); ctx.setLineWidth(4); ctx.strokePath()
            ctx.setFillColor(c(0xbfe6ff, 0.8)); ctx.fillEllipse(in: CGRect(x: 40, y: 30, width: 26, height: 16))
            for x in [56.0, 92] { ctx.setFillColor(c(0xffffff)); ctx.fillEllipse(in: CGRect(x: x, y: 58, width: 16, height: 20)); ctx.setFillColor(c(0x1a1a22)); ctx.fillEllipse(in: CGRect(x: x + 5, y: 64, width: 8, height: 11)) }
            ctx.setStrokeColor(c(0x1a1a22)); ctx.setLineWidth(3); ctx.addArc(center: CGPoint(x: 80, y: 86), radius: 10, startAngle: 0.3, endAngle: .pi - 0.3, clockwise: false); ctx.strokePath()
            return ctx.makeImage()!
        case "Bat":
            let ctx = makeCanvas(220, 140)
            for flip in [1.0, -1.0] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 110, y: 60))
                p.addCurve(to: CGPoint(x: 110 + 100 * flip, y: 20), control1: CGPoint(x: 110 + 30 * flip, y: 20), control2: CGPoint(x: 110 + 70 * flip, y: 0))
                p.addLine(to: CGPoint(x: 110 + 90 * flip, y: 80))
                p.addQuadCurve(to: CGPoint(x: 110 + 60 * flip, y: 76), control: CGPoint(x: 110 + 76 * flip, y: 64))
                p.addQuadCurve(to: CGPoint(x: 110 + 30 * flip, y: 82), control: CGPoint(x: 110 + 46 * flip, y: 66))
                p.addQuadCurve(to: CGPoint(x: 110, y: 80), control: CGPoint(x: 110 + 16 * flip, y: 70))
                p.closeSubpath()
                ctx.addPath(p); ctx.setFillColor(c(0x5a3a7a)); ctx.fillPath()
                ctx.addPath(p); ctx.setStrokeColor(c(0x2e1a44)); ctx.setLineWidth(3); ctx.strokePath()
            }
            ctx.setFillColor(c(0x6e4a92)); ctx.fillEllipse(in: CGRect(x: 84, y: 40, width: 52, height: 62))
            ctx.setFillColor(c(0x6e4a92)); for x in [86.0, 120] { let t = CGMutablePath(); t.addLines(between: [CGPoint(x: x, y: 50), CGPoint(x: x + 6, y: 26), CGPoint(x: x + 14, y: 48)]); t.closeSubpath(); ctx.addPath(t); ctx.fillPath() }
            for x in [96.0, 114] { ctx.setFillColor(c(0xffe04a)); ctx.fillEllipse(in: CGRect(x: x, y: 58, width: 10, height: 10)) }
            ctx.setFillColor(c(0xffffff)); for x in [102.0, 113] { let t = CGMutablePath(); t.addLines(between: [CGPoint(x: x, y: 80), CGPoint(x: x + 3, y: 88), CGPoint(x: x + 6, y: 80)]); ctx.addPath(t); ctx.fillPath() }
            return ctx.makeImage()!
        case "Snake":
            let ctx = makeCanvas(180, 170)
            ctx.setFillColor(c(0x000000, 0.25)); ctx.fillEllipse(in: CGRect(x: 20, y: 146, width: 140, height: 18))
            for (i, y) in [130.0, 108, 86].enumerated() {
                let w = 140 - Double(i) * 26
                ctx.setFillColor(c(i % 2 == 0 ? 0x3f8f3a : 0x4fa846)); ctx.fillEllipse(in: CGRect(x: 90 - w / 2, y: y, width: w, height: 30))
                ctx.setStrokeColor(c(0x22551f)); ctx.setLineWidth(3); ctx.strokeEllipse(in: CGRect(x: 90 - w / 2, y: y, width: w, height: 30))
            }
            ctx.setFillColor(c(0x4fa846)); ctx.fill(CGRect(x: 76, y: 40, width: 28, height: 56))
            ctx.fillEllipse(in: CGRect(x: 60, y: 16, width: 60, height: 44))
            ctx.setStrokeColor(c(0x22551f)); ctx.strokeEllipse(in: CGRect(x: 60, y: 16, width: 60, height: 44))
            ctx.setFillColor(c(0xf2d24b)); for x in [72.0, 98] { ctx.fillEllipse(in: CGRect(x: x, y: 28, width: 10, height: 12)) }
            ctx.setFillColor(c(0x1a1a22)); for x in [76.0, 102] { ctx.fill(CGRect(x: x, y: 29, width: 3, height: 10)) }
            ctx.setStrokeColor(c(0xd93f3f)); ctx.setLineWidth(3); ctx.move(to: CGPoint(x: 90, y: 58)); ctx.addLine(to: CGPoint(x: 90, y: 72)); ctx.addLine(to: CGPoint(x: 84, y: 78)); ctx.move(to: CGPoint(x: 90, y: 72)); ctx.addLine(to: CGPoint(x: 96, y: 78)); ctx.strokePath()
            return ctx.makeImage()!
        default: // Forest Spirit (boss)
            let ctx = makeCanvas(300, 320)
            ctx.setFillColor(c(0x000000, 0.25)); ctx.fillEllipse(in: CGRect(x: 40, y: 290, width: 220, height: 26))
            for (dx, h) in [(-70.0, 200.0), (70, 210), (0, 240)] {
                ctx.setFillColor(c(0x1f5a2b)); ctx.fillEllipse(in: CGRect(x: 150 + dx - 70, y: 300 - h - 40, width: 140, height: 150))
            }
            ctx.setFillColor(c(0x2f7d3b)); ctx.fillEllipse(in: CGRect(x: 70, y: 30, width: 160, height: 150))
            ctx.setFillColor(c(0x4fa257)); ctx.fillEllipse(in: CGRect(x: 100, y: 46, width: 60, height: 40))
            let trunk = CGMutablePath()
            trunk.move(to: CGPoint(x: 110, y: 300)); trunk.addLine(to: CGPoint(x: 120, y: 150)); trunk.addLine(to: CGPoint(x: 180, y: 150)); trunk.addLine(to: CGPoint(x: 190, y: 300)); trunk.closeSubpath()
            ctx.addPath(trunk); ctx.setFillColor(c(0x6b4423)); ctx.fillPath()
            ctx.setStrokeColor(c(0x4a2f17)); ctx.setLineWidth(4); for x in [130.0, 150, 170] { ctx.move(to: CGPoint(x: x, y: 160)); ctx.addLine(to: CGPoint(x: x + (x - 150) * 0.2, y: 296)) }; ctx.strokePath()
            for x in [126.0, 160] { ctx.setFillColor(c(0x1a1a22)); ctx.fillEllipse(in: CGRect(x: x, y: 182, width: 22, height: 26)); ctx.setFillColor(c(0x9fffd0)); ctx.fillEllipse(in: CGRect(x: x + 5, y: 188, width: 12, height: 14)) }
            ctx.setFillColor(c(0x1a1a22)); ctx.fillEllipse(in: CGRect(x: 134, y: 228, width: 40, height: 22))
            for (x, y) in [(60.0, 120.0), (240, 110), (110, 30), (200, 40), (150, 10)] { ctx.setFillColor(c(0x9fffd0, 0.8)); ctx.fillEllipse(in: CGRect(x: x, y: y, width: 10, height: 10)) }
            return ctx.makeImage()!
        }
    }

    // MARK: battlebacks (1000 x 740, MZ size)

    public static func makeBattleback1() -> CGImage {
        let ctx = makeCanvas(1000, 740)
        for y in stride(from: 380, to: 740, by: 4) {
            let t = Double(y - 380) / 360
            ctx.setFillColor(CGColor(red: 0.30 + 0.05 * t, green: 0.55 + 0.08 * t, blue: 0.24, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: 1000, height: 4))
        }
        // Perspective furrows
        ctx.setStrokeColor(c(0x2f6a25, 0.35)); ctx.setLineWidth(2)
        for i in -10...10 { ctx.move(to: CGPoint(x: 500 + Double(i) * 30, y: 380)); ctx.addLine(to: CGPoint(x: 500 + Double(i) * 160, y: 740)) }
        ctx.strokePath()
        for i in 0..<220 {
            let x = Double(noise(i, 1, 3) * 4 % 1000), y = 390 + Double(noise(i, 2, 3) * 3 % 350)
            ctx.setFillColor(c(noise(i, 3, 3) % 2 == 0 ? 0x86c45f : 0x3f7a31)); ctx.fill(CGRect(x: x, y: y, width: 6, height: 3))
        }
        return ctx.makeImage()!
    }

    public static func makeBattleback2() -> CGImage {
        let ctx = makeCanvas(1000, 740)
        for y in stride(from: 0, to: 400, by: 4) {
            let t = Double(y) / 400
            ctx.setFillColor(CGColor(red: 0.45 + 0.35 * t, green: 0.65 + 0.25 * t, blue: 0.95, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: 1000, height: 4))
        }
        for (x, y, s) in [(160.0, 80.0, 1.0), (620, 120, 1.4), (880, 60, 0.8)] {
            ctx.setFillColor(c(0xffffff, 0.85))
            for (dx, r) in [(0.0, 30.0), (34, 40), (74, 28)] { ctx.fillEllipse(in: CGRect(x: x + dx * s, y: y - r * s / 2, width: r * 2 * s, height: r * 1.3 * s)) }
        }
        let hills = CGMutablePath(); hills.move(to: CGPoint(x: 0, y: 400))
        for i in 0...10 { hills.addQuadCurve(to: CGPoint(x: Double(i) * 100 + 100, y: 400), control: CGPoint(x: Double(i) * 100 + 50, y: 300 + Double(noise(i, 5, 1) % 60))) }
        hills.addLine(to: CGPoint(x: 1000, y: 420)); hills.addLine(to: CGPoint(x: 0, y: 420)); hills.closeSubpath()
        ctx.addPath(hills); ctx.setFillColor(c(0x5f9f6a)); ctx.fillPath()
        for i in 0..<14 {
            let x = Double(i) * 75 + Double(noise(i, 9, 2) % 30)
            ctx.setFillColor(c(0x2b6a34)); ctx.fillEllipse(in: CGRect(x: x, y: 330, width: 70, height: 80))
            ctx.setFillColor(c(0x5a3b1c)); ctx.fill(CGRect(x: x + 31, y: 395, width: 8, height: 22))
        }
        return ctx.makeImage()!
    }

    // MARK: vehicles (MZ Vehicle.png: index 0 boat, 1 ship, 3 airship)

    public static func makeVehicles() -> CGImage {
        let ctx = makeCanvas(576, 384)
        func cell(_ index: Int, _ row: Int, _ p: Int) -> CGRect { CGRect(x: ((index % 4) * 3 + p) * 48, y: ((index / 4) * 4 + row) * 48, width: 48, height: 48) }
        for (row, dir) in [2, 4, 6, 8].enumerated() { for p in 0..<3 {
            let bob = CGFloat(p == 1 ? 0 : 1)
            // Boat
            var r = cell(0, row, p)
            ctx.setFillColor(c(0x8a5a30))
            if dir == 4 || dir == 6 {
                let h = CGMutablePath(); h.addLines(between: [CGPoint(x: r.minX + 4, y: r.minY + 26 + bob), CGPoint(x: r.maxX - 4, y: r.minY + 26 + bob), CGPoint(x: r.maxX - 10, y: r.minY + 38 + bob), CGPoint(x: r.minX + 10, y: r.minY + 38 + bob)]); h.closeSubpath()
                ctx.addPath(h); ctx.fillPath()
            } else { ctx.fillEllipse(in: CGRect(x: r.minX + 12, y: r.minY + 10 + bob, width: 24, height: 34)) }
            ctx.setFillColor(c(0xc08d55)); ctx.fill(CGRect(x: r.minX + 16, y: r.minY + 24 + bob, width: 16, height: 4))
            // Ship
            r = cell(1, row, p)
            ctx.setFillColor(c(0x6b4423))
            let hull = CGMutablePath()
            if dir == 4 || dir == 6 { hull.addLines(between: [CGPoint(x: r.minX + 1, y: r.minY + 30 + bob), CGPoint(x: r.maxX - 1, y: r.minY + 30 + bob), CGPoint(x: r.maxX - 8, y: r.minY + 44 + bob), CGPoint(x: r.minX + 8, y: r.minY + 44 + bob)]) }
            else { hull.addLines(between: [CGPoint(x: r.minX + 10, y: r.minY + 26 + bob), CGPoint(x: r.maxX - 10, y: r.minY + 26 + bob), CGPoint(x: r.midX + 6, y: r.maxY - 1 + bob), CGPoint(x: r.midX - 6, y: r.maxY - 1 + bob)]) }
            hull.closeSubpath(); ctx.addPath(hull); ctx.fillPath()
            ctx.setFillColor(c(0x4a2f17)); ctx.fill(CGRect(x: r.midX - 1.5, y: r.minY + 2, width: 3, height: 30))
            ctx.setFillColor(c(0xf4f1e8)); ctx.fill(CGRect(x: r.midX - (dir == 4 || dir == 6 ? 12 : 16), y: r.minY + 4, width: dir == 4 || dir == 6 ? 24 : 32, height: 20))
            ctx.setFillColor(c(0xa53a3a)); ctx.fill(CGRect(x: r.midX - 4, y: r.minY + 2, width: 8, height: 4))
            // Airship (index 3)
            r = cell(3, row, p)
            ctx.setFillColor(c(0xd9a03a)); ctx.fillEllipse(in: CGRect(x: r.minX + 2, y: r.minY + 2 + bob, width: 44, height: 24))
            ctx.setStrokeColor(c(0x8a5a30)); ctx.setLineWidth(2); ctx.strokeEllipse(in: CGRect(x: r.minX + 2, y: r.minY + 2 + bob, width: 44, height: 24))
            ctx.setFillColor(c(0x6b4423)); ctx.fill(CGRect(x: r.minX + 14, y: r.minY + 32 + bob, width: 20, height: 9))
            ctx.setStrokeColor(c(0x4a2f17)); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: r.minX + 14, y: r.minY + 32 + bob)); ctx.addLine(to: CGPoint(x: r.minX + 10, y: r.minY + 24 + bob))
            ctx.move(to: CGPoint(x: r.minX + 34, y: r.minY + 32 + bob)); ctx.addLine(to: CGPoint(x: r.minX + 38, y: r.minY + 24 + bob)); ctx.strokePath()
            if p != 1 { ctx.setFillColor(c(0xc8d0dc)); ctx.fill(CGRect(x: dir == 4 ? r.maxX - 6 : r.minX + 2, y: r.minY + 33 + bob, width: 4, height: 8)) }
        } }
        return ctx.makeImage()!
    }

    // MARK: pictures

    public static func makeBanner(_ title: String) -> CGImage {
        let ctx = makeCanvas(520, 150)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 4, y: 4, width: 512, height: 142), cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.setFillColor(c(0x5a2e14, 0.92)); ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: CGRect(x: 12, y: 12, width: 496, height: 126), cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setStrokeColor(c(0xe0b44c)); ctx.setLineWidth(3); ctx.strokePath()
        // Batik-like kawung dots along the border.
        for x in stride(from: 30.0, to: 500, by: 24) { for y in [22.0, 120] {
            ctx.setFillColor(c(0xe0b44c, 0.8)); ctx.fillEllipse(in: CGRect(x: x - 5, y: y, width: 10, height: 6)); ctx.fillEllipse(in: CGRect(x: x - 3, y: y - 2, width: 6, height: 10))
        } }
        NSAttributedStringShim.draw(title, in: ctx, at: CGPoint(x: 0, y: 46), size: 46, color: c(0xfff3d0), centeredIn: 520)
        return ctx.makeImage()!
    }

    // MARK: tileset extras

    public static func drawExtraA2(_ ctx: CGContext) {
        for (k, g) in extraA2 { drawAutotile(ctx, (k % 8) * 96, (k / 8) * 144, g) }
    }

    public static func drawExtraA5(_ ctx: CGContext) {
        func at(_ i: Int) -> CGRect { CGRect(x: (i % 8) * 48, y: (i / 8) * 48, width: 48, height: 48) }
        let cr = at(a5Counter)
        ctx.setFillColor(c(0x8a5a30)); ctx.fill(cr)
        ctx.setFillColor(c(0xc08d55)); ctx.fill(CGRect(x: cr.minX, y: cr.minY, width: 48, height: 18))
        ctx.setFillColor(c(0x5a3b1c)); ctx.fill(CGRect(x: cr.minX, y: cr.minY + 18, width: 48, height: 2))
        let lv = at(a5Lava)
        ctx.setFillColor(c(0xb83a1a)); ctx.fill(lv)
        for i in 0..<6 { ctx.setFillColor(c(0xf2a03a)); ctx.fillEllipse(in: CGRect(x: lv.minX + Double(noise(i, 1, 9) % 40), y: lv.minY + Double(noise(i, 2, 9) % 40), width: 8, height: 6)) }
    }

    public static func drawExtraB(_ ctx: CGContext) {
        func rect(_ r: CGRect, _ col: UInt32) { ctx.setFillColor(c(col)); ctx.fill(r) }
        let mt = bRect(bMountain)
        let p = CGMutablePath(); p.addLines(between: [CGPoint(x: mt.minX + 2, y: mt.maxY - 2), CGPoint(x: mt.midX, y: mt.minY + 4), CGPoint(x: mt.maxX - 2, y: mt.maxY - 2)]); p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(c(0x7c6a4e)); ctx.fillPath()
        let snow = CGMutablePath(); snow.addLines(between: [CGPoint(x: mt.midX - 9, y: mt.minY + 18), CGPoint(x: mt.midX, y: mt.minY + 4), CGPoint(x: mt.midX + 9, y: mt.minY + 18)]); snow.closeSubpath()
        ctx.addPath(snow); ctx.setFillColor(c(0xf4f4f8)); ctx.fillPath()
        let pn = bRect(bPine)
        for (i, w) in [36.0, 28, 18].enumerated() {
            let t = CGMutablePath(); let y = pn.minY + 30 - Double(i) * 11
            t.addLines(between: [CGPoint(x: pn.midX - w / 2, y: y + 12), CGPoint(x: pn.midX, y: y - 6), CGPoint(x: pn.midX + w / 2, y: y + 12)]); t.closeSubpath()
            ctx.addPath(t); ctx.setFillColor(c(0x1f5a2b)); ctx.fillPath()
        }
        rect(CGRect(x: pn.midX - 3, y: pn.minY + 40, width: 6, height: 7), 0x6b4423)
        let sh = bRect(bShrine)
        rect(CGRect(x: sh.minX + 6, y: sh.minY + 6, width: 36, height: 6), 0xa53a3a)
        rect(CGRect(x: sh.minX + 10, y: sh.minY + 12, width: 4, height: 34), 0xa53a3a); rect(CGRect(x: sh.minX + 34, y: sh.minY + 12, width: 4, height: 34), 0xa53a3a)
        rect(CGRect(x: sh.minX + 8, y: sh.minY + 18, width: 32, height: 4), 0xa53a3a)
        let cf = bRect(bCampfire)
        rect(CGRect(x: cf.minX + 10, y: cf.minY + 36, width: 28, height: 5), 0x6b4423)
        ctx.setFillColor(c(0xe8602a)); ctx.fillEllipse(in: CGRect(x: cf.minX + 14, y: cf.minY + 16, width: 20, height: 24))
        ctx.setFillColor(c(0xffd04a)); ctx.fillEllipse(in: CGRect(x: cf.minX + 19, y: cf.minY + 26, width: 10, height: 12))
        let dk = bRect(bDock)
        for x in stride(from: 0.0, to: 48, by: 12) { rect(CGRect(x: dk.minX + x, y: dk.minY + 4, width: 11, height: 40), 0xa0703f) }
        rect(CGRect(x: dk.minX, y: dk.minY + 4, width: 48, height: 2), 0x6e4a26)
    }
}

/// Text drawing into a y-down CGContext via CoreText (no AppKit dependency in LakonRender).
import CoreText
enum NSAttributedStringShim {
    @discardableResult
    static func draw(_ s: String, in ctx: CGContext, at p: CGPoint, size: CGFloat, color: CGColor, centeredIn width: CGFloat? = nil) -> CGFloat {
        let font = CTFontCreateWithName("Avenir Next Bold" as CFString, size, nil)
        let attr = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color])
        let line = CTLineCreateWithAttributedString(attr)
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: (width.map { ($0 - w) / 2 } ?? 0) + p.x, y: p.y + size)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return w
    }
}
