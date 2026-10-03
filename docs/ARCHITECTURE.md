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

The optional Codex reset watch is a separate path with an explicit failure state:
`codex-resets.com -> CodexResetRadar -> AppState -> tooltip announcements footer`. It never
feeds the Codex App Server connection, personal quota, reset timestamp, local
history, retry state, or menu-bar status. `CodexResetRadar` uses one fixed
unauthenticated HTTPS GET, a 10-second timeout, a bounded response body, strict
schema and endpoint validation, and native `URLSession` with cookies and its
cache disabled. `AppState` owns opt-in, ETag/freshness metadata, request
coalescing, cancellation and generation guards. Start, enable, wake and a real
hidden-to-visible tooltip transition and the existing visible-tooltip countdown
lifecycle share the same stale gate (minimum 60 seconds and longer cache/retry
intervals). There is no separate background polling timer or persisted response.
The validated response retains scheduled, latest and watch data separately;
shared presentation deduplicates event IDs and expires latest events after 24
hours from their announcement, never from their fetch. A stale/failed source is
unavailable, distinct from a successful empty response. The footer adds 68 or
102 pt before the existing M scaling, and panel geometry uses the same state.

The existing `account/rateLimits/read` response also supplies the personal,
account-level reset-credit confirmation. The decoder tolerantly accepts only a
nonnegative `rateLimitResetCredits.availableCount`; malformed or missing credit
metadata becomes unknown without rejecting the quota snapshot. `AppState` keeps
the count only in memory while the matching App Server connection is current,
outside `QuotaSnapshot`, quota history, and preferences. Shared
`QuotaTooltipContent` always presents the personal count independently of the
external footer and distinguishes confirmed zero from unknown. Public news
never proves personal availability. This path adds no request, timer,
persistence, authentication flow, or consume operation.

## Modules

- `App`: application entry point and lifecycle.
- `Models`: domain and visual state.
- `Services`: Codex App Server integration.
- `Services/CodexResetRadar.swift`: isolated third-party reset-watch transport
  and validation.
- `Views`: SwiftUI menu, sprite renderer, and localized hover card.
- `Support`: constants and the narrow `NSPanel` adapter.

The app consumes the documented Codex App Server protocol and does not
scrape Codex UI or private application files.

## Optional response-ready notices

The default-off notice has its own event path:
`Codex notify -> headless app invocation -> native local IPC -> AppState verification -> child NSPanel`.
It does not infer completion from quota or subscribe to another process's turn
notifications. The normal app entry point handles `--black-hole-notify-v1`
before starting SwiftUI. The adapter forwards the original JSON argument to
the previous notifier unchanged, without a shell, then sends only bounded
thread/turn IDs and a timestamp through `DistributedNotificationCenter`.
The receiver is scoped by a random per-installation token; the IPC message is
only a hint, never proof that a response completed.

Explicit opt-in reads the raw user configuration layer through `config/read`
and writes only `notify` through `config/value/write`, using its version as a
concurrency guard. The encoded adapter contains the previous command. A stored
fingerprint allows disabling to restore that command, or remove an originally
absent key, only while the wrapper is still owned by this feature. Active
profiles, overriding notification configuration, invalid wrappers and failed
writes leave an actionable setting error. Startup does not rewrite configuration.
Codex keeps `notify` in loaded session state, so existing chats may require a
Codex restart after first setup. Source verification used installed CLI
0.159.0-alpha.12.1 and its matching public source commit
`180d8caaac22c656bfc6329f2f573ee1430cbe20`.

The existing App Server makes bounded, event-triggered `thread/read` requests
without turns and `thread/turns/list` requests with `itemsView: notLoaded`.
Only an exact turn with status `completed`, no error, a recent `completedAt`,
and a top-level `user` thread is accepted. Missing freshness or scope metadata
fails closed. The optional chat name falls back to `Codex`; message contents
are neither requested for verification nor retained. Local user-thread turns
are supported, including background continuations in the same thread; dedicated
automation, child and remote/cloud threads are outside this boundary.

A separate App Server can temporarily normalize an unfinished persisted turn to
`interrupted` without `completedAt`. That error-free, undated shape receives the
existing bounded retries; an actual dated interruption remains rejected.

`AppState` owns bounded deduplication, verification retries, eight seconds of
automatic dismissal time and the shared menu preference. Interaction with the
card pauses the remaining time; leaving resumes it. New completions update the
current count without resetting the remaining time. An ID-scoped close action
uses the existing invalidation path, so stale callbacks cannot dismiss a newer
notice. Generation guards invalidate work on hide, pet interaction, sleep,
reconnect, disable and termination. No missed event queue or periodic history
polling is added. Transport failures leave quota and history unchanged.

`AppDelegate` synchronously observes process-local `NSMenu` begin/end tracking
notifications to suppress notices during actual native menu interaction. A set
of menu identities keeps suppression active through nested and duplicate events.
The observers and set are cleared at termination. SwiftUI menu content appearance
does not own this state: its view can appear while the native menu is closed.

`PetPanelController` reuses the existing tooltip placement helper for a static,
nonactivating child panel. The card accepts pointer input for its native close
button; the body has no action and cannot click an obscured application. This
avoids an asynchronous global-monitor race when changing whole-window mouse
transparency above a small close target. The pet's own input policy is separate.
The hosting view is retained during content updates to preserve hover and focus.
Hovering the pet, dragging it and opening menus still take precedence.
`CompletionNoticeView` shares existing Smooth/Pixel styling, keeps a readable
size independent of the pet, exposes the close button separately to accessibility,
and provides one accessibility announcement per presentation. Pointer and
keyboard/accessibility interaction pause the timer without automatic activation
or focus transfer. Headless logic/IPC checks and an offscreen view preview are
available via `script/check_completion_notices.sh`; live Desktop delivery,
native menu tracking, first-click behavior, focus and spoken VoiceOver require
separate GUI verification.

## Application updates

The approved update boundary is independent of Codex quota:
`native / Pixel menu -> AppState command availability -> Sparkle adapter -> GitHub`.
One `SPUStandardUpdaterController` owns native update UI, download, verification,
installation and relaunch. Sparkle 2.9.6 is pinned; the application does not
implement its own archive extractor or installer. Manual-only policy and strict
feed/archive signing are bundle configuration. The public key is supplied at
build time; a missing or malformed key fails closed before checking.

`AppDelegate` coordinates update termination with accepted history writes.
`AppState` serializes load, record and clear operations, stops new intake during
preparation, and waits for the accepted queue and final persistence. A deadline
can cancel the termination attempt without canceling a disk write or allowing a
late completion to approve termination. Failure resumes the owned App Server
through the existing gap/baseline logic. Normal Quit must use the same gate
because Sparkle may have a user-authorized installation waiting for exit.

A one-use, build-matched handoff retains the current manual visibility and pet
frame only across an update. `PetPanelController` applies frame restoration
through its existing screen selection/clamping policy, including an initially
hidden pet. Persistent preferences and history remain outside the app bundle.

Ad-hoc packaging retains Hardened Runtime and applies the approved Library
Validation exception to the host app. Sparkle's Ed25519 trust is independent of
Apple signing; it does not provide notarization or bypass Gatekeeper. Signing
and feed tooling are part of the source change; production key provisioning and
publication remain separate from implementation.

## Existing quota and presentation flow

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
The optional persisted `showsOnlyWhenCodexIsActive` preference adds foreground
application eligibility to this same visibility decision. It matches
`com.openai.codex` for the whole host application, independently of quota and
the manual visibility flag. The native menu-bar and Pixel context-menu toggles
update the same preference and immediately reevaluate visibility; wake also
reevaluates it. Transient
activation of the pet itself retains the last external foreground/fullscreen
context instead of treating its own menus as a different eligible application.
Foreground suppression reuses `hide()` to clear transient presentation, and
restoration requires fresh hover before showing the tooltip or refreshing on
hover. Quota collection continues through the existing AppState lifecycle.
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
`QuotaHistoryClassifier` classifies accepted quota-window transitions for local
history. A classified reset remains a history boundary. Quota-consumption
reaction scheduling and APNG decoding were removed in 0.10.2. `PetVisualState`
continues to select the normal quota shape and rotation phase; click/hover and
object-absorption presentation remain independent of quota consumption.
`PetPanelController` also owns a separate transient key-capable `NSPanel` for
the custom pixel context menu. Local pointer monitoring distinguishes secondary
clicks from absorption and dragging, while a short-lived global monitor closes
the menu after clicks in other applications. SwiftUI reads live settings from
`AppState`; menu actions call the same state methods as the menu bar and do not
refresh quota. Hit testing, screen-quadrant placement, and the reversible
spaghettification state are pure helpers covered by tests.
Both menus group settings as Appearance, Object Mix, Behavior, followed by
Hide/Show Pet, Check for Updates and Quit. The right-click menu has six normal
root actions. Its update action routes through the same AppDelegate callback
and AppState availability as the native menu. Appearance and Behavior flatten
their settings into one submenu level; Object Mix retains its existing matrix
in the Pixel menu and native pickers in the menu bar. Group expansion and
keyboard selection are view-local and do not create new persisted preferences.
Both Appearance groups expose the existing forecast opt-in, conditional provider
link and local-history command/status. The Pixel history action reaches the same
AppDelegate confirmation as the native menu; provider navigation and confirmation
run after context-menu dismissal. Conditional provider actions and busy response
notice settings are omitted from keyboard traversal using their current AppState
values. The short root is anchored independently
of the submenu height inside the shared panel reserve; the controller keeps its
existing screen-quadrant placement and dismissal responsibilities.

`AppState` owns the independent persisted position-lock and pointer-click-through
preferences. `PetPanelController` applies their single effective `NSPanel`
policy, keeps the menu-bar toggle as the recovery path, and uses named native
frame restoration only for locked placement; display changes reuse the existing
positive-intersection screen selection and visible-frame clamping. Routine
ordering of an existing panel is frame-neutral. A per-quota cached alpha union
of the six idle sprites, mapped through the renderer's aspect-fit and maximum
pulse together with the stable absorption core, is the shared hover, context,
drag, and dynamic transparent-padding pass-through region. Local and global
mouse-move monitors update the one panel's native `ignoresMouseEvents` policy;
active pointer sequences hold capture until release without adding permissions.

## Companion catalogue selection control

`AppState` owns the optional catalogue-validated `selectedCompanionID` in local
preferences, independently of manual absorption weights. `CompanionPickerView`
keeps category, magnifier zoom and preview/focus local; only selection commits
the ID. `CompanionPreviews` contains the six unchanged approved detailed source
sheets plus the restored tenth character's source sheet (Паша), with per-ID
fractional crop metadata. Grid/menu images reuse the existing
80×80 PNGs. No production sprite or black-hole rendering changes are involved.

Native and Pixel menus share an AppDelegate action into the existing
`PetPanelController`. It owns one transient nonactivating catalogue panel,
clamps it to the visible display, suppresses conflicting pet UI and removes its
outside-click monitors on dismissal. The SwiftUI catalogue can scroll vertically
on a small display. The real work-start/pause transport and orbital rendering are
not part of this implemented control slice; the existing completion hint cannot
be treated as a signal that work started.

## Companion orbit renderer

The subsequent approved motion slice adds `CompanionOrbitVisualState` and a
small view-local `CompanionOrbitPresentation`. The pure geometry uses the
approved 5-second period and 80 pt sprite canvas at L. `PetSpriteScene` shares
the existing quota-frame and object-image caches and composes the far companion,
quota image and near companion in that order; manual absorption and reaction
layers stay above it. The existing `BlackHoleView` timeline advances both the
orbit and its finite appearance/removal state. No extra timer, task queue,
transport, image assets or dependencies are introduced. Companion images are
excluded from pointer hit testing and accessibility focus.

Ordinary launches keep `AppState.companionActivity` at `.unavailable`. The renderer
and transition checks use isolated synthetic inputs. The installed
Codex's independent App Server and external hooks do not provide a complete
Desktop lifecycle; details and exact source evidence are recorded in
`docs/feature-workstreams/companion-picker.md`.

Future activity integration must own concurrent turns in AppState and obtain
fresh verified state after reconnect, hide/show, sleep and resize. In particular,
the current shared `absorptionResetID` clears presentation on resize and hide;
the future source/presentation connection must explicitly reconcile after these
resets. The inactive-source implementation and pure tests do not prove these
live lifecycle transitions, GUI delivery or spoken VoiceOver behavior.

The approved hooks experiment supplies an explicitly approximate exception.
`BLACK_HOLE_COMPANION_HOOK_TOKEN` must contain a UUID at launch. Without it there
is no activity listener. `CompanionActivityHook` handles a bounded stdin JSON
payload before the application's SwiftUI entry point, emits a metadata-only
local notification on a separate channel, and returns neutral JSON without
controlling Codex. The token scopes the experiment; it is not authentication.

`AppState` owns `CompanionHookTracker`, the listener and one expiry task. Positive
prompt/tool hints create or refresh ephemeral turns; permission hints only pause
an observed turn. Stop, SubagentStop and Interrupt remove matching turns with
temporary tombstones; SessionEnd clears its session up to a timestamp cutoff.
The aggregate remains working if any tracked turn works. After ten minutes
without a positive hint, an expired turn is removed and an empty aggregate is
unavailable. Generation/epoch resets clear state on connection changes, sleep,
actual panel visibility changes and scene resets. Fresh hints are required to
restart; there is no snapshot or inferred recovery. Hook timestamps represent
helper start, not guaranteed runtime ordering. Same-turn Stop continuations,
missing terminal events and long silent work remain known approximation limits.

The experiment does not install/trust hooks, persist activity, change existing
completion-notify configuration, add UI or alter release metadata. The prepared
hook definition lives under build artifacts until reviewed separately. Actual
Codex-dispatched delivery and live GUI behavior must be distinguished from
headless synthetic-input/IPC checks.
