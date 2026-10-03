# Companion picker

Status: final functional and Pixel/Smooth mockups frozen on 2 October 2026;
native selection-control implementation explicitly authorized. The user then
approved the orbital preview at 5 seconds per revolution and authorized its
implementation. Automatic activation still requires a verified activity source.

The user approved the catalogue with a magnifier after removing the redundant
“У Дыры” sprite comparison and its divider. The approved control implementation is recorded in docs/PRODUCT_SPEC.md.

## Frozen control behavior

- Compact entry row shows the chosen companion and opens or closes the catalogue.
- Categories: space, animals and characters. One selected model has a stable ID.
- Hover or keyboard focus changes the large preview without changing selection.
  Click, Enter or Space selects the model; the selected tile retains a checkmark.
- The magnifier uses detailed source artwork. Grid and runtime sprites keep the
  existing assets; zoom affects only the large preview, at 1×, 1.5× and 2×.
- Arrow keys move through the grid. Close and Escape dismiss the catalogue and
  return focus to its entry. “Без спутника” clears the chosen companion.
- Category changes and zoom preserve the chosen model. Changing presentation
  between Pixel and Smooth preserves the same choice and control state.
- The companion is intended to appear only during work and disappear afterwards.
  The control carries the “Во время работы” label.
- Do not restore the removed “У Дыры” comparison or its divider.

## Approved character names and order

| Stable ID | Display name |
| --- | --- |
| character-white-shirt | Даня |
| character-purple-shirt | Женя |
| character-green-hoodie | Расул |
| character-glasses | Мила |
| character-cream-sweater | Настя |
| character-cargo-skirt | Лиза К. |
| character-botanical-shirt | Лёша Р. |
| character-taupe-loungewear | Денис |
| character-tied-cream-sweater | Лиза П. |
| character-charcoal-blazer | Паша |

Order is left to right, then the next row, including when the grid adapts in width.

### Missing tenth character correction — 3 October 2026

The user confirmed that the existing sprite set contains ten characters and named
the tenth Паша. Restore `character-charcoal-blazer` after Лиза П. in the shared
catalogue: 34 models, including ten characters. Preserve its previously shipped
80×80 PNG and derive its HQ preview from `absorbable-person-10-v1.png`.
Keep three character columns; Паша occupies the first tile of the fourth row,
reachable by keyboard and the existing scrolling container in both styles.
Selection, persistence, manual absorption and the working companion use the same
stable ID. The original 33 frozen entries, crops and artwork remain unchanged;
this is an additive correction to that reference, not a replacement mockup.
Acceptance: all ten names/assets/previews, fourth-row navigation, persisted Паша
selection and a local build pass. Live GUI verification remains separate.

Verified locally: the fresh app bundles 34 models and 34 preview entries; all ten
names, persisted Паша selection and fourth-row navigation model pass focused
checks. The original 33 sprites, six HQ sources and frozen HTML are unchanged.
RU/EN offscreen renders show Паша's full HQ silhouette in Pixel and Smooth.
The fourth row uses the existing scroll container at the retained panel height;
physical scrolling, keyboard delivery and VoiceOver remain unverified. The fresh
unsigned app/test build and independent review/QA passed. Evidence is in
`build/companion-ten-audit/`; this build has not been launched.

## Presentation references

Pixel follows `PixelPalette` and `PixelMenuBackground` in
`Views/PixelContextMenuView.swift`: fixed dark purple surface, system monospaced
type, stepped 7/3 pt corners, 2 pt outer gold border, inset inner border, crisp
purple/black offset shadows, gold selection and brown hover fill.

Smooth follows the existing Smooth tooltip family in `Views/QuotaTooltipView.swift`:
charcoal surface, rounded system type, 18 pt corners, restrained white border,
soft shadow and warm gold accent. The current menu-bar menu is system-rendered;
this mockup proposes a matching picker panel, not a replacement native menu.

The catalogue stays a separate approximately 380 pt panel, with the same controls
in both styles. It is not squeezed into the existing 232 pt context-menu width.
Detailed preview artwork remains detailed in both presentations.

## Approval boundary and evidence

The control and subsequent 5-second orbital preview are approved for local
implementation. The real work-start/pause/terminal event source must be verified
before automatic runtime motion can be enabled. The updated motion specification
is recorded in docs/PRODUCT_SPEC.md.

Approved fragment in this task's visualization directory:
`companion-picker-hq.html`, SHA-256
`7f93fe50b18a5f356c8e5aa5336d0645c33deed20215954f090c924d897628f3`.
It remains unchanged. Styling comparison: `companion-picker-styles.html`.

Styling checks must preserve the names, IDs, image data, hover/selection distinction,
zoom, keyboard controls, close behavior and disabling. At narrow widths, names
with initials must remain readable. Pixel must retain its dark palette in a light
host appearance. Headless prototype checks do not verify native VoiceOver or live
application behavior.

Final frozen style source: `docs/concepts/companion-picker-approved.html`,
SHA-256 `0fd47b726429255053ba283a641a847a76414422191eec702b4ce1eaae2dcbaf`. Character grid 3×3, common content inset, anchored
preview name, gold selected-name accent in both appearances.

## Approved orbital motion

The user reviewed the animation, requested double speed, and then approved
implementation. The interactive reference uses the unchanged quota-50 six-frame
loop and game PNGs. Its simulated activity is only a visual reference.

- One clockwise elliptical orbit every 5 seconds (doubled speed at the user's request), upright sprite with at most
  5 degrees of tilt. L-scene radii 130 × 62 pt, scaled with S/M/L; the original
  80 pt sprite canvas follows the existing manual-absorption scale.
- The far half is composited behind the existing hole; the near half is in
  front. Depth scale varies gently from 0.88 to 1.00. No trail or orbit line.
- Appearance takes 350 ms; completion fades the current sprite over 250 ms.
  No shrinking spiral, new absorption event or effect on the quota disk.
- With Reduce Motion, the companion remains static beside the hole while busy;
  appearance/disappearance are immediate and the hole uses its existing frame 0.
- Demo activity is simulated and clearly separate from the production source.
  The demo runs one finite cycle and offers pause/replay and character selection.

The updated prototype was sampled at 701 points; the complete sprite canvas stays
inside the existing pet scene. Front/back layers, disappearance, static reduced
motion and widths 736/320 passed headless checks. This proves the proposed
geometry only, not native runtime delivery. The user separately approved the
visual result and implementation.

## Native control implementation evidence

Implemented locally: AppState selection/persistence, one shared picker panel from
both menus, original miniatures plus the approved HQ sheets/crops, RU/EN labels,
three categories, magnifier and keyboard/focus handling. The subsequently approved
native orbit is now implemented; automatic busy integration remains blocked by
the source limitation documented below.

The unsigned Debug app and test target compile. Focused catalogue checks and the
existing completion-notice regression pass; source hashes are recorded in
`build/companion-implementation-audit/manifest.json`. The actual offscreen SwiftUI
renders in `build/companion-checks/companion-picker-{ru,en}.png` preserve the
representative Mila/Lyosha crops, readable initials and footer in both skins.
Live menu tracking, focus, pointer dismissal, sleep and VoiceOver remain unverified.
No app launch, installation, release/version change, commit or publication occurred.

Independent read-only code and QA reviews found one preview/keyboard-selection
mismatch; it was fixed and rechecked before the final build. No confirmed
in-scope defects remained in the reviewed source and offscreen renders.

## Activity source verification — 2 October 2026

Automatic activation is blocked by the available external activity contract,
not by motion approval. Installed CLI reports `0.159.0-alpha.12.1`.
A read-only `codex app-server daemon version` probe could not connect to the
standard control socket (`No such file or directory`, OS error 2); no daemon
or GUI was started and no user configuration was changed.

The app's independent stdio App Server cannot observe the Desktop server's
in-memory active turns. Its thread reader can normalize an unloaded persisted
`inProgress` turn to `Interrupted`, so polling that reader cannot prove busy.
The existing `notify` integration supplies completion hints only.

External hooks are incomplete for this purpose: `UserPromptSubmit` precedes
acceptance; `Stop` may request continuation and is bypassed by terminal errors;
`Interrupt` covers only the `Interrupted` abort reason, not every terminal
path. `SessionEnd` is session-level. The internal Rust lifecycle contributors
cover more events but are not the external command-hook interface.

Evidence: the existing source snapshot in
`/private/tmp/black-hole-notify-source-v0159/`, specifically
`codex-rs__app-server__src__request_processors__thread_processor.rs:2778,5805–5824`,
`codex-rs__core__src__session__turn.rs:649–683,780–816`,
`codex-rs__core__src__tasks__mod.rs:822–823,986–987`, and
`codex-rs__core__src__tasks__lifecycle.rs:46–57`.
The installed binary's commit SHA was not independently established in this pass.
Official interface references: https://learn.chatgpt.com/docs/hooks and
https://learn.chatgpt.com/docs/app-server.

The current implementation therefore stops at a native renderer and isolated
motion checks, with automatic presentation inactive. Completing the feature
requires a supported connection to the server actually executing Desktop tasks,
an initial activity snapshot and complete lifecycle/status events. It must
handle concurrent turns and invalidate activity on disconnect/sleep. Do not
substitute partial hooks, private-file polling or a fabricated busy timer.

## Native orbit implementation evidence

The existing SwiftUI timeline now shares a native `PetSpriteScene` with the
offscreen harness. Ordinary sprites, 5-second geometry, far/near layers,
350/250 ms appearance/removal, static waiting/Reduce Motion and selection/reset
behavior are implemented. `AppState.companionActivity` is read-only and returns
`.unavailable`; there is no simulated production start event or configuration
change. A real active companion therefore does not appear in the normal app yet.

`build/companion-orbit-checks.log` records passing geometry/state/render checks,
2,103 S/M/L bounds samples, pixel equality for the representative inactive quota
scene and the existing catalogue/asset checks. Read-only review found an opacity
increase when a task finished before appearance completed. The correction freezes
the reached entry opacity; 130 early-finish samples now verify monotonic removal
and zero opacity at 250 ms. The focused reviewer and QA rechecked this correction.

`build/companion-orbit-build.log` records `TEST BUILD SUCCEEDED` with
`CODE_SIGNING_ALLOWED=NO`; completion/IPC regression also passed before the final
isolated fade correction. The native contact sheet is
`build/companion-checks/companion-orbit-native.png`. The six-file scoped source
diff and final hashes are in `build/companion-orbit-audit/`. The existing Debug app
is under `build/CompanionPickerDerivedData/Build/Products/Debug/`.

GUI, hosted XCTest, installation, release metadata and publication were not part
of this run. Live activity delivery, concurrency, VoiceOver and active resize,
hide/show and sleep recovery remain unverified. In particular, future integration
must reconcile verified activity after the existing absorption reset clears the
presentation; pure scene bounds do not prove this lifecycle behavior.

## Follow-up owner-endpoint verification — 3 October 2026

The user authorized completing integration, native checks and local Release
preparation, with publication still excluded. A fresh read-only investigation
closed two alternatives without changing Codex configuration:

- The installed CLI still reports `0.159.0-alpha.12.1`. The standard daemon
  control socket is absent. Sanitized process metadata identified the actual
  Desktop-owned App Server as a separate standard-stdio process, with no
  `--listen`, daemon/proxy arguments or TCP listener. Its input/output streams
  belong to its parent application; the pet's independent stdio server cannot
  attach as a second client.
- The paginated turn-reader also calls `normalize_thread_turns_status` after
  converting stored statuses. It uses its own thread manager/watch state;
  it does not preserve another process's live `InProgress` status. Therefore
  switching from the legacy reader to `thread/turns/list` does not solve busy
  detection.

Source evidence in the existing snapshot:
`codex-rs__app-server__src__lib.rs:775–821` (stdio single-client transport),
`codex-rs__app-server__src__request_processors__thread_processor.rs:3269–3282`
(paginated normalization), `:5811–5824` (normalization rule), and `:2641`
(thread-list enrichment from the owner's runtime). No chat content, credentials
or private application data was read. A new daemon was not started.

The missing capability remains a supported second connection to the actual
Desktop server, with an initial runtime snapshot and subsequent lifecycle
events. A separate shared-server/CLI workflow would be a distinct product and
workflow decision, not a transparent fix for existing Desktop tasks. No new
activity transport or fake busy fallback was added.

Local Release preparation in `build/companion-activity-audit/` is consequently
technical validation only. It must not be described as a completed automatic
companion release or replace the previously prepared 0.14.0 candidate.

The fresh Release build and technical ZIP passed compilation, bundle/resource
validation, completion/IPC regression and archive round-trip checks. They retain
the checkout's 0.13.2 (32) metadata; the original 0.14.0 candidate is unchanged.
Evidence: `build/companion-activity-audit/release-audit.md` and
`release-verification.json`. No signing, installation or publication occurred.

The initial native QA attempt was stopped by automatic approval review at the
context-menu action. The user then explicitly approved the proposed menu/picker
checks, restoring settings and closing only the test copy.

The subsequent live Pixel/English pass confirmed context-menu entry, all nine
character names, selection of Мила and then Настя, zoom at 1×/1.5×/2× with disabled
endpoints, close via X, and preservation of Настя when reopening the catalogue.
The original No companion state and 2× preview were restored; object weights
remained 0:0:3. Quit closed test PID 72973; a process check confirmed original
PID 61752 was still running from the published 0.13.2 bundle.

Keyboard delivery through CUA did not change either the picker or the standard
macOS application menu (including Escape). This is an inconclusive tool-level
control, not a confirmed catalogue defect; focused source review found no
confirmed keyboard bug. Access to SystemUIServer for the status-menu check timed
out. Status-menu entry, keyboard/focus, Smooth live interaction and VoiceOver
therefore remain unverified. No source changes or new build were needed for this
pass. Evidence is in `build/companion-activity-audit/gui-check.json`.

## Approved hooks experiment — 3 October 2026

After the user accepted trying the approximate hooks approach, a bounded opt-in
prototype was implemented. The complete contract is the final experimental
section in PRODUCT_SPEC.md. Ordinary launches remain inactive; only a launch
with `BLACK_HOLE_COMPANION_HOOK_TOKEN` set to the experiment UUID listens to the
separate activity channel. No Codex configuration, hook trust or existing notify
settings were changed.

The built executable's `--black-hole-activity-hook-v1` mode reads at most 64 KiB
for at most 0.5 seconds, before SwiftUI starts. It forwards only event/IDs/time
and returns neutral JSON. AppState aggregates finite in-memory turn state from
eight hook events, including SubagentStop. Positive hints refresh a ten-minute
expiry; permission hints retain an already observed turn statically. Terminal
tombstones, session cutoffs and lifecycle epochs reject late state revival.
The original five-second renderer and catalogue remain unchanged.

Evidence in `build/companion-hooks-audit/`:

- `build.log`: successful unsigned Debug build in `build/CompanionHooksDerivedData`.
- `checks.log`: parser/privacy, ordering, parallel turns, waiting, Stop and
  SubagentStop, cancellation, TTL after a missing terminal event, lifecycle
  resets, default-off, actual headless executable → distributed notification →
  AppState, and existing completion regression checks.
- `qa-replay.log`: independent repeat of the complete headless hooks runner.
- `qa-helper-smoke.json`: independent malformed/oversize/default-off/no-EOF
  checks. The first valid notification was blocked by the tool sandbox; the
  explicitly allowed local-IPC retry passed with neutral output and no stderr.
- `scoped-source-manifest.json` and `scoped-source.diff`: the eight-file change
  relative to the pre-experiment dirty checkout, preserving unrelated work.

The reviewer found no confirmed production defect. A private-type visibility
error in the test fixture and missing localized resources in the regression
runner were corrected before the passing run. Agent capacity prevented a
separate QA agent; the primary agent performed the independent QA replay.

These checks send synthetic hook payloads through real IPC; they do not prove
Codex's dispatcher or live Desktop rendering. The scheduled expiry timer was
not awaited for ten real minutes; TTL is checked with an injected clock. Hook
trust, real dispatch, error/oversized-input handling by Codex, and live GUI remain
unverified. Conservative Stop tombstones can miss same-turn continuations, and
ten minutes without events can hide a still-working companion. The prepared
hook definition must be reviewed and trusted normally before a live test; no
trust bypass, application launch, installation or publication was performed.
