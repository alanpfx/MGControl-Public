from pathlib import Path
import sys,zipfile,hashlib,plistlib,stat
sys.path.insert(0,str(Path('build-support').resolve()))
from ipa_permissions import normalize_ipa,normalized
app=Path('design-build/Build/Products/Release-iphoneos/MGDesignWorkbench.app')
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['MinimumOSVersion']=='15.0' and info['CFBundleShortVersionString']=='0.1' and info['CFBundleVersion']=='1'
assert info['CFBundleIdentifier']=='com.alanpfx.MGControl.DesignWorkbench'
out=Path('design-output');out.mkdir(exist_ok=True)
raw=out/'raw.zip'
with zipfile.ZipFile(raw,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(app.rglob('*')):
  if p.is_file():
   assert not p.is_symlink()
   z.write(p,'Payload/MGDesignWorkbench.app/'+p.relative_to(app).as_posix())
target=out/'MGDesignWorkbench-V0.1-ready-unsigned.ipa'
normalize_ipa(raw,target);raw.unlink()
with zipfile.ZipFile(target) as z:
 for entry in z.infolist():assert entry.external_attr==normalized(entry,z.read(entry)).external_attr
digest=hashlib.sha256(target.read_bytes()).hexdigest()
(out/'SHA256SUMS.txt').write_text(digest+'  '+target.name+'\n',encoding='utf8')
print('Verified standalone iOS15 installer with normalized permissions: '+digest)
