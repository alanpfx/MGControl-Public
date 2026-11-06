"""Protect public SOURCE scope; compiled installers retain approved runtime models."""
from pathlib import Path, PurePosixPath
import subprocess, sys, zipfile

MODEL_EXTENSIONS = {'.glb', '.gltf', '.blend', '.fbx', '.obj', '.mtl', '.usdz', '.usd', '.usdc', '.usda', '.stl'}
EDITABLE_EXTENSIONS = {'.ai', '.svg', '.eps', '.psd', '.sketch', '.fig', '.swift', '.xib', '.storyboard'}
INSTALLER_SOURCE_EXTENSIONS = {'.swift', '.ai', '.blend', '.psd', '.sketch', '.fig', '.h', '.m', '.mm', '.c', '.cpp', '.har', '.chlz', '.pem', '.key'}
ROOT_FILES = {'.gitignore', 'README.md', 'LICENSE', 'COPYRIGHT.md', 'BUILDING-PRIVATE-SOURCE.md',
              'CHANGELOG.md', 'RELEASE-NOTES.md', 'SOURCE-MANIFEST.json', 'PUBLIC-DISTRIBUTION.json'}
ALLOWED_ROOTS = {'docs', 'build-support', 'release-manifests', '.github'}

def forbidden_resource(name):
    path = PurePosixPath(name.replace('\\', '/'))
    lower = name.lower().replace('\\', '/')
    return (path.suffix.lower() in MODEL_EXTENSIONS | EDITABLE_EXTENSIONS
            or any(part in {'vehicle3d', 'design-workbench', 'designer-assets'} for part in lower.split('/')))

def check_source_paths(paths):
    for name in paths:
        path = PurePosixPath(name)
        if forbidden_resource(name) or '..' in path.parts or (name not in ROOT_FILES and path.parts[0] not in ALLOWED_ROOTS):
            raise ValueError('Protected or unreviewed public source path: ' + name)

def check_public_ipa(path):
    with zipfile.ZipFile(path) as z:
        if len(z.namelist()) != len(set(z.namelist())):
            raise ValueError('Duplicate installer entries')
        for entry in z.infolist():
            name = entry.filename
            if PurePosixPath(name).suffix.lower() in INSTALLER_SOURCE_EXTENSIONS:
                raise ValueError('Source or authoring original in public installer: ' + name)
            # The author explicitly permits compiled runtime models in public IPAs.

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--ipa':
        check_public_ipa(Path(sys.argv[2]))
    else:
        root = Path(__file__).resolve().parents[1]
        files = subprocess.check_output(['git', '-c', 'safe.directory='+root.as_posix(), '-C', str(root), 'ls-files', '-z']).decode().split('\0')
        check_source_paths([p for p in files if p])
    print('Public boundary verified.')
