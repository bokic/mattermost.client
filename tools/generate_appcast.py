#!/usr/bin/env python3
"""
Generates or updates the Sparkle appcast.xml feed for mattermost.client releases.
"""

import argparse
import datetime
import hashlib
import os
import sys
import xml.etree.ElementTree as ET


def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def format_rfc2822_date(dt=None):
    if dt is None:
        dt = datetime.datetime.now(datetime.timezone.utc)
    return dt.strftime("%a, %d %b %Y %H:%M:%S +0000")


def generate_item_xml(version, download_url, file_size, sha256_hash, release_notes_url=None, min_sys="15.0"):
    pub_date = format_rfc2822_date()
    if not release_notes_url:
        tag = f"v{version}" if not version.startswith("v") else version
        release_notes_url = f"https://github.com/bokic/mattermost.client/releases/tag/{tag}"

    clean_version = version.lstrip("v")
    item = f"""    <item>
      <title>Version {clean_version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:releaseNotesLink>{release_notes_url}</sparkle:releaseNotesLink>
      <sparkle:minimumSystemVersion>{min_sys}</sparkle:minimumSystemVersion>
      <enclosure url="{download_url}"
                 sparkle:version="{clean_version}"
                 sparkle:shortVersionString="{clean_version}"
                 sparkle:sha256="{sha256_hash}"
                 length="{file_size}"
                 type="application/octet-stream" />
    </item>"""
    return item


def update_appcast(appcast_path, version, download_url, file_size, sha256_hash, release_notes_url=None, min_sys="15.0"):
    item_xml = generate_item_xml(version, download_url, file_size, sha256_hash, release_notes_url, min_sys)

    if not os.path.exists(appcast_path):
        content = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mattermost Client Changelog</title>
    <link>https://github.com/bokic/mattermost.client</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
{item_xml}
  </channel>
</rss>
"""
    else:
        with open(appcast_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Insert after <language>en</language>
        marker = "<language>en</language>"
        if marker in content:
            content = content.replace(marker, f"{marker}\n{item_xml}", 1)
        else:
            # Fallback to inserting inside <channel>
            ch_idx = content.find("<channel>")
            if ch_idx != -1:
                insert_pos = ch_idx + len("<channel>\n")
                content = content[:insert_pos] + item_xml + "\n" + content[insert_pos:]
            else:
                sys.exit(f"Could not find <channel> tag in {appcast_path}")

    with open(appcast_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Updated {appcast_path} with version {version}")


def main():
    parser = argparse.ArgumentParser(description="Update appcast.xml with a new release")
    parser.add_argument("--appcast", default="appcast.xml", help="Path to appcast.xml")
    parser.add_argument("--version", required=True, help="Release version (e.g. 0.9.0)")
    parser.add_argument("--dmg", help="Path to release DMG file")
    parser.add_argument("--download-url", help="URL where the DMG will be hosted")
    parser.add_argument("--release-notes-url", help="URL to release notes / changelog")
    parser.add_argument("--min-sys", default="15.0", help="Minimum supported macOS version")
    parser.add_argument("--sha256", help="SHA256 checksum (computed from DMG if omitted)")
    parser.add_argument("--size", type=int, help="File size in bytes (computed from DMG if omitted)")
    args = parser.parse_args()

    clean_version = args.version.lstrip("v")
    tag = f"v{clean_version}"

    file_size = args.size or 0
    sha256 = args.sha256 or ""

    if args.dmg and os.path.exists(args.dmg):
        if not file_size:
            file_size = os.path.getsize(args.dmg)
        if not sha256:
            sha256 = compute_sha256(args.dmg)

    download_url = args.download_url
    if not download_url:
        dmg_name = os.path.basename(args.dmg) if args.dmg else f"mattermost.client-{clean_version}.dmg"
        download_url = f"https://github.com/bokic/mattermost.client/releases/download/{tag}/{dmg_name}"

    update_appcast(
        args.appcast,
        clean_version,
        download_url,
        file_size,
        sha256,
        args.release_notes_url,
        args.min_sys,
    )


if __name__ == "__main__":
    main()
