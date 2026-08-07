# Product specification

## Product goal

Show the remaining Codex quota as a persistent macOS black-hole pet without
requiring the user to keep the Codex window open.

## Confirmed behavior

- The accretion disk grows as quota is consumed.
- The black core and its photon ring remain the same size at every quota value.
- From 100% through 60%, the disk is gold.
- From 50% through 30%, an orange layer appears and reaches full strength.
- From 20% through 0%, a purple layer appears and reaches full strength.
- Each 10% quota state uses a six-frame transparent pixel-art loop. Gold,
  orange, and purple accumulate while their highlights animate at distinct
  phases inside that loop. The exported canvas excludes master-sheet bleed and
  contains no unrelated opaque markers outside the intended artwork.
- The renderer uses a limited pixel-art palette with stepped edges and glow.
- Hover shows a compact localized card with the exact remaining quota, a
  mode-specific progress bar, dynamic day segments, and reset time. Standard
  uses a smooth bar; Turbo adds a bolt, chevrons, and edge glow. English and
  Russian follow the macOS app language. The menu bar uses the same localized
  quota, mode, status, and action labels. The card has no actions.
- Standard mode rotates continuously.
- Fast mode rotates 1.5 times faster and pulses without changing quota geometry.
- At zero quota, the disk reaches its largest purple state, rotation nearly
  stops, and Fast-mode pulsing is disabled.
- The pet is a draggable, transparent, always-on-top macOS surface with a menu
  bar control and no Dock icon. The menu can hide and restore the pet without
  quitting the application.
- The menu bar control uses the approved monochrome 20 × 20 native macOS
  template: two asymmetric caustic arcs orbit an open negative-space event
  horizon. The heavier upper arc and more compact lower arc keep their tapered
  opposing tips; there is no enclosing ring, central dot, or pixelation. The
  1× and Retina 2× assets use antialiased transparent edges and follow the
  system menu-bar foreground color in light and dark appearances.
- The app respects Reduce Motion. A persisted menu setting can hide the pet
  automatically while another application is fullscreen.
- VoiceOver announces the exact remaining quota, Standard or Turbo mode, and
  connection state from both the pet and menu bar status item.
- If Codex App Server disconnects, the pet keeps the last known quota visible
  in a dimmed state and retries after 1, 2, 5, 10, then at most 30 seconds. The
  menu shows the reconnecting state and provides `Retry Now`.
- The quota refreshes at startup, after App Server quota notifications, every
  60 seconds as a passive fallback, on hover when the snapshot is at least 30
  seconds old, and after macOS wakes from sleep.
- All processing is local. There is no backend, analytics, or cloud sync.

## Approved pet size selection

The size-selection design update was approved for implementation on
3 August 2026.

- The current 400 × 220 pt pet is `L`. The additional sizes are `M` at
  320 × 176 pt and `S` at 240 × 132 pt.
- A localized `Size` / `Размер` picker in the menu bar exposes `S`, `M`, and
  `L`, marks the current selection, and persists it between launches. Existing
  installs and invalid stored values fall back to `L`.
- All quota states continue to use the existing sprite assets, uniformly scaled
  into the selected scene. Core, photon-ring, disk, reaction, Standard/Turbo,
  zero-quota, and Reduce Motion relationships do not otherwise change.
- Absorbable models keep their existing 48 × 48 pt rendered size and use the
  same assets and animation timing. Spawn points and trajectories adapt to the
  selected scene, and the complete transformed object remains inside the pet
  panel throughout the approach instead of being clipped at its edges.
- Changing size immediately hides the tooltip, clears active absorption
  objects, resizes around the pet's current center, and clamps the resulting
  panel to the current screen's visible frame. Dragging and fullscreen hiding
  continue to use the same behavior at every size.
- The tooltip keeps its existing contents. `L` uses the existing layout at 100%,
  `M` scales it uniformly to 80%, and `S` uses the separately approved compact
  circular layout below; stale-on-hover quota refresh behavior is unchanged.
- VoiceOver quota and absorption actions, connection/retry behavior, data
  freshness, local-only processing, permissions, signing, packaging, and
  distribution scope are unchanged.

Acceptance criteria for this update:

- a fresh or migrated install uses `L`, and selecting each menu item produces
  the exact approved panel size and survives relaunch;
- the black-hole scene scales uniformly for every quota state while absorbable
  objects remain 48 × 48 pt;
- resizing preserves the panel center when space permits, remains on-screen,
  clears active absorption, and gives each size its approved tooltip that
  remains on-screen without regressing hover, click, drag, Standard/Turbo,
  Reduce Motion, reconnecting, or accessibility behavior;
- localized English and Russian menu labels are bundled, automated tests pass,
  and `./script/build_and_run.sh --verify` builds and launches the app.

## Approved compact S tooltip

The compact `S` tooltip design update was approved for implementation on
3 August 2026 and supersedes only the earlier requirement that the `S` tooltip
uniformly scale to 60%.

- `L` and `M` keep their current tooltip layouts and 100% / 80% scales.
- `S` uses a dedicated readable 248 × 112 pt card inside a 272 × 132 pt tooltip
  panel instead of shrinking the existing card, text, and progress bar to 60%.
- The compact card keeps the localized Available label, exact remaining
  percentage, localized days until reset, and localized exact reset date and
  time. Its circular quota indicator replaces the horizontal progress bar and
  the redundant day-segment strip.
- Standard shows a plain circular quota arc. Turbo adds static directional
  chevrons on the filled arc and a filled bolt marker at the beginning of the
  arc. The decorations do not animate and are hidden from accessibility.
- The arc keeps the existing gold, orange, and purple quota thresholds. Missing
  quota renders an em dash and an empty track; missing reset data keeps the
  existing localized unavailable state.
- Reduce Motion, hover refresh, drag behavior, four-side tooltip placement,
  screen clamping, reconnecting and stale-data behavior, menu content,
  VoiceOver summaries, localization, permissions, signing, packaging, and
  distribution scope are unchanged.

Acceptance criteria for this update:

- selecting `S` produces the dedicated compact panel while `M` and `L` retain
  their existing layouts and scales; the `S` panel is smaller than `M` in both
  dimensions;
- the `S` card remains readable and on-screen in Standard and Turbo, for every
  quota color state, in English and Russian, and at each tooltip placement;
- Turbo places a filled bolt at the start of the circular arc and shows static
  chevrons only on the filled portion; Standard shows neither decoration;
- the compact progress and reset information retain their existing accessible
  labels, automated tests pass, and `./script/build_and_run.sh --verify` builds
  and launches the app.

## Approved Smooth and Pixel tooltip styles

The selectable tooltip-style design freeze was approved for implementation on
6 August 2026. The representative system prototype, including the system
monospaced typography, style-dependent L/M/S geometry, Standard/Turbo states,
English/Russian copy, quota colors, stale and missing-data states, and comparison
with the unchanged Smooth presentation, was approved the same day.

- The app exposes exactly two tooltip styles. `Smooth` is the current tooltip;
  its normal-text-size typography, colors, layout, dimensions, pointer, progress
  semantics, S composition, shadows, and absence of continuous animation remain
  visually unchanged. `Pixel` is a code-native SwiftUI presentation aligned
  with the approved black-hole sprites and pixel context menu. The concept PNGs
  remain visual references and are not shipped as flattened tooltip assets.
- `AppState` owns one persisted raw-value preference, `smooth` or `pixel`.
  Fresh installs, migrated installs with no stored value, and invalid values use
  `smooth`. Changing style never refreshes quota or starts another App Server
  process.
- The menu bar exposes `Tooltip Style -> Smooth / Pixel` in English and
  `Стиль подсказки -> Обычный / Стилизованный` in Russian. The custom pixel
  context menu exposes the same choice in a side submenu, grows only its fixed
  panel height from 318 to 350 pt, and keeps its 386 pt width and existing row
  geometry. Choosing a style closes the context menu. The main style icon uses
  overlapping normal and stepped cards; submenu icons distinguish normal and
  stepped cards, while the current selection uses the existing trailing
  checkmark. Icons are static and decorative for accessibility.
- Context-menu keyboard behavior matches the size submenu: Right Arrow enters,
  Up and Down Arrow move selection, Left Arrow returns, Return or Space selects,
  and Escape dismisses. VoiceOver reads the localized label and selected state.
- Both presentations consume one shared semantic tooltip-content value covering
  exact primary remaining percentage and quota level, Standard/Turbo, reset
  countdown and absolute date, reset-duration availability, missing and stale
  state, and the accessibility summary. Smooth and Pixel remain two focused
  presentations; there is no theme engine, renderer protocol, factory, arbitrary
  skin system, or speculative secondary/history content.
- Pixel uses the system monospaced font at medium/semibold weights. No font is
  bundled and no font dependency is added. The selected system face has complete
  glyph coverage for the bundled English and Russian tooltip and picker copy.
  Short structural labels and mode names use uppercase; dynamic phrases and
  dates use normal localized casing.
- Pixel reuses the approved pixel-context-menu background, inner-border, purple
  hard-shadow, orange-accent, and bright-gold chrome palette. Its frame never
  changes with quota. Quota content uses the existing Smooth colors: gold
  `#FFC24F`, orange `#FF5729`, and purple `#AD45F0`.
- At normal system text size, Pixel L uses a 420 x 210 pt panel with a
  390 x 180 pt card. M uses the same composition at 80%, producing a
  336 x 168 pt panel with a 312 x 144 pt card. S uses a dedicated
  304 x 148 pt panel with a 280 x 128 pt card and circular quota indicator.
  L/M show the title, mode badge, large percentage, linear progress, reset
  window, countdown, and exact date. S shows the percentage in a circular
  indicator with mode, countdown, and exact date beside it and omits reset
  segments.
- Standard uses a plain fill or arc and a mode badge without a bolt. Turbo adds
  a static bolt, static chevrons only on the filled portion, and a static end
  marker kept inside progress bounds. S places the bolt at the beginning of the
  filled arc. No tooltip decoration loops or animates.
- Tooltip quota colors use the current thresholds: 30-100% gold, 10-29% orange,
  and 0-9% purple. At 0%, the track or ring is empty, chevrons and the end marker
  are absent, and a known Turbo badge and bolt remain. At 100%, fill stops at the
  inner bound. Missing quota uses an em dash and an empty neutral indicator while
  retaining a known Standard/Turbo mode.
- If `resetsAt` is unavailable, Pixel shows the localized unavailable message
  without segments or a calendar row. If `resetsAt` exists but window duration
  is unavailable or invalid, both presentations show countdown and exact date
  without inventing reset-window segments. When both are valid, the full reset
  presentation is shown.
- During reconnecting with a last accepted snapshot, both styles retain the
  values and accessibility summary. Pixel dims only its informational content
  to 62% opacity while keeping its frame and pointer fully visible; it does not
  add a stale badge. Smooth remains visually unchanged. VoiceOver identifies the
  value as last known and announces the connection state.
- The Pixel pointer is one code-native stepped shape rendered above, below, left,
  or right. L-to-M scales it to 80%; S uses a compact form of the same geometry.
  Borders, shadow, pointer, icons, bolt, chevrons, segments, and progress end
  markers are hidden from accessibility.
- Changing style while the tooltip is open updates it immediately without a
  fade or morph, preserves the current side and pointer attachment when it fits,
  resizes the native panel, and clamps it inside the current screen's visible
  frame. If that side no longer fits, the controller chooses the next fitting
  side before clamping. A hidden tooltip uses the selected style on its next
  hover.
- The tooltip belongs to the display containing the largest part of the pet,
  stays inside that display's visible frame, and never moves the pet during a
  style change. Dock and menu-bar insets continue to be respected.
- The approved dimensions are bases for normal text size. At accessibility text
  sizes, both presentations may expand and reflow inside the current visible
  frame: percentage, mode, and the em dash are never truncated; reset text may
  wrap to two lines; S keeps its circular composition but may grow vertically;
  and compact system date formatting is preferred before reducing legibility.
  There is no internal scrolling.
- Pet and menu-bar VoiceOver summaries use the same semantic formatter and
  include the exact percentage or localized unavailable state, Standard/Turbo,
  connection state, last-known wording when stale, and reset date when known.
  The visual style name is not included. The tooltip remains noninteractive and
  does not add a keyboard stop.
- Existing hover refresh, drag restoration, absorption and context-menu
  suppression, size-change hiding, fullscreen suppression, pet hit testing,
  hide/show behavior, and reconnect logic are unchanged for both styles. Opening
  or switching a tooltip cannot add network traffic.
- Pixel has no `TimelineView`, timer, continuous Canvas refresh, or rendering
  task. It redraws only when observed data, mode, style, placement, or
  accessibility environment changes. Reduce Motion therefore preserves the same
  fully static content and presentation.
- Secondary quota and local history do not add placeholders in this slice. A
  future approved feature extends the shared semantic content and explicitly
  defines Smooth, Pixel, and S compositions in the same change. Style persistence
  stays independent from quota schema and local-history storage.

Acceptance criteria for this update:

- fresh, migrated, persisted, and invalid style values follow the approved
  Smooth default and survive relaunch after selection;
- localized menu-bar and pixel-context-menu pickers expose both styles with the
  approved icons, checkmarks, dismissal, keyboard, and VoiceOver behavior;
- switching an open tooltip is immediate, keeps it visible, preserves its side
  when possible, stays on the owning display, and adds no quota refresh;
- Smooth Standard/Turbo and S/M/L retain their approved normal-size visuals,
  layout, content, pointer placement, hover/drag suppression, and accessibility;
- Pixel Standard/Turbo and S/M/L render correctly in English and Russian at
  0%, critical, warning, normal, 100%, missing quota, missing reset, missing
  duration, connected, and stale/reconnecting states;
- all four pointer placements, screen edges, multiple displays, long localized
  values, and accessibility text sizes remain readable and inside the visible
  frame;
- formatting, preference, panel-size, placement, view-state, localization,
  keyboard, and accessibility tests pass; the focused macOS test suite passes;
  `./script/build_and_run.sh --verify` builds and launches the app; and
  screenshot QA confirms the Smooth regression contract and approved Pixel
  system without continuous idle rendering.

## Approved adaptive reset countdown

The reset-countdown refinement was approved for implementation on
8 August 2026. It changes only the localized relative countdown already shown
inside both approved tooltip styles.

- At 24 hours or more, the tooltip keeps the existing whole-day countdown.
  From one hour up to but excluding 24 hours, it shows whole hours instead of
  `0 days`. Below one hour, it shows whole minutes and seconds. Exact boundaries
  belong to the larger unit: 24:00 is one day and 1:00 is one hour.
- The countdown truncates to completed whole units, never rounds upward, and
  never becomes negative. At or after the last known reset timestamp it shows
  zero minutes and zero seconds until App Server supplies a new window.
- English and Russian use the system-localized abbreviated hour, minute, and
  second units so compact S geometry remains readable. Representative copy is
  `23h until reset` / `23 ч до сброса` and
  `42m 17s until reset` / `42 мин 17 с до сброса`. The separate absolute reset
  date and time remain unchanged.
- Smooth and Pixel, Standard and Turbo, and S/M/L consume the same shared
  semantic formatter. Tooltip panel and card dimensions, reset-window segments,
  quota/history content, colors, typography, pointer geometry, and stale/missing
  presentation otherwise remain unchanged.
- While the tooltip is visible, the countdown updates at the next displayed-unit
  boundary and once per second below one hour. Countdown work stops whenever the
  tooltip is hidden, including drag, context-menu, pet hiding, and fullscreen
  suppression. There is no background timer, extra App Server read, continuous
  Canvas rendering, or persistence change.
- Reduce Motion does not alter the value because the countdown is text rather
  than decorative motion. The reset row exposes the same current countdown and
  absolute timestamp through VoiceOver. Missing reset data retains the existing
  localized unavailable state; reconnecting/stale data counts down from the last
  accepted reset timestamp.
- Hover refresh, click, drag restoration, resize, style switching, pointer
  placement, screen clamping, hide/fullscreen behavior, wake handling, menu-bar
  content, quota-history collection, privacy, signing, packaging, and
  distribution scope are unchanged.

Acceptance criteria for this update:

- deterministic formatter tests cover 24:00, 23:59, 1:00, 59:59, zero, expired,
  missing reset data, English, and Russian;
- Smooth and Pixel S/M/L show the same countdown semantics without truncating
  the representative English and Russian strings or changing approved geometry;
- visible-only update lifecycle tests prove that live countdown work starts on
  hover, stops on every tooltip dismissal path, and adds no quota refresh;
- focused and full macOS tests pass, `./script/build_and_run.sh --verify` builds
  and launches the app, and representative Smooth/Pixel screenshot QA confirms
  the sub-day and sub-hour states.

## Approved local quota history

The local quota-history design freeze was approved for implementation on
7 August 2026. It extends the approved Smooth/Pixel tooltip system without
claiming access to exact tokens or complete account activity.

- History contains only locally observed integer percentage snapshots and the
  minimum reset-window and limit identity metadata required to decide whether
  adjacent observations are comparable. It never stores tokens, cost, request
  details, prompts, tasks, models, credentials, or Codex private files.
- Primary and optional secondary windows are persisted independently. The first
  UI slice presents only primary history; secondary history has no placeholder
  until its own Smooth/Pixel/S composition is approved.
- Collection is local-on. A persisted `Show Quota Dynamics` /
  `Показывать динамику квоты` preference is enabled by default and controls
  presentation only. Turning it off removes history from the tooltip and its
  VoiceOver summary while collection, retention, and the clear-history path
  continue unchanged.
- A changed percentage, window availability, reset metadata, or identity is a
  meaningful snapshot. Identical accepted data records at most one hourly
  heartbeat. History never initiates another App Server read.
- Retention is a rolling 30 days with a hard cap of 2,000 snapshots. Expired
  points are pruned first, then the oldest overflow; the first remaining point
  becomes a baseline.
- A percentage drop is comparable only within one uninterrupted connection,
  with compatible limit identity, the same non-null reset timestamp, compatible
  duration metadata, no missing window, no clock reversal, and no gap longer
  than 90 minutes.
- A credible reset requires continuous identity and connection, the old reset
  time to pass between observations, a new future reset time, and compatible
  duration metadata. It is a reset boundary regardless of whether the integer
  percentage rises, stays equal, or falls.
- An increase without a credible reset is a correction boundary. Startup,
  reconnect, every macOS wake, identity change, window disappearance or
  reappearance, backward clock movement, and a gap over 90 minutes also begin a
  new baseline. Both boundary observations are retained, but no line or change
  is inferred across them.
- Changes in `limitId`, `planType`, or a non-empty `limitName` break identity.
  Missing identity fields alone do not claim an account change; incomplete
  identity continues only through an uninterrupted connection with matching
  window metadata. The protocol cannot identify an account switch when all
  visible identity fields remain the same.
- Observation time is the local `Date` at snapshot acceptance because App
  Server provides no observation timestamp. Append order is authoritative.
  Future-dated points after a backward clock adjustment remain subject to the
  hard cap and are not age-pruned until local time catches up.

Persistence and privacy:

- One versioned Foundation `Codable` JSON file lives in the app-specific
  Application Support directory, uses atomic replacement and current-user file
  permissions, and is excluded from backup. There is no database, third-party
  package, iCloud/ubiquity, network sync, backend, analytics, or custom crypto.
- Missing and empty stores start normally. Corrupt, partial, old unsupported,
  or unknown future versions are never salvaged or overwritten in place. The
  file is moved to a timestamped quarantine beside the active file and history
  restarts empty.
- If quarantine fails, the original file remains untouched and writes are
  disabled for that session. If a normal write fails, the last valid file is
  preserved, in-memory session history continues, and atomic persistence is
  retried only on the next meaningful snapshot or heartbeat.
- The regular menu shows a short localized nonmodal status when history was
  restarted or is not being saved. Quota display, reconnect, pet animation,
  consumption reactions, and reset events remain independent of persistence.
- `Clear Local History…` / `Очистить локальную историю…` appears only in the
  regular menu and uses a native confirmation with Cancel as the default. A
  successful clear removes active history and quarantines, leaves the current
  quota unchanged, and makes the next normally accepted snapshot a baseline.
  A failed clear never reports success.

Presentation:

- The default range is the latest 24 hours. X is time-proportional across that
  fixed range and Y is fixed at 0...100% so small movements are not exaggerated.
- L and M show a static chart plus the latest uninterrupted comparable segment.
  Smooth uses an antialiased line; Pixel uses a stepped line. Both use identical
  data semantics and the current quota color. A reset is a line break with an
  outlined diamond; other lost-continuity boundaries are breaks with a neutral
  dashed mark. Flat observations remain horizontal.
- User copy shows endpoints instead of percentage-point notation: for example,
  `85% → 77%` with `over 6 hours observed`, and in compact form
  `85% → 77% · 6 h`. Russian uses `за 6 часов наблюдений` and `6 ч`.
  No `p.p.` / `п.п.` abbreviation is shown. An unchanged segment says that the
  current percentage is unchanged; one comparable point says history is being
  collected; a missing current primary says the current value is unavailable.
- With dynamics visible, normal-size panel geometry is Smooth L 360 x 252 pt,
  Smooth M 288 x 201.6 pt, Smooth S 272 x 158 pt, Pixel L 420 x 290 pt,
  Pixel M 336 x 232 pt, and Pixel S 304 x 174 pt. L/M show the chart; S keeps
  its circular composition and adds one text-only endpoint/duration line.
- With dynamics hidden, each style and size returns exactly to its previously
  approved panel and card composition with no empty history space. Changing the
  preference while a tooltip is open updates and resizes immediately, preserves
  the current side when it fits, chooses the next fitting side otherwise, and
  clamps to the owning display without moving the pet.
- Standard and Turbo have the same history. Turbo does not add bolts, chevrons,
  pulses, or distinct meaning to the chart. The chart has no `TimelineView`,
  timer, continuous Canvas refresh, or reveal animation. Reduce Motion retains
  the same static information.
- Reconnecting/stale presentation retains the last history. Pixel applies its
  existing 62% informational-content dimming; Smooth remains visually
  unchanged. A missing current primary keeps past segments visible but labels
  the current value unavailable.
- Existing hover refresh, pet click and absorption, dragging, resize, style
  switching, context-menu suppression, hide/show, fullscreen suppression,
  click-through behavior, four-side placement, multiple-display ownership, and
  screen clamping remain unchanged. Collection continues while the pet is
  hidden or fullscreen-suppressed.
- The regular menu and Pixel context menu both expose the persisted dynamics
  toggle. The Pixel context menu keeps its existing keyboard and VoiceOver
  behavior and may grow only by the one fixed row required for this option.

Accessibility, localization, and performance:

- Chart geometry and decorations are accessibility-hidden after an equivalent
  localized text summary is supplied. With dynamics enabled, pet and menu-bar
  VoiceOver summaries add the start and end percentages, observed duration,
  and whether a reset or continuity break is present. The tooltip remains
  noninteractive and adds no keyboard stop.
- English and Russian use Foundation-localized dates and durations, natural
  casing, and complete phrases for collecting, unchanged, current unavailable,
  restarted, not saved, clear confirmation, and the visibility toggle.
- Views read an already-derived presentation and never read files. Persistence,
  decoding, pruning, and encoding do not run on the main actor. Rendering is
  capped at 240 derived points, retains endpoints and boundary meaning, and is
  recomputed only when history changes.
- A maximum-size fixture measures decode, prune, and presentation derivation;
  the development target is a median at or below 100 ms over ten runs and at or
  below 10 ms for subsequent presentation derivation. Actual measured results,
  not assumptions, are reported after implementation.

Acceptance criteria for this update:

- empty/fresh, relaunch, deduplication, heartbeat, 30-day pruning, hard cap,
  and primary/secondary absence are covered by focused tests;
- same-window drop, reset rollover, correction, account/plan change, startup,
  reconnect, wake, long gap, duplicate, missing metadata, and clock changes
  produce the frozen boundaries without inventing usage;
- atomic failure, corrupt JSON, unsupported version, quarantine failure,
  unwritable storage, in-memory continuation, retry, and confirmed clear are
  safe and do not affect live quota behavior;
- Smooth and Pixel L/M/S render the approved endpoint copy, graph/compact
  composition, Standard/Turbo, Reduce Motion, stale, missing, English, Russian,
  accessibility, and visible/hidden geometry states;
- all tooltip placements, display edges, accessibility text sizes, hover,
  click, drag, resize, style changes, hide/fullscreen, reconnect, and context
  menu behavior remain correct with no extra App Server traffic;
- fixture-driven classifier, store, presentation, preference, geometry, and
  localization tests pass, followed by focused macOS tests,
  `./script/build_and_run.sh --verify`, and visual QA of changed states.

Explicit non-goals are exact tokens, complete account activity, prediction,
export, cloud sync, analytics, a backend, notifications, a dashboard/settings
window, a database, third-party charts/storage, new sprites, signing changes,
or distribution changes.

## Approved absorption interaction

The approved design freeze is recorded in
[`ABSORPTION_DESIGN_FREEZE.md`](ABSORPTION_DESIGN_FREEZE.md). Its confirmed
behavior is:

The interaction is implemented in the production application from the approved
V3 design and uses the bundled manifest-driven asset set.

- A short click on the black core absorbs one decorative pixel-art object. A
  pointer movement beyond 6 pt remains a panel drag and creates nothing.
- Objects spawn inside an edge of the selected 400 × 220, 320 × 176, or
  240 × 132 pt pet window. The feature does not create a desktop-wide overlay
  or inspect applications, files, or other windows.
- The bundled set contains 31 approved models: twelve space objects, twelve
  cute animals, and seven characters. Category selection uses `2 : 2 : 1`
  weights, producing 40% space objects, 40% animals, and 20% characters, with
  no immediate model repeat.
- At most three objects can be active. Their starting sides differ when
  possible, and their paths may cross only near the core.
- A normal absorption lasts approximately 0.9–1.05 seconds. The object follows
  a curved partial orbit, accelerates near the core, and undergoes discrete
  pixel spaghettification up to about 2.5× length and 0.5× width.
- Objects start moving immediately without an introductory wobble. Rotation
  follows the continuous path tangent before position pixel-snapping to avoid
  visible jitter on curved approaches.
- During the final approach, the visible silhouette progressively loses 8–14
  colored pixel blocks. Those detached fragments continue independently toward
  the core instead of acting as an unrelated overlay trail.
- Objects render in front of the accretion disk during approach. At the center,
  the object itself disappears through stepped pixel breakup, shrink, and fade;
  no additional black overlay is drawn over the existing core artwork.
- The photon ring uses a restrained 100–150 ms flash with a softer outer contour
  and horizontal line. The disk reacts with a pulse capped at 2.2%. The fixed
  core size and quota-state geometry never change.
- Absorption is silent, manually triggered, session-only, and has no counters,
  achievements, progression, automatic events, settings, or persistence.
- The interaction is cosmetic and works at every quota value, including zero,
  with the same object duration in Standard and Turbo. It does not affect quota
  data, refresh behavior, service tier, or reset time.
- Reduce Motion replaces the orbit, rotation, spaghettification, particles, and
  disk pulse with a 200–250 ms stepped pixel fade next to the core.
- A successful click suppresses the quota tooltip until the pointer exits and
  hovers again. Existing stale-on-hover refresh and drag behavior remain.
- Active objects move with the panel during a drag and are discarded if the pet
  is hidden or suppressed by another fullscreen application.
- The interaction remains available while reconnecting and is dimmed with the
  rest of the disconnected pet.
- VoiceOver exposes one localized `Absorb Object` / `Втянуть объект` action but
  does not announce the selected model or completion.
- The renderer may use 30 fps only while objects are active and must return to
  the existing idle schedule after the final absorption. No new renderer,
  dependency, network service, permission, signing change, or distribution
  change is approved.
- A bundled manifest declares category selection weights and each model's stable
  ID, category, and PNG asset. Sprites load lazily through the existing cache
  approach. Adding a normal model or category requires assets and manifest data,
  not a new Swift animation branch.

Three additional user-approved characters were added on 5 August 2026 from the
approved cream-sweater, cargo-skirt, and botanical-shirt concepts. They use the
existing character category weight and do not change interaction behavior.

The V2 astronaut animation is the approved representative visual prototype.
The slower V3 timing is approved through the three-object launch with varied
trajectories. The user explicitly authorized implementation after the design
and visual gates were complete.

## Approved black-hole context menu

The black-hole context-menu design update was approved for development on
3 August 2026. The representative `L` visual prototype was approved the same
day, including its pixel icons, palette, layout, and reversible animation.

- A secondary click anywhere on the visible black hole or accretion disk opens
  the menu. Transparent panel edges are not interactive. A right mouse click,
  the configured secondary trackpad click, and Control-click are equivalent.
- The menu opens after button release when pointer travel is at most 6 pt. A
  secondary click never starts absorption or panel dragging.
- The context menu deliberately does not duplicate quota, reset, speed-mode,
  connection-status, or connection-error text from the tooltip and menu bar.
  Its ordered contents are: conditional `Retry Now`; a `Size` submenu with
  `S`, `M`, and `L`; `Hide in Full Screen`; `Launch at Login`; conditional
  launch-at-login approval, settings, and error items; a divider; `Hide Pet`;
  and the compact localized label `Quit` / `Выход`.
- `Retry Now` appears only when the connection is not connected. Launch-at-login
  approval, settings, and error items appear only when relevant. Current size,
  toggle state, enabled state, and conditional items update live from
  `AppState` while the menu is open.
- Every item has a minimal static 12 × 12 pixel icon in a fixed leading column.
  The approved mapping is: circular arrow for retry, scale frame for size,
  three progressively sized rectangles for `S`/`M`/`L`, screened shadow for
  fullscreen hiding, door and entering arrow for launch at login, lock for
  approval, system sliders for Login Items settings, warning diamond for a
  launch-at-login error, crossed eye for hiding the pet, and power symbol for
  quitting. Icons are decorative for accessibility.
- The current size and enabled toggles use a separate trailing pixel checkmark.
  Icons use muted gold normally, bright gold on hover, and muted gray-purple
  when disabled. They do not animate independently from the menu.
- The menu is a custom opaque dark pixel-art panel with a gold stepped border,
  restrained orange and purple accents, and a fixed gold hover treatment that
  does not depend on quota. It keeps the same readable size for `S`, `M`, and
  `L`; it does not scale with the pet.
- The menu originates near the pointer. It chooses a free quadrant and is
  clamped fully inside the current screen's visible frame. Pet dragging is
  disabled while the menu is open.
- Normal-motion appearance starts as an elongated pixel strand at the click
  point with a few detached pixels, visually related to absorbed-object
  spaghettification. It straightens along its main axis, then restores height
  in discrete steps over 280 ms. Items become interactive only after that
  transition completes.
- Normal-motion dismissal reverses the same deformation over 220 ms. `Hide Pet`
  and `Quit` execute after dismissal completes. Size, retry, and navigation
  actions update or execute immediately while dismissal runs. The `Hide in Full
  Screen` and `Launch at Login` toggles update in place and keep the menu open;
  automatic fullscreen suppression can still hide the pet and menu immediately.
  Quota state and Standard or Turbo mode do not alter these timings or geometry.
- Reduce Motion replaces stretch, deformation, and detached pixels with a short
  stepped pixel fade. It preserves the same content, placement, and action
  timing semantics.
- The menu dismisses after a non-toggle action, an outside click, Escape, a
  repeated secondary click, a size change, or pet hiding. The two setting
  toggles keep it open. Automatic fullscreen suppression dismisses it
  immediately without requiring an exit animation.
- Opening the menu hides the tooltip. The tooltip can return only after the menu
  closes and the pointer exits and hovers again. Existing absorptions continue
  behind the menu, but new absorptions cannot start while it is open.
- Opening the context menu does not refresh quota or add network traffic. The
  existing connection, retry, persistence, and launch-at-login behavior remain
  the source of truth.
- English and Russian follow the current app language. Arrow keys move menu
  selection; Return or Space activates it; Escape dismisses it. The custom menu
  may temporarily take keyboard focus without adding a Dock icon or changing
  the app's accessory activation model. Keyboard focus does not draw a native
  blue focus ring around the custom pixel surface; selection remains visible
  through the menu's own gold pixel highlight.
- VoiceOver exposes a localized `Open Context Menu` action on the pet and reads
  item labels, current size, toggle state, enabled state, and retry availability.
  It does not announce decorative icons or duplicate quota inside the menu.
- The feature does not change pet geometry, sprite animation, Standard/Turbo,
  absorption behavior, the Codex App Server protocol, permissions,
  dependencies, signing, packaging, or distribution.

The representative visual prototype must show the `L` pet in Russian with the
normal open menu plus its initial spaghettified and final expanded forms. It
must demonstrate icon alignment, normal/hover/disabled states, trailing state
checks, and the approved dark, gold, orange, and purple palette before
production implementation begins.

Acceptance criteria for this update:

- right mouse, secondary trackpad, and Control-click open the menu only from the
  visible pet; pointer travel beyond 6 pt does not open it, absorb an object, or
  create an unintended drag;
- content, ordering, conditional items, actions, icons, checkmarks, and live
  state match the approved design in English and Russian;
- the menu remains readable for `S`, `M`, and `L`, chooses an on-screen quadrant
  at every display edge, and behaves correctly with multiple displays;
- appearance and dismissal use the approved reversible spaghettification in
  normal motion and the approved stepped fade with Reduce Motion;
- tooltip suppression, drag blocking, ongoing and blocked absorption behavior,
  fullscreen suppression, reconnecting, and launch-at-login states do not
  regress;
- keyboard and VoiceOver can expose, traverse, activate, and dismiss the menu
  without changing the accessory activation model or drawing native focus
  chrome; the two setting toggles update their checkmarks without closing it;
- focused automated tests pass, and `./script/build_and_run.sh --verify` builds
  and launches the app for real-flow review.

## MVP boundary

The first release includes Codex App Server connectivity, quota and reset data,
Standard/Fast detection, the approved renderer states and animations, the
floating panel, hover details, menu bar settings, launch at login, and
accessibility behavior. Reconnection states are implemented.

Skins, controlling Fast mode, resetting quota, cross-device sync, and non-macOS
platforms are outside the MVP.

## Future interaction ideas

- Persist the number and kinds of objects absorbed by the black hole.
- Turn absorbed objects into a lightweight collection or achievement system.
- Add special visual reactions after click streaks or absorption milestones.

These ideas are intentionally outside the first absorption-interaction slice.
The initial version keeps every click self-contained and stores no interaction
progress.

## Current MVP status

- The functional pet, all eleven quota states, Turbo behavior, Reduce Motion,
  VoiceOver summaries, fullscreen preference, and reconnect flow are implemented.
- Launch at login is implemented with the native `SMAppService` main-app login
  item and verified through a logout/login cycle using an Apple Development
  signed build.
- Local Debug build, launch, and unit tests pass. The tests cover all
  66 bundled sprite frames, quota mapping, Turbo behavior, visibility,
  fullscreen policy, quota freshness, launch-at-login state handling, and
  automatic/manual reconnects.
- A local unsigned Release build passes. During an eight-second active-animation
  sample it held approximately 3.1–3.2% CPU and 21 MB of memory without growth.
- Runtime recovery was verified by terminating only the app's child Codex App
  Server process; the pet stayed alive and started a replacement automatically.
- Live macOS Accessibility-tree inspection verifies one labelled pet element
  with the current quota, speed mode, connection state, and reset time.
- The approved app icon and matching menu-bar icon are integrated through the
  native asset catalog.
- GitHub preview releases ship an Apple-silicon ZIP with a matching SHA-256
  checksum. Developer ID signing, notarization, and clean-Mac validation remain
  future work for a production distribution channel.
