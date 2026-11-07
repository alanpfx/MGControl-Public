"""Export numeric test totals only. Raw logs and rendered previews stay encrypted."""
import argparse,json,re
from pathlib import Path

def version_metadata(value):
    version=value.get('marketingVersion');build=value.get('buildNumber')
    if not isinstance(version,str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}',version):
        raise ValueError('Invalid source version metadata')
    if type(build) is not int or not 0<build<1_000_000_000:
        raise ValueError('Invalid source build metadata')
    return {'version':version,'build':build}

def test_totals(log):
    if '** TEST SUCCEEDED **' not in log:
        raise ValueError('Native test run did not succeed')
    result={}
    for name,key in [('MGControlTests.xctest','unit'),('MGControlUITests.xctest','ui')]:
        pattern=r"Test Suite '"+re.escape(name)+r"' passed[^\n]*\n\s*Executed (\d+) tests?, with (\d+) failures"
        matches=list(re.finditer(pattern,log))
        if not matches:raise ValueError('Required native test suite did not pass')
        count,failures=map(int,matches[-1].groups())
        if count<=0 or failures:raise ValueError('Required native tests were empty or failed')
        result[key]={'tests':count,'failures':failures}
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['metadata','summary'])
    p.add_argument('--version-file',required=True);p.add_argument('--github-env')
    p.add_argument('--log');p.add_argument('--source-sha');p.add_argument('--output')
    a=p.parse_args();metadata=version_metadata(json.loads(Path(a.version_file).read_text(encoding='utf8')))
    if a.mode=='metadata':
        if not a.github_env:raise ValueError('Missing workflow environment file')
        with Path(a.github_env).open('a',encoding='utf8') as f:f.write('EXPECTED_APP_BUILD='+str(metadata['build'])+'\n')
    else:
        if not a.source_sha or not re.fullmatch('[0-9a-f]{40}',a.source_sha):raise ValueError('Invalid immutable source pin')
        value={'result':'PASS','sourceSHA':a.source_sha,'sourceVersion':metadata,'suites':test_totals(Path(a.log).read_text(encoding='utf8',errors='replace')),'ipaProduced':False,'nativeProbeOnly':True,'candidateModelIncluded':False}
        target=Path(a.output);target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(json.dumps(value,indent=2)+'\n',encoding='utf8')

if __name__=='__main__':main()
