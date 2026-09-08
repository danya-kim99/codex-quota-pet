#!/usr/bin/env python3
"""Prepare and verify a signed feed locally. Never publishes or creates a key."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
REPOSITORY = 'https://github.com/danya-kim99/codex-quota-pet'
APP_NAME = 'Black Hole Codex Quota Indicator.app'


def fail(message):
    raise SystemExit(message)


def run_signed(command, secret):
    result = subprocess.run(command, input=secret, text=True, capture_output=True)
    if result.returncode:
        # Signing-tool diagnostics must never echo key material into CI logs.
        fail(f'{Path(command[0]).name} failed; no update was published')
    return result.stdout


def items(path):
    parsed = ET.parse(path)
    found = {}
    for item in parsed.findall('./channel/item'):
        enclosure = item.find('enclosure')
        build = item.findtext(SPARKLE + 'version')
        if enclosure is None or not build or not re.fullmatch(r'[1-9][0-9]*', build):
            fail('Feed contains an invalid update item')
        if build in found:
            fail('Feed contains duplicate build numbers')
        url = enclosure.get('url', '')
        if not url.startswith(REPOSITORY + '/releases/download/'):
            fail('Feed archive is outside the approved GitHub repository')
        if not enclosure.get(SPARKLE + 'edSignature'):
            fail('Feed archive has no Ed25519 signature')
        found[build] = (item, enclosure)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--tools', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    previous = parser.add_mutually_exclusive_group(required=True)
    previous.add_argument('--previous-feed', type=Path)
    previous.add_argument('--bootstrap', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', args.tag):
        fail('A stable vMAJOR.MINOR.PATCH release tag is required')
    secret = os.environ.get('SPARKLE_PRIVATE_KEY', '').strip()
    try:
        raw = base64.b64decode(secret, validate=True)
    except (ValueError, base64.binascii.Error):
        fail('SPARKLE_PRIVATE_KEY must be a valid base64 Ed25519 seed')
    if len(raw) != 32:
        fail('SPARKLE_PRIVATE_KEY must contain a 32-byte Ed25519 seed')
    # Keep the private seed in memory/stdin, never argv, a file, or the Keychain.
    secret += '\n'
    sign_tool = str((args.tools / 'sign_update').resolve(strict=True))
    generator = str((args.tools / 'generate_appcast').resolve(strict=True))
    archive = args.archive.resolve(strict=True)
    expected_name = f'Black-Hole-Codex-Quota-Indicator-{args.tag}-macos-arm64.zip'
    if archive.name != expected_name:
        fail('Archive name does not match the selected release tag')
    with zipfile.ZipFile(archive) as package:
        info = plistlib.loads(package.read(APP_NAME + '/Contents/Info.plist'))
    if info.get('CFBundleIdentifier') != 'com.blackholecodex.quotaindicator':
        fail('Archive contains a different application')
    build = info.get('CFBundleVersion', '')
    if not re.fullmatch(r'[1-9][0-9]*', build):
        fail('The app must contain a positive integer CFBundleVersion')
    if info.get('CFBundleShortVersionString') != args.tag[1:]:
        fail('Archive version and release tag differ')
    expected = {
        'SUFeedURL': REPOSITORY + '/releases/latest/download/appcast.xml',
        'SUVerifyUpdateBeforeExtraction': True, 'SURequireSignedFeed': True,
        'SUSignedFeedFailureExpirationInterval': 0, 'SUEnableAutomaticChecks': False,
        'SUAutomaticallyUpdate': False, 'SUAllowsAutomaticUpdates': False,
        'SUEnableSystemProfiling': False, 'SUEnableJavaScript': False,
    }
    if any(type(info.get(k)) is not type(v) or info[k] != v for k, v in expected.items()):
        fail('Archive does not contain the approved updater settings')
    public = info.get('SUPublicEDKey', '')
    # CryptoKit is supplied by macOS; do not install a Python crypto dependency.
    swift = '''import Foundation
import CryptoKit
let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: input)!)
guard key.publicKey.rawRepresentation.base64EncodedString() == CommandLine.arguments[1] else { exit(1) }
'''
    run_signed(['xcrun', 'swift', '-e', swift, public], secret)
    prior = {}
    if args.previous_feed:
        run_signed([sign_tool, '--ed-key-file', '-', '--verify', str(args.previous_feed)], secret)
        prior = items(args.previous_feed)
        if prior and int(build) <= max(map(int, prior)):
            fail('New build must be greater than every previously published build')

    args.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='appcast-', dir=args.output_dir) as staging:
        stage = Path(staging)
        staged_archive = stage / archive.name
        shutil.copyfile(archive, staged_archive)
        # Embed escaped text so release notes cannot introduce scripts or external resources.
        import html
        (stage / (archive.stem + '.html')).write_text(
            '<pre>' + html.escape(args.notes.read_text()) + '</pre>', encoding='utf-8'
        )
        feed = stage / 'appcast.xml'
        if args.previous_feed:
            shutil.copyfile(args.previous_feed, feed)
        run_signed([
            generator, '--ed-key-file', '-', '--maximum-deltas', '0',
            '--maximum-versions', '0', '--embed-release-notes',
            '--download-url-prefix', REPOSITORY + '/releases/download/' + args.tag + '/',
            '-o', str(feed), str(stage),
        ], secret)
        run_signed([sign_tool, '--ed-key-file', '-', '--verify', str(feed)], secret)
        generated = items(feed)
        if set(generated) != set(prior) | {build}:
            fail('Generated feed lost historical entries or added an unexpected build')
        for old_build, (_, old_enclosure) in prior.items():
            if generated[old_build][1].attrib != old_enclosure.attrib:
                fail('Generated feed changed an existing archive entry')
        item, enclosure = generated[build]
        if (enclosure.get('url') != REPOSITORY + '/releases/download/' + args.tag + '/' + archive.name
                or enclosure.get('length') != str(archive.stat().st_size)
                or item.findtext(SPARKLE + 'shortVersionString') != args.tag[1:]):
            fail('Generated feed does not match the packaged application')
        run_signed([sign_tool, '--ed-key-file', '-', '--verify', str(archive),
                    enclosure.get(SPARKLE + 'edSignature')], secret)
        shutil.copyfile(feed, args.output_dir / 'appcast.xml')
    print(f'Verified signed archive and appcast for build {build}; retained {len(prior)} historical entries')
    print('appcast SHA-256:', hashlib.sha256((args.output_dir / 'appcast.xml').read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
