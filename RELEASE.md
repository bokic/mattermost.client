# Release checklist

The release build is produced by `build_release.sh`. It signs nested code
inside-out (never with `codesign --deep`), verifies the hardened runtime,
submits the app and DMG to Apple's notary service, staples the tickets, runs a
Gatekeeper assessment and writes a SHA-256 checksum next to the DMG.

## One-time setup

1. Install a **Developer ID Application** certificate in the login Keychain.
2. Store notarization credentials:

   ```bash
   xcrun notarytool store-credentials "mattermost-client-notary" \
       --apple-id "you@example.com" --team-id "TEAMID" \
       --password "app-specific-password"
   ```

   Alternatively export `NOTARYTOOL_APPLE_ID`, `NOTARYTOOL_PASSWORD` and
   `NOTARYTOOL_TEAM_ID`, or the App Store Connect API key variables
   (`NOTARYTOOL_KEY`, `NOTARYTOOL_KEY_ID`, `NOTARYTOOL_ISSUER`).

## Every release

```bash
# 1. Choose the version and tag it. version.sh derives the build number from
#    the nearest tag plus the commits since it.
git tag v0.9.0
git push origin main --tags

# 2. Verify the source baseline.
./build.sh
./test.sh
./lint.sh

# 3. Build, sign, notarize, staple and checksum. This requires the certificate
#    and notarization credentials above.
DEVELOPER_ID_APPLICATION="Developer ID Application: Example (TEAMID)" \
NOTARYTOOL_PROFILE="mattermost-client-notary" \
./build_release.sh

# 4. Verify the artifact on a clean Mac (or VM) before publishing.
DMG="build/Build/Products/Release/mattermost.client-$(./version.sh --full).dmg"
hdiutil verify "$DMG"
shasum -a 256 -c "$DMG.sha256"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
```

4. Launch the mounted app on a clean machine: restore a session, switch
   channels/teams, send/edit/delete, upload/download, open the RHS panels,
   exercise zoom, resize/relaunch and confirm Gatekeeper does not block it.

5. Publish the DMG, its `.sha256` file, and commit the updated `appcast.xml`.
   `build_release.sh` automatically updates `appcast.xml` using `tools/generate_appcast.py`.

## Auto-Update and Appcast Feed

The application includes a native auto-update mechanism (`UpdateChecker.swift`):
- **Feed URL**: `https://raw.githubusercontent.com/bokic/mattermost.client/main/appcast.xml` (configurable via `SUFeedURL` in `Info.plist` or `customUpdateFeedURL` in `UserDefaults`).
- **Integrity**: Each release enclosure in `appcast.xml` records the release version, file length, and SHA-256 checksum (`sparkle:sha256`) matching the published DMG.
- **User Controls**: Users can trigger manual checks via **Mattermost > Check for Updates…** in the menu bar, or through **Settings > Updates > Check for updates** in the right-hand panel. Automatic checks can also be toggled in Settings.
- **Manual Download**: Users who do not have internet connectivity or prefer manual updates can download the DMG directly from GitHub Releases: `https://github.com/bokic/mattermost.client/releases`.

## Local-only builds

CI builds a universal ad-hoc DMG for smoke testing:

```bash
./build_release.sh --adhoc
```

This is intentionally **not** suitable for distribution: Gatekeeper will reject
it on another Mac.

## Current limitation

The repository does not contain a Developer ID certificate or notary
credentials, so a real notarized artifact can only be produced by a maintainer
with access to those secrets (or by the protected CI release job once the
secrets are configured).
