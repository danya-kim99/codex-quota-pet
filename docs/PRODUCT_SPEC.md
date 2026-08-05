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
