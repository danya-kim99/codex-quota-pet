# Black Hole Codex Quota Indicator guidance

## Product scope

This repository contains a native macOS 14+ floating Codex quota pet. The pet is
an animated black hole whose accretion disk visualizes remaining quota. Product
requirements live in `docs/PRODUCT_SPEC.md`; technical boundaries live in
`docs/ARCHITECTURE.md`.

The MVP is local-only. Do not add a backend, analytics, cloud sync, skins,
non-macOS platforms, Codex Fast-mode controls, or quota-reset behavior unless the
user explicitly expands scope.

## Product workflow gates

- Keep discovery and design separate from implementation. Do not edit production
  code, generate batch final assets, or begin release work while product design
  still has unresolved decisions.
- Treat statements such as "fix this section" or "move to the next design step"
  as approval of that section only. They do not authorize implementation.
- Before implementation, present one consolidated design-freeze specification
  covering quota states, Standard/Turbo and Reduce Motion behavior, tooltip and
  menu content, hover/drag/positioning behavior, localization, accessibility,
  data freshness and failure states, distribution scope, and acceptance criteria.
- Begin implementation only after the user explicitly approves that consolidated
  specification for development. Record the approved behavior in
  `docs/PRODUCT_SPEC.md` before changing production code.
- Validate one representative visual prototype with the user before generating
  all states or committing to a renderer/asset pipeline. The user owns subjective
  visual approval; automated layout, accessibility, build, and regression checks
  remain the agent's responsibility.
- Maintain an acceptance checklist through implementation so previously approved
  features are not silently removed or regressed. If design changes after the
  freeze, pause implementation, update the specification and checklist, assess
  affected work, and obtain approval again before continuing.
- Verify external protocol semantics from authoritative source or a focused live
  experiment before choosing an architecture. Inspect existing authentication,
  tooling, and environment state before asking the user to configure them.
- Confirm the intended distribution channel before changing certificates,
  signing, notarization, packaging, or release configuration.
- Keep agent-run visual QA proportional. Unless the user explicitly delegates
  aesthetic approval, provide a build for their review instead of spending an
  extended cycle judging subjective visual fidelity.

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

## GitHub release transport

- Prefer the GitHub integration or `gh` CLI for repository and release actions.
- If `gh auth status` is invalid, use `gh auth login -h github.com` before
  falling back to browser automation.
- Use the GitHub web UI only when the integration and authenticated CLI do not
  expose the required operation.
