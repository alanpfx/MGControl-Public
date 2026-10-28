"""macOS-only ad-hoc entitlement preparation for TrollStore, no certificates."""
from pathlib import Path
import os,sys,json,zipfile,plistlib,hashlib,struct,subprocess,tempfile,urllib.request,urllib.parse
from ipa_permissions import normalized
GROUP='group.aa470567aa802a25.1'
REPO='alanpfx/MGControl-Public';BASE='https://api.github.com/repos/'+REPO
TOKEN=os.environ['GH_TOKEN'];VERSION=os.environ.get('APP_VERSION','0.61')
def api(path,data=None,method='GET'):
 req=urllib.request.Request(BASE+path,data=None if data is None else json.dumps(data).encode(),method=method,headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json','Content-Type':'application/json','User-Agent':'MGControl-groups-preparation'})
 with urllib.request.urlopen(req,timeout=90) as r:return json.load(r)
def sections(data):
 assert data[:4]==b'\xcf\xfa\xed\xfe'
 result={};offset=32
 for _ in range(struct.unpack_from('<I',data,16)[0]):
  cmd,size=struct.unpack_from('<II',data,offset)
  if cmd==0x19:
   for i in range(struct.unpack_from('<I',data,offset+64)[0]):
    start=offset+72+80*i;name=data[start:start+32].hex();length=struct.unpack_from('<Q',data,start+40)[0];fileoff=struct.unpack_from('<I',data,start+48)[0]
    if fileoff and length:
     assert fileoff+length<=len(data);result[name]=hashlib.sha256(data[fileoff:fileoff+length]).hexdigest()
  offset+=size
 return result
release=api('/releases/tags/v'+VERSION)
name=f'MGControl-V{VERSION}-widget-ready-unsigned.ipa'
asset=next(a for a in release['assets'] if a['name']==name)
with urllib.request.urlopen(asset['browser_download_url'],timeout=120) as r:source=r.read(32*1024*1024)
assert 'sha256:'+hashlib.sha256(source).hexdigest()==asset['digest']
out=Path('appgroups-output');out.mkdir(exist_ok=True)
sourcepath=out/'input.ipa';sourcepath.write_bytes(source)
proof={'version':VERSION,'source_sha256':hashlib.sha256(source).hexdigest(),'group':GROUP,'scope':'TrollStore only; no runtime container verification','bundles':[]}
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp)
 with zipfile.ZipFile(sourcepath) as z:
  assert z.testzip() is None and len(z.namelist())==len(set(z.namelist()))
  original={e.filename:z.read(e) for e in z.infolist()}
  for entry in z.infolist():
   data=z.read(entry);item=normalized(entry,data);target=root/item.filename
   if item.is_dir():target.mkdir(parents=True,exist_ok=True)
   else:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
   os.chmod(target,(item.external_attr>>16)&0o777)
 app=root/'Payload/MGControl.app'
 bundles=list(app.glob('PlugIns/*.appex'))+[app]
 assert len(bundles)==2
 executables=set()
 for bundle in bundles:
  info=plistlib.loads((bundle/'Info.plist').read_bytes())
  assert info['MGControlAppGroupIdentifier']==GROUP and info['MinimumOSVersion']=='15.0' and info['CFBundleShortVersionString']==VERSION
  bid=info['CFBundleIdentifier'];assert bid in ['com.alanpfx.MGControl','com.alanpfx.MGControl.Widget']
  binary=bundle/info['CFBundleExecutable'];executables.add(binary.relative_to(root).as_posix());before=sections(binary.read_bytes())
  ent={'application-identifier':'TROLLTROLL.*' if bundle==app else 'TROLLTROLL.'+bid,'com.apple.developer.team-identifier':'TROLLTROLL','com.apple.security.application-groups':[GROUP]}
  if bundle==app:ent['keychain-access-groups']=['TROLLTROLL.*']
  path=root/(bid+'.entitlements');path.write_bytes(plistlib.dumps(ent))
  subprocess.run(['codesign','--force','--sign','-','--identifier',bid,'--entitlements',str(path),'--generate-entitlement-der','--timestamp=none',str(bundle)],check=True)
  result=subprocess.run(['codesign','--display','--entitlements',':-',str(binary)],check=True,capture_output=True)
  decoded=plistlib.loads(result.stdout);assert decoded==ent
  assert sections(binary.read_bytes())==before,'Executable sections must remain unchanged'
  subprocess.run(['codesign','--verify','--strict',str(bundle)],check=True)
  proof['bundles'].append({'bundle':bid,'entitlements':ent,'executable_sections_unchanged':True})
 dest=out/f'MGControl-V{VERSION}-widget-trollstore-appgroups.ipa'
 with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
  for p in sorted((root/'Payload').rglob('*')):
   if p.is_file():
    rel=p.relative_to(root).as_posix()
    if rel in original and rel not in executables and '/_CodeSignature/' not in rel:assert p.read_bytes()==original[rel]
  for p in [root/'Payload']+sorted((root/'Payload').rglob('*')):
   rel=p.relative_to(root).as_posix()+('/' if p.is_dir() else '')
   data=b'' if p.is_dir() else p.read_bytes();entry=zipfile.ZipInfo(rel,date_time=(2026,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED
   z.writestr(normalized(entry,data),data)
 with zipfile.ZipFile(dest) as z:
  assert z.testzip() is None
  assert all(e.external_attr==normalized(e,z.read(e)).external_attr for e in z.infolist())
sourcepath.unlink()
proof['sha256']=hashlib.sha256(dest.read_bytes()).hexdigest()
manifest=out/'TrollStore-AppGroups-verification.json';manifest.write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
checksum=out/'SHA256SUMS-trollstore-appgroups.txt';checksum.write_text(proof['sha256']+'  '+dest.name+'\n',encoding='utf8')
for path in [dest,manifest,checksum]:
 data=path.read_bytes();digest='sha256:'+hashlib.sha256(data).hexdigest();old=next((a for a in release['assets'] if a['name']==path.name),None)
 if old:assert old.get('digest')==digest;continue
 url=release['upload_url'].split('{')[0]+'?name='+urllib.parse.quote(path.name)
 req=urllib.request.Request(url,data=data,method='POST',headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/octet-stream','Accept':'application/vnd.github+json'})
 with urllib.request.urlopen(req,timeout=120) as r:uploaded=json.load(r)
 assert uploaded['digest']==digest
marker='### TrollStore App Groups 适配包'
if marker not in release['body']:
 body=release['body']+'\n\n'+marker+'\n\n新增 `widget-trollstore-appgroups.ipa`，预置主App/扩展相同的App Groups权限及巨魔默认身份兼容配置，供巨魔用户覆盖安装测试。普通签名仍用原widget-ready包。程序段及原资源已核对不变，版本仍为'+VERSION+'。不必卸载或重新领取钥匙。安装后打开主App同步车况，再重新添加小组件；实际容器共享仍待真机验证。\n'
 api('/releases/'+str(release['id']),{'body':body},'PATCH')
print('Prepared and published scoped TrollStore App Groups installer; runtime verification pending.')

