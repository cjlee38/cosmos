# Cosmos Development

[README](../../README.md)

## Requirements

- macOS 14 or later
- Xcode
- [just](https://github.com/casey/just)

Cosmos uses macOS Accessibility APIs. Grant Accessibility permission when
prompted. If permission is granted after startup, relaunch the app or check the
permission state in Settings.

## Run the app

Clone the repository:

```sh
git clone https://github.com/cjlee38/cosmos.git
cd cosmos
```

Run the development menu bar app:

```sh
just run dev
```

The development app uses `~/.config/cosmos-dev/` so it can run alongside a
release build without sharing configuration or runtime state.

## CLI REPL

Run the development REPL with:

```sh
just repl
```

Available commands:

```text
help
permission
list
displays
focused
switch 1
move 2
unhide-all
spaces
quit
```

The REPL is currently a development and debugging surface. It is not the
planned public CLI.

## Configuration

The release app stores its configuration at:

```text
~/.config/cosmos/config.yaml
```

The development app stores its configuration at:

```text
~/.config/cosmos-dev/config.yaml
```

If the file does not exist, Cosmos creates default spaces `1`, `2`, and `3`.
Space IDs are limited to `0...9` and `A...Z`.

Settings rewrites the complete YAML file with normalized formatting. Custom
comments may be removed, and the last editor or Settings save wins.

## Tests and checks

Run the XCTest suite:

```sh
just test
```

The automated tests use fake windows and do not move real macOS windows.

Run the standard build-and-test verification:

```sh
just check
```

Run SwiftLint and Periphery:

```sh
just lint
```

Format Swift sources:

```sh
just fmt
```

## Manual window verification

Use `cosmos-fixture-app` as a separate AppKit process for Accessibility and
window-management verification:

```sh
just fixture
```

The core acceptance case is:

1. Open two windows from the same application.
2. Assign the windows to different Cosmos spaces.
3. Switch between the spaces.
4. Verify that only the assigned window is visible and that its original frame
   is restored.

## Project structure

```text
macos/
├── Apps/
│   └── Cosmos/
├── Sources/
│   ├── CosmosApp/
│   └── CosmosCore/
└── Tests/
```

- `CosmosCore` owns models, space policy, window state, macOS window adapters,
  and persistence.
- `CosmosApp` owns the menu bar UI, runtime wiring, shortcuts, switchers,
  Settings, and debug surfaces.

## Release

Release distribution runs only from the manual GitHub Actions
`Publish GitHub Releases`
workflow:

1. Run `just set-version <major.minor.patch>`, commit, and push `main`.
2. Open **Actions > Publish GitHub Releases > Run workflow**.
3. Run the workflow. It reads the version from `Version.xcconfig` and uses the
   GitHub Actions run number as the build number.
4. Wait for the workflow to create the notarized DMG, annotated tag, checksum,
   and draft GitHub Release.
5. Review and publish the draft release.

Pushing a tag does not trigger distribution. `scripts/package.sh`,
`scripts/notarize.sh`, and `scripts/release.sh` are internal workflow stages.

The repository's `Release` environment requires these GitHub Actions secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application certificate
- `MACOS_CERTIFICATE_PASSWORD`: password for the certificate archive
- `APPLE_APP_PASSWORD`: app-specific password used by `notarytool`

The Apple ID and Team ID are account identifiers, not credentials, so they are
kept in the workflow source.
