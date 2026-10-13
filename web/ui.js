// Lakon web runtime — immediate-mode UI on a 2D canvas. Port of Sources/Lakon/SceneUI.swift.
// Coordinates follow the Swift code (SpriteKit, origin bottom-left, y up) so the scene code ports line by line;
// every call queues a draw with a z value, and end() draws them in z order.
"use strict";
(function (LK) {
  const W = 816, H = 624;
  LK.W = W; LK.H = H;
  const rgba = (c, a) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a === undefined ? (c[3] === undefined ? 1 : c[3]) : a})`;
  const C = (r, g, b, a) => [r, g, b, a === undefined ? 1 : a];
  const white = C(1, 1, 1), black = C(0, 0, 0);
  LK.Color = { rgba, C, white, black, gray: (w, a) => C(w, w, w, a) };
  const FONT = '"Avenir Next", "Avenir", "Segoe UI", "Helvetica Neue", Arial, sans-serif';

  class SceneUI {
    constructor(ctx) { this.ctx = ctx; this.draws = []; this.frame = 0; this.windowTone = [0, 0, 0, 0]; this.iconSheet = null; this.seq = 0; this.measureCache = {}; }
    begin() { this.draws = []; this.frame++; this.seq = 0; }
    end() {
      this.draws.sort((a, b) => a.z - b.z || a.s - b.s);
      const ctx = this.ctx;
      for (const d of this.draws) { ctx.save(); try { d.f(ctx); } finally { ctx.restore(); } }
    }
    push(z, f) { this.draws.push({ z: 100 + z, s: this.seq++, f }); }
    // y-up rect → canvas rect
    static cr(r) { return [r.x, H - r.y - r.h, r.w, r.h]; }
    static R(x, y, w, h) { return { x, y, w, h, get maxX() { return x + w; }, get maxY() { return y + h; }, get midX() { return x + w / 2; }, get midY() { return y + h / 2; }, get minX() { return x; }, get minY() { return y; } }; }

    get windowFill() { const t = this.windowTone; return C(LK.clamp(26 + t[0], 0, 255) / 255, LK.clamp(34 + t[1], 0, 255) / 255, LK.clamp(78 + t[2], 0, 255) / 255, 0.92); }
    roundRect(ctx, x, y, w, h, r) { ctx.beginPath(); if (ctx.roundRect) ctx.roundRect(x, y, w, h, r); else ctx.rect(x, y, w, h); }
    window(_key, r, z = 0, opacity = 1) {
      const fill = this.windowFill;
      this.push(z, ctx => {
        const [x, y, w, h] = SceneUI.cr(r);
        ctx.globalAlpha = opacity;
        this.roundRect(ctx, x, y, w, h, 10); ctx.fillStyle = rgba(fill); ctx.fill();
        ctx.lineWidth = 2; ctx.strokeStyle = "rgba(255,255,255,0.85)"; ctx.stroke();
      });
    }
    rect(_key, r, color, z = 0, corner = 0, stroke = null) {
      this.push(z, ctx => {
        const [x, y, w, h] = SceneUI.cr(r);
        if (corner > 0) this.roundRect(ctx, x, y, w, h, Math.min(corner, w / 2, h / 2)); else { ctx.beginPath(); ctx.rect(x, y, w, h); }
        ctx.fillStyle = rgba(color); ctx.fill();
        if (stroke) { ctx.lineWidth = 1.5; ctx.strokeStyle = rgba(stroke); ctx.stroke(); }
      });
    }
    cursor(key, r, z = 1) { const pulse = 0.2 + 0.1 * Math.sin(this.frame / 8); this.rect(key, r, C(1, 1, 1, pulse), z, 6, C(1, 1, 1, 0.55)); }
    font(size, bold) { return `${bold ? "600" : "500"} ${size}px ${FONT}`; }
    measure(text, size, bold) {
      const k = size + (bold ? "b" : "") + text;
      if (this.measureCache[k] !== undefined) return this.measureCache[k];
      this.ctx.save(); this.ctx.font = this.font(size, bold); const w = this.ctx.measureText(text).width; this.ctx.restore();
      if (Object.keys(this.measureCache).length > 4000) this.measureCache = {};
      return (this.measureCache[k] = w);
    }
    /// Returns the drawn width. align: "left" | "center" | "right".
    label(_key, text, p, o = {}) {
      const size = o.size || 22, color = o.color || white, align = o.align || "left", bold = !!o.bold, z = o.z === undefined ? 2 : o.z, alpha = o.alpha === undefined ? 1 : o.alpha;
      text = String(text);
      let w = this.measure(text, size, bold), sx = 1;
      if (o.maxWidth && w > o.maxWidth) { sx = o.maxWidth / w; w = o.maxWidth; }
      this.push(z, ctx => {
        ctx.font = this.font(size, bold); ctx.textAlign = align; ctx.textBaseline = "alphabetic"; ctx.globalAlpha = alpha;
        const y = H - p.y;
        ctx.translate(p.x, y); ctx.scale(sx, 1);
        ctx.fillStyle = "rgba(0,0,0,0.65)"; ctx.fillText(text, 1.5, 1.5);
        ctx.fillStyle = rgba(color); ctx.fillText(text, 0, 0);
      });
      return w;
    }
    /// Draws an image (or a sub-rect `src` = [sx, sy, sw, sh]) at `center` with `anchor` (0…1, y up), like SKSpriteNode.
    sprite(_key, img, center, o = {}) {
      if (!img || !(img.complete === undefined || img.complete) || !img.width) return;
      const src = o.src || [0, 0, img.width, img.height];
      const size = o.size || { w: src[2], h: src[3] };
      const anchor = o.anchor || { x: 0.5, y: 0.5 };
      const z = o.z === undefined ? 1 : o.z, alpha = o.alpha === undefined ? 1 : o.alpha;
      if (alpha <= 0) return;
      this.push(z, ctx => {
        ctx.globalAlpha = Math.min(1, alpha);
        ctx.globalCompositeOperation = SceneUI.blendOp(o.blend);
        ctx.translate(center.x, H - center.y);
        if (o.rotation) ctx.rotate(-o.rotation);
        ctx.scale(o.xScale === undefined ? 1 : o.xScale, o.yScale === undefined ? 1 : o.yScale);
        const dx = -anchor.x * size.w, dy = -(1 - anchor.y) * size.h;
        ctx.imageSmoothingEnabled = o.smooth !== false;
        ctx.drawImage(img, src[0], src[1], src[2], src[3], dx, dy, size.w, size.h);
        if (o.flash && o.flash[3] > 0.5) SceneUI.drawFlash(ctx, img, src, dx, dy, size.w, size.h, o.flash);
      });
    }
    /// MZ's Sprite.setBlendColor: rgb = mix(rgb, color, a) over the sprite's opaque pixels.
    static drawFlash(ctx, img, src, dx, dy, w, h, c) {
      const t = SceneUI.tintCanvas(img, src, c);
      ctx.globalCompositeOperation = "source-over"; ctx.globalAlpha *= c[3] / 255;
      ctx.drawImage(t, 0, 0, src[2], src[3], dx, dy, w, h);
    }
    static tintCanvas(img, src, c) {
      const cv = SceneUI._tint || (SceneUI._tint = document.createElement("canvas"));
      if (cv.width < src[2] || cv.height < src[3]) { cv.width = Math.max(cv.width, src[2]); cv.height = Math.max(cv.height, src[3]); }
      const g = cv.getContext("2d");
      g.globalCompositeOperation = "copy"; g.drawImage(img, src[0], src[1], src[2], src[3], 0, 0, src[2], src[3]);
      g.globalCompositeOperation = "source-in"; g.fillStyle = `rgb(${c[0]},${c[1]},${c[2]})`; g.fillRect(0, 0, src[2], src[3]);
      g.globalCompositeOperation = "source-over";
      return cv;
    }
    static blendOp(b) { return b === 1 || b === "add" ? "lighter" : b === 2 || b === "multiply" ? "multiply" : b === 3 || b === "screen" ? "screen" : "source-over"; }
    icon(key, index, p, size = 28, z = 2, alpha = 1) {
      const s = this.iconSheet;
      if (index <= 0 || !s || !s.width) return;
      const cols = Math.floor(s.width / 32);
      if (Math.floor(index / cols) >= Math.floor(s.height / 32)) return;
      this.sprite(key, s, { x: p.x + size / 2, y: p.y + size / 2 }, { src: [(index % cols) * 32, Math.floor(index / cols) * 32, 32, 32], size: { w: size, h: size }, z, alpha, smooth: false });
    }
    gauge(key, r, rate, colors, label, value, z = 2) {
      this.rect(key + ".bg", SceneUI.R(r.x, r.y, r.w, 8), C(0.1, 0.1, 0.1, 0.9), z, 3);
      const w = LK.clamp(rate, 0, 1) * r.w;
      if (w > 0) this.rect(key + ".fg", SceneUI.R(r.x, r.y, w, 8), colors[1], z + 0.1, 3);
      this.label(key + ".l", label, { x: r.x, y: r.y + 6 }, { size: 16, color: SceneUI.systemColor, bold: true, z: z + 0.2 });
      this.label(key + ".v", value, { x: r.x + r.w, y: r.y + 6 }, { size: 18, align: "right", z: z + 0.2 });
    }
    /// \C[n] colours and \I[n] icons.
    richText(key, text, p, size = 24, z = 2, alpha = 1) {
      let x = p.x, color = white, run = "", i = 0;
      const chars = [...text];
      const flush = () => { if (!run) return; x += this.label(key + "." + i, run, { x, y: p.y }, { size, color, z, alpha }); i++; run = ""; };
      for (let k = 0; k < chars.length;) {
        if (chars[k] === "\\" && k + 2 < chars.length && "CcIi".includes(chars[k + 1]) && chars[k + 2] === "[") {
          const close = chars.indexOf("]", k + 3);
          const n = close > 0 ? parseInt(chars.slice(k + 3, close).join(""), 10) : NaN;
          if (!isNaN(n)) {
            flush();
            if (chars[k + 1] === "C" || chars[k + 1] === "c") color = SceneUI.textColors[n] || white;
            else { this.icon(key + ".icon" + i, n, { x: x + 2, y: p.y - 6 }, size + 4, z, alpha); x += size + 8; i++; }
            k = close + 1; continue;
          }
        }
        run += chars[k]; k++;
      }
      flush();
      return x - p.x;
    }
    /// Window_Selectable-style list (rows, cursor, scrolling, optional columns and title).
    list(key, r, rows, cursor, o = {}) {
      const active = o.active === undefined ? true : o.active, rowHeight = o.rowHeight || 38, cols = Math.max(1, o.columns || 1), z = o.z === undefined ? 20 : o.z;
      this.window(key + ".w", r, z);
      let top = r.y + r.h - 12;
      if (o.title) { this.label(key + ".title", o.title, { x: r.x + 18, y: top - 28 }, { size: 20, color: SceneUI.systemColor, bold: true, z: z + 2 }); top -= 36; }
      const visibleRows = Math.max(1, Math.floor((top - r.y - 8) / rowHeight));
      const cur = cursor === null || cursor === undefined ? 0 : cursor;
      const firstRow = Math.max(0, Math.min(Math.floor(cur / cols) - visibleRows + 1, Math.ceil(rows.length / cols) - visibleRows));
      const start = Math.max(0, (cursor === null || cursor === undefined ? 0 : Math.max(0, firstRow)) * cols);
      const colW = (r.w - 24) / cols;
      for (let n = 0, i = start; i < Math.min(rows.length, start + visibleRows * cols); i++, n++) {
        const row = rows[i];
        const x = r.x + 12 + (n % cols) * colW, y = top - (Math.floor(n / cols) + 1) * rowHeight;
        const en = row.enabled === undefined ? true : row.enabled;
        if (active && cursor === i) this.cursor(key + ".c", SceneUI.R(x, y + 2, colW - 4, rowHeight - 4), z + 1);
        let tx = x + 10;
        if (row.icon > 0) { this.icon(key + ".i" + n, row.icon, { x: tx, y: y + (rowHeight - 28) / 2 }, 28, z + 2, en ? 1 : 0.45); tx += 34; }
        this.label(key + ".t" + n, row.text, { x: tx, y: y + rowHeight / 2 - 8 }, { size: 21, color: row.color || white, z: z + 2, alpha: en ? 1 : 0.45, maxWidth: colW - (tx - x) - (row.right ? 76 : 14) });
        if (row.right) this.label(key + ".r" + n, row.right, { x: x + colW - 16, y: y + rowHeight / 2 - 8 }, { size: 20, align: "right", z: z + 2, alpha: en ? 1 : 0.45 });
      }
      if (rows.length > start + visibleRows * cols) this.label(key + ".more", "▼", { x: r.x + r.w / 2, y: r.y + 2 }, { size: 14, align: "center", z: z + 2 });
      if (start > 0) this.label(key + ".less", "▲", { x: r.x + r.w / 2, y: r.y + r.h - 16 }, { size: 14, align: "center", z: z + 2 });
    }
    static move(cur, count, u, columns = 1) {
      if (count <= 0) return cur;
      let c = cur;
      if (u.down) c = c + columns < count ? c + columns : (columns === 1 ? 0 : c);
      if (u.up) c = c - columns >= 0 ? c - columns : (columns === 1 ? count - 1 : c);
      if (columns > 1) { if (u.right) c = Math.min(count - 1, c + 1); if (u.left) c = Math.max(0, c - 1); }
      if (u.pageDown) c = Math.min(count - 1, c + 6 * columns);
      if (u.pageUp) c = Math.max(0, c - 6 * columns);
      return c;
    }
    static stripCodes(t) { return t.replace(/\\[CIci]\[\d+\]/g, ""); }
    static visiblePrefix(text, n) {
      let out = "", count = 0, k = 0;
      const chars = [...text];
      while (k < chars.length && count < n) {
        if (chars[k] === "\\") { const m = /^\\[CIci]\[\d+\]/.exec(chars.slice(k).join("")); if (m) { out += m[0]; k += [...m[0]].length; continue; } }
        out += chars[k]; count++; k++;
      }
      return out;
    }
  }
  SceneUI.textColors = [
    white, C(0.13, 0.6, 0.87), C(1, 0.47, 0.47), C(0.4, 0.8, 0.25), C(0.6, 0.8, 1), C(0.8, 0.6, 1), C(1, 1, 0.6), C(0.62, 0.62, 0.62), C(0.75, 0.75, 0.75),
    C(0.13, 0.4, 0.85), C(0.85, 0.2, 0.2), C(0.2, 0.6, 0.2), C(0.2, 0.6, 0.85), C(0.6, 0.4, 0.85), C(1, 0.85, 0.2), black, C(0.52, 0.75, 1), C(1, 1, 0.25),
    C(1, 0.2, 0.2), black, C(0.88, 0.5, 0.25), C(0.94, 0.75, 0.25), C(0.13, 0.25, 0.5), C(0.5, 0.25, 0.5), C(0.5, 0.75, 0.25), C(0.6, 0.4, 0.2), C(0.5, 0.5, 1),
    C(1, 0.5, 1), C(0, 0.6, 0.25), C(0, 0.88, 0.4), C(0.63, 0.38, 0.88), C(0.75, 0.5, 1),
  ];
  SceneUI.hpColor = [C(0.88, 0.5, 0.25), C(0.94, 0.75, 0.25)];
  SceneUI.mpColor = [C(0.13, 0.4, 0.85), C(0.25, 0.63, 1)];
  SceneUI.tpColor = [C(0, 0.63, 0.25), C(0, 0.88, 0.4)];
  SceneUI.systemColor = C(0.52, 0.75, 1);
  LK.SceneUI = SceneUI;
  LK.R = SceneUI.R;
})(LK);
