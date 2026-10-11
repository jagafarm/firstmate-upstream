import subprocess,os,json,time,pathlib
root=os.getcwd(); ev=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M4MBEGDRCR601S6H58YZ04MV'); session='fm-lab-devin-gate-1011'
os.environ.pop('NO_COLOR',None); os.environ['TERM']='xterm-256color'
os.environ['FM_HERDR_LAB_STATE_DIR']=root+'/.test-lab-state'
helper=root+'/bin/fm-herdr-lab.sh'
log=[]
def call(args,check=True):
 p=subprocess.run(args,text=True,capture_output=True); log.append('$ '+' '.join(args)+'\n'+p.stdout+p.stderr); print(log[-1],flush=True)
 if check and p.returncode: raise RuntimeError('command failed')
 return p.stdout
def h(*args):return call([helper,'run',session,*args])
def control(verb):
 env=os.environ.copy();env.update(FM_HOME=root+'/.test-devin-home',HERDR_SESSION=session,FM_CONTROL_POLL='0.2',FM_CONTROL_EXIT_WAIT='12',FM_LAB_ORIGINAL_PATH=os.environ['PATH'],FM_LAB_RUN_ROOT=root,PATH=root+'/.test-tools:'+os.environ['PATH'])
 p=subprocess.run([root+'/bin/fm-control.sh','validation',verb]+(['--note','Disposable composer lab; reply LAB_READY and wait; do not run tools.'] if verb=='relaunch' else []),text=True,capture_output=True,env=env);log.append('CONTROL '+verb+' rc='+str(p.returncode)+'\n'+p.stdout+p.stderr);print(log[-1],flush=True);return p
def capture(label):
 plain=h('pane','read','w2:p1','--source','visible','--raw'); ansi=h('pane','read','w2:p1','--source','visible','--format','ansi')
 (ev/(label+'.txt')).write_text(plain);(ev/(label+'.ansi')).write_text(ansi)
 return ansi
try:
 call([helper,'provision',session]);call([helper,'viewer','start',session]);h('workspace','create','--cwd',root+'/.test-worker','--label','devin-validation','--no-focus')
 h('agent','start','validation','--kind','devin','--pane','w2:p1','--','--permission-mode','dangerous','--respect-workspace-trust','false','--config',root+'/.test-devin-home/config/devin.json')
 pathlib.Path(root+'/.test-devin-home/state/validation.meta').write_text('window='+session+':w2:p1\nendpoint_task_id=validation\nharness=devin\nbackend=herdr\nherdr_session='+session+'\nherdr_workspace_id=w2\nherdr_tab_id=w2:t1\nherdr_pane_id=w2:p1\nworktree='+root+'/.test-worker'+'\nproject='+root+'/.test-project'+'\nkind=scout\nmodel=default\neffort=default\n')
 time.sleep(12);capture('devin-idle');h('agent','get','w2:p1')
 # Real adapter reads routed through the required lab helper.
 script='. bin/fm-backend.sh\nfm_backend_source herdr\nfm_backend_herdr_cli() { local s=$1; shift; bin/fm-herdr-lab.sh run "$s" "$@"; }\nfm_backend_herdr_composer_state fm-lab-devin-gate-1011:w2:p1\n'
 call(['bash','-c',script])
 h('pane','send-text','w2:p1','preserve this\n╭────╮\n│ ❭ │\n╰────╯');time.sleep(1);capture('devin-box-draft');call(['bash','-c',script]);control('exit');capture('devin-box-after-refusal')
 h('pane','send-keys','w2:p1',*(['backspace']*100));time.sleep(1);capture('devin-cleared');call(['bash','-c',script]);control('relaunch');time.sleep(8);capture('devin-after-relaunch');h('agent','get','w2:p1');call(['bash','-c',script]);control('exit');capture('devin-after-exit')
finally:
 call([helper,'teardown',session],False)
 (ev/'devin-live-transcript.log').write_text('\n'.join(log))
