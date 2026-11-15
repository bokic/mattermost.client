// Capture a computed-style snapshot of the Mattermost web client for parity work.
// Run through tools/mmdrive.py; the driver reads window.__mm back in chunks.
(function () {
  const PROPS = [
    'display', 'position', 'flexDirection', 'alignItems', 'justifyContent', 'gap',
    'backgroundColor', 'color', 'opacity',
    'fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing',
    'padding', 'margin', 'border', 'borderRadius', 'boxShadow', 'outline',
    'width', 'height', 'minWidth', 'minHeight', 'overflow'
  ];

  const styleOf = function (el) {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const out = { rect: { x: +r.x.toFixed(2), y: +r.y.toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2) } };
    for (const p of PROPS) out[p] = s[p];
    return out;
  };

  const pick = function (sel) {
    const el = document.querySelector(sel);
    if (!el) return { sel: sel, missing: true };
    return { sel: sel, tag: el.tagName.toLowerCase(), cls: String(el.className), text: (el.innerText || '').slice(0, 160), style: styleOf(el) };
  };

  const SELECTORS = [
    '.app__body', '.sidebar--left', '.sidebar-header', '.sidebar-header__info',
    '.team-sidebar', '.sidebar-channel', '.sidebar-item', '.sidebar-item__name',
    '.channel-header', '.channel-header__info', '.channel-header__title',
    '.post-list', '.post-list__table', '.post', '.post__header', '.post__body',
    '.post-create', '.post-create-body', '.textarea-wrapper', '#post_textbox',
    '.advanced-textarea', '.post-body__cell', '.post__content',
    '.sidebar-right', '#SidebarContainer', '.status-wrapper', '.status',
    '.Avatar', '.MenuWrapper', '.channel-intro', '.date-separator'
  ];

  const vars = {};
  ['--sidebar-bg', '--sidebar-header-bg', '--sidebar-text', '--sidebar-unread-text',
   '--center-channel-bg', '--center-channel-color', '--button-bg', '--button-color',
   '--link-color', '--mention-bg', '--mention-color', '--sidebar-team-background'
  ].forEach(function (v) { vars[v] = getComputedStyle(document.body).getPropertyValue(v).trim(); });

  // Full computed-style map for every element under .app__body (tree, with depth).
  const tree = [];
  const root = document.querySelector('.app__body');
  const walk = function (el, depth) {
    if (!el || depth > 14) return;
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    tree.push({
      t: el.tagName.toLowerCase(),
      c: String(el.className).slice(0, 120),
      d: depth,
      r: [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)],
      bg: s.backgroundColor,
      fg: s.color,
      fs: s.fontSize,
      fw: s.fontWeight,
      lh: s.lineHeight,
      p: s.padding,
      m: s.margin,
      br: s.borderRadius,
      b: s.border,
      bs: s.boxShadow === 'none' ? '' : s.boxShadow
    });
    const kids = el.children;
    for (let i = 0; i < kids.length && i < 60; i++) walk(kids[i], depth + 1);
  };
  walk(root, 0);

  const payload = {
    capturedAt: new Date().toISOString(),
    url: location.href,
    dpr: devicePixelRatio,
    viewport: { w: innerWidth, h: innerHeight },
    bodyClass: document.body.className,
    themeVars: vars,
    elements: SELECTORS.map(pick),
    tree: tree,
    appHTML: (root || document.body).outerHTML.slice(0, 300000)
  };

  window.__mm = JSON.stringify(payload);
  return String(window.__mm.length);
})();
