// Lakon web runtime — audio. Port of Sources/Lakon/AudioPlayer.swift on WebAudio: BGM/BGS loop (honouring
// RPG Maker LOOPSTART/LOOPLENGTH, stored in the export manifest), ME interrupts and then resumes the BGM, SE pool,
// pitch (playbackRate), pan and fades. Over file:// (no fetch) it falls back to <audio> elements.
"use strict";
(function (LK) {
  class AudioPlayer {
    constructor(manifest) {
      this.manifest = manifest || {};            // "bgm/Name" → { file, loopStart, loopLength } (loop points in seconds)
      this.ctx = null; this.buffers = {}; this.loading = {};
      this.ch = { bgm: null, bgs: null, me: null };
      this.bgmPausedForMe = null;
      this.volumes = Object.assign({ bgm: 0.9, bgs: 0.9, me: 0.9, se: 0.9 }, JSON.parse(localStorage.getItem("lakonVolumes") || "{}"));
      this.useElements = location.protocol === "file:";
    }
    saveVolumes() { localStorage.setItem("lakonVolumes", JSON.stringify(this.volumes)); }
    unlock() {
      if (this.useElements) return;
      if (!this.ctx) { const AC = window.AudioContext || window.webkitAudioContext; if (AC) this.ctx = new AC(); }
      if (this.ctx && this.ctx.state === "suspended") this.ctx.resume();
    }
    entry(folder, name) { return this.manifest[folder + "/" + name]; }
    load(folder, name) {
      const key = folder + "/" + name, e = this.entry(folder, name);
      if (!e || !this.ctx) return Promise.resolve(null);
      if (this.buffers[key]) return Promise.resolve(this.buffers[key]);
      if (!this.loading[key]) {
        this.loading[key] = fetch(e.file).then(r => r.arrayBuffer()).then(b => new Promise((ok, bad) => this.ctx.decodeAudioData(b, ok, bad)))
          .then(buf => (this.buffers[key] = buf)).catch(err => { console.warn("audio", key, err); return null; });
      }
      return this.loading[key];
    }
    handle(cmds) {
      for (const c of cmds) {
        switch (c.t) {
          case "playBgm": if (this.ch.me && this.ch.me.playing) { this.bgmPausedForMe = c.f; break; } this.play("bgm", c.f, true); break;
          case "stopBgm": this.stop("bgm"); this.bgmPausedForMe = null; break;
          case "fadeOutBgm": this.fade("bgm", c.s); break;
          case "playBgs": this.play("bgs", c.f, true); break;
          case "stopBgs": this.stop("bgs"); break;
          case "fadeOutBgs": this.fade("bgs", c.s); break;
          case "playMe": {
            const cur = this.ch.bgm;
            if (cur && cur.playing) { this.bgmPausedForMe = cur.file; this.stop("bgm"); }
            this.play("me", c.f, false, () => {
              const b = this.bgmPausedForMe; this.bgmPausedForMe = null;
              if (b) { this.play("bgm", b, true); const ch = this.ch.bgm; if (ch) { ch.fadeIn = true; ch.fadeTotal = 60; ch.fadeFrames = 60; ch.setVolume(0); } }
            });
            break;
          }
          case "playSe": this.play("se", c.f, false); break;
          case "stopSe": for (const s of this.seList || []) s.stop(); this.seList = []; break;
        }
      }
    }
    update() {
      for (const k of ["bgm", "bgs"]) {
        const c = this.ch[k]; if (!c || c.fadeFrames <= 0) continue;
        c.fadeFrames--;
        const t = c.fadeFrames / Math.max(1, c.fadeTotal);
        c.setVolume(c.baseVolume * (c.fadeIn ? 1 - t : t));
        if (c.fadeFrames === 0 && !c.fadeIn) this.stop(k);
        if (c.fadeFrames === 0) c.fadeIn = false;
      }
    }
    stopAll() { for (const k of ["bgm", "bgs", "me"]) this.stop(k); for (const s of this.seList || []) s.stop(); this.seList = []; }
    stop(k) { const c = this.ch[k]; if (c) c.stop(); this.ch[k] = null; }
    fade(k, seconds) { const c = this.ch[k]; if (!c || !c.playing) return; if (seconds <= 0) { this.stop(k); return; } c.fadeIn = false; c.fadeTotal = seconds * 60; c.fadeFrames = seconds * 60; }
    play(folder, f, loop, onEnd) {
      if (!f || !f.name) return;
      const e = this.entry(folder, f.name); if (!e) return;
      const base = f.volume / 100 * (this.volumes[folder] === undefined ? 0.9 : this.volumes[folder]);
      const rate = Math.max(50, Math.min(150, f.pitch)) / 100, pan = f.pan / 100;
      const chan = this.useElements ? new ElementChannel(e, base, rate, loop, onEnd) : new BufferChannel(this, folder, f.name, e, base, rate, pan, loop, onEnd);
      chan.file = f; chan.baseVolume = base;
      if (folder === "se") { this.seList = (this.seList || []).filter(s => s.playing).concat([chan]).slice(-8); return; }
      this.stop(folder); this.ch[folder] = chan;
    }
  }

  class BufferChannel {
    constructor(player, folder, name, entry, volume, rate, pan, loop, onEnd) {
      this.playing = true; this.fadeFrames = 0; this.fadeTotal = 0; this.fadeIn = false; this.stopped = false;
      const ctx = player.ctx; if (!ctx) { this.playing = false; return; }
      this.gain = ctx.createGain(); this.gain.gain.value = volume;
      let node = this.gain;
      if (ctx.createStereoPanner) { this.panner = ctx.createStereoPanner(); this.panner.pan.value = pan; this.gain.connect(this.panner); node = this.panner; }
      node.connect(ctx.destination);
      player.load(folder, name).then(buf => {
        if (!buf || this.stopped) return;
        const src = ctx.createBufferSource(); src.buffer = buf; src.playbackRate.value = rate;
        if (loop) {
          src.loop = true;
          if (entry.loopLength > 0 && entry.loopStart + entry.loopLength <= buf.duration + 0.01) { src.loopStart = entry.loopStart; src.loopEnd = entry.loopStart + entry.loopLength; }
        } else src.onended = () => { this.playing = false; if (!this.stopped && onEnd) onEnd(); };
        src.connect(this.gain); src.start(); this.src = src;
      });
    }
    setVolume(v) { if (this.gain) this.gain.gain.value = v; }
    stop() { this.stopped = true; this.playing = false; try { if (this.src) this.src.stop(); } catch (e) { /* not started */ } if (this.gain) this.gain.disconnect(); }
  }

  class ElementChannel {
    constructor(entry, volume, rate, loop, onEnd) {
      this.playing = true; this.fadeFrames = 0; this.fadeTotal = 0; this.fadeIn = false;
      const a = this.a = new Audio(entry.file);
      a.volume = Math.min(1, volume); a.playbackRate = rate; a.loop = loop;
      a.onended = () => { this.playing = false; if (onEnd) onEnd(); };
      a.play().catch(() => { this.playing = false; });
    }
    setVolume(v) { this.a.volume = Math.max(0, Math.min(1, v)); }
    stop() { this.playing = false; this.a.onended = null; this.a.pause(); }
  }
  LK.AudioPlayer = AudioPlayer;
})(LK);
