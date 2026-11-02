import os,pathlib,subprocess,json,time,shlex,re
root=pathlib.Path.cwd(); ev=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M6CV1MTS66Y6ANJ9AYFS72RN'); lab='fm-lab-watch-current'; home=root/'.test-live/home'
env=dict(os.environ)
for k in list(env):
 if k.startswith('FM_') or k.startswith('HERDR_') or k in ('CLAUDECODE','CLAUDE_CODE_ENTRYPOINT'): env.pop(k,None)
env.update(FM_HOME=str(home),FM_HERDR_LAB_STATE_DIR=str(root/'.test-live/lab-state'),FM_POLL='1',FM_WATCHED_PANE_READ_SECS='3')
log=(ev/'current-live-transcript.jsonl').open('w'); active=[]; results=[]
def run(args,e=env,timeout=30,check=True):
 p=subprocess.run(args,env=e,text=True,capture_output=True,timeout=timeout)
 log.write(json.dumps(dict(time=time.time(),args=args,rc=p.returncode,stdout=p.stdout,stderr=p.stderr))+'\n');log.flush()
 if check: assert p.returncode==0,(args,p.stdout,p.stderr)
 return p.stdout
helper=['bash','bin/fm-herdr-lab.sh']
def cli(*args):
 args=list(args)
 if args[0]=='agent' and len(args)>2: args[2]=args[2].lower()
 return run(helper+['run',lab]+args,timeout=90)
def status(a):return json.loads(cli('agent','get',a))['result']['agent']['agent_status']
def wait(a,want,timeout=75):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  s=status(a)
  if s==want:return
  time.sleep(.7)
 raise AssertionError((a,want,s,cli('agent','read',a,'--lines','40')))
def drain():
 s=run(['bash','bin/fm-wake-drain.sh'],e=we)
 m=re.search(r'--ack-through (\d+) --recovery-generation (\S+)',s)
 if m: run(['bash','bin/fm-wake-drain.sh','--ack-through',m[1],'--recovery-generation',m[2]],e=we)
def watch(name):
 drain(); f=(ev/('current-watcher-'+name+'.log')).open('w');p=subprocess.Popen(['bash','bin/fm-watch.sh'],env=we,stdout=f,stderr=subprocess.STDOUT);active.append((p,f));return p,f
def donewatch(p,f,name,needle):
 p.wait(timeout=20);f.close();s=(ev/('current-watcher-'+name+'.log')).read_text(); assert p.returncode==0 and needle in s,s;return s
try:
 run(['bash','bin/fm-lab-home.sh','create',str(home)])
 run(helper+['provision',lab]);run(helper+['viewer','start',lab])
 ws=json.loads(cli('workspace','create','--cwd',str(home),'--label','watch-ops'))
 print('workspace',ws,flush=True)
 (ev/'current-workspace.json').write_text(json.dumps(ws,indent=2))
 # Keep all watcher Herdr transport explicitly inside the lab, including capability queries.
 bindir=root/'.test-live/bin';bindir.mkdir()
 wrapper='''#!/bin/bash
set -eu
args=("$@")
n=${#args[@]}
if [ "${1:-}" = status ] || [ "${1:-} ${2:-}" = 'api schema' ] || [ "${1:-} ${2:-}" = 'session list' ]; then
 args+=(--session fm-lab-watch-current); n=${#args[@]}
fi
[ "$n" -ge 2 ] && [ "${args[n-2]}" = --session ] && [ "${args[n-1]}" = fm-lab-watch-current ] || exit 98
exec env PATH='''+shlex.quote(env['PATH'])+' '+shlex.quote(str(root/'bin/fm-herdr-lab.sh'))+''' run fm-lab-watch-current "${args[@]:0:n-2}"
'''
 (bindir/'herdr').write_text(wrapper);(bindir/'herdr').chmod(0o755)
 we=dict(env,PATH=str(bindir)+':'+env['PATH'])
 # workspace creates an initial shell tab/pane
 info=ws['result']; print('keys',info,flush=True)
 wid=info.get('workspace',info).get('id',info.get('workspace',info).get('workspace_id'))
 assert wid,ws
 tab=json.loads(cli('tab','create','--workspace',wid,'--cwd',str(home),'--label','Notify','--no-focus'))
 tab2=json.loads(cli('tab','create','--workspace',wid,'--cwd',str(home),'--label','Blocked','--no-focus'))
 (ev/'current-tabs.json').write_text(json.dumps([tab,tab2],indent=2))
 for label,t in [('Notify',tab),('Blocked',tab2)]:
  pane=t['result']['root_pane']['pane_id']; assert pane,t
  cli('agent','start',label,'--kind','claude','--pane',pane,'--timeout','60000','--','--setting-sources','','--settings','{"disableAllHooks":true}','--system-prompt','You are a live notification test subject. Follow only the user test prompt. Do not inspect files, run shell commands, delegate, or modify files. Use AskUserQuestion when asked and wait for the answer, then reply WATCH_TEST_DONE.')
  run(['bash','bin/fm-watch-pane.sh','add',lab,'watch-ops',label,label]+(['--notify-done'] if label=='Notify' else []),e=we)
 for label in ['Notify','Blocked']:
  p,f=watch(label+'-blocked')
  cli('agent','prompt',label,'Use AskUserQuestion now to ask "Can this notification test finish?" with options "Finish test" and "Keep waiting". Wait for my answer then reply exactly WATCH_TEST_DONE. Do not use other tools.')
  wait(label,'blocked');(ev/('current-'+label+'-blocked.txt')).write_text(cli('agent','read',label,'--source','detection','--lines','50'))
  s=donewatch(p,f,label+'-blocked','watched pane '+label)
  assert 'agent blocked' in s,s
  results.append(dict(name=label+' blocked wake',result='pass',live=True))
  # resolve first question and acknowledge any optional tutorial separately
  cli('agent','send-keys',label,'enter')
  end=time.monotonic()+75
  while time.monotonic()<end:
   st=status(label)
   if st in ('done','idle'):break
   if st=='blocked':
    screen=cli('agent','read',label,'--source','detection','--lines','45')
    if 'Teach auto mode' in screen:cli('agent','send-keys',label,'esc')
   time.sleep(.8)
  assert st in ('done','idle'),st
  if label=='Notify':
   p,f=watch('initial-done');donewatch(p,f,'initial-done','agent done')
 # unfocus both agents so completions are reported done, not focused idle
 third=json.loads(cli('tab','create','--workspace',wid,'--cwd',str(home),'--label','Observer','--focus'))
 p,f=watch('done-policy');time.sleep(2);assert p.poll() is None
 cli('agent','prompt','Blocked','Reply exactly WATCH_TEST_DONE. Do not use tools.');wait('Blocked','done');time.sleep(4)
 assert p.poll() is None,'blocked-only completion woke watcher'
 (ev/'current-Blocked-done.txt').write_text(cli('agent','read','Blocked','--lines','45'))
 results.append(dict(name='Blocked-only done suppressed',result='pass',live=True,observation_seconds=4))
 cli('agent','prompt','Notify','Reply exactly WATCH_TEST_DONE. Do not use tools.');wait('Notify','done')
 (ev/'current-Notify-done.txt').write_text(cli('agent','read','Notify','--lines','45'))
 s=donewatch(p,f,'done-policy','watched pane Notify');assert 'agent done' in s and 'watched pane Blocked' not in s,s
 results.append(dict(name='Notify done wakes exclusively',result='pass',live=True))
except Exception as ex:
 results.append(dict(error=str(ex)));raise
finally:
 for p,f in active:
  if p.poll() is None:p.terminate();p.wait(timeout=10)
  if not f.closed:f.close()
 run(helper+['teardown',lab],check=False,timeout=40)
 (ev/'current-live-results.json').write_text(json.dumps(results,indent=2));log.close()
 import shutil
 shutil.rmtree(root/'.test-live')
print(json.dumps(results),flush=True)
