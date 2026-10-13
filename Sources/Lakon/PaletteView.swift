import AppKit
import LakonCore
import LakonRender
import SwiftUI

enum PaletteTab: String, CaseIterable, Identifiable {
    case A, B, C, D, E
    var id: String { rawValue }
    var setIndex: Int { ["A": 0, "B": 5, "C": 6, "D": 7, "E": 8][rawValue]! }
}

/// Palette contents in MZ order: tab A lists A1, A2, A3, A4 autotile kinds then A5; tabs B–E list 256 tiles in 8 columns.
func paletteIds(_ tab: PaletteTab, tileset: Tileset) -> [Int] {
    switch tab {
    case .A:
        var ids: [Int] = []
        let names = tileset.tilesetNames
        if !names[0].isEmpty { ids += (0..<16).map { TileID.make(kind: $0, shape: $0 >= 4 && $0 % 2 == 1 ? 3 : 47) } }
        if !names[1].isEmpty { ids += (16..<48).map { TileID.make(kind: $0, shape: 47) } }
        if !names[2].isEmpty { ids += (48..<80).map { TileID.make(kind: $0, shape: 15) } }  // walls preview: isolated shape
        if !names[3].isEmpty { ids += (80..<128).map { TileID.make(kind: $0, shape: (($0 - 80) / 8) % 2 == 1 ? 15 : 47) } }
        if !names[4].isEmpty { ids += (0..<128).map { TileID.A5 + $0 } }
        return ids
    default:
        guard !tileset.tilesetNames[tab.setIndex].isEmpty else { return [] }
        let base = (tab.setIndex - 5) * 256
        return (0..<256).map { base + $0 }
    }
}

/// Palette tile IDs are stored with a fixed shape for autotiles; placing normalises the shape.
final class PaletteNSView: NSView {
    var doc: EditorDocument!
    var tab: PaletteTab = .A
    var ids: [Int] = []
    let cols = 8
    var cellSize: CGFloat = 36
    /// When set, the view edits passability flags instead of picking a brush (Database → Tilesets).
    var passageEditor: ((Int) -> Void)?
    var flags: [Int]?
    private var dragStart: Int?
    private var dragEnd: Int?

    override var isFlipped: Bool { true }

    func reload() {
        ids = paletteIds(tab, tileset: passageTileset ?? doc.tileset)
        let rows = (ids.count + cols - 1) / cols
        setFrameSize(NSSize(width: CGFloat(cols) * cellSize, height: max(CGFloat(rows) * cellSize, 40)))
        needsDisplay = true
    }
    var passageTileset: Tileset?

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ts = passageTileset ?? doc.tileset
        let r = doc.renderer(for: ts)
        ctx.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor); ctx.fill(bounds)
        for (i, id) in ids.enumerated() {
            let rect = cellRect(i)
            guard rect.intersects(dirtyRect) else { continue }
            if (i / cols + i % cols) % 2 == 0 { ctx.setFillColor(NSColor(white: 0.22, alpha: 1).cgColor); ctx.fill(rect) }
            r.draw(id, in: ctx, x: rect.minX, y: rect.minY, size: cellSize)
            if let flags {
                let f = flags[TileID.isAutotile(id) ? TileID.make(kind: TileID.kind(id), shape: 0) : id]
                let mark = f & 0x10 != 0 ? "☆" : (f & 0x0f) == 0x0f ? "×" : "○"
                let color: NSColor = mark == "×" ? .systemRed : mark == "☆" ? .systemYellow : .white
                let s = NSAttributedString(string: mark, attributes: [.font: NSFont.boldSystemFont(ofSize: cellSize * 0.5), .foregroundColor: color,
                                                                     .strokeColor: NSColor.black, .strokeWidth: -3])
                let sz = s.size()
                s.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
            }
        }
        if passageEditor == nil, let sel = selectionRect() {
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(4); ctx.stroke(sel.insetBy(dx: 1, dy: 1))
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2); ctx.stroke(sel.insetBy(dx: 1, dy: 1))
        }
    }

    func cellRect(_ i: Int) -> CGRect {
        CGRect(x: CGFloat(i % cols) * cellSize, y: CGFloat(i / cols) * cellSize, width: cellSize, height: cellSize)
    }
    private func index(_ e: NSEvent) -> Int? {
        let p = convert(e.locationInWindow, from: nil)
        let c = Int(p.x / cellSize), r = Int(p.y / cellSize)
        guard c >= 0, c < cols, r >= 0 else { return nil }
        let i = r * cols + c
        return i < ids.count ? i : nil
    }
    private func selectionRect() -> CGRect? {
        guard let s = dragStart ?? ids.firstIndex(of: doc.brush.first?.first ?? -1) else { return nil }
        let e = dragEnd ?? (s + (doc.brush.first!.count - 1) + (doc.brush.count - 1) * cols)
        let a = cellRect(min(s % cols, e % cols) + min(s / cols, e / cols) * cols)
        let b = cellRect(max(s % cols, e % cols) + max(s / cols, e / cols) * cols)
        return a.union(b)
    }

    override func mouseDown(with event: NSEvent) {
        guard let i = index(event) else { return }
        if let edit = passageEditor { edit(ids[i]); needsDisplay = true; return }
        dragStart = i; dragEnd = i; commit()
    }
    override func mouseDragged(with event: NSEvent) {
        guard passageEditor == nil, let i = index(event) else { return }
        dragEnd = i; commit()
    }

    private func commit() {
        guard let s = dragStart, let e = dragEnd else { return }
        let c0 = min(s % cols, e % cols), c1 = max(s % cols, e % cols)
        let r0 = min(s / cols, e / cols), r1 = max(s / cols, e / cols)
        doc.brush = (r0...r1).map { r in (c0...c1).map { c in let i = r * cols + c; return i < ids.count ? ids[i] : 0 } }
        if doc.mode == .event { doc.mode = .map }
        needsDisplay = true
    }
}

struct PaletteView: NSViewRepresentable {
    @ObservedObject var doc: EditorDocument
    var tab: PaletteTab
    var cellSize: CGFloat = 36
    var tileset: Tileset? = nil
    var onPassage: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let v = PaletteNSView()
        scroll.documentView = v
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let v = scroll.documentView as? PaletteNSView else { return }
        v.doc = doc; v.tab = tab; v.cellSize = cellSize
        v.passageTileset = tileset; v.passageEditor = onPassage; v.flags = onPassage == nil ? nil : tileset?.flags
        _ = doc.revision
        v.reload()
    }
}
