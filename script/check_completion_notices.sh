#!/bin/bash
set -euo pipefail
# Headless only. Builds a testable source module; no App.main/AppDelegate or real configuration writes.
repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/build/completion-checks"
module=Black_Hole_Codex_Quota_Indicator
sparkle_framework="${BH_COMPLETION_SPARKLE_FRAMEWORK:-$repo/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
app="${BH_COMPLETION_APP_EXECUTABLE:-$repo/build/CompletionNoticesDerivedData/Build/Products/Debug/Black Hole Codex Quota Indicator.app/Contents/MacOS/Black Hole Codex Quota Indicator}"
[ -x "$app" ] || { printf 'Missing built app executable: %s\n' "$app" >&2; exit 2; }
[ -f "$sparkle_framework/Modules/module.modulemap" ] || { printf 'Missing Sparkle compiler framework: %s\n' "$sparkle_framework" >&2; exit 2; }
sparkle=$(dirname "$sparkle_framework")
mkdir -p "$out/module-cache" "$out/CompletionChecks.bundle/Contents/MacOS" "$out/CompletionChecks.bundle/Contents/Resources"
runner="$out/CompletionChecks.bundle/Contents/MacOS/CompletionChecks"
ditto "$repo/Resources" "$out/CompletionChecks.bundle/Contents/Resources"
cat > "$out/CompletionChecks.bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.black-hole.completion-checks</string><key>CFBundleExecutable</key><string>CompletionChecks</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(cd "$repo" && /usr/bin/find App Models Services Support Views -type f -name '*.swift' | LC_ALL=C sort)
cd "$repo"
common=(-swift-version 5 -D DEBUG -Onone -g -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" -module-cache-path "$out/module-cache" -F "$sparkle")
xcrun swiftc "${common[@]}" -parse-as-library -emit-library -emit-module -enable-testing -module-name "$module" -emit-module-path "$out/$module.swiftmodule" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" -o "$out/lib$module.dylib" "${sources[@]}" > "$out/compile-production.log" 2>&1
xcrun swiftc "${common[@]}" -parse-as-library -I "$out" -L "$out" -l"$module" -framework Sparkle -Xlinker -rpath -Xlinker "$out" -Xlinker -rpath -Xlinker "$sparkle" Tests/CompletionNoticeChecks.swift -o "$runner" > "$out/compile-checks.log" 2>&1
LLVM_PROFILE_FILE="$out/headless-forward-%p.profraw" "$runner" --app-executable "$app"
"$runner" --preview "$out/response-notice-preview.png" -AppleLanguages '(ru)' -AppleLocale ru_RU
"$runner" --preview "$out/response-notice-preview-en.png" -AppleLanguages '(en)' -AppleLocale en_US
