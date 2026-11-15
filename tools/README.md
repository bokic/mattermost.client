# Parity tooling

Utilities used to measure the live Mattermost web client and compare it with the
native AppKit layout. They require Google Chrome with
**View → Developer → Allow JavaScript from Apple Events** enabled, and a
logged-in Mattermost tab.

Set the tab matcher to a substring of your server URL:

```bash
export MM_TAB_MATCH=localhost:8065
```

## DOM / computed-style dump

```bash
python3 tools/mmdrive.py
```

Reads `tools/dom_dump.js`, which snapshots the viewport, theme CSS variables, a
selected set of layout elements and a computed-style tree under `.app__body`.
The result is written to `tools/dom_dump.json` (ignored by git — it contains
live message text, so do not commit it).

Useful comparisons:

- `viewport` / `dpr` — reference geometry and Retina scale.
- `elements` — computed styles and rects for the web client's sidebar, header,
  timeline, composer, RHS and avatars.
- `tree` — full depth-limited style tree for measuring anything else.
- `themeVars` — CSS variables that back the server theme.

## Ad-hoc JavaScript

```bash
python3 tools/runjs.py path/to/snippet.js
```

The snippet's final expression is stored in `window.__mm` and printed in chunks.
This is useful for measuring one selector without generating a full dump:

```js
(() => {
  const el = document.querySelector('.post-create');
  const s = getComputedStyle(el);
  const r = el.getBoundingClientRect();
  return JSON.stringify({ rect: r.toJSON(), radius: s.borderRadius, padding: s.padding });
})();
```

## Zoom HUD measurement

```bash
swift tools/hud_measure.swift /path/to/zoom-hud.png [scale]
```

Scans a screenshot for the dark zoom-percentage pill and prints the pill/text
bounds and padding in points. The default scale is `2.0` (Retina); pass `1.0`
for a 1x capture.

## Notes

- These scripts only read from the already-open tab; they do not log in or
  store credentials.
- Chrome's AppleScript bridge is intentionally disabled by default. Enable it
  only on a development machine.
- `dom_dump.json` is git-ignored because message text and user identifiers may
  appear in the `appHTML` field.
