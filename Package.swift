// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lakon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lakon", targets: ["Lakon"]),
    ],
    targets: [
        // Pure Swift: data model, tile math, interpreter, headless world simulation.
        .target(name: "LakonCore"),
        // CoreGraphics: tile/character rendering and procedural default assets.
        .target(name: "LakonRender", dependencies: ["LakonCore"]),
        // Public-domain Ogg Vorbis decoder (MZ ships .ogg audio; AVFoundation can't decode it).
        .target(name: "CStbVorbis", cSettings: [.unsafeFlags(["-w"])]),
        // SwiftUI/AppKit editor + SpriteKit playtest/runtime.
        .executableTarget(name: "Lakon", dependencies: ["LakonCore", "LakonRender", "CStbVorbis"]),
        .testTarget(name: "LakonCoreTests", dependencies: ["LakonCore", "LakonRender"]),
    ],
    swiftLanguageModes: [.v5]
)
