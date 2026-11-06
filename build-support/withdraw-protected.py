"""Withdraw explicitly scoped legacy model releases; never delete release assets.

User authorized keeping the repository public and withdrawing old resources on 2026-11-06.
Releases become recoverable drafts. Only public Actions artifacts containing model
resources or synthetic design previews are deleted; encrypted diagnostics are untouched.
"""
import io, json, os, re, urllib.request, urllib.error, zipfile
from pathlib import Path
from public_boundary import forbidden_resource

REPO = 'alanpfx/MGControl-Public'
BASE = 'https://api.github.com/repos/' + REPO
SCOPED_TAGS = {f'v0.{v}' for v in range(68, 81)} | {'design-workbench-v0.1', 'design-workbench-v0.1.1'}
TOKEN = os.environ['GH_TOKEN']
assert os.environ['GITHUB_REPOSITORY'] == REPO
assert os.environ['GITHUB_ACTOR'] == 'alanpfx'
report = {'policyDate':'2026-11-06', 'releases':[], 'artifacts':[], 'historyRewritten':False,
          'releaseAssetsDeleted':False, 'externalCopiesRecalled':False}
out = Path('privacy-output'); out.mkdir(exist_ok=True)

def save():
    (out/'withdrawal-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf8')

def request(path, method='GET', obj=None):
    url = path if path.startswith('https://') else BASE + path
    data = None if obj is None else json.dumps(obj).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={'Authorization':'Bearer '+TOKEN,
        'Accept':'application/vnd.github+json', 'Content-Type':'application/json', 'User-Agent':'MGControl-resource-withdrawal'})
    with urllib.request.urlopen(req, timeout=120) as response:
        if response.status == 204:
            return None
        return json.load(response)

def pages(path, key=None):
    result=[]
    for page in range(1, 31):
        data=request(f'{path}?per_page=100&page={page}')
        items=data[key] if key else data
        result.extend(items)
        if len(items)<100:
            return result
    raise RuntimeError('Pagination bound exceeded')

for release in pages('/releases'):
    if release['tag_name'] not in SCOPED_TAGS:
        continue
    assert not release.get('immutable', False), 'Immutable release requires owner intervention'
    before={'id':release['id'], 'tag':release['tag_name'], 'draftBefore':release['draft'],
            'assets':[{'id':a['id'], 'name':a['name'], 'size':a['size'], 'digest':a.get('digest')} for a in release['assets']]}
    report['releases'].append(before); save()
    if not release['draft']:
        request('/releases/'+str(release['id']), 'PATCH', {'draft':True, 'make_latest':'false'})
    assert request('/releases/'+str(release['id']))['draft'] is True
    before['verifiedDraft']=True; save()
    print('Withdrew release as recoverable draft:', release['tag_name'])

for artifact in pages('/actions/artifacts', 'artifacts'):
    if artifact['expired'] or not (artifact['name'].startswith('MGControl-') or artifact['name'].startswith('MGDesignWorkbench')):
        continue
    name=artifact['name']
    if 'encrypted' in name or 'diagnostic' in name or name.startswith('MGControl-privacy-withdrawal'):
        continue
    assert 0 < artifact['size_in_bytes'] <= 160*1024*1024, 'Artifact download bound exceeded'
    req=urllib.request.Request(artifact['archive_download_url'], headers={'Authorization':'Bearer '+TOKEN, 'User-Agent':'MGControl-resource-withdrawal'})
    with urllib.request.urlopen(req, timeout=120) as response:
        payload=response.read(160*1024*1024+1)
    assert len(payload)<=160*1024*1024
    protected='widget-previews' in name or 'DesignWorkbench' in name
    with zipfile.ZipFile(io.BytesIO(payload)) as outer:
        for entry in outer.infolist():
            if entry.filename.lower().endswith('.ipa'):
                with zipfile.ZipFile(io.BytesIO(outer.read(entry))) as ipa:
                    protected |= any(forbidden_resource(p) for p in ipa.namelist())
    if not protected:
        continue
    record={'id':artifact['id'], 'name':name, 'runId':artifact.get('workflow_run',{}).get('id'), 'protectedPayloadConfirmed':True}
    report['artifacts'].append(record); save()
    request('/actions/artifacts/'+str(artifact['id']), 'DELETE')
    record['deleted']=True; save()
    print('Removed protected public build artifact:', name, artifact['id'])
save()
print('Withdrawal finished; repository and historical Git refs remain unchanged.')
