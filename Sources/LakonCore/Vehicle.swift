import Foundation

/// Port of Game_Vehicle: boat (shallow water, flag 0x200 clear), ship (0x400 clear), airship (flies; lands where
/// 0x800 is clear and the tile is walkable). The player boards with the action button, like MZ.
public final class GameVehicle: GameCharacter {
    public enum Kind: Int, CaseIterable { case boat = 0, ship, airship }
    public let kind: Kind
    public var mapId = 0
    public var driving = false
    public var altitude = 0.0
    public static let maxAltitude = 48.0

    init(kind: Kind, data: VehicleData) {
        self.kind = kind
        super.init()
        setImage(data.characterName, data.characterIndex)
        mapId = data.startMapId
        locate(data.startX, data.startY)
        moveSpeed = [4, 5, 6][kind.rawValue]
        priorityType = kind == .airship ? 2 : 1
        walkAnime = true
        stepAnime = false
    }

    var bgm: AudioFile? {
        guard let s = world?.project.system else { return nil }
        return [s.boat, s.ship, s.airship][kind.rawValue].bgm
    }

    func isPassable(at x: Int, _ y: Int) -> Bool {
        guard let w = world, w.map.isValid(x, y) else { return false }
        switch kind {
        case .boat: return w.map.checkPassage(x, y, bit: 0x0200, tileset: w.tileset)
        case .ship: return w.map.checkPassage(x, y, bit: 0x0400, tileset: w.tileset)
        case .airship: return true
        }
    }

    func isLandOk(_ x: Int, _ y: Int, _ d: Int) -> Bool {
        guard let w = world else { return false }
        if kind == .airship {
            return w.map.checkPassage(x, y, bit: 0x0800, tileset: w.tileset) && w.map.checkPassage(x, y, bit: 0x0f, tileset: w.tileset)
                && !w.events.contains { $0.x == x && $0.y == y && $0.pageIndex >= 0 }
        }
        let x2 = Self.xWith(x, d), y2 = Self.yWith(y, d)
        guard w.map.isValid(x2, y2), w.map.isPassable(x2, y2, Self.reverse(d), tileset: w.tileset) else { return false }
        return !w.events.contains { $0.x == x2 && $0.y == y2 && $0.isNormalPriority && !$0.through && $0.pageIndex >= 0 }
    }

    override func update() {
        super.update()
        if kind == .airship {
            if driving { altitude = min(Self.maxAltitude, altitude + 1) } else { altitude = max(0, altitude - 1) }
        }
    }

    var save: VehicleSave { VehicleSave(mapId: mapId, x: x, y: y, direction: direction) }
}
