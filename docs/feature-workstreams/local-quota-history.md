# Workstream: local quota history

Status: historical discovery handoff for the implemented local-history baseline

Shared context: [README.md](README.md)

This document preserves the original discovery handoff. The authoritative
implemented contract is
[Approved local quota history](../PRODUCT_SPEC.md#approved-local-quota-history).

## Product intent

Give the user a small, honest view of how the observed Codex quota changed over
time while keeping every byte local. The first slice should answer “how has my
available quota moved recently?” without pretending to know exact token use or
account activity that happened while the app was not observing.

## Current behavior

- `AppState` keeps only the latest `QuotaSnapshot` and a private freshness date.
- The App Server delivers integer percentages, duration, and reset timestamps;
  it does not deliver a historical series to this app.
- The app refreshes at normal product-defined moments and may be closed,
  disconnected, asleep, or attached to an App Server process that does not see
  notifications from other processes.
- There is no application data store besides small `UserDefaults` preferences.
- Tooltip layouts are tightly approved: full L, scaled M, and dedicated compact
  S. The custom context menu deliberately contains no quota detail.
- All processing is currently local, with no analytics or cloud sync.

Relevant files:

- `Models/AppState.swift`
- `Services/CodexAppServer.swift`
- `Views/QuotaTooltipView.swift`
- `Views/MenuBarContent.swift`
- `Support/AppConstants.swift`
- `Support/PetPanelController.swift`
- localization files and `Tests/RateLimitDecodingTests.swift`

## Truthful data semantics

History is a record of **observed snapshots**, not a usage ledger.

- A drop from 82% to 79% is an observed change of 3 percentage points, not an
  exact token count.
- A gap while the app is closed/disconnected must remain visible as a gap or
  unknown interval, not a continuous inferred line.
- An increase is not negative usage. It may be a real reset, correction, or
  discontinuity and must use the shared transition classification.
- Integer rounding means several real Codex actions may appear as one later
  percentage-point change.
- The feature must not scrape Codex logs, conversations, credentials, private
  files, or UI to fill gaps.

User-facing copy should use terms equivalent to “observed”, “quota change”, and
“percentage points”. Do not claim “tokens spent” or a complete account history.

## Recommended first-slice storage hypothesis

Use a small versioned `Codable` file under the application’s own Application
Support directory. Avoid Core Data, SwiftData, SQLite, and third-party packages.

A sample can contain only what the app already receives and needs:

- observation timestamp;
- selected limit identity/name and plan type when present;
- optional primary window: remaining percent, duration, reset timestamp;
- optional secondary window with the same fields;
- a format version at the file level.

Suggested write policy to validate in design:

- accept data only from the existing successful-snapshot path;
- append on a meaningful value/window/identity change;
- add a sparse heartbeat, perhaps hourly, only if required to distinguish an
  observed flat period from an offline gap;
- deduplicate identical rapid reads;
- prune by both approved retention and a hard sample-count ceiling;
- write atomically and off the rendering path;
- if decoding fails, preserve/quarantine the unreadable file and start an empty
  in-memory history rather than silently overwriting the only copy.

Starting retention recommendation: 30 days with a conservative hard cap. The
design chat must decide the actual duration, heartbeat, and cap based on the
chosen UI and realistic sample volume.

## Recommended first-slice presentation hypothesis

Keep the feature ambient:

- L/M quota details show a small recent sparkline and a concise change such as
  “−8 p.p. observed in 24 h”.
- Gaps are visibly broken/dashed; a reset is a distinct boundary marker.
- S uses a separately designed compact summary rather than shrinking the chart;
  options are one delta line, a very small arc trend, or omitting history from S.
- Primary history is visualized first. Secondary samples may be stored from day
  one so the file format does not need an immediate migration, but secondary
  history UI is not required in the first slice.
- A longer-range dashboard, prediction, or new settings window is not part of
  the first slice unless the user explicitly prefers it over tooltip history.

This hypothesis must be coordinated with the secondary-window design. The six
untracked tooltip concepts under `docs/concepts/` must be preserved and their
status clarified with the user before choosing a new layout.

## Product decisions the feature chat must resolve

### Retention and sampling

- 7, 14, or 30 days, or a window-relative policy;
- change-only samples versus sparse heartbeat;
- maximum sample count and deterministic pruning;
- primary-only versus both windows in storage;
- what establishes account/plan/limit continuity;
- whether wake/reconnect samples extend a line or start a gap;
- timestamp source and behavior when the system clock moves backward/forward.

### Presentation

- time range shown by default;
- exact chart treatment for resets, corrections, missing data, and flat periods;
- L/M size and whether existing panel dimensions change;
- dedicated S behavior;
- Standard/Turbo styling without implying different history semantics;
- whether the menu bar gets a compact history line or action;
- whether the user needs a full history surface later.

### User control and privacy

- a visible “Clear Local History…” action and confirmation behavior;
- whether history collection is always on or optional (default recommendation:
  local-on with clear retention/copy, unless user research prefers opt-in);
- whether disabling collection deletes or merely pauses existing history;
- corrupted-file recovery and user-facing error policy;
- storage location documentation and exclusion from cloud behavior.

## Architecture boundary

Preferred flow:

`CodexAppServer -> AppState accepts snapshot -> shared transition classifier -> small history store -> derived chart model -> tooltip/details view`

Requirements:

- `AppState` remains the source of truth for the current live snapshot.
- A focused history store owns persistence, retention, and decoding; views never
  read files directly.
- Use Foundation `Codable`, atomic file replacement, and an injected test URL or
  file boundary. Do not introduce a database abstraction for one small file.
- Persistence must not block animation or App Server reads on the main actor.
- Rendering consumes already-decimated/derived points and does not scan an
  unbounded file on every `TimelineView` tick.
- The transition classifier is shared with consumption/reset features. History
  does not invent a second meaning for increases or reconnects.

Do not finalize class/file names before the design is approved; the implementation
should add the fewest focused files needed by the frozen behavior.

## Local history and event features

The Smooth/Pixel tooltip-style workstream is the first implementation priority.
Do not freeze or implement a history tooltip layout until both style foundations
and their shared content boundary are approved.

The history workstream is the natural first owner of durable window identity and
retention, but transient visuals must not require persistence to run.

- A consumption marker equals the same primary same-window percentage drop used
  by the reaction feature.
- A reset marker equals the classifier's credible rollover boundary.
- Correction/account-change/unknown boundaries break the line and produce no
  consumption visual.
- The first sample after uncertain continuity starts a new observed segment.
- If history is disabled or corrupted, current quota and the consumption
  reaction must continue through their in-memory paths.

## Accessibility, localization, and performance

- Chart meaning must be available as concise text; VoiceOver cannot rely on the
  line shape or color.
- Use localized date/time and percentage-point copy in English and Russian.
- Color alone cannot distinguish reset markers, gaps, and normal consumption.
- Decorative chart marks are accessibility-hidden after an equivalent summary
  is provided.
- The chart does not animate continuously. Reduce Motion removes any optional
  reveal transition but does not remove data.
- Loading, pruning, and encoding must be bounded. Measure launch and tooltip
  latency with a maximum-size fixture.
- The app must continue correctly with a missing, empty, old-version, partially
  corrupt, or unwritable store.

## Acceptance areas to include in the freeze

- empty/fresh store, relaunch, deduplication, heartbeat, pruning, and hard cap;
- atomic write failure, corrupt JSON, unknown future version, and unwritable path;
- same-window drop, reset rollover, correction, account/plan change, reconnect,
  wake, long offline gap, duplicate, and clock change;
- primary/secondary absent or partial metadata;
- L/M/S presentation, every tooltip placement, and current user tooltip concepts;
- Standard/Turbo, Reduce Motion, disconnected stale state, and click-through;
- clear-history action and confirmation if approved;
- English/Russian copy and a complete VoiceOver equivalent;
- fixture-driven store/classifier/chart tests and maximum-size performance check;
- no extra App Server reads or network/cloud activity;
- focused tests plus `./script/build_and_run.sh --verify` after implementation.

## Explicit non-goals for the first slice

- exact tokens, cost, request counts, or complete account activity;
- predictive “quota will run out” modelling;
- cloud sync, export, analytics, backend, or cross-device history;
- scraping Codex logs, tasks, UI, credentials, or private files;
- Core Data, SwiftData, SQLite, or third-party chart/storage packages;
- full dashboard/settings window unless explicitly approved during design;
- notifications, streaks, achievements, or gameplay progression.

## Paste-ready prompt for a new chat

```text
Work on the discovery and design freeze for “local quota history” in
/Users/danya-kim/Documents/Development/Black Hole Codex Quota Indicator.

First read, in full:
- AGENTS.md
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/feature-workstreams/README.md
- docs/feature-workstreams/local-quota-history.md

Use ponytail full and the relevant Build macOS SwiftUI skills. Reinspect the
current snapshot/freshness flow, tooltip variants, localization, tests, App
Server schema/live metadata, and dirty worktree. Preserve all user files and the
six untracked tooltip concepts; ask me what status those concepts have before
using them as an approved layout.

This chat is for truthful observed-history semantics, minimal local persistence,
privacy/user-control decisions, a representative L/M/S presentation prototype,
and a consolidated design freeze. Do not modify production Swift, add a
database/dependency, or implement until I explicitly approve the complete
freeze. Reuse the shared snapshot-transition contract. Resolve retention,
sampling/heartbeat, gaps, reset/correction/account boundaries, corruption and
write failure, clear-history behavior, secondary storage, tooltip coexistence,
localization, accessibility, and bounded performance. Never label observed
integer percentage changes as exact token usage.
```
