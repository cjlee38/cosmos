<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cosmos-icon-dark.png">
    <img src="docs/assets/cosmos-icon-light.png" width="160" alt="Cosmos icon">
  </picture>
</p>

<h1 align="center">Cosmos</h1>

<p align="center">A non-tiling virtual workspace manager for macOS.</p>

> [!WARNING]
> This project is under development.

## Why Cosmos?

Cosmos is a macOS space manager built around virtual workspaces.

The project is inspired by
[AeroSpace](https://github.com/nikitabobko/AeroSpace), a tiling window manager
for macOS. AeroSpace is great, but some of its design choices did not fit the
way I wanted to manage windows.

To keep the app simple, AeroSpace intentionally uses file-based configuration
instead of providing a GUI. Its tiling layout also manages window sizes by
default. You can work around that, but I ended up maintaining extra shell
scripts to get the behavior I wanted.

Cosmos uses the same basic approach to virtual workspaces by moving inactive
windows to a display corner.

## Features and Roadmap

- [x] Logical spaces for each display
- [x] Keyboard shortcuts for switching spaces
- [x] Move the focused window between spaces
- [x] Space and window switchers with thumbnail previews
- [x] Native Settings and first-run setup
- [x] YAML configuration
- [x] Multi-display support
- [x] Preservation of user-created window frames
- [x] Emergency recovery for hidden windows
- [ ] Homebrew installation
- [ ] Rectangle/Spectacle-style window move and resize commands
- [ ] Search across all managed windows
- [ ] First-class CLI
- [ ] Runtime event hooks, starting with an after-window-moved hook
- [ ] Window-space membership restoration across app restarts

## Compatibility

- macOS 14 or later
- Tested only on my Apple Silicon Mac running macOS Tahoe 26.5
- Release builds target Apple Silicon and Intel, but Intel Macs have not been tested

## Installation

1. Download the latest DMG from [GitHub Releases](https://github.com/cjlee38/cosmos/releases).
2. Manual build:

   ```sh
   git clone https://github.com/cjlee38/cosmos.git
   cd cosmos
   just build release
   ```

   The built app is located at
   `macos/.build/xcode/Build/Products/Release/Cosmos.app`.

3. Homebrew support is not available yet.

## Development

Build instructions, tests, project structure, and release tooling are documented
in [docs/development/README.md](docs/development/README.md).
