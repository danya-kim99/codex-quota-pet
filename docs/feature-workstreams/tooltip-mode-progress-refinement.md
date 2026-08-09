# Workstream: tooltip mode and progress refinement

Status: production implementation complete; automated checks and affected runtime
QA passed. Live Turbo motion and the exhaustive screenshot matrix remain
unverified because the active App Server session exposed Standard mode only.

Approved: 8 August 2026

Authoritative requirements:
[Approved Smooth and Pixel tooltip styles](../PRODUCT_SPEC.md#approved-smooth-and-pixel-tooltip-styles)

## Outcome

The quota bar or arc represents quota only. Standard and Turbo use identical
progress geometry within the same tooltip style and size. Mode moves to a
separate localized badge:

- Standard: static badge, no bolt;
- Turbo: same footprint, one decorative bolt, highlighted style-appropriate
  border/glow;
- Turbo highlight: two finite glow pulses over 2.4 seconds when eligible;
- no chevrons, start bolt, endpoint tick, or endpoint glow on any quota bar or
  arc.

Smooth and Pixel keep their own visual languages. S keeps its circular layout;
M keeps scaling the L composition. Normal-text-size card and panel dimensions do
not change.

## Representative prototype gate

The non-production comparison board is
[quota-tooltip-mode-progress-refinement-v1.png](../concepts/quota-tooltip-mode-progress-refinement-v1.png).
It shows Smooth L Standard, Smooth L Turbo at pulse peak, Russian Smooth S Turbo,
and Pixel L Turbo at pulse peak. It is a visual reference only; production stays
code-native and does not ship this bitmap.

The user must approve the badge placement, equal Standard/Turbo footprint, and
restrained peak glow in this board before production Swift changes begin. The
exact four-phase motion remains governed by the animation contract below.

## Animation contract

The pulse changes only a decorative badge-highlight overlay:

`0 -> 1 -> 0 -> 1 -> 0`, four 0.6-second `easeInOut` phases.

The resting badge surface and text remain readable throughout. The badge never
scales, moves, rotates, blinks, changes layout, or changes quota color.

Start a new pulse only for:

1. hidden to visible while mode is Turbo, connection is connected, quota is
   known and above 0%, and Reduce Motion is off;
2. Standard to Turbo while the tooltip is already visible and the same
   eligibility conditions hold.

Do not start or restart it for percentage, reset-countdown, tooltip-style, size,
placement, stale-to-fresh, missing-to-known, zero-to-positive, or Reduce Motion
on-to-off updates.

Cancel it immediately on hide, drag, context-menu opening, resize suppression,
fullscreen suppression, Turbo-to-Standard, Reduce Motion, disconnect/reconnect,
missing quota, or 0%. A later eligible hover starts from the beginning. At 0%,
missing quota, and stale/reconnecting, the known Turbo badge remains highlighted
but static.

The animation is view-local and finite. It adds no `Timer`, `TimelineView`,
continuous `Canvas`, model state, persistence, quota refresh, or network traffic.

## Minimal implementation

### `Views/QuotaTooltipView.swift`

- Delete `ProgressPresentation`, `QuotaTooltipContent.progressPresentation`,
  `progressPresentation(for:)`, `turboProgressBar`, and `TurboChevronPattern`.
- Render the existing plain Smooth progress bar for both modes.
- Remove the Turbo bolt and chevrons from the Smooth S ring.
- Remove `smallRingRadius` when it becomes unused.
- Add one local Smooth mode-badge view:
  - L/M in the header between the title and percentage;
  - S in the text column beside, never over, the circular indicator.
- Reserve the larger localized Standard versus bolt-plus-Turbo content width at
  the current text scale and center the active content; do not use an invisible
  Standard bolt or a fixed width that can clip Russian/accessibility text.
- Smooth uses natural localized casing and a fixed gold Turbo accent independent
  of quota color. Pixel keeps uppercase and its existing orange Turbo accent.
- Keep the pulse task/state at the root `QuotaTooltipView` and pass only its
  highlight intensity into the active Smooth or Pixel badge.
- Gate the pulse with one deterministic helper over tooltip visibility,
  `SpeedMode`, `ConnectionState`, remaining percentage, and Reduce Motion.

Do not create a theme engine, badge protocol, renderer factory, view model, or
new source file for this refinement.

### `Views/PixelQuotaTooltipView.swift`

- Keep the existing `modeBadge` and `PixelBolt`; the bolt is used only inside
  the Turbo badge.
- Accept the root-provided badge-highlight intensity and apply it only to the
  Turbo badge border/glow.
- Remove the Turbo branch from the L/M progress bar.
- Remove the Turbo bolt and chevrons from the S ring.
- Delete `smallRingChevronSize`, `smallRingRadius`, `PixelChevronPattern`, and
  `PixelRingChevron` when unused.

### `Support/PetPanelController.swift`

`NSPanel.orderOut` does not reliably unmount its SwiftUI tree, so bare
`onAppear`/`onDisappear` cannot own the animation lifecycle.

- Pass one controller-owned `isTooltipPresented` signal into
  `QuotaTooltipView`.
- Set it to `true` only after the current root view is installed and immediately
  before/when the panel is shown.
- Set it to `false` before every tooltip `orderOut` or suppression path.
- Preserve the actual value when refreshing placement, style, or countdown.
- Reuse the existing `NSHostingView` root where possible so style/layout refresh
  does not reset state or retrigger the pulse.

AppKit owns visibility only. It must not interpret speed mode, quota values, or
animation phases. `AppState`, quota-history models, and the App Server client do
not change for this workstream.

## Test changes

Delete obsolete tests and assertions that freeze the removed representation:

- `testPixelTurboRingChevronsStayWithinArc`;
- `testTooltipProgressPresentationUsesRealSpeedMode`;
- assertions against `QuotaTooltipContent.progressPresentation`.

Add one deterministic pulse-eligibility matrix covering:

- visible Turbo + connected + known positive quota + normal motion: eligible;
- Standard, hidden, Reduce Motion, 0%, missing quota, connecting, reconnecting,
  and disconnected: ineligible.

Extend localization coverage for the existing English and Russian Standard and
Turbo names. Keep current panel-size, placement, style-switch, accessibility,
and reset-countdown lifecycle tests as regression coverage.

Do not add a production animation model solely to unit-test elapsed time. The
fixed four-phase sequence is verified by runtime/visual QA; deterministic tests
cover its gate and controller visibility lifecycle.

## Acceptance checklist

- [x] User approves the representative badge placement and pulse-peak prototype
      and explicitly authorizes development.
- [x] Smooth Standard/Turbo progress matches pixel-for-pixel within Smooth at
      S, M, and L for 0%, a partial value, 100%, and missing quota.
- [x] Pixel Standard/Turbo progress matches pixel-for-pixel within Pixel for the
      same matrix.
- [x] No quota bar or arc contains a chevron, start bolt, endpoint tick, or
      mode-specific endpoint glow.
- [x] Standard and Turbo badges have the same footprint and stay outside progress
      geometry; only Turbo contains a bolt.
- [x] English and Russian badges fit S/M/L without changing normal-text-size
      panel dimensions.
- [ ] Eligible Turbo show and Standard-to-Turbo each run exactly two bounded glow
      pulses and settle with no idle redraw.
- [x] Hide/suppression and every ineligible state cancel an active pulse;
      unrelated data/layout updates do not restart it.
- [x] Reduce Motion keeps both badges static and readable.
- [x] Badge glow and bolt are decorative for accessibility; the existing
      localized mode and connection summary remains available once.
- [x] Hover, drag, context menu, resize, style switching, countdown updates,
      screen placement, stale handling, history, and quota traffic do not regress.
- [x] Focused and full macOS tests pass.
- [x] `./script/build_and_run.sh --verify` builds and launches the app.
- [ ] Screenshot QA covers Smooth/Pixel, S/M/L, Standard/Turbo, English/Russian,
      Reduce Motion, 0%, missing quota, and stale/reconnecting.

## Verification commands

```sh
xcodebuild -project 'Black Hole Codex Quota Indicator.xcodeproj' \
  -scheme 'Black Hole Codex Quota Indicator' \
  -configuration Debug \
  -derivedDataPath 'build/DerivedData' \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test

./script/build_and_run.sh --verify
```

## Scope guardrails

- Preserve unrelated dirty work, especially active quota-reaction/history work.
- Re-read the current diff before editing `PetPanelController`; merge around any
  parallel visibility/suppression changes instead of overwriting them.
- Do not change tooltip dimensions, quota thresholds, history-chart markers,
  reset segments, localization wording, signing, packaging, or distribution.
- Do not commit, push, publish, or release without a separate request.
