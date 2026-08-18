# Workstream: real quota-consumption reaction

Status: production implementation complete on 12 August 2026; automated tests,
build/launch verification, reviewer, and accessibility QA passed. Missed GUI
holds and a comparable idle-CPU before/after sample remain uninstrumented.

Shared context: [README.md](README.md)

The production app implements the automatic quota-consumption presentation from
[Relativistic Hotspot Plunge](../PRODUCT_SPEC.md#approved-real-quota-consumption-reaction-relativistic-hotspot-plunge).
It uses the existing `QuotaHistoryClassifier`, finite authored lossless APNG
playback, one active plus one strongest merged pending event, a 24 fps
Small/Medium/Large/Last Light ladder, static 360 ms Reduce Motion treatment, and
the existing black-hole canvas and phase handoff. The withdrawn procedural
SwiftUI/Canvas implementation remains prohibited.

The concept references are the four `quota-consumption-*-preview-v1.gif` files
under `docs/concepts/`. The four approved lossless RGBA masters under
`Assets/Sprites/frames/quota-consumption-master-*.apng` now freeze shipping
pixels and authorize the complete bucket/phase bake. Their normative hashes are
recorded in `PRODUCT_SPEC.md`.

The sections below preserve the original discovery questions as historical
handoff context. The product-spec freeze supersedes any conflicting hypothesis.

## Product intent

Make the pet visibly react when Codex actually consumes quota, so the black hole
feels causally connected to work rather than merely polling a percentage. The
reaction is ambient feedback, not a notification, counter, or second absorption
game.

## Historical production behavior before implementation

- `CodexAppServer` emits complete accepted `QuotaSnapshot` values to `AppState`.
- The implemented `QuotaHistoryClassifier` compares accepted primary transitions
  for local history. `AppState` has no consumption cadence, active/pending event,
  or automatic-reaction playback state.
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

## Historical trigger questions resolved by the freeze

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

## Historical visual and interaction questions resolved by the freeze

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

## Historical motion, performance, and accessibility questions

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

The approved boundary is:

`accepted snapshot -> shared transition classification -> transient event in AppState -> BlackHoleView animation`

`AppState` should own the meaning and identity of the event. `BlackHoleView`
should own only ephemeral rendering progress. Do not compare quota values in the
view, and do not make `PetPanelController` interpret rate-limit data.

Use the shared transition contract from `README.md`. Reuse the local-history
implementation rather than introducing a second comparator.

## Cross-feature coordination

- A reset must never also emit a consumption reaction.
- A true reset clears active and pending consumption plus cadence.
- Local history should record the same delta as a primary-window consumption
  event, including the same discontinuity decisions.
- The secondary window does not trigger this first slice unless the user
  explicitly expands the design.
- Position lock and click-through do not change classification. Click-through
  should not suppress a real event visually unless the pet itself is hidden.
- Manual absorption is user-triggered and has presentation priority: starting it
  cancels active and pending consumption, and consumption during it advances
  cadence without visual queue or replay.

## Frozen acceptance coverage

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
- exact-percentage, mode-specific, or size-specific art;
- a new renderer, dependency, backend, process, read, or extra polling;
- automatic changes to Standard/Turbo mode or quota-reset controls.

## Implementation record

- Shipping assets are 264 full-scene APNGs plus one three-slot Reduce Motion
  overlay. The consumption directory is 274,590,536 bytes (268,680 KiB
  allocated); the final verified Debug app is 283,596 KiB. The complete matrix is a
  measured product-size risk, not a specification violation; changing topology
  or format requires a new design decision.
- Cold ImageIO decode across 30 files per kind measured: Small median/p95
  5.492/7.401 ms, Medium 10.970/14.409 ms, Large 16.100/21.426 ms, and Last
  Light 23.826/29.585 ms.
- Worst-case Last Light active plus Large pending added 4,505,600 bytes RSS and
  retained 475,136 bytes one second after release. A separate cancellation
  stress of all 264 assets over six rounds showed 16,384 bytes growth after the
  warm round and no per-decode accumulation.
- The final canonical test run passed 87/87 tests in 71.752 seconds; the full
  production-asset validator took 69.351 seconds.
  `./script/build_and_run.sh --verify` and `git diff --check` passed.
- A five-second post-implementation idle Debug sample observed 0.0–2.0% CPU and
  about 27 MB RSS. There is no comparable pre-implementation sample, so no idle
  CPU delta is claimed. Missed authored holds inside the real GUI were not
  instrumented; finite production playback and process liveness were smoke
  tested for every kind at S and L.
