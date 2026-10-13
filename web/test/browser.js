#!/usr/bin/env node
// Headless browser check of an exported web build (no npm dependencies; Chrome DevTools Protocol over Node's WebSocket).
//   node web/test/browser.js <export-folder> <steps.json> <out-dir>
// Steps: [{"wait": ms}, {"until": "js condition", "timeout": ms}, {"key": "z"|"ArrowUp"|…, "hold": ms}, {"shot": "name"}, {"eval": "js expression"}]
// Serves the folder over http://127.0.0.1, opens index.html?autostart, prints console errors, exits 1 on any.
"use strict";
const http = require("http"), fs = require("fs"), path = require("path"), { spawn } = require("child_process"), os = require("os");
const [root, stepsFile, outDir] = process.argv.slice(2);
const steps = JSON.parse(fs.readFileSync(stepsFile, "utf8"));
fs.mkdirSync(outDir, { recursive: true });
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const types = { ".html": "text/html", ".js": "text/javascript", ".png": "image/png", ".m4a": "audio/mp4", ".wav": "audio/wav", ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".json": "application/json", ".wasm": "application/wasm" };

const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(req.url.split("?")[0]));
  if (!p.startsWith(path.resolve(root)) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "Content-Type": types[path.extname(p).toLowerCase()] || "application/octet-stream" });
  fs.createReadStream(p).pipe(res);
});

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function main() {
  await new Promise(r => server.listen(0, "127.0.0.1", r));
  const port = server.address().port;
  const profile = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), "lakon-chrome-"));
  const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profile, "--window-size=816,624", "--autoplay-policy=no-user-gesture-required",
    "--no-first-run", "--no-default-browser-check", "--mute-audio", "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
  const wsUrl = await new Promise((ok, bad) => {
    let buf = "";
    chrome.stderr.on("data", d => { buf += d; const m = /DevTools listening on (ws:\/\/\S+)/.exec(buf); if (m) ok(m[1]); });
    setTimeout(() => bad(new Error("chrome did not start")), 15000);
  });
  const browserWs = new WebSocket(wsUrl);
  await new Promise(r => browserWs.addEventListener("open", r));
  let id = 0; const pending = {}; const handlers = [];
  browserWs.addEventListener("message", ev => {
    const m = JSON.parse(ev.data);
    if (m.id && pending[m.id]) { pending[m.id](m); delete pending[m.id]; } else handlers.forEach(h => h(m));
  });
  const send = (method, params, sessionId) => new Promise(ok => { const i = ++id; pending[i] = ok; browserWs.send(JSON.stringify({ id: i, method, params: params || {}, sessionId })); });
  const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
  const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
  const S = (m, p) => send(m, p, sessionId);
  const errors = [];
  handlers.push(m => {
    if (m.sessionId !== sessionId) return;
    if (m.method === "Runtime.exceptionThrown") errors.push("exception: " + (m.params.exceptionDetails.exception ? m.params.exceptionDetails.exception.description : m.params.exceptionDetails.text));
    if (m.method === "Runtime.consoleAPICalled") {
      const text = m.params.args.map(a => (a.value !== undefined ? a.value : a.description)).join(" ");
      if (m.params.type === "error") errors.push("console.error: " + text); else console.log("  [page]", text);
    }
    if (m.method === "Log.entryAdded" && m.params.entry.level === "error" && !/favicon/.test(m.params.entry.url || "")) errors.push("log: " + m.params.entry.text + " " + (m.params.entry.url || ""));
  });
  await S("Runtime.enable"); await S("Log.enable"); await S("Page.enable");
  await S("Page.bringToFront"); await S("Emulation.setFocusEmulationEnabled", { enabled: true });
  await S("Emulation.setDeviceMetricsOverride", { width: 816, height: 624, deviceScaleFactor: 1, mobile: false });
  await S("Page.navigate", { url: `http://127.0.0.1:${port}/index.html?autostart` });
  await sleep(1500);
  const keyInfo = k => {
    const named = { ArrowUp: 38, ArrowDown: 40, ArrowLeft: 37, ArrowRight: 39, Enter: 13, Escape: 27, " ": 32, Shift: 16, Backspace: 8 };
    const code = named[k] || k.toUpperCase().charCodeAt(0);
    const codeName = k.length === 1 ? (k === " " ? "Space" : "Key" + k.toUpperCase()) : k;
    return { key: k, code: codeName, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code };
  };
  for (const st of steps) {
    if (st.wait) await sleep(st.wait);
    if (st.key) {
      const k = keyInfo(st.key);
      await S("Input.dispatchKeyEvent", Object.assign({ type: "keyDown", text: st.key.length === 1 ? st.key : undefined }, k));
      await sleep(st.hold || 60);
      await S("Input.dispatchKeyEvent", Object.assign({ type: "keyUp" }, k));
      await sleep(40);
    }
    if (st.until) {
      const t0 = Date.now(); let ok = false;
      while (Date.now() - t0 < (st.timeout || 10000)) {
        const r = await S("Runtime.evaluate", { expression: "!!(" + st.until + ")", returnByValue: true });
        if (r.result.result.value === true) { ok = true; break; }
        await sleep(50);
      }
      if (!ok) errors.push("timeout waiting for: " + st.until);
    }
    if (st.eval) { const r = await S("Runtime.evaluate", { expression: st.eval, returnByValue: true }); console.log("  eval", st.eval.slice(0, 60), "→", JSON.stringify(r.result.result.value)); }
    if (st.shot) {
      const r = await S("Page.captureScreenshot", { format: "png" });
      fs.writeFileSync(path.join(outDir, st.shot + ".png"), Buffer.from(r.result.data, "base64"));
      console.log("  shot", st.shot);
    }
  }
  const exited = new Promise(r => chrome.on("exit", r));
  chrome.kill(); server.close(); await exited;
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) { /* Chrome may still be flushing */ }
  if (errors.length) { console.log("ERRORS:\n" + [...new Set(errors)].join("\n")); process.exit(1); }
  console.log("no page errors");
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(2); });
