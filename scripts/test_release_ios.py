"""Offline tests. No Xcode, signing credentials, Apple requests or real builds."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import release_ios as ios


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'bowls_saas'
        (self.root / 'ios/Runner.xcodeproj').mkdir(parents=True)
        (self.root / 'lib').mkdir()
        (self.root / 'lib/main.dart').write_text('production')
        (self.root / 'pubspec.yaml').write_text('version: 1.6.9+35\n')
        (self.root / 'ios/Runner.xcodeproj/project.pbxproj').write_text(
            f'PRODUCT_BUNDLE_IDENTIFIER = {ios.BUNDLE};\nDEVELOPMENT_TEAM = {ios.TEAM};')
        self.notes = self.base / 'notes.txt'
        self.notes.write_text('Booking improvements.', encoding='utf-8')
        self.key = self.base / 'api.json'
        self.key.write_text(json.dumps(dict(key_id='TEST', issuer_id='TEST', key='FAKE')))
        self.key.chmod(0o600)
        self.args = argparse.Namespace(project_root=self.root, notes=self.notes, api_key=self.key,
                                       validate_only=False, submit_for_review=False, check_apple_access=False)
        self.commands = []
        self.fail = None

    def ipa(self, path, version='1.6.9', bundle=ios.BUNDLE):
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(dict(
                CFBundleIdentifier=bundle, CFBundleShortVersionString=version, CFBundleVersion='35')))

    def runner(self, command, root, log=None, env=None):
        self.commands.append(command)
        if self.fail and self.fail in command:
            raise RuntimeError('Simulated step failure')
        if command[:3] == ['flutter', 'build', 'ipa']:
            self.ipa(self.root / 'build/ios/ipa/release.ipa')

    def output(self, command, **kwargs):
        if command[:3] == ['git', 'remote', 'get-url']:
            return 'https://github.com/totalleisure/bowls_saas.git\n'
        if command[0] == 'codesign':
            return f'TeamIdentifier={ios.TEAM}\n'
        return '' if '--porcelain' in command else 'commit123\n'

    def execute(self):
        with patch.object(ios, 'run', side_effect=self.runner), \
                patch.object(ios.shutil, 'which', return_value='/fake/tool'), \
                patch.object(ios.subprocess, 'check_output', side_effect=self.output), \
                contextlib.redirect_stdout(io.StringIO()):
            ios.release(self.args)

    def test_draft_full_workflow_and_retry_block(self):
        self.execute()
        actions = [c for c in self.commands if c[:3] == ['bundle', 'exec', 'fastlane']]
        self.assertEqual(len(actions), 2)
        self.assertIn('submit_for_review:false', actions[-1])
        self.assertIn('build_number:35', actions[-1])
        self.assertIn('reject_if_possible:false', actions[-1])
        self.assertIn('skip_binary_upload:true', actions[-1])
        receipt = json.loads((self.root / 'tmp/releases/ios/1.6.9-35/receipt.json').read_text())
        self.assertEqual(receipt['state'], 'store_draft_prepared')
        self.assertNotIn('FAKE', json.dumps(receipt))
        before = len(actions)
        with self.assertRaises(ValueError):
            self.execute()
        self.assertEqual(len([c for c in self.commands if c[:3] == ['bundle', 'exec', 'fastlane']]), before)

    def test_submit_full_workflow(self):
        self.args.submit_for_review = True
        self.execute()
        self.assertIn('submit_for_review:true', self.commands[-1])
        self.assertIn('automatic_release:true', self.commands[-1])

    def test_validate_never_builds_or_uploads(self):
        self.args.validate_only = True
        self.execute()
        self.assertEqual(self.commands, [['bundle', 'check'], ['xcodebuild', '-version']])

    def test_apple_access_check_only_reads(self):
        self.args.check_apple_access = True
        self.execute()
        self.assertIn('app_store_build_number', self.commands[-1])
        self.assertIn('live:true', self.commands[-1])
        self.assertFalse((self.root / 'tmp/releases/ios/1.6.9-35/receipt.json').exists())

    def test_tests_fail_before_build_or_upload(self):
        self.fail = 'test'
        with self.assertRaises(RuntimeError):
            self.execute()
        self.assertFalse(any('fastlane' in c or 'ipa' in c for c in self.commands))

    def test_upload_failure_never_submits(self):
        self.fail = 'upload_to_testflight'
        with self.assertRaises(RuntimeError):
            self.execute()
        self.assertFalse(any('upload_to_app_store' in c for c in self.commands))
        receipt = json.loads((self.root / 'tmp/releases/ios/1.6.9-35/receipt.json').read_text())
        self.assertEqual(receipt['state'], 'upload_started')

    def test_wrong_ipa_identity(self):
        ipa = self.base / 'wrong.ipa'
        self.ipa(ipa, bundle='staging.app')
        with self.assertRaises(ValueError):
            ios.verify_ipa(ipa, '1.6.9', '35')

    def test_wrong_version(self):
        ipa = self.base / 'old.ipa'
        self.ipa(ipa, version='1.6.8')
        with self.assertRaises(ValueError):
            ios.verify_ipa(ipa, '1.6.9', '35')

    def test_bad_notes(self):
        self.notes.write_text('x' * 4001)
        with self.assertRaises(ValueError):
            ios.read_release(self.root, self.notes)

    def test_credentials_inside_repo_rejected(self):
        with self.assertRaises(ValueError):
            ios.outside(self.root / 'secret.p8', self.root)

    def test_key_setup_exclusive_and_private(self):
        p8 = self.base / 'test.p8'
        p8.write_text('-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n')
        destination = self.base / 'private/key.json'
        with contextlib.redirect_stdout(io.StringIO()):
            ios.configure_key(self.root, p8, 'TEST', 'ISSUER', destination)
        self.assertEqual(json.loads(destination.read_text())['key_id'], 'TEST')
        with self.assertRaises(FileExistsError):
            ios.configure_key(self.root, p8, 'TEST', 'ISSUER', destination)


if __name__ == '__main__':
    unittest.main()
