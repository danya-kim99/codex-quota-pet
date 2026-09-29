# Tooltip snapshots

Requires macOS, Xcode and the project's existing Sparkle package artifact. No
additional packages, app launch, real App Server, network calls or settings
changes. The script compiles current production sources into a testable
framework; the application entrypoint is never invoked.

From the repository root, render 32 fixtures across RU/EN, Smooth/Pixel, S/M/L
and history on/off (768 cards, 24 labelled 1× overview sheets):

```sh
bash script/tooltip_snapshots.sh render \
  --app-bundle 'build/Merge0121DerivedData/Build/Products/Debug/Black Hole Codex Quota Indicator.app' \
  --sparkle-framework 'build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
```

Pass another existing built app/package artifact when those paths differ. The
app supplies resources; source localizations are refreshed from `Resources/`.
Compiler logs live in `build/tooltip-snapshots/tool/`. Images, contact sheets and
per-language manifests live in `build/tooltip-snapshots/`. The PNGs preserve the
whole rendered panel at 2×; overview tiles display it at 1× without trimming.

Inspect the actual images, especially S and two-event states. **Do not record
known clipping or other defects as correct.** Only after explicit visual review:

```sh
bash script/tooltip_snapshots.sh record --reviewed
```

This copies the already-rendered, internally verified matrix to
`Tests/Snapshots/Tooltip/`. No initial references are supplied automatically.
`record` is the only mode that changes references; it preserves the reviewed
render's environment metadata instead of generating new metadata.

For regression verification use the render command above with `check` instead
of `render`. It recompiles/renders current sources into an explicit 8-bit sRGB
RGBA bitmap context and compares decoded pixels, not PNG metadata or compressed
bytes. This avoids the implicit ImageRenderer target's observed early-render
one-step color quantization drift; no comparison tolerance is used. Missing
references, changed dimensions/pixels, a changed card set or a different
OS/SDK/Swift/font/render environment fail without updating references.
`--output` and `--baseline` may select separate directories, including a copied
reference set for negative tests; resolved ancestor/descendant overlap is rejected
before writing.

Time is fixed to 2026-09-29 10:00 UTC; locale, calendar, timezone, dark appearance
and normal text size are pinned. `isTooltipPresented: false` suppresses the
decorative badge task, and the render transaction disables animations. The tool
does not override the system's read-only Reduce Motion value. Fixtures use
volatile preferences, an in-memory history store and fake transport, with awaited
state/history readiness. Coverage includes zero/unknown/99/100+/exact spoken
counts, disconnection with cached quota, missing/zero/critical/warning quota,
missing reset date, next-year dates, every public-state copy, simultaneous events,
deduplication and expiry. This is static-card verification, not live hover,
window placement, actual animations or spoken VoiceOver.
