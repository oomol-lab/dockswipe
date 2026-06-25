# dockswipe

[English](./README.md) · [简体中文](./README.zh-CN.md)

[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/dockswipe/ci.yml?branch=main&label=CI&logo=github)](https://github.com/oomol-lab/dockswipe/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/oomol-lab/dockswipe?logo=github&color=blue)](https://github.com/oomol-lab/dockswipe/releases/latest)
[![Homebrew](https://img.shields.io/badge/homebrew-oomol--lab%2Ftap-orange?logo=homebrew)](https://github.com/oomol-lab/homebrew-tap)
[![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Objective--C-438eff)](./dockswipe.m)
[![License](https://img.shields.io/github/license/oomol-lab/dockswipe?color=green)](./LICENSE)

Synthesize macOS **trackpad dock-swipe gestures** from the command line — programmatically
trigger **Mission Control**, **switch desktops (Spaces)**, **App Exposé**, **Show Desktop**
and **Launchpad** through the *real trackpad gesture pathway*, with **controllable speed**
(a finger-following animation, not an instant snap).

Built for **end-to-end UI test automation**: it drives the exact system effects a 3/4-finger
trackpad swipe produces, without a keyboard shortcut and without a physical trackpad.

## Demo

Driving macOS dock-swipe gestures straight from the terminal:

<video src="https://github.com/oomol-lab/dockswipe/raw/main/assets/demo.mp4" controls muted width="100%"></video>

## Why not a keyboard shortcut or a Spaces API?

| Need | Why dock-swipe fits |
| --- | --- |
| **Trackpad pathway, not a shortcut** | These events *are* how macOS represents 3/4-finger swipes to Dock/WindowServer. `Ctrl+↑` / `Ctrl+←→` are a different path; the direct space-switch APIs (`CGSManagedDisplaySetCurrentSpace`, Hammerspoon `hs.spaces`) **cannot open Mission Control at all** — only the gesture path can. |
| **Controllable speed** | The event carries a continuous `progress` value plus `began → changed → ended` phases. Streaming progress-incrementing frames with sleeps makes the animation follow the chosen pace. |
| **Framework-agnostic** | The effect is system-global (Dock/WindowServer), so there is no per-app recognition problem (no "works in Safari, fails in Chrome"). |

## How it works

macOS encodes a trackpad 3/4-finger swipe to the Dock/WindowServer as an undocumented
"dock swipe" `CGEvent`. `dockswipe` builds that event with the private field layout and posts
it via `CGEventPost`:

- two events per step — a companion `NSEventTypeGesture` (type 29) marker + the main
  dock-control event (type 30) carrying subtype `kIOHIDEventTypeDockSwipe` (23);
- **axis** in field `123` — `1` horizontal (Spaces), `2` vertical (Mission Control / App Exposé), `3` pinch;
- **progress** (the speed value) accumulated in field `124`;
- **phase** (`began`/`changed`/`ended`) in field `132`;
- **direction** (up/down, left/right, in/out) = the **sign** of the accumulated delta;
- posted to the **session** event tap.

The private field layout is ported verbatim from **Mac Mouse Fix**
(`Helper/Core/Touch/TouchSimulator.m`); a copy is included here as
[`TouchSimulator.reference.m`](./TouchSimulator.reference.m).

## Install

### Homebrew (recommended)

```sh
brew install oomol-lab/tap/dockswipe
```

(`brew install` taps the repository automatically.) Each release ships a
separate Developer-ID-signed binary for Apple silicon and Intel; the formula
picks the right one.

### Direct download

Grab `dockswipe-<version>-<arch>.tar.gz` from the
[Releases](https://github.com/oomol-lab/dockswipe/releases) page. The binaries
are signed but **not notarized**, so a binary downloaded with a browser is
quarantined — clear it before first run:

```sh
tar -xzf dockswipe-*-arm64.tar.gz
xattr -d com.apple.quarantine dockswipe   # only needed for browser downloads
```

(Homebrew installs are not quarantined, so this step doesn't apply there.)

## Build

```sh
make build
# or invoke the compiler directly:
clang -O2 -Wall -framework CoreGraphics -framework ApplicationServices -o dockswipe dockswipe.m
```

Optional install: `make install` (to `/usr/local/bin`, override with `PREFIX=...`).

The version reported by `dockswipe --version` is baked in at compile time.
Local builds default to `0.0.0-development`; pass `make build VERSION=1.2.3` to
override it (this is how the release pipeline stamps the real version).

## Releasing

Releases are one-click: in GitHub, go to **Actions → Release → Run workflow**.
Leave the version empty to auto-bump the latest tag (patch by default, or pick
`minor`/`major`), or type an explicit `X.Y.Z`. The workflow builds and signs
both architectures, publishes a GitHub Release with the tarballs, and bumps the
Homebrew formula in [oomol-lab/homebrew-tap](https://github.com/oomol-lab/homebrew-tap).
There is no beta channel — every release is stable.

## Permissions

Grant the **running terminal / binary** Accessibility in
*System Settings → Privacy & Security → Accessibility*.
No SIP disable, no special entitlement, no code injection.

## Usage

```
dockswipe <preset> [options]
dockswipe --axis <axis> --direction <dir> [options]
```

### Presets

| Preset | Axis | Direction | Effect |
| --- | --- | --- | --- |
| `mission-control` | vertical | up | Open Mission Control |
| `app-expose` | vertical | down | App Exposé (front app's windows) |
| `space-left` | horizontal | left | Switch to the desktop on the left |
| `space-right` | horizontal | right | Switch to the desktop on the right |
| `show-desktop` | pinch | out | Spread to show desktop |
| `launchpad` | pinch | in | Pinch to open Launchpad |

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--axis <vertical\|horizontal\|pinch>` | — | Override/define the axis |
| `--direction <up\|down\|left\|right\|in\|out>` | — | Override/define the direction |
| `--offset <float>` | `1.5` | Total accumulated travel (~1.0–3.0 = a full screen) |
| `--steps <int>` | `25` | Number of animation frames (more = smoother) |
| `--interval <us>` | `8000` | Microseconds between frames (≈ real trackpad) |
| `--duration <ms>` | — | Total gesture time; **overrides** `--interval` |
| `--invert` | off | Flip the direction sign (natural-scrolling compensation) |
| `--repeat <int>` | `1` | Repeat the whole gesture N times |
| `--repeat-delay <ms>` | `400` | Pause between repeats |
| `--tap <session\|hid>` | `session` | Event tap to post to (fallback knob) |
| `--end-resends <int>` | `1` | Extra `Ended` re-posts to avoid a stuck gesture |
| `--end-resend-delay <ms>` | `200` | Delay before each resend |
| `-n, --dry-run` | off | Print the event stream instead of posting |
| `-v, --verbose` | off | Log each posted frame |
| `-h, --help` | — | Show help |
| `-V, --version` | — | Print version |

### Speed control

`speed = total_offset / (steps × interval)`. Bigger per-frame step or shorter interval =
faster; more steps + longer interval = slower and smoother.

```sh
dockswipe mission-control --steps 60 --interval 12000      # slow, silky
dockswipe space-right     --offset 2.0 --steps 12 --interval 4000   # fast
dockswipe mission-control --duration 500                   # ~0.5s total
```

### Examples

```sh
dockswipe mission-control
dockswipe app-expose --duration 300
dockswipe --axis horizontal --direction left --repeat 2 --repeat-delay 600
dockswipe space-right --dry-run -v          # inspect the event stream, post nothing
```

## Limitations & caveats

- **macOS version.** The field-based recipe is known to work **~macOS 10.11 – 26 (Tahoe)**.
  On **macOS 27+** the field path stops working; the fix is to build an `IOHIDEvent` and attach it
  via `CGEventSetHIDEvent` (see the `@available(macOS 27.0, *)` branch in
  `TouchSimulator.reference.m`; tracking: Mac Mouse Fix issue #1876, which also notes a
  "stuck transition" bug on the 27 beta).
- **Vertical Mission Control is source-confirmed, not independently repro'd.** Minimal samples
  (`joshuarli/iss`, `zackbart/mrmouse`) only exercise the horizontal axis; the vertical mapping
  comes from reading Mac Mouse Fix. **Verify on the target OS.**
- **Direction sign** depends on the *natural scrolling* setting — use `--invert` if reversed.
- **Stuck gesture.** Under load the `Ended` event can be dropped, leaving the gesture mid-animation.
  `--end-resends` mitigates this (Mac Mouse Fix resends end events at 0.2s/0.5s).
- **Commit vs peek.** The accumulated offset decides whether Mission Control truly opens or just
  peeks and snaps back. The full-open threshold isn't in the source — calibrate `--offset` per
  machine/OS.
- **Private API.** All field indices are undocumented and may be renumbered by Apple. Not
  App-Store compatible. Untested by the author — validate before use.

## Credits & sources

- **[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)** —
  `Helper/Core/Touch/TouchSimulator.m` (load-bearing field layout, vertical axis, both pre-27 and
  macOS-27 paths). Issue [#1876](https://github.com/noah-nuebling/mac-mouse-fix/issues/1876).
- **[joshuarli/iss](https://github.com/joshuarli/iss)** — single-file dock-swipe injector
  (horizontal Spaces); confirms field indices and the phase enum.
- **[zackbart/mrmouse](https://github.com/zackbart/mrmouse)** — confirms the technique still works
  on macOS 26 Tahoe.

## License

The original field layout is derived from Mac Mouse Fix (MIT). Treat this port accordingly.
