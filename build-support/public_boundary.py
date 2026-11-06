"""Fail closed before public upload: no UI source, design originals or 3D resources."""
from pathlib import Path, PurePosixPath
import subprocess, sys, zipfile

MODEL_EXTENSIONS = {'.glb', '.gltf', '.blend', '.fbx', '.obj', '.mtl', '.usdz', '.usd', '.usdc', '.usda', '.stl'}
EDITABLE_EXTENSIONS = {'.ai', '.svg', '.eps', '.psd', '.sketch', '.fig', '.swift', '.xib', '.storyboard'}
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
            if forbidden_resource(name):
                raise ValueError('Protected resource in public installer: ' + name)
            # Renaming the GLB must not bypass the filename rule.
            if not entry.is_dir():
                with z.open(entry) as stream:
                    if stream.read(4) == b'glTF':
                        raise ValueError('GLB payload in public installer: ' + name)

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--ipa':
        check_public_ipa(Path(sys.argv[2]))
    else:
        root = Path(__file__).resolve().parents[1]
        files = subprocess.check_output(['git', '-c', 'safe.directory='+root.as_posix(), '-C', str(root), 'ls-files', '-z']).decode().split('\0')
        check_source_paths([p for p in files if p])
    print('Public boundary verified.')
