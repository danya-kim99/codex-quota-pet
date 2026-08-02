# Black Hole Codex Quota Indicator

A native macOS floating pet that represents the remaining Codex quota as an
animated black-hole accretion disk.

The app reads the main Codex rate-limit bucket from the locally installed Codex
App Server. It renders the live value as a transparent, always-on-top black hole
whose accretion disk grows and accumulates gold, orange, and purple color layers.
Hovering the pet shows a localized quota card with the exact percentage, reset
time, a dynamic day countdown, and a progress bar whose appearance reflects
Standard or Turbo mode; detailed status remains available from the menu bar.
The app also reads the effective Codex
service tier: Fast/Turbo rotates 1.5 times faster and adds a pulse, while Reduce
Motion freezes both effects. The menu can hide or restore the pet and optionally
hide it while another application is fullscreen. If the local Codex process
stops, the pet reconnects automatically and the menu offers an immediate retry.
The menu also controls whether the main app launches when the user logs in.
VoiceOver announces the exact quota, speed mode, and connection state. Standard
mode updates only when its pixel-art frame changes; Turbo keeps a smooth 30 fps
pulse, and Reduce Motion freezes both effects.

The renderer uses a compact pixel-art style. Its three color layers rotate and
animate independently around a fixed black core.

Product decisions are recorded in `docs/PRODUCT_SPEC.md`, and the technical
boundary is recorded in `docs/ARCHITECTURE.md`.

## Requirements

- macOS 14 or newer
- Apple silicon for the `v0.1.0` preview build
- A locally installed and authenticated Codex CLI

## Install the private preview

1. Download and unzip the release archive.
2. Move `Black Hole Codex Quota Indicator.app` to `/Applications`.
3. Open the app. Because the private preview is not notarized, macOS may require
   one-time approval in **System Settings → Privacy & Security → Open Anyway**.

Do not disable Gatekeeper. The app can enable Launch at Login from its menu
after it is installed in `/Applications`.

## Local verification

```sh
./script/build_and_run.sh --verify
```

Run the unit tests with:

```sh
xcodebuild -project 'Black Hole Codex Quota Indicator.xcodeproj' \
  -scheme 'Black Hole Codex Quota Indicator' \
  -configuration Debug \
  -derivedDataPath 'build/DerivedData' \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
