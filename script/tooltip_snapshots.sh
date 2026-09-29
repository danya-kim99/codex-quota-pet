#!/bin/bash
set -euo pipefail

# Offscreen only: never opens an app, invokes AppDelegate, or contacts a service.
# render/check --app-bundle APP --sparkle-framework FRAMEWORK [--output DIR] [--baseline DIR]
# record --output DIR [--baseline DIR] --reviewed  (only after reviewing the PNGs)
repo=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-}; shift || true
output="$repo/build/tooltip-snapshots"
baseline="$repo/Tests/Snapshots/Tooltip"
app_bundle= sparkle_framework= reviewed=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app-bundle) app_bundle=$2; shift 2;;
    --sparkle-framework) sparkle_framework=$2; shift 2;;
    --output) output=$2; shift 2;;
    --baseline) baseline=$2; shift 2;;
    --reviewed) reviewed=true; shift;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2;;
  esac
done
case "$mode" in render|check|record) ;; *) printf 'Use render, check, or record; see script header.\n' >&2; exit 2;; esac
# Resolve existing symlink ancestors without creating either directory.
canonical_path() {
  local parent leaf
  if [ -d "$1" ]; then (cd "$1" && pwd -P); return; fi
  parent=$(canonical_path "$(dirname "$1")")
  leaf=$(basename "$1")
  case "$leaf" in
    .) printf '%s\n' "$parent";;
    ..) dirname "$parent";;
    *) printf '%s/%s\n' "${parent%/}" "$leaf";;
  esac
}
output=$(canonical_path "$output")
baseline=$(canonical_path "$baseline")
case "$output/" in "$baseline/"*) printf 'Output overlaps references; refusing before any writes.\n' >&2; exit 2;; esac
case "$baseline/" in "$output/"*) printf 'References overlap output; refusing before any writes.\n' >&2; exit 2;; esac
tool="$output/tool"
module=Black_Hole_Codex_Quota_Indicator
runner="$tool/TooltipSnapshots.bundle/Contents/MacOS/TooltipSnapshots"

if [ "$mode" = record ]; then
  [ "$reviewed" = true ] || { printf 'Review images first; record requires --reviewed.\n' >&2; exit 2; }
  [ -x "$runner" ] || { printf 'Run render before recording reviewed outputs.\n' >&2; exit 2; }
  "$runner" record "$output" "$baseline"
  exit
fi

[ -d "$app_bundle/Contents/Resources" ] || { printf 'Pass a built app with --app-bundle.\n' >&2; exit 2; }
[ -f "$sparkle_framework/Modules/module.modulemap" ] || {
  printf 'Pass the existing Sparkle.framework with compiler Modules using --sparkle-framework.\n' >&2; exit 2;
}
app_bundle=$(cd "$app_bundle" && pwd -P)
sparkle_framework=$(cd "$sparkle_framework" && pwd -P)
mkdir -p "$tool/$module.framework/Resources" "$tool/module-cache" \
  "$tool/TooltipSnapshots.bundle/Contents/MacOS" "$tool/TooltipSnapshots.bundle/Contents/Resources"
framework="$tool/$module.framework"
ditto "$app_bundle/Contents/Resources" "$framework/Resources"
ditto "$app_bundle/Contents/Resources" "$tool/TooltipSnapshots.bundle/Contents/Resources"
# Use current source strings even if the passed app predates a copy correction.
ditto "$repo/Resources" "$framework/Resources"
ditto "$repo/Resources" "$tool/TooltipSnapshots.bundle/Contents/Resources"
for bundle in "$framework" "$tool/TooltipSnapshots.bundle/Contents"; do
  info="$bundle/Info.plist"
  [ "$bundle" != "$framework" ] || info="$bundle/Resources/Info.plist"
  plutil -create xml1 "$info"
  plutil -insert CFBundleIdentifier -string local.black-hole.tooltip-snapshots "$info"
  plutil -insert CFBundleDevelopmentRegion -string en "$info"
done
plutil -insert CFBundleExecutable -string "$module" "$framework/Resources/Info.plist"
plutil -insert CFBundlePackageType -string FMWK "$framework/Resources/Info.plist"
plutil -insert CFBundleExecutable -string TooltipSnapshots "$tool/TooltipSnapshots.bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string BNDL "$tool/TooltipSnapshots.bundle/Contents/Info.plist"

sources=()
while IFS= read -r source; do sources+=("$source"); done < <(
  find "$repo/App" "$repo/Models" "$repo/Services" "$repo/Support" "$repo/Views" -name '*.swift' -type f | LC_ALL=C sort
)
sparkle_parent=$(dirname "$sparkle_framework")
common=(-swift-version 5 -D DEBUG -Onone -g -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macos14.0" -module-cache-path "$tool/module-cache" -F "$sparkle_parent")
xcrun swiftc "${common[@]}" -parse-as-library -emit-library -emit-module -enable-testing \
  -module-name "$module" -emit-module-path "$tool/$module.swiftmodule" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$sparkle_parent" \
  -Xlinker -install_name -Xlinker "@rpath/$module.framework/$module" \
  -o "$framework/$module" "${sources[@]}" > "$tool/compile-production.log" 2>&1
xcrun swiftc "${common[@]}" -parse-as-library -I "$tool" -F "$tool" \
  -framework "$module" -framework Sparkle -Xlinker -rpath -Xlinker "$tool" \
  -Xlinker -rpath -Xlinker "$sparkle_parent" "$repo/Tests/TooltipSnapshots.swift" \
  -o "$runner" > "$tool/compile-snapshots.log" 2>&1
export TZ=UTC
export BH_SNAPSHOT_SWIFT_VERSION="$(xcrun swiftc --version)"
export BH_SNAPSHOT_SDK_VERSION="$(xcrun --show-sdk-version)"
for language in en ru; do
  "$runner" render "$output" "$language" -AppleLanguages "($language)" \
    -AppleLocale "${language}_$( [ "$language" = en ] && printf US || printf RU )" \
    -AppleICUForce24HourTime YES
done
if [ "$mode" = check ]; then "$runner" check "$output" "$baseline"; fi
