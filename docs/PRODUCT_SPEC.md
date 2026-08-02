# Product specification

## Product goal

Show the remaining Codex quota as a persistent macOS black-hole pet without
requiring the user to keep the Codex window open.

## Confirmed behavior

- The accretion disk grows as quota is consumed.
- The black core and its photon ring remain the same size at every quota value.
- From 100% through 60%, the disk is gold.
- From 50% through 30%, an orange layer appears and reaches full strength.
- From 20% through 0%, a purple layer appears and reaches full strength.
- Each 10% quota state uses a six-frame transparent pixel-art loop. Gold,
  orange, and purple accumulate while their highlights animate at distinct
  phases inside that loop.
- The renderer uses a limited pixel-art palette with stepped edges and glow.
- Hover shows a compact localized card with the exact remaining quota, a
  mode-specific progress bar, dynamic day segments, and reset time. Standard
  uses a smooth bar; Turbo adds a bolt, chevrons, and edge glow. English and
  Russian follow the macOS app language. The menu bar uses the same localized
  quota, mode, status, and action labels. The card has no actions.
- Standard mode rotates continuously.
- Fast mode rotates 1.5 times faster and pulses without changing quota geometry.
- At zero quota, the disk reaches its largest purple state, rotation nearly
  stops, and Fast-mode pulsing is disabled.
- The pet is a draggable, transparent, always-on-top macOS surface with a menu
  bar control and no Dock icon. The menu can hide and restore the pet without
  quitting the application.
- The app respects Reduce Motion. A persisted menu setting can hide the pet
  automatically while another application is fullscreen.
- VoiceOver announces the exact remaining quota, Standard or Turbo mode, and
  connection state from both the pet and menu bar status item.
- If Codex App Server disconnects, the pet keeps the last known quota visible
  in a dimmed state and retries after 1, 2, 5, 10, then at most 30 seconds. The
  menu shows the reconnecting state and provides `Retry Now`.
- All processing is local. There is no backend, analytics, or cloud sync.

## MVP boundary

The first release includes Codex App Server connectivity, quota and reset data,
Standard/Fast detection, the approved renderer states and animations, the
floating panel, hover details, menu bar settings, launch at login, and
accessibility behavior. Reconnection states are implemented.

Skins, controlling Fast mode, resetting quota, cross-device sync, and non-macOS
platforms are outside the MVP.

## Current MVP status

- The functional pet, all eleven quota states, Turbo behavior, Reduce Motion,
  VoiceOver summaries, fullscreen preference, and reconnect flow are implemented.
- Launch at login is implemented with the native `SMAppService` main-app login
  item and verified through a logout/login cycle using an Apple Development
  signed build.
- Local Debug build, launch, and twenty-two unit tests pass. The tests cover all
  66 bundled sprite frames, quota mapping, Turbo behavior, visibility,
  fullscreen policy, launch-at-login state handling, and automatic/manual
  reconnects.
- A local unsigned Release build passes. During an eight-second active-animation
  sample it held approximately 3.1–3.2% CPU and 21 MB of memory without growth.
- Runtime recovery was verified by terminating only the app's child Codex App
  Server process; the pet stayed alive and started a replacement automatically.
- Live macOS Accessibility-tree inspection verifies one labelled pet element
  with the current quota, speed mode, connection state, and reset time.
- The approved app icon and matching menu-bar icon are integrated through the
  native asset catalog.
- Distribution remains blocked on a clean Git baseline, Developer ID signing,
  notarization, and validation on a clean Mac. None of those release settings
  or external operations were changed during preflight.
