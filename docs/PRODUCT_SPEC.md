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
  mode-neutral progress bar or arc, an explicit Standard/Turbo badge, dynamic
  day segments, and reset time. The progress geometry encodes quota only; mode
  never adds directional marks or endpoint markers to it. English and Russian
  follow the macOS app language. The menu bar uses the same localized quota,
  mode, status, and action labels. The card has no actions.
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

The proportional absorbable-object sizing revision was approved for
implementation on 9 August 2026 and supersedes only the earlier fixed 48 × 48
pt size across `S`, `M`, and `L`.

- The current 400 × 220 pt pet is `L`. The additional sizes are `M` at
  320 × 176 pt and `S` at 240 × 132 pt.
- A localized `Size` / `Размер` picker in the menu bar exposes `S`, `M`, and
  `L`, marks the current selection, and persists it between launches. Existing
  installs and invalid stored values fall back to `L`.
- All quota states continue to use the existing sprite assets, uniformly scaled
  into the selected scene. Core, photon-ring, disk, reaction, Standard/Turbo,
  zero-quota, and Reduce Motion relationships do not otherwise change.
- Absorbable models keep a nominal visible size proportional to the selected pet
  scene: `S` is 48 × 48 pt, `M` is 64 × 64 pt, and `L` is 80 × 80 pt. Their
  generated PNG canvas is 80 × 80 px and SwiftUI renders that transparent canvas
  in `60 × 60`, `80 × 80`, and `100 × 100` pt fields respectively, preserving
  the approved model scale while adding room around its silhouette. The same
  field applies to the model and detached fragments before deformation, shrink,
  and fade. The approved concept sources, nearest-neighbor rendering, animation
  timing, spawn logic, and trajectories are unchanged.
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
- the black-hole scene scales uniformly for every quota state, absorbable
  objects use the exact approved base sizes `S` 48 × 48 pt, `M` 64 × 64 pt,
  and `L` 80 × 80 pt inside transparent render fields of 60 × 60, 80 × 80, and
  100 × 100 pt, and the complete transformed object remains inside each selected
  scene in normal and Reduce Motion presentation;
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
- Standard and Turbo use the same plain circular quota arc. A separate localized
  mode badge identifies Standard or Turbo; no bolt, chevron, tick, glow, or
  other mode decoration is placed on the arc.
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
- Standard and Turbo have identical circular progress geometry, with no mode
  decoration on the arc, and keep a readable localized mode badge beside it;
- the compact progress and reset information retain their existing accessible
  labels, automated tests pass, and `./script/build_and_run.sh --verify` builds
  and launches the app.

## Approved Smooth and Pixel tooltip styles

The selectable tooltip-style design freeze was approved for implementation on
6 August 2026. The representative system prototype, including the system
monospaced typography, style-dependent L/M/S geometry, Standard/Turbo states,
English/Russian copy, quota colors, stale and missing-data states, and comparison
with the unchanged Smooth presentation, was approved the same day.

The mode/progress-semantics amendment was approved for implementation on
8 August 2026. It supersedes only the earlier Turbo chevron, progress-bolt,
endpoint-marker, edge-glow, and fully static mode-badge requirements in this
document.

- The app exposes exactly two tooltip styles. `Smooth` keeps its current
  normal-text-size typography, colors, dimensions, pointer, S composition, and
  shadows, while adopting the shared explicit mode badge and mode-neutral
  progress semantics below. `Pixel` is a code-native SwiftUI presentation aligned
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
- Within each style and size, Standard and Turbo use identical progress tracks,
  fills, arcs, quota colors, line caps, and endpoints. Progress contains no
  directional chevrons, start bolt, end tick, endpoint glow, or other mode cue.
  Pixel keeps its existing rectangular/stepped treatment and Smooth keeps its
  existing rounded treatment; the amendment does not make both styles visually
  identical to each other.
- Both styles show the localized mode in a dedicated badge outside the progress
  geometry. Standard uses a static badge without a bolt. Turbo uses the same
  badge footprint with one decorative bolt and a highlighted style-appropriate
  border or glow. Smooth uses natural localized casing with a neutral Standard
  treatment and fixed gold Turbo accent; Pixel keeps its existing uppercase,
  muted-gold Standard, and orange Turbo treatment. The badge reserves the larger
  of the localized Standard content and bolt-plus-Turbo content at the current
  text scale, then centers the actual content without an invisible Standard bolt
  or a clipping fixed width. L/M place it in the header; S places it in the text
  column beside the circular indicator, never over the arc. Normal-text-size card
  and panel dimensions remain unchanged.
- When a connected tooltip with known quota above 0% becomes visible in Turbo,
  only the badge highlight performs two slow glow pulses over 2.4 seconds and
  then remains static. Highlight intensity follows
  `0 -> 1 -> 0 -> 1 -> 0`, with four 0.6-second ease-in-out phases; the badge's
  resting text and surface never blink or disappear. The animation never changes
  scale, position, layout, text, progress fill, quota color, or percentage.
  Switching an already visible tooltip from Standard to Turbo triggers the same
  finite pulse once.
- Reduce Motion, 0%, missing quota, and stale/reconnecting states keep the Turbo
  badge highlighted but static. Hiding or suppressing the tooltip cancels any
  remaining badge animation. No badge animation runs in a hidden panel or uses a
  timer, `TimelineView`, continuous `Canvas`, or app/model persistence.
- Percentage, reset-countdown, style, size, placement, stale-to-fresh,
  missing-to-known, zero-to-positive, and Reduce-Motion-on-to-off updates never
  retrigger the pulse. Becoming ineligible during a pulse cancels it immediately;
  the next eligible hover starts a new cycle rather than resuming the old one.
- Tooltip quota colors use the current thresholds: 30-100% gold, 10-29% orange,
  and 0-9% purple. At 0%, the track or ring is empty and a known mode badge
  remains. At 100%, fill stops at the inner bound. Missing quota uses an em dash
  and an empty neutral indicator while retaining a known Standard/Turbo mode.
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
  Borders, shadow, pointer, icons, the Turbo-badge bolt and glow, and segments are
  hidden from accessibility.
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
- Outside the finite visible-only Turbo-badge pulse, Pixel and Smooth have no
  `TimelineView`, animation timer, continuous Canvas refresh, or rendering task.
  They redraw only when observed data, mode, style, placement, accessibility
  environment, or the finite badge-animation phase changes.
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
- Smooth and Pixel Standard/Turbo and S/M/L use identical within-style progress
  geometry without chevrons, progress bolts, endpoint ticks, or endpoint glow;
- every Standard/Turbo state has a readable localized mode badge outside the
  progress geometry without changing normal-text-size panel dimensions;
- the Turbo badge performs exactly the approved finite pulse only while a
  connected, known, positive-quota tooltip is visible; Reduce Motion, 0%,
  missing, stale/reconnecting, and hidden states remain static with no idle work;
- Smooth S/M/L retain their approved normal-size typography, colors, layout,
  content, pointer placement, hover/drag suppression, and accessibility apart
  from the frozen badge and progress-semantic amendment;
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

The relaunch-continuity and chart-clarity amendment was approved for
implementation on 8 August 2026. It keeps every existing history boundary and
storage rule while making retained history visibly survive app lifecycle gaps.

The adaptive history Y-scale amendment was approved for development on
10 August 2026. It replaces only the fixed vertical chart domain so small
observed integer-percentage changes remain legible without adding another
interaction or changing tooltip geometry.

The grouped history-gap amendment was approved for development on
11 August 2026. It removes overlapping internal borders from adjacent displayed
gap boundaries without changing their time positions or inferring missing data.

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
  and transition classification remain independent of persistence.
- `Clear Local History…` / `Очистить локальную историю…` appears only in the
  regular menu and uses a native confirmation with Cancel as the default. A
  successful clear removes active history and quarantines, leaves the current
  quota unchanged, and makes the next normally accepted snapshot a baseline.
  A failed clear never reports success.

Presentation:

- The default range is the latest 24 hours. X remains time-proportional across
  that fixed range. L/M derive one shared adaptive Y-domain from every displayed
  primary point, including observations on both sides of a reset or gap. The
  domain adds 2 percentage points of padding on each available side, rounds
  outward to 5-point boundaries, clamps to 0...100%, and expands in 5-point
  steps to a minimum 10-point span. If expansion has two equally close choices,
  the lower domain wins. The domain changes only with the derived history
  presentation and never animates. The integer-percentage source still cannot
  expose movement below one percentage point.
- L and M show a static chart plus the latest uninterrupted comparable segment.
  Smooth uses an antialiased line; Pixel uses a stepped line. Both use identical
  data semantics and the current quota color. The chart title is `Last 24 h` /
  `Последние 24 ч`; compact endpoints and observed duration share its header.
  Two numeric Y anchors show the actual upper and lower domain bounds, while
  `24 h ago` / `now` (`24 ч назад` / `сейчас`) continue to explain the fixed
  X-axis. There is no separate `Zoom` / `Увеличено` label or interactive zoom.
  The current endpoint is an outlined marker. A reset stays a line break with an
  outlined diamond and a direct `Reset` / `Сброс` label; its diamond sits between
  the adjacent observations rather than pretending to be a measured percentage.
  Consecutive displayed lost-continuity boundaries form one maximal neutral
  lightly filled dashed span with no internal borders. Continuous, reset, and
  baseline boundaries always end a span; even a short real continuous segment
  remains visible and separates adjacent spans. Grouping uses the already
  derived displayed points, preserves the outer time positions, and changes
  presentation only: it does not claim one outage, its duration, or a quota
  transition through missing continuity. The most recent grouped span is
  directly labeled `Gap` / `Перерыв` when it fits; there is no separate badge.
  Every displayed observation remains inside the shared domain, and flat
  observations remain horizontal. These additions do not change panel geometry.
- User copy shows endpoints instead of percentage-point notation: for example,
  `85% → 77%` with `over 6 hours observed`, and in compact form
  `85% → 77% · 6 h`. Russian uses `за 6 часов наблюдений` and `6 ч`.
  No `p.p.` / `п.п.` abbreviation is shown. An unchanged segment says that the
  current percentage is unchanged. When the latest segment has only one point,
  the most recent earlier segment of at least two comparable points inside the
  24-hour range remains visible as `Earlier: 85% → 77% · 6 h` /
  `Ранее: 85% → 77% · 6 ч`. Repeated one-point lifecycle segments do not hide
  that earlier completed segment. The summary switches to the latest segment as
  soon as it has two comparable points. `Collecting local history…` is reserved
  for a store with no such completed segment. A missing current primary still
  takes precedence and says that the current value is unavailable. Live primary
  availability from `AppState` wins over an older persisted endpoint during
  startup, so retained history is never presented as the current value. The
  earlier summary never connects points or infers quota use across a gap.
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
  repeated lifecycle gaps, earlier-summary fallback and handoff to the current
  segment, and primary/secondary absence are covered by focused tests;
- same-window drop, reset rollover, correction, account/plan change, startup,
  reconnect, wake, long gap, duplicate, missing metadata, and clock changes
  produce the frozen boundaries without inventing usage;
- atomic failure, corrupt JSON, unsupported version, quarantine failure,
  unwritable storage, in-memory continuation, retry, and confirmed clear are
  safe and do not affect live quota behavior;
- Smooth and Pixel L/M/S render the approved current/earlier endpoint copy,
  adaptive Y-domain and actual bound labels, gap, reset, and current-point cues,
  graph/compact composition, Standard/Turbo, Reduce Motion, stale, missing,
  English, Russian, accessibility, and visible/hidden geometry states;
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

## Approved real quota-consumption reaction — Relativistic Hotspot Plunge

The authored-frame redesign was approved for design freeze on 10 August 2026.
It supersedes the withdrawn procedural SwiftUI/Canvas reaction. The four
representative Small, Medium, Large, and Last Light motion previews are approved
as concept references. On 12 August 2026 the user approved the four final
transparent explicit-keyframe masters after actual-size S/L review and explicitly
authorized the 264-sequence derivative bake and production Swift integration.
The approved masters preserve the complete authoritative accretion disk in every
slot and add only connected contour layers; no destructive erase, particle-stamp,
sampled-orbit, procedural interpolation, or runtime effect geometry is allowed.

Trigger, continuity, and cadence:

- The feature consumes `.consumption(delta:)` from the existing shared
  `QuotaHistoryClassifier` for the primary window. `BlackHoleView` never compares
  raw percentages, and AppKit never interprets quota data.
- A comparison requires two accepted primary samples from one uninterrupted
  connection, forward local time no more than 90 minutes apart, compatible
  account, plan, limit identity, equal non-null `resetsAt`, and equal
  `windowDurationMins`; both duration values may be `nil`. Missing primary or
  reset metadata, incompatible identity or duration, startup, reconnect, wake,
  forced gap, backward clock movement, correction, and reset establish a
  baseline or discontinuity and never emit consumption.
- Duplicate and secondary-only changes neither emit nor cancel a reaction. The
  accepted snapshot order is authoritative because the protocol supplies no
  independent observation timestamp.
- Cadence is session-local to the uninterrupted primary window and is not
  persisted. Every confidently consumed percentage point advances it even when
  presentation is suppressed or cancelled. Ordinary points use Small, every
  fifth point uses Medium, and every tenth point uses Large instead of Medium.
  A multi-point delta emits at most one event at the strongest crossed milestone,
  `Large > Medium > Small`.
- A confident positive-to-zero transition emits Last Light instead of the
  cadence result. Reset, correction, reconnect, wake, identity change, and every
  other discontinuity clear cadence and transient events; duplicates, visual
  suppression, cancellation, and local-history visibility or clearing do not.
- Event identity, active state, pending state, and cadence are local to the
  current process and are never persisted or replayed after relaunch or view
  recreation.

Approved normal-motion presentation:

| Kind | Frames | Duration | Frozen visual contract |
| --- | ---: | ---: | --- |
| Small | 10 at 24 fps | 416.7 ms | One compact inner-disk hotspot with a short restrained plunge |
| Medium | 20 at 24 fps | 833.3 ms | One complete representative Relativistic Hotspot Plunge |
| Large | 30 at 24 fps | 1.25 s | Two connected disk disturbances and exactly one coronal loop |
| Last Light | 40 at 24 fps | 1.667 s | Near-complete lensed orbit, redshift, plunge, and exact 0% handoff |

- Every sequence is finite, non-looping, and advances only through uniquely
  authored raster slots without temporal interpolation. Exact endpoint slots may
  deliberately match an existing idle sprite.
- A bright inner-disk knot Doppler-brightens, shears into a crescent under
  differential rotation, produces physically connected upper and lower lensed
  images, redshifts as approved, and disappears at the opaque shadow edge. The
  black shadow remains circular, centered, fixed, and non-emissive. The disk
  never opens; light and matter never emerge from the event horizon.
- Small remains local. Medium establishes the complete motion grammar. Large is
  the upper consumption bound and contains two connected disturbances plus one
  coronal loop, without reset-like crown, jets, explosion, or loose debris. Last
  Light has no coronal loop and settles into the canonical 0% state.
- Small, Medium, and Large transient colors are white, gold, amber, and
  orange-red. Independent purple, violet, magenta, cyan, and blue are prohibited
  except colors already present in the current quota sprite. Last Light may
  redshift its moving hotspot through magenta and violet while retaining the
  canonical mixed gold/orange/magenta/violet 0% destination.
- The former packet routes, vector rings, drain threads, glints, Canvas geometry,
  exact procedural timings, overlay-only composition, and easing are rejected
  history and are not design constraints.

Reduce Motion, modes, and sizes:

- Reduce Motion replaces Small, Medium, and Large with one common transparent
  authored APNG overlay: a stationary hotspot uses three discrete brightness
  slots of 120 ms each, for 360 ms total. It has no orbit, lensing, deformation,
  pulse, scale, travel, or acceleration. Last Light immediately shows the
  authoritative 0% sprite without decorative playback.
- Any Reduce Motion value change during playback cancels active and pending
  reactions, immediately reveals the latest authoritative sprite, and creates
  no conversion, catch-up, or replay.
- Standard and Turbo use identical assets, slots, timing, and intensity. Idle
  rotation and Turbo pulse freeze during playback. A Standard/Turbo change does
  not cancel or restart the sequence; idle resumes after the exact phase handoff.
- S, M, and L use one raster family, nearest-neighbor `.aspectFit`, identical
  timing, and the existing `240 x 132`, `320 x 176`, and `400 x 220` scene
  bounds. There is no size-specific art, phase omission, runtime scale effect,
  panel resize, or hit-region change.
- Every effect pixel, including baked glow, stays inside a 10 px safe inset on
  the source canvas. Semantically necessary hotspot, crescent, and loop features
  are at least two source pixels thick and remain distinguishable at actual S
  size; otherwise the master art is revised instead of creating an S variant.

Asset and playback contract:

- Normal motion is one lossless RGBA APNG matrix of four kinds, eleven quota
  buckets, and six idle phases: 264 manifest-addressed sequences. Each authored
  sequence uses the existing transparent `384 x 272 px` canvas, anchor
  `(192, 136)`, equatorial disk plane, sRGB color, and nearest-neighbor display.
  Existing idle PNGs remain authoritative and unchanged.
- Small, Medium, and Large select the authoritative destination bucket and
  captured idle phase; their first and last slots are the exact destination PNG
  for that phase. Last Light enters from the captured positive source bucket and
  phase and ends on the exact phase-compatible `quota-0-frame-N`.
- One offline authoring/bake step derives bucket and phase variants from four
  reviewed master animations. Runtime may only select, decode through system
  ImageIO, cache, and schedule authored slots. It must not synthesize effect
  geometry through SwiftUI `Canvas`, paths, runtime particles or deformation,
  Core Image animation, Metal, or another renderer, and it adds no dependency.
- Decode and prefetch work remain off the main actor. Cache scope is bounded to
  active and pending playback and is released afterward. Missing, corrupt, or
  undecodable assets safely skip to the authoritative idle sprite without a
  crash, user-facing error, pending event, or replay. No new idle work is added.
- Bundle size, first-play latency, missed holds, peak memory, and cache release
  are measured from shipping candidates before implementation is accepted; the
  APNG decision is not permission to ship an unmeasured asset bundle.

Queue, suppression, and arbitration:

- At most one immutable reaction is active and one reaction is merged pending.
  A new event never restarts, retargets, or restitches active playback. Pending
  stores the latest authoritative target and the strongest received kind,
  `Last Light > Large > Medium > Small`, without summing deltas a second time.
  After active completes, pending starts once from the latest authoritative
  bucket and frozen phase, without an intermediate idle frame.
- Presentation starts only while the pet is visible, connected, and not being
  dragged, resized, fullscreen-suppressed, manually hidden, covered by its
  context menu, or running manual absorption. A classified event arriving while
  ineligible still updates history and cadence but creates no active or pending
  playback, catch-up, or replay.
- Drag begin, resize or size change, context-menu opening, hide, fullscreen
  suppression, disconnect, wake, view disappearance, any Reduce Motion change,
  and successful manual-absorption start immediately clear active and pending
  reactions and reveal the latest authoritative sprite.
- Manual absorption retains user-action priority. Consumption during absorption
  advances classifier history and cadence but is visually suppressed without a
  queue or replay.
- Position lock, visible click-through, an open tooltip, tooltip style or history
  preference changes, duplicates, secondary-only updates, and Standard/Turbo
  changes do not suppress or cancel playback.
- A true reset clears consumption cadence plus active and pending consumption.

Tooltip, menu, accessibility, and localization:

- An open tooltip stays open above decorative playback. Authoritative quota,
  local history, reset time, menu content, and existing accessibility summaries
  update immediately and never wait for animation. Opening the tooltip during
  playback does not cancel it or add a read beyond existing stale-on-hover logic.
- The feature adds no visible copy, tooltip or menu row, setting, localization
  string, sound, notification, achievement, VoiceOver announcement, child
  window, keyboard stop, hit target, or interaction. Artwork is decorative,
  accessibility-hidden, and noninteractive; English and Russian remain unchanged.
- Visual QA must reject alternating full-scene bright and dark frames and more
  than three qualifying luminance or red flashes in any second. Reduce Motion
  and flash safety are acceptance requirements, not subjective polish.

Normative concept references:

- [Small preview](concepts/quota-consumption-relativistic-hotspot-small-preview-v1.gif),
  SHA-256 `d96b561b92c524bf56212badfb4152e297a9ded654414ccc251c55864fa8676a`;
- [Medium preview](concepts/quota-consumption-relativistic-hotspot-medium-preview-v1.gif),
  SHA-256 `ce4f05f1b1e0dcf34d7194b1a68fe42a90692e2606a7ee4c74d18bf0ff8c6353`;
- [Large preview](concepts/quota-consumption-relativistic-hotspot-large-preview-v1.gif),
  SHA-256 `1f791f2e1a47def9d6c3c78733f91241890b7d1e13ab5558cad6c2141d662657`;
- [Last Light preview](concepts/quota-consumption-final-redshift-last-light-preview-v1.gif),
  SHA-256 `b1e5e33857bcbad0d18579f1830049de1e6f85eb0d16903ace4c29243f492bfd`.

The GIFs are motion and relative-intensity references. They contain a 500 ms
final review hold and GIF delay quantization that are absent from production.
Their black review background, crop, compression, provisional pixel clusters,
AI interpolation artifacts, and nontransparent matte are non-normative and do
not ship. Normative aspects are the motion grammar, relative Small/Medium/Large
intensity, single Large loop, Last Light orbit and redshift, fixed shadow, palette
relationships, and finite return to the canonical sprite.

Normative shipping masters approved on 12 August 2026:

- `quota-consumption-master-small.apng`, SHA-256
  `c7305f68785dc1129f1949fe98d428ccbb67923865c2d449da3faef0e378be37`;
- `quota-consumption-master-medium.apng`, SHA-256
  `d4f7ac15247390f70d3d1a204609459ec42af7c8d44bd7a3e19ad311e8085ed5`;
- `quota-consumption-master-large.apng`, SHA-256
  `15bc0b9e6f303506f27728079b655900cce40c1eaeaf070fcd5e47d6a699be5d`;
- `quota-consumption-master-last-light.apng`, SHA-256
  `c207becaa5adf7483fc21dbdb477f99843e491c8c51ce76c18f637bf62609e19`.

These lossless RGBA APNGs, rather than the earlier opaque GIF concepts, are the
authoritative source for derivative bake and runtime acceptance.

Acceptance criteria:

- deterministic classifier and cadence tests cover baseline, duplicate, 1-, 5-,
  10-, and multi-point drops, crossing both milestones, positive-to-zero,
  matching, missing, and mismatched window metadata, reset, correction, identity
  change, missing primary, reconnect, wake, long gap, and backward clock;
- state tests cover strongest pending merge, repeated arrivals, Last Light,
  completion, every cancellation and suppression path, one and three active
  absorptions, reset continuity, no replay, and immediate authoritative UI;
- asset tests cover all manifest entries, exact frame counts and durations,
  finite APNG playback, exact endpoint pixels, six-phase handoff, alpha, sRGB,
  anchor, disk plane, 10 px safe inset, decode failure, and absence of procedural
  effect geometry;
- visual regression covers Standard/Turbo parity, S/M/L actual-size readability,
  no clipping, feature thickness, Reduce Motion, 0%, tooltip coexistence, exact
  entry and exit, final transparent-master review, and flash safety;
- performance evidence covers first-play latency, missed authored holds, peak
  memory, bundle size, cache release, exact return to idle cadence, and zero new
  idle work;
- focused macOS tests and `./script/build_and_run.sh --verify` pass after
  implementation, with unchanged English, Russian, VoiceOver tree, panel
  geometry, hit testing, and App Server traffic.

Explicit non-goals are secondary-window reactions, token or cost estimates,
persisted cadence or events, replay, exact-percentage, size-specific or
mode-specific art, floating text, sound, notifications, achievements, analytics,
backend or cloud work, quota controls, a new renderer or dependency, additional
polling, process, read, setting, signing, packaging, release, or distribution
changes.

## Approved position lock and pointer click-through

The position-lock and pointer-click-through design freeze was approved for
implementation on 8 August 2026. It changes only pet-window input and position
policy; quota acquisition, rendering, manual interaction, and menu-bar
availability stay independent.

Preferences and precedence:

- The app exposes two independent persisted Boolean preferences, both disabled
  by default: `Lock Position` / `Закрепить положение` and
  `Pass Pointer Input Through` / `Пропускать ввод указателя`.
- Only an actual stored Boolean is accepted. A missing, string, collection,
  data, unsupported numeric, or otherwise invalid value falls back to `false`.
- Position lock disables movement while retaining hover, absorption, secondary
  click, Control-click, keyboard context-menu navigation, and accessibility
  actions. Click-through takes precedence over pointer interaction without
  changing the stored lock value; disabling it restores the underlying locked
  or unlocked policy.
- The menu-bar menu is the guaranteed escape from click-through. Its status item
  and native toggle remain accessible after launch, manual hide, fullscreen
  suppression, reconnect, wake, resize, and display changes.

Pointer behavior and transitions:

- With neither mode enabled, a left sequence moving at most 6 pt remains an
  absorption click, and a secondary or Control-click sequence within the same
  threshold opens the context menu. Left movement over 6 pt drags the panel;
  secondary or Control-click movement over 6 pt performs no action.
- With position lock enabled, sequences within 6 pt keep their normal actions,
  while movement over 6 pt performs no action and leaves the frame unchanged.
- With click-through enabled, the underlying application receives mouse and
  trackpad down, move, and up events regardless of the stored lock state. The
  pet starts no hover, tooltip, absorption, drag, or context-menu interaction.
- Any lock change cancels the controller's current left, secondary, and
  Control-click bookkeeping without absorption or context action. Enabling lock
  does not promise to abort a native background drag already in progress; after
  release the stable final frame is captured and subsequent dragging is blocked.
- Enabling click-through first cancels pointer tracking, stops the tooltip
  countdown and hides the tooltip, closes the context menu and removes its
  monitor, recalculates movability, and then makes the main panel ignore mouse
  events. Disabling it restores mouse events first, reapplies the current lock
  and menu policy, and suppresses tooltip reentry until a real pointer exit and
  following enter. A synthetic exit while the panel ignores events cannot clear
  that suppression.
- Context-menu opening keeps panel movement disabled. Every dismissal path
  recalculates the effective policy instead of unconditionally making the panel
  movable. Already-running manual absorption may finish; click-through never
  changes its visible presentation.

Position persistence and displays:

- A locked position persists between launches through native AppKit frame
  restoration. Unlocked movement does not update the saved locked frame, and an
  unlocked launch ignores a stale saved frame. Relocking an existing panel
  overwrites that stale record with the current frame.
- The frame is saved when lock turns on, after a size change while locked, after
  the pointer is released from a drag that was already active when locking, and
  after a corrective display reconfiguration. It is not autosaved for every
  unlocked move and never writes in a notification loop.
- Restoration loads the named frame with forced native restoration, rejects
  non-finite geometry, applies the current S/M/L scene around the restored
  center, chooses a screen only when intersection is positive and otherwise
  falls back to the main screen, then clamps to that screen's `visibleFrame`.
- The same validation runs before every show and after display-parameter
  changes. It supports negative coordinates, displays to the left or above the
  main display, rotation, removal between or during launches, and Dock or menu
  bar inset changes. No absolute-position guarantee is made across arbitrary
  display rearrangement beyond this restore-and-clamp policy.
- An ordered-out panel saves its current frame when locking. If the panel has
  not been created, a valid saved frame is used on first creation; otherwise the
  current upper-right default is used and then saved if lock is active. Hidden
  resizing uses the same center, sizing, validation, and locked-save rules.

Menus, modes, data, and accessibility:

- Both toggles appear after `Size` / `Размер` and before tooltip style in the
  native menu-bar menu and custom pixel context menu. State changes made through
  either surface use the same `AppState` actions. Enabling click-through from
  the custom menu dismisses that menu before input pass-through begins.
- The pixel menu's worst-case fixed panel is 394 x 443 pt. Only one side submenu
  is open at once, and highlighting either new top-level row closes a size or
  tooltip-style submenu. Placement continues to prefer a free quadrant; when a
  display's visible height is below 443 pt, the menu is clamped as far inside as
  possible rather than claiming full containment.
- Standard, Turbo, Reduce Motion, S/M/L, renderer cadence, tooltip styles,
  reconnect, stale or missing data, and wake behavior are unchanged. Click-
  through adds no read and does not pause sprite or manual-absorption animation.
  Detailed tooltip history is unavailable until click-through is disabled; the
  menu bar continues to provide current and secondary quota, issues, controls,
  and the existing accessible summary rather than duplicating the graph.
- Native menu items expose localized labels, toggle state, and help explaining
  that pointer input passes to applications underneath and is disabled from the
  menu bar. Custom pixel rows expose equivalent localized label, value, and help
  instead of relying only on visual selection.
- The target accessibility behavior is for the pet to remain in the external
  accessibility tree and retain both custom actions during click-through. This
  must be verified against a built `.app`. If AppKit cannot provide it reliably,
  the approved fallback is the guaranteed native menu-bar toggle with pet custom
  actions explicitly unavailable while click-through is enabled; any additional
  workaround requires a new design decision.

Architecture, performance, and privacy:

- `AppState` remains the preference source of truth. `PetPanelController` is the
  only AppKit seam and applies one effective policy:
  `allowsPointer = !clickThrough` and
  `allowsDrag = !clickThrough && !positionLocked && contextMenuPanel == nil`.
  SwiftUI menus only read state and call narrow actions.
- The feature adds no dependency, service, process, timer, polling loop,
  `TimelineView`, render cadence, App Server read, telemetry, permission, or
  network traffic. Boolean preferences and frame data remain local in
  `UserDefaults` and are not sensitive product data.

Acceptance criteria for this update:

- deterministic tests cover fresh, migrated, invalid, persisted, and relaunched
  preferences; all four lock/click-through combinations; every menu and
  accessibility entry point; and left, secondary, and Control-click sequences
  at exactly 6.0 and 6.01 pt;
- integration tests cover atomic enable/disable ordering, tooltip exit/reentry,
  pointer cancellation, an already-started drag, context-menu opening and every
  dismissal path, active manual absorption, hide/show, fullscreen,
  reconnect, stale/missing data, wake, and panel-not-yet-created behavior;
- frame tests cover S/M/L center preservation, locked hidden resize, relocking,
  invalid and non-finite geometry, four screen quadrants, negative coordinates,
  rotated and removed displays, and visible-frame changes without repetitive
  writes;
- English and Russian menu fixtures cover the worst conditional item set, both
  submenu states, Standard/Turbo, Reduce Motion, S/M/L, keyboard traversal, and
  localized accessibility label, value, and help;
- an external VoiceOver/accessibility inspection of the built `.app` verifies
  the native escape and either the target pet actions or the approved fallback;
- focused macOS tests pass, `./script/build_and_run.sh --verify` builds and
  launches the app, and visual QA confirms the changed menu states and recovery
  flow without new idle rendering or App Server traffic.

Explicit non-goals are edge snapping, magnetic placement, per-Space or per-size
positions, desktop-widget mode, window-level changes, global hotkeys, helper
processes, new permissions, renderer or quota changes, signing, packaging, or
distribution changes.

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
- The bundled set contains 33 approved models: twelve space objects, twelve
  cute animals, and nine characters. The default category selection uses
  `2 : 2 : 1`, producing 40% space objects, 40% animals, and 20% characters,
  with no immediate model repeat when an alternative is available.
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
- Absorption is silent and manually triggered, with no counters, achievements,
  progression, or automatic events. Active plans and random history remain
  session-only; only the separately approved category-weight preference may be
  persisted.
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

On 9 August 2026, the user approved the more cartoonish replacement concept
[`absorbable-people-06-07-v2.png`](concepts/absorbable-people-06-07-v2.png) for
the cargo-skirt and botanical-shirt characters. It supersedes their V1 concept
and aligns them with the approved white-shirt, purple-shirt, and green-hoodie
character style. The catalog remains 31 models with seven characters, and the
existing character category weight and interaction behavior are unchanged.

On 17 August 2026, the user approved two additional character concepts:
[`absorbable-person-08-v5.png`](concepts/absorbable-person-08-v5.png), the man
in a taupe loungewear set, and
[`absorbable-person-09-v3.png`](concepts/absorbable-person-09-v3.png), the woman
with round glasses, a prominent silver-gray face-framing streak, a tied cream
sweater, and wide gray trousers. Her V3 concept supersedes V2. The catalog now
contains 33 models with nine characters. The existing `characters` category
weight, selection behavior, animation, and interaction rules remain unchanged.

The V2 astronaut animation is the approved representative visual prototype.
The slower V3 timing is approved through the three-object launch with varied
trajectories. The user explicitly authorized implementation after the design
and visual gates were complete.

## Approved selectable absorption category weights

The user approved this design freeze and the representative
[`Object Mix` menu prototype](concepts/object-mix-menu-prototype-v1.png) on
17 August 2026. This amendment supersedes only the fixed `2 : 2 : 1` selection
rule and the former statement that absorption has no setting or persistence.
The native-menu slice subsequently received separate authorization for
production implementation. The Pixel context-menu amendment below was approved
and explicitly authorized for implementation on 18 August 2026.

Menu and interaction:

- Immediately after `Size` / `Размер`, the native menu-bar menu exposes
  `Object Mix (2:2:1)` / `Состав объектов (2:2:1)`. The trailing ratio shows the
  three selected raw weights in Space, Animals, Characters order; it is not
  converted to percentages.
- The submenu contains native pickers for `Space` / `Космос`, `Animals` /
  `Зверюшки`, and `Characters` / `Персонажи`. Each relative weight is an integer
  from `0` through `3`; `0` is labelled `Off` / `Не показывать` and excludes the
  category. A localized hint explains that larger weights appear more often.
- At least one category must remain above zero. The zero choice is disabled for
  the last active category without an alert. There is no reset command; choosing
  `2 : 2 : 1` manually restores the default mix.
- A changed mix applies to the next accepted absorption. Existing active plans
  continue unchanged. The existing limit of three active objects and ignored
  fourth click remain unchanged.
- Category selection normalizes the positive configured weights. Selection
  inside the selected category remains uniform. The same model is not selected
  on consecutive accepted clicks when an alternative exists; if exactly one
  model is available across all active categories, repeating it is allowed so
  an accepted click still creates an object.
- The native menu bar and the separately approved Pixel context-menu matrix are
  the only settings surfaces. The tooltip and pet interaction surfaces remain
  unchanged; no Settings window is added.

Persistence, failure behavior, and ownership:

- Fresh and migrated installs use manifest defaults `2 : 2 : 1`. The selected
  mix persists locally across relaunches and never syncs or leaves the Mac.
- A missing, malformed, out-of-range, or all-zero stored set falls back as a
  whole to manifest defaults. Unknown stored category IDs are ignored, a removed
  category has no effect, and a new manifest category receives its bundled
  default weight.
- `AppState` remains the preference source of truth. The bundled manifest and
  `AbsorbableObjectCatalog` remain the sources of category identity, defaults,
  validation, and normalized selection. SwiftUI reads state and invokes narrow
  actions; AppKit does not own or interpret category weights.
- Persistence failure does not affect quota data, active absorption plans, or
  the current session value and does not add a modal error for this cosmetic
  preference.

State matrix and accessibility:

- The same saved mix applies at every quota value, in Standard and Turbo, with
  Reduce Motion, at S/M/L, with Smooth or Pixel tooltips, and while connected,
  stale, reconnecting, or disconnected. It does not change animation, sizes,
  trajectories, hover, drag, positioning, lock, click-through, hide/fullscreen,
  freshness, wake, or retry behavior.
- The native menu remains available while click-through is enabled or the pet is
  hidden or fullscreen-suppressed. The Pixel matrix is available whenever the
  existing pointer-operated pet context menu is available.
- English and Russian localize the parent label, three category names, `Off` /
  `Не показывать`, explanation, accessibility labels, values, and hints. Native
  arrow-key, Return, Escape, and VoiceOver semantics expose the category, current
  weight, relative-frequency meaning, and zero behavior.
- The feature adds no App Server read, network request, analytics, timer,
  renderer work, dependency, permission, signing, packaging, or distribution
  change.

Explicit non-goals are individual weights for the 33 models, physical mass,
weight-dependent speed, trajectory or black-hole reaction, percentages,
presets, import/export, sync, counters, collections, achievements, a reset
command, or a Settings window.

Acceptance criteria for this amendment:

- deterministic tests cover all 63 valid `0...3` combinations, normalized
  boundaries, zero-category exclusion, the default 40/40/20 distribution,
  uniform within-category selection, no immediate repeat, and the single-model
  repeat fallback;
- fresh, migrated, valid, malformed, out-of-range, unknown, removed, new-category,
  all-zero, persisted, and relaunched preference states resolve as specified;
- UI prevents disabling the last active category, shows the raw current ratio,
  applies changes only to future accepted clicks, and leaves active plans intact;
- English and Russian menu fixtures and a built-app accessibility inspection
  verify the native controls and the approved Pixel matrix;
- all quota, renderer, Standard/Turbo, Reduce Motion, S/M/L, tooltip, pointer,
  connection, hide/fullscreen, and idle-performance acceptance criteria remain
  green with no new App Server traffic; focused tests, the full macOS suite, and
  `./script/build_and_run.sh --verify` pass before implementation is considered
  complete.

### Approved Pixel context-menu matrix amendment

The user approved the mouse-first matrix design freeze and the representative
[`Pixel Object Mix Matrix V2` prototype](concepts/object-mix-context-matrix-prototype-v2.png)
on 18 August 2026. This amendment supersedes only the earlier statements that
the Pixel context menu was unchanged, that its contents did not include object
weights, and that Pixel context-menu changes were a non-goal. It does not by
itself authorize implementation; the user provided that authorization
separately after approving the V2 prototype.

Content and geometry:

- Immediately after `Size` / `Размер`, the main Pixel menu adds
  `Object Mix (2:2:1)` / `Состав объектов (2:2:1)` with a static decorative
  12 × 12 pixel mix icon and a disclosure marker. The live raw ratio remains in
  Space, Animals, Characters order and is never shown as percentages.
- Hovering or clicking that row opens the existing single side slot as a matrix.
  The current manifest has three localized category rows in manifest order and
  four columns labelled `0`, `1`, `2`, and `3`. A future manifest change is not
  part of this visual freeze and must not silently alter the fixed geometry.
- The main column remains 232 pt, the inter-panel gap remains 8 pt, the matrix
  side panel is 214 pt, and the trailing shadow allowance remains 8 pt. The
  maximum fixed panel becomes 462 × 474 pt. Each matrix cell has a 31 × 31 pt
  hit region matching the existing row height; the category label column is
  76 pt. The panel does not scale with pet size.
- The visible localized hints are `0 — Off` and `Higher — more often` in English,
  and `0 — Не показывать` and `Больше — чаще` in Russian. The representative
  matrix is readable without truncating `Characters` or `Персонажи`.
- Right-opening and left-opening placements move the matrix as a whole while
  preserving the logical left-to-right column order `0, 1, 2, 3`. Existing
  quadrant selection, visible-frame clamping, multi-display behavior, shadows,
  palette, and stepped borders remain unchanged.

Mouse-first interaction and visual states:

- Hovering the parent row shows the matrix immediately. Crossing the existing
  8 pt gap does not close it. Hovering `Size`, `Tooltip Style`, or another main
  row replaces or hides the side content according to the current menu behavior.
- An available unselected cell has a dark background, inner border, and
  muted-gold numeral. Hover uses the existing hover background with a
  bright-gold outline. The selected cell uses a solid bright-gold fill with a
  dark numeral, without a checkmark. Pressed feedback is confined to the cell
  and adds no independent animation.
- Clicking an enabled cell applies the weight on mouse-up, persists through the
  existing `AppState` path, updates the selected fill and parent ratio in the
  same presentation, and keeps the menu open for further edits. Clicking the
  current cell is a no-op. Existing active absorption plans remain unchanged;
  the new mix applies to the next accepted absorption.
- The `0` cell of the last active category stays visible but uses the existing
  disabled gray-purple treatment, does not react to hover or click, and causes
  no alert, shake, tooltip, or modal error. Its enabled state is recalculated
  immediately after every successful selection.
- Outside click, repeated secondary click, Escape, pet hiding, and automatic
  fullscreen suppression retain their existing dismissal behavior. A weight
  click behaves like an in-place setting change and never starts dismissal.
- The matrix is optimized for pointer use. No dedicated two-dimensional
  keyboard navigation or new shortcut is added. Baseline macOS accessibility
  remains required: the matrix is an accessibility group with the current raw
  ratio; its 12 cells are standard buttons in row-major order; labels expose
  category and weight; selected and disabled states are announced; the zero
  choice exposes `Off` / `Не показывать`; decorative headers, hints, borders,
  and icons do not duplicate speech. Existing Escape behavior remains.

Ownership and non-goals:

- `AppState` remains the only preference source of truth and final guard.
  SwiftUI reads the manifest-ordered categories, current weights, summary, and
  zero eligibility, then invokes one narrow weight-setting action. The context
  menu panel controller does not store, validate, normalize, or interpret
  weights. No new AppKit bridge, dependency, persistence path, timer, renderer
  work, App Server request, analytics, permission, signing, packaging, or
  distribution change is introduced.
- Drill-down, a third panel, native popovers, a Settings window, category-specific
  icons, cell animation, presets, reset, percentages, and individual object
  weights remain out of scope. The selection algorithm, defaults, active-plan
  behavior, tooltip, pet animation, and black-hole reaction remain unchanged.

Acceptance criteria for the Pixel amendment:

- the full English and Russian parent labels, live ratio, three category labels,
  `0...3` headers, and both visible hints fit the approved 462 × 474 pt geometry;
- all 12 cells expose 31 × 31 pt pointer targets, exactly one selected value per
  category, distinct normal, hover, selected, pressed, and disabled treatments,
  and immediate live updates without closing the menu;
- every valid mix is reachable, only the last active category's zero is disabled,
  and enabling another category immediately re-enables that zero without an
  alert or transient error;
- right and left placement preserve `0...3` order and remain correctly clamped
  in all four quadrants, on multiple displays, with negative display coordinates,
  and at the smallest supported visible frame;
- connected, stale, reconnecting, disconnected, Standard, Turbo, Reduce Motion,
  S/M/L, Smooth/Pixel tooltip, active-absorption, lock, click-through,
  hide/fullscreen, launch-at-login, retry, dismissal, and no-network behavior do
  not regress;
- focused matrix and localization tests, the full macOS suite, built-app pointer
  and VoiceOver inspection, and `./script/build_and_run.sh --verify` pass before
  the amendment is considered implemented.

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
  `S`, `M`, and `L`; the separately approved `Object Mix` matrix;
  `Hide in Full Screen`; `Launch at Login`; conditional
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

- The functional pet, all eleven quota states, mode-neutral tooltips, Turbo
  behavior, Reduce Motion, VoiceOver summaries, fullscreen preference, and
  reconnect flow are implemented. The authored-frame quota-consumption redesign
  has approved explicit-keyframe masters and a completed 264-sequence production
  integration as of 12 August 2026.
- Launch at login is implemented with the native `SMAppService` main-app login
  item and verified through a logout/login cycle using an Apple Development
  signed build.
- Local Debug build, launch, and unit tests pass. The tests cover all 66 bundled
  sprite frames, quota mapping and transition classification, tooltip lifecycle,
  Turbo behavior, visibility, fullscreen policy, quota freshness,
  launch-at-login state handling, and automatic/manual reconnects.
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
