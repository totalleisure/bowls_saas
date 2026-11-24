#!/usr/bin/env python3
"""Mac-only production build and App Store Connect upload. No shell interpolation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import time
import zipfile

BUNDLE = 'com.totalleisure.bowlssaas'
TEAM = 'XX6FPA95YH'
ROOT = Path(__file__).resolve().parent.parent
KEY = Path.home() / '.config/bowls/app-store-connect.json'


def digest(path):
    with path.open('rb') as stream:
        checksum = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
        return checksum.hexdigest()


def read_release(root, notes_path):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
                      (root / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise ValueError('pubspec.yaml must contain version: X.Y.Z+BUILD.')
    notes = notes_path.read_text(encoding='utf-8-sig').strip()
    if not notes or len(notes) > 4000 or re.search(r'</?en-', notes):
        raise ValueError('Supply plain release notes, 1-4000 characters, without language tags.')
    project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
    if f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};' not in project or f'DEVELOPMENT_TEAM = {TEAM};' not in project:
        raise ValueError('Production iPhone bundle identifier/team not found.')
    if not (root / 'lib/main.dart').is_file():
        raise ValueError('Production entry point missing.')
    return match[1], match[2], notes


def outside(path, root):
    if path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Apple credentials must be outside the repository.')


def configure_key(root, p8, key_id, issuer_id, destination):
    outside(p8, root)
    outside(destination, root)
    if not key_id or not issuer_id:
        raise ValueError('Both key ID and issuer ID are required for a team API key.')
    content = p8.read_text()
    if '-----BEGIN PRIVATE KEY-----' not in content:
        raise ValueError('Expected an Apple .p8 private key.')
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Exclusive creation protects an existing configuration; never print the key.
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(dict(key_id=key_id, issuer_id=issuer_id, key=content, in_house=False), stream)
    print(f'Apple API configuration saved privately at {destination}')


def run(command, root, log=None, env=None):
    if log is None:
        subprocess.run(command, cwd=root, env=env, check=True)
        return
    with log.open('a', encoding='utf-8') as stream:
        process = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            print(line, end='', flush=True)
            stream.write(line)
        if process.wait():
            raise RuntimeError(f'Step failed; see {log}. If upload started, inspect App Store Connect before retrying.')


def fastlane_command(action, key, **options):
    return ['bundle', 'exec', 'fastlane', 'run', action, f'api_key_path:{key}',
            f'app_identifier:{BUNDLE}'] + [f'{k}:{str(v).lower() if isinstance(v, bool) else v}'
                                         for k, v in options.items()]


def verify_ipa(ipa, version, build):
    with zipfile.ZipFile(ipa) as archive:
        plists = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
        if len(plists) != 1:
            raise ValueError('Expected exactly one application in exported IPA.')
        info = plistlib.loads(archive.read(plists[0]))
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (BUNDLE, version, build):
        raise ValueError('Exported IPA identity or version differs from the requested production release.')


def release(args):
    root = args.project_root.resolve()
    version, build, notes = read_release(root, args.notes.resolve())
    beta_notes = notes
    if getattr(args, 'testflight_notes', None):
        beta_notes = args.testflight_notes.read_text(encoding='utf-8-sig').strip()
        if not beta_notes or len(beta_notes) > 4000 or re.search(r'</?en-', beta_notes):
            raise ValueError('Supply plain TestFlight notes, 1-4000 characters, without language tags.')
    outside(args.api_key, root)
    key_data = json.loads(args.api_key.read_text())
    if not all(key_data.get(k) for k in ('key_id', 'issuer_id', 'key')):
        raise ValueError('Apple API key JSON is incomplete. Use --configure-key first.')
    if os.name != 'nt' and args.api_key.stat().st_mode & 0o077:
        raise ValueError('API key configuration is accessible to others. Run chmod 600 on it.')
    remote = subprocess.check_output(['git', 'remote', 'get-url', 'origin'], cwd=root, text=True).strip()
    if not re.search(r'[/ :]bowls_saas(?:\.git)?$', remote):
        raise ValueError('Run against the production bowls_saas checkout.')
    env = dict(os.environ, BUNDLE_GEMFILE=str(ROOT / 'scripts/ios/Gemfile'),
               BUNDLE_PATH=os.environ.get('BUNDLE_PATH', str(Path.home() / '.local/share/bowls/gems')),
               FASTLANE_SKIP_UPDATE_CHECK='1', FASTLANE_HIDE_CHANGELOG='1', CI='true')
    for executable in ('flutter', 'pod', 'xcodebuild', 'bundle', 'codesign'):
        if not shutil.which(executable):
            raise ValueError(f'{executable} not found. Complete the Mac setup first.')
    run(['bundle', 'check'], root, env=env)
    run(['xcodebuild', '-version'], root)
    print(f'Production iPhone {version} ({build}); notes:\n{notes}', flush=True)
    if args.validate_only:
        print('Local checks passed. No build, upload or Apple API requests made.')
        return
    if args.check_apple_access:
        run(fastlane_command('app_store_build_number', args.api_key.resolve(), live=True, platform='ios'), root, env=env)
        print('Apple API read access succeeded. No build, upload or review submission made.')
        return
    output = root / f'tmp/releases/ios/{version}-{build}'
    receipt_path = output / 'receipt.json'
    if receipt_path.exists():
        raise ValueError(f'A release attempt already exists: {receipt_path}. Inspect App Store Connect before retrying. No automatic re-upload.')
    output.mkdir(parents=True, exist_ok=False)
    receipt = dict(version=version, build=build, bundle=BUNDLE, team=TEAM,
                   commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                   working_changes=subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).splitlines(),
                   notes=notes, state='build_started')

    def save(state):
        receipt['state'] = state
        temporary = receipt_path.with_suffix('.new')
        temporary.write_text(json.dumps(receipt, indent=2) + '\n')
        temporary.replace(receipt_path)

    save('build_started')
    log = output / 'release.log'
    run(['flutter', 'pub', 'get'], root, log, env)
    run(['flutter', 'test', '--no-pub'], root, log, env)
    run(['pod', 'install'], root / 'ios', log, env)
    export = output / 'ExportOptions.plist'
    with export.open('wb') as stream:
        plistlib.dump(dict(method='app-store-connect', destination='export', signingStyle='automatic',
                           teamID=TEAM, manageAppVersionAndBuildNumber=False, uploadSymbols=True), stream)
    started = time.time()
    run(['flutter', 'build', 'ipa', '--release', '--no-pub', '--target=lib/main.dart',
         f'--build-name={version}', f'--build-number={build}', f'--export-options-plist={export}',
         '--dart-define=ACCOUNT_USERNAME_ENABLED=false', '--dart-define=PROFILE_PHOTOS_ENABLED=false',
         '--dart-define=QUICK_UNLOCK_ENABLED=false'], root, log, env)
    candidates = [p for p in (root / 'build/ios/ipa').glob('*.ipa') if p.stat().st_mtime >= started]
    if len(candidates) != 1:
        raise ValueError('Build did not produce exactly one fresh IPA. Nothing uploaded.')
    ipa = output / f'bowls-{version}-{build}.ipa'
    shutil.copy2(candidates[0], ipa)
    verify_ipa(ipa, version, build)
    # Verify the archive signature and team in addition to the exported IPA identity.
    app = root / 'build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app'
    run(['codesign', '--verify', '--deep', '--strict', str(app)], root, log, env)
    signature = subprocess.check_output(['codesign', '-dv', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
    if f'TeamIdentifier={TEAM}' not in signature:
        raise ValueError('Archive signing team differs from the production Apple team.')
    receipt['ipa'] = str(ipa)
    receipt['sha256'] = digest(ipa)
    save('built')
    save('upload_started')
    run(fastlane_command('upload_to_testflight', args.api_key.resolve(), ipa=ipa,
                         skip_waiting_for_build_processing=False, distribute_external=False,
                         notify_external_testers=False, submit_beta_review=False,
                         reject_build_waiting_for_review=False, expire_previous_builds=False,
                         wait_processing_timeout_duration=3600, changelog=beta_notes), output, log, env)
    save('uploaded_and_processed')
    metadata = output / 'metadata/en-GB'
    metadata.mkdir(parents=True, exist_ok=True)
    (metadata / 'release_notes.txt').write_text(notes, encoding='utf-8')
    save('store_update_started')
    run(fastlane_command('upload_to_app_store', args.api_key.resolve(),
                         app_version=version, build_number=build, platform='ios',
                         skip_binary_upload=True, skip_screenshots=True,
                         metadata_path=metadata.parent, force=True,
                         reject_if_possible=False, edit_live=False,
                         precheck_include_in_app_purchases=False,
                         submit_for_review=args.submit_for_review,
                         automatic_release=args.submit_for_review), output, log, env)
    save('submitted_for_review' if args.submit_for_review else 'store_draft_prepared')
    print(f"Complete: {receipt['state']}. Receipt: {receipt_path}")
    print('Apple controls processing, review and availability. No database changes made.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root', type=Path, default=ROOT)
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--testflight-notes', type=Path)
    parser.add_argument('--api-key', type=Path, default=KEY)
    parser.add_argument('--submit-for-review', action='store_true')
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--check-apple-access', action='store_true')
    parser.add_argument('--configure-key', type=Path)
    parser.add_argument('--key-id')
    parser.add_argument('--issuer-id')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('Run on the signing Mac. Windows cannot build/sign the iPhone app.')
    try:
        if args.configure_key:
            configure_key(args.project_root, args.configure_key, args.key_id, args.issuer_id, args.api_key)
        else:
            if not args.notes:
                parser.error('--notes is required for build/upload.')
            release(args)
    except (ValueError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f'STOPPED: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
