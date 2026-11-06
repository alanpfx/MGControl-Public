"""Remove protected source from main/tag history with an atomic lease-guarded push.

Explicitly authorized by the repository owner on 2026-11-06. Original refs and
protected files were backed up locally before this workflow. This does not erase
GitHub cached SHA/PR views or external forks/copies.
"""
from pathlib import Path
import subprocess,os,base64,json,tempfile
from public_boundary import check_source_paths

REPO='alanpfx/MGControl-Public'
assert os.environ['GITHUB_REPOSITORY']==REPO and os.environ['GITHUB_ACTOR']=='alanpfx'
ROOT=Path.cwd();EXPECTED=os.environ['GITHUB_SHA']
def git(repo,*args,data=None,env=None):
    return subprocess.check_output(['git','-C',str(repo),*args],input=data,env=env,stderr=subprocess.PIPE)

assert git(ROOT,'rev-parse','HEAD').decode().strip()==EXPECTED
git(ROOT,'update-ref','refs/heads/main',EXPECTED)
target=ROOT.parent/'_sanitized-public.git'
subprocess.run(['git','clone','--bare','--no-hardlinks',str(ROOT),str(target)],check=True,capture_output=True)
refs={s.split(' ',1)[0]:s.split(' ',1)[1] for s in git(target,'for-each-ref','--format=%(refname) %(objectname)','refs/heads/main','refs/tags').decode().splitlines()}
commits=git(target,'rev-list','--reverse','--topo-order','--all').decode().splitlines()
mapping={};trees={};removed=set()
def allowed(path):
    if path in {'.github/workflows/design-workbench.yml','docs/DESIGN-WORKBENCH.md'}:return False
    try:check_source_paths([path]);return True
    except ValueError:return False
def tree(entries):
    root={}
    for path,mode,blob in entries:
        parts=path.split('/');node=root
        for part in parts[:-1]:node=node.setdefault(part,{})
        node[parts[-1]]=(mode,blob)
    def finish(node):
        records=[]
        for name,value in node.items():
            if isinstance(value,dict):mode,blob,kind='040000',finish(value),'tree'
            else:mode,blob=value;kind='blob'
            records.append(f'{mode} {kind} {blob}\t{name}\0'.encode())
        return git(target,'mktree','-z',data=b''.join(records)).decode().strip()
    return finish(root)
for old in commits:
    raw=git(target,'cat-file','commit',old);header,body=raw.split(b'\n\n',1);oldtree=header.splitlines()[0].split()[1].decode()
    if oldtree not in trees:
        entries=[]
        for row in git(target,'ls-tree','-rz','--full-tree',old).split(b'\0'):
            if not row:continue
            meta,name=row.split(b'\t',1);mode,kind,blob=meta.decode().split();path=name.decode()
            if allowed(path):assert kind=='blob';entries.append((path,mode,blob))
            else:removed.add(path)
        trees[oldtree]=tree(entries)
    lines=[];drop=False
    for line in header.splitlines():
        if line.startswith(b' '):
            if not drop:lines.append(line)
            continue
        drop=line.startswith((b'gpgsig ',b'gpgsig-sha256 ',b'mergetag '))
        if drop:continue
        if line.startswith(b'tree '):line=b'tree '+trees[oldtree].encode()
        elif line.startswith(b'parent '):line=b'parent '+mapping[line.split()[1].decode()].encode()
        lines.append(line)
    mapping[old]=git(target,'hash-object','-t','commit','-w','--stdin',data=b'\n'.join(lines)+b'\n\n'+body).decode().strip()
changes=[]
for ref,old in refs.items():
    kind=git(target,'cat-file','-t',old).decode().strip()
    if kind=='commit':new=mapping[old]
    else:
        assert kind=='tag';first,rest=git(target,'cat-file','tag',old).split(b'\n',1);commit=first.split()[1].decode()
        assert commit in mapping;rest=rest.split(b'-----BEGIN PGP SIGNATURE-----')[0]
        new=git(target,'hash-object','-t','tag','-w','--stdin',data=b'object '+mapping[commit].encode()+b'\n'+rest).decode().strip()
    git(target,'update-ref',ref,new,old);changes.append({'ref':ref,'before':old,'after':new})
assert git(target,'rev-parse','refs/heads/main^{tree}')==git(ROOT,'rev-parse','HEAD^{tree}'),'Current release/support tree must not change'
for new in set(mapping.values()):
    check_source_paths([p for p in git(target,'ls-tree','-rz','--name-only',new).decode().split('\0') if p])
report={'sourceOnly':True,'commitCount':len(commits),'removedPaths':sorted(removed),'refs':changes,'allNewTreesVerified':True,'externalForksCleaned':False,'githubCachedRefsCleaned':False,'pushed':False}
out=ROOT/'privacy-output';out.mkdir(exist_ok=True)
def save():(out/'history-cleanup.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
save()
leases=['--force-with-lease='+c['ref']+':'+c['before'] for c in changes]
refspecs=[c['ref']+':'+c['ref'] for c in changes]
auth=base64.b64encode(('x-access-token:'+os.environ['GH_TOKEN']).encode()).decode()
env={**os.environ,'GIT_CONFIG_COUNT':'1','GIT_CONFIG_KEY_0':'http.https://github.com/.extraheader','GIT_CONFIG_VALUE_0':'AUTHORIZATION: basic '+auth}
try:
    git(target,'push','--atomic',*leases,'https://github.com/'+REPO+'.git',*refspecs,env=env)
except subprocess.CalledProcessError as error:
    # Git output can include paths/ref names; never print the authenticated env.
    message=error.stderr.decode(errors='replace').replace(os.environ['GH_TOKEN'],'[redacted]').replace(auth,'[redacted]')
    print(message);raise SystemExit('Atomic history push failed; remote refs were not partially updated')
report['pushed']=True;save()
print('Verified and atomically cleaned',len(commits),'commits and',len(changes),'refs; current source tree and compiled installers unchanged.')
