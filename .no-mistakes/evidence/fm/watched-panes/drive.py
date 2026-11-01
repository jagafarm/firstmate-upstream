import os, pathlib, subprocess, json, time, shutil
R=pathlib.Path.cwd(); E=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M6CABHCVTFN9910QVKEZZ69B'); H=R/'bin/fm-herdr-lab.sh'
env=os.environ.copy()
for k in list(env):
 if k.startswith('HERDR_') or k in ['FM_HOME','FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','FM_BACKEND','FM_GATE_REFUSE_BYPASS']: env.pop(k,None)
env['FM_HERDR_LAB_STATE_DIR']=str(E/'lab-state')
log=(E/'live-transcript.log').open('w'); session=''; active=False
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
try:
 session=run([H,'name','watched-panes']).stdout.strip()
 run([H,'provision',session]);active=True
 run(['bash',R/'bin/fm-lab-home.sh','create',home])
 wrap.mkdir(exist_ok=True)
 # Every adapter CLI call is admitted through the trusted lab helper.
 (wrap/'herdr').write_text('''#!/usr/bin/env bash
set -eu
args=("$@")
n=${#args[@]}
[ "$n" -ge 2 ] && [ "${args[$((n-2))]}" = --session ] && [ "${args[$((n-1))]}" = "$LAB_SESSION" ] || exit 97
args=("${args[@]:0:$((n-2))}")
exec env PATH="$LAB_PATH" "$LAB_HELPER" run "$LAB_SESSION" "${args[@]}"
''');(wrap/'herdr').chmod(0o755)
 appenv=env.copy();appenv.update(FM_HOME=str(home),FM_POLL='1',PATH=str(wrap)+':'+env['PATH'],LAB_PATH=env['PATH'],LAB_SESSION=session,LAB_HELPER=str(H))
 ws=obj('workspace','create','--cwd',R,'--label','Watch lab','--no-focus')['result']; pane=ws['root_pane']['pane_id'];tab=ws['tab']['tab_id'];wid=ws['workspace']['workspace_id']
 lab('tab','rename',tab,'Operations')
 cli('add',session,'Watch lab','Operations','Operations primary','--notify-done');cli('list')
 before=(home/'state/watched-panes').read_bytes()
 assert cli('add',session,'Watch lab','Operations','Duplicate',check=False).returncode != 0
 assert cli('add',session,'Missing','Operations','Missing',check=False).returncode != 0
 assert (home/'state/watched-panes').read_bytes()==before
 split=obj('pane','split',pane,'--direction','right','--cwd',R,'--no-focus')['result']['pane']['pane_id']
 assert cli('add',session,'Watch lab','Operations','Operations primary',check=False).returncode !=0
 assert (home/'state/watched-panes').read_bytes()==before
 lab('pane','close',split)
 cli('remove','Absent')
 (E/'registry-results.txt').write_text('PASS real Herdr: explicit label registration/list, duplicate identity refusal, missing workspace refusal, split tab refusal, failed updates preserve registry, absent removal is idempotent.\n'+before.decode())
 run([H,'viewer','start',session])
 lab('pane','run',pane,'env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME='+str(home)+' claude --settings \'{"feedbackDrafts":"off"}\'')
 for i in range(25):
  screen=lab('pane','read',pane,'--source','visible').stdout
  (E/'claude-start.txt').write_text(screen)
  if 'trust this folder' in screen or 'trust this directory' in screen:
   (E/'claude-blocker.txt').write_text('Claude requires folder trust. Accepting it would modify user-level tool configuration outside the worktree, forbidden by this phase boundary.\n'+screen);break
  st=lab('agent','get',pane,check=False)
  if st.returncode==0:
   agent=json.loads(st.stdout).get('result',{}).get('agent',{}) or {}
   if agent.get('agent_status') in ['idle','done'] and '❯' in screen: break
  time.sleep(1)
 else: raise RuntimeError('Claude did not reach ready composer')
 (E/'lab-target.json').write_text(json.dumps(dict(session=session,pane=pane,workspace=wid,tab=tab)))
 # Human-readable shell output retains actual initial state and readiness.
 if (E/'claude-blocker.txt').exists(): print('BLOCKED_CLAUDE_TRUST',flush=True)
 else:
  print('CLAUDE_READY',flush=True)
  p=subprocess.Popen(['bash',str(R/'bin/fm-watch.sh')],env=appenv,stdout=(E/'watch-claude.log').open('w'),stderr=subprocess.STDOUT)
  try:
   lab('agent','prompt',pane,'Do not use tools or change files. Reply with exactly WATCH_PANE_LIVE_OK.')
   seen=[]
   for i in range(45):
    a=obj('agent','get',pane)['result']['agent']; seen.append(a)
    if p.poll() is not None:break
    time.sleep(1)
   (E/'claude-states.json').write_text(json.dumps(seen,indent=2))
   (E/'claude-result.txt').write_text(lab('pane','read',pane,'--source','recent','--lines','200').stdout)
   if p.poll() is None: print('NO_CLAUDE_WAKE',flush=True)
   else: print('CLAUDE_WATCH_EXIT',p.returncode,(E/'watch-claude.log').read_text(),flush=True)
   if (home/'state/.wake-queue').exists():shutil.copyfile(home/'state/.wake-queue',E/'claude-wake-queue.tsv')
  finally:
   if p.poll() is None:p.terminate();p.wait(timeout=10)
finally:
 if active:run([H,'teardown',session],False,timeout=45)
 if home.exists():shutil.rmtree(home)
 if wrap.exists():shutil.rmtree(wrap)
 log.close()
