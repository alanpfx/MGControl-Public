"""Numeric summary for focused native appearance checks; never claims full regression."""
import argparse,json,re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--log',required=True);p.add_argument('--source-sha',required=True);p.add_argument('--output',required=True);a=p.parse_args()
assert re.fullmatch('[0-9a-f]{40}',a.source_sha)
log=Path(a.log).read_text(encoding='utf8',errors='replace')
assert '** TEST SUCCEEDED **' in log
suites={}
for name in ['CarLiveActivityTests','ClassicMediumWidgetPreviewTests']:
 matches=list(re.finditer(r"Test Suite '"+name+r"' passed[^\n]*\n\s*Executed (\d+) tests?, with (\d+) failures",log))
 assert matches,'Required appearance suite missing'
 count,failed=map(int,matches[-1].groups());assert count>0 and failed==0
 suites[name]={'tests':count,'failures':failed}
target=Path(a.output);target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(json.dumps({'sourceSHA':a.source_sha,'result':'PASS','scope':'focused-native-appearance-preview','suites':suites,'uiTestsExecuted':False,'fullRegression':False,'ipaProduced':False},indent=2)+'\n',encoding='utf8')
