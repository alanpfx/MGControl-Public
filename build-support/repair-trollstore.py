from pathlib import Path
import os,json,urllib.request,hashlib,zipfile,stat
from ipa_permissions import normalize_ipa
repo='alanpfx/MGControl-Public'
base='https://api.github.com/repos/'+repo
token=os.environ['GH_TOKEN']
def api(url,data=None,method='GET',kind='application/json'):
 req=urllib.request.Request(url,data=data,method=method,headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','Content-Type':kind,'User-Agent':'MGControl-permissions-fix'})
 with urllib.request.urlopen(req,timeout=120) as r:return json.load(r)
release=api(base+'/releases/tags/v0.60')
out=Path('ts-output');out.mkdir(exist_ok=True)
assets=[]
for variant,digest in [('widget','74c5e6af3bd80b4b093095d458f7baf13d59ae95db527a05075dd9ffd301e209'),('app-only','5097fefc6a496f83c59ea31643245113577e5c1a1479a398960c8a489babe6ef')]:
 name=f'MGControl-V0.60-{variant}-ready-unsigned.ipa'
 a=next(a for a in release['assets'] if a['name']==name)
 with urllib.request.urlopen(a['browser_download_url'],timeout=120) as r:data=r.read(32*1024*1024)
 assert hashlib.sha256(data).hexdigest()==digest
 source=out/name;source.write_bytes(data)
 target=out/name.replace('-ready-unsigned','-trollstore-ready-unsigned')
 normalize_ipa(source,target);source.unlink()
 assets.append(target)
checks=out/'SHA256SUMS-trollstore.txt'
checks.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in assets),encoding='utf8')
assets.append(checks)
for p in assets:
 data=p.read_bytes();digest='sha256:'+hashlib.sha256(data).hexdigest()
 previous=next((a for a in release['assets'] if a['name']==p.name),None)
 if previous:assert previous.get('digest')==digest;continue
 uploaded=api(release['upload_url'].split('{')[0]+'?name='+p.name,data,'POST','application/octet-stream')
 assert uploaded['digest']==digest
body=release['body']
marker='### TrollStore 权限修复包'
if marker not in body:
 body+='\n\n'+marker+'\n\n新增名称包含 `trollstore` 的两种IPA及独立校验文件。仅规范ZIP条目权限，所有包内文件内容与原0.60完全一致，版本仍为0.60（44）。后续安装优先下载修复包；不必卸载或重新领取钥匙。仍报181时请反馈修复包文件名、TrollStore版本和完整安装日志。\n'
 api(base+'/releases/'+str(release['id']),json.dumps({'body':body}).encode(),'PATCH')
print('Verified permissions, unchanged entry contents, and uploaded both TrollStore installers.')
