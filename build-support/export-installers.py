from pathlib import Path
import sys,zipfile,plistlib,hashlib,shutil,re
source=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
checks=[]
for variant in ('widget','app-only'):
 candidates=list((source/'build').glob(f'*-{variant}-unsigned.ipa'))
 if len(candidates)!=1:raise RuntimeError('Expected one installer for each variant')
 p=candidates[0]
 with zipfile.ZipFile(p) as z:
  if z.testzip() is not None:raise RuntimeError('Corrupt installer')
  for name in z.namelist():
   if Path(name).suffix.lower() in {'.swift','.h','.m','.mm','.c','.cpp','.har','.chlz','.pem','.key'}:raise RuntimeError('Excluded source or credential file in installer')
   if not name.startswith('Payload/'):raise RuntimeError('Unexpected installer root')
  info=plistlib.loads(z.read('Payload/MGControl.app/Info.plist'))
  if info['CFBundleShortVersionString']!='0.57' or info['CFBundleVersion']!='41':raise RuntimeError('Unexpected application version')
  if info['MinimumOSVersion']!='15.0':raise RuntimeError('Unexpected minimum OS')
  if 'Payload/MGControl.app/embedded.mobileprovision' in z.namelist():raise RuntimeError('Expected unsigned installer')
 name=f'MGControl-V0.57-{variant}-unsigned.ipa'
 shutil.copyfile(p,out/name)
 checks.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+name)
(out/'SHA256SUMS.txt').write_text('\n'.join(checks)+'\n',encoding='utf8')
print('Exported only two verified installers and checksums.')
