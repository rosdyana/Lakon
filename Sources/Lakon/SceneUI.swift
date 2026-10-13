import AppKit
import LakonCore
import LakonRender
import SpriteKit

/// Immediate-mode UI on top of SpriteKit with node reuse: every frame the scene "declares" its windows,
/// labels and sprites by key; nodes not declared in a frame are removed. This keeps per-frame node churn low.
final class SceneUI {
    let root = SKNode()
    private var nodes: [String: SKNode] = [:]
    private var used = Set<String>()
    private var shapeRects: [String: CGRect] = [:]
    var frame = 0

    static let font = "Avenir Next Medium"
    static let bold = "Avenir Next Demi Bold"
    /// MZ window-skin text colours (\C[n]).
    static let textColors: [NSColor] = [
        .white, NSColor(red: 0.13, green: 0.6, blue: 0.87, alpha: 1), NSColor(red: 1, green: 0.47, blue: 0.47, alpha: 1),
        NSColor(red: 0.4, green: 0.8, blue: 0.25, alpha: 1), NSColor(red: 0.6, green: 0.8, blue: 1, alpha: 1),
        NSColor(red: 0.8, green: 0.6, blue: 1, alpha: 1), NSColor(red: 1, green: 1, blue: 0.6, alpha: 1),
        NSColor(white: 0.62, alpha: 1), NSColor(white: 0.75, alpha: 1), NSColor(red: 0.13, green: 0.4, blue: 0.85, alpha: 1),
        NSColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1), NSColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1),
        NSColor(red: 0.2, green: 0.6, blue: 0.85, alpha: 1), NSColor(red: 0.6, green: 0.4, blue: 0.85, alpha: 1),
        NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1), NSColor.black,
        NSColor(red: 0.52, green: 0.75, blue: 1, alpha: 1), NSColor(red: 1, green: 1, blue: 0.25, alpha: 1),
        NSColor(red: 1, green: 0.2, blue: 0.2, alpha: 1), NSColor.black, NSColor(red: 0.88, green: 0.5, blue: 0.25, alpha: 1),
        NSColor(red: 0.94, green: 0.75, blue: 0.25, alpha: 1), NSColor(red: 0.13, green: 0.25, blue: 0.5, alpha: 1),
        NSColor(red: 0.5, green: 0.25, blue: 0.5, alpha: 1), NSColor(red: 0.5, green: 0.75, blue: 0.25, alpha: 1),
        NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1), NSColor(red: 0.5, green: 0.5, blue: 1, alpha: 1),
        NSColor(red: 1, green: 0.5, blue: 1, alpha: 1), NSColor(red: 0, green: 0.6, blue: 0.25, alpha: 1),
        NSColor(red: 0, green: 0.88, blue: 0.4, alpha: 1), NSColor(red: 0.63, green: 0.38, blue: 0.88, alpha: 1),
        NSColor(red: 0.75, green: 0.5, blue: 1, alpha: 1),
    ]
    static let hpColor = (NSColor(red: 0.88, green: 0.5, blue: 0.25, alpha: 1), NSColor(red: 0.94, green: 0.75, blue: 0.25, alpha: 1))
    static let mpColor = (NSColor(red: 0.13, green: 0.4, blue: 0.85, alpha: 1), NSColor(red: 0.25, green: 0.63, blue: 1, alpha: 1))
    static let tpColor = (NSColor(red: 0, green: 0.63, blue: 0.25, alpha: 1), NSColor(red: 0, green: 0.88, blue: 0.4, alpha: 1))
    static let systemColor = NSColor(red: 0.52, green: 0.75, blue: 1, alpha: 1)

    var windowTone: [Int] = [0, 0, 0, 0]
    var iconSheet: SKTexture?
    var iconTextures: [Int: SKTexture] = [:]

    init() { root.zPosition = 100 }

    func begin() { used = []; frame += 1 }
    func end() {
        for (k, n) in nodes where !used.contains(k) { n.removeFromParent(); nodes[k] = nil; shapeRects[k] = nil }
    }

    private func node<T: SKNode>(_ key: String, _ make: () -> T) -> T {
        used.insert(key)
        if let n = nodes[key] as? T { return n }
        nodes[key]?.removeFromParent()
        let n = make()
        nodes[key] = n
        root.addChild(n)
        return n
    }

    // MARK: windows

    var windowFill: NSColor {
        let t = windowTone
        return NSColor(red: CGFloat(max(0, min(255, 26 + t[0]))) / 255, green: CGFloat(max(0, min(255, 34 + t[1]))) / 255,
                       blue: CGFloat(max(0, min(255, 78 + t[2]))) / 255, alpha: 0.92)
    }

    func window(_ key: String, _ r: CGRect, z: CGFloat = 0, opacity: CGFloat = 1) {
        let n = node(key) { SKShapeNode() }
        if shapeRects[key] != r {
            n.path = CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)
            shapeRects[key] = r
        }
        n.fillColor = windowFill; n.strokeColor = NSColor(white: 1, alpha: 0.85); n.lineWidth = 2
        n.zPosition = z; n.alpha = opacity
    }

    func rect(_ key: String, _ r: CGRect, color: NSColor, z: CGFloat = 0, corner: CGFloat = 0, stroke: NSColor? = nil) {
        let n = node(key) { SKShapeNode() }
        if shapeRects[key] != r {
            n.path = corner > 0 ? CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil) : CGPath(rect: r, transform: nil)
            shapeRects[key] = r
        }
        n.fillColor = color; n.strokeColor = stroke ?? .clear; n.lineWidth = stroke == nil ? 0 : 1.5; n.zPosition = z
    }

    func cursor(_ key: String, _ r: CGRect, z: CGFloat = 1) {
        let pulse = 0.2 + 0.1 * sin(Double(frame) / 8)
        rect(key, r, color: NSColor(white: 1, alpha: pulse), z: z, corner: 6, stroke: NSColor(white: 1, alpha: 0.55))
    }

    @discardableResult
    func label(_ key: String, _ text: String, _ p: CGPoint, size: CGFloat = 22, color: NSColor = .white, align: SKLabelHorizontalAlignmentMode = .left,
               bold: Bool = false, z: CGFloat = 2, alpha: CGFloat = 1, maxWidth: CGFloat? = nil) -> SKLabelNode {
        let l = node(key) { () -> SKLabelNode in
            let l = SKLabelNode(); l.verticalAlignmentMode = .baseline
            let sh = SKLabelNode(); sh.name = "shadow"; sh.fontColor = NSColor(white: 0, alpha: 0.65); sh.position = CGPoint(x: 1.5, y: -1.5); sh.zPosition = -0.1
            sh.verticalAlignmentMode = .baseline
            l.addChild(sh)
            return l
        }
        let fontName = bold ? Self.bold : Self.font
        if l.text != text || l.fontSize != size || l.fontName != fontName {
            l.text = text; l.fontSize = size; l.fontName = fontName
            if let sh = l.childNode(withName: "shadow") as? SKLabelNode { sh.text = text; sh.fontSize = size; sh.fontName = fontName }
        }
        (l.childNode(withName: "shadow") as? SKLabelNode)?.horizontalAlignmentMode = align
        l.horizontalAlignmentMode = align; l.fontColor = color; l.position = p; l.zPosition = z; l.alpha = alpha
        if let mw = maxWidth, l.frame.width > mw { l.xScale = mw / l.frame.width * l.xScale } else { l.xScale = 1 }
        return l
    }

    func sprite(_ key: String, _ tex: SKTexture?, center: CGPoint, size: CGSize? = nil, z: CGFloat = 1, alpha: CGFloat = 1, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5),
                rotation: CGFloat = 0, xScale: CGFloat = 1, yScale: CGFloat = 1, blend: SKBlendMode = .alpha) {
        guard let tex else { return }
        let s = node(key) { SKSpriteNode() }
        if s.texture !== tex { s.texture = tex }
        s.size = size ?? tex.size(); s.position = center; s.zPosition = z; s.alpha = alpha; s.anchorPoint = anchor
        s.zRotation = rotation; s.xScale = xScale; s.yScale = yScale; s.blendMode = blend
    }

    /// A silhouette of `tex` in a solid colour, alpha-blended over the sprite: MZ's Sprite.setBlendColor
    /// (rgb = mix(rgb, color, a)). `rgba` is 0…255.
    func flashSprite(_ key: String, _ tex: SKTexture?, center: CGPoint, size: CGSize? = nil, z: CGFloat, anchor: CGPoint, rgba: [Double],
                     xScale: CGFloat = 1, blend: SKBlendMode = .alpha) {
        guard let tex, rgba.count >= 4, rgba[3] > 0.5 else { return }
        let s = node(key) { () -> SKSpriteNode in let n = SKSpriteNode(); n.shader = Self.flashShader; return n }
        if s.texture !== tex { s.texture = tex }
        s.size = size ?? tex.size(); s.position = center; s.zPosition = z; s.anchorPoint = anchor; s.xScale = xScale; s.blendMode = blend
        s.setValue(SKAttributeValue(vectorFloat4: vector_float4(Float(rgba[0] / 255), Float(rgba[1] / 255), Float(rgba[2] / 255), Float(rgba[3] / 255))), forAttribute: "a_flash")
    }

    static let flashShader: SKShader = {
        let sh = SKShader(source: """
        void main() {
            vec4 c = texture2D(u_texture, v_tex_coord);
            gl_FragColor = vec4(a_flash.rgb, 1.0) * c.a * a_flash.a;
        }
        """)
        sh.attributes = [SKAttribute(name: "a_flash", type: .vectorFloat4)]
        return sh
    }()

    func icon(_ key: String, _ index: Int, _ p: CGPoint, size: CGFloat = 28, z: CGFloat = 2, alpha: CGFloat = 1) {
        guard index > 0, let t = iconTexture(index) else { return }
        sprite(key, t, center: CGPoint(x: p.x + size / 2, y: p.y + size / 2), size: CGSize(width: size, height: size), z: z, alpha: alpha)
    }

    func iconTexture(_ index: Int) -> SKTexture? {
        if let t = iconTextures[index] { return t }
        guard let sheet = iconSheet else { return nil }
        let cols = Int(sheet.size().width / 32), rows = Int(sheet.size().height / 32)
        guard cols > 0, index / cols < rows else { return nil }
        let r = CGRect(x: CGFloat(index % cols) / CGFloat(cols), y: 1 - CGFloat(index / cols + 1) / CGFloat(rows),
                       width: 1 / CGFloat(cols), height: 1 / CGFloat(rows))
        let t = SKTexture(rect: r, in: sheet); t.filteringMode = .nearest
        iconTextures[index] = t
        return t
    }

    func gauge(_ key: String, _ r: CGRect, rate: Double, colors: (NSColor, NSColor), label: String, value: String, z: CGFloat = 2) {
        rect(key + ".bg", CGRect(x: r.minX, y: r.minY, width: r.width, height: 8), color: NSColor(white: 0.1, alpha: 0.9), z: z, corner: 3)
        let w = max(0, min(1, rate)) * Double(r.width)
        if w > 0 { rect(key + ".fg", CGRect(x: r.minX, y: r.minY, width: CGFloat(w), height: 8), color: colors.1, z: z + 0.1, corner: 3) }
        self.label(key + ".l", label, CGPoint(x: r.minX, y: r.minY + 6), size: 16, color: Self.systemColor, bold: true, z: z + 0.2)
        self.label(key + ".v", value, CGPoint(x: r.maxX, y: r.minY + 6), size: 18, align: .right, z: z + 0.2)
    }

    /// Text with MZ escapes \C[n] colour and \I[n] icon. Returns the drawn width.
    @discardableResult
    func richText(_ key: String, _ text: String, _ p: CGPoint, size: CGFloat = 24, z: CGFloat = 2, alpha: CGFloat = 1) -> CGFloat {
        var x = p.x, color: NSColor = .white, run = "", i = 0
        let chars = Array(text)
        func flush() {
            guard !run.isEmpty else { return }
            let l = label("\(key).\(i)", run, CGPoint(x: x, y: p.y), size: size, color: color, z: z, alpha: alpha)
            x += l.frame.width
            i += 1; run = ""
        }
        var k = 0
        while k < chars.count {
            if chars[k] == "\\", k + 2 < chars.count, ["C", "c", "I", "i"].contains(chars[k + 1]), chars[k + 2] == "[",
               let close = chars[(k + 3)...].firstIndex(of: "]"), let n = Int(String(chars[(k + 3)..<close])) {
                flush()
                if chars[k + 1] == "C" || chars[k + 1] == "c" { color = Self.textColors[safe: n] ?? .white }
                else { icon("\(key).icon\(i)", n, CGPoint(x: x + 2, y: p.y - 6), size: size + 4, z: z, alpha: alpha); x += size + 8; i += 1 }
                k = close + 1
                continue
            }
            run.append(chars[k]); k += 1
        }
        flush()
        return x - p.x
    }

    struct Row {
        var text: String
        var icon = 0
        var right = ""
        var enabled = true
        var color: NSColor = .white
    }

    /// A selectable list window (Window_Selectable): rows of `rowHeight`, scrolling to keep the cursor visible.
    /// `columns` > 1 lays rows out in a grid like MZ's item lists.
    func list(_ key: String, _ r: CGRect, rows: [Row], cursor: Int?, active: Bool = true, rowHeight: CGFloat = 38, columns: Int = 1, z: CGFloat = 20, title: String? = nil) {
        window(key + ".w", r, z: z)
        var top = r.maxY - 12
        if let t = title {
            label(key + ".title", t, CGPoint(x: r.minX + 18, y: top - 28), size: 20, color: Self.systemColor, bold: true, z: z + 2)
            top -= 36
        }
        let visibleRows = max(1, Int((top - r.minY - 8) / rowHeight))
        let cols = max(1, columns)
        let cur = cursor ?? 0
        let firstRow = max(0, min(cur / cols - visibleRows + 1, (rows.count + cols - 1) / cols - visibleRows))
        let start = max(0, (cursor == nil ? 0 : max(0, firstRow)) * cols)
        let colW = (r.width - 24) / CGFloat(cols)
        for (n, i) in (start..<min(rows.count, start + visibleRows * cols)).enumerated() {
            let row = rows[i]
            let x = r.minX + 12 + CGFloat(n % cols) * colW
            let y = top - CGFloat(n / cols + 1) * rowHeight
            if active, cursor == i { self.cursor(key + ".c", CGRect(x: x, y: y + 2, width: colW - 4, height: rowHeight - 4), z: z + 1) }
            var tx = x + 10
            if row.icon > 0 { icon(key + ".i\(n)", row.icon, CGPoint(x: tx, y: y + (rowHeight - 28) / 2), z: z + 2, alpha: row.enabled ? 1 : 0.45); tx += 34 }
            label(key + ".t\(n)", row.text, CGPoint(x: tx, y: y + rowHeight / 2 - 8), size: 21, color: row.color, z: z + 2,
                  alpha: row.enabled ? 1 : 0.45, maxWidth: colW - (tx - x) - (row.right.isEmpty ? 14 : 76))
            if !row.right.isEmpty { label(key + ".r\(n)", row.right, CGPoint(x: x + colW - 16, y: y + rowHeight / 2 - 8), size: 20, align: .right, z: z + 2, alpha: row.enabled ? 1 : 0.45) }
        }
        if rows.count > start + visibleRows * cols { label(key + ".more", "▼", CGPoint(x: r.midX, y: r.minY + 2), size: 14, align: .center, z: z + 2) }
        if start > 0 { label(key + ".less", "▲", CGPoint(x: r.midX, y: r.maxY - 16), size: 14, align: .center, z: z + 2) }
    }

    /// Moves a list cursor with up/down (and left/right in grids), wrapping like MZ.
    static func move(_ cursor: inout Int, count: Int, _ u: UIInput, columns: Int = 1) -> Bool {
        guard count > 0 else { return false }
        let old = cursor
        if u.down { cursor = cursor + columns < count ? cursor + columns : (columns == 1 ? 0 : cursor) }
        if u.up { cursor = cursor - columns >= 0 ? cursor - columns : (columns == 1 ? count - 1 : cursor) }
        if columns > 1 {
            if u.right { cursor = min(count - 1, cursor + 1) }
            if u.left { cursor = max(0, cursor - 1) }
        }
        if u.pageDown { cursor = min(count - 1, cursor + 6 * columns) }
        if u.pageUp { cursor = max(0, cursor - 6 * columns) }
        return cursor != old
    }

    /// Strips \C/\I so typewriter counts match visible characters.
    static func visibleCount(_ text: String) -> Int { stripCodes(text).count }
    static func stripCodes(_ t: String) -> String {
        t.replacingOccurrences(of: "\\\\[CIci]\\[\\d+\\]", with: "", options: .regularExpression)
    }
    /// Prefix of `text` containing `n` visible characters (codes kept intact).
    static func visiblePrefix(_ text: String, _ n: Int) -> String {
        var out = "", count = 0, k = text.startIndex
        while k < text.endIndex && count < n {
            if text[k] == "\\", let r = text.range(of: "^\\\\[CIci]\\[\\d+\\]", options: .regularExpression, range: k..<text.endIndex) {
                out += text[r]; k = r.upperBound; continue
            }
            out.append(text[k]); count += 1; k = text.index(after: k)
        }
        return out
    }
}
