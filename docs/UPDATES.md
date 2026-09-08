# Application updates

The implementation uses Sparkle 2.9.6 and GitHub Releases. Checks are initiated
from **Check for Updates… / Проверить обновления…** in the native menu. Sparkle
handles the update windows, download, verification, installation and relaunch.

Version 0.10.0 (build 23) is the first updater-enabled release. Version 0.9.0
requires a one-time manual replacement with this version. Local source builds
still require an explicit public key; release builds obtain it from GitHub.

## Build configuration

`Support/Info.plist` contains typed manual-only and strict signing settings.
Supply `SPARKLE_PUBLIC_ED_KEY` to Xcode when building a configured app. It is the
canonical Base64 encoding of the public Ed25519 key, not a password or private
seed. Without a valid key, the menu reports that the update channel is not
configured and does not start a check.

The fixed production feed is:
`https://github.com/danya-kim99/codex-quota-pet/releases/latest/download/appcast.xml`.
The public key is a permanent trust anchor for installed versions; retain a
secure backup of its private counterpart. Do not generate a different key for
each release. Production key creation and GitHub secret provisioning require
separate authorization from implementation.

The approved ad-hoc configuration uses only the host's
`com.apple.security.cs.disable-library-validation` entitlement and retains
Hardened Runtime. Sparkle signatures do not provide notarization or suppress
Gatekeeper warnings. Neither application nor packaging scripts should disable
system-wide macOS security.

## Publishing contract

The release workflow requires a `SPARKLE_PUBLIC_ED_KEY` repository variable and
`SPARKLE_PRIVATE_KEY` secret. The new private-key format is a canonical Base64
32-byte Ed25519 seed. Never put it in Xcode build settings, command arguments,
source files, output artifacts or logs. Signing tools receive it through stdin.
Use a distinct temporary key for local verification; do not put a test key in a
production release.

The packaging path must fail if the archive's embedded public key differs from
the signing key. A successful `generate_appcast` exit alone is insufficient:
Sparkle can merely warn about that mismatch. Verify the archive signature
against the key embedded in the app, and verify the signed feed before upload.

Preserve the previous signed appcast and all compatible entries. Do not replace
an unreachable or invalid existing feed with an empty one. An explicit bootstrap
is required for the first feed. Generate full archives only, embed release notes,
and sign the final XML after all changes. Publish the complete ZIP, SHA-256 and
appcast set before switching the release to latest.

## Verification boundaries

The feature acceptance checklist is in
[`feature-workstreams/app-self-update.md`](feature-workstreams/app-self-update.md).
A compile or signature check is not proof of successful replacement and relaunch.
Use two isolated updater-enabled builds for the A → B test; preserve the user's
installed application and quota data. GUI testing requires explicit consent
under this workspace's AGENTS.md.

Check history drain failure/timeout, resumed collection after cancellation,
build-matched frame/visibility restoration, native cancellation, English/Russian,
keyboard/VoiceOver, hidden/click-through pet, and actual ad-hoc Gatekeeper
behavior before calling an update release verified.

Official references: [setup](https://sparkle-project.org/documentation/),
[configuration](https://sparkle-project.org/documentation/customization/),
[publishing](https://sparkle-project.org/documentation/publishing/).
