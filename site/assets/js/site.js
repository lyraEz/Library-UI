/* Page behaviour: themes, parallax sky, copy buttons, Lua highlighting and the mobile menu. */
(function () {
  "use strict";
  var root = document.documentElement;
  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

  // ------------------------------------------------------------------ themes (same palettes as Lyra.Themes)
  var THEMES = {
    Lavender: { base: [19, 18, 29], card: [30, 28, 45], raised: [41, 37, 59], line: [78, 69, 101], accent: [188, 167, 246], accentDark: [111, 88, 161], text: [244, 239, 255], muted: [201, 193, 223], sheenA: [235, 211, 255], sheenB: [124, 120, 174], bg: [11, 10, 18], bg2: [15, 13, 24], surface: [21, 19, 32] },
    Midnight: { base: [14, 17, 29], card: [22, 27, 45], raised: [31, 38, 61], line: [64, 78, 112], accent: [140, 182, 252], accentDark: [64, 92, 158], text: [236, 242, 255], muted: [180, 192, 222], sheenA: [205, 222, 255], sheenB: [92, 112, 172], bg: [8, 10, 18], bg2: [11, 14, 24], surface: [16, 20, 33] },
    Rose: { base: [27, 17, 25], card: [42, 27, 38], raised: [56, 36, 50], line: [108, 72, 94], accent: [246, 170, 200], accentDark: [156, 80, 118], text: [255, 240, 247], muted: [228, 194, 210], sheenA: [255, 216, 234], sheenB: [172, 112, 142], bg: [16, 10, 15], bg2: [21, 13, 19], surface: [30, 19, 27] },
    Mint: { base: [13, 24, 22], card: [20, 37, 34], raised: [28, 50, 46], line: [58, 100, 91], accent: [137, 221, 187], accentDark: [52, 124, 100], text: [236, 255, 248], muted: [182, 220, 206], sheenA: [212, 255, 238], sheenB: [88, 150, 130], bg: [7, 14, 13], bg2: [10, 19, 17], surface: [15, 27, 25] },
    Ember: { base: [27, 19, 14], card: [41, 30, 22], raised: [55, 41, 30], line: [108, 83, 60], accent: [241, 201, 140], accentDark: [150, 106, 52], text: [255, 247, 235], muted: [228, 208, 182], sheenA: [255, 233, 204], sheenB: [172, 132, 92], bg: [16, 11, 8], bg2: [21, 15, 11], surface: [30, 22, 16] }
  };
  var VARS = { base: "--w-base", card: "--w-card", raised: "--w-raised", line: "--w-line", accent: "--w-accent", accentDark: "--w-accent-dark", text: "--w-text", muted: "--w-muted", sheenA: "--w-sheen-a", sheenB: "--w-sheen-b", bg: "--s-bg", bg2: "--s-bg-2", surface: "--s-surface" };
  var current = "Lavender";
  function rgbHex(c) { return "#" + c.map(function (v) { return ("0" + v.toString(16)).slice(-2); }).join(""); }
  function applyTheme(name, quiet) {
    var theme = THEMES[name];
    if (!theme) return;
    current = name;
    Object.keys(VARS).forEach(function (key) { root.style.setProperty(VARS[key], theme[key].join(" ")); });
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", rgbHex(theme.bg));
    document.querySelectorAll("[data-theme-pick]").forEach(function (button) {
      button.setAttribute("aria-pressed", String(button.getAttribute("data-theme-pick") === name));
    });
    try { localStorage.setItem("lyra-ui-theme", name); } catch (e) { /* storage can be blocked */ }
    starColor = null;
    if (!quiet) document.dispatchEvent(new CustomEvent("lyra-theme", { detail: name }));
  }
  function buildThemeCards() {
    var list = document.getElementById("themes-list");
    if (!list) return;
    Object.keys(THEMES).forEach(function (name) {
      var t = THEMES[name];
      var c = function (a, alpha) { return "rgb(" + a.join(" ") + (alpha ? " / " + alpha : "") + ")"; };
      var button = document.createElement("button");
      button.type = "button";
      button.className = "theme";
      button.setAttribute("data-theme-pick", name);
      button.setAttribute("aria-pressed", "false");
      button.innerHTML =
        '<span class="theme__mini" style="background:linear-gradient(115deg,' + c(t.sheenA, 0.12) + ',transparent),' + c(t.base) + '">' +
        '<i style="left:8px;top:8px;width:30px;bottom:8px;background:' + c(t.card) + '"></i>' +
        '<i style="left:12px;top:14px;width:22px;height:6px;background:' + c(t.accent) + '"></i>' +
        '<i style="left:46px;top:10px;right:10px;height:16px;background:' + c(t.card) + '"></i>' +
        '<i style="left:46px;top:32px;right:30px;height:16px;background:' + c(t.card) + '"></i>' +
        '<i style="right:10px;top:34px;width:16px;height:12px;border-radius:6px;background:' + c(t.accentDark) + '"></i>' +
        '<i style="left:46px;bottom:10px;width:56px;height:14px;border-radius:5px;background:' + c(t.accent) + '"></i></span>' +
        '<span class="theme__name">' + name + '<span class="theme__dots"><span style="background:' + c(t.accent) + '"></span><span style="background:' + c(t.accentDark) + '"></span><span style="background:' + c(t.card) + '"></span></span></span>';
      button.addEventListener("click", function () { applyTheme(name); });
      list.appendChild(button);
    });
  }

  // ------------------------------------------------------------------ Lua highlighting
  var KEYWORDS = /^(local|function|end|if|then|else|elseif|for|in|do|while|repeat|until|return|and|or|not|break)$/;
  var LITERALS = /^(nil|true|false|self)$/;
  var GLOBALS = /^(game|Enum|Instance|Vector2|Vector3|UDim2|UDim|Color3|task|print|loadstring|workspace|pcall|ipairs|pairs|tostring|tonumber|math|string|table|Lyra|setclipboard)$/;
  var TOKENS = /(--\[\[[\s\S]*?\]\]|--[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|\[\[[\s\S]*?\]\])|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][\w]*)/g;
  function escapeHtml(text) { return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function highlight(code) {
    var source = code.textContent;
    var out = "", last = 0, match;
    TOKENS.lastIndex = 0;
    while ((match = TOKENS.exec(source))) {
      out += escapeHtml(source.slice(last, match.index));
      var token = match[0], cls = null;
      if (match[1]) cls = "tok-com";
      else if (match[2]) cls = "tok-str";
      else if (match[3]) cls = "tok-num";
      else if (KEYWORDS.test(token)) cls = "tok-key";
      else if (LITERALS.test(token)) cls = "tok-lit";
      else if (GLOBALS.test(token)) cls = "tok-glob";
      else if (source.charAt(match.index - 1) === ":" || /^\s*\(/.test(source.slice(match.index + token.length, match.index + token.length + 2))) cls = "tok-fn";
      out += cls ? '<span class="' + cls + '">' + escapeHtml(token) + "</span>" : escapeHtml(token);
      last = match.index + token.length;
    }
    code.innerHTML = out + escapeHtml(source.slice(last));
  }

  // ------------------------------------------------------------------ copy buttons
  function copyFrom(button) {
    var target = document.querySelector(button.getAttribute("data-copy"));
    if (!target) return;
    var text = target.textContent;
    var done = function () {
      button.classList.add("is-done");
      var label = button.lastChild;
      var before = label.textContent;
      label.textContent = "Copied";
      setTimeout(function () { button.classList.remove("is-done"); label.textContent = before; }, 1600);
    };
    var select = function () {
      var range = document.createRange();
      range.selectNodeContents(target);
      var selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, select);
    } else {
      select();
    }
  }

  // ------------------------------------------------------------------ sky: stars on a canvas, layers in parallax
  var canvas = document.getElementById("stars");
  var ctx = canvas && canvas.getContext("2d");
  var stars = [], starColor = null, pointer = { x: 0, y: 0, tx: 0, ty: 0 }, heroVisible = true;
  function seed() {
    stars = [];
    var count = Math.round(Math.min(320, (canvas.clientWidth * canvas.clientHeight) / 4200));
    for (var i = 0; i < count; i++) {
      var depth = Math.random();
      stars.push({ x: Math.random(), y: Math.random(), r: 0.35 + depth * 1.25, depth: depth, a: 0.35 + Math.random() * 0.6, speed: 0.4 + Math.random() * 1.6, phase: Math.random() * 6.28 });
    }
  }
  function resizeCanvas() {
    if (!canvas) return;
    var ratio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(canvas.clientWidth * ratio);
    canvas.height = Math.round(canvas.clientHeight * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    seed();
  }
  function drawStars(time) {
    if (!ctx) return;
    if (!starColor) starColor = getComputedStyle(root).getPropertyValue("--w-sheen-a").trim().split(/\s+/).join(",");
    var w = canvas.clientWidth, h = canvas.clientHeight;
    ctx.clearRect(0, 0, w, h);
    var scroll = window.scrollY || 0;
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var twinkle = reduced.matches ? 1 : 0.65 + 0.35 * Math.sin(time * 0.001 * s.speed + s.phase);
      var x = s.x * w + pointer.x * s.depth * 26;
      var y = s.y * h + pointer.y * s.depth * 18 - scroll * s.depth * 0.25;
      y = ((y % h) + h) % h;
      ctx.globalAlpha = s.a * twinkle;
      ctx.fillStyle = s.depth > 0.92 ? "rgb(255,255,255)" : "rgb(" + starColor + ")";
      ctx.beginPath();
      ctx.arc(x, y, s.r, 0, 6.2832);
      ctx.fill();
      if (s.depth > 0.96) {
        ctx.globalAlpha = s.a * twinkle * 0.25;
        ctx.beginPath();
        ctx.arc(x, y, s.r * 4, 0, 6.2832);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }
  var layers = Array.prototype.slice.call(document.querySelectorAll(".sky__layer[data-depth]"));
  var drifts = Array.prototype.slice.call(document.querySelectorAll(".drift[data-scroll]"));
  var tilt = document.getElementById("hero-tilt");
  function frame(time) {
    pointer.x += (pointer.tx - pointer.x) * 0.06;
    pointer.y += (pointer.ty - pointer.y) * 0.06;
    var scroll = window.scrollY || 0;
    if (heroVisible) {
      layers.forEach(function (layer) {
        var depth = parseFloat(layer.getAttribute("data-depth")) || 0;
        var speed = parseFloat(layer.getAttribute("data-scroll")) || 0;
        layer.style.transform = "translate3d(" + (pointer.x * depth * 120).toFixed(2) + "px," + (scroll * speed + pointer.y * depth * 80).toFixed(2) + "px,0)";
      });
      drawStars(time);
      if (tilt && window.innerWidth > 920) {
        tilt.style.transform = "rotateY(" + (-9 + pointer.x * 5).toFixed(2) + "deg) rotateX(" + (5 - pointer.y * 4).toFixed(2) + "deg)";
      }
    }
    var vh = window.innerHeight;
    drifts.forEach(function (item) {
      var rect = item.parentElement.getBoundingClientRect();
      if (rect.bottom < -200 || rect.top > vh + 200) return;
      var speed = parseFloat(item.getAttribute("data-scroll")) || 0;
      item.style.transform = "translate3d(0," + ((rect.top - vh / 2) * -speed).toFixed(2) + "px,0)";
    });
    if (!reduced.matches) requestAnimationFrame(frame);
  }

  // ------------------------------------------------------------------ boot
  document.addEventListener("DOMContentLoaded", function () {
    buildThemeCards();
    var saved = null;
    try { saved = localStorage.getItem("lyra-ui-theme"); } catch (e) { saved = null; }
    applyTheme(THEMES[saved] ? saved : "Lavender", true);

    document.querySelectorAll("code.lua").forEach(highlight);
    document.addEventListener("click", function (event) {
      var button = event.target.closest("[data-copy]");
      if (button) copyFrom(button);
    });

    var navToggle = document.getElementById("nav-toggle");
    var nav = document.querySelector(".nav");
    if (navToggle && nav) {
      navToggle.addEventListener("click", function () {
        var open = !nav.classList.contains("is-open");
        nav.classList.toggle("is-open", open);
        navToggle.setAttribute("aria-expanded", String(open));
      });
      nav.querySelectorAll(".nav__links a").forEach(function (link) {
        link.addEventListener("click", function () { nav.classList.remove("is-open"); navToggle.setAttribute("aria-expanded", "false"); });
      });
    }

    var heroFrame = document.getElementById("hero-frame");
    if (heroFrame && "ResizeObserver" in window) {
      new ResizeObserver(function () { heroFrame.style.setProperty("--hero-scale", (heroFrame.clientWidth / 820).toFixed(4)); }).observe(heroFrame);
    }

    if (canvas) {
      resizeCanvas();
      window.addEventListener("resize", resizeCanvas);
      var hero = document.querySelector(".hero");
      hero.addEventListener("pointermove", function (event) {
        var rect = hero.getBoundingClientRect();
        pointer.tx = (event.clientX - rect.left) / rect.width - 0.5;
        pointer.ty = (event.clientY - rect.top) / rect.height - 0.5;
      });
      hero.addEventListener("pointerleave", function () { pointer.tx = 0; pointer.ty = 0; });
      if ("IntersectionObserver" in window) {
        new IntersectionObserver(function (entries) { heroVisible = entries[0].isIntersecting; }).observe(hero);
      }
      requestAnimationFrame(function (time) { drawStars(time); frame(time); });
    }
  });

  window.LyraSite = {
    themes: THEMES,
    applyTheme: applyTheme,
    currentTheme: function () { return current; },
    highlight: highlight
  };
})();
