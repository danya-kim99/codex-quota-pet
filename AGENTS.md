# Black Hole Codex Quota Indicator guidance

## Product scope

This repository contains a native macOS 14+ floating Codex quota pet. The pet is
an animated black hole whose accretion disk visualizes remaining quota. Product
requirements live in `docs/PRODUCT_SPEC.md`; technical boundaries live in
`docs/ARCHITECTURE.md`.

The MVP is local-only. Do not add a backend, analytics, cloud sync, skins,
non-macOS platforms, Codex Fast-mode controls, or quota-reset behavior unless the
user explicitly expands scope.

## Architecture

- Keep SwiftUI and `AppState` as the source of truth.
- Keep AppKit bridges narrow and limited to macOS capability gaps such as the
  floating `NSPanel`.
- Start with SwiftUI and native platform APIs. Add MetalKit only after the
  simpler renderer demonstrably falls short.
- Consume the documented Codex App Server protocol. Do not scrape Codex UI,
  credentials, or private application files.
- Apply Ponytail full: reuse existing code, prefer standard library and native
  APIs, and do not add speculative abstractions, files, or dependencies.

## Protected settings

Do not change signing, entitlements, bundle identifier, deployment target,
launch-at-login configuration, release metadata, or distribution settings
without an explicit request. The current local debug build intentionally uses
`CODE_SIGNING_ALLOWED=NO`.

## Verified local workflow

From the project root:

```sh
./script/build_and_run.sh --verify
```

This builds the Debug app into `build/DerivedData`, launches the `.app`, and
checks that its process exists. The Codex Run action is configured in
`.codex/environments/environment.toml` and calls `./script/build_and_run.sh`.

The focused macOS test command is:

```sh
xcodebuild -project 'Black Hole Codex Quota Indicator.xcodeproj' \
  -scheme 'Black Hole Codex Quota Indicator' \
  -configuration Debug \
  -derivedDataPath 'build/DerivedData' \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
