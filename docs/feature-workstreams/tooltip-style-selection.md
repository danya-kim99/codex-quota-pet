# Workstream: Smooth and Pixel tooltip styles

Status: historical discovery handoff for the implemented two-style baseline

User priority decision: 6 August 2026

Shared context: [README.md](README.md)

The active implementation-ready follow-up is
[tooltip mode and progress refinement](tooltip-mode-progress-refinement.md). It
supersedes this historical brief only for mode badges and progress decoration.

## Product intent

Let the user choose between two presentations of the same live quota details:

- **Smooth** — the current approved tooltip, preserved as-is.
- **Pixel** — a code-native pixel-art presentation based on the six
  `docs/concepts/quota-tooltip-*.png` references and visually aligned with the
  black-hole sprites and custom pixel context menu.

This workstream is the first implementation priority because secondary quota
and local history will later add content to the tooltip. They must build on a
frozen two-style content/layout boundary instead of redesigning the tooltip in
parallel.

## Current behavior

- `QuotaTooltipView` owns both current layouts:
  - L uses a 320 pt card inside a 360 × 178 pt panel;
  - M uniformly scales the L layout to 80%;
  - S uses a separate 248 × 112 pt compact card inside a 272 × 132 pt panel.
- Current Smooth styling uses rounded system typography, rounded card corners,
  a subtle border/shadow, a linear L/M progress bar, and a circular S indicator.
- Standard uses a plain progress treatment. Turbo adds a bolt, chevrons, and
  edge emphasis without changing quota geometry.
- Tooltip content includes exact primary remaining percentage, localized reset
  countdown, reset date/time, and mode-aware progress.
- `PetPanelController` owns the separate noninteractive tooltip `NSPanel`, four-
  side placement, size, screen clamping, and recreation when placement changes.
- Tooltip visibility is suppressed during drag, absorption click, context menu,
  hide, and fullscreen suppression according to the existing product freeze.
- No tooltip-style preference currently exists.

Relevant files:

- `Views/QuotaTooltipView.swift`
- `Support/PetPanelController.swift`
- `Models/AppState.swift`
- `Support/AppConstants.swift`
- `Views/MenuBarContent.swift`
- `Views/PixelContextMenuView.swift`
- `Resources/en.lproj/Localizable.strings`
- `Resources/ru.lproj/Localizable.strings`
- `Tests/RateLimitDecodingTests.swift`

## Visual references

Primary Pixel family:

- `docs/concepts/quota-tooltip-standard-arcade-lm-v1.png`
- `docs/concepts/quota-tooltip-standard-arcade-s-v1.png`
- `docs/concepts/quota-tooltip-turbo-arcade-lm-v1.png`
- `docs/concepts/quota-tooltip-turbo-arcade-s-v1.png`

Comparative Turbo explorations:

- `docs/concepts/quota-tooltip-turbo-clean-concept-v1.png`
- `docs/concepts/quota-tooltip-turbo-pixel-menu-style-v1.png`

The primary family establishes the stepped gold frame, dark violet-black panel,
purple offset shadow, pixel pointer toward the pet, large percentage, mode
label/badge, Standard/Turbo progress treatments, reset-window segments, clock
and calendar rows, and separate L/M versus S composition.

The PNG files are visual references, not flattened UI assets. Production must
render real quota values, localized text, dynamic dates, missing-data states,
accessibility, and all four pointer placements in SwiftUI. Do not ship screenshots
with embedded English text and do not generate a raster for every state.

## Recommended first-slice hypothesis

1. Add one persisted two-case preference, conceptually `smooth` / `pixel`.
2. Existing and migrated installs default to Smooth so the current approved UI
   does not change without user action.
3. Expose a localized `Tooltip Style` / `Стиль подсказки` picker with `Smooth`
   and `Pixel` in the standard menu bar and custom pixel context menu.
4. Switching style updates an open tooltip immediately, preserves its visible
   screen side, recalculates panel size, and clamps it on-screen without requiring
   a relaunch or pointer exit.
5. Smooth reuses the current implementation and dimensions without visual
   redesign in this slice.
6. Pixel is implemented with SwiftUI shapes, layout, and existing palette/native
   facilities. No new renderer or dependency.
7. Both styles consume one shared semantic quota-content model/formatting path;
   they differ only in visual composition.

These are starting recommendations, not approved behavior.

## Design decisions to resolve

### Picker behavior

- Confirm Smooth as the default for fresh and migrated installs.
- Confirm persistence and invalid-value fallback.
- Decide whether the pixel context menu uses a submenu or two direct rows.
- Place the picker without exceeding the context menu’s readable fixed geometry;
  update placement tests if panel dimensions change.
- Define whether a style change keeps the custom menu open or dismisses it.
- Define keyboard navigation, trailing checkmarks, icons, and VoiceOver state.

### Pixel typography

No pixel font is currently bundled. Decide between:

- system monospaced typography styled to match the concepts; or
- one bundled pixel font with verified redistribution license, Cyrillic coverage,
  legibility at S size, and application-bundle integration.

Do not add a font package dependency. A font without complete Russian glyphs is
not acceptable. The prototype must compare English and Russian before a font is
approved.

### Pixel geometry

Resolve exact production dimensions for:

- L card and containing tooltip panel;
- M scaling or a dedicated M layout;
- dedicated S card and panel;
- stepped border thickness and purple offset shadow;
- pixel pointer for above, below, left, and right placement;
- internal padding, percentage baseline, reset row, icons, and progress height.

The concept artwork includes a visual black hole only to show attachment and
scale. It is not part of the tooltip panel asset and must not be duplicated in
the SwiftUI tooltip.

### Pixel state mapping

Define Pixel versions of:

- Standard and Turbo;
- normal, warning, and critical quota colors using existing thresholds;
- missing quota (`—` and empty track/ring);
- missing reset timestamp or duration;
- connected versus stale/dimmed/reconnecting presentation;
- 0% and 100%;
- long localized dates, day plurals, and unusually large system text settings.

Turbo references show a bolt and chevrons. Decide whether these elements are
static or have a restrained transition. Reduce Motion must remove any optional
movement while preserving the same information.

### Smooth preservation

“Smooth as-is” means the first slice should not redesign its typography, colors,
layout, dimensions, pointer, progress semantics, S compact card, shadows, or
animation. Refactoring shared content/formatting is allowed only if screenshots,
layout tests, accessibility, and behavior demonstrate no Smooth regression.

## Shared content boundary

Preferred flow:

`AppState live data -> shared formatted tooltip content -> Smooth or Pixel presentation -> PetPanelController panel placement`

The shared layer should cover semantic values and formatting already common to
both styles:

- exact remaining percentage and quota level;
- Standard/Turbo mode;
- reset countdown, date/time, and day indicator;
- missing-data and accessibility summaries.

Do not build an abstract theme engine, protocol hierarchy, or arbitrary skin
system for two fixed styles. Two focused SwiftUI presentations over shared pure
formatting are sufficient. `AppState` owns the persisted style preference;
`PetPanelController` applies style-dependent panel geometry but does not own the
preference or quota semantics.

## Interaction, accessibility, and localization

- Tooltip remains noninteractive and contains no actions.
- Existing hover refresh, suppression, drag, absorption, context-menu, hide,
  fullscreen, and reconnect behavior remains unchanged.
- Changing style cannot generate App Server traffic.
- Both styles expose the same concise VoiceOver values regardless of decorative
  structure. Borders, shadows, chevrons, icons, and pointer are hidden.
- English and Russian must be reviewed in Standard/Turbo and S/L references.
- Pixel copy should remain natural localized copy; do not force all-uppercase if
  it harms Cyrillic readability or causes truncation.
- Dynamic Type/accessibility text sizing on macOS must remain readable without
  overflowing the visible panel; document the supported behavior.
- Reduce Motion changes only motion, not the selected style.

## Cross-feature coordination

- This workstream freezes the two-style tooltip foundation before secondary
  quota and local history change tooltip content.
- Secondary quota must later define both Smooth and Pixel layouts, including S.
- Local history must later define both Smooth and Pixel representations or an
  explicitly approved style-independent surface.
- Consumption visuals do not alter style selection, but tooltip values must
  still update correctly during their events.
- Click-through removes pointer hover for both styles and must preserve the
  menu-bar path to style selection when pointer interaction is enabled again.
- Do not implement secondary quota or history content speculatively in this
  slice.

## Representative prototype gate

Before production implementation, present a code-native or precise visual
prototype containing at least:

1. Pixel L/M Standard;
2. Pixel L/M Turbo;
3. Pixel S Standard;
4. Pixel S Turbo;
5. English and Russian examples;
6. one warning/critical quota example;
7. a direct comparison with the unchanged Smooth equivalent.

Also show the chosen pixel typography and all four pointer directions, or provide
a geometry proof that the same stepped pointer rotates without changing layout.
The user must explicitly approve the representative Pixel system and the
Smooth-preservation contract before implementation.

## Acceptance areas to include in the freeze

- fresh, migrated, and invalid stored style preference;
- style picker in menu bar and context menu, keyboard and VoiceOver state;
- immediate switching while tooltip is visible and while hidden;
- Smooth screenshot/layout regression in Standard/Turbo and S/M/L;
- Pixel Standard/Turbo, S/M/L, 0/critical/warning/normal/100%, missing data;
- English/Russian, long localized values, Cyrillic font coverage;
- above/below/left/right placement, all screen edges, multiple displays;
- hover refresh, drag, absorption, context menu, resize, hide/fullscreen,
  reconnect/stale state, launch, and Reduce Motion;
- no hit-test change and no extra App Server calls;
- no idle rendering/frame-rate regression;
- pure formatting, preference, panel-size, placement, and view-state tests;
- focused macOS tests, `./script/build_and_run.sh --verify`, and screenshot QA
  after implementation.

## Explicit non-goals

- more than two tooltip styles;
- arbitrary user themes, palettes, skins, or custom CSS/theme files;
- flattened screenshot-based production UI;
- redesigning Smooth in the first slice;
- secondary quota, history chart, notifications, or new quota semantics;
- new renderer, database, third-party dependency, backend, analytics, or cloud
  sync;
- changes to the pet sprites, absorption, signing, or distribution.

## Paste-ready prompt for a new chat

```text
Work on the highest-priority feature “Smooth and Pixel tooltip styles” in:

/Users/danya-kim/Documents/Development/Black Hole Codex Quota Indicator

Before any action, read in full:
- AGENTS.md
- docs/PRODUCT_SPEC.md
- docs/ARCHITECTURE.md
- docs/feature-workstreams/README.md
- docs/feature-workstreams/tooltip-style-selection.md

Inspect all six docs/concepts/quota-tooltip-*.png files at original resolution.
Treat the current implemented tooltip as Smooth “as is”. Treat the PNGs as
visual references for one selectable Pixel style, not as flattened production
assets and not as authorization for a third style. The four arcade L/M/S
Standard/Turbo images are the primary family; compare the two additional Turbo
concepts when resolving typography and degree of pixel styling.

Use ponytail full and build-macos-apps:swiftui-patterns. Reinspect the current
QuotaTooltipView, PetPanelController, AppState, menu bar, pixel context menu,
localization, tests, and dirty worktree. Preserve all user files.

This chat is for discovery, one representative Pixel system prototype, Smooth
regression contract, picker behavior, and a consolidated design freeze. Do not
modify production Swift, bundle a font, generate final assets, or implement
until I explicitly approve the complete freeze. Resolve persisted default and
migration, menu-bar/context-menu selection, typography and Cyrillic licensing,
S/M/L geometry, four pointer directions, Standard/Turbo, quota color/missing
states, Reduce Motion, English/Russian, VoiceOver/keyboard, live style switching,
screen clamping, performance, and coexistence with future secondary/history
content.

After explicit approval, first record the frozen behavior in
docs/PRODUCT_SPEC.md, then use feature-vertical-slice to implement the smallest
complete native SwiftUI solution over shared semantic formatting. Keep Smooth
visually unchanged, add proportional tests, run focused macOS tests,
./script/build_and_run.sh --verify, and screenshot QA. Do not commit, push,
publish, sign, or change distribution configuration without a separate request.

Start by reporting the code/visual audit, your recommended minimal architecture,
the differences you observed across the six references, and the first blocking
design choice. Ask one decision at a time.
```
