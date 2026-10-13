// Lakon web runtime — Effekseer bridge. When the export bundles Effekseer for WebGL (MIT) and the project has
// effects/*.efkefc, MZ-format animations play their real effect: rendered on an offscreen WebGL canvas with
// MZ's matrices and viewport (rmmz_sprites.js Sprite_Animation._render) and composited into the 2D canvas.
// Without it, game.js draws the coloured stand-in.
"use strict";
(function (LK) {
  if (typeof window === "undefined" || !window.effekseer) return;
  const W = LK.W, H = LK.H, VIEW = 4096;
  const fx = LK.Effects = { ready: false, failed: false, effects: {}, canvas: null, gl: null, ctx: null };

  fx.init = () => {
    if (fx.canvas) return;
    const c = fx.canvas = document.createElement("canvas");
    c.width = W; c.height = H;
    const gl = fx.gl = c.getContext("webgl", { alpha: true, premultipliedAlpha: true, antialias: false, preserveDrawingBuffer: true }) || c.getContext("experimental-webgl");
    if (!gl) { fx.failed = true; return; }
    effekseer.initRuntime("effekseer/effekseer.wasm", () => {
      try { fx.ctx = effekseer.createContext(); fx.ctx.init(gl); fx.ready = true; } catch (e) { console.warn("Effekseer init failed", e); fx.failed = true; }
    }, () => { console.warn("Effekseer runtime failed to load"); fx.failed = true; });
  };

  /// EffectManager.load: one cached effect per name.
  fx.load = name => {
    if (!fx.ready) return null;
    if (fx.effects[name]) return fx.effects[name];
    const entry = fx.effects[name] = { loaded: false, failed: false, effect: null };
    entry.effect = fx.ctx.loadEffect("effects/" + encodeURIComponent(name) + ".efkefc", 1, () => { entry.loaded = true; }, () => { entry.failed = true; });
    return entry;
  };

  /// Gives an MZ-format AnimationPlayback a handle; `exists` keeps the animation playing until the effect ends.
  /// True when the real effect can be drawn for this playback (else the caller draws the stand-in).
  fx.canDraw = pb => fx.ready && !!pb.effectHandle && !(pb.effectHandle.entry && pb.effectHandle.entry.failed);

  fx.attach = pb => {
    const a = pb.animation;
    if (a.isMV || !a.effectName || fx.failed) return;
    if (!fx.ready) fx.init();
    const h = pb.effectHandle = { handle: null, entry: null, played: false,
      get exists() { if (fx.failed || (this.entry && this.entry.failed)) return false; if (!this.played) return true; return !!(this.handle && this.handle.exists); } };
    h.entry = fx.load(a.effectName);
  };

  /// Once per game frame (SceneManager.updateEffekseer).
  fx.update = () => { if (fx.ready) fx.ctx.update(); };

  /// Starts the handle when the animation's delay has passed (Sprite_Animation.update), then renders it centred on
  /// (x, y) in canvas pixels and draws the WebGL canvas into the 2D context `g`.
  fx.draw = (g, pb, x, y) => {
    const h = pb.effectHandle;
    if (!fx.ready || !h) return;
    if (!h.entry) h.entry = fx.load(pb.animation.effectName);
    if (!h.played) {
      if (!h.entry || !h.entry.loaded) return;
      h.handle = fx.ctx.play(h.entry.effect, 0, 0, 0); h.played = true;
    }
    if (!h.handle || !h.handle.exists) return;
    const a = pb.animation, r = Math.PI / 180, s = a.scale / 100;
    h.handle.setLocation(0, 0, 0);
    h.handle.setRotation(a.rotation.x * r, a.rotation.y * r, a.rotation.z * r);
    h.handle.setScale(s, s, s);
    h.handle.setSpeed(a.speed / 100);
    const gl = fx.gl;
    const p = -(VIEW / H);
    fx.ctx.setProjectionMatrix(new Float32Array([pb.mirror ? -1 : 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, p, 0, 0, 0, 1]));
    fx.ctx.setCameraMatrix(new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -10, 1]));
    // GL viewports start bottom-left; (x, y) is top-left based.
    gl.viewport(a.offsetX - VIEW / 2 + x, H - y - a.offsetY - VIEW / 2, VIEW, VIEW);
    fx.ctx.beginDraw(); fx.ctx.drawHandle(h.handle); fx.ctx.endDraw();
    gl.viewport(0, 0, W, H);
    g.save(); g.setTransform(1, 0, 0, 1, 0, 0); g.globalAlpha = 1; g.globalCompositeOperation = "source-over";
    g.drawImage(fx.canvas, 0, 0);
    g.restore();
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
  };
  fx.init();
})(LK);
