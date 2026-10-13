import CoreGraphics
import Foundation
import ImageIO
import LakonCore

public let tileSize = 48

public func loadPNG(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

public func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(dst, image, nil)
    if !CGImageDestinationFinalize(dst) { throw CocoaError(.fileWriteUnknown) }
}

/// Creates an RGBA context whose coordinate system is top-left origin, y down — like a canvas.
public func makeCanvas(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .none
    return ctx
}

extension CGContext {
    /// Draws an image upright into a y-down context.
    public func drawUpright(_ image: CGImage, in r: CGRect) {
        saveGState()
        translateBy(x: r.minX, y: r.maxY); scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        restoreGState()
    }
}

/// Holds the 9 tileset sheets and draws tile IDs, following rmmz_core.js Tilemap._addNormalTile/_addAutotile.
public final class TileRenderer {
    public let sheets: [CGImage?]
    private var cache: [Int64: CGImage] = [:]
    public var animationFrame = 0

    public init(sheets: [CGImage?]) { self.sheets = sheets }

    public convenience init(project: Project, tileset: Tileset) {
        self.init(sheets: tileset.tilesetNames.map { $0.isEmpty ? nil : loadPNG(project.imageURL("tilesets", $0)) })
    }

    private func piece(_ set: Int, _ sx: Int, _ sy: Int, _ w: Int, _ h: Int) -> CGImage? {
        let key = Int64(set) << 48 | Int64(sx) << 32 | Int64(sy) << 16 | Int64(w) << 8 | Int64(h)
        if let c = cache[key] { return c }
        guard set < sheets.count, let sheet = sheets[set],
              sx + w <= sheet.width, sy + h <= sheet.height,
              let img = sheet.cropping(to: CGRect(x: sx, y: sy, width: w, height: h)) else { return nil }
        cache[key] = img
        return img
    }

    /// Draws one tile at (dx, dy) in a y-down context. `scale` lets palettes draw at other sizes.
    public func draw(_ tileId: Int, in ctx: CGContext, x dx: CGFloat, y dy: CGFloat, size: CGFloat = 48) {
        guard tileId > 0, tileId < TileID.max else { return }
        let s = size / CGFloat(tileSize)
        for (set, sx, sy, w, h, ox, oy) in rects(tileId) {
            if let img = piece(set, sx, sy, w, h) {
                ctx.drawUpright(img, in: CGRect(x: dx + CGFloat(ox) * s, y: dy + CGFloat(oy) * s, width: CGFloat(w) * s, height: CGFloat(h) * s))
            }
        }
    }

    /// Source rectangles for a tile: (setNumber, sx, sy, w, h, offsetX, offsetY).
    public func rects(_ tileId: Int) -> [(Int, Int, Int, Int, Int, Int, Int)] {
        let w = tileSize, h = tileSize
        if !TileID.isAutotile(tileId) {
            let set = TileID.isA5(tileId) ? 4 : 5 + tileId / 256
            let sx = ((tileId / 128) % 2 * 8 + tileId % 8) * w
            let sy = ((tileId % 256) / 8 % 16) * h
            return [(set, sx, sy, w, h, 0, 0)]
        }
        let kind = TileID.kind(tileId), shape = TileID.shape(tileId)
        let tx = kind % 8, ty = kind / 8
        var set = 0, bx = 0, by = 0
        var table = TileID.floorTable
        if TileID.isA1(tileId) {
            let water = [0, 1, 2, 1][animationFrame % 4]
            switch kind {
            case 0: bx = water * 2; by = 0
            case 1: bx = water * 2; by = 3
            case 2: bx = 6; by = 0
            case 3: bx = 6; by = 3
            default:
                bx = tx / 4 * 8
                by = ty * 6 + (tx / 2) % 2 * 3
                if kind % 2 == 0 { bx += water * 2 }
                else { bx += 6; table = TileID.waterfallTable; by += animationFrame % 3 }
            }
        } else if TileID.isA2(tileId) {
            set = 1; bx = tx * 2; by = (ty - 2) * 3
        } else if TileID.isA3(tileId) {
            set = 2; bx = tx * 2; by = (ty - 6) * 2; table = TileID.wallTable
        } else {
            set = 3; bx = tx * 2
            by = Int(floor(Double(ty - 10) * 2.5 + (ty % 2 == 1 ? 0.5 : 0)))
            if ty % 2 == 1 { table = TileID.wallTable }
        }
        guard shape < table.count else { return [] }
        let q = table[shape], w1 = w / 2, h1 = h / 2
        return (0..<4).map { i in
            (set, (bx * 2 + q[i][0]) * w1, (by * 2 + q[i][1]) * h1, w1, h1, (i % 2) * w1, (i / 2) * h1)
        }
    }

    /// Renders a rectangle of map cells into an image. `upper` selects ☆ tiles (drawn above characters).
    public func renderMap(_ map: GameMap, tileset: Tileset, x0: Int, y0: Int, cols: Int, rows: Int, upper: Bool) -> CGImage? {
        let ctx = makeCanvas(cols * tileSize, rows * tileSize)
        for y in y0..<min(map.height, y0 + rows) { for x in x0..<min(map.width, x0 + cols) {
            for z in 0..<4 {
                let id = map.tileId(x, y, z)
                guard id > 0 else { continue }
                let star = tileset.flag(id) & 0x10 != 0
                if star == upper { draw(id, in: ctx, x: CGFloat((x - x0) * tileSize), y: CGFloat((y - y0) * tileSize)) }
            }
        } }
        return ctx.makeImage()
    }
}

/// Character sheet frame lookup (rmmz_sprites.js Sprite_Character): normal sheets hold 8 characters
/// in a 4x2 grid of 3 patterns x 4 directions; "$" sheets hold one; row = (direction - 2) / 2.
public enum CharacterSheet {
    public static func frame(sheet: CGImage, name: String, index: Int, direction: Int, pattern: Int) -> CGRect {
        let big = name.range(of: "^[!$]*\\$", options: .regularExpression) != nil
        let pw = big ? sheet.width / 3 : sheet.width / 12
        let ph = big ? sheet.height / 4 : sheet.height / 8
        let bx = big ? 0 : (index % 4) * 3
        let by = big ? 0 : (index / 4) * 4
        let row = max(0, min(3, (direction - 2) / 2))
        return CGRect(x: (bx + pattern) * pw, y: (by + row) * ph, width: pw, height: ph)
    }
}
