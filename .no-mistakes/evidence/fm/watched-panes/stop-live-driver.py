import os, pathlib, subprocess, time, signal, json
root=pathlib.Path.cwd()
evidence=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M6CV1MTS66Y6ANJ9AYFS72RN')
env=dict(os.environ)
for key in ('FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','FM_BACKEND','HERDR_ENV','HERDR_PANE_ID','HERDR_SOCKET_PATH','HERDR_SESSION','FM_GATE_REFUSE_BYPASS'):
    env.pop(key,None)
env.update(FM_HOME=str(root/'.test-live/home'), PATH=str(root/'.test-live/bin')+':'+env['PATH'], FM_POLL='1', FM_LIVE_DELAY_STATUS='1')
results=[]
def alive(pid):
    p=subprocess.run(['ps','-p',str(pid),'-o','stat='],text=True,capture_output=True)
    return bool(p.stdout.strip()) and not p.stdout.strip().startswith('Z')
for mode in ('budget','stop'):
    home=root/f'.test-live/home-{mode}'
    subprocess.run(['bash','bin/fm-lab-home.sh','create',str(home)],check=True,stdout=subprocess.DEVNULL)
    (home/'state/watched-panes').write_text((root/'.test-live/home/state/watched-panes').read_text())
    env['FM_HOME']=str(home)
    pidlog=root/f'.test-live/{mode}-delayed-pids-2'
    env.update(FM_LIVE_DELAY_LOG=str(pidlog),FM_WATCHED_PANE_READ_SECS='1' if mode=='budget' else '30')
    output=evidence/f'watcher-{mode}.log'
    start=time.monotonic()
    with output.open('w') as f:
        p=subprocess.Popen(['bash','bin/fm-watch.sh'],env=env,stdout=f,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+20
            target_count=2 if mode=='budget' else 1
            while time.monotonic()<deadline:
                pids=pidlog.read_text().splitlines() if pidlog.exists() else []
                if len(pids)>=target_count: break
                if p.poll() is not None: raise RuntimeError(f'watcher exited before delayed read: {output.read_text()}')
                time.sleep(.1)
            assert len(pids)>=target_count, 'watcher did not reach delayed reads'
            reached=time.monotonic()-start
            if mode=='budget':
                assert not alive(int(pids[0])), 'first delayed read survived budget'
            pgid=subprocess.check_output(['ps','-p',pids[-1],'-o','pgid='],text=True).strip()
            stop=time.monotonic()
            p.terminate()
            rc=p.wait(timeout=8)
            elapsed=time.monotonic()-stop
            assert not alive(int(pids[-1])), 'delayed read survived watcher stop'
            results.append(dict(mode=mode,watcher_pid=p.pid,delayed_read_pids=pids,delayed_read_pgid=pgid,reached_seconds=round(reached,2),stop_seconds=round(elapsed,2),exit_code=rc,delayed_read_survived=False))
        finally:
            if p.poll() is None:
                p.terminate()
                try:p.wait(timeout=8)
                except subprocess.TimeoutExpired:p.kill();p.wait()
print(json.dumps(results,indent=2))
