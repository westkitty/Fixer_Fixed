# 1132 Fixer

`1132 Fixer` is a Mac app that helps you reset Zoom and start it again.

## Before you start

You need:

- a Mac running macOS 13 or newer
- Zoom installed in `/Applications/zoom.us.app`

## Install

1. Go to [westkitty/Fixer_Fixed releases](https://github.com/westkitty/Fixer_Fixed/releases/latest).
2. Download the newest file.
3. Open the ZIP or DMG.
4. Drag `1132 Fixer.app` into `/Applications`.
5. Open `1132 Fixer.app`.

If your Mac asks for permission, allow the prompts you want to allow.

## Use

1. Open `1132 Fixer`.
2. Click `Start Zoom`.
3. Enter your password if your Mac asks for it.
4. Wait for the steps to finish.
5. Zoom should open again.

If the app says a VPN is active, turn the VPN off and try again.

## Diagnostics

1. Open `1132 Fixer`.
2. Click `Diagnostics`.
3. Read the preview.
4. Export it if you want to save a copy.

The app keeps diagnostics on your Mac. It does not upload them by itself.

## Check for updates

1. Open `1132 Fixer`.
2. Click `Check for Updates`.

The app does not check for updates when it starts. Update checks are manual.

## Build a release on GitHub

1. Open the repository on GitHub.
2. Open `Actions`.
3. Open `Build macOS Release`.
4. Click `Run workflow`.
5. Choose `main`.
6. Run the workflow.
7. When it finishes, download the artifact from the workflow run.

If Apple signing secrets are not set, GitHub builds an unsigned ZIP.

## Verify the download

If the workflow gives you `SHA256SUMS.txt`, you can verify the ZIP:

```bash
shasum -a 256 1132.Fixer-v1.6.4-local-safe-ci-unsigned.zip
cat SHA256SUMS.txt
```

## Build from source

```bash
swift test
swift build -c release
```

## License

See `LICENSE`.
