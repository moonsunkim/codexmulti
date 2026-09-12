import json
import os
import pathlib
import signal
import socket
import subprocess
import sys
import time
import urllib.request

root = pathlib.Path(sys.argv[1]).resolve()
assert root.name.startswith('codexmulti-sparkle-') and root.parent == pathlib.Path('/private/tmp')
plan = json.loads((root / 'plan.json').read_text())
app = root / 'Installed/CodexMulti.app'
binary = app / 'Contents/MacOS/CodexMulti'
runtime = root / 'Home/Library/Application Support/CodexMulti'
env = dict(os.environ, HOME=str(root / 'Home'), CFFIXED_USER_HOME=str(root / 'Home'))
connection = None
process = None
target = f'gui/{os.getuid()}/'


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else None


def health():
    token = (runtime / 'proxy.json.control-token').read_text().strip()
    request = urllib.request.Request(f'http://127.0.0.1:{plan["port"]}/_proxy/update/v1/health',
                                     headers={'Authorization': 'Bearer ' + token})
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.load(response)


def wait_health(predicate):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        try:
            result = health()
            if predicate(result):
                return result
        except (OSError, ValueError):
            pass
        time.sleep(0.1)
    raise RuntimeError('health_timeout')


def owned_job(label):
    result = subprocess.run(['/bin/launchctl', 'print', target + label], capture_output=True, text=True)
    if result.returncode:
        return False
    assert str(root) in result.stdout, 'foreign_job'
    return True


try:
    subprocess.run([str(binary), '--prepare'], env=env, check=True)
    initial = wait_health(lambda item: item['gate'] == 'serving')
    auth_before = (runtime / 'auth.json').read_bytes()
    connection = socket.create_connection(('127.0.0.1', plan['port']), timeout=2)
    connection.sendall((f'POST /backend-api/codex/responses HTTP/1.1\r\nHost: 127.0.0.1:{plan["port"]}\r\n'
                        'Content-Type: application/json\r\nContent-Length: 100\r\n\r\n{').encode())
    wait_health(lambda item: item['work_total'] == 1)
    log = (root / 'probe.log').open('w')
    process = subprocess.Popen([str(binary)], env=env, stdout=log, stderr=subprocess.STDOUT)
    old_pid = process.pid
    released = False
    deadline = time.monotonic() + 200
    last = None
    waiting_since = None
    while time.monotonic() < deadline:
        events = [json.loads(line) for line in (root / 'events.jsonl').read_text().splitlines()]
        failures = [event for event in events if event['event'] == 'failed']
        if failures:
            raise RuntimeError(f'probe_failed: {failures[-1]}')
        pointer = read_json(runtime / 'current-update.json')
        journal = read_json(runtime / 'updates' / pointer['transaction_id'] / 'journal.json') if pointer else None
        phase = journal['phase'] if journal else None
        if phase != last:
            print('Sparkle transition', phase, flush=True)
            last = phase
        success = read_json(root / 'success.json')
        if success:
            assert success['build'] == plan['newBuild']
            assert success['pid'] != old_pid
            current = wait_health(lambda item: item['gate'] == 'serving')
            if plan['changedRuntime']:
                assert released and current['runtime_id'] != initial['runtime_id']
                assert current['boot_id'] != initial['boot_id'] and current['generation'] == 2
            else:
                assert current['boot_id'] == initial['boot_id'] and current['work_total'] == 1
                assert current['generation'] == initial['generation']
            shutdown = [event for event in events if event['event'] == 'core-shutdown-joined' and event['pid'] == old_pid]
            download = [event for event in events if event['event'] == 'transport' and event['path'] == '/CodexMulti.zip']
            assert shutdown and download and shutdown[0]['time'] < download[0]['time']
            assert auth_before == (runtime / 'auth.json').read_bytes()
            receipt = dict(success, changed_runtime=plan['changedRuntime'], old_pid=old_pid,
                           old_boot_id=initial['boot_id'], new_boot_id=current['boot_id'],
                           active_connection_preserved=True, core_shutdown_preceded_download=True,
                           transport='local URLProtocol fixture', actual_sparkle_install=True)
            (root / 'verified.json').write_text(json.dumps(receipt, indent=2) + '\n')
            print(json.dumps(receipt, indent=2), flush=True)
            break
        if connection:
            current = health()
            assert current['boot_id'] == initial['boot_id'], 'proxy_restarted_while_busy'
            assert current['work_total'] == 1, 'active_connection_lost'
        if plan['changedRuntime'] and phase == 'WAITING_IDLE' and not released:
            assert any(event['event'] == 'gui-start' and event['build'] == plan['newBuild'] for event in events)
            waiting_since = waiting_since or time.monotonic()
            if time.monotonic() - waiting_since >= 3:
                connection.close()
                connection = None
                released = True
                print('Closed partial request after new GUI stayed WAITING_IDLE', flush=True)
        time.sleep(0.2)
    else:
        raise RuntimeError('sparkle_timeout')
finally:
    if connection:
        connection.close()
    labels = [plan['label']]
    pointer = read_json(runtime / 'current-update.json')
    if pointer:
        labels.append('dev.codexmulti.app.update.' + pointer['transaction_id'])
    for label in labels:
        if owned_job(label):
            subprocess.run(['/bin/launchctl', 'bootout', target + label], check=True, capture_output=True)
    if process and process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    events_path = root / 'events.jsonl'
    if events_path.exists():
        for event in [json.loads(line) for line in events_path.read_text().splitlines()]:
            if event['event'] == 'gui-start':
                pid = event['pid']
                result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True)
                if result.returncode == 0 and str(binary) in result.stdout:
                    os.kill(pid, signal.SIGTERM)
