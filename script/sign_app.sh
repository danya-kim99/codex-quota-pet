#!/bin/bash
set -euo pipefail

# Ad-hoc preview packaging only; this does not notarize or bypass Gatekeeper.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$1" "$ROOT_DIR/Support/BlackHole.entitlements" <<'PY'
import pathlib, plistlib, subprocess, sys

app = pathlib.Path(sys.argv[1]).resolve(strict=True)
entitlements = pathlib.Path(sys.argv[2]).resolve(strict=True)
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
if info.get('CFBundleIdentifier') != 'com.blackholecodex.quotaindicator':
    raise SystemExit('Refusing to sign a different application')
framework = app / 'Contents/Frameworks/Sparkle.framework'
if not framework.is_dir():
    raise SystemExit('Sparkle.framework is missing from the app')

# Sign nested code from the inside out, retaining each helper's own entitlements.
mach_o = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe',
          b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
targets = []
roots = [app / 'Contents/Frameworks', app / 'Contents/PlugIns', app / 'Contents/MacOS']
for path in (path for root in roots if root.exists() for path in root.rglob('*')):
    if path.is_symlink():
        continue
    if path.is_dir() and path.suffix in {'.app', '.xpc', '.framework', '.xctest'}:
        targets.append(path)
    elif path.is_file():
        with path.open('rb') as source:
            if source.read(4) in mach_o:
                targets.append(path)
for path in sorted(targets, key=lambda p: len(p.parts), reverse=True):
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                    '--timestamp=none', '--preserve-metadata=entitlements', str(path)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                '--timestamp=none', '--entitlements', str(entitlements), str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
actual = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
if actual != {'com.apple.security.cs.disable-library-validation': True}:
    raise SystemExit('Unexpected application entitlements')
print('Verified ad-hoc application and nested Sparkle code:', app)
PY
