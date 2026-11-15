#!/usr/bin/env python3
"""Run a JavaScript file in a logged-in Mattermost Chrome tab.

The tab is selected by a URL substring (``--match`` or ``MM_TAB_MATCH``). The
script's final expression is stored in ``window.__mm`` and printed in chunks so
large DOM dumps survive AppleScript's reply limits.

Requirements:
  * Google Chrome with "Allow JavaScript from Apple Events" enabled
    (View > Developer > Allow JavaScript from Apple Events).
  * The user is already logged in to the Mattermost web client.

Example:
  MM_TAB_MATCH=localhost:8065 python3 tools/runjs.py tools/dom_dump.js
"""

import argparse
import os
import subprocess
import sys
import tempfile
import textwrap
import uuid

CHUNK = 40000


def applescript_literal(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def javascript_literal(js: str) -> str:
    # Collapse to one line and escape for an AppleScript string literal.
    lines = [line.strip() for line in js.splitlines() if not line.strip().startswith("//")]
    return applescript_literal(" ".join(lines))


def run_js(js: str, match: str, timeout: int = 180) -> str:
    escaped_js = javascript_literal(js)
    escaped_match = applescript_literal(match)
    script = textwrap.dedent(
        f'''
        tell application "Google Chrome"
            set targetTab to missing value
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "{escaped_match}" then
                        set targetTab to t
                        exit repeat
                    end if
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat
            if targetTab is missing value then return "ERR:NO_TAB"
            execute targetTab javascript "{escaped_js}"
        end tell
        '''
    )

    path = os.path.join(tempfile.gettempdir(), f"mm-runjs-{uuid.uuid4().hex}.applescript")
    try:
        with open(path, "w") as handle:
            handle.write(script)
        result = subprocess.run(
            ["osascript", path], capture_output=True, text=True, timeout=timeout
        )
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass

    if result.returncode != 0 or (result.stderr and not result.stdout):
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("js_file", help="JavaScript file to execute")
    parser.add_argument(
        "--match",
        default=os.environ.get("MM_TAB_MATCH", ""),
        help="URL substring identifying the Mattermost tab (or set MM_TAB_MATCH)",
    )
    args = parser.parse_args()

    if not args.match:
        parser.error("provide --match or set MM_TAB_MATCH (e.g. localhost:8065)")

    js = open(args.js_file, encoding="utf-8").read()
    wrapped = "window.__mm = (function(){" + js + "})(); String(window.__mm).length;"
    length = int(run_js(wrapped, args.match))

    parts = []
    start = 0
    while start < length:
        end = min(start + CHUNK, length)
        parts.append(run_js(f"window.__mm.slice({start},{end})", args.match))
        start = end
    print("".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
