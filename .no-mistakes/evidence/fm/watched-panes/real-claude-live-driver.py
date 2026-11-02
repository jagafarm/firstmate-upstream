import os, pathlib, subprocess, time, json, re
root=pathlib.Path.cwd()
ev=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M6CV1MTS66Y6ANJ9AYFS72RN')
lab='fm-lab-watch-gate-01m6'
env=dict(os.environ)
for k in ('FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','FM_BACKEND','HERDR_ENV','HERDR_PANE_ID','HERDR_SOCKET_PATH','HERDR_SESSION','FM_GATE_REFUSE_BYPASS'): env.pop(k,None)
env.update(FM_HOME=str(root/'.test-live/home'),FM_LIVE_ROOT=str(root),FM_LIVE_ORIGINAL_PATH=env['PATH'],FM_HERDR_LAB_STATE_DIR=str(root/'.test-live/lab-state'),FM_POLL='1',FM_WATCHED_PANE_READ_SECS='3')
cli_env=dict(env)
env['PATH']=str(root/'.test-live/bin')+':'+env['PATH']
records=json.loads((ev/"real-claude-results.json").read_text())["results"]
log=(ev/'real-claude-transitions.log').open('a')
def cli(*args):
    p=subprocess.run(['bash','bin/fm-herdr-lab.sh','run',lab,*args],env=cli_env,text=True,capture_output=True,timeout=15)
    log.write(json.dumps({'time':time.time(),'args':args,'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr})+'\n');log.flush()
    assert p.returncode==0,(args,p.stdout,p.stderr)
    return p.stdout

def state(agent): return json.loads(cli('agent','get',agent))['result']['agent']['agent_status']
def waitstate(agent,want,secs=60):
    end=time.monotonic()+secs
    while time.monotonic()<end:
        s=state(agent)
        if s==want:return
        time.sleep(.5)
    raise AssertionError((agent,want,s))
def drain():
    p=subprocess.run(['bash','bin/fm-wake-drain.sh'],env=env,text=True,capture_output=True,timeout=20)
    log.write(json.dumps({'drain':p.stdout+p.stderr})+'\n');log.flush()
    m=re.search(r'--ack-through (\d+) --recovery-generation (\S+)',p.stdout+p.stderr)
    if m:
        p=subprocess.run(['bash','bin/fm-wake-drain.sh','--ack-through',m[1],'--recovery-generation',m[2]],env=env,text=True,capture_output=True,timeout=20)
        log.write(json.dumps({'ack':p.stdout+p.stderr,'rc':p.returncode})+'\n');log.flush()
        assert p.returncode==0

def startwatch(label):
    drain()
    f=(ev/f'claude-watcher-{label}.log').open('w')
    return subprocess.Popen(['bash','bin/fm-watch.sh'],env=env,stdout=f,stderr=subprocess.STDOUT),f

def wake(p,f,label,status):
    p.wait(timeout=15);f.close()
    output=(ev/f'claude-watcher-{label}.log').read_text()
    assert p.returncode==0,output
    assert f'watched pane {label}' in output and f'agent {status}' in output,output
    records.append({'scenario':label+' '+status,'passed':True,'watcher_output':output})

active=[]
try:
    cli('agent','send-keys','notify-agent','enter')
    end=time.monotonic()+60
    while time.monotonic()<end:
        current=state('notify-agent')
        if current=='done': break
        if current=='blocked':
            screen=cli('agent','read','notify-agent','--source','detection','--lines','40')
            if 'Teach auto mode about your environment?' in screen:
                (ev/'claude-Notify-tutorial.txt').write_text(screen)
                cli('agent','send-keys','notify-agent','esc')
        time.sleep(.5)
    assert state('notify-agent')=='done'
    # Consume the initial notify-done level once before testing new completion edges.
    p,f=startwatch('initial-done');active.append(p)
    p.wait(timeout=15);f.close()
    assert p.returncode==0
    initial=(ev/'claude-watcher-initial-done.log').read_text()
    assert 'watched pane Notify' in initial and 'agent done' in initial,initial
    p,f=startwatch('done-policy');active.append(p)
    time.sleep(2)
    assert p.poll() is None
    cli('agent','prompt','blocked-agent','Reply exactly WATCH_TEST_DONE. Do not use tools.')
    waitstate('blocked-agent','done')
    (ev/'claude-Blocked-done.txt').write_text(cli('agent','read','blocked-agent','--source','detection','--lines','50'))
    time.sleep(4)
    assert p.poll() is None,'blocked-only watch emitted a completion wake'
    records.append({'scenario':'Blocked done suppressed','passed':True,'observation_seconds':4,'agent_status':state('blocked-agent')})
    cli('agent','prompt','notify-agent','Reply exactly WATCH_TEST_DONE. Do not use tools.')
    waitstate('notify-agent','done')
    (ev/'claude-Notify-done.txt').write_text(cli('agent','read','notify-agent','--source','detection','--lines','50'))
    p.wait(timeout=15);f.close()
    output=(ev/'claude-watcher-done-policy.log').read_text()
    assert p.returncode==0 and 'watched pane Notify' in output and 'agent done' in output,output
    assert 'watched pane Blocked' not in output,output
    records.append({'scenario':'Notify done delivered exclusively','passed':True,'watcher_output':output})
finally:
    for p in active:
        if p.poll() is None:
            p.terminate();p.wait(timeout=8)
    (ev/'real-claude-results.json').write_text(json.dumps({'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'results':records},indent=2)+'\n')
    log.close()
print(json.dumps(records,indent=2))
