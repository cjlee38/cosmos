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

## Packaging

Create a signed Universal DMG:

```sh
just package
```

Create, submit, staple, and verify a notarized DMG:

```sh
just notarize <version>
```

These distribution commands require the project's Developer ID certificate and
notarization credentials. They are intended for maintainers rather than local
development builds.
