#!/bin/bash
set -euo pipefail
# Headless only: no app UI, real Codex hook/config/trust writes or image previews.
repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/build/companion-hooks-audit/checks"
module=Black_Hole_Codex_Quota_Indicator
sparkle_framework="${BH_HOOK_SPARKLE_FRAMEWORK:-$repo/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
app="${BH_HOOK_APP_EXECUTABLE:-$repo/build/CompanionHooksDerivedData/Build/Products/Debug/Black Hole Codex Quota Indicator.app/Contents/MacOS/Black Hole Codex Quota Indicator}"
[ -x "$app" ] || { printf 'Missing built app: %s\n' "$app" >&2; exit 2; }
[ -f "$sparkle_framework/Modules/module.modulemap" ] || { printf 'Missing Sparkle: %s\n' "$sparkle_framework" >&2; exit 2; }
sparkle=$(dirname "$sparkle_framework")
mkdir -p "$out/module-cache"
cd "$repo"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(/usr/bin/find App Models Services Support Views -type f -name '*.swift' | LC_ALL=C sort)
common=(-swift-version 5 -D DEBUG -Onone -g -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" -module-cache-path "$out/module-cache" -F "$sparkle")
xcrun swiftc "${common[@]}" -parse-as-library -emit-library -emit-module -enable-testing -module-name "$module" -emit-module-path "$out/$module.swiftmodule" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" -o "$out/lib$module.dylib" "${sources[@]}" > "$out/compile-production.log" 2>&1
link=(-parse-as-library -I "$out" -L "$out" -l"$module" -framework Sparkle -Xlinker -rpath -Xlinker "$out" -Xlinker -rpath -Xlinker "$sparkle")
xcrun swiftc "${common[@]}" "${link[@]}" Tests/CompanionHookChecks.swift -o "$out/CompanionHookChecks" > "$out/compile-checks.log" 2>&1
unset BLACK_HOLE_COMPANION_HOOK_TOKEN
LLVM_PROFILE_FILE="$out/helper-%p.profraw" "$out/CompanionHookChecks" --app-executable "$app"
# Exercise the unchanged completion route against the same executable; no preview mode.
completion_bundle="$out/CompletionRegressionChecks.bundle"
completion_runner="$completion_bundle/Contents/MacOS/CompletionRegressionChecks"
mkdir -p "$completion_bundle/Contents/MacOS" "$completion_bundle/Contents/Resources"
ditto "$repo/Resources" "$completion_bundle/Contents/Resources"
cat > "$completion_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.black-hole.completion-regression-checks</string><key>CFBundleExecutable</key><string>CompletionRegressionChecks</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
xcrun swiftc "${common[@]}" "${link[@]}" Tests/CompletionNoticeChecks.swift -o "$completion_runner" > "$out/compile-completion-checks.log" 2>&1
LLVM_PROFILE_FILE="$out/completion-%p.profraw" "$completion_runner" --app-executable "$app"
