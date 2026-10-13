import Foundation
import LakonCore

/// "Deployment": copies this very executable into <Title>.app with the project under Resources/Game.
/// At launch, main.swift sees Resources/Game and starts straight into the player (no editor UI).
enum Exporter {
    static func exportApp(project: Project, to dir: URL) throws -> URL {
        let fm = FileManager.default
        let safe = project.system.gameTitle.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted).joined()
        let name = safe.trimmingCharacters(in: .whitespaces).isEmpty ? "Game" : safe.trimmingCharacters(in: .whitespaces)
        let app = dir.appendingPathComponent(name + ".app")
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        let contents = app.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS"), res = contents.appendingPathComponent("Resources")
        let game = res.appendingPathComponent("Game")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: game, withIntermediateDirectories: true)

        guard let exe = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        try fm.copyItem(at: exe, to: macos.appendingPathComponent(name))
        try fm.copyItem(at: project.root.appendingPathComponent("data"), to: game.appendingPathComponent("data"))
        try fm.copyItem(at: project.root.appendingPathComponent("img"), to: game.appendingPathComponent("img"))
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            try? fm.copyItem(at: icon, to: res.appendingPathComponent("AppIcon.icns"))
        }

        let id = "com.lakon.game." + name.lowercased().filter { $0.isLetter || $0.isNumber }
        let plist: [String: Any] = [
            "CFBundleExecutable": name, "CFBundleIdentifier": id, "CFBundleName": project.system.gameTitle,
            "CFBundleDisplayName": project.system.gameTitle, "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "CFBundleIconFile": "AppIcon",
            "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": true, "NSPrincipalClass": "NSApplication",
            "LSApplicationCategoryType": "public.app-category.role-playing-games",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        // Ad-hoc signature so Apple Silicon will launch it locally (distribution needs a Developer ID + notarization).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--force", "--deep", "--sign", "-", app.path]
        try p.run(); p.waitUntilExit()
        return app
    }
}
