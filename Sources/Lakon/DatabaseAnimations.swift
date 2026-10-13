import AppKit
import LakonCore
import LakonRender
import SpriteKit
import SwiftUI

/// Animation id field for skills, items and weapons. -1 = "Normal Attack" (the user's weapon animation).
struct AnimationPicker: View {
    @ObservedObject var doc: EditorDocument
    @Binding var id: Int
    var allowNormalAttack = true
    var body: some View {
        HStack {
            Picker("Animation", selection: $id) {
                if allowNormalAttack { Text("Normal Attack").tag(-1) }
                Text("None").tag(0)
                ForEach(doc.project.animations.compactMap { $0 }) { a in Text(String(format: "%04d %@", a.id, a.name)).tag(a.id) }
            }
            if id > 0, let a = doc.project.animation(id) {
                Button { AnimationPreviewWindow.show(doc: doc, animation: a) } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless).help("Preview")
            }
        }
    }
}

/// MZ's Animations tab. MV-format entries (cells cut from img/animations) are edited here; MZ-format (Effekseer)
/// entries keep their effect name, scale/speed and flash/sound timings.
struct AnimationsTab: View {
    @ObservedObject var doc: EditorDocument
    @State private var sel: Int? = 1
    @State private var cellCount = 8

    var body: some View {
        HStack(spacing: 0) {
            DBList(items: doc.listBinding(\.animations), selection: $sel, name: { $0.name + ($0.isMV ? "" : " (Effekseer)") }, make: { id in
                var a = AnimationData(id: id, name: "New Animation"); a.frames = DefaultArt.sheetCells("Hit", 5); a.animation1Name = "Hit"; return a
            })
            Divider()
            if let s = sel, s < doc.project.animations.count, doc.project.animations[s] != nil {
                let a = doc.binding(\.animations, s)
                ScrollView {
                    VStack(spacing: 4) {
                        AnimationPreview(doc: doc, animation: a.wrappedValue).frame(width: 250, height: 200).clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Plays on a sample enemy. Click to replay.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                    Form {
                        TextField("Name", text: a.name)
                        Picker("Format", selection: Binding(get: { a.wrappedValue.isMV }, set: { mv in
                            if mv && !a.wrappedValue.isMV { a.wrappedValue.frames = DefaultArt.sheetCells(a.wrappedValue.animation1Name.isEmpty ? "Hit" : a.wrappedValue.animation1Name, cellCount) }
                            if !mv { a.wrappedValue.frames = nil }
                        })) { Text("Cells (MV)").tag(true); Text("Effekseer (MZ)").tag(false) }.pickerStyle(.segmented)
                        if a.wrappedValue.isMV { mvFields(a) } else { mzFields(a) }
                    }.formStyle(.grouped)
                }.frame(minWidth: 0, maxWidth: .infinity)
            } else { Spacer() }
        }
    }

    @ViewBuilder func mvFields(_ a: Binding<AnimationData>) -> some View {
        Picker("Image 1", selection: a.animation1Name) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/animations"), id: \.self) { Text($0).tag($0) } }
        Picker("Image 2", selection: a.animation2Name) { Text("(None)").tag(""); ForEach(doc.project.assetNames("img/animations"), id: \.self) { Text($0).tag($0) } }
        Picker("Position", selection: a.position) { Text("Head").tag(0); Text("Center").tag(1); Text("Feet").tag(2); Text("Screen").tag(3) }
        HStack {
            Text("\(a.wrappedValue.frames?.count ?? 0) frames · \(a.wrappedValue.playFrames) game frames").fixedSize()
            Spacer()
            Stepper("Cells: \(cellCount)", value: $cellCount, in: 1...30).fixedSize()
            Button("Rebuild Frames") { a.wrappedValue.frames = DefaultArt.sheetCells(a.wrappedValue.animation1Name, cellCount) }
        }
        Text("Each frame shows the next 192×192 cell of Image 1 at the target. Lakon doesn't have MZ's cell-by-cell frame editor; imported frames are kept as they are.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Section("Timings (frame = animation frame, 4 game frames each)") {
            ForEach(a.wrappedValue.timings.indices, id: \.self) { i in
                let t = Binding(get: { a.wrappedValue.timings[i] }, set: { a.wrappedValue.timings[i] = $0 })
                HStack {
                    Text("Frame \(t.wrappedValue.frame)").monospacedDigit().frame(width: 70, alignment: .leading)
                    Stepper("", value: t.frame, in: 0...200).labelsHidden()
                    Picker("", selection: t.flashScope) { Text("No flash").tag(0); Text("Target").tag(1); Text("Screen").tag(2); Text("Hide").tag(3) }.labelsHidden().fixedSize()
                    if t.wrappedValue.flashScope > 0 {
                        ColorPicker("", selection: rgbaBinding(t.flashColor)).labelsHidden()
                        Stepper("\(t.wrappedValue.flashDuration)", value: t.flashDuration, in: 1...60).fixedSize()
                    }
                    Picker("", selection: Binding(get: { t.wrappedValue.se?.name ?? "" }, set: { n in t.wrappedValue.se = n.isEmpty ? nil : AudioFile(n, volume: t.wrappedValue.se?.volume ?? 90, pitch: t.wrappedValue.se?.pitch ?? 100) })) {
                        Text("(No SE)").tag("")
                        ForEach(doc.project.assetNames("audio/se"), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 140)
                    Button { if let se = t.wrappedValue.se { doc.previewAudio("se", se) } } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless).disabled(t.wrappedValue.se == nil)
                    Spacer(minLength: 0)
                    Button { a.wrappedValue.timings.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Timing") { a.wrappedValue.timings.append(AnimationData.MVTiming(frame: 0)) }
        }
    }

    @ViewBuilder func mzFields(_ a: Binding<AnimationData>) -> some View {
        TextField("Effect (effects/<name>.efkefc)", text: a.effectName)
        Picker("Display Type", selection: a.displayType) { Text("For each target").tag(0); Text("Center of targets").tag(1); Text("Screen").tag(2) }
        HStack { TextField("Scale %", value: a.scale, format: .number); TextField("Speed %", value: a.speed, format: .number) }
        HStack { TextField("Offset X", value: a.offsetX, format: .number); TextField("Offset Y", value: a.offsetY, format: .number) }
        Toggle("Align bottom", isOn: a.alignBottom)
        Text("The Mac player draws a coloured stand-in for Effekseer effects; the HTML export plays the real effect when the project has effects/.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Section("Flash Timings") {
            ForEach(a.wrappedValue.flashTimings.indices, id: \.self) { i in
                let t = Binding(get: { a.wrappedValue.flashTimings[i] }, set: { a.wrappedValue.flashTimings[i] = $0 })
                HStack {
                    Stepper("Frame \(t.wrappedValue.frame)", value: t.frame, in: 0...600).frame(width: 130)
                    ColorPicker("", selection: rgbaBinding(t.color)).labelsHidden()
                    Stepper("Duration \(t.wrappedValue.duration)", value: t.duration, in: 1...120).fixedSize()
                    Spacer()
                    Button { a.wrappedValue.flashTimings.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Flash") { a.wrappedValue.flashTimings.append(.init(frame: 0, duration: 10, color: [255, 255, 255, 170])) }
        }
        Section("Sound Timings") {
            ForEach(a.wrappedValue.soundTimings.indices, id: \.self) { i in
                let t = Binding(get: { a.wrappedValue.soundTimings[i] }, set: { a.wrappedValue.soundTimings[i] = $0 })
                HStack {
                    Stepper("Frame \(t.wrappedValue.frame)", value: t.frame, in: 0...600).frame(width: 130)
                    AudioField(doc: doc, title: "SE", folder: "se", file: t.se)
                    Button { a.wrappedValue.soundTimings.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Sound") { a.wrappedValue.soundTimings.append(.init(frame: 0, se: AudioFile("Skill"))) }
        }
    }

    func rgbaBinding(_ c: Binding<[Int]>) -> Binding<Color> {
        Binding(get: {
            let v = c.wrappedValue + [255, 255, 255, 255].dropFirst(c.wrappedValue.count)
            return Color(.sRGB, red: Double(v[0]) / 255, green: Double(v[1]) / 255, blue: Double(v[2]) / 255, opacity: Double(v[3]) / 255)
        }, set: { col in
            let n = NSColor(col).usingColorSpace(.sRGB) ?? .white
            c.wrappedValue = [n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent].map { Int(($0 * 255).rounded()) }
        })
    }
}

/// SpriteKit preview of one animation on a sample enemy, using the player's own playback logic.
struct AnimationPreview: NSViewRepresentable {
    @ObservedObject var doc: EditorDocument
    let animation: AnimationData

    func makeNSView(context: Context) -> SKView {
        let v = SKView(); v.preferredFramesPerSecond = 60
        let scene = AnimationPreviewScene(project: doc.project, size: CGSize(width: 250, height: 200))
        v.presentScene(scene)
        scene.play(animation)
        return v
    }
    func updateNSView(_ v: SKView, context: Context) {
        if let s = v.scene as? AnimationPreviewScene, s.current != animation { s.play(animation) }
    }
}

final class AnimationPreviewScene: SKScene {
    let project: Project
    var playback: AnimationPlayback?
    var current: AnimationData?
    let target = SKSpriteNode()
    let flash = SKSpriteNode()
    var cells: [SKSpriteNode] = []
    let screenFlash = SKSpriteNode(color: .white, size: CGSize(width: 400, height: 400))
    var images: [String: CGImage] = [:]
    let audio: AudioPlayer
    let standIn = SKSpriteNode(texture: AnimationArt.glow)

    init(project: Project, size: CGSize) {
        self.project = project
        audio = AudioPlayer(project: project)
        super.init(size: size)
        backgroundColor = NSColor(white: 0.15, alpha: 1)
        let name = project.enemies.compactMap { $0 }.first?.battlerName ?? ""
        if let img = loadPNG(project.imageURL("enemies", name)) { target.texture = SKTexture(cgImage: img); target.size = CGSize(width: img.width, height: img.height) }
        else { target.color = .gray; target.size = CGSize(width: 100, height: 100) }
        let fit = min(1, 180 / max(target.size.height, 1)); target.setScale(fit)
        target.anchorPoint = CGPoint(x: 0.5, y: 0); target.position = CGPoint(x: size.width / 2, y: 40); addChild(target)
        flash.anchorPoint = target.anchorPoint; flash.position = target.position; flash.setScale(fit); flash.shader = SceneUI.flashShader; flash.texture = target.texture
        flash.size = target.size; flash.zPosition = 1; addChild(flash)
        screenFlash.anchorPoint = .zero; screenFlash.zPosition = 20; screenFlash.alpha = 0; addChild(screenFlash)
        standIn.zPosition = 9; standIn.blendMode = .add; standIn.colorBlendFactor = 1; addChild(standIn)
    }
    required init?(coder: NSCoder) { fatalError() }

    func play(_ a: AnimationData) {
        current = a
        playback = AnimationPlayback(a, targets: [0], mirror: false, delay: AnimationData.baseDelay)
    }
    override func mouseDown(with event: NSEvent) { if let a = current { play(a) } }

    func image(_ name: String) -> CGImage? {
        if let i = images[name] { return i }
        let i = loadPNG(project.imageURL("animations", name)); images[name] = i; return i
    }

    override func update(_ currentTime: TimeInterval) {
        guard let p = playback else { return }
        audio.handle(p.update().map { .playSe($0) })
        let a = p.animation
        let h = target.frame.height
        var o = CGPoint(x: size.width / 2, y: 40 + h / 2)
        if a.isMV { o.y = a.position == 0 ? 40 + h : a.position == 2 ? 40 : a.position == 3 ? size.height / 2 : 40 + h / 2; if a.position == 3 { o.x = size.width / 2 } }
        let scale: CGFloat = 0.8
        while cells.count < p.cells.count { let n = SKSpriteNode(); n.zPosition = 10; addChild(n); cells.append(n) }
        for (i, n) in cells.enumerated() {
            guard i < p.cells.count, let c = p.cells[safe: i] else { n.isHidden = true; continue }
            let name = c.sheet == 1 ? a.animation1Name : a.animation2Name
            guard let img = image(name)?.cropping(to: CGRect(x: (c.pattern % 5) * 192, y: (c.pattern / 5) * 192, width: 192, height: 192)) else { n.isHidden = true; continue }
            n.isHidden = false; n.texture = SKTexture(cgImage: img); n.size = CGSize(width: 192 * scale, height: 192 * scale)
            n.position = CGPoint(x: o.x + CGFloat(c.x) * scale, y: o.y - CGFloat(c.y) * scale)
            n.zRotation = -CGFloat(c.rotation); n.xScale = CGFloat(c.scaleX); n.yScale = CGFloat(c.scaleY); n.alpha = CGFloat(c.opacity / 255)
            n.blendMode = [.alpha, .add, .multiply, .screen][max(0, min(3, c.blend))]
        }
        if let t = p.standInProgress {
            let col = AnimationArt.standInColor(a)
            standIn.isHidden = false; standIn.position = o; standIn.alpha = CGFloat(sin(t * .pi))
            standIn.size = CGSize(width: 180, height: 180); standIn.color = NSColor(red: col.0 / 255, green: col.1 / 255, blue: col.2 / 255, alpha: 1)
        } else { standIn.isHidden = true }
        let f = p.flashColor
        flash.isHidden = f[3] < 0.5 || p.hidingTargets
        flash.setValue(SKAttributeValue(vectorFloat4: vector_float4(Float(f[0] / 255), Float(f[1] / 255), Float(f[2] / 255), Float(f[3] / 255))), forAttribute: "a_flash")
        target.isHidden = p.hidingTargets
        let sf = p.screenFlashColor
        screenFlash.color = NSColor(red: sf[0] / 255, green: sf[1] / 255, blue: sf[2] / 255, alpha: 1); screenFlash.alpha = sf[3] / 255
        if !p.isPlaying { cells.forEach { $0.isHidden = true } }
    }
}

/// Small floating window for previewing from skill/item/weapon pickers.
enum AnimationPreviewWindow {
    static var windows: [NSWindow] = []
    static func show(doc: EditorDocument, animation: AnimationData) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = animation.name
        w.contentView = NSHostingView(rootView: AnimationPreview(doc: doc, animation: animation))
        w.isReleasedWhenClosed = false
        w.center(); w.makeKeyAndOrderFront(nil)
        windows.append(w); windows.removeAll { !$0.isVisible && $0 !== w }
    }
}
