import unittest, tempfile, zipfile
from pathlib import Path
from public_boundary import check_source_paths, check_public_ipa

class PublicBoundaryTests(unittest.TestCase):
    def test_allow_release_support(self):
        check_source_paths(['README.md', 'COPYRIGHT.md', '.github/workflows/build-private-source.yml',
                            'build-support/ipa_permissions.py', 'docs/INSTALL.md', 'release-manifests/v0.80.json'])

    def test_reject_design_source_even_under_docs(self):
        for path in ['Shared/CarCard.swift', 'docs/design.ai', 'docs/icon.svg', 'docs/model.glb', 'MGControl/Assets.xcassets/icon.png']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                check_source_paths([path])

    def test_reject_model_folder_and_disguised_glb(self):
        for name, payload in [('Payload/MGControl.app/Vehicle3D/texture.png', b'PNG'),
                              ('Payload/MGControl.app/cache.dat', b'glTF' + bytes(20))]:
            with tempfile.TemporaryDirectory() as tmp:
                ipa = Path(tmp) / 'sample.ipa'
                with zipfile.ZipFile(ipa, 'w') as z:
                    z.writestr(name, payload)
                with self.assertRaises(ValueError):
                    check_public_ipa(ipa)

    def test_allow_compiled_application(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = Path(tmp) / 'sample.ipa'
            with zipfile.ZipFile(ipa, 'w') as z:
                z.writestr('Payload/MGControl.app/MGControl', b'\xcf\xfa\xed\xfe')
                z.writestr('Payload/MGControl.app/Assets.car', b'compiled assets')
            check_public_ipa(ipa)

if __name__ == '__main__':
    unittest.main()
