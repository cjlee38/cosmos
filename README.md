<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cosmos-icon-dark.png">
    <img src="docs/assets/cosmos-icon-light.png" width="160" alt="Cosmos icon">
  </picture>
</p>

<h1 align="center">Cosmos</h1>

<p align="center">A window and space manager for macOS.</p>

> [!WARNING]
> Cosmos is still under active development. I’m currently focused on making it as stable and safe as possible.
>
> If you find a bug or have a suggestion, please feel free to [open an issue](https://github.com/cjlee38/cosmos/issues).

## Why Cosmos?

Cosmos organizes windows into virtual spaces.

The project is inspired by
[AeroSpace](https://github.com/nikitabobko/AeroSpace), a tiling window manager
for macOS. AeroSpace is great, but some of its design choices did not fit the
way I wanted to manage windows.

To keep the app simple, AeroSpace intentionally uses file-based configuration
instead of providing a GUI. Its tiling layout also manages window sizes by
default. You can work around that, but I ended up maintaining extra shell
scripts to get the behavior I wanted.

Cosmos adopted the same basic approach to virtual workspaces by moving inactive
windows to a display corner, but leaves their sizes and positions as they are.

## Features and Roadmap

- [x] Logical spaces across multiple displays
- [x] Keyboard shortcuts for switching spaces and moving windows
- [x] Space and window switchers with thumbnail previews
- [x] GUI and YAML configuration
- [x] First-run setup
- [x] Preserves window sizes and positions
- [x] Emergency recovery for hidden windows
- [x] Homebrew installation
- [ ] Rectangle/Spectacle-style window move and resize commands
- [ ] Search across windows
- [ ] CLI support
- [ ] Runtime event hooks

## Compatibility

- macOS 14 or later
- Tested on an Apple Silicon Mac running macOS Tahoe 26.5
- Release builds support Apple Silicon and Intel, but Cosmos has not been tested
  on an Intel Mac

## Installation

1. Homebrew:

   ```sh
   brew install --cask cjlee38/tap/cosmos
   ```

2. Download the latest DMG from
   [GitHub Releases](https://github.com/cjlee38/cosmos/releases).
3. Manual build:

   ```sh
   git clone https://github.com/cjlee38/cosmos.git
   cd cosmos
   just build release
   ```

   The built app is located at
   `macos/.build/xcode/Build/Products/Release/Cosmos.app`.

## Development

Build instructions, tests, project structure, and release tooling are documented
in [docs/development/README.md](docs/development/README.md).
