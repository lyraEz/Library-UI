/* Docs page: icon grid, section filter and the active link in the sidebar. */
(function () {
  "use strict";
  // Library icon names (Lyra.IconNames) and the drawing this site uses for each.
  var LIBRARY_ICONS = [
    ["user", "user"], ["users", "users"], ["server", "server"], ["star", "star"], ["history", "history"], ["bookmark", "bookmark"],
    ["sliders-horizontal", "sliders"], ["code-xml", "code"], ["search", "search"], ["x", "x"], ["menu", "menu"], ["maximize-2", "maximize"],
    ["minus", "minus"], ["plus", "plus"], ["undo-2", "undo"], ["copy", "copy"], ["check", "check"], ["arrow-right", "arrow"],
    ["rotate-ccw", "reset"], ["box", "box"], ["refresh-cw", "refresh"], ["pencil", "pencil"], ["share-2", "share"], ["trash-2", "trash"],
    ["download", "download"], ["gamepad-2", "gamepad"], ["shirt", "shirt"], ["save", "save"], ["link", "link"], ["github", "github"],
    ["discord", "discord"], ["bell", "bell"], ["info", "info"], ["circle-check", "circle-check"], ["triangle-alert", "alert"],
    ["circle-x", "circle-x"], ["eye-off", "eye-off"], ["repeat", "repeat"], ["chevron-down", "chevron-down"], ["chevron-up", "chevron-up"]
  ];

  document.addEventListener("DOMContentLoaded", function () {
    var grid = document.getElementById("icons-grid");
    if (grid) {
      LIBRARY_ICONS.forEach(function (pair) {
        var cell = document.createElement("div");
        cell.appendChild(window.LyraIcons.icon(pair[1]));
        cell.appendChild(document.createTextNode(pair[0]));
        grid.appendChild(cell);
      });
    }

    var links = Array.prototype.slice.call(document.querySelectorAll("#docs-nav a"));
    var sections = links.map(function (link) { return document.querySelector(link.getAttribute("href")); });

    // Filter: matches link text and the section's own text.
    var filter = document.getElementById("docs-filter");
    var empty = document.getElementById("docs-empty");
    filter.addEventListener("input", function () {
      var term = filter.value.trim().toLowerCase();
      var any = false;
      links.forEach(function (link, i) {
        var section = sections[i];
        var hit = !term || link.textContent.toLowerCase().indexOf(term) >= 0 || (section && section.textContent.toLowerCase().indexOf(term) >= 0);
        link.parentElement.hidden = !hit;
        if (hit) any = true;
      });
      document.querySelectorAll("#docs-nav > div").forEach(function (group) {
        group.hidden = !group.querySelector("li:not([hidden])");
      });
      empty.hidden = any;
    });
    filter.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      var first = links.find(function (link) { return !link.parentElement.hidden; });
      if (first) first.click();
    });

    // Highlight the section being read.
    if ("IntersectionObserver" in window) {
      var visible = new Map();
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) { visible.set(entry.target, entry.isIntersecting ? entry.intersectionRatio : 0); });
        var best = null, bestTop = Infinity;
        sections.forEach(function (section) {
          if (!section || !visible.get(section)) return;
          var top = Math.abs(section.getBoundingClientRect().top);
          if (top < bestTop) { bestTop = top; best = section; }
        });
        if (!best) return;
        links.forEach(function (link, i) { link.classList.toggle("is-active", sections[i] === best); });
      }, { rootMargin: "-80px 0px -55% 0px", threshold: [0, 0.01, 0.5] });
      sections.forEach(function (section) { if (section) observer.observe(section); });
    }
  });
})();
