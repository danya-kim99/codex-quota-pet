# Workstream: secondary quota window

Status: deferred on 8 August 2026; not approved for implementation

Shared context: [README.md](README.md)

## Deferral decision

The product owner deferred this workstream because, in their experience, very
few users enable an additional quota and the expected value does not justify the
tooltip, localization, accessibility, layout, and regression surface now. This
is a product judgment, not an analytics finding; the app intentionally has no
analytics. The focused live sample collected during discovery also had no
secondary window, but one sample does not establish adoption.

Keep the existing neutral secondary percentage line in the regular menu as the
low-cost fallback. Do not add secondary to the pet, Smooth/Pixel tooltips,
VoiceOver summary, reset scheduler, or approved product behavior while this
decision stands.

The discovery notes and representative
[`secondary-quota-details-first-v1`](../concepts/secondary-quota-details-first-v1.png)
prototype are retained as references, not as an approved design freeze. Their
geometry and mode/history assumptions may become stale and must not be copied
into production without a fresh review.

Resume only after the product owner explicitly reverses this decision because
of a direct product need or repeated credible user demand. A resumed workstream
must revalidate the then-current repository, App Server schema and live
metadata, tooltip/history/mode contracts, and consolidated design freeze before
implementation. Never infer a fixed duration or `weekly` label from this
archived discovery.

## Product intent

Expose the second Codex rate-limit window as a legible supporting signal without
weakening the primary relationship: the accretion disk remains the main quota
indicator, while the secondary window explains longer-term pressure.

## Current behavior and confirmed data

- `QuotaSnapshot` already decodes optional `primary` and `secondary`
  `QuotaWindow` values from the selected `codex` bucket.
- Both windows can carry integer used percentage, duration in minutes, and reset
  timestamp.
- The primary window drives the pet, full tooltip, compact S tooltip, menu
  headline, and VoiceOver summary.
- The secondary window currently appears only as a neutral percentage line in
  `MenuBarContent`; its duration and reset time are not presented.
- The installed App Server schema names the windows “primary” and “secondary”
  but does not promise fixed human names or durations.
- Current product requirements freeze the black core and photon ring at the same
  size for every **primary** quota state. Any variable outer visual must avoid
  changing or obscuring that approved geometry, or explicitly update the product
  freeze with user approval.

Relevant files:

- `Services/CodexAppServer.swift`
- `Models/AppState.swift`
- `Models/PetVisualState.swift`
- `Views/BlackHoleView.swift`
- `Views/QuotaTooltipView.swift`
- `Views/MenuBarContent.swift`
- `Support/PetPanelController.swift`
- `Resources/en.lproj/Localizable.strings`
- `Resources/ru.lproj/Localizable.strings`
- `Tests/RateLimitDecodingTests.swift`

## Recommended first-slice hypothesis

Keep the primary window fully authoritative for disk geometry and add two
secondary representations:

1. A clearly labelled secondary section in quota details, including exact
   remaining percentage, duration-derived label, and reset time when available.
2. A restrained, visually independent outer pixel orbit or segmented halo that
   communicates secondary remaining percentage without resizing the black core,
   photon ring, or primary accretion disk.

The outer representation must be validated as a single visual prototype before
it is accepted. If the user finds a dual pet encoding ambiguous, the valid
fallback is tooltip/menu-only secondary information. “Feature exists” does not
require forcing two percentages into the pet art.

This is a design hypothesis, not approval.

## Protocol and labelling decisions

The feature chat must run a focused check against the currently installed Codex
App Server and record representative values for:

- presence or absence of secondary;
- primary and secondary `windowDurationMins`;
- reset timestamps;
- plan/limit identifiers that can establish continuity.

Do not hardcode “5 hours”, “weekly”, or any other duration from memory. Preferred
copy derives a localized duration label from `windowDurationMins`, for example a
neutral equivalent of “5-hour window” or “7-day window”. If duration is missing,
use “Primary” / “Secondary” or another user-approved neutral label.

Resolve:

- how durations are formatted for unusual values and Russian pluralization;
- whether the product calls the values “windows”, “limits”, or another term;
- what is shown when percentage exists but reset time or duration is missing;
- what is shown when secondary disappears after previously existing;
- whether an account/plan change needs an immediate UI baseline reset.

No new endpoint or polling cadence is needed.

## Visual decisions

The representative prototype must compare at least:

- primary high / secondary high;
- primary high / secondary low;
- primary low / secondary high;
- both low;
- no secondary value;
- Standard and Turbo;
- Reduce Motion;
- one L tooltip and the compact S presentation.

Resolve:

- orbit/halo shape, pixel density, palette, and whether “remaining” maps to
  filled or missing segments;
- whether the secondary visual rotates, stays static, or has only frame-level
  variation;
- how it remains distinct from the purple low-primary layer, Turbo glow,
  absorption fragments, and reset/consumption effects;
- whether it scales uniformly at S/M/L without clipping absorbed objects;
- whether the existing tooltip grows, replaces redundant content, or adopts one
  of the user’s untracked tooltip concepts;
- whether history later shares the same tooltip space.

Inspect the six untracked `docs/concepts/quota-tooltip-*.png` files, but do not
edit them or assume they are approved. Ask the user what role they play before
using them as the new baseline.

## Tooltip and accessibility requirements

- The exact primary value must remain most prominent.
- Primary and secondary need explicit localized labels; visual proximity alone
  is insufficient.
- If both reset times are present, the card must make each reset unambiguous.
- The L/M card and dedicated S card need separate layout decisions. Do not merely
  shrink additional text into S.
- Missing secondary should collapse cleanly instead of displaying a misleading
  100%, 0%, or empty decorative orbit.
- VoiceOver must distinguish both windows, percentages, and reset times without
  turning the pet value into an excessively long repeated announcement.
- Decorative orbit/halo segments must be hidden from accessibility.
- The context menu still intentionally contains no quota detail.

## Motion and performance

- Standard must keep event-driven sprite scheduling. A static or sprite-timed
  secondary visual is preferred over a permanent 30 fps animation.
- Turbo may share the existing 30 fps timeline only when necessary; it must not
  start a second timeline.
- Reduce Motion freezes all new orbit movement and leaves a fully understandable
  static state.
- The outer visual cannot enlarge panel bounds, hit-test bounds, or tooltip
  anchors unless the approved design explicitly changes and retests them.
- Any code-native visual should use the existing SwiftUI renderer and palette;
  no Metal or third-party renderer.

## Cross-feature coordination

- The Smooth/Pixel tooltip-style workstream is the first implementation
  priority. Do not freeze or implement secondary tooltip composition until its
  shared content boundary and both style geometries are approved.
- Primary remains the sole trigger for the first consumption-reaction slice.
  Secondary reactions are a later explicit scope decision.
- Local history may store both windows, but its first visualization may remain
  primary-only. The data labels and duration formatter should be consistent.
- If both secondary and history alter the tooltip, perform one combined tooltip
  design review before either production implementation. Do not land two
  independently approved layouts that cannot coexist.
- Position lock/click-through has no data dependency but must preserve hover and
  tooltip behavior when pointer interaction is enabled.

## Acceptance areas to include in the freeze

- secondary present, absent, appears, disappears, and has partial metadata;
- diverse primary/secondary percentages and reset-order combinations;
- duration-derived English and Russian labels/plurals;
- Standard, Turbo, 0% primary, disconnected stale snapshot, and Reduce Motion;
- S/M/L, every tooltip placement, screen-edge clamping, and multiple displays;
- no conflict with absorption, consumption reaction, or Turbo glow;
- compact and complete VoiceOver summaries;
- no new polling and no idle frame-rate regression;
- decoding/formatting/layout/visual-state unit tests;
- focused tests plus `./script/build_and_run.sh --verify` after implementation.

## Explicit non-goals

- assuming fixed named durations without runtime evidence;
- letting the user switch or mutate Codex limits;
- displaying token counts, prices, or invented forecasts;
- secondary-driven notifications or reactions in the first slice;
- replacing the primary disk mapping;
- a new renderer, dependency, backend, analytics, or cloud sync.

## Reactivation prompt

Use this only after the product owner explicitly resumes the deferred feature.

```text
The deferred “secondary quota window” workstream has been explicitly resumed.
Work on a fresh discovery and design freeze in
/Users/danya-kim/Documents/Development/Black Hole Codex Quota Indicator.

First read, in full:
- AGENTS.md
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/feature-workstreams/README.md
- docs/feature-workstreams/secondary-quota-window.md

Use ponytail full and the relevant Build macOS SwiftUI skills. Reinspect the
current code, generated schema/live values from the locally installed Codex App
Server, and dirty worktree. Preserve the six untracked tooltip concepts and ask
me whether they are references or intended replacements before treating them as
approved.

This chat is for protocol verification, copy and layout decisions, one
representative dual-window visual prototype, and a consolidated design freeze.
Do not modify production Swift, generate the full final asset set, or implement
until I explicitly approve the complete freeze. Never hardcode “weekly” or a
fixed duration without runtime evidence. Resolve S/M/L, Standard/Turbo, Reduce
Motion, missing data, tooltip, localization, accessibility, performance, and
cross-feature coexistence with history/consumption/reset.
```
