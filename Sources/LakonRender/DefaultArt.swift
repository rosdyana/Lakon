import CoreGraphics
import Foundation
import LakonCore

/// Procedurally drawn starter art in MZ's sheet layouts (A2 autotiles, A5, B objects, 12x8 character sheets).
/// MZ's own RTP graphics are licensed to MZ owners, so Lakon ships none of them; drop MZ-format PNGs
/// into img/ to use your own.
public enum DefaultArt {
    // MARK: palette
    static func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    /// Deterministic hash noise so textures look the same every generation.
    static func noise(_ x: Int, _ y: Int, _ seed: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed &* 2147483647)
        h = (h ^ (h >> 13)) &* 1274126177
        return Int(h ^ (h >> 16)) & 0xff
    }

    struct Ground {
        var base: UInt32, dark: UInt32, light: UInt32, edge: UInt32
        var overlay = false
        var pattern: Pattern = .speckle
        enum Pattern { case speckle, planks, tiles, waves, leaves, flowers }
    }

    static func fillTexture(_ ctx: CGContext, _ r: CGRect, _ g: Ground) {
        ctx.setFillColor(c(g.base)); ctx.fill(r)
        let x0 = Int(r.minX), y0 = Int(r.minY)
        switch g.pattern {
        case .speckle, .leaves:
            for y in stride(from: y0, to: Int(r.maxY), by: 4) { for x in stride(from: x0, to: Int(r.maxX), by: 4) {
                let n = noise(x / 4, y / 4, Int(g.base))
                if n < 40 { ctx.setFillColor(c(g.dark)); ctx.fill(CGRect(x: x, y: y, width: 4, height: g.pattern == .leaves ? 4 : 2)) }
                else if n > 225 { ctx.setFillColor(c(g.light)); ctx.fill(CGRect(x: x, y: y, width: 2, height: 2)) }
            } }
        case .flowers:
            for y in stride(from: y0, to: Int(r.maxY), by: 12) { for x in stride(from: x0, to: Int(r.maxX), by: 12) {
                let n = noise(x, y, 7)
                let col: UInt32 = [0xf2d24b, 0xe8607a, 0xffffff, 0x8f7ae8][n % 4]
                let ox = CGFloat(x + n % 6), oy = CGFloat(y + (n / 7) % 6)
                ctx.setFillColor(c(col)); ctx.fill(CGRect(x: ox, y: oy, width: 4, height: 4))
                ctx.setFillColor(c(0xfff3a0)); ctx.fill(CGRect(x: ox + 1, y: oy + 1, width: 2, height: 2))
            } }
        case .planks:
            for y in stride(from: y0, to: Int(r.maxY), by: 12) {
                ctx.setFillColor(c(g.dark)); ctx.fill(CGRect(x: CGFloat(x0), y: CGFloat(y + 11), width: r.width, height: 1))
                let off = (y / 12) % 2 == 0 ? 0 : 24
                for x in stride(from: x0 + off, to: Int(r.maxX), by: 48) { ctx.fill(CGRect(x: x, y: y, width: 1, height: 12)) }
            }
        case .tiles:
            for y in stride(from: y0, to: Int(r.maxY), by: 24) { for x in stride(from: x0, to: Int(r.maxX), by: 24) {
                ctx.setFillColor(c(g.light)); ctx.fill(CGRect(x: x, y: y, width: 23, height: 1))
                ctx.setFillColor(c(g.dark)); ctx.fill(CGRect(x: x, y: y + 23, width: 24, height: 1)); ctx.fill(CGRect(x: x + 23, y: y, width: 1, height: 24))
            } }
        case .waves:
            for y in stride(from: y0, to: Int(r.maxY), by: 8) { for x in stride(from: x0, to: Int(r.maxX), by: 8) {
                if noise(x / 8, y / 8, 3) < 50 { ctx.setFillColor(c(g.light)); ctx.fill(CGRect(x: x, y: y + 3, width: 6, height: 2)) }
            } }
        }
    }

    /// One A2 kind = 96x144 block: preview tile (0,0), inner-corner tile (48,0), 2x2 edged area (0,48).
    static func drawAutotile(_ ctx: CGContext, _ ox: Int, _ oy: Int, _ g: Ground) {
        func shape(_ r: CGRect) {
            let inset: CGFloat = g.overlay ? 3 : 0
            let body = r.insetBy(dx: inset, dy: inset)
            ctx.saveGState()
            // Ground kinds stay opaque to the cell edge (nothing is drawn beneath layer 0); overlays get rounded, transparent corners.
            if g.overlay { ctx.addPath(CGPath(roundedRect: body, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.clip() }
            fillTexture(ctx, r, g)
            ctx.restoreGState()
            ctx.setStrokeColor(c(g.edge)); ctx.setLineWidth(4)
            ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.strokePath()
        }
        shape(CGRect(x: ox, y: oy, width: 48, height: 48))
        shape(CGRect(x: ox, y: oy + 48, width: 96, height: 96))
        // Inner corners: full fill, notch of edge (or transparency for overlays) at each corner.
        let inner = CGRect(x: ox + 48, y: oy, width: 48, height: 48)
        fillTexture(ctx, inner, g)
        let n: CGFloat = g.overlay ? 7 : 6
        for (cx, cy) in [(inner.minX, inner.minY), (inner.maxX - n, inner.minY), (inner.minX, inner.maxY - n), (inner.maxX - n, inner.maxY - n)] {
            let r = CGRect(x: cx, y: cy, width: n, height: n)
            if g.overlay { ctx.clear(r) }
            ctx.setFillColor(c(g.edge)); ctx.fill(r.insetBy(dx: g.overlay ? 2 : 1, dy: g.overlay ? 2 : 1))
        }
    }

    // A2 kinds (index within A2). tileId = TileID.A2 + index * 48.
    public static let grass = 0, dirt = 1, sand = 2, water = 3, hedge = 4, flowers = 5, woodFloor = 8, stoneFloor = 9, carpet = 10
    static let a2Kinds: [Int: Ground] = [
        grass: Ground(base: 0x5fa548, dark: 0x4b8a3a, light: 0x86c45f, edge: 0x3f7a31, pattern: .speckle),
        dirt: Ground(base: 0xb48a58, dark: 0x9a7246, light: 0xcda575, edge: 0x7c5a36),
        sand: Ground(base: 0xe2cf8f, dark: 0xcdb875, light: 0xf3e3b0, edge: 0xb79e5c),
        water: Ground(base: 0x3d7fc4, dark: 0x2f68a6, light: 0x8ec2ee, edge: 0xd9ecf6, pattern: .waves),
        hedge: Ground(base: 0x2f7a3a, dark: 0x215a2a, light: 0x4fa257, edge: 0x173f1e, overlay: true, pattern: .leaves),
        flowers: Ground(base: 0x58a043, dark: 0x4b8a3a, light: 0x86c45f, edge: 0x3f7a31, overlay: true, pattern: .flowers),
        woodFloor: Ground(base: 0xa0703f, dark: 0x6e4a26, light: 0xc08d55, edge: 0x5a3b1c, pattern: .planks),
        stoneFloor: Ground(base: 0x9a9aa4, dark: 0x6f6f7a, light: 0xc4c4cc, edge: 0x5c5c66, pattern: .tiles),
        carpet: Ground(base: 0xa53a3a, dark: 0x842c2c, light: 0xc95a50, edge: 0xe0b44c),
    ]
    public static func a2(_ index: Int) -> Int { TileID.A2 + index * 48 }

    public static func makeA2() -> CGImage {
        let ctx = makeCanvas(768, 576)
        for (k, g) in a2Kinds { drawAutotile(ctx, (k % 8) * 96, (k / 8) * 144, g) }
        drawExtraA2(ctx)
        return ctx.makeImage()!
    }

    // MARK: A5 (8 x 16 normal tiles). tileId = TileID.A5 + index.
    public static let a5Void = 0, a5Wall = 1, a5WallDark = 2, a5RoofRed = 3, a5RoofBlue = 4, a5Window = 5, a5StoneWall = 6, a5Cobble = 7
    public static func a5(_ i: Int) -> Int { TileID.A5 + i }

    public static func makeA5() -> CGImage {
        let ctx = makeCanvas(384, 768)
        func at(_ i: Int) -> CGRect { CGRect(x: (i % 8) * 48, y: (i / 8) * 48, width: 48, height: 48) }
        ctx.setFillColor(c(0x101018)); ctx.fill(at(a5Void))
        func bricks(_ r: CGRect, _ base: UInt32, _ mortar: UInt32) {
            ctx.setFillColor(c(base)); ctx.fill(r)
            ctx.setFillColor(c(mortar))
            for row in 0..<4 {
                let y = r.minY + CGFloat(row * 12)
                ctx.fill(CGRect(x: r.minX, y: y + 11, width: 48, height: 1))
                for x in stride(from: row % 2 == 0 ? 0 : 12, to: 48, by: 24) { ctx.fill(CGRect(x: r.minX + CGFloat(x), y: y, width: 1, height: 12)) }
            }
        }
        bricks(at(a5Wall), 0xe9dcc0, 0xbfae8c)
        bricks(at(a5WallDark), 0x8c6a4a, 0x5e4430)
        bricks(at(a5StoneWall), 0x8d8f99, 0x5f6170)
        for (i, base, dark) in [(a5RoofRed, UInt32(0xb5443a), UInt32(0x7d2a24)), (a5RoofBlue, 0x3f5fa8, 0x293f73)] {
            let r = at(i)
            ctx.setFillColor(c(base)); ctx.fill(r)
            ctx.setFillColor(c(dark))
            for row in 0..<4 {
                let y = r.minY + CGFloat(row * 12)
                ctx.fill(CGRect(x: r.minX, y: y + 10, width: 48, height: 2))
                for x in stride(from: row % 2 == 0 ? 6 : 18, to: 48, by: 24) { ctx.fill(CGRect(x: r.minX + CGFloat(x), y: y + 4, width: 2, height: 6)) }
            }
        }
        let w = at(a5Window)
        bricks(w, 0xe9dcc0, 0xbfae8c)
        ctx.setFillColor(c(0x5a3b1c)); ctx.fill(CGRect(x: w.minX + 10, y: w.minY + 8, width: 28, height: 28))
        ctx.setFillColor(c(0x9fd4f0)); ctx.fill(CGRect(x: w.minX + 13, y: w.minY + 11, width: 22, height: 22))
        ctx.setFillColor(c(0x5a3b1c)); ctx.fill(CGRect(x: w.minX + 23, y: w.minY + 11, width: 2, height: 22)); ctx.fill(CGRect(x: w.minX + 13, y: w.minY + 21, width: 22, height: 2))
        let cb = at(a5Cobble)
        ctx.setFillColor(c(0x7d7a74)); ctx.fill(cb)
        for y in stride(from: 0, to: 48, by: 12) { for x in stride(from: (y / 12) % 2 * 6, to: 48, by: 12) {
            ctx.setFillColor(c(noise(x, y, 5) % 2 == 0 ? 0xa9a59c : 0x9b978f))
            ctx.addPath(CGPath(roundedRect: CGRect(x: cb.minX + CGFloat(x) + 1, y: cb.minY + CGFloat(y) + 1, width: 10, height: 10), cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.fillPath()
        } }
        drawExtraA5(ctx)
        return ctx.makeImage()!
    }

    // MARK: B objects (16 x 16 tiles, left 8 columns = ids 0..127, right 8 = 128..255). Tile 0 must stay empty.
    public static let bTreeTop = 1, bTreeTrunk = 9, bRock = 2, bBush = 3, bSign = 4, bFence = 5, bWell = 6, bBarrel = 7
    public static let bCrate = 10, bDoor = 11, bBed = 12, bTable = 13, bPot = 14, bShelf = 15, bLampTop = 16, bLampPost = 24
    public static let bStairs = 17, bChair = 18, bPlant = 19, bRug = 20

    static func bRect(_ id: Int) -> CGRect {
        CGRect(x: ((id / 128) % 2 * 8 + id % 8) * 48, y: ((id % 256) / 8 % 16) * 48, width: 48, height: 48)
    }

    public static func makeB() -> CGImage {
        let ctx = makeCanvas(768, 768)
        func ellipse(_ r: CGRect, _ col: UInt32) { ctx.setFillColor(c(col)); ctx.fillEllipse(in: r) }
        func rect(_ r: CGRect, _ col: UInt32) { ctx.setFillColor(c(col)); ctx.fill(r) }
        // Tree (2 tiles): canopy on top tile + overlap into trunk tile.
        let tt = bRect(bTreeTop), tk = bRect(bTreeTrunk)
        ellipse(CGRect(x: tt.minX + 2, y: tt.minY + 6, width: 44, height: 42), 0x1f5a2b)
        ellipse(CGRect(x: tt.minX + 6, y: tt.minY + 4, width: 36, height: 34), 0x2f7d3b)
        ellipse(CGRect(x: tt.minX + 12, y: tt.minY + 8, width: 16, height: 12), 0x4fa257)
        ellipse(CGRect(x: tk.minX + 2, y: tk.minY - 4, width: 44, height: 22), 0x1f5a2b)
        ellipse(CGRect(x: tk.minX + 6, y: tk.minY - 6, width: 36, height: 20), 0x2f7d3b)
        rect(CGRect(x: tk.minX + 19, y: tk.minY + 14, width: 10, height: 28), 0x6b4423)
        rect(CGRect(x: tk.minX + 19, y: tk.minY + 14, width: 3, height: 28), 0x8a5a30)
        ellipse(CGRect(x: tk.minX + 12, y: tk.minY + 38, width: 24, height: 8), 0x2b4a22)
        // Rock
        let rk = bRect(bRock)
        ellipse(CGRect(x: rk.minX + 6, y: rk.minY + 14, width: 36, height: 28), 0x5f6170)
        ellipse(CGRect(x: rk.minX + 9, y: rk.minY + 15, width: 28, height: 20), 0x8d8f99)
        ellipse(CGRect(x: rk.minX + 14, y: rk.minY + 18, width: 10, height: 6), 0xb8bac4)
        // Bush
        let bu = bRect(bBush)
        ellipse(CGRect(x: bu.minX + 4, y: bu.minY + 12, width: 40, height: 32), 0x1f5a2b)
        ellipse(CGRect(x: bu.minX + 8, y: bu.minY + 12, width: 32, height: 26), 0x3a8a45)
        // Sign
        let sg = bRect(bSign)
        rect(CGRect(x: sg.minX + 21, y: sg.minY + 24, width: 6, height: 20), 0x6b4423)
        rect(CGRect(x: sg.minX + 8, y: sg.minY + 8, width: 32, height: 20), 0x8a5a30)
        rect(CGRect(x: sg.minX + 10, y: sg.minY + 10, width: 28, height: 16), 0xc08d55)
        for i in 0..<3 { rect(CGRect(x: sg.minX + 13, y: sg.minY + 13 + CGFloat(i * 4), width: 22 - CGFloat(i * 6), height: 2), 0x6b4423) }
        // Fence
        let fe = bRect(bFence)
        rect(CGRect(x: fe.minX, y: fe.minY + 18, width: 48, height: 5), 0x8a5a30)
        rect(CGRect(x: fe.minX, y: fe.minY + 32, width: 48, height: 5), 0x8a5a30)
        for x in [6, 38] { rect(CGRect(x: fe.minX + CGFloat(x), y: fe.minY + 10, width: 6, height: 34), 0x6b4423) }
        // Well
        let we = bRect(bWell)
        ellipse(CGRect(x: we.minX + 4, y: we.minY + 14, width: 40, height: 30), 0x5f6170)
        ellipse(CGRect(x: we.minX + 10, y: we.minY + 18, width: 28, height: 18), 0x1d3550)
        rect(CGRect(x: we.minX + 6, y: we.minY + 2, width: 4, height: 24), 0x6b4423); rect(CGRect(x: we.minX + 38, y: we.minY + 2, width: 4, height: 24), 0x6b4423)
        rect(CGRect(x: we.minX + 4, y: we.minY + 2, width: 40, height: 5), 0xa53a3a)
        // Barrel
        let ba = bRect(bBarrel)
        ctx.addPath(CGPath(roundedRect: CGRect(x: ba.minX + 10, y: ba.minY + 8, width: 28, height: 36), cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.setFillColor(c(0x8a5a30)); ctx.fillPath()
        for y in [14, 34] { rect(CGRect(x: ba.minX + 10, y: ba.minY + CGFloat(y), width: 28, height: 3), 0x4a4a52) }
        // Crate
        let cr = bRect(bCrate)
        rect(CGRect(x: cr.minX + 6, y: cr.minY + 10, width: 36, height: 34), 0x6b4423)
        rect(CGRect(x: cr.minX + 9, y: cr.minY + 13, width: 30, height: 28), 0xb07a45)
        ctx.setStrokeColor(c(0x6b4423)); ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: cr.minX + 9, y: cr.minY + 13)); ctx.addLine(to: CGPoint(x: cr.minX + 39, y: cr.minY + 41)); ctx.strokePath()
        // Door
        let dr = bRect(bDoor)
        rect(CGRect(x: dr.minX + 6, y: dr.minY + 2, width: 36, height: 46), 0x4a2f17)
        rect(CGRect(x: dr.minX + 9, y: dr.minY + 5, width: 30, height: 43), 0x8a5a30)
        rect(CGRect(x: dr.minX + 23, y: dr.minY + 5, width: 2, height: 43), 0x6b4423)
        ellipse(CGRect(x: dr.minX + 30, y: dr.minY + 26, width: 4, height: 4), 0xe0b44c)
        // Bed
        let bd = bRect(bBed)
        rect(CGRect(x: bd.minX + 6, y: bd.minY + 2, width: 36, height: 44), 0x6b4423)
        rect(CGRect(x: bd.minX + 9, y: bd.minY + 5, width: 30, height: 12), 0xf4f1e8)
        rect(CGRect(x: bd.minX + 9, y: bd.minY + 17, width: 30, height: 26), 0x3f5fa8)
        rect(CGRect(x: bd.minX + 9, y: bd.minY + 17, width: 30, height: 4), 0x6b88cc)
        // Table
        let tb = bRect(bTable)
        rect(CGRect(x: tb.minX + 4, y: tb.minY + 12, width: 40, height: 22), 0x8a5a30)
        rect(CGRect(x: tb.minX + 4, y: tb.minY + 12, width: 40, height: 4), 0xc08d55)
        for x in [6, 38] { rect(CGRect(x: tb.minX + CGFloat(x), y: tb.minY + 34, width: 4, height: 12), 0x6b4423) }
        // Pot
        let pt = bRect(bPot)
        ellipse(CGRect(x: pt.minX + 10, y: pt.minY + 14, width: 28, height: 30), 0xa8623a)
        rect(CGRect(x: pt.minX + 16, y: pt.minY + 10, width: 16, height: 8), 0xa8623a)
        rect(CGRect(x: pt.minX + 14, y: pt.minY + 8, width: 20, height: 4), 0x7a4426)
        // Shelf
        let sh = bRect(bShelf)
        rect(CGRect(x: sh.minX + 2, y: sh.minY + 2, width: 44, height: 44), 0x5a3b1c)
        for (i, y) in [6, 20, 34].enumerated() {
            rect(CGRect(x: sh.minX + 5, y: sh.minY + CGFloat(y), width: 38, height: 10), 0x3a2410)
            for b in 0..<6 {
                let col: [UInt32] = [0xa53a3a, 0x3f5fa8, 0xe0b44c, 0x2f7d3b]
                rect(CGRect(x: sh.minX + 6 + CGFloat(b * 6), y: sh.minY + CGFloat(y + 1), width: 5, height: 9), col[(b + i) % 4])
            }
        }
        // Lamp post (2 tiles)
        let lt = bRect(bLampTop), lp = bRect(bLampPost)
        rect(CGRect(x: lt.minX + 14, y: lt.minY + 18, width: 20, height: 24), 0x2b2b33)
        rect(CGRect(x: lt.minX + 17, y: lt.minY + 21, width: 14, height: 18), 0xffe28a)
        rect(CGRect(x: lt.minX + 12, y: lt.minY + 14, width: 24, height: 5), 0x2b2b33)
        rect(CGRect(x: lt.minX + 21, y: lt.minY + 42, width: 6, height: 6), 0x2b2b33)
        rect(CGRect(x: lp.minX + 21, y: lp.minY, width: 6, height: 40), 0x2b2b33)
        rect(CGRect(x: lp.minX + 15, y: lp.minY + 38, width: 18, height: 8), 0x2b2b33)
        // Stairs (down)
        let st = bRect(bStairs)
        for i in 0..<5 { rect(CGRect(x: st.minX + 4, y: st.minY + 4 + CGFloat(i * 8), width: 40, height: 8), [0x9a9aa4, 0x7f7f8a, 0x66666f, 0x4c4c55, 0x34343b][i]) }
        // Chair
        let ch = bRect(bChair)
        rect(CGRect(x: ch.minX + 14, y: ch.minY + 6, width: 20, height: 18), 0x8a5a30)
        rect(CGRect(x: ch.minX + 12, y: ch.minY + 24, width: 24, height: 8), 0xc08d55)
        for x in [13, 31] { rect(CGRect(x: ch.minX + CGFloat(x), y: ch.minY + 32, width: 4, height: 12), 0x6b4423) }
        // Potted plant
        let pl = bRect(bPlant)
        ellipse(CGRect(x: pl.minX + 8, y: pl.minY + 2, width: 32, height: 28), 0x2f7d3b)
        ellipse(CGRect(x: pl.minX + 14, y: pl.minY + 6, width: 12, height: 10), 0x4fa257)
        rect(CGRect(x: pl.minX + 14, y: pl.minY + 28, width: 20, height: 16), 0xa8623a)
        // Rug
        let rg = bRect(bRug)
        rect(rg.insetBy(dx: 2, dy: 8), 0x7a3a8a)
        rect(rg.insetBy(dx: 6, dy: 12), 0xa95cb8)
        drawExtraB(ctx)
        return ctx.makeImage()!
    }

    // MARK: characters (576 x 384 = 4x2 characters, each 3 patterns x 4 directions of 48x48)

    struct Look {
        var skin: UInt32 = 0xf1c79c
        var hair: UInt32
        var top: UInt32
        var bottom: UInt32
        var accent: UInt32 = 0xffffff
        var hat: UInt32? = nil
        var longHair = false
    }

    static func drawCharacter(_ ctx: CGContext, _ ox: CGFloat, _ oy: CGFloat, _ look: Look, dir: Int, pattern: Int) {
        func px(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ col: UInt32) {
            ctx.setFillColor(c(col)); ctx.fill(CGRect(x: ox + CGFloat(x * 2), y: oy + CGFloat(y * 2), width: CGFloat(w * 2), height: CGFloat(h * 2)))
        }
        let outline: UInt32 = 0x2a1f2e
        let step = pattern == 0 ? -1 : pattern == 2 ? 1 : 0
        let bob = pattern == 1 ? 0 : 1
        // shadow
        ctx.setFillColor(c(0x000000, 0.22)); ctx.fillEllipse(in: CGRect(x: ox + 12, y: oy + 40, width: 24, height: 6))
        // legs
        let lx = dir == 4 || dir == 6 ? 10 : 9
        px(lx, 17 + bob, 3, 5 - (step < 0 ? 1 : 0), look.bottom)
        px(lx + 3 + (dir == 2 || dir == 8 ? 0 : -1), 17 + bob, 3, 5 - (step > 0 ? 1 : 0), look.bottom)
        px(lx, 21 + bob - (step < 0 ? 1 : 0), 3, 1, outline)
        px(lx + 3 + (dir == 2 || dir == 8 ? 0 : -1), 21 + bob - (step > 0 ? 1 : 0), 3, 1, outline)
        // body
        px(7, 11 + bob, 10, 7, outline)
        px(8, 12 + bob, 8, 6, look.top)
        px(8, 16 + bob, 8, 1, look.accent)
        // arms
        if dir == 2 || dir == 8 {
            px(6, 12 + bob + step, 2, 5, look.top); px(6, 16 + bob + step, 2, 1, look.skin)
            px(16, 12 + bob - step, 2, 5, look.top); px(16, 16 + bob - step, 2, 1, look.skin)
        } else {
            let ax = dir == 4 ? 11 + step : 11 - step
            px(ax, 12 + bob, 2, 5, look.top); px(ax, 16 + bob, 2, 1, look.skin)
        }
        // head
        px(6, 2 + bob, 12, 10, outline)
        px(7, 3 + bob, 10, 8, look.skin)
        // hair
        px(7, 2 + bob, 10, 3, look.hair)
        switch dir {
        case 8: px(7, 3 + bob, 10, 8, look.hair)
        case 4: px(12, 3 + bob, 5, 6, look.hair); px(7, 3 + bob, 2, 2, look.hair)
        case 6: px(7, 3 + bob, 5, 6, look.hair); px(15, 3 + bob, 2, 2, look.hair)
        default: px(7, 3 + bob, 2, 4, look.hair); px(15, 3 + bob, 2, 4, look.hair)
        }
        if look.longHair && dir != 2 { px(7, 8 + bob, 10, 4, look.hair) }
        if look.longHair && dir == 2 { px(6, 6 + bob, 2, 6, look.hair); px(16, 6 + bob, 2, 6, look.hair) }
        // eyes
        switch dir {
        case 2: px(9, 7 + bob, 1, 2, outline); px(14, 7 + bob, 1, 2, outline)
        case 4: px(8, 7 + bob, 1, 2, outline)
        case 6: px(15, 7 + bob, 1, 2, outline)
        default: break
        }
        if let hat = look.hat { px(5, 1 + bob, 14, 2, hat); px(7, 0 + bob, 10, 2, hat) }
    }

    static func makeCharacterSheet(_ looks: [Look]) -> CGImage {
        let ctx = makeCanvas(576, 384)
        for (i, look) in looks.prefix(8).enumerated() {
            let bx = (i % 4) * 3, by = (i / 4) * 4
            for (row, dir) in [2, 4, 6, 8].enumerated() { for p in 0..<3 {
                drawCharacter(ctx, CGFloat((bx + p) * 48), CGFloat((by + row) * 48), look, dir: dir, pattern: p)
            } }
        }
        return ctx.makeImage()!
    }

    public static func makeActors() -> CGImage {
        makeCharacterSheet([
            Look(hair: 0x2a1f2e, top: 0x3f5fa8, bottom: 0x3a2f2a, accent: 0xe0b44c),            // hero
            Look(hair: 0xb5443a, top: 0x2f7d3b, bottom: 0x5a3b1c, accent: 0xf4f1e8, longHair: true),
            Look(hair: 0xe0b44c, top: 0x7a3a8a, bottom: 0x2b2b33, accent: 0xe0b44c),
            Look(skin: 0xc68b5e, hair: 0x101018, top: 0xa53a3a, bottom: 0x2b2b33, accent: 0xe0b44c, longHair: true),
            Look(hair: 0x6b4423, top: 0xb07a45, bottom: 0x3a2f2a),
            Look(hair: 0xf4f1e8, top: 0x5f6170, bottom: 0x2b2b33),
            Look(skin: 0xc68b5e, hair: 0x3a2410, top: 0x3f8f8a, bottom: 0x3a2f2a),
            Look(hair: 0x8f7ae8, top: 0xf4f1e8, bottom: 0x3f5fa8, longHair: true),
        ])
    }

    public static func makePeople() -> CGImage {
        makeCharacterSheet([
            Look(hair: 0xd8d8d8, top: 0x6b4423, bottom: 0x3a2f2a, accent: 0xa53a3a, hat: 0x8a5a30),  // elder
            Look(hair: 0x6b4423, top: 0xe8607a, bottom: 0x7a3a8a, longHair: true),                     // villager
            Look(hair: 0x2a1f2e, top: 0x8d8f99, bottom: 0x2b2b33, accent: 0x5f6170, hat: 0x5f6170),  // guard
            Look(skin: 0xc68b5e, hair: 0x101018, top: 0xe0b44c, bottom: 0x5a3b1c),                   // merchant
            Look(hair: 0xe0b44c, top: 0x86c45f, bottom: 0x3f5fa8),                                     // kid
            Look(hair: 0xb5443a, top: 0xf4f1e8, bottom: 0x3a2f2a, longHair: true),
            Look(skin: 0xc68b5e, hair: 0x3a2410, top: 0x3f5fa8, bottom: 0x2b2b33, hat: 0xa53a3a),
            Look(hair: 0x5f6170, top: 0x5a3b1c, bottom: 0x2b2b33),
        ])
    }

    /// "!" sheet: object characters (no 6px shift). Chest: rows = closed → opening → open (direction 2,4,6,8).
    public static func makeObjects() -> CGImage {
        let ctx = makeCanvas(576, 384)
        func chest(_ ox: CGFloat, _ oy: CGFloat, open: Int) {
            ctx.setFillColor(c(0x4a2f17)); ctx.fill(CGRect(x: ox + 8, y: oy + 18, width: 32, height: 26))
            ctx.setFillColor(c(0x8a5a30)); ctx.fill(CGRect(x: ox + 10, y: oy + 24, width: 28, height: 18))
            ctx.setFillColor(c(0xe0b44c)); ctx.fill(CGRect(x: ox + 8, y: oy + 30, width: 32, height: 3))
            let lidY = oy + 12 - CGFloat(open * 4)
            ctx.setFillColor(c(0x4a2f17)); ctx.fill(CGRect(x: ox + 8, y: lidY, width: 32, height: 12))
            ctx.setFillColor(c(0xa8703c)); ctx.fill(CGRect(x: ox + 10, y: lidY + 2, width: 28, height: 8))
            if open == 3 { ctx.setFillColor(c(0xffe28a)); ctx.fill(CGRect(x: ox + 12, y: oy + 19, width: 24, height: 4)) }
            else { ctx.setFillColor(c(0xe0b44c)); ctx.fill(CGRect(x: ox + 21, y: oy + 22, width: 6, height: 6)) }
        }
        func door(_ ox: CGFloat, _ oy: CGFloat, open: Int) {
            ctx.setFillColor(c(0x101018)); ctx.fill(CGRect(x: ox + 6, y: oy + 2, width: 36, height: 46))
            let w = CGFloat(30 - open * 9)
            ctx.setFillColor(c(0x8a5a30)); ctx.fill(CGRect(x: ox + 9, y: oy + 5, width: w, height: 43))
            ctx.setFillColor(c(0xe0b44c)); if w > 12 { ctx.fill(CGRect(x: ox + 9 + w - 6, y: oy + 26, width: 3, height: 3)) }
        }
        for row in 0..<4 { for p in 0..<3 {
            chest(CGFloat(p * 48), CGFloat(row * 48), open: row)
            door(CGFloat((3 + p) * 48), CGFloat(row * 48), open: row)
        } }
        return ctx.makeImage()!
    }

    /// Default tileset with MZ-style flags: low nibble = walking blocked per direction, 0x10 ☆, 0x40 bush,
    /// 0x80 counter, 0x100 damage floor, 0x200 boat blocked, 0x400 ship blocked, 0x800 airship can't land.
    /// Land tiles carry 0x600 (no boats/ships), like MZ's defaults.
    public static func tileset() -> Tileset {
        var t = Tileset(id: 1, name: "Lakon Field", names: ["", "Lakon_A2", "", "", "Lakon_A5", "Lakon_B", "", "", ""])
        for i in 0..<t.flags.count { t.flags[i] = 0x600 }
        func setKind(_ k: Int, _ f: Int) { for s in 0..<48 { t.flags[a2(k) + s] = f } }
        setKind(water, 0x80f)                 // boat + ship
        setKind(deepWater, 0xa0f)             // ship only
        setKind(hedge, 0x60f)
        setKind(tallGrass, 0x640)             // bush: lower body half-transparent, doubles encounter progress
        setKind(swamp, 0x700)                 // damage floor
        for i in [a5Void, a5Wall, a5WallDark, a5RoofRed, a5RoofBlue, a5Window, a5StoneWall] { t.flags[a5(i)] = 0x60f }
        t.flags[a5(a5Counter)] = 0x68f        // counter: talk across it
        t.flags[a5(a5Lava)] = 0x700
        for i in [bTreeTrunk, bRock, bBush, bSign, bWell, bBarrel, bCrate, bBed, bTable, bPot, bShelf, bLampPost, bPlant, bMountain, bPine, bTent, bCampfire] { t.flags[i] = 0x60f }
        for i in [bTreeTop, bLampTop] { t.flags[i] = 0x10 }
        t.flags[bFence] = 0x60f
        t.flags[0] = 0x10
        // Empty B cells are "no effect" so the layer below decides.
        for i in 1..<256 where t.flags[i] == 0x600 && ![bDoor, bStairs, bChair, bRug, bShrine, bDock].contains(i) { t.flags[i] = 0x10 }
        // Dock planks over water: walkable, and boats/ships can't pass.
        t.flags[bDock] = 0x600
        return t
    }

    public static func writeAll(to project: Project) throws {
        try writePNG(makeA2(), to: project.imageURL("tilesets", "Lakon_A2"))
        try writePNG(makeA5(), to: project.imageURL("tilesets", "Lakon_A5"))
        try writePNG(makeB(), to: project.imageURL("tilesets", "Lakon_B"))
        try writePNG(makeActors(), to: project.imageURL("characters", "Actor1"))
        try writePNG(makePeople(), to: project.imageURL("characters", "People1"))
        try writePNG(makeObjects(), to: project.imageURL("characters", "!Objects"))
        try writePNG(makeVehicles(), to: project.imageURL("characters", "Vehicle"))
        try writePNG(makeIconSet(), to: project.imageURL("system", "IconSet"))
        for n in ["Slime", "Bat", "Snake", "Forest_Spirit"] { try writePNG(makeEnemy(n), to: project.imageURL("enemies", n)) }
        try writePNG(makeBattleback1(), to: project.imageURL("battlebacks1", "Grassland"))
        try writePNG(makeBattleback2(), to: project.imageURL("battlebacks2", "Grassland"))
        try writePNG(makeBanner("Kampung Lakon"), to: project.imageURL("pictures", "Banner"))
        try writeBattleArt(to: project)
    }
}
