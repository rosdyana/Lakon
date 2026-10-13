import Foundation

/// A project folder, laid out like an MZ project:
///   game.lakon            marker (MZ uses game.rmmzproject)
///   data/System.json, MapInfos.json, Map001.json, Tilesets.json, Actors.json, Items.json, CommonEvents.json
///   img/tilesets/*.png, img/characters/*.png
public final class Project {
    public static let markerFile = "game.lakon"

    public var root: URL
    public var system = SystemData()
    public var mapInfos: [MapInfo?] = [nil]
    public var maps: [Int: GameMap] = [:]
    public var tilesets: [Tileset?] = [nil]
    public var actors: [Actor?] = [nil]
    public var items: [Item?] = [nil]
    public var commonEvents: [CommonEvent?] = [nil]
    public var classes: [ClassData?] = [nil]
    public var skills: [Skill?] = [nil]
    public var weapons: [EquipItem?] = [nil]
    public var armors: [EquipItem?] = [nil]
    public var enemies: [Enemy?] = [nil]
    public var troops: [Troop?] = [nil]
    public var states: [StateData?] = [nil]
    public var animations: [AnimationData?] = [nil]

    public init(root: URL) { self.root = root }

    public var dataURL: URL { root.appendingPathComponent("data") }
    public func imageURL(_ folder: String, _ name: String) -> URL {
        root.appendingPathComponent("img").appendingPathComponent(folder).appendingPathComponent(name + ".png")
    }
    public static func mapFileName(_ id: Int) -> String { String(format: "Map%03d.json", id) }

    // MARK: load / save

    public static func load(from root: URL) throws -> Project {
        let p = Project(root: root)
        let dataDir = root.appendingPathComponent("data")
        func read<T: Decodable>(_ name: String, _ type: T.Type) throws -> T? {
            let url = dataDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
            catch { throw ProjectError.corrupt(name, error) }
        }
        guard let system = try read("System.json", SystemData.self) else { throw ProjectError.notAProject(root) }
        p.system = system
        p.mapInfos = try read("MapInfos.json", [MapInfo?].self) ?? [nil]
        p.tilesets = try read("Tilesets.json", [Tileset?].self) ?? [nil]
        p.actors = try read("Actors.json", [Actor?].self) ?? [nil]
        p.items = try read("Items.json", [Item?].self) ?? [nil]
        p.commonEvents = try read("CommonEvents.json", [CommonEvent?].self) ?? [nil]
        p.classes = try read("Classes.json", [ClassData?].self) ?? [nil]
        p.skills = try read("Skills.json", [Skill?].self) ?? [nil]
        p.weapons = try read("Weapons.json", [EquipItem?].self) ?? [nil]
        p.armors = try read("Armors.json", [EquipItem?].self) ?? [nil]
        p.enemies = try read("Enemies.json", [Enemy?].self) ?? [nil]
        p.troops = try read("Troops.json", [Troop?].self) ?? [nil]
        p.states = try read("States.json", [StateData?].self) ?? [nil]
        p.animations = try read("Animations.json", [AnimationData?].self) ?? [nil]
        for info in p.mapInfos.compactMap({ $0 }) {
            if let m = try read(mapFileName(info.id), GameMap.self) { p.maps[info.id] = m }
        }
        return p
    }

    public func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dataURL, withIntermediateDirectories: true)
        for f in Project.assetFolders {
            try fm.createDirectory(at: root.appendingPathComponent(f), withIntermediateDirectories: true)
        }
        let marker = root.appendingPathComponent(Self.markerFile)
        if !fm.fileExists(atPath: marker.path) { try Data("LAKON 1.0".utf8).write(to: marker) }
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            try enc.encode(value).write(to: dataURL.appendingPathComponent(name), options: .atomic)
        }
        try write(system, "System.json")
        try write(mapInfos, "MapInfos.json")
        try write(tilesets, "Tilesets.json")
        try write(actors, "Actors.json")
        try write(items, "Items.json")
        try write(commonEvents, "CommonEvents.json")
        try write(classes, "Classes.json")
        try write(skills, "Skills.json")
        try write(weapons, "Weapons.json")
        try write(armors, "Armors.json")
        try write(enemies, "Enemies.json")
        try write(troops, "Troops.json")
        try write(states, "States.json")
        try write(animations, "Animations.json")
        for (id, map) in maps { try write(map, Self.mapFileName(id)) }
        // Remove files of deleted maps.
        let live = Set(maps.keys.map(Self.mapFileName))
        for f in (try? fm.contentsOfDirectory(atPath: dataURL.path)) ?? []
        where f.hasPrefix("Map") && f != "MapInfos.json" && f.hasSuffix(".json") && !live.contains(f) {
            try? fm.removeItem(at: dataURL.appendingPathComponent(f))
        }
    }

    /// Imports an RPG Maker MZ (or MV) project into a new folder. The source is only read, never written.
    public static func importMZ(from source: URL, to dest: URL) throws -> Project {
        let p = try load(from: source)
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for folder in Project.assetFolders {
            let src = source.appendingPathComponent(folder)
            let dst = dest.appendingPathComponent(folder)
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] where Project.assetExtensions.contains((f as NSString).pathExtension.lowercased()) {
                let to = dst.appendingPathComponent(f)
                if !fm.fileExists(atPath: to.path) { try fm.copyItem(at: src.appendingPathComponent(f), to: to) }
            }
        }
        p.root = dest
        try p.save()
        return p
    }

    public static let assetFolders = ["img/tilesets", "img/characters", "img/faces", "img/pictures", "img/enemies", "img/sv_enemies",
                                      "img/sv_actors", "img/animations", "img/battlebacks1", "img/battlebacks2", "img/parallaxes",
                                      "img/titles1", "img/system", "effects", "effects/Texture",
                                      "audio/bgm", "audio/bgs", "audio/me", "audio/se"]
    static let assetExtensions: Set<String> = ["png", "ogg", "m4a", "wav", "mp3", "caf", "aiff", "efkefc", "efk", "efkmat", "efkmodel"]

    public func audioURL(_ folder: String, _ name: String) -> URL? {
        let dir = root.appendingPathComponent("audio").appendingPathComponent(folder)
        for ext in ["ogg", "m4a", "wav", "mp3", "caf", "aiff"] {
            let u = dir.appendingPathComponent(name + "." + ext)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
    public func assetNames(_ folder: String) -> [String] {
        let dir = root.appendingPathComponent(folder)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { Project.assetExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { ($0 as NSString).deletingPathExtension }
        return Array(Set(names)).sorted()
    }

    // MARK: map management

    public var orderedMapInfos: [MapInfo] { mapInfos.compactMap { $0 }.sorted { $0.order < $1.order } }

    @discardableResult
    public func createMap(name: String, width: Int = 17, height: Int = 13, fill: Int = 0, parentId: Int = 0) -> Int {
        let id = (mapInfos.compactMap { $0?.id }.max() ?? 0) + 1
        let order = (mapInfos.compactMap { $0?.order }.max() ?? 0) + 1
        while mapInfos.count <= id { mapInfos.append(nil) }
        mapInfos[id] = MapInfo(id: id, name: name, order: order, parentId: parentId)
        let tid = tilesets.compactMap { $0?.id }.first ?? 1
        maps[id] = GameMap(width: width, height: height, tilesetId: tid, fill: fill)
        return id
    }

    public func deleteMap(_ id: Int) {
        guard id < mapInfos.count else { return }
        let newParent = mapInfos[id]?.parentId ?? 0
        for i in mapInfos.indices where mapInfos[i]?.parentId == id { mapInfos[i]?.parentId = newParent }
        mapInfos[id] = nil
        maps[id] = nil
        while mapInfos.count > 1, mapInfos.last! == nil { mapInfos.removeLast() }
    }

    public func tileset(for map: GameMap) -> Tileset {
        (map.tilesetId < tilesets.count ? tilesets[map.tilesetId] : nil) ?? tilesets.compactMap { $0 }.first ?? Tileset(id: 1, name: "", names: [])
    }
    public func mapName(_ id: Int) -> String { (id < mapInfos.count ? mapInfos[id]?.name : nil) ?? "Map \(id)" }
}

public enum ProjectError: LocalizedError {
    case notAProject(URL)
    case corrupt(String, Error)
    public var errorDescription: String? {
        switch self {
        case .notAProject(let u): return "\(u.lastPathComponent) has no data/System.json — not an RPG project."
        case .corrupt(let f, let e): return "Could not read \(f): \(e.localizedDescription)"
        }
    }
}

/// Grows a 1-based MZ-style array (index 0 is always null) to hold `id`.
public func ensureSlot<T>(_ array: inout [T?], _ id: Int) {
    while array.count <= id { array.append(nil) }
}
