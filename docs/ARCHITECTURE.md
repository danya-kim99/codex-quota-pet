# Architecture

## Platform

- Native SwiftUI application targeting macOS 14 or newer.
- A narrow AppKit bridge owns the transparent nonactivating `NSPanel`.
- SwiftUI renders one of eleven six-frame transparent pixel-art sprite loops.
  Native image loading and nearest-neighbor interpolation keep the renderer
  dependency-free and preserve hard pixel edges.
- `MenuBarExtra` owns application controls and diagnostics.
- The application uses accessory activation and does not appear in the Dock.

## Data flow

`Codex App Server -> AppState -> renderer, tooltip, and menu bar`

`AppState` is the SwiftUI source of truth. The AppKit panel receives state but
does not own product data.

## Modules

- `App`: application entry point and lifecycle.
- `Models`: domain and visual state.
- `Services`: Codex App Server integration.
- `Views`: SwiftUI menu, sprite renderer, and localized hover card.
- `Support`: constants and the narrow `NSPanel` adapter.

The app consumes the documented Codex App Server protocol and does not
scrape Codex UI or private application files.

The current client launches the installed Codex executable with the stable
stdio JSONL transport, reads `account/rateLimits/read`, selects the main
`codex` bucket, and refetches after `account/rateLimits/updated` notifications.
Because those notifications are local to turns handled by the same App Server
process, the passive pet also refreshes every 60 seconds, when a user hovers an
older-than-30-second snapshot, and after macOS wakes from sleep. Concurrent
quota reads are coalesced into the existing in-flight request.
It polls `config/read` for the effective `service_tier`; `fast` and its request
value `priority` map to the Turbo visual state. A failed config read leaves quota
connectivity untouched and falls back to Standard mode.
`AppState` owns reconnection. Failures schedule one retry task with a capped
1–2–5–10–30 second backoff; a successful quota snapshot resets that sequence,
and the menu can cancel the wait and retry immediately. `CodexAppServer` stops
its previous process before every start and tags callbacks with a session ID so
late output from an old process cannot affect the new connection.
`PetVisualState` maps the exact remaining percentage to the nearest 10% sprite
state and derives the current frame from animation time and mode. `TimelineView`
plays the six-frame loop; Turbo advances it 1.5 times faster and adds a bounded
2% scale pulse. Every frame shares one canvas and anchor, so the core stays
fixed while the color-layer highlights move. Standard mode schedules updates at
the actual sprite-frame interval (about 0.7–7.1 Hz depending on quota) instead
of refreshing at 30 Hz. Turbo retains 30 Hz only while its pulse is active.
`PetPanelController` keeps the SwiftUI renderer in a transparent floating
surface across Spaces and fullscreen windows. `AppState` owns the session-level
visibility flag; the menu action asks the controller to order the existing panel
in or out instead of recreating it. An optional `UserDefaults` preference hides
the panel when the frontmost layer-zero window matches a screen frame. The
controller reevaluates that condition when the active Space or application
changes, without requiring Accessibility or Screen Recording access.
`AppState` also owns the persisted S/M/L pet-size preference. The renderer reads
the selected scene dimensions directly, while `PetPanelController` resizes the
native panel around its current center and clamps it to the visible screen.
Absorption path fitting keeps the nominal 48/64/80 pt model envelope, while
SwiftUI renders each 80 px absorbable asset in a 1.25× transparent field so
extra canvas padding does not change the visible model scale or trajectory.
The pet panel never changes size or position on hover. `PetPanelController`
shows a separate noninteractive child `NSPanel` for the localized quota card;
the child follows the pet when it is dragged and ignores mouse events. `L` uses
the existing tooltip, `M` scales it to 80%, and `S` uses a dedicated compact
circular-quota layout in a 272 × 132 pt panel. The card uses bundled English and
Russian strings plus system date formatting.
`QuotaTooltipContent` is the shared semantic input for the focused Smooth and
Pixel SwiftUI presentations. Progress geometry represents quota only; each
presentation renders its own separate mode badge. `PetPanelController` owns
only the tooltip panel's explicit presented/hidden signal and reuses the
existing `NSHostingView` root across countdown, style, layout, and placement
refreshes. `QuotaTooltipView` owns the finite visible-only Turbo-badge highlight
task and cancels it from that signal; AppKit does not inspect quota or own
animation phases. The task uses no timer, `TimelineView`, persistence, or
network request and settles with no idle redraw after its bounded cycle.
`QuotaHistoryClassifier` classifies accepted primary-window transitions once
for history and the transient consumption effect. A credible reset remains a
classifier result and history boundary, never a consumption event. `AppState`
owns consumption continuity and cadence. `BlackHoleView` renders only accepted
finite consumption events, handles manual-absorption priority, and returns to
the existing idle schedule after completion. AppKit may suppress presentation
while the pet is hidden, dragged, resized, or covered by its context menu, but
never interprets quota values. Consumption events are session-local,
accessibility-hidden, and add no persistence, process, polling, dependency, or
network traffic.
`PetPanelController` also owns a separate transient key-capable `NSPanel` for
the custom pixel context menu. Local pointer monitoring distinguishes secondary
clicks from absorption and dragging, while a short-lived global monitor closes
the menu after clicks in other applications. SwiftUI reads live settings from
`AppState`; menu actions call the same state methods as the menu bar and do not
refresh quota. Hit testing, screen-quadrant placement, and the reversible
spaghettification state are pure helpers covered by tests.

`AppState` owns the independent persisted position-lock and pointer-click-through
preferences. `PetPanelController` applies their single effective `NSPanel`
policy, keeps the menu-bar toggle as the recovery path, and uses named native
frame restoration only for locked placement; display changes reuse the existing
positive-intersection screen selection and visible-frame clamping.
