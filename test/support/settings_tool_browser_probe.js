(mode) => {
  const root = document.querySelector("[data-settings-tool]");
  const main = document.querySelector("main");
  const visible = e => e.getClientRects().length > 0 && e.checkVisibility() && getComputedStyle(e).visibility === "visible";
  const identity = e => ({tag: e.tagName, id: e.id, classes: typeof e.className === "string" ? e.className : e.className.baseVal, promptBody: e.matches("[data-prompt-content]")});
  const controls = "a,button,input,select,textarea";
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext("2d", {willReadFrequently: true});

  function rgba(color) {
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, 1, 1);
    const result = Array.from(ctx.getImageData(0, 0, 1, 1).data);
    result[3] /= 255;
    return result;
  }

  function blend(foreground, background) {
    return foreground.slice(0, 3).map((value, i) => value * foreground[3] + background[i] * (1 - foreground[3]));
  }

  function background(e) {
    const ancestors = [];
    for (; e; e = e.parentElement) ancestors.unshift(e);
    return ancestors.reduce((result, ancestor) => {
      const style = getComputedStyle(ancestor);
      if (style.opacity !== "1" || style.backgroundImage !== "none") throw Error("Unmeasured surface");
      return blend(rgba(style.backgroundColor), result);
    }, [255, 255, 255]);
  }

  function luminance(rgb) {
    return rgb.map(value => {
      value /= 255;
      return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    }).reduce((sum, value, i) => sum + value * [0.2126, 0.7152, 0.0722][i], 0);
  }

  function row(e, property, minimum, outside = false) {
    const backgroundRGB = background(outside ? e.parentElement : e);
    const foregroundRGB = blend(rgba(getComputedStyle(e)[property]), backgroundRGB);
    const a = luminance(foregroundRGB), b = luminance(backgroundRGB);
    return {...identity(e), property, minimum, outside, backgroundRGB, foregroundRGB, ratio: (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)};
  }

  if (mode === "walk") {
    return Array.from(root.querySelectorAll(controls)).filter(e => visible(e) && !e.disabled && e.tabIndex >= 0)
      .map((e, index) => { e.dataset.toolsWalk = String(index); return e; }).length;
  }

  if (mode === "focus") {
    const e = document.activeElement, r = e.getBoundingClientRect(), m = main.getBoundingClientRect(), s = getComputedStyle(e);
    const top = Math.max(0, m.top), bottom = Math.min(innerHeight, m.bottom);
    const y1 = Math.max(r.top + 2, top + 2), y2 = Math.min(r.bottom - 2, bottom - 2);
    // Editors may extend below the viewport after native Tab; their visible edges must still pass hit tests.
    const tallField = e.matches("textarea");
    const points = [[r.left + 2, (y1 + y2) / 2], [r.right - 2, (y1 + y2) / 2], [(r.left + r.right) / 2, y1], [(r.left + r.right) / 2, y2]];
    const hits = points.map(([x, y]) => {
      const node = document.elementFromPoint(x, y);
      return {x, y, hit: !!node && (node === e || e.contains(node))};
    });
    return {...identity(e), index: e.dataset.toolsWalk, bounds: r.toJSON(), mainBounds: m.toJSON(), width: r.width, height: r.height,
      outline: parseFloat(s.outlineWidth), focusVisible: e.matches(":focus-visible"), hovered: e.matches(":hover"), tallField, hits,
      unobscured: r.left >= Math.max(0, m.left) && r.right <= Math.min(innerWidth, m.right) && y2 > y1 &&
        (tallField || (r.top >= top && r.bottom <= bottom)) && hits.every(point => point.hit)};
  }

  if (mode === "layout") {
    const rows = Array.from(root.querySelectorAll("h1,h2,h3,p,label,nav,nav li,a,button,input[type=submit],[data-prompt-content]")).filter(visible).map(e => {
      const r = e.getBoundingClientRect(), s = getComputedStyle(e);
      let fits = e.scrollWidth <= e.clientWidth + 1 && s.textOverflow !== "ellipsis";
      if (e.matches("input[type=submit]")) {
        ctx.font = [s.fontStyle, s.fontVariant, s.fontWeight, s.fontSize, s.fontFamily].join(" ");
        const value = s.textTransform === "uppercase" ? e.value.toUpperCase() : s.textTransform === "lowercase" ? e.value.toLowerCase() : e.value;
        const width = ctx.measureText(value).width + Math.max(0, value.length - 1) * (parseFloat(s.letterSpacing) || 0);
        const available = r.width - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight) - parseFloat(s.borderLeftWidth) - parseFloat(s.borderRightWidth);
        fits = fits && width <= available + 1;
      } else {
        const walker = document.createTreeWalker(e, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (!node.textContent.trim()) continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          fits = fits && Array.from(range.getClientRects()).every(rect => rect.left >= r.left - 1 && rect.right <= r.right + 1);
        }
      }
      return {...identity(e), fits};
    });
    return {pageFits: document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1 && main.scrollWidth <= main.clientWidth + 1, rows};
  }

  if (mode === "contrast") {
    const rows = Array.from(root.querySelectorAll("h1,h2,h3,p,label,a,button,input:not([type=hidden]),select,textarea,svg,.n-settings-tool-badge,[data-prompt-content]"))
      .filter(visible).map(e => row(e, "color", e.matches("svg") ? 3 : 4.5));
    root.querySelectorAll(".n-workspace-button,.n-settings-tool-input").forEach(e => {
      if (!visible(e)) return;
      if (e.classList.contains("n-workspace-primary")) rows.push(row(e, "backgroundColor", 3, true));
      else rows.push(row(e, "borderTopColor", 3), row(e, "borderTopColor", 3, true));
    });
    const active = document.activeElement;
    if (root.contains(active) && active.matches(controls)) {
      rows.push(row(active, "outlineColor", 3, true));
      if (active.matches("input,select,textarea")) rows.push(row(active, "outlineColor", 3));
    }
    return rows;
  }

  if (mode === "hover") {
    const e = root.querySelector("[data-tools-hover]"), s = getComputedStyle(e);
    return {...identity(e), backgroundCSS: s.backgroundColor, rgba: rgba(s.backgroundColor), bounds: e.getBoundingClientRect().toJSON(),
      hovered: e.matches(":hover"), capable: matchMedia("(hover:hover)").matches && matchMedia("(pointer:fine)").matches, decoration: s.textDecorationLine};
  }

  throw Error("Unknown Settings browser probe mode");
}
