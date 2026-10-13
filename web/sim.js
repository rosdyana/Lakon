#!/usr/bin/env node
// Parity check: node web/sim.js <project> <script.json> <out.txt>
// Runs the web runtime headless with the same driver rules and snapshot format as LakonCore's Simulation.swift.
"use strict";
const fs = require("fs"), path = require("path");
const LK = require("./core-data.js");
global.LK = LK;
for (const f of ["core-world.js", "core-battle.js", "core-script.js"]) require("./" + f);

function loadProject(root) {
  const files = {};
  const dataDir = path.join(root, "data");
  for (const f of fs.readdirSync(dataDir)) if (f.endsWith(".json")) files[f] = JSON.parse(fs.readFileSync(path.join(dataDir, f), "utf8"));
  files.__plugins = loadPlugins(root);
  return new LK.Project(files);
}
function loadPlugins(root) {
  const dir = path.join(root, "plugins");
  if (!fs.existsSync(dir)) return [];
  let entries;
  const listFile = path.join(dir, "plugins.json");
  if (fs.existsSync(listFile)) entries = JSON.parse(fs.readFileSync(listFile, "utf8")).filter(e => e.status !== false).map(e => ({ name: e.name, parameters: e.parameters || {} }));
  else entries = fs.readdirSync(dir).filter(f => f.endsWith(".js")).sort().map(f => ({ name: f.slice(0, -3), parameters: {} }));
  return entries.filter(e => fs.existsSync(path.join(dir, e.name + ".js"))).map(e => Object.assign(e, { source: fs.readFileSync(path.join(dir, e.name + ".js"), "utf8") }));
}

const fx = (x, d) => { const sc = Math.pow(10, d), n = LK.rnd(x * sc), a = Math.abs(n); const fp = String(a % sc); return (n < 0 ? "-" : "") + Math.trunc(a / sc) + "." + "0".repeat(d - fp.length) + fp; };
const f4 = x => fx(x, 4), f2 = x => fx(x, 2), f1 = x => fx(x, 1);
function snapshot(w, frame) {
  const s = w.state, keys = d => Object.keys(d).map(Number).sort((a, b) => a - b);
  const sw = keys(s.switches).filter(k => s.switches[k]).join(",");
  const vars = keys(s.variables).map(k => k + ":" + s.variables[k]).join(",");
  const items = keys(s.items).map(k => k + ":" + s.items[k]).join(",");
  const selfs = Object.keys(s.selfSwitches).sort().join(";");
  const party = w.allMembers.map(a => `${a.actorId}:${a.hp}/${a.mp}/${a.tp}/L${a.level}/E${a.currentExp}/${a.states.join(".")}`).join(",");
  const evs = w.events.map(e => `${e.eventId}@${e.x},${e.y},${e.direction},${e.pageIndex}`).join(" ");
  let line = `f=${frame} m=${s.mapId} p=${w.player.x},${w.player.y},${w.player.direction} r=${f4(w.player.realX)},${f4(w.player.realY)}`;
  line += ` g=${s.gold} sw=[${sw}] v=[${vars}] it=[${items}] ss=[${selfs}] party=[${party}] ev=[${evs}]`;
  line += " msg=" + (w.message ? w.message.text.split("\n").join("/") + "#" + w.message.visibleChars : "-");
  if (w.battle) { const b = w.battle; line += ` battle=${b.phase} t${b.turnCount} log=${b.log.join("|")} en=[${b.enemies.map(e => e.hp).join(",")}]`; }
  const pics = keys(s.screen.pictures).map(k => { const p = s.screen.pictures[k]; return `${k}:${p.name}@${f2(p.x)},${f2(p.y)},${f1(p.opacity)}`; }).join(",");
  line += ` pic=[${pics}] par=${s.parallax.name}:${f4(s.parallax.autoX)} bright=${f2(w.brightness)}`;
  return line;
}
function drive(w) {
  if (w.nameInput) { const a = w.actor(w.nameInput.actorId); if (a) a.setName("Hero"); w.nameInput = null; }
  if (w.shop) w.shop = null;
  if (w.requestMenu || w.requestSave) { w.requestMenu = false; w.requestSave = false; }
  const b = w.battle;
  if (b && b.phase === "input" && !b.isBusy) {
    if (b.waitingForPartyCommand) b.commandFight();
    else if (b.inputActor) { const i = b.enemies.findIndex(e => e.isAlive); b.commandAttack(i < 0 ? 0 : i); }
  }
}
function run(project, script) {
  const w = new LK.GameWorld(project, new LK.SeededRandom(script.seed === undefined ? 1 : script.seed));
  w.newGame();
  const out = []; let frame = 0;
  for (const st of script.steps || []) {
    for (let k = 0; k < Math.max(0, st.frames === undefined ? 1 : st.frames); k++) {
      drive(w);
      const i = LK.newInput({ dir4: st.dir || 0, ok: !!st.ok, cancel: !!st.cancel, dash: !!st.dash });
      if (w.message && w.message.isTextComplete && frame % 2 === 0) i.ok = true;
      w.update(i);
      frame++;
      out.push(snapshot(w, frame));
    }
  }
  return out;
}
module.exports = { run, loadProject, snapshot };
if (require.main === module) {
  const [root, scriptFile, outFile] = process.argv.slice(2);
  const lines = run(loadProject(root), JSON.parse(fs.readFileSync(scriptFile, "utf8")));
  fs.writeFileSync(outFile, lines.join("\n") + "\n");
  console.log("wrote " + outFile);
}
