---
title: Configuration
weight: 4
---

Cosmos reads its YAML configuration from:

```text
~/.config/cosmos/config.yaml
```

The file is created with the default configuration on first run. Settings and
the YAML file edit the same configuration.

## Default configuration

```yaml
version: 1

switcher:
  shortcuts:
    space: option+shift+tab
    window: option+tab

window:
  shortcuts:
    center: option+command+c

spaces:
  - id: "1"
    display: 1
    shortcuts:
      switch: option+1
      move_window: option+shift+1
  - id: "2"
    display: 1
    shortcuts:
      switch: option+2
      move_window: option+shift+2
  - id: "3"
    display: 1
    shortcuts:
      switch: option+3
      move_window: option+shift+3
```

## Schema

### Top level

| Field | Type | Required | Default |
| --- | --- | --- | --- |
| `version` | integer | Yes | `1` |
| `switcher` | object | No | Switcher shortcuts disabled when omitted |
| `window` | object | No | Default window shortcuts |
| `spaces` | array | Yes | Spaces 1, 2, and 3 in a newly created file |

`version` must be `1`. `spaces` must contain at least one item, and every space
ID must be unique.

### `switcher`

| Field | Type | Default |
| --- | --- | --- |
| `shortcuts.space` | shortcut or `null` | `option+shift+tab` in a newly created file |
| `shortcuts.window` | shortcut or `null` | `option+tab` in a newly created file |

### `window`

| Field | Type | Default |
| --- | --- | --- |
| `shortcuts.center` | shortcut or `null` | `option+command+c` |

### `spaces[]`

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | Yes | One character: `0`–`9` or `A`–`Z` |
| `display` | integer | Yes | Display slot, starting at `1` |
| `shortcuts.switch` | shortcut or `null` | No | Switch to this space |
| `shortcuts.move_window` | shortcut or `null` | No | Move the focused window to this space |

Letter IDs are case-insensitive and are saved as uppercase. New spaces created
in Settings receive `Option+<ID>` and `Option+Shift+<ID>` shortcuts.

## Shortcut format

A shortcut contains zero or more modifiers and one key, joined with `+`:

```text
option+shift+1
command+k
```

Supported modifier names are `control`, `option`, `shift`, and `command`.
Setting a shortcut field to `null` disables that action. Cosmos rejects the
entire update if configured shortcuts conflict with each other.

## Saving and validation

The file contains desired configuration, while Cosmos continues running with
the last configuration that was successfully validated and applied.

- If a value is invalid, the file is kept but the running configuration is not
  changed.
- If the YAML cannot be decoded, Cosmos keeps the last valid configuration.
- Settings rewrites the file as normalized YAML. Custom comments and formatting
  may be removed.
- Settings and external editors do not merge concurrent changes. The last save
  wins.
