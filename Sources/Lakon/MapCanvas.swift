import AppKit
import LakonCore
import LakonRender
import SwiftUI

/// The map editing surface. Draws only visible cells straight from tile IDs each frame,
/// so painting never needs a full-map re-render.
final class MapCanvasView: NSView {
    var doc: EditorDocument!
    private var dragStart: (Int, Int)?
    private var dragCurrent: (Int, Int)?
    private var strokeActive = false
    private var draggingEventId: Int?
    private var hover: (Int, Int)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var cell: CGFloat { CGFloat(tileSize) * doc.zoom }

    func syncSize() {
        let m = doc.map
        let size = NSSize(width: CGFloat(m.width) * cell, height: CGFloat(m.height) * cell)
        if frame.size != size { setFrameSize(size) }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let doc else { return }
        let m = doc.map, ts = doc.tileset, r = doc.renderer, c = cell
        ctx.interpolationQuality = .none
        ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor); ctx.fill(dirtyRect)
        let x0 = max(0, Int(dirtyRect.minX / c)), y0 = max(0, Int(dirtyRect.minY / c))
        let x1 = min(m.width, Int(ceil(dirtyRect.maxX / c))), y1 = min(m.height, Int(ceil(dirtyRect.maxY / c)))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 { for x in x0..<x1 {
            for z in 0..<4 { r.draw(m.tileId(x, y, z), in: ctx, x: CGFloat(x) * c, y: CGFloat(y) * c, size: c) }
        } }
        // Upper (☆) tiles are just drawn in layer order in the editor, like MZ.
        _ = ts

        // Grid
        if doc.mode != .map || doc.zoom >= 1 {
            ctx.setStrokeColor(NSColor(white: 0, alpha: doc.mode == .map ? 0.12 : 0.3).cgColor)
            ctx.setLineWidth(1)
            for x in x0...x1 { ctx.move(to: CGPoint(x: CGFloat(x) * c, y: CGFloat(y0) * c)); ctx.addLine(to: CGPoint(x: CGFloat(x) * c, y: CGFloat(y1) * c)) }
            for y in y0...y1 { ctx.move(to: CGPoint(x: CGFloat(x0) * c, y: CGFloat(y) * c)); ctx.addLine(to: CGPoint(x: CGFloat(x1) * c, y: CGFloat(y) * c)) }
            ctx.strokePath()
        }

        if doc.mode == .region { drawRegions(ctx, m, x0, y0, x1, y1) }
        drawEvents(ctx, m)
        drawStartPosition(ctx)

        // Rectangle preview / hover cursor
        if doc.mode != .event {
            if doc.tool == .rectangle, let s = dragStart, let e = dragCurrent {
                let rr = CGRect(x: CGFloat(min(s.0, e.0)) * c, y: CGFloat(min(s.1, e.1)) * c,
                                width: CGFloat(abs(s.0 - e.0) + 1) * c, height: CGFloat(abs(s.1 - e.1) + 1) * c)
                ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2); ctx.stroke(rr)
            } else if let h = hover {
                let bw = doc.mode == .map && doc.tool == .pencil ? (doc.brush.first?.count ?? 1) : 1
                let bh = doc.mode == .map && doc.tool == .pencil ? doc.brush.count : 1
                let rr = CGRect(x: CGFloat(h.0) * c, y: CGFloat(h.1) * c, width: CGFloat(bw) * c, height: CGFloat(bh) * c)
                ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(3); ctx.stroke(rr.insetBy(dx: 1, dy: 1))
                ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.5); ctx.stroke(rr.insetBy(dx: 1, dy: 1))
            }
        }
    }

    private func drawRegions(_ ctx: CGContext, _ m: GameMap, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        let c = cell
        for y in y0..<y1 { for x in x0..<x1 {
            let rid = m.regionId(x, y)
            guard rid > 0 else { continue }
            let hue = CGFloat((rid * 47) % 360) / 360
            ctx.setFillColor(NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 0.45).cgColor)
            let rr = CGRect(x: CGFloat(x) * c, y: CGFloat(y) * c, width: c, height: c)
            ctx.fill(rr)
            let s = NSAttributedString(string: "\(rid)", attributes: [.font: NSFont.boldSystemFont(ofSize: max(8, c * 0.35)), .foregroundColor: NSColor.white])
            s.draw(at: CGPoint(x: rr.minX + 3, y: rr.minY + 2))
        } }
    }

    private func drawEvents(_ ctx: CGContext, _ m: GameMap) {
        let c = cell
        for e in m.liveEvents {
            let rr = CGRect(x: CGFloat(e.x) * c, y: CGFloat(e.y) * c, width: c, height: c)
            let img = e.pages.first?.image ?? EventImage()
            if doc.mode == .event {
                ctx.setFillColor(NSColor(white: 1, alpha: 0.25).cgColor); ctx.fill(rr.insetBy(dx: 2, dy: 2))
            }
            if img.tileId > 0 {
                doc.renderer.draw(img.tileId, in: ctx, x: rr.minX, y: rr.minY, size: c)
            } else if let sheet = doc.characterSheet(img.characterName) {
                let f = CharacterSheet.frame(sheet: sheet, name: img.characterName, index: img.characterIndex, direction: img.direction, pattern: img.pattern)
                if let fr = sheet.cropping(to: f) {
                    let scale = c / CGFloat(tileSize)
                    let w = f.width * scale, h = f.height * scale
                    ctx.drawUpright(fr, in: CGRect(x: rr.midX - w / 2, y: rr.maxY - h, width: w, height: h))
                }
            }
            if doc.mode == .event {
                let selected = doc.selectedEventId == e.id
                ctx.setStrokeColor((selected ? NSColor.systemYellow : NSColor.white).cgColor)
                ctx.setLineWidth(selected ? 3 : 1.5)
                ctx.stroke(rr.insetBy(dx: 2, dy: 2))
            }
        }
    }

    private func drawStartPosition(_ ctx: CGContext) {
        let s = doc.project.system
        guard s.startMapId == doc.mapId else { return }
        let c = cell
        let rr = CGRect(x: CGFloat(s.startX) * c, y: CGFloat(s.startY) * c, width: c, height: c).insetBy(dx: 3, dy: 3)
        ctx.setStrokeColor(NSColor.systemGreen.cgColor); ctx.setLineWidth(3)
        ctx.stroke(rr)
        let t = NSAttributedString(string: "S", attributes: [.font: NSFont.boldSystemFont(ofSize: max(9, c * 0.3)), .foregroundColor: NSColor.systemGreen])
        t.draw(at: CGPoint(x: rr.minX + 3, y: rr.minY + 1))
    }

    // MARK: input

    private func cellAt(_ event: NSEvent) -> (Int, Int) {
        let p = convert(event.locationInWindow, from: nil)
        return (Int(floor(p.x / cell)), Int(floor(p.y / cell)))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = cellAt(event)
        if hover.map({ $0 != p }) ?? true {
            hover = p; needsDisplay = true
            if doc.map.isValid(p.0, p.1) {
                let rid = doc.map.regionId(p.0, p.1)
                doc.status = "(\(p.0), \(p.1))" + (rid > 0 ? "  region \(rid)" : "") + (doc.map.event(at: p.0, p.1).map { "  \($0.name)" } ?? "")
            }
        }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let (x, y) = cellAt(event)
        guard doc.map.isValid(x, y) else { return }
        if doc.mode == .event { eventMouseDown(event, x, y); return }
        if event.modifierFlags.contains(.option) || event.type == .rightMouseDown { pick(x, y); return }
        switch doc.tool {
        case .rectangle: dragStart = (x, y); dragCurrent = (x, y)
        case .fill:
            doc.edit { m in
                if doc.mode == .region { regionFill(&m, x, y) } else { m.floodFill(doc.brush[0][0], x, y) }
            }
        case .pencil, .eraser:
            doc.beginEdit(); strokeActive = true
            apply(x, y)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let (x, y) = cellAt(event)
        hover = (x, y)
        if doc.mode == .event {
            if let id = draggingEventId, doc.map.isValid(x, y) { dragCurrent = (x, y); doc.status = "Move event \(id) → (\(x), \(y))" }
            return
        }
        if doc.tool == .rectangle { dragCurrent = (x, y); needsDisplay = true; return }
        if strokeActive { apply(x, y) }
    }

    override func mouseUp(with event: NSEvent) {
        if doc.mode == .event {
            if let id = draggingEventId, let t = dragCurrent, let s = dragStart, t != s { doc.moveEvent(id, to: t.0, t.1); doc.selectedEventId = id }
            draggingEventId = nil; dragStart = nil; dragCurrent = nil
            return
        }
        if doc.tool == .rectangle, let s = dragStart, let e = dragCurrent {
            doc.edit { m in
                for y in min(s.1, e.1)...max(s.1, e.1) { for x in min(s.0, e.0)...max(s.0, e.0) { paintCell(&m, x, y) } }
            }
        }
        if strokeActive { doc.touched() }
        strokeActive = false; dragStart = nil; dragCurrent = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let (x, y) = cellAt(event)
        guard doc.map.isValid(x, y) else { return }
        if doc.mode != .event { pick(x, y); return }
        let menu = NSMenu()
        func item(_ title: String, _ action: @escaping () -> Void) {
            let it = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let target = MenuAction(action); it.target = target; it.representedObject = target
            menu.addItem(it)
        }
        if let e = doc.map.event(at: x, y) {
            item("Edit…") { self.doc.editingEvent = self.doc.map.events[e.id] ?? e }
            item("Delete") { self.doc.deleteEvent(e.id) }
        } else {
            item("New Event…") { self.doc.editingEvent = self.doc.createEvent(at: x, y) }
            menu.addItem(.separator())
            item("Quick Event: Treasure") { self.doc.quickTreasure(at: x, y, itemId: 1) }
            item("Quick Event: Transfer…") { self.doc.quickTransfer(at: x, y) }
        }
        menu.addItem(.separator())
        item("Set Player Starting Position") { self.doc.setStartPosition(x, y) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        if doc.mode == .event, let id = doc.selectedEventId, [51, 117].contains(Int(event.keyCode)) { doc.deleteEvent(id); return }
        if doc.mode == .event, let id = doc.selectedEventId, event.keyCode == 36 { doc.editingEvent = doc.map.events[id] ?? nil; return }
        super.keyDown(with: event)
    }

    private func eventMouseDown(_ event: NSEvent, _ x: Int, _ y: Int) {
        let existing = doc.map.event(at: x, y)
        doc.selectedEventId = existing?.id
        if event.clickCount == 2 {
            doc.editingEvent = existing ?? doc.createEvent(at: x, y)
            return
        }
        if let e = existing { draggingEventId = e.id; dragStart = (x, y); dragCurrent = (x, y) }
        needsDisplay = true
    }

    /// Option-click / right-click eyedropper, like MZ's right-click tile pick.
    private func pick(_ x: Int, _ y: Int) {
        if doc.mode == .region { doc.region = doc.map.regionId(x, y); return }
        let t = doc.map.topTile(x, y)
        if t > 0 { doc.brush = [[t]] }
    }

    private func apply(_ x: Int, _ y: Int) {
        var m = doc.map
        paintCell(&m, x, y)
        doc.map = m
        needsDisplay = true
    }

    private func paintCell(_ m: inout GameMap, _ x: Int, _ y: Int) {
        guard m.isValid(x, y) else { return }
        if doc.mode == .region { m.setTile(x, y, 5, doc.tool == .eraser ? 0 : doc.region); return }
        if doc.tool == .eraser { m.eraseTop(x, y); return }
        if doc.tool == .rectangle {
            // Rectangle tiles the brush pattern across the area.
            let b = doc.brush, s = dragStart ?? (x, y)
            let bx = ((x - min(s.0, dragCurrent?.0 ?? x)) % (b.first?.count ?? 1)), by = ((y - min(s.1, dragCurrent?.1 ?? y)) % b.count)
            if b[by][bx] > 0 { m.place(b[by][bx], x, y) }
        } else {
            doc.stamp(at: x, y, into: &m)
        }
    }

    private func regionFill(_ m: inout GameMap, _ x: Int, _ y: Int) {
        let target = m.regionId(x, y)
        var stack = [(x, y)], seen = Set<Int>()
        while let (cx, cy) = stack.popLast() {
            guard m.isValid(cx, cy), !seen.contains(cy * m.width + cx), m.regionId(cx, cy) == target else { continue }
            seen.insert(cy * m.width + cx)
            m.setTile(cx, cy, 5, doc.region)
            stack += [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
        }
    }
}

final class MenuAction: NSObject {
    let action: () -> Void
    init(_ a: @escaping () -> Void) { action = a }
    @objc func run() { action() }
}

struct MapCanvas: NSViewRepresentable {
    @ObservedObject var doc: EditorDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.backgroundColor = NSColor(white: 0.08, alpha: 1)
        let canvas = MapCanvasView()
        canvas.doc = doc
        scroll.documentView = canvas
        canvas.syncSize()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView as? MapCanvasView else { return }
        canvas.doc = doc
        _ = doc.revision
        canvas.syncSize()
    }
}
