"""Publish verified public-run installers without exposing private source or logs."""
from pathlib import Path
import os,json,urllib.request,urllib.error,urllib.parse,hashlib,zipfile,io,re,base64,sys

REPO='alanpfx/MGControl-Public'
BASE='https://api.github.com/repos/'+REPO
TOKEN=os.environ['GH_TOKEN']
RUN=int(os.environ['BUILD_RUN_ID'])
ROOT=Path(__file__).resolve().parents[1]
RAW=Path(os.environ.get('INSTALLER_DIRECTORY','compiled'))
OUT=Path('release-output');OUT.mkdir(exist_ok=True)

def api(path,method='GET',obj=None):
 data=None if obj is None else json.dumps(obj,ensure_ascii=False).encode()
 req=urllib.request.Request(BASE+path,data=data,method=method,headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'})
 try:
  with urllib.request.urlopen(req,timeout=60) as r:return json.load(r)
 except urllib.error.HTTPError as e:
  raise RuntimeError('GitHub request failed: HTTP '+str(e.code)) from None

run=api('/actions/runs/'+str(RUN))
assert run['conclusion']=='success' and run['head_branch']=='main'
assert run['path']=='.github/workflows/build-private-source.yml'
assert run['actor']['login']=='alanpfx' and run['head_repository']['full_name']==REPO
assert run['event'] in {'push','workflow_dispatch'}

files=list(RAW.glob('*.ipa'));assert len(files)==2
sums={line.split()[1]:line.split()[0] for line in (RAW/'SHA256SUMS.txt').read_text().splitlines()}
version=build=None
for p in files:
 assert hashlib.sha256(p.read_bytes()).hexdigest()==sums[p.name]
 with zipfile.ZipFile(p) as z:
  import plistlib
  assert z.testzip() is None
  for n in z.namelist():
   assert n.startswith('Payload/') and Path(n).suffix.lower() not in {'.swift','.har','.chlz','.pem','.key','.c','.h','.m','.mm','.cpp'}
  meta=plistlib.loads(z.read('Payload/MGControl.app/Info.plist'))
  v=str(meta['CFBundleShortVersionString']);b=str(meta['CFBundleVersion'])
  assert re.fullmatch(r'\d+\.\d+(?:\.\d+)?',v) and b.isdecimal()
  if version is None:version,build=v,b
  assert (version,build)==(v,b) and meta['MinimumOSVersion']=='15.0'
  assert not any(n.endswith('/embedded.mobileprovision') or '/_CodeSignature/' in n for n in z.namelist())
notes=(ROOT/'RELEASE-NOTES.md').read_text(encoding='utf8')
assert re.match(r'# MGControl '+re.escape(version)+r'（'+re.escape(build)+r'）',notes),'Prepare matching public release notes before building'
changelog=(ROOT/'CHANGELOG.md').read_text(encoding='utf8')
assert f'## {version}（{build}）' in changelog,'Prepare matching changelog before building'

# Bootstrap contains application parameters already distributed in public 0.54,
# never a personal login session, VIN, safety PIN or digital-key material.
bootstrap_url='https://github.com/'+REPO+'/releases/download/v0.54/MGControl-V0.54-app-only-ready-unsigned.ipa'
with urllib.request.urlopen(urllib.request.Request(bootstrap_url,headers={'User-Agent':'MGControl-release'}),timeout=60) as r:old=r.read(16*1024*1024)
assert hashlib.sha256(old).hexdigest()=='89e6ca0c5905d44cdbea06715196a7c9b82f54e439a02596ee93f2155c11448d'
resource='Payload/MGControl.app/MGControl-Login-Configuration.json'
with zipfile.ZipFile(io.BytesIO(old)) as z:configuration=z.read(resource)
c=json.loads(configuration);assert set(c)=={'accountSigningKey','vehicleSigningKey','captchaID'}
assert all(isinstance(v,str) and 1<=len(v)<=1024 for v in c.values())

assets=[]
for variant in ('widget','app-only'):
 p=next(p for p in files if p.name.endswith('-'+variant+'-unsigned.ipa'))
 name=f'MGControl-V{version}-{variant}-ready-unsigned.ipa';dest=OUT/name
 with zipfile.ZipFile(p) as src,zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as dst:
  for entry in src.infolist():
   if entry.filename!=resource:dst.writestr(entry,src.read(entry))
  item=zipfile.ZipInfo(resource,date_time=(2026,1,1,0,0,0));item.compress_type=zipfile.ZIP_DEFLATED;dst.writestr(item,configuration)
 with zipfile.ZipFile(dest) as z:
  assert z.testzip() is None and z.read(resource)==configuration
  with zipfile.ZipFile(p) as original:
   assert all(z.read(n)==original.read(n) for n in original.namelist() if n!=resource)
 assets.append((name,dest.read_bytes()))
checks=''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name,data in assets)
assets += [('SHA256SUMS.txt',checks.encode()),('LICENSE.txt',(ROOT/'LICENSE').read_bytes())]

tag='v'+version
existing=None
try:
 req=urllib.request.Request(BASE+'/releases/tags/'+tag,headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json'})
 with urllib.request.urlopen(req,timeout=30) as r:existing=json.load(r)
except urllib.error.HTTPError as e:
 if e.code!=404:raise RuntimeError('Cannot check existing release') from None
if existing is not None and not existing['draft']:
 expected={name:'sha256:'+hashlib.sha256(data).hexdigest() for name,data in assets}
 actual={x['name']:x.get('digest') for x in existing['assets']}
 assert actual==expected,'Published version differs; bump version rather than replacing installers'
 print('Release already published with identical verified files: '+existing['html_url']);sys.exit(0)

head=api('/git/ref/heads/main')['object']['sha']
release=existing or api('/releases','POST',{'tag_name':tag,'target_commitish':head,'name':f'MGControl {version}（{build}）测试版','body':notes,'draft':True,'prerelease':True,'generate_release_notes':False})
for name,data in assets:
 expected='sha256:'+hashlib.sha256(data).hexdigest()
 previous=next((a for a in release['assets'] if a['name']==name),None)
 if previous:
  assert previous.get('digest')==expected and previous['size']==len(data),'Draft file differs; do not overwrite'
  continue
 url=release['upload_url'].split('{',1)[0]+'?name='+urllib.parse.quote(name)
 req=urllib.request.Request(url,data=data,method='POST',headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/octet-stream','Accept':'application/vnd.github+json'})
 with urllib.request.urlopen(req,timeout=120) as r:uploaded=json.load(r)
 assert uploaded['size']==len(data) and uploaded.get('digest')==expected
release=api('/releases/'+str(release['id']),'PATCH',{'draft':False,'prerelease':True,'make_latest':'false','body':notes})

# Document the exact successful run and installer digests in the public changelog.
# The curated version log and README are already required above; this records publication.
proof={'version':version,'build':build,'build_run':run['html_url'],'release':release['html_url'],'assets':[{'name':name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)} for name,data in assets]}
proof_path=f'release-manifests/{tag}.json'
current=None
try:
 req=urllib.request.Request(BASE+'/contents/'+proof_path,headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json'})
 with urllib.request.urlopen(req,timeout=30) as r:current=json.load(r)
except urllib.error.HTTPError as e:
 if e.code!=404:raise
payload={'message':f'Record published installers for {tag}','content':base64.b64encode((json.dumps(proof,ensure_ascii=False,indent=2)+'\n').encode()).decode(),'branch':'main'}
if current:payload['sha']=current['sha']
api('/contents/'+proof_path,'PUT',payload)
print('Published '+release['html_url']+' with two verified installers, checksums and noncommercial license.')
