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
The pet panel never changes size or position on hover. `PetPanelController`
shows a separate noninteractive child `NSPanel` below it for the localized quota
card; the child follows the pet when it is dragged and ignores mouse events.
The card uses bundled English and Russian strings plus system date formatting.
