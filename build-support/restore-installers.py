"""Restore original release visibility following the author's final source-only scope."""
import os,json,urllib.request
REPO='alanpfx/MGControl-Public'
assert os.environ['GITHUB_REPOSITORY']==REPO and os.environ['GITHUB_ACTOR']=='alanpfx'
TOKEN=os.environ['GH_TOKEN'];BASE='https://api.github.com/repos/'+REPO
def api(path,obj=None):
    req=urllib.request.Request(BASE+path,data=None if obj is None else json.dumps(obj).encode(),method='GET' if obj is None else 'PATCH',headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json','Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=60) as response:return json.load(response)
tags={f'v0.{v}' for v in range(68,81)}|{'design-workbench-v0.1','design-workbench-v0.1.1'}
releases=api('/releases?per_page=100');results=[]
for release in releases:
    if release['tag_name'] not in tags:continue
    before={a['name']:(a['id'],a['size'],a.get('digest')) for a in release['assets']}
    if release['draft']:api('/releases/'+str(release['id']),{'draft':False,'make_latest':'false'})
    after=api('/releases/'+str(release['id']))
    assert after['draft'] is False
    assert before=={a['name']:(a['id'],a['size'],a.get('digest')) for a in after['assets']}
    results.append({'tag':release['tag_name'],'assetsUnchanged':True,'public':True})
    print('Restored original compiled installers:',release['tag_name'])
assert len(results)==15
from pathlib import Path
Path('privacy-output').mkdir(exist_ok=True)
Path('privacy-output/restored-releases.json').write_text(json.dumps(results,indent=2)+'\n')
