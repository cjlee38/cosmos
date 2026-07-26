---
title: Installation
weight: 2
---

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac

Release builds support both architectures.

{{< callout type="warning" >}}
Intel builds are not currently tested on physical hardware.
{{< /callout >}}

## Homebrew

```sh
brew install --cask cjlee38/tap/cosmos
```

## DMG

Download the latest DMG from
[GitHub Releases](https://github.com/cjlee38/cosmos/releases), install Cosmos,
and launch it.

## Permissions

The first-run setup shows the permissions used by Cosmos:

| Permission | Required | Why it is used |
| --- | --- | --- |
| Accessibility | Yes | Find, focus, and move application windows |
| Screen Recording | No | Capture window previews for the switchers |

Accessibility is required for window management. Screen Recording is optional;
without it, switchers use application icons and window titles instead of
captured previews.
