# Workstream: position lock and click-through

Status: historical discovery handoff for the implemented position-lock and
click-through baseline

Shared context: [README.md](../../README.md)

The approved and implemented contract is
[Approved position lock and pointer click-through](../PRODUCT_SPEC.md#approved-position-lock-and-pointer-click-through).

## Product intent

Let users keep the pet visible without accidentally moving or interacting with
it. Position lock preserves deliberate placement while retaining pet
interactions; click-through temporarily makes the pet ignore pointer input and
must always have an obvious recovery path through the menu bar.

## Behavior at the discovery snapshot

- `PetPanelController` creates one borderless nonactivating `NSPanel` with
  `isMovableByWindowBackground = true` and installs a local pointer monitor.
- Left down/up may become absorption or a panel drag. Movement beyond 6 pt is not
  accepted as an absorption click.
- Secondary/Control-click opens a separate transient key-capable context-menu
  panel. Hover controls a child tooltip panel that ignores mouse events.
- Opening the context menu temporarily disables background movement and restores
  it on dismissal.
- Hiding, fullscreen suppression, resizing, and scene changes clear related
  transient interaction state.
- Panel position is not currently persisted; a newly created panel begins near
  the upper-right of the main screen.
- The menu bar remains accessible even when the pet is hidden and is therefore
  the only safe place to reverse click-through.

Relevant files:

- `Models/AppState.swift`
- `Support/AppConstants.swift`
- `Support/PetPanelController.swift`
- `Views/MenuBarContent.swift`
- `Views/PixelContextMenuView.swift`
- `App/BlackHoleCodexQuotaIndicatorApp.swift`
- localization files and `Tests/RateLimitDecodingTests.swift`

## Required semantic distinction

Treat these as two independent persisted preferences:

| Mode | Drag | Hover tooltip | Absorb click | Context menu | Menu bar recovery |
| --- | --- | --- | --- | --- | --- |
| Normal | Yes | Yes | Yes | Yes | Yes |
| Position locked | No | Yes | Yes | Yes | Yes |
| Click-through | No | No pointer hover | No pointer click | No pointer click | Required |

Click-through should mean ignoring mouse/trackpad input, not hiding the pet,
pausing quota updates, or disabling accessible menu-bar controls. The design
must explicitly verify what `NSPanel.ignoresMouseEvents` does to the existing
VoiceOver element and custom accessibility actions rather than assuming.

When click-through is enabled, the stored position-lock value should remain
unchanged underneath it. Disabling click-through restores either the normal or
locked interaction policy that was previously selected.

## Recommended first-slice hypothesis

- Add localized persisted toggles to `AppState`.
- Expose both toggles in the standard menu-bar menu.
- Expose both in the pixel context menu while pointer input is available.
- Enabling click-through from the context menu dismisses the menu first, hides
  the tooltip, cancels pointer/drag tracking, and then applies mouse ignoring.
- Disabling click-through is always possible from `MenuBarExtra` without
  relaunching the app.
- Position lock changes only drag policy. Absorption, hover, secondary click,
  keyboard context-menu navigation, and VoiceOver remain available.
- Click-through does not change the panel level, all-Spaces behavior, or
  fullscreen-hiding policy.

This hypothesis does not yet decide whether panel coordinates persist across
launches.

## Decisions the feature chat must resolve

### Position persistence

“Lock position” can mean either:

1. lock movement for the current and future sessions while the normal launch
   position still resets; or
2. remember the locked coordinates and restore them on relaunch.

The second is more intuitive but expands scope into multi-display restoration.
If approved, define:

- stored coordinate system: absolute, screen-relative, or normalized;
- display identity and fallback when a display is removed or rearranged;
- behavior after resolution, Dock, menu-bar, or visible-frame changes;
- S/M/L resize behavior around the saved center;
- clamping and migration of invalid values;
- whether unlocked movement also updates the saved position.

Do not silently add edge snapping, magnetic corners, or per-Space placement;
those are separate features.

### Toggle naming and placement

Resolve concise English and Russian labels that fit the custom menu’s current
fixed width and 30-character discipline. Decide ordering relative to size,
fullscreen hiding, and launch at login. Adding rows may require an approved menu
height/layout update and retesting every screen-edge quadrant.

### Transition behavior

Define what happens when either mode changes while:

- the tooltip is visible;
- a drag is in progress;
- an absorption pointer-down has started;
- the context menu is open or closing;
- absorption objects are already animating;
- the pet is fullscreen-suppressed or manually hidden;
- VoiceOver invokes an action.

Default recommendation: already-running cosmetic absorption may finish;
interaction tracking and tooltip/context panels are cancelled before the new
pointer policy becomes active.

## Architecture boundary

Use the existing split:

- `AppState` owns persisted preference values and user intent.
- `AppDelegate` routes menu actions to the existing controller.
- `PetPanelController` applies the effective policy to `NSPanel`, pointer
  monitoring, drag handling, tooltip, and context menu.
- SwiftUI menus read state and invoke narrow actions.

Do not duplicate preference truth inside `PetPanelController`. Do not scatter
`NSWindow` discovery or mutation into SwiftUI views. The exact AppKit capability
gap is pointer/window policy; the existing controller is already the smallest
bridge.

## Accessibility and recovery requirements

- Menu-bar items must expose label, enabled state, and toggle state in English
  and Russian.
- The user must never be trapped in click-through. Menu-bar reversal works after
  launch, hide/show, reconnect, fullscreen suppression, and screen changes.
- Verify keyboard activation of both standard and pixel menus.
- Verify whether the pet’s VoiceOver custom actions remain callable in
  click-through. If not, document and design the accessible alternative before
  approval.
- No invisible tooltip or context-menu panel may remain ordered front or accept
  input after click-through begins.
- Click-through must not make the menu-bar status item inaccessible.

## Cross-feature coordination

- Consumption visuals continue while visible regardless of pointer
  policy; the feature changes input, not data or rendering.
- Secondary quota and history hover content naturally become unavailable from
  the pet during click-through but remain reachable through the approved
  menu-bar recovery/details path.
- Any future tooltip expansion must not be used as the only way to disable
  click-through.
- If position persistence is approved, it should reuse the same screen-clamping
  helpers as resizing and tooltip/context placement rather than add a second
  screen-selection policy.

## Acceptance areas to include in the freeze

- fresh install, migrated install, invalid stored values, and relaunch;
- every combination of lock and click-through;
- enabling from menu bar and from context menu, and disabling from menu bar;
- left click, 6 pt drag threshold, secondary click, Control-click, hover, and
  VoiceOver actions in each effective mode;
- tooltip/context menu open and close transitions;
- active absorptions and real consumption visuals;
- hide/show, fullscreen suppression, S/M/L resize, reconnect, and Reduce Motion;
- multiple displays and display removal if position persistence is included;
- English/Russian copy, keyboard traversal, VoiceOver state;
- pure policy tests and controller integration seams;
- focused tests plus `./script/build_and_run.sh --verify` after implementation.

## Explicit non-goals

- changing window level or all-Spaces policy;
- edge snapping, magnetic placement, per-Space position, or desktop-widget mode;
- global hotkeys or a background helper;
- accessibility/screen-recording permissions;
- changes to quota, renderer, absorption timing, signing, or distribution.

## Paste-ready prompt for a new chat

```text
Work on the discovery and design freeze for “position lock and click-through”
in /Users/danya-kim/Documents/Development/Black Hole Codex Quota Indicator.

First read, in full:
- AGENTS.md
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/feature-workstreams/README.md
- docs/feature-workstreams/position-lock-click-through.md

Use ponytail full plus build-macos-apps:window-management,
build-macos-apps:appkit-interop, and build-macos-apps:swiftui-patterns. Reinspect
the current NSPanel, pointer monitor, tooltip/context-menu lifecycle, AppState,
menus, tests, and dirty worktree. Preserve all user files.

This chat is for product semantics, a narrow AppKit architecture, localization,
accessibility/recovery behavior, and a consolidated design freeze. Do not modify
production Swift or implement until I explicitly approve the complete freeze.
Resolve whether locked coordinates persist, all multi-display consequences,
state precedence, transitions during drag/menu/absorption, and the guaranteed
menu-bar escape from click-through. Do not add window-level modes, snapping, or
other placement features unless I explicitly expand scope.
```
