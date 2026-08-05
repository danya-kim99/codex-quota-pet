---
name: add-black-hole-characters
description: Generate pixel-art characters from user photos, obtain explicit visual approval, add approved character sprites to Black Hole Codex Quota Indicator through its manifest-driven asset pipeline, and prepare the next GitHub preview release. Use for requests to add, update, or release absorbable people/characters in this specific project.
---

# Add Black Hole Characters

Follow the four gates in order. Treat approval of one gate as approval of that
gate only.

## 1. Generate concepts

1. Read the project `AGENTS.md`, `docs/PRODUCT_SPEC.md`,
   `docs/ABSORPTION_DESIGN_FREEZE.md`, and current Git status.
2. Read and use the `imagegen` skill. Use each photo as an identity/clothing
   reference and the latest approved character sheet as a style reference.
3. Preserve recognizable hair, expression, glasses, and clothing. Use one
   full-body floating pose per person, hard pixel edges, the dark navy backdrop,
   and no logos or readable brand text.
4. Save a versioned concept under `docs/concepts/` and show it to the user.
5. Stop before production assets, manifest changes, version bumps, or release
   work. Request explicit visual approval.

## 2. Record approval

After explicit approval:

1. Record the added characters, concept paths, date, total model count, and
   character count in `docs/PRODUCT_SPEC.md` and
   `docs/ABSORPTION_DESIGN_FREEZE.md` before changing runtime assets.
2. Preserve the existing `characters` category and its selection weight unless
   the user explicitly approves a behavior change.
3. Confirm that release work targets the repository's existing GitHub preview
   channel. Do not change Developer ID signing or notarization.

If approval requests visual changes, edit only the concepts and repeat this
gate.

## 3. Integrate approved characters

1. Add stable descriptive IDs to `MODELS` in
   `script/generate_absorbable_objects.py` and route each approved concept sheet
   through the existing `extract_sheet` helper. Keep normal characters
   manifest-driven; do not add Swift branches.
2. Let preview rows derive from `len(MODELS)` so future additions do not overflow
   the atlas.
3. Run `script/generate_absorbable_objects.py` with a Python environment that
   already provides Pillow and NumPy. Prefer the Codex bundled workspace Python
   if the system Python lacks them; do not add project dependencies for this.
4. Inspect every new `Assets/Sprites/objects/absorb-*.png` and the combined
   `Assets/Sprites/previews/absorbable-objects-atlas.png` for silhouette,
   transparency, clipping, scale, and stray pixels.
5. Update the manifest/sprite test counts and README catalog count. Leave Swift
   production code unchanged unless the existing manifest path demonstrably
   cannot load the assets.

## 4. Prepare the preview release

1. Choose the next SemVer patch version and increment
   `CURRENT_PROJECT_VERSION` once in both project configurations.
2. Add `docs/releases/vX.Y.Z.md` using the latest release-note format. Mention
   only the new characters, catalog count, and checks that actually ran.
3. Run, in order:

   ```sh
   xcodebuild -project 'Black Hole Codex Quota Indicator.xcodeproj' \
     -scheme 'Black Hole Codex Quota Indicator' \
     -configuration Debug \
     -derivedDataPath 'build/DerivedData' \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO \
     test

   xcodebuild -project 'Black Hole Codex Quota Indicator.xcodeproj' \
     -scheme 'Black Hole Codex Quota Indicator' \
     -configuration Release \
     -derivedDataPath 'build/ReleaseDerivedData' \
     -destination 'platform=macOS,arch=arm64' \
     CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
     build

   ./script/build_and_run.sh --verify
   ```

4. Validate the Release bundle version, build number, macOS minimum, arm64
   architecture, manifest count, and presence of every new PNG.
5. Review the complete diff and preserve unrelated user files.
6. Do not create a local ZIP, commit, push, tag, dispatch CI, or publish a GitHub
   release unless the user explicitly asks for that external step. The existing
   `CI and Release` workflow owns signing, checksumming, packaging, tagging, and
   publishing.

Report the new IDs, total catalog count, release version/build, exact checks and
results, saved concept/asset paths, and any CI-only work still pending.
