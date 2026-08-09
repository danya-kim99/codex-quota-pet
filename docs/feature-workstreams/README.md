# Feature workstreams

Status: mixed historical handoff and implementation record; see each workstream

Prepared: 5 August 2026

Original discovery snapshot: `v0.4.2`, HEAD `8246e57`

## Purpose

This folder lets five future Codex chats develop related features without
depending on the context of the chat that created them. Each feature has one
self-contained brief and a paste-ready prompt. This index is the shared source
for product and architecture invariants that apply to every workstream.

The briefs authorize discovery, protocol verification, product design, one
representative visual prototype where needed, and preparation of a consolidated
design freeze. They do **not** authorize production implementation. The project
workflow in `AGENTS.md` still requires explicit user approval of the complete
design freeze before production Swift or final asset work begins.

## Workstreams

1. **Implemented:** [Smooth / Pixel tooltip styles](tooltip-style-selection.md)
2. **Implemented:** [Real quota-consumption reaction](quota-consumption-reaction.md)
3. **Deferred:** [Secondary quota window](secondary-quota-window.md) — expected
   adoption is too low to justify the tooltip, accessibility, localization, and
   QA surface now; retain the existing menu fallback and discovery references.
4. **Implemented:** [Position lock and click-through](position-lock-click-through.md)
5. **Implemented:** [Local quota history](local-quota-history.md)

Approved implementation follow-up:

- [Tooltip mode and progress refinement](tooltip-mode-progress-refinement.md) —
  text and visual freeze approved on 8 August 2026; production implementation
  and affected runtime QA are complete.

## Current product baseline

- Native macOS 14+ accessory application with no Dock icon.
- `MenuBarExtra` provides persistent recovery and configuration access.
- A transparent, borderless, nonactivating `NSPanel` hosts the black-hole pet.
  It is currently floating, joins all Spaces, and can appear beside fullscreen
  applications unless the user enables fullscreen hiding.
- SwiftUI and `AppState` are the source of truth. `PetPanelController` is the
  narrow AppKit boundary for panel, tooltip, context-menu, pointer, placement,
  and fullscreen behavior.
- The local Codex App Server is launched over stdio. The app reads
  `account/rateLimits/read`, selects the `codex` bucket, and decodes optional
  `primary` and `secondary` windows.
- Each quota window contains integer `usedPercent` and optional
  `windowDurationMins` and `resetsAt`. Remaining percentage is clamped to
  `100 - usedPercent`.
- The primary window drives the eleven 10% sprite states, exact hover value,
  reset card, menu-bar headline, and accessibility summary. The secondary
  window is currently shown only as a percentage line in the standard menu-bar
  menu.
- Successful quota reads happen at startup, after same-process update
  notifications, every 60 seconds, on a stale hover, and after wake. Concurrent
  reads are coalesced.
- On disconnect the pet keeps the last snapshot, dims it, and reconnects with a
  capped backoff. A first snapshot, reconnect, duplicate response, correction,
  consumption, and real reset are not currently distinguished as domain events.
- Standard animation schedules only sprite-frame changes. Turbo uses 30 fps for
  its pulse. Reduce Motion freezes rotation and Turbo pulsing. Absorption may
  temporarily use 30 fps and has its own 150 ms photon-ring reaction.
- The pet supports S, M, and L scenes. L and M use the full tooltip at 100% and
  80%; S uses a separately designed compact circular card. Tooltip placement is
  tested on all four sides and clamped to the visible screen.
- Left click absorbs an object, movement beyond 6 pt drags the panel, and
  secondary/Control-click opens the custom context menu. The context menu has
  pointer, keyboard, and VoiceOver paths.
- English and Russian localization, VoiceOver, Reduce Motion, multi-display
  behavior, reconnection, fullscreen hiding, and launch at login are existing
  acceptance dimensions, not optional polish.
- All processing is local. There is no backend, analytics, cloud sync, account
  scraping, Codex UI scraping, or direct quota mutation.

Re-read `AGENTS.md`, `docs/PRODUCT_SPEC.md`, and `docs/ARCHITECTURE.md` at the
start of every feature chat. This snapshot is orientation, not a substitute for
the current files.

## Verified protocol boundary

The installed `codex-cli 0.147.0-alpha.1.2` can generate an App Server JSON
Schema. On 5 August 2026 that schema confirmed:

- `account/rateLimits/read` and `account/rateLimits/updated` exist;
- `RateLimitSnapshot.primary` and `.secondary` are optional
  `RateLimitWindow` values;
- `usedPercent` is required and integer;
- `windowDurationMins` and `resetsAt` are nullable integers;
- update notifications are sparse and clients should merge them or refetch.

The schema does **not** define the product meaning of “primary” and “secondary”
or guarantee that either one always represents a fixed named duration. A future
agent must not hardcode labels such as “5-hour” or “weekly” from memory. It must
inspect the schema and focused live values from the locally installed Codex
version, then derive a localized duration label from `windowDurationMins` or use
a neutral label when duration is unavailable.

The current client deliberately refetches the complete snapshot after update
notifications. None of these features should add a second polling loop or
additional App Server process.

## Shared quota-transition semantics

Two workstreams consume changes between successful snapshots:

- quota-consumption reaction;
- local history.

They must agree on one semantic classification. Otherwise a reset can be stored
as “negative consumption”, a reconnect can produce a false animation, or two
visual effects can fire for one update.

A design must classify, at minimum:

| Transition | Required behavior |
| --- | --- |
| First accepted snapshot | Establish baseline; never animate consumption or reset. |
| Identical snapshot | Refresh freshness only; no new history point unless an approved heartbeat policy requires it. |
| Same window, lower remaining percentage | Consumption candidate with a positive percentage-point delta. |
| Window rollover with a credible reset boundary | Reset candidate; never also classify as consumption. |
| Remaining percentage increase without a credible rollover | Correction/unknown; no celebratory event by default. |
| Account, plan, or limit identity change | Discontinuity; do not compare usage across it. |
| First snapshot after lost continuity | Re-establish baseline unless the approved design has enough persisted evidence to classify it safely. |

“Same window” should prefer stable evidence: matching non-null reset timestamps,
compatible window durations, and unchanged limit/account context. Missing
metadata must lead to a documented conservative fallback, not confident
guessing. Percent values are integer observations, not token counts. Product
copy must say percentage points or quota change, never claim exact tokens.

No concrete shared Swift abstraction is frozen yet. During design, agree on the
contract first. During implementation, keep the comparison in one domain seam
owned by the app state/model layer, then let transient visuals and persistence
consume its result. Do not independently compare raw percentages inside
multiple SwiftUI views.

## Cross-workstream ownership

| Concern | Owner |
| --- | --- |
| Snapshot acquisition and connection freshness | Existing `CodexAppServer` and `AppState`; features consume accepted snapshots. |
| Shared transition classification | Reused by local history and consumption reactions. |
| Durable samples, retention, corruption handling | Local-history workstream. |
| Transient consumption visual | Consumption-reaction workstream. |
| Secondary window’s product representation | Secondary-window workstream. |
| Main panel pointer and movement policy | Position-lock/click-through workstream. |
| Tooltip style foundation and shared content contract | Smooth/Pixel tooltip-style workstream. |
| Future tooltip content changes | Secondary and history must target both frozen tooltip styles. |

Recommended implementation order after all relevant designs are approved:

1. Smooth/Pixel tooltip style selection and shared tooltip-content boundary.
2. Shared transition contract and local-history storage seam.
3. Consumption events against that contract.
4. Secondary/history tooltip composition for both styles after a single combined
   layout review.
5. Position lock and click-through at any time; it is data-independent.

The design chats may proceed separately. Do not implement them concurrently in
one worktree. Serialize changes or use explicitly isolated branches/worktrees,
then rebase each implementation on the latest accepted product specification.

## Existing user work to preserve

At the time of this handoff, six untracked concept images existed under
`docs/concepts/`:

- `quota-tooltip-standard-arcade-lm-v1.png`
- `quota-tooltip-standard-arcade-s-v1.png`
- `quota-tooltip-turbo-arcade-lm-v1.png`
- `quota-tooltip-turbo-arcade-s-v1.png`
- `quota-tooltip-turbo-clean-concept-v1.png`
- `quota-tooltip-turbo-pixel-menu-style-v1.png`

They belong to the user. Never delete, overwrite, or move them. On 6 August
2026, the user explicitly designated the `quota-tooltip-*.png` concepts as the
visual references for a selectable Pixel tooltip style, while the current
tooltip remains the Smooth style. The four `*-arcade-lm/s-v1` images form the
complete Standard/Turbo and L/M/S reference family. The two additional Turbo
concepts are comparisons for typography and degree of pixel styling; they do
not create a third style unless the user explicitly chooses one.

## Shared non-goals

Unless the user explicitly expands scope during a feature chat, do not add:

- a backend, account system, analytics, telemetry upload, or cloud sync;
- quota reset controls, service-tier controls, or any write to the Codex account;
- scraping of Codex UI, credentials, private app files, or unrelated windows;
- a new renderer, database framework, third-party dependency, or background
  helper process;
- sounds, skins, currencies, progression, achievements, or notifications;
- signing, entitlements, deployment target, distribution, or release changes.

## Skills for future chats

Use only the relevant subset:

- `ponytail` full — mandatory project rule; reuse existing native seams.
- `build-macos-apps:swiftui-patterns` — state ownership and macOS UI composition.
- `build-macos-apps:window-management` and
  `build-macos-apps:appkit-interop` — position lock and click-through.
- `build-macos-apps:build-run-debug` — real `.app` build and runtime checks after
  implementation is authorized.
- `build-macos-apps:test-triage` — only when tests fail.
- `screenshot` — installed globally during this handoff; available from the next
  turn for reproducible macOS window capture when no better capture tool exists.
- `imagegen` — only if the user asks for a raster visual prototype; do not use it
  to replace code-native SwiftUI effects or existing sprite assets by default.

## Definition of a completed design chat

A feature chat is ready for implementation only when it has:

1. Revalidated the current repo and working tree without disturbing user files.
2. Resolved every decision listed in its feature brief.
3. Verified any external protocol assumption against the installed Codex version
   or recorded it as bounded uncertainty.
4. Produced and received user approval for one representative visual prototype
   when the feature changes the pet or tooltip appearance.
5. Written one consolidated design-freeze section covering normal, Turbo,
   Reduce Motion, S/M/L, tooltip/menu behavior, hover/drag/pointer behavior,
   localization, accessibility, freshness/failure, persistence/privacy where
   relevant, non-goals, and acceptance criteria.
6. Recorded the approved behavior in `docs/PRODUCT_SPEC.md`.
7. Received an explicit instruction to begin implementation after that record is
   complete.

“Looks good”, “fix this prototype”, or approval of one subsection is not approval
to implement the entire feature.
