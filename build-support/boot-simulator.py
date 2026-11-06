"""Boot only the selected simulator, with bounded CI readiness waits."""
import json,re,subprocess,sys
identifier=sys.argv[1]
assert re.fullmatch(r'[0-9A-Fa-f-]{36}',identifier)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j'],timeout=30))
device=next(d for rows in devices['devices'].values() for d in rows if d['udid']==identifier)
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',identifier],check=True,timeout=60)
subprocess.run(['xcrun','simctl','bootstatus',identifier,'-b'],check=True,timeout=180)
print('Selected simulator is ready')
