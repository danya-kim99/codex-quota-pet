# Workstream: real quota-consumption reaction

Status: implementation withdrawn; the production visual was rejected and a
separate redesign is required.

Shared context: [README.md](README.md)

The current production app has no automatic quota-consumption presentation.
`QuotaHistoryClassifier` and the agreed conservative transition/cadence semantics
remain useful design input, but the former procedural SwiftUI/Canvas visual and
its visual freeze are not approved for reuse. A future visual must use authored
assets and frames in the existing black-hole/reset visual language, not synthesize
the effect with a native procedural SwiftUI/Canvas animation.

The sections below preserve the original discovery and design history as a
handoff. Current status is recorded in
[Deferred real quota-consumption reaction redesign](../PRODUCT_SPEC.md#deferred-real-quota-consumption-reaction-redesign).

## Product intent

Make the pet visibly react when Codex actually consumes quota, so the black hole
feels causally connected to work rather than merely polling a percentage. The
reaction is ambient feedback, not a notification, counter, or second absorption
game.

## Current behavior

- `CodexAppServer` emits complete accepted `QuotaSnapshot` values to `AppState`.
- `AppState.didReceive` replaces `quota` and updates freshness but does not retain
  or compare the preceding snapshot.
- `BlackHoleView` derives the sprite only from the current primary remaining
  percentage.
- A manually absorbed object already produces a 150 ms ring flash, up to 2.2%
  disk pulse, and temporary 30 fps rendering through view-local `reactionStart`.
- Update notifications, the 60-second fallback, hover refresh, wake refresh, and
  reconnect can all deliver snapshots. The visual layer cannot currently tell
  which source produced a change.

Relevant files:

- `Models/AppState.swift`
- `Models/PetVisualState.swift`
- `Services/CodexAppServer.swift`
- `Views/BlackHoleView.swift`
- `Tests/RateLimitDecodingTests.swift`

## Rejected first-slice hypothesis (historical)

The withdrawn implementation used a code-native pixel/glow reaction for a confidently classified drop
in the **primary** remaining percentage within the same quota window.

- Small, medium, and large deltas may have three restrained intensity bands.
- Do not show floating text over the pet. Exact deltas belong to history or
  details UI; the pet remains readable as an ambient object.
- Reuse the current palette and SwiftUI renderer. Do not generate eleven new
  sprite sets and do not add Metal.
- Keep the current quota geometry transition authoritative. The effect layers on
  top and must not imply a different remaining percentage.
- Coalesce rapid accepted drops into at most one active/pending reaction; never
  build an unbounded animation queue.
- After the effect, return to the existing Standard/Turbo idle schedule.

This approach is rejected and is retained only as historical context.

## Trigger contract to resolve

A consumption event needs all of the following unless the design explicitly
approves a conservative fallback:

1. There is a preceding accepted primary snapshot.
2. Connection continuity is trustworthy.
3. Old and new samples refer to the same quota window.
4. New remaining percentage is lower than old remaining percentage.
5. The transition was not already classified as a reset, correction, account
   change, plan change, or discontinuity.

Define:

- how matching `resetsAt` and `windowDurationMins` establish window identity;
- what happens when one or both metadata fields are missing;
- whether a sample after sleep may animate and how long a gap is acceptable;
- whether the first sample after reconnect is always a new baseline;
- how duplicate/out-of-order responses are rejected or made harmless;
- how rapid changes are coalesced and whether deltas sum or the latest wins;
- thresholds for the visual intensity bands;
- whether a drop to 0% has a distinct but still restrained treatment.

Do not add polling for this feature. It reacts only to the app’s normal accepted
snapshots, so notification timing can be delayed by the existing refresh policy.

## Visual and interaction decisions

The design chat must settle:

- exact shape: ring flash, inward particles, brightness step, brief speed-up, or
  a small combination;
- exact duration and intensity for representative 1, 5, and 15 percentage-point
  drops;
- relationship to the existing manual-absorption flash when both overlap;
- whether the reaction is visible while the pet is dimmed/reconnecting (default
  recommendation: no new consumption classification without continuity);
- behavior at 0%, where normal rotation nearly stops;
- whether the tooltip stays visible during the effect;
- whether drag, resize, hide, fullscreen suppression, and context-menu opening
  cancel the transient effect;
- whether a setting is needed (default recommendation: no setting for the first
  slice unless the prototype is materially distracting).

The representative prototype should show the same L-size quota state in:

1. idle Standard;
2. a small real-consumption reaction;
3. a large real-consumption reaction;
4. the chosen Reduce Motion replacement.

User approval is required before implementation.

## Motion, performance, and accessibility

- Normal motion may use 30 fps only while the reaction is active.
- Reduce Motion must remove travel, acceleration, and pulse. Prefer a short
  stepped brightness/color change without geometry movement, or no additional
  effect if the user finds even that distracting.
- Existing Turbo pulse may continue only if the combined scale/brightness stays
  within an approved cap.
- Do not post a VoiceOver announcement for every quota drop by default. The
  current exact quota remains available through the labelled pet and menu bar.
- Decorative particles and overlays must remain accessibility-hidden and
  noninteractive.
- The effect must not create new child windows or expand hit testing.

## State ownership boundary

The preferred boundary is:

`accepted snapshot -> shared transition classification -> transient event in AppState -> BlackHoleView animation`

`AppState` should own the meaning and identity of the event. `BlackHoleView`
should own only ephemeral rendering progress. Do not compare quota values in the
view, and do not make `PetPanelController` interpret rate-limit data.

Use the shared transition contract from `README.md`. Reuse the local-history
implementation rather than introducing a second comparator.

## Cross-feature coordination

- A reset must never also emit a consumption reaction.
- Local history should record the same delta as a primary-window consumption
  event, including the same discontinuity decisions.
- The secondary window does not trigger this first slice unless the user
  explicitly expands the design.
- Position lock and click-through do not change classification. Click-through
  should not suppress a real event visually unless the pet itself is hidden.
- Keep manual absorption independent: it is user-triggered and cosmetic, while
  this effect is data-triggered.

## Acceptance areas to include in the freeze

- first snapshot, duplicate snapshot, 1-point drop, multi-point drop;
- same-window metadata present and missing;
- reconnect, wake, long gap, account/plan change, correction, and real reset;
- Standard, Turbo, 0%, disconnected/dimmed, and Reduce Motion;
- S/M/L scaling and no panel-edge clipping;
- overlap with one and three active absorptions;
- tooltip open, pet drag, resize, context menu, manual hide, and fullscreen hide;
- idle CPU returns to the existing schedule after the effect;
- deterministic transition tests and visual-state timing tests;
- English/Russian and VoiceOver remain unchanged unless approved copy is added;
- focused tests plus `./script/build_and_run.sh --verify` after implementation.

## Explicit non-goals

- token counts or cost estimates;
- sounds, notifications, streaks, achievements, or persistence of reactions;
- secondary-window reactions;
- new sprite-state exports, renderer, dependency, backend, or extra polling;
- automatic changes to Standard/Turbo mode or quota-reset controls.

## Paste-ready prompt for a new chat

```text
Work on the discovery and design freeze for “real quota-consumption reaction”
in /Users/danya-kim/Documents/Development/Black Hole Codex Quota Indicator.

First read, in full:
- AGENTS.md
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/feature-workstreams/README.md
- docs/feature-workstreams/quota-consumption-reaction.md

Use ponytail full and the relevant Build macOS SwiftUI skills. Reinspect the
current code and dirty worktree; preserve all user files. This chat is for
discovery, protocol/transition semantics, one representative visual prototype,
and a consolidated design freeze. Do not modify production Swift, generate the
full final asset set, or start release work until I explicitly approve the
complete design freeze for implementation.

The withdrawn procedural SwiftUI/Canvas visual must not be reused. Develop an
authored asset/frame-based direction in the existing black-hole/reset language.

Resolve every open trigger, overlap, Reduce Motion, performance, S/M/L,
tooltip/drag/menu, localization, accessibility, and failure-state decision in
the brief. Reuse the shared snapshot-transition contract; do not create an
independent raw-percentage comparator. Clearly separate confirmed repo facts,
your recommendation, and decisions that require my subjective approval.
```
