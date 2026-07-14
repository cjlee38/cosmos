# kkaci

macOS-only workspace/window manager prototype.

The current runtime supports:

- enumerate macOS windows through Accessibility
- identify windows by `CGWindowID`
- move individual windows to a screen corner
- restore their original frame
- assign windows to runtime workspaces
- auto-assign newly discovered windows to the active workspace on their monitor
- prune closed/missing windows from runtime state
- switch workspaces by hiding/restoring assigned windows
- cycle configured workspaces and focus windows within the active workspace
- configure workspaces and global hotkeys through TOML

## Run

```sh
just run
```

Grant Accessibility permission when prompted. If it is granted after startup, relaunch the app or use `Request Accessibility Permission` from the menu bar. The menu bar runtime also requests Input Monitoring permission for modifier-release detection; after granting it, relaunch the app or use `Reload Config`.

Run the menu bar runtime app with:

```sh
just app
```

The menu bar app captures currently visible windows into the active workspace for each window's monitor on launch.
It also opens a debug status window; use `Show Debug Status` from the menu bar item to reopen it.

Workspace config is stored at:

```text
~/Library/Application Support/kkaci/config.toml
```

If the config does not exist, kkaci creates the default workspaces `1`, `2`, and `3`. Missing workspaces are created and persisted when used.

```toml
[workspaces]
names = ["1", "2", "3", "dev"]

[workspaces.monitors]
dev = 2

[[bindings]]
key = "ctrl+tab"
command = "next-workspace"

[[bindings]]
key = "ctrl+shift+tab"
command = "previous-workspace"

[[bindings]]
key = "option+tab"
command = "next-window"

[[bindings]]
key = "option+shift+tab"
command = "previous-window"

[[bindings]]
key = "option+1"
command = "workspace"
workspace = "1"

[[bindings]]
key = "option+shift+1"
command = "move-window-to-workspace"
workspace = "1"
```

The default config registers these global hotkeys:

```text
Ctrl+Tab              next workspace
Ctrl+Shift+Tab        previous workspace
Option+Tab            next window
Option+Shift+Tab      previous window
Option+1/2/3          switch to workspace 1/2/3
Option+Shift+1/2/3    move focused window to workspace 1/2/3
```

Use `Reload Config` from the menu bar item after editing `config.toml`.
If reload fails, kkaci keeps the previous valid config. If the initial load fails, kkaci runs with defaults until a later reload succeeds and avoids overwriting the broken config.

Workspace monitor slots are config-level roles. `monitor 1` is the current macOS main display. Other monitors are ordered by distance from the main display, then by x/y position as deterministic ties. Kkaci does not store physical display IDs in the config.

## REPL

```text
help
permission
list
focused
assign 1
assign 2 <window-id>
capture <workspace>
switch 1
switch 2
next-workspace
prev-workspace
next-window
prev-window
hide <window-id>
restore <window-id>
restore <window-id> <window-id>
workspaces
quit
```

The first window scan is treated as the baseline. Windows discovered after that are assigned to the currently active workspace.

The CLI REPL keeps the manual baseline flow. The menu bar app restores matching hidden-window records, then captures each still-unassigned visible window into the active workspace on that window's monitor.

The acceptance test for the core primitive is two windows from the same app assigned to different workspaces, then switching workspaces so only the assigned window is restored.

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
