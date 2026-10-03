#!/bin/bash
set -euo pipefail
# Compiles the production module and exercises it without launching the app or creating windows.
repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/build/companion-checks"
module=Black_Hole_Codex_Quota_Indicator
sparkle_framework="${BH_COMPANION_SPARKLE_FRAMEWORK:-$repo/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
[ -f "$sparkle_framework/Modules/module.modulemap" ] || { printf 'Missing Sparkle: %s\n' "$sparkle_framework" >&2; exit 2; }
sparkle=$(dirname "$sparkle_framework")
bundle="$out/CompanionChecks.bundle"
mkdir -p "$out/module-cache" "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
ditto "$repo/Resources" "$bundle/Contents/Resources"
ditto "$repo/Assets/Sprites/frames" "$bundle/Contents/Resources/frames"
ditto "$repo/Assets/Sprites/objects" "$bundle/Contents/Resources/objects"
ditto "$repo/Assets/CompanionPreviews" "$bundle/Contents/Resources/CompanionPreviews"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.black-hole.companion-checks</string><key>CFBundleExecutable</key><string>CompanionChecks</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(cd "$repo" && /usr/bin/find App Models Services Support Views -type f -name '*.swift' | LC_ALL=C sort)
cd "$repo"
common=(-swift-version 5 -D DEBUG -Onone -g -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" -module-cache-path "$out/module-cache" -F "$sparkle")
xcrun swiftc "${common[@]}" -parse-as-library -emit-library -emit-module -enable-testing -module-name "$module" -emit-module-path "$out/$module.swiftmodule" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" -o "$out/lib$module.dylib" "${sources[@]}" > "$out/compile-production.log" 2>&1
runner="$bundle/Contents/MacOS/CompanionChecks"
xcrun swiftc "${common[@]}" -parse-as-library -I "$out" -L "$out" -l"$module" -framework Sparkle -Xlinker -rpath -Xlinker "$out" -Xlinker -rpath -Xlinker "$sparkle" Tests/CompanionPickerChecks.swift -o "$runner" > "$out/compile-checks.log" 2>&1
"$runner" --source-root "$repo"
"$runner" --preview "$out/companion-picker-ru.png" -AppleLanguages '(ru)' -AppleLocale ru_RU
"$runner" --preview "$out/companion-picker-en.png" -AppleLanguages '(en)' -AppleLocale en_US
"$runner" --orbit-preview "$out/companion-orbit-native.png"
