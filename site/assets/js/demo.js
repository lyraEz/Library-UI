/* A browser replica of the Lyra UI window for the playground and the component cards.
   It follows the same layout rules as the Luau library: 196 px rail with labels from 760 px,
   a 60 px icon rail below that, a drawer under 520 px and compact rows under 470 px of content. */
(function () {
  "use strict";
  var Icons = window.LyraIcons;
  var KIND = { info: "var(--w-accent)", success: "var(--w-green)", warning: "var(--w-gold)", error: "var(--w-red)" };
  var GLYPH = { info: "info", success: "check", warning: "alert", error: "x" };
  var FLIGHT = 420;

  function $(selector, scope) { return (scope || document).querySelector(selector); }
  function $$(selector, scope) { return Array.prototype.slice.call((scope || document).querySelectorAll(selector)); }
  function el(html) {
    var holder = document.createElement("div");
    holder.innerHTML = html.trim();
    var node = holder.firstElementChild;
    Icons.hydrate(node);
    return node;
  }
  function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }
  function keyName(event) {
    var code = event.code || "";
    if (/^Key[A-Z]$/.test(code)) return code.slice(3);
    var digits = { Digit0: "Zero", Digit1: "One", Digit2: "Two", Digit3: "Three", Digit4: "Four", Digit5: "Five", Digit6: "Six", Digit7: "Seven", Digit8: "Eight", Digit9: "Nine" };
    if (digits[code]) return digits[code];
    var named = { ControlRight: "RightControl", ControlLeft: "LeftControl", ShiftRight: "RightShift", ShiftLeft: "LeftShift", AltRight: "RightAlt", AltLeft: "LeftAlt", ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right", Enter: "Return" };
    return named[code] || code || event.key;
  }

  // ------------------------------------------------------------------ toasts
  function toast(container, spec) {
    var kind = KIND[spec.kind] ? spec.kind : "info";
    var duration = spec.duration == null ? 4 : spec.duration;
    var node = el('<div class="lw-toast" role="status"><span class="lw-toast__badge"><i data-icon="' + (spec.icon || GLYPH[kind]) + '"></i></span><div class="lw-toast__text"><b></b><span></span></div>' +
      (duration > 0 ? '<span class="lw-toast__bar"></span>' : "") + "</div>");
    node.style.setProperty("--k", KIND[kind]);
    $(".lw-toast__text b", node).textContent = spec.title;
    $(".lw-toast__text span", node).textContent = spec.text || "";
    if (!spec.text) $(".lw-toast__text span", node).remove();
    var bar = $(".lw-toast__bar", node);
    if (bar) bar.style.animationDuration = duration + "s";
    var closed = false;
    function dismiss() {
      if (closed) return;
      closed = true;
      node.classList.add("is-out");
      setTimeout(function () { node.remove(); }, 220);
    }
    node.addEventListener("click", dismiss);
    container.appendChild(node);
    // The oldest toast leaves when a new one goes past the limit (4 in a window, fewer in a small card).
    var live = $$(".lw-toast:not(.is-out)", container);
    if (live.length > (spec.max || 4)) live[0].click();
    if (duration > 0) setTimeout(dismiss, duration * 1000);
    return dismiss;
  }

  // ------------------------------------------------------------------ shared controls
  function wireSwitch(button, onChange) {
    button.addEventListener("click", function () {
      var on = button.getAttribute("aria-checked") !== "true";
      button.setAttribute("aria-checked", String(on));
      if (onChange) onChange(on);
    });
  }
  function wireSlider(slider, onChange) {
    var min = parseFloat(slider.getAttribute("data-min")) || 0;
    var max = parseFloat(slider.getAttribute("data-max")) || 100;
    var suffix = slider.getAttribute("data-suffix") || "";
    var value = parseFloat(slider.getAttribute("data-value")) || min;
    var track = $(".lw-track", slider), fill = $(".lw-fill", slider), knob = $(".lw-knob", slider), out = $("output", slider);
    function show() {
      var ratio = (value - min) / (max - min);
      fill.style.width = (ratio * 100) + "%";
      knob.style.left = (ratio * 100) + "%";
      out.textContent = value + suffix;
    }
    function at(x) {
      var rect = track.getBoundingClientRect();
      var next = Math.round(min + clamp((x - rect.left) / rect.width, 0, 1) * (max - min));
      if (next !== value) { value = next; show(); if (onChange) onChange(value); }
    }
    track.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      track.setPointerCapture(event.pointerId);
      at(event.clientX);
      function move(e) { at(e.clientX); }
      function up() { track.removeEventListener("pointermove", move); track.removeEventListener("pointerup", up); track.removeEventListener("pointercancel", up); }
      track.addEventListener("pointermove", move);
      track.addEventListener("pointerup", up);
      track.addEventListener("pointercancel", up);
    });
    show();
  }
  function wireStepper(stepper, format, onChange) {
    var values = (stepper.getAttribute("data-values") || "").split(",").map(Number);
    var value = Number(stepper.getAttribute("data-value"));
    var out = $("output", stepper);
    var buttons = $$(".lw-btn", stepper);
    function show() { out.textContent = format(value); }
    function step(direction) {
      var index = 0;
      values.forEach(function (item, i) { if (item <= value) index = i; });
      var next = values[clamp(index + direction, 0, values.length - 1)];
      if (next !== value) { value = next; show(); if (onChange) onChange(value); }
    }
    buttons[0].addEventListener("click", function () { step(-1); });
    buttons[1].addEventListener("click", function () { step(1); });
    show();
  }
  var openList = null;
  function closeList() {
    if (!openList) return;
    openList.button.setAttribute("aria-expanded", "false");
    openList.node.remove();
    openList = null;
  }
  // The list floats in host (the window or a gallery card), below the button or above it when there is no room.
  function wireDropdown(button, host, getScale, onChange) {
    var options = (button.getAttribute("data-options") || "").split(",");
    button.addEventListener("click", function (event) {
      event.stopPropagation();
      if (openList && openList.button === button) { closeList(); return; }
      closeList();
      var value = button.getAttribute("data-value");
      var scale = getScale();
      var hostRect = host.getBoundingClientRect(), rect = button.getBoundingClientRect();
      var width = Math.max(180, rect.width / scale);
      var height = options.length * 38 + 8;
      var left = clamp((rect.right - hostRect.left) / scale - width, 8, hostRect.width / scale - width - 8);
      var below = (rect.bottom - hostRect.top) / scale + 6;
      var top = below + height > hostRect.height / scale - 8 ? (rect.top - hostRect.top) / scale - height - 6 : below;
      var list = el('<div class="lw-list" role="listbox"></div>');
      list.style.left = left + "px";
      list.style.top = Math.max(8, top) + "px";
      list.style.width = width + "px";
      options.forEach(function (option) {
        var item = el('<button type="button" role="option"><span></span>' + (option === value ? '<i data-icon="check"></i>' : "") + "</button>");
        $("span", item).textContent = option;
        item.setAttribute("aria-selected", String(option === value));
        item.addEventListener("click", function (e) {
          e.stopPropagation();
          closeList();
          button.setAttribute("data-value", option);
          $("span", button).textContent = option;
          if (onChange) onChange(option);
        });
        list.appendChild(item);
      });
      host.appendChild(list);
      button.setAttribute("aria-expanded", "true");
      openList = { button: button, node: list };
    });
  }
  document.addEventListener("pointerdown", function (event) {
    if (openList && !openList.node.contains(event.target) && event.target !== openList.button && !openList.button.contains(event.target)) closeList();
  });
  function wirePressGroup(buttons, attribute, onChange) {
    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        buttons.forEach(function (other) {
          if (attribute === "class") other.classList.toggle("lw-btn--sel", other === button);
          else other.setAttribute("aria-pressed", String(other === button));
        });
        if (onChange) onChange(button.textContent.trim());
      });
    });
  }
  var capture = null;
  function wireKey(button, onChange) {
    button.addEventListener("click", function () {
      if (capture) capture.cancel();
      var before = button.textContent;
      button.textContent = "Press a key…";
      var timer = setTimeout(function () { if (capture && capture.button === button) capture.cancel(); }, 10000);
      capture = {
        button: button,
        done: function (name) { clearTimeout(timer); capture = null; button.textContent = name; if (onChange) onChange(name); },
        cancel: function () { clearTimeout(timer); capture = null; button.textContent = before; }
      };
    });
  }
  document.addEventListener("keydown", function (event) {
    if (!capture) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.key === "Escape") capture.cancel(); else capture.done(keyName(event));
  }, true);
  function openModal(modal, seconds, onConfirm) {
    modal.classList.add("is-open");
    var count = $("[data-count]", modal);
    var left = seconds;
    if (count) count.textContent = String(left);
    var timer = setInterval(function () {
      left -= 1;
      if (count) count.textContent = String(left);
      if (left <= 0) close(false);
    }, 1000);
    function close(confirmed) {
      clearInterval(timer);
      modal.classList.remove("is-open");
      if (confirmed && onConfirm) onConfirm();
    }
    $$("[data-close]", modal).forEach(function (button, index) {
      button.onclick = function () { close(index === 1); };
    });
  }

  // ------------------------------------------------------------------ gallery cards
  function wireGallery(gallery) {
    $$(".comp__demo", gallery).forEach(function (demo) {
      $$(".lw-switch", demo).forEach(function (s) { wireSwitch(s); });
      $$(".lw-slider", demo).forEach(function (s) { wireSlider(s); });
      $$(".lw-stepper", demo).forEach(function (s) { wireStepper(s, function (v) { return v < 60 ? v + " s" : (v / 60) + " min"; }); });
      $$(".lw-drop", demo).forEach(function (d) { wireDropdown(d, demo, function () { return 1; }); });
      var chips = $$(".lw-chip", demo);
      if (chips.length) wirePressGroup(chips, "aria-pressed");
      var segs = $$("[data-seg]", demo);
      if (segs.length) wirePressGroup(segs, "class");
      $$("[data-key]", demo).forEach(function (k) { wireKey(k); });
      $$("[data-buy]", demo).forEach(function (buy) {
        buy.addEventListener("click", function () {
          var card = buy.closest(".lw-item");
          var owned = !card.classList.contains("is-owned");
          card.classList.toggle("is-owned", owned);
          buy.textContent = owned ? "Equip" : "Buy";
          buy.classList.toggle("lw-btn--primary", !owned);
        });
      });
      var toasts = $(".lw-toasts", demo);
      $$("[data-toast]", demo).forEach(function (button) {
        button.addEventListener("click", function () {
          var kind = button.getAttribute("data-toast");
          toast(toasts, kind === "success" ? { kind: "success", title: "Config saved", text: "Restored on your next run.", icon: "save", max: 2 }
            : { kind: "warning", title: "Clipboard unavailable", text: "Select the link and copy it.", icon: "alert", max: 2 });
        });
      });
      var confirm = $("[data-confirm]", demo);
      if (confirm) confirm.addEventListener("click", function () { openModal($(".lw-modal", demo), 10); });
    });
  }

  // ------------------------------------------------------------------ the playground window
  var PAGES = {
    Home:
      '<div class="lw-page" data-page="Home">' +
      '<div class="lw-sec"><h4>Welcome to Lyra UI</h4><p>Drag the corner to resize: the rail turns into icons, then into a drawer.</p></div>' +
      '<div class="lw-card lw-group"><span class="lw-cap">QUICK ACTIONS</span><div class="lw-row3">' +
      '<button class="lw-btn lw-btn--primary" type="button" data-act="notify"><i data-icon="bell"></i><span>Notify</span></button>' +
      '<button class="lw-btn" type="button" data-act="confirm"><i data-icon="info"></i><span>Confirm</span></button>' +
      '<button class="lw-btn" type="button" data-act="go-settings"><i data-icon="sliders"></i><span>Settings</span></button></div></div>' +
      '<div class="lw-card lw-strip"><div class="lw-strip__head"><i data-icon="history"></i><b>Activity</b><span data-strip-hint></span></div><div class="lw-tiles" data-tiles></div>' +
      '<div class="lw-row3"><button class="lw-btn lw-btn--primary" type="button" data-act="strip-add"><i data-icon="plus"></i><span>Add</span></button>' +
      '<button class="lw-btn" type="button" data-act="strip-undo"><i data-icon="undo"></i><span>Undo</span></button>' +
      '<button class="lw-btn" type="button" data-act="strip-clear"><i data-icon="trash"></i><span>Clear</span></button></div></div>' +
      '<button class="lw-guide" type="button" data-act="guide" aria-expanded="false"><span>How it works</span><i data-icon="chevron-down"></i></button>' +
      '<div class="lw-card lw-guide-body"><span>1. Create a window with Lyra:CreateWindow.</span><span>2. Add tabs with Window:Tab and fill them with elements.</span><span>3. Give an element a Flag to save its value between runs.</span><small>Close the window with the X: the floating button, RightControl or /lyra in chat bring it back.</small></div>' +
      "</div>",
    Controls:
      '<div class="lw-page" data-page="Controls">' +
      '<div class="lw-sec"><h4>Controls</h4><p>Values with a Flag are saved to a file and restored the next time the script runs.</p></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Auto collect</b><span>Collects drops near your character.</span></div><button class="lw-switch" type="button" role="switch" aria-checked="false" aria-label="Auto collect" data-switch="Auto collect"></button></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Field of view</b><span>Your camera\'s field of view.</span></div><div class="lw-slider" data-min="50" data-max="110" data-value="70" data-suffix="°"><output></output><div class="lw-track"><div class="lw-fill"></div><div class="lw-knob"></div></div></div></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Round length</b><span>How long each round lasts.</span></div><div class="lw-stepper" data-values="30,60,90,120,180,300" data-value="60"><button class="lw-btn" type="button" aria-label="Less"><i data-icon="minus"></i></button><output></output><button class="lw-btn" type="button" aria-label="More"><i data-icon="plus"></i></button></div></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Quality</b><span>Pick one of several named options.</span></div><button class="lw-drop" type="button" aria-expanded="false" data-options="Low,Medium,High,Ultra" data-value="High"><span>High</span><i data-icon="chevron-down"></i></button></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Quick action</b><span>Tap, then press a key. Esc cancels.</span></div><button class="lw-btn lw-key" type="button" data-key>G</button></div>' +
      '<span class="lw-label">Nickname</span><label class="lw-input"><i data-icon="pencil"></i><input type="text" id="demo-nickname" placeholder="Type a name and press Enter" data-nickname></label>' +
      '<div class="lw-chips" data-chips><button class="lw-chip" type="button" aria-pressed="true">All</button><button class="lw-chip" type="button" aria-pressed="false">Weapons</button><button class="lw-chip" type="button" aria-pressed="false">Pets</button><button class="lw-chip" type="button" aria-pressed="false">Cosmetics</button><button class="lw-chip" type="button" aria-pressed="false">Boosts</button></div>' +
      '<div class="lw-row3" style="--n:2"><button class="lw-btn lw-btn--sel" type="button" data-seg><i data-icon="star"></i><span>Favorites</span></button><button class="lw-btn" type="button" data-seg><i data-icon="history"></i><span>Recent</span></button></div>' +
      '<button class="lw-btn lw-collapse-btn" type="button" data-act="collapse" aria-expanded="false"><i data-icon="chevron-down"></i><span>Show advanced options</span></button>' +
      '<div class="lw-collapse"><div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Developer mode</b><span>Extra logs in the console.</span></div><button class="lw-switch" type="button" role="switch" aria-checked="false" aria-label="Developer mode" data-switch="Developer mode"></button></div></div>' +
      "</div>",
    Players:
      '<div class="lw-page" data-page="Players">' +
      '<div class="lw-sec"><h4>Players in this server</h4><p>On narrow windows the row buttons keep only their icons.</p></div>' +
      '<label class="lw-input"><i data-icon="search"></i><input type="text" id="demo-search" placeholder="Search players by name" data-search></label>' +
      '<span class="lw-label" data-count></span><div class="lw-page is-on" data-players style="gap:6px"></div>' +
      '<div class="lw-sec" style="padding-top:8px"><h4>Playlist</h4><p>Drag the number of a row to move it.</p></div>' +
      '<div class="lw-page is-on" data-playlist style="gap:6px"></div>' +
      "</div>",
    Shop:
      '<div class="lw-page" data-page="Shop">' +
      '<div class="lw-sec"><h4>Item shop</h4><p>Two columns on phones, more as the window grows.</p></div>' +
      '<div class="lw-chips" data-shop-chips><button class="lw-chip" type="button" aria-pressed="true">All</button><button class="lw-chip" type="button" aria-pressed="false">Hats</button><button class="lw-chip" type="button" aria-pressed="false">Faces</button><button class="lw-chip" type="button" aria-pressed="false">Effects</button></div>' +
      '<div class="lw-gridc" data-grid></div></div>',
    About:
      '<div class="lw-page" data-page="About">' +
      '<div class="lw-sec"><h4>Made by lyraEz</h4><p>Find the library and the community here.</p></div>' +
      '<div class="lw-card lw-group" style="background:linear-gradient(28deg, rgb(var(--w-accent-dark) / .45), rgb(var(--w-card) / .85) 65%)">' +
      '<div style="display:flex;gap:12px;align-items:center"><span class="lw-thumb" style="width:52px;height:52px;border-radius:16px;background:rgb(var(--w-accent));color:rgb(var(--w-base));font-size:26px">L</span>' +
      '<div style="display:grid"><span class="lw-cap">GITHUB PROFILE</span><b style="font-size:19px">lyraEz</b><span class="lw-label" style="padding:0">@lyraEz</span></div></div>' +
      '<span>The moon reminds me that even in darkness, there\'s always a <b style="color:#cbb8ff">beautiful light</b></span>' +
      '<button class="lw-btn" type="button" data-act="copy-link" data-url="https://github.com/lyraEz"><i data-icon="copy"></i><span>Copy link</span></button></div>' +
      '<div class="lw-card lw-group"><div style="display:flex;gap:12px;align-items:center"><span class="lw-thumb" style="width:44px;height:44px;border-radius:13px"><i data-icon="discord"></i></span><div style="display:grid"><b style="font-size:17px">Discord</b><span class="lw-label" style="padding:0">Join the community</span></div></div>' +
      '<button class="lw-btn" type="button" data-act="copy-link" data-url="https://discord.gg/8bxXcn2Vfb"><i data-icon="copy"></i><span>Copy link</span></button></div>' +
      "</div>",
    Settings:
      '<div class="lw-page" data-page="Settings">' +
      '<div class="lw-sec"><h4>Settings</h4><p>The defaults work for most people. Change only what you need.</p></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Interface size</b><span>Makes the window and its text smaller or larger.</span></div><div class="lw-stepper" data-values="80,85,90,95,100,105,110" data-value="100" data-scale><button class="lw-btn" type="button" aria-label="Smaller"><i data-icon="minus"></i></button><output></output><button class="lw-btn" type="button" aria-label="Larger"><i data-icon="plus"></i></button></div></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Window size</b><span>Drag the corner to resize. Reset restores the default size.</span></div><button class="lw-btn" type="button" data-act="reset-size"><i data-icon="reset"></i><span>Reset</span></button></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Theme</b><span>The colours of the whole window.</span></div><button class="lw-drop" type="button" aria-expanded="false" data-options="Lavender,Midnight,Rose,Mint,Ember" data-value="Lavender" data-theme-drop><span>Lavender</span><i data-icon="chevron-down"></i></button></div>' +
      '<div class="lw-sec"><h4>How to reopen the window</h4><p>Keep at least one on, so the window can always come back.</p></div>' +
      '<div class="lw-card lw-reopen"><div>Floating button <em data-reopen-orb>On</em></div><div>Roblox menu shortcut (Esc ×3) <em>On</em></div><div>Shortcut key (RightControl) <em>Ready</em></div><div>Chat  /lyra <em>Ready</em></div></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Floating button</b><span>Shows a draggable button while the window is closed.</span></div><button class="lw-switch" type="button" role="switch" aria-checked="true" aria-label="Floating button" data-orb-switch></button></div>' +
      '<div class="lw-card lw-ctrl"><div class="lw-ctrl__text"><b>Show notifications</b><span>Small pop-ups in the bottom-right corner.</span></div><button class="lw-switch" type="button" role="switch" aria-checked="true" aria-label="Show notifications" data-notify-switch></button></div>' +
      "</div>"
  };
  var TABS = [["Home", "user"], ["Controls", "sliders"], ["Players", "users"], ["Shop", "box"], ["About", "code"], ["Settings", "sliders"]];
  var PEOPLE = [["Sheliak", "sheliak", true], ["Vega", "vega_star"], ["Altair", "altair"], ["Deneb", "deneb_nights"], ["Lyra Tester", "lyratester"]];
  var SONGS = ["Moonlight", "Vega", "Nebula", "Afterglow", "Stardust"];
  var ITEMS = [["Starlight Crown", "Hats · 250", "Hats", "star", "NEW"], ["Comet Trail", "Effects · 400", "Effects", "refresh"], ["Moon Visor", "Faces · 120", "Faces", "eye-off", null, true],
    ["Nebula Cape", "Hats · 300", "Hats", "shirt"], ["Orbit Ring", "Effects · 180", "Effects", "repeat", "SALE"], ["Vega Mask", "Faces · 90", "Faces", "user"]];

  function Playground(stage) {
    var self = this;
    this.stage = stage;
    this.state = { x: 0, y: 0, w: 820, h: 560, scale: 1, visible: true, min: false, max: false, drawer: false, orb: true, notify: true };
    var tabs = TABS.map(function (tab, i) {
      return '<button class="lw-tab" type="button" role="tab" data-tab="' + tab[0] + '" aria-selected="' + (i === 0) + '"><i data-icon="' + tab[1] + '"></i><span>' + tab[0] + "</span></button>";
    }).join("");
    var pages = TABS.map(function (tab) { return PAGES[tab[0]]; }).join("");
    this.lw = el(
      '<div class="lw" role="application" aria-label="Lyra Showcase window replica">' +
      '<div class="lw-head" data-drag><button class="lw-ib lw-menu" type="button" data-act="menu" aria-label="Open the tab drawer"><i data-icon="menu"></i></button>' +
      '<span class="lw-logo">LS</span><div class="lw-titles"><b>Lyra Showcase</b><small>Lyra UI · v1.0.0</small></div>' +
      '<div class="lw-actions"><button class="lw-ib" type="button" data-act="minimize" aria-label="Minimize"><i data-icon="minus"></i></button>' +
      '<button class="lw-ib" type="button" data-act="maximize" aria-label="Maximize"><i data-icon="maximize"></i></button>' +
      '<button class="lw-ib" type="button" data-act="close" aria-label="Close"><i data-icon="x"></i></button></div></div>' +
      '<nav class="lw-rail" role="tablist" aria-label="Tabs"><div class="lw-rail__cap">WORKSPACE</div>' + tabs + '<div class="lw-rail__foot">LYRA<br>SHOWCASE</div></nav>' +
      '<button class="lw-scrim" type="button" data-act="scrim" aria-label="Close the drawer"></button>' +
      '<div class="lw-back"></div><div class="lw-content">' + pages + "</div>" +
      '<div class="lw-status"><i></i><span>Ready to explore.</span></div>' +
      '<button class="lw-grip" type="button" aria-label="Resize the window"></button>' +
      '<div class="lw-modal"><div class="lw-modal__card"><b data-modal-title></b><p data-modal-text></p><div class="lw-row3"><button class="lw-btn" type="button" data-close>Cancel</button><button class="lw-btn lw-btn--primary" type="button" data-close>Confirm</button></div></div></div>' +
      "</div>");
    this.orb = el('<button class="lw-orb" type="button" aria-label="Open the window" hidden>LS</button>');
    this.badge = el('<div class="lw-badge" aria-hidden="true"></div>');
    this.toasts = el('<div class="lw-toasts" aria-live="polite"></div>');
    stage.appendChild(this.lw);
    stage.appendChild(this.orb);
    stage.appendChild(this.badge);
    stage.appendChild(this.toasts);
    this.statusNode = $(".lw-status", this.lw);
    this.select("Home");
    this.wire();
    var size = this.fit(820, 560);
    this.state.w = size.w;
    this.state.h = size.h;
    this.center();
    this.orbAt(stage.clientWidth - 70, stage.clientHeight / 2 - 26);
    if ("ResizeObserver" in window) new ResizeObserver(function () { self.layout(false); }).observe(stage);
  }
  Playground.prototype.fit = function (w, h) {
    return { w: clamp(w, 300, Math.max(300, (this.stage.clientWidth - 20) / this.state.scale)), h: clamp(h, 240, Math.max(240, (this.stage.clientHeight - 20) / this.state.scale)) };
  };
  Playground.prototype.center = function () {
    var s = this.state;
    s.x = (this.stage.clientWidth - s.w) / 2;
    s.y = (this.stage.clientHeight - (s.min ? 52 : s.h)) / 2;
    this.layout(false);
  };
  // Mirrors Window:_layout: size, clamping and the rail / compact breakpoints.
  Playground.prototype.layout = function (animate) {
    var s = this.state, lw = this.lw;
    var stageW = this.stage.clientWidth, stageH = this.stage.clientHeight;
    var w = s.max ? (stageW - 20) / s.scale : clamp(s.w, 300, Math.max(300, (stageW - 20) / s.scale));
    var h = s.max ? (stageH - 20) / s.scale : clamp(s.h, 240, Math.max(240, (stageH - 20) / s.scale));
    var shownH = s.min ? 52 : h;
    if (s.max) { s.x = (stageW - w) / 2; s.y = (stageH - h) / 2; }
    var visualW = w * s.scale, visualH = shownH * s.scale;
    var x = clamp(s.x + (w - visualW) / 2, 10, Math.max(10, stageW - visualW - 10)) - (w - visualW) / 2;
    var y = clamp(s.y + (shownH - visualH) / 2, 10, Math.max(10, stageH - visualH - 10)) - (shownH - visualH) / 2;
    if (!s.max) { s.x = x; s.y = y; }
    var narrow = w < 520, mini = !narrow && w < 760;
    var left = narrow ? 10 : (mini ? 78 : 214);
    lw.classList.toggle("is-animating", !!animate);
    lw.classList.toggle("is-narrow", narrow);
    lw.classList.toggle("is-mini", mini);
    lw.classList.toggle("is-compact", w - left - 22 < 470);
    lw.classList.toggle("is-min", s.min);
    lw.classList.toggle("is-max", s.max);
    if (!narrow) s.drawer = false;
    lw.classList.toggle("is-drawer", s.drawer);
    lw.style.left = x + "px";
    lw.style.top = y + "px";
    lw.style.width = w + "px";
    lw.style.height = shownH + "px";
    if (!lw.classList.contains("is-flying")) lw.style.transform = "scale(" + s.scale + ")";
    this.w = w; this.h = h;
  };
  Playground.prototype.status = function (text, kind) {
    this.statusNode.setAttribute("data-kind", kind || "info");
    $("span", this.statusNode).textContent = text;
  };
  Playground.prototype.notify = function (spec) { if (this.state.notify) toast(this.toasts, spec); };
  Playground.prototype.select = function (name) {
    $$(".lw-tab", this.lw).forEach(function (tab) { tab.setAttribute("aria-selected", String(tab.getAttribute("data-tab") === name)); });
    $$(".lw-content > .lw-page", this.lw).forEach(function (page) { page.classList.toggle("is-on", page.getAttribute("data-page") === name); });
    $(".lw-content", this.lw).scrollTop = 0;
    this.state.drawer = false;
    closeList();
    this.layout(false);
  };
  Playground.prototype.confirm = function (title, text, onConfirm) {
    var modal = $(".lw-modal", this.lw);
    $("[data-modal-title]", modal).textContent = title;
    $("[data-modal-text]", modal).innerHTML = "";
    $("[data-modal-text]", modal).append(document.createTextNode(text + " Closes on its own in "), el("<span data-count>10</span>"), document.createTextNode(" s."));
    openModal(modal, 10, onConfirm);
  };
  Playground.prototype.orbAt = function (x, y) {
    this.orbX = clamp(x, 8, this.stage.clientWidth - 60);
    this.orbY = clamp(y, 8, this.stage.clientHeight - 60);
    this.orb.style.left = this.orbX + "px";
    this.orb.style.top = this.orbY + "px";
  };
  // Window flight: the window shrinks into the floating button (or its own centre) and grows back out.
  Playground.prototype.setVisible = function (visible) {
    var s = this.state, lw = this.lw, self = this;
    if (visible === s.visible) return;
    s.visible = visible;
    closeList();
    var rect = { x: s.x + this.w / 2, y: s.y + (s.min ? 52 : this.h) / 2 };
    var target = s.orb ? { x: this.orbX + 26, y: this.orbY + 26 } : rect;
    var away = "translate(" + (target.x - rect.x) + "px," + (target.y - rect.y) + "px) scale(" + (s.scale * 0.06) + ")";
    clearTimeout(this.flightTimer);
    if (visible) {
      lw.hidden = false;
      lw.classList.remove("is-flying");
      lw.style.transform = away;
      lw.style.opacity = s.orb ? "1" : "0";
      void lw.offsetWidth;
      lw.classList.add("is-flying");
      lw.style.transform = "scale(" + s.scale + ")";
      lw.style.opacity = "1";
      this.orb.hidden = true;
      this.flightTimer = setTimeout(function () { lw.classList.remove("is-flying"); }, FLIGHT);
      return;
    }
    lw.classList.add("is-flying");
    lw.style.transform = away;
    if (!s.orb) lw.style.opacity = "0";
    if (s.orb) { this.orb.hidden = false; this.orb.classList.remove("is-pop"); }
    this.flightTimer = setTimeout(function () {
      lw.hidden = true;
      lw.classList.remove("is-flying");
      if (s.orb) {
        self.orb.classList.add("is-pop");
        setTimeout(function () { self.orb.classList.remove("is-pop"); }, 240);
      } else {
        self.notify({ kind: "info", icon: "eye-off", title: "Lyra Showcase hidden", text: "To reopen it, press RightControl, press Esc 3 times, or type /lyra in chat." });
      }
    }, FLIGHT);
  };
  Playground.prototype.renderStrip = function () {
    var tiles = $("[data-tiles]", this.lw), self = this;
    tiles.innerHTML = "";
    if (!this.activity.length) tiles.appendChild(el("<span>Entries you add appear here.</span>"));
    this.activity.forEach(function (name, index) {
      var now = index === self.activity.length - 1;
      var tile = el('<button class="lw-tile' + (now ? " is-now" : "") + '" type="button"><i><i data-icon="star"></i></i><small></small></button>');
      $("small", tile).textContent = now ? "Now" : name;
      tile.addEventListener("click", function () { self.status("You picked " + name + ".", "info"); });
      tiles.appendChild(tile);
    });
    tiles.scrollLeft = tiles.scrollWidth;
    $("[data-strip-hint]", this.lw).textContent = this.activity.length ? this.activity.length + " entries · tap one" : "";
  };
  Playground.prototype.renderPlayers = function (term) {
    var list = $("[data-players]", this.lw), self = this;
    term = (term || "").toLowerCase();
    list.innerHTML = "";
    var shown = PEOPLE.filter(function (p) { return !term || p[0].toLowerCase().indexOf(term) >= 0 || p[1].indexOf(term) >= 0; });
    shown.forEach(function (p, i) {
      var row = el('<div class="lw-card lw-row' + (p[2] ? " is-current" : "") + '"><span class="lw-thumb"></span><div class="lw-row__text"><b></b><span></span></div>' +
        '<button class="lw-btn lw-btn--primary" type="button">Wave</button><button class="lw-btn can-collapse" type="button"><i data-icon="user"></i><span>Profile</span></button>' +
        '<button class="lw-btn lw-btn--icon" type="button" aria-label="Favorite"><i data-icon="star"></i></button></div>');
      var thumb = $(".lw-thumb", row);
      thumb.textContent = p[0].charAt(0);
      thumb.style.background = "hsl(" + (250 + i * 37) + " 32% 30%)";
      $("b", row).textContent = p[0];
      $(".lw-row__text span", row).textContent = "@" + p[1] + (p[2] ? " · you" : "");
      var buttons = $$(".lw-btn", row);
      buttons[0].addEventListener("click", function () { self.status("You waved at " + p[0] + ".", "success"); });
      buttons[1].addEventListener("click", function () { self.status(p[1] + " · ID " + (1000 + i * 4217), "info"); });
      buttons[2].addEventListener("click", function () { self.notify({ kind: "success", icon: "star", title: "Added to favorites", text: p[0] }); });
      list.appendChild(row);
    });
    if (!shown.length) list.appendChild(el('<div class="lw-card" style="height:126px;display:grid;place-items:center;text-align:center;padding:14px"><div><b>No players found</b><br><span class="lw-label">Try another name or clear the search.</span></div></div>'));
    $("[data-count]", this.lw).textContent = "Showing " + shown.length + " of " + PEOPLE.length + " players";
  };
  Playground.prototype.renderPlaylist = function () {
    var list = $("[data-playlist]", this.lw), self = this;
    list.innerHTML = "";
    this.songs.forEach(function (song, index) {
      var row = el('<div class="lw-card lw-row"><span class="lw-num"></span><span class="lw-thumb"><i data-icon="star"></i></span><div class="lw-row__text"><b></b><span>Lyra Sessions</span></div>' +
        '<button class="lw-btn" type="button">Play</button><button class="lw-btn lw-btn--icon" type="button" aria-label="Remove"><i data-icon="x"></i></button></div>');
      $(".lw-num", row).textContent = String(index + 1);
      $("b", row).textContent = song;
      var buttons = $$(".lw-btn", row);
      buttons[0].addEventListener("click", function () { self.status("Playing " + song + ".", "success"); });
      buttons[1].addEventListener("click", function () { self.songs.splice(self.songs.indexOf(song), 1); self.renderPlaylist(); });
      self.dragRow($(".lw-num", row), row, index);
      list.appendChild(row);
    });
    if (!this.songs.length) list.appendChild(el('<div class="lw-card" style="height:90px;display:grid;place-items:center"><span class="lw-label">Your playlist is empty.</span></div>'));
  };
  // Drag the number to move a row. A line marks where it will land.
  Playground.prototype.dragRow = function (grip, row, index) {
    var self = this;
    grip.addEventListener("pointerdown", function (event) {
      if (self.songs.length < 2) return;
      event.preventDefault();
      grip.setPointerCapture(event.pointerId);
      var list = row.parentElement, line = el('<div class="lw-dropline"></div>');
      row.classList.add("is-drag");
      var slot = index;
      function update(y) {
        var rows = $$(".lw-row", list);
        slot = rows.length;
        for (var i = 0; i < rows.length; i++) {
          var rect = rows[i].getBoundingClientRect();
          if (y < rect.top + rect.height / 2) { slot = i; break; }
        }
        list.insertBefore(line, rows[slot] || null);
      }
      function move(e) { update(e.clientY); }
      function up() {
        grip.removeEventListener("pointermove", move);
        grip.removeEventListener("pointerup", up);
        grip.removeEventListener("pointercancel", up);
        line.remove();
        var target = slot > index ? slot - 1 : slot;
        if (target !== index) {
          var song = self.songs.splice(index, 1)[0];
          self.songs.splice(target, 0, song);
          self.status("Moved song " + (index + 1) + " to position " + (target + 1) + ".", "info");
        }
        self.renderPlaylist();
      }
      grip.addEventListener("pointermove", move);
      grip.addEventListener("pointerup", up);
      grip.addEventListener("pointercancel", up);
      update(event.clientY);
    });
  };
  Playground.prototype.renderShop = function (category) {
    var grid = $("[data-grid]", this.lw), self = this;
    grid.innerHTML = "";
    ITEMS.forEach(function (item) {
      if (category !== "All" && item[2] !== category) return;
      var card = el('<div class="lw-card lw-item' + (item[5] ? " is-owned" : "") + '"><div class="lw-item__pic">' + (item[4] ? '<span class="lw-tag"></span>' : "") +
        '<span class="lw-check"><i data-icon="check"></i></span><i data-icon="' + item[3] + '"></i></div><b></b><small></small><button class="lw-btn" type="button"></button></div>');
      if (item[4]) $(".lw-tag", card).textContent = item[4];
      $("b", card).textContent = item[0];
      $("small", card).textContent = item[1];
      var button = $("button", card);
      function paint() { button.textContent = item[5] ? "Equip" : "Buy"; button.classList.toggle("lw-btn--primary", !item[5]); card.classList.toggle("is-owned", !!item[5]); }
      button.addEventListener("click", function () {
        if (!item[5]) { item[5] = true; paint(); self.notify({ kind: "success", icon: "box", title: item[0], text: "Added to your inventory." }); }
        else self.status(item[0] + " equipped.", "success");
      });
      paint();
      grid.appendChild(card);
    });
  };
  Playground.prototype.wire = function () {
    var self = this, lw = this.lw, s = this.state;
    this.activity = [];
    this.songs = SONGS.slice();
    this.renderStrip();
    this.renderPlayers("");
    this.renderPlaylist();
    this.renderShop("All");
    var host = lw, scale = function () { return s.scale; };

    $$(".lw-tab", lw).forEach(function (tab) { tab.addEventListener("click", function () { self.select(tab.getAttribute("data-tab")); }); });
    $$("[data-switch]", lw).forEach(function (sw) {
      wireSwitch(sw, function (on) { self.status(sw.getAttribute("data-switch") + (on ? " is on." : " is off."), on ? "success" : "info"); });
    });
    $$(".lw-slider", lw).forEach(function (slider) { wireSlider(slider, function (v) { self.status("Field of view: " + v + "°", "info"); }); });
    $$(".lw-stepper:not([data-scale])", lw).forEach(function (stepper) {
      wireStepper(stepper, function (v) { return v < 60 ? v + " s" : (v / 60) + " min"; }, function (v) { self.status("Round length: " + (v < 60 ? v + " s" : (v / 60) + " min") + ".", "info"); });
    });
    wireStepper($("[data-scale]", lw), function (v) { return v === 100 ? "Auto" : v + "%"; }, function (v) { s.scale = v / 100; self.layout(true); });
    $$(".lw-drop", lw).forEach(function (drop) {
      wireDropdown(drop, host, scale, function (value) {
        if (drop.hasAttribute("data-theme-drop")) { window.LyraSite.applyTheme(value); self.status("Theme: " + value + ".", "info"); }
        else self.status("Quality: " + value + ".", "info");
      });
    });
    document.addEventListener("lyra-theme", function (event) {
      var drop = $("[data-theme-drop]", lw);
      drop.setAttribute("data-value", event.detail);
      $("span", drop).textContent = event.detail;
    });
    $$("[data-key]", lw).forEach(function (key) { wireKey(key, function (name) { self.status("Quick action is now " + name + ".", "success"); }); });
    wirePressGroup($$("[data-chips] .lw-chip", lw), "aria-pressed", function (v) { self.status("Filter: " + v, "info"); });
    wirePressGroup($$("[data-shop-chips] .lw-chip", lw), "aria-pressed", function (v) { self.renderShop(v); });
    wirePressGroup($$("[data-seg]", lw), "class", function (v) { self.status("Showing " + v.toLowerCase() + ".", "info"); });
    var nickname = $("[data-nickname]", lw);
    nickname.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && nickname.value.trim()) { self.status("Hello, " + nickname.value.trim() + "!", "success"); nickname.blur(); }
    });
    var search = $("[data-search]", lw), searchTimer;
    search.addEventListener("input", function () { clearTimeout(searchTimer); searchTimer = setTimeout(function () { self.renderPlayers(search.value); }, 160); });
    var orbSwitch = $("[data-orb-switch]", lw);
    wireSwitch(orbSwitch, function (on) { s.orb = on; $("[data-reopen-orb]", lw).textContent = on ? "On" : "Off"; $("[data-reopen-orb]", lw).classList.toggle("off", !on); });
    wireSwitch($("[data-notify-switch]", lw), function (on) { s.notify = on; if (!on) $$(".lw-toast", self.toasts).forEach(function (t) { t.click(); }); });

    lw.addEventListener("click", function (event) {
      var button = event.target.closest("[data-act]");
      if (!button || !lw.contains(button)) return;
      var act = button.getAttribute("data-act");
      if (act === "menu") { s.drawer = !s.drawer; self.layout(false); }
      else if (act === "scrim") { s.drawer = false; self.layout(false); }
      else if (act === "minimize") { s.min = !s.min; self.layout(true); }
      else if (act === "maximize") { s.max = !s.max; s.min = false; self.layout(true); }
      else if (act === "close") self.setVisible(false);
      else if (act === "notify") self.notify({ kind: "success", icon: "circle-check", title: "Hello there", text: "This is a Lyra toast. Tap it to close it." });
      else if (act === "confirm") self.confirm("Run the demo action?", "This dialog cancels itself if nobody answers.", function () { self.status("Demo action finished.", "success"); });
      else if (act === "go-settings") self.select("Settings");
      else if (act === "strip-add") { self.activity.push("Step " + (self.activity.length + 1)); self.renderStrip(); }
      else if (act === "strip-undo") { self.activity.pop(); self.renderStrip(); }
      else if (act === "strip-clear") { self.activity = []; self.renderStrip(); }
      else if (act === "guide") {
        var body = button.nextElementSibling, open = !body.classList.contains("is-open");
        body.classList.toggle("is-open", open);
        button.setAttribute("aria-expanded", String(open));
        $("span", button).textContent = open ? "Hide how it works" : "How it works";
      } else if (act === "collapse") {
        var section = button.nextElementSibling, opened = !section.classList.contains("is-open");
        section.classList.toggle("is-open", opened);
        button.setAttribute("aria-expanded", String(opened));
        $("span", button).textContent = opened ? "Hide advanced options" : "Show advanced options";
      } else if (act === "reset-size") {
        s.max = false; s.min = false; s.scale = 1;
        var fit = self.fit(820, 560);
        s.w = fit.w; s.h = fit.h;
        $("[data-scale] output", lw).textContent = "Auto";
        $("[data-scale]", lw).setAttribute("data-value", "100");
        self.center();
        self.layout(true);
        self.status("Window size and interface size reset.", "info");
      } else if (act === "copy-link") {
        var url = button.getAttribute("data-url");
        var label = $("span", button);
        var done = function () { label.textContent = "Copied!"; self.status("Link copied.", "success"); setTimeout(function () { label.textContent = "Copy link"; }, 1500); };
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { self.status(url, "warning"); });
        else self.status(url, "warning");
      }
    });

    // Drag the window by its header (not over its buttons).
    var head = $("[data-drag]", lw);
    head.addEventListener("pointerdown", function (event) {
      if (event.target.closest("button") || s.max) return;
      head.setPointerCapture(event.pointerId);
      var startX = event.clientX, startY = event.clientY, originX = s.x, originY = s.y;
      function move(e) { s.x = originX + e.clientX - startX; s.y = originY + e.clientY - startY; self.layout(false); }
      function up() { head.removeEventListener("pointermove", move); head.removeEventListener("pointerup", up); head.removeEventListener("pointercancel", up); }
      head.addEventListener("pointermove", move);
      head.addEventListener("pointerup", up);
      head.addEventListener("pointercancel", up);
    });
    // Bottom-right grip: resize live with a size badge.
    var grip = $(".lw-grip", lw), badge = this.badge, badgeTimer;
    function showBadge() {
      badge.textContent = Math.round(self.w) + " × " + Math.round(self.h);
      badge.style.left = (s.x + self.w * s.scale - 100 + (self.w - self.w * s.scale) / 2) + "px";
      badge.style.top = (s.y + self.h - 40) + "px";
      badge.classList.add("is-on");
    }
    grip.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      grip.setPointerCapture(event.pointerId);
      grip.classList.add("is-active");
      s.max = false;
      var startX = event.clientX, startY = event.clientY, startW = self.w, startH = self.h;
      $$("[data-preset]").forEach(function (b) { b.setAttribute("aria-pressed", "false"); });
      function move(e) {
        s.w = clamp(startW + (e.clientX - startX) / s.scale, 300, (self.stage.clientWidth - s.x - 10) / s.scale);
        s.h = clamp(startH + (e.clientY - startY) / s.scale, 240, (self.stage.clientHeight - s.y - 10) / s.scale);
        self.layout(false);
        showBadge();
      }
      function up() {
        grip.classList.remove("is-active");
        grip.removeEventListener("pointermove", move);
        grip.removeEventListener("pointerup", up);
        grip.removeEventListener("pointercancel", up);
        clearTimeout(badgeTimer);
        badgeTimer = setTimeout(function () { badge.classList.remove("is-on"); }, 500);
      }
      grip.addEventListener("pointermove", move);
      grip.addEventListener("pointerup", up);
      grip.addEventListener("pointercancel", up);
    });
    // Floating button: drag it anywhere, tap it to bring the window back.
    var orb = this.orb;
    orb.addEventListener("pointerdown", function (event) {
      orb.setPointerCapture(event.pointerId);
      var startX = event.clientX, startY = event.clientY, originX = self.orbX, originY = self.orbY, moved = false;
      function move(e) {
        if (Math.abs(e.clientX - startX) + Math.abs(e.clientY - startY) > 7) moved = true;
        if (moved) self.orbAt(originX + e.clientX - startX, originY + e.clientY - startY);
      }
      function up() {
        orb.removeEventListener("pointermove", move);
        orb.removeEventListener("pointerup", up);
        orb.removeEventListener("pointercancel", up);
        if (!moved) self.setVisible(true);
      }
      orb.addEventListener("pointermove", move);
      orb.addEventListener("pointerup", up);
      orb.addEventListener("pointercancel", up);
    });
  };
  Playground.prototype.preset = function (w, h) {
    var s = this.state;
    s.max = false; s.min = false;
    var fit = this.fit(w, h);
    s.w = fit.w; s.h = fit.h;
    if (!s.visible) this.setVisible(true);
    this.center();
    this.layout(true);
  };

  // ------------------------------------------------------------------ boot
  document.addEventListener("DOMContentLoaded", function () {
    var gallery = document.getElementById("gallery");
    if (gallery) wireGallery(gallery);
    var stage = document.getElementById("stage");
    if (!stage) return;
    var play = new Playground(stage);
    $$("[data-preset]").forEach(function (button) {
      button.addEventListener("click", function () {
        $$("[data-preset]").forEach(function (b) { b.setAttribute("aria-pressed", String(b === button)); });
        var size = button.getAttribute("data-preset").split("x").map(Number);
        play.preset(size[0], size[1]);
      });
    });
    // RightControl toggles; Esc three times within 5 s reopens a hidden window (like opening the Roblox menu).
    var escapes = [];
    document.addEventListener("keydown", function (event) {
      if (event.code === "ControlRight") { play.setVisible(!play.state.visible); return; }
      if (event.key === "Escape" && !play.state.visible) {
        var now = Date.now();
        escapes.push(now);
        escapes = escapes.filter(function (t) { return now - t < 5000; });
        if (escapes.length >= 3) {
          escapes = [];
          play.setVisible(true);
          play.notify({ kind: "info", icon: "menu", title: "Lyra Showcase reopened", text: "You pressed Esc 3 times in a row, like opening the Roblox menu." });
        }
      }
    });
    var chat = document.getElementById("chatbar");
    chat.addEventListener("submit", function (event) {
      event.preventDefault();
      var input = document.getElementById("chat-input");
      var text = input.value.trim().toLowerCase();
      input.value = "";
      var body = text.replace(/^\/e\s+/, "/");
      if (body === "/lyra") {
        if (!play.state.visible) play.setVisible(true);
        play.status("Hub opened.", "info");
      } else if (body.indexOf("/hello") === 0) {
        var who = body.slice(6).trim();
        play.notify({ kind: "info", icon: "bell", title: "Hello" + (who ? ", " + who : "") + "!", text: "Sent from the chat with /hello." });
      } else if (text) {
        play.status("Unknown command. Try /lyra or /hello.", "warning");
      }
    });
  });
})();
