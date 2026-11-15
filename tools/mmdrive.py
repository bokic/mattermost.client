#!/usr/bin/env python3
"""Capture a DOM/computed-style dump from the logged-in Mattermost web client.

``tools/dom_dump.js`` stores a JSON string in ``window.__mm`` and returns its
length. This driver reads that string back in chunks and writes it to JSON for
comparison with the native AppKit layout.

Requirements:
  * Google Chrome with "Allow JavaScript from Apple Events" enabled.
  * A logged-in Mattermost tab matching ``--match``/``MM_TAB_MATCH``.

Example:
  MM_TAB_MATCH=localhost:8065 python3 tools/mmdrive.py
  MM_TAB_MATCH=localhost:8065 python3 tools/mmdrive.py --out /tmp/dom.json
"""

import argparse
import json
import os
import sys

from runjs import run_js

HERE = os.path.dirname(os.path.abspath(__file__))
CHUNK = 40000


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "js_file",
        nargs="?",
        default=os.path.join(HERE, "dom_dump.js"),
        help="dump script that sets window.__mm (default: tools/dom_dump.js)",
    )
    parser.add_argument(
        "--match",
        default=os.environ.get("MM_TAB_MATCH", ""),
        help="URL substring identifying the Mattermost tab (or set MM_TAB_MATCH)",
    )
    parser.add_argument(
        "--out",
        default=os.path.join(HERE, "dom_dump.json"),
        help="output JSON path (default: tools/dom_dump.json)",
    )
    args = parser.parse_args()

    if not args.match:
        parser.error("provide --match or set MM_TAB_MATCH (e.g. localhost:8065)")

    js = open(args.js_file, encoding="utf-8").read()
    length = int(run_js(js, args.match))

    parts = []
    start = 0
    while start < length:
        end = min(start + CHUNK, length)
        parts.append(run_js(f"window.__mm.slice({start},{end})", args.match))
        start = end
        print(f"  read {start}/{length} chars", flush=True)

    data = json.loads("".join(parts))
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=1)
    print(f"wrote {args.out} ({os.path.getsize(args.out)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
