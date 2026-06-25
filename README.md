# 1132 Fixer

Simple macOS app for resetting local Zoom state and launching Zoom again.

## What it does

- Closes Zoom
- Checks for a VPN and stops if one is active
- Backs up local Zoom data
- Clears local Zoom data, cache, logs, and saved state
- Flushes DNS
- Stops Zoom updater processes
- Launches Zoom again
- Lets you preview and export redacted diagnostics

## Requirements

- macOS 13 or newer
- Zoom installed in `/Applications/zoom.us.app`

## Easiest setup

1. Download the latest release:
   [https://github.com/westkitty/Fixer_Fixed/releases/latest](https://github.com/westkitty/Fixer_Fixed/releases/latest)
2. Open the ZIP or DMG you downloaded.
3. Move `1132 Fixer.app` to `/Applications`.
4. Open the app.
5. If macOS asks for permission, allow the prompts you trust for:
   - administrator access
   - camera
   - microphone
   - automation / Apple Events

## How to use it

1. Quit Zoom if you want a clean start.
2. Open `1132 Fixer`.
3. Click `Start Zoom`.
4. Enter your password if macOS asks.
5. Wait for the steps to finish.
6. Zoom should open again.

If a VPN is active, the app stops on purpose. Turn the VPN off and try again.

## Diagnostics

1. Open `1132 Fixer`.
2. Click `Diagnostics`.
3. Review the preview.
4. Export it if you need a local file.

Diagnostics stay local. The app does not upload them automatically.

## Update check

Update checks are manual.

1. Open `1132 Fixer`.
2. Click `Check for Updates`.

## Build from source

```bash
swift test
swift build -c release
```

## CI release build

This repo includes a GitHub Actions workflow that can build a macOS release artifact.

Unsigned build:
- works without Apple signing secrets
- produces a ZIP artifact for manual testing

Signed build:
- requires Apple signing and notarization secrets
- is the path for smoother sharing on other Macs

Run the workflow from GitHub:

1. Open `Actions`.
2. Open `Build macOS Release`.
3. Click `Run workflow`.
4. Download the artifact from the finished run.

Verify the checksum:

```bash
shasum -a 256 1132.Fixer-v1.6.4-local-safe-ci-unsigned.zip
cat SHA256SUMS.txt
```

## Notes

- The app does not upload diagnostics automatically.
- The app does not bundle a bug report token or endpoint.
- The app does not check GitHub for updates on launch.

## License

See `LICENSE`.
