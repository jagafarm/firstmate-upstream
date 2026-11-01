import os, pathlib, subprocess, json, time, shutil, re
R=pathlib.Path.cwd(); E=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M6CABHCVTFN9910QVKEZZ69B'); H=R/'bin/fm-herdr-lab.sh'
env=os.environ.copy()
for k in list(env):
 if k.startswith('HERDR_') or k in ['FM_HOME','FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','FM_BACKEND','FM_GATE_REFUSE_BYPASS']: env.pop(k,None)
env['FM_HERDR_LAB_STATE_DIR']=str(E/'lab-state')
log=(E/'api-transcript.log').open('w'); session=''; active=False
home=E/'lab-home'; wrap=E/'lab-bin'
def run(args,check=True,timeout=30,ev=None):
 p=subprocess.run([str(a) for a in args],env=ev or env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 log.write('$ '+ ' '.join(map(str,args))+'\n'+p.stdout+'\nexit='+str(p.returncode)+'\n');log.flush()
 if check and p.returncode: raise RuntimeError(p.stdout)
 return p

def lab(*args,check=True): return run([H,'run',session,*args],check)
def obj(*args): return json.loads(lab(*args).stdout)
def cli(*args,check=True): return run(['bash',R/'bin/fm-watch-pane.sh',*args],check,ev=appenv)
def watch(label,seconds=4):
 p=run(['bash',R/'bin/fm-watch.sh'],False,timeout=seconds+20,ev=appenv)
 (E/(label+'.log')).write_text(p.stdout); return p
def spawn_watch(name):
 f=(E/(name+'.log')).open('w')
 p=subprocess.Popen(['bash',str(R/'bin/fm-watch.sh')],env=appenv,stdout=f,stderr=subprocess.STDOUT)
 return p,f

def stop_watch(p,f):
 if p.poll() is None:p.terminate();p.wait(timeout=10)
 f.close()
def report(status):
 if status=='done':status='idle'
 lab('pane','report-agent',pane,'--source','watch-live-api','--agent','claude','--state',status)
 lab('agent','get',pane,check=False)
def queue():
 q=home/'state/.wake-queue'
 return q.read_text() if q.exists() else ''
pending=None
last_queue=''
def ack():
 d=run(['bash',R/'bin/fm-wake-drain.sh'],False,ev=appenv)
 m=re.search(r'--ack-through (\d+) --recovery-generation (\S+)',d.stdout)
 assert m,d.stdout
 run(['bash',R/'bin/fm-wake-drain.sh','--ack-through',m[1],'--recovery-generation',m[2]],False,ev=appenv)
def expect_wake(name,status):
 global pending,last_queue
 if pending is None: p,f=spawn_watch(name)
 else: p,f=pending;pending=None
 try:
  p.wait(timeout=45)
  assert p.returncode==0,(name,p.returncode)
 finally:stop_watch(p,f)
 text=queue()
 assert 'watched pane Operations primary' in text and 'agent '+status in text,text
 (E/(name+'-queue.tsv')).write_text(text)
 print(name,text.strip(),flush=True)
 ack();last_queue=queue()
def expect_quiet(name):
 global pending
 if pending is None:pending=spawn_watch(name)
 p,f=pending
 before=queue();time.sleep(4)
 assert p.poll() is None,(name,(E/(name+'.log')).read_text() if (E/(name+'.log')).exists() else 'watcher exited')
 assert queue()==before,name+' duplicate queue record'
 (E/(name+'-observation.txt')).write_text('Watcher stayed running for four seconds; durable queue unchanged.\n'+before)
 print(name,'quiet with unchanged wake queue',flush=True)
try:
 session=run([H,'name','watch-api']).stdout.strip()
 run([H,'provision',session]);active=True
 run(['bash',R/'bin/fm-lab-home.sh','create',home])
 wrap.mkdir(exist_ok=True)
 (wrap/'herdr').write_text('''#!/usr/bin/env bash
set -eu
args=("$@")
if [ "${1:-} ${2:-}" = 'session list' ]; then exec env PATH="$LAB_PATH" "$LAB_HELPER" run "$LAB_SESSION" "$@"; fi
n=${#args[@]}
[ "$n" -ge 2 ] && [ "${args[$((n-2))]}" = --session ] && [ "${args[$((n-1))]}" = "$LAB_SESSION" ] || exit 97
args=("${args[@]:0:$((n-2))}")
exec env PATH="$LAB_PATH" "$LAB_HELPER" run "$LAB_SESSION" "${args[@]}"
''');(wrap/'herdr').chmod(0o755)
 appenv=env.copy();appenv.update(FM_HOME=str(home),FM_POLL='1',PATH=str(wrap)+':'+env['PATH'],LAB_PATH=env['PATH'],LAB_SESSION=session,LAB_HELPER=str(H))
 ws=obj('workspace','create','--cwd',R,'--label','Watch lab','--no-focus')['result'];pane=ws['root_pane']['pane_id'];tab=ws['tab']['tab_id'];wid=ws['workspace']['workspace_id']
 lab('tab','rename',tab,'Operations')
 cli('add',session,'Watch lab','Operations','Operations primary','--notify-done')
 report('blocked');expect_wake('api-blocked','blocked');expect_quiet('api-blocked-deduped')
 report('working');expect_quiet('api-working-rearms')
 report('blocked');expect_wake('api-rearmed-blocked','blocked')
 # Opting out of finish notifications uses the same public registration CLI.
 cli('add',session,'Watch lab','Operations','Operations primary')
 report('working');expect_quiet('api-optout-working')
 report('idle');expect_quiet('api-idle-deferred')
 # Refresh the label identity: close the old tab, create its replacement.
 ws2=obj('tab','create','--workspace',wid,'--cwd',R,'--label','Replacement','--no-focus')['result']
 newpane=ws2['root_pane']['pane_id'];newtab=ws2['tab']['tab_id']
 lab('tab','close',tab);lab('tab','rename',newtab,'Operations');pane=newpane
 report('blocked');expect_wake('api-replacement-pane','blocked')
 (E/'api-final-queue.tsv').write_text(queue())
 cli('remove','Operations primary');assert cli('list').stdout==''
 expect_quiet('api-unregistered')
 print('ALL_API_SCENARIOS_PASS',flush=True)
finally:
 if pending is not None:stop_watch(*pending)
 if active:run([H,'teardown',session],False,timeout=45)
 if home.exists():shutil.rmtree(home)
 if wrap.exists():shutil.rmtree(wrap)
 log.close()
