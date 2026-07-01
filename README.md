# kkaci

Prototype macOS workspace/window manager.

This first spike verifies the core primitive:

- enumerate macOS windows through Accessibility
- identify windows by `CGWindowID`
- move individual windows to a screen corner
- restore their original frame
- assign windows to in-memory workspaces
- auto-assign newly discovered windows to the active workspace
- prune closed/missing windows from in-memory state
- switch workspaces by hiding/restoring assigned windows
- cycle configured workspaces and focus windows within the active workspace
- configure workspaces and global hotkeys through TOML

## Run

```sh
just run
```

Grant Accessibility permission when prompted, then restart the executable if macOS requires it.

Run the menu bar runtime app with:

```sh
just app
```

The menu bar app captures currently visible windows into workspace `1` on launch.
It also opens a debug status window; use `Show Debug Status` from the menu bar item to reopen it.

Workspace config is stored at:

```text
~/Library/Application Support/kkaci/config.toml
```

If the config does not exist, kkaci creates the default workspaces `1`, `2`, and `3`. Missing workspaces are created and persisted when used.

```toml
[workspaces]
names = ["1", "2", "3", "dev"]

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

## REPL

```text
list
focused
assign 1
assign 2 <window-id>
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

The CLI REPL keeps the manual baseline flow. The menu bar app performs an initial capture into workspace `1`.

The acceptance test for the core primitive is two windows from the same app assigned to different workspaces, then switching workspaces so only the assigned window is restored.

## Tests

The XCTest suite uses fake windows and does not move real macOS windows:

```sh
just test
```

Run the full local check with:

```sh
just check
```
