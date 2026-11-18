"""Exercise the real exporter contract: future builds produce no app-only package."""
from pathlib import Path
import json,os,plistlib,subprocess,sys,tempfile,unittest,zipfile

class InstallerVariantTests(unittest.TestCase):
    def test_new_export_is_widget_only_with_a_versioned_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';build=source/'build';build.mkdir(parents=True);out=root/'output'
            (source/'version.json').write_text(json.dumps({'marketingVersion':'1.23','buildNumber':123}))
            for variant in ['widget','app-only']:
                with zipfile.ZipFile(build/f'MGControl-V1.23-{variant}-unsigned.ipa','w') as z:
                    z.writestr('Payload/MGControl.app/Info.plist',plistlib.dumps({'CFBundleShortVersionString':'1.23','CFBundleVersion':'123','MinimumOSVersion':'15.0','CFBundleExecutable':'MGControl'}))
                    z.writestr('Payload/MGControl.app/MGControl',b'fixture-only-not-an-executable')
            env=dict(os.environ,EXPECTED_APP_VERSION='1.23',EXPECTED_APP_BUILD='123')
            subprocess.run([sys.executable,str(Path(__file__).with_name('export-installers.py')),str(source),str(out)],env=env,check=True,capture_output=True)
            self.assertEqual([p.name for p in out.glob('*.ipa')],['MGControl-V1.23-widget-unsigned.ipa'])
            self.assertEqual(json.loads((out/'installer-variants.json').read_text()),{'version':'1.23','build':'123','variants':['widget']})
            self.assertEqual(len((out/'SHA256SUMS.txt').read_text().splitlines()),1)
    def test_version_mismatch_does_not_export_an_installer(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';source.mkdir();(source/'version.json').write_text(json.dumps({'marketingVersion':'1.23','buildNumber':123}))
            p=subprocess.run([sys.executable,str(Path(__file__).with_name('export-installers.py')),str(source),str(root/'out')],env=dict(os.environ,EXPECTED_APP_VERSION='1.24',EXPECTED_APP_BUILD='124'),capture_output=True)
            self.assertNotEqual(p.returncode,0);self.assertEqual(list((root/'out').glob('*.ipa')),[])
