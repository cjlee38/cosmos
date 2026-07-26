---
title: Overview
weight: 1
---

Cosmos is a window and space manager for macOS. It groups individual windows
into logical spaces without replacing the Dock, `Command+Tab`, or macOS native
Spaces.

## Spaces

A space is a group of windows. Each managed window belongs to one configured
space, and each display shows one space at a time.

Switching spaces changes which windows are visible. Moving a window to another
space changes its membership. When the destination space belongs to another
display, Cosmos maps the window into that display's usable area.

## Displays

Spaces are assigned to display slots:

- Display 1 is the macOS main display.
- Other displays are numbered by their position relative to the main display.
- Mirrored displays do not receive a slot.

Each display can show a different space. If a configured display is
disconnected, its spaces temporarily fall back to the main display and return
when the display reconnects.

## Window behavior

Cosmos manages regular application windows and independent utility or dialog
windows. Sheets, menus, tooltips, system dialogs, and other transient windows
are not managed.

Windows opened while Cosmos is running join the visible space on their current
display. Selecting a managed window from the Dock or `Command+Tab` switches to
the space containing that window.

## Default shortcuts

| Action | Shortcut |
| --- | --- |
| Open the window switcher | `Option+Tab` |
| Open the space switcher | `Option+Shift+Tab` |
| Switch to space 1, 2, or 3 | `Option+1`, `Option+2`, `Option+3` |
| Move the focused window to space 1, 2, or 3 | `Option+Shift+1`, `Option+Shift+2`, `Option+Shift+3` |
| Center the focused window | `Option+Command+C` |

Spaces and shortcuts can be changed in Settings or in the
[configuration file](../configuration/).
