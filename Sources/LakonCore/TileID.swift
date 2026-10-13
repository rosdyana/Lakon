import Foundation

/// MZ tile ID space (rmmz_core.js Tilemap.TILE_ID_*). Kept identical so imported maps render correctly.
public enum TileID {
    public static let B = 0, C = 256, D = 512, E = 768
    public static let A5 = 1536, A1 = 2048, A2 = 2816, A3 = 4352, A4 = 5888
    public static let max = 8192

    public static func isAutotile(_ id: Int) -> Bool { id >= A1 }
    public static func isA1(_ id: Int) -> Bool { id >= A1 && id < A2 }
    public static func isA2(_ id: Int) -> Bool { id >= A2 && id < A3 }
    public static func isA3(_ id: Int) -> Bool { id >= A3 && id < A4 }
    public static func isA4(_ id: Int) -> Bool { id >= A4 && id < max }
    public static func isA5(_ id: Int) -> Bool { id >= A5 && id < A1 }
    public static func isUpperSet(_ id: Int) -> Bool { id > 0 && id < A5 }   // B..E
    public static func kind(_ id: Int) -> Int { (id - A1) / 48 }
    public static func shape(_ id: Int) -> Int { (id - A1) % 48 }
    public static func make(kind: Int, shape: Int) -> Int { A1 + kind * 48 + shape }
    public static func sameKind(_ a: Int, _ b: Int) -> Bool {
        isAutotile(a) && isAutotile(b) ? kind(a) == kind(b) : a == b
    }

    /// Wall-type autotiles use the 16-entry wall table: A3 everything, A4 odd rows.
    public static func isWallType(_ id: Int) -> Bool {
        if isA3(id) { return true }
        if isA4(id) { return (kind(id) / 8) % 2 == 1 }
        return false
    }
    /// A1 kinds 5,7,9,11,13,15 are waterfalls (4-entry table, left/right neighbours only).
    public static func isWaterfall(_ id: Int) -> Bool {
        isA1(id) && kind(id) >= 4 && kind(id) % 2 == 1
    }
    /// A1 "decoration" kinds and A2 right half sit on layer 1 above the ground (field mode).
    public static func isOverlayGround(_ id: Int) -> Bool {
        if isA2(id) { return (kind(id) % 8) >= 4 }
        return false
    }

    // MARK: autotile tables (rmmz_core.js:2765-2842). These are part of the file format:
    // a tile's "shape" (0..47) indexes this table, so they must match MZ exactly.

    public static let floorTable: [[[Int]]] = [
        [[2, 4], [1, 4], [2, 3], [1, 3]], [[2, 0], [1, 4], [2, 3], [1, 3]], [[2, 4], [3, 0], [2, 3], [1, 3]], [[2, 0], [3, 0], [2, 3], [1, 3]],
        [[2, 4], [1, 4], [2, 3], [3, 1]], [[2, 0], [1, 4], [2, 3], [3, 1]], [[2, 4], [3, 0], [2, 3], [3, 1]], [[2, 0], [3, 0], [2, 3], [3, 1]],
        [[2, 4], [1, 4], [2, 1], [1, 3]], [[2, 0], [1, 4], [2, 1], [1, 3]], [[2, 4], [3, 0], [2, 1], [1, 3]], [[2, 0], [3, 0], [2, 1], [1, 3]],
        [[2, 4], [1, 4], [2, 1], [3, 1]], [[2, 0], [1, 4], [2, 1], [3, 1]], [[2, 4], [3, 0], [2, 1], [3, 1]], [[2, 0], [3, 0], [2, 1], [3, 1]],
        [[0, 4], [1, 4], [0, 3], [1, 3]], [[0, 4], [3, 0], [0, 3], [1, 3]], [[0, 4], [1, 4], [0, 3], [3, 1]], [[0, 4], [3, 0], [0, 3], [3, 1]],
        [[2, 2], [1, 2], [2, 3], [1, 3]], [[2, 2], [1, 2], [2, 3], [3, 1]], [[2, 2], [1, 2], [2, 1], [1, 3]], [[2, 2], [1, 2], [2, 1], [3, 1]],
        [[2, 4], [3, 4], [2, 3], [3, 3]], [[2, 4], [3, 4], [2, 1], [3, 3]], [[2, 0], [3, 4], [2, 3], [3, 3]], [[2, 0], [3, 4], [2, 1], [3, 3]],
        [[2, 4], [1, 4], [2, 5], [1, 5]], [[2, 0], [1, 4], [2, 5], [1, 5]], [[2, 4], [3, 0], [2, 5], [1, 5]], [[2, 0], [3, 0], [2, 5], [1, 5]],
        [[0, 4], [3, 4], [0, 3], [3, 3]], [[2, 2], [1, 2], [2, 5], [1, 5]], [[0, 2], [1, 2], [0, 3], [1, 3]], [[0, 2], [1, 2], [0, 3], [3, 1]],
        [[2, 2], [3, 2], [2, 3], [3, 3]], [[2, 2], [3, 2], [2, 1], [3, 3]], [[2, 4], [3, 4], [2, 5], [3, 5]], [[2, 0], [3, 4], [2, 5], [3, 5]],
        [[0, 4], [1, 4], [0, 5], [1, 5]], [[0, 4], [3, 0], [0, 5], [1, 5]], [[0, 2], [3, 2], [0, 3], [3, 3]], [[0, 2], [1, 2], [0, 5], [1, 5]],
        [[0, 4], [3, 4], [0, 5], [3, 5]], [[2, 2], [3, 2], [2, 5], [3, 5]], [[0, 2], [3, 2], [0, 5], [3, 5]], [[0, 0], [1, 0], [0, 1], [1, 1]],
    ]
    public static let wallTable: [[[Int]]] = [
        [[2, 2], [1, 2], [2, 1], [1, 1]], [[0, 2], [1, 2], [0, 1], [1, 1]], [[2, 0], [1, 0], [2, 1], [1, 1]], [[0, 0], [1, 0], [0, 1], [1, 1]],
        [[2, 2], [3, 2], [2, 1], [3, 1]], [[0, 2], [3, 2], [0, 1], [3, 1]], [[2, 0], [3, 0], [2, 1], [3, 1]], [[0, 0], [3, 0], [0, 1], [3, 1]],
        [[2, 2], [1, 2], [2, 3], [1, 3]], [[0, 2], [1, 2], [0, 3], [1, 3]], [[2, 0], [1, 0], [2, 3], [1, 3]], [[0, 0], [1, 0], [0, 3], [1, 3]],
        [[2, 2], [3, 2], [2, 3], [3, 3]], [[0, 2], [3, 2], [0, 3], [3, 3]], [[2, 0], [3, 0], [2, 3], [3, 3]], [[0, 0], [3, 0], [0, 3], [3, 3]],
    ]
    public static let waterfallTable: [[[Int]]] = [
        [[2, 0], [1, 0], [2, 1], [1, 1]], [[0, 0], [1, 0], [0, 1], [1, 1]],
        [[2, 0], [3, 0], [2, 1], [3, 1]], [[0, 0], [3, 0], [0, 1], [3, 1]],
    ]

    // MARK: shape derivation (editor side — MZ's editor does this; the runtime only reads shapes)

    /// Neighbour-same flags for a floor autotile: indices 0..7 = UL, U, UR, L, R, DL, D, DR.
    /// Each quarter picks a piece from the 4x6 quarter grid; the resulting quartet is looked up
    /// in `floorTable`, which guarantees the shape IDs we write are the ones MZ expects.
    public static func floorShape(same n: [Bool]) -> Int {
        let ul = n[0], u = n[1], ur = n[2], l = n[3], r = n[4], dl = n[5], d = n[6], dr = n[7]
        func quarter(_ v: Bool, _ h: Bool, _ diag: Bool, outer: [Int], vEdge: [Int], hEdge: [Int], inner: [Int], center: [Int]) -> [Int] {
            switch (v, h) {
            case (false, false): return outer
            case (false, true): return hEdge      // vertical neighbour differs → top/bottom edge
            case (true, false): return vEdge      // horizontal neighbour differs → left/right edge
            case (true, true): return diag ? center : inner
            }
        }
        let q = [
            quarter(u, l, ul, outer: [0, 2], vEdge: [0, 4], hEdge: [2, 2], inner: [2, 0], center: [2, 4]),
            quarter(u, r, ur, outer: [3, 2], vEdge: [3, 4], hEdge: [1, 2], inner: [3, 0], center: [1, 4]),
            quarter(d, l, dl, outer: [0, 5], vEdge: [0, 3], hEdge: [2, 5], inner: [2, 1], center: [2, 3]),
            quarter(d, r, dr, outer: [3, 5], vEdge: [3, 3], hEdge: [1, 5], inner: [3, 1], center: [1, 3]),
        ]
        return floorTable.firstIndex(of: q) ?? 0
    }

    /// Wall shape is a 4-bit mask of differing orthogonal neighbours: 1 left, 2 up, 4 right, 8 down.
    public static func wallShape(same n: [Bool]) -> Int {
        (n[3] ? 0 : 1) | (n[1] ? 0 : 2) | (n[4] ? 0 : 4) | (n[6] ? 0 : 8)
    }
    public static func waterfallShape(same n: [Bool]) -> Int {
        (n[3] ? 0 : 1) | (n[4] ? 0 : 2)
    }
}

extension GameMap {
    static let neighbourOffsets = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

    /// Recomputes the autotile shape at (x, y, z) from its neighbours. Out-of-bounds counts as "same"
    /// so edges of the map don't get borders, matching MZ's editor.
    public mutating func refreshAutotile(_ x: Int, _ y: Int, _ z: Int) {
        guard isValid(x, y) else { return }
        let id = tileId(x, y, z)
        guard TileID.isAutotile(id) else { return }
        let same = Self.neighbourOffsets.map { (dx, dy) -> Bool in
            let nx = x + dx, ny = y + dy
            return !isValid(nx, ny) || TileID.sameKind(tileId(nx, ny, z), id)
        }
        let shape: Int
        if TileID.isWaterfall(id) { shape = TileID.waterfallShape(same: same) }
        else if TileID.isWallType(id) { shape = TileID.wallShape(same: same) }
        else { shape = TileID.floorShape(same: same) }
        setTile(x, y, z, TileID.make(kind: TileID.kind(id), shape: shape))
    }

    public mutating func refreshAutotiles(around x: Int, _ y: Int, _ z: Int) {
        for dy in -1...1 { for dx in -1...1 { refreshAutotile(x + dx, y + dy, z) } }
    }

    /// Places a palette tile with MZ-style automatic layering:
    /// - A tiles go to z0 (ground) or z1 (A2 right-half overlays) and clear the upper layers.
    /// - B–E tiles go to z3 if z2 holds a different tile, else z2.
    /// `paletteId` for autotiles is any id of the kind; the shape is recomputed.
    public mutating func place(_ paletteId: Int, _ x: Int, _ y: Int) {
        guard isValid(x, y) else { return }
        if TileID.isUpperSet(paletteId) {
            let z2 = tileId(x, y, 2)
            if z2 == 0 || z2 == paletteId { setTile(x, y, 2, paletteId) } else { setTile(x, y, 3, paletteId) }
            return
        }
        let z = TileID.isOverlayGround(paletteId) ? 1 : 0
        if z == 0 { setTile(x, y, 1, 0); refreshAutotiles(around: x, y, 1) }
        setTile(x, y, 2, 0); setTile(x, y, 3, 0)
        setTile(x, y, z, TileID.isAutotile(paletteId) ? TileID.make(kind: TileID.kind(paletteId), shape: 0) : paletteId)
        refreshAutotiles(around: x, y, z)
    }

    /// Eraser: removes the topmost non-empty tile layer (z3 → z0).
    public mutating func eraseTop(_ x: Int, _ y: Int) {
        for z in stride(from: 3, through: 0, by: -1) where tileId(x, y, z) != 0 {
            setTile(x, y, z, 0); refreshAutotiles(around: x, y, z); return
        }
    }

    /// The layer whose content defines a cell for flood fill (topmost non-empty).
    public func topTile(_ x: Int, _ y: Int) -> Int {
        for z in stride(from: 3, through: 0, by: -1) where tileId(x, y, z) != 0 {
            return TileID.isAutotile(tileId(x, y, z)) ? TileID.make(kind: TileID.kind(tileId(x, y, z)), shape: 0) : tileId(x, y, z)
        }
        return 0
    }

    public mutating func floodFill(_ paletteId: Int, _ x: Int, _ y: Int) {
        guard isValid(x, y) else { return }
        let target = topTile(x, y)
        var seen = Set<Int>(), stack = [(x, y)]
        while let (cx, cy) = stack.popLast() {
            guard isValid(cx, cy), !seen.contains(cy * width + cx), topTile(cx, cy) == target else { continue }
            seen.insert(cy * width + cx)
            stack += [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
        }
        for key in seen { place(paletteId, key % width, key / width) }
    }

    /// Passability, ported in behaviour from rmmz_objects.js Game_Map.checkPassage:
    /// scan layers top→down; ☆ tiles are ignored; first tile with a decisive bit wins.
    public func checkPassage(_ x: Int, _ y: Int, bit: Int, tileset: Tileset) -> Bool {
        for z in stride(from: 3, through: 0, by: -1) {
            let tile = tileId(x, y, z)
            let flag = tileset.flag(tile)
            if flag & 0x10 != 0 { continue }
            if flag & bit == 0 { return true }
            if flag & bit == bit { return false }
        }
        return false
    }
    /// d is a numpad direction: 2 down, 4 left, 6 right, 8 up.
    public func isPassable(_ x: Int, _ y: Int, _ d: Int, tileset: Tileset) -> Bool {
        checkPassage(x, y, bit: (1 << (d / 2 - 1)) & 0x0f, tileset: tileset)
    }
    public func regionId(_ x: Int, _ y: Int) -> Int { tileId(x, y, 5) }
}
