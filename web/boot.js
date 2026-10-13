// Lakon web runtime — boot: scale the 816×624 canvas to the window, wait for a click/key (browsers only
// allow audio after a user gesture, and itch.io embeds need focus), then start the game.
"use strict";
(function () {
  const game = window.LAKON_GAME;
  const canvas = document.getElementById("game"), overlay = document.getElementById("start");
  const fit = () => {
    const s = Math.min(window.innerWidth / LK.W, window.innerHeight / LK.H);
    canvas.style.width = Math.floor(LK.W * s) + "px"; canvas.style.height = Math.floor(LK.H * s) + "px";
  };
  window.addEventListener("resize", fit); fit();
  if (!game) { overlay.textContent = "Missing data.js — re-export the game from Lakon."; return; }
  document.title = game.data["System.json"].gameTitle || "Lakon Game";
  const g = new LK.Game(canvas, game);
  window.lakonGame = g;
  // Preload the system images and the first map's tilesets so the title appears complete.
  g.images.preload(game.preload || []);
  let started = false;
  const go = () => {
    if (started) return; started = true;
    g.audio.unlock(); overlay.remove(); canvas.focus(); g.start();
  };
  overlay.addEventListener("click", go);
  window.addEventListener("keydown", e => { if (!started) { e.preventDefault(); go(); } }, { capture: true });
  if (new URLSearchParams(location.search).has("autostart")) go();
})();
