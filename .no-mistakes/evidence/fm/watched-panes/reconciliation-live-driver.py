import os,pathlib,subprocess,time,json
root=pathlib.Path.cwd();evidence=pathlib.Path('/Users/buruchan_1221/.no-mistakes/evidence/01M6CV1MTS66Y6ANJ9AYFS72RN')
env=dict(os.environ)
for k in ('FM_ROOT_OVERRIDE','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_CONFIG_OVERRIDE','FM_PROJECTS_OVERRIDE','FM_BACKEND','HERDR_ENV','HERDR_PANE_ID','HERDR_SOCKET_PATH','HERDR_SESSION','FM_GATE_REFUSE_BYPASS'):env.pop(k,None)
env.update(PATH=str(root/'.test-live/bin')+':'+env['PATH'],FM_POLL='5',FM_WATCHED_PANE_READ_SECS='1')
results=[]
for mode in ('second','healthy'):
    home=root/f'.test-live/home-{mode}-socketfix'
    subprocess.run(['bash','bin/fm-lab-home.sh','create',str(home)],check=True,stdout=subprocess.DEVNULL)
    (home/'state/watched-panes').write_text((root/'.test-live/home/state/watched-panes').read_text())
    reads=root/f'.test-live/{mode}-reads-socketfix';delay=root/f'.test-live/{mode}-delay-socketfix'
    env.update(FM_HOME=str(home),FM_LIVE_DELAY_STATUS=mode,FM_LIVE_READ_LOG=str(reads),FM_LIVE_DELAY_LOG=str(delay))
    with (evidence/f'watcher-{mode}.log').open('w') as log:
        p=subprocess.Popen(['bash','bin/fm-watch.sh'],env=env,stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+20
            while time.monotonic()<deadline:
                rows=[r.split() for r in reads.read_text().splitlines()] if reads.exists() else []
                if len(rows)>=3:break
                if p.poll() is not None:raise RuntimeError('watcher exited early')
                time.sleep(.1)
            assert len(rows)>=3,'watcher failed to retry'
            elapsed=int(rows[2][1])-int(rows[1][1])
            assert int(rows[1][1])-int(rows[0][1])<=2,'second read was a later probe, not reconciliation'
            if mode=='second':
                assert delay.exists(),'second status read was not reached'
                state=subprocess.run(['ps','-p',delay.read_text().strip(),'-o','stat='],text=True,capture_output=True).stdout.strip()
                assert not state or state.startswith('Z'),'second read survived budget'
                assert elapsed<4,f'second read exceeded the 1-second budget: {elapsed}s'
            else:
                assert elapsed>=4,f'healthy subscription was truncated to {elapsed}s'
            results.append(dict(mode=mode,reads=rows,second_to_next_probe_seconds=elapsed,passed=True))
        finally:
            p.terminate();p.wait(timeout=8)
print(json.dumps(results,indent=2))
