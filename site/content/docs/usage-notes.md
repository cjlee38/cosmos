---
title: Usage Notes
weight: 3
---

## Display arrangement

Set the display arrangement in macOS System Settings so it matches the physical
position of your displays. Cosmos uses that arrangement to assign display slots,
move windows between displays, and choose where inactive windows are kept.

Cosmos temporarily keeps inactive windows at a lower corner of their display.
If neighboring displays touch both lower corners, part of an inactive window
may remain visible on another display. Settings and first-run setup show a
warning for this layout.

When possible, arrange the displays so at least one lower corner of each display
does not border another display. Changing the main display or rearranging
displays can also change their slot numbers; check **Settings → Spaces** after a
display change.

## Window states

- Minimized windows keep their space membership. Cosmos does not unminimize
  them.
- `Command+H` remains a macOS app-level action. Cosmos does not treat it as a
  space change.
- Native fullscreen windows live in separate macOS Spaces and may not be tracked
  reliably when entering or leaving fullscreen.
- Sheets, menus, tooltips, system dialogs, and similar transient windows are not
  assigned to Cosmos spaces.

## Moving windows between displays

Moving a window to a space on another display changes both its position and size
in proportion to the usable area of the destination display. The menu bar and
visible Dock area are excluded from that calculation.

## Window recovery

Cosmos records the original frame before it hides a window. If a window does not
return as expected, use **Emergency Unhide** from the Cosmos menu bar menu.

Emergency Unhide restores windows that Cosmos has hidden. It does not change
windows minimized by the user or apps hidden with `Command+H`.
