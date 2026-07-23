# cosmos

macOS-only space/window manager prototype.

The current runtime supports:

- enumerate macOS windows through Accessibility
- identify windows by `CGWindowID`
- move individual windows to a screen corner
- restore their original frame
- assign windows to runtime spaces
- auto-assign newly discovered windows to the active space on their monitor
- prune closed/missing windows from runtime state
- switch spaces by hiding/restoring assigned windows
- cycle configured spaces and focus windows within the active space
- configure spaces and global hotkeys through YAML

## Run

```sh
just repl
```

Grant Accessibility permission when prompted. If it is granted after startup, relaunch the app or check the permission state in Settings.

Run the menu bar runtime app with:

```sh
just run dev
```

The menu bar app captures non-minimized windows discovered during startup into the active space for each window's monitor. Use `Show Debug Status` from the menu bar item when runtime state needs inspection.

Space config is stored at:

```text
~/.config/cosmos/config.yaml
```

The development app uses `~/.config/cosmos-dev/config.yaml` so it can run alongside the release app without sharing runtime state.

If the config does not exist, cosmos creates the default spaces `1`, `2`, and `3`. Space IDs are limited to `0...9` and `A...Z`; letter IDs are normalized to uppercase. Runtime commands only use configured spaces; a missing space is a no-op and is never added to the config automatically.

```yaml
version: 1

switcher:
  shortcuts:
    space: option+shift+tab
    window: option+tab

spaces:
  - id: 1
    display: 1
    shortcuts:
      switch: option+1
      move_window: option+shift+1
  - id: D
    display: 2
    shortcuts:
      switch: option+d
      move_window: option+shift+d
```

The default config registers these global hotkeys:

```text
Option+Shift+Tab      cycle space
Option+Tab            cycle window
Option+1/2/3          switch to space 1/2/3
Option+Shift+1/2/3    move focused window to space 1/2/3
```

Use `Reload Config` from the menu bar item after editing `config.yaml`.
If reload fails, cosmos keeps the previous valid config. If the initial load fails, cosmos runs with defaults until a later reload succeeds and avoids overwriting the broken config.
Settings rewrites the complete YAML file with a standard help header. Custom comments and formatting may be removed, and the last editor or Settings save wins.

Space monitor slots are config-level roles. `monitor 1` is the current macOS main display. Other monitors are ordered by distance from the main display, then by x/y position as deterministic ties. Cosmos does not store physical display IDs in the config.

## REPL

```text
help
permission
list
displays
focused
switch 1
switch 2
move 2
unhide-all
spaces
quit
```

The CLI is a client of the same Core command model as the menu bar app. It restores matching hidden-window records, then captures each still-unassigned visible window into the active space on that window's monitor. It does not expose CLI-only window or space behavior.

The acceptance test for the core primitive is two windows from the same app assigned to different spaces, then switching spaces so only the assigned window is restored.

## Tests

The XCTest suite uses fake windows and does not move real macOS windows:

```sh
just test
```

Run the build-and-test check with:

```sh
just check
```

Run SwiftLint and Periphery with:

```sh
just lint
```

Format Swift sources with:

```sh
just fmt
```
