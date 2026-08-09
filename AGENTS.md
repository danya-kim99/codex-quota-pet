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

## Evidence-first visual debugging

- Treat a user-supplied source/output comparison as confirmed evidence of a
  defect. A green test, deterministic regeneration, safe margin, or reviewer
  opinion does not override a visible mismatch; it means the current check may
  assert the wrong invariant.
- Before changing scale, viewport, padding, outlines, animation, or generating
  replacement art, compare the marked region through the complete pipeline:
  approved source, intermediate crop/mask, generated asset, and runtime render.
  Fix the first stage where pixels diverge.
- Never infer that source pixels are missing until the approved source has been
  inspected at original resolution. Do not use image generation to repair a
  pipeline loss.
- If the user reports the same mismatch after one attempted correction, stop
  the current hypothesis. Reproduce the exact comparison, invalidate prior
  visual passes that conflict with it, and diagnose again from the source.
- Check every sibling asset that uses the same pipeline, then leave one focused
  regression check at the failing stage. Provide a source/current/fixed visual
  for user approval when the result is subjective.

## Automatic agent routing

The primary agent must select and delegate to the project agents under
`.codex/agents/` when a request enters one of the phases below. The user does
not need to name the agents. Announce the delegation briefly, give each agent a
bounded task and output contract, wait for every required result, and return one
synthesis rather than raw agent transcripts. Run at most three subagents at the
same time.

Automatic routing changes who performs the work, not what is authorized. Never
advance from discovery or design to production implementation without the
explicit approvals required above, and never advance from release readiness to
signing or publication without a separate explicit request.

### Discovery

When the user asks what to build next, requests feature ideas, or presents an
unshaped product opportunity, spawn `product_scout`, `product_manager`, and
`experience_designer` in parallel. Keep them read-only. Require evidence-backed
options, product fit, risks, effort, and a smallest validation step. The primary
agent reconciles overlap and presents no more than five candidates. Do not edit
product documents or code in this phase.

### Product design and design freeze

When the user selects or refines a feature and no complete approved design
freeze exists, spawn `product_manager`, `experience_designer`, and
`macos_architect` in parallel. Require one shared state matrix, unresolved
decisions, native feasibility constraints, non-goals, and testable acceptance
criteria. The primary agent resolves contradictions and presents the
consolidated design freeze for user approval.

After explicit approval, the primary agent records the approved behavior in
`docs/PRODUCT_SPEC.md`. Approval of an individual concept, prototype, or
subsection does not satisfy this gate.

### Implementation

When the user authorizes implementation and the approved design freeze is
already recorded, use `macos_architect` first if the implementation boundary is
missing or stale, then delegate production changes to `swift_implementer`.
These steps are sequential. `swift_implementer` is the only subagent allowed to
edit source code or tests; do not run competing writer agents in parallel.

If the required approval or recorded specification is absent, stop at the
missing gate and return to the design phase instead of asking the implementer to
guess.

### Verification and correction

After implementation, spawn `reviewer` and `qa_accessibility` in parallel.
Require both to map findings to the approved acceptance criteria and distinguish
confirmed failures from unverified risks. They must not edit source code.

The primary agent deduplicates their findings. Send confirmed in-scope fixes to
`swift_implementer`, then rerun only the affected verification. Do not hide
remaining failures or repeat correction loops indefinitely; report unresolved
work when another product decision or user action is required.

### Release readiness

Only when the user explicitly requests release-readiness work, delegate the
audit to `release_auditor`. It may build and inspect artifacts but must not
change protected settings, sign, notarize, publish, upload, commit, push, or
delete builds. The primary agent reports passed, failed, blocked, and unverified
items separately.

### Small-task exception

Do not create an agent swarm for a typo, a purely mechanical documentation
correction, or another obviously local low-risk change with no product,
architecture, runtime, or release decision. For every non-trivial product or
code change, follow the phase routing above. If a named custom agent is
unavailable, continue with the same role constraints in the primary thread and
state the fallback.

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
