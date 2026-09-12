import json
import os
import pathlib
import re
import signal
import socket
import subprocess
import sys
import time
import tomllib
import urllib.request
import uuid

root = pathlib.Path(sys.argv[1]).resolve()
assert root.name.startswith('codexmulti-sparkle-') and root.parent == pathlib.Path('/private/tmp')
plan = json.loads((root / 'plan.json').read_text())
legacy_migration = plan.get('legacyMigration') is True
plan['label'] = 'dev.codexmulti.tests.sparkle.' + str(uuid.uuid4())
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0))
    plan['port'] = reservation.getsockname()[1]
(root / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
app = root / 'Installed/CodexMulti.app'
binary = app / 'Contents/MacOS/CodexMulti'
runtime = root / 'Home/Library/Application Support/CodexMulti'
env = dict(os.environ, HOME=str(root / 'Home'), CFFIXED_USER_HOME=str(root / 'Home'))
connection = None
process = None
target = f'gui/{os.getuid()}/'
kill_phase = os.environ.get('CODEXMULTI_TEST_AGENT_KILL_PHASE')
cold_restart = os.environ.get('CODEXMULTI_TEST_COLD_RESTART') == '1'
if cold_restart:
    assert kill_phase == 'STOP_COMMITTED'
restart_receipt = None


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


def owned_pid(label):
    result = subprocess.run(['/bin/launchctl', 'print', target + label], capture_output=True, text=True)
    if result.returncode:
        return None
    assert str(root) in result.stdout, 'foreign_job'
    matches = re.findall(r'^\s*pid = (\d+)\s*$', result.stdout, re.MULTILINE)
    assert len(matches) <= 1
    return int(matches[0]) if matches else None


def bootout_owned(label):
    if not owned_job(label):
        return
    result = subprocess.run(['/bin/launchctl', 'bootout', target + label], capture_output=True, text=True)
    assert result.returncode in (0, 3), result.stderr
    until = time.monotonic() + 10
    while time.monotonic() < until:
        if not owned_job(label):
            return
        time.sleep(0.05)
    raise RuntimeError('job_did_not_unload')


def restart_agent(journal):
    label = 'dev.codexmulti.app.update.' + journal['transaction_id']
    pid = owned_pid(label)
    assert pid and pid > 1
    os.kill(pid, signal.SIGKILL)
    if cold_restart:
        bootout_owned(label)
        assert owned_job(plan['label'])
        bootout_owned(plan['label'])
        plist = root / 'Home/Library/LaunchAgents' / (plan['label'] + '.plist')
        result = subprocess.run(['/bin/launchctl', 'bootstrap', target.rstrip('/'), str(plist)], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        until = time.monotonic() + 3
        while time.monotonic() < until:
            try:
                assert health()['gate'] != 'serving', 'admission_before_coordinator_recovery'
            except OSError:
                pass
            time.sleep(0.1)
        agent_plist = root / 'Home/Library/LaunchAgents' / (label + '.plist')
        subprocess.run(['/bin/launchctl', 'bootstrap', target.rstrip('/'), str(agent_plist)], capture_output=True, check=True)
    until = time.monotonic() + 15
    while time.monotonic() < until:
        restarted = owned_pid(label)
        if restarted and restarted != pid:
            return dict(phase=journal['phase'], old_pid=pid, new_pid=restarted,
                        cold_restart=cold_restart, admission_blocked_before_recovery=cold_restart)
        time.sleep(0.025)
    raise RuntimeError('agent_did_not_restart')


try:
    subprocess.run([str(binary), '--prepare'], env=env, check=True)
    initial = wait_health(lambda item: item['gate'] == 'serving')
    auth_before = (runtime / 'auth.json').read_bytes()
    if not legacy_migration:
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
        if kill_phase and phase == kill_phase and restart_receipt is None:
            restart_receipt = restart_agent(journal)
            print('Recovered coordinator process', json.dumps(restart_receipt), flush=True)
        success = read_json(root / 'success.json')
        if success:
            if legacy_migration:
                current = wait_health(lambda item: item['gate'] == 'serving' and item['generation'] == 2)
                assert success['build'] == plan['oldBuild'] and success['pid'] == old_pid
                assert current['boot_id'] != initial['boot_id']
                assert journal['kind'] == 'migration' and journal['desired_enabled'] is True
                assert auth_before == (runtime / 'auth.json').read_bytes()
                assert json.loads((runtime / 'proxy-settings.json').read_text())['enabled'] is True
                routing = tomllib.loads((root / 'Home/.codex/config.toml').read_text())
                assert routing['chatgpt_base_url'] == 'http://127.0.0.1:8787/backend-api/'
                assert routing['openai_base_url'] == 'http://127.0.0.1:8787/backend-api/codex'
                assert any(event['event'] == 'core-shutdown-joined' for event in events)
                receipt = dict(success, actual_legacy_migration=True, authentication_preserved=True,
                               enabled_preserved=True, routing_file_enabled=True,
                               old_boot_id=initial['boot_id'], new_boot_id=current['boot_id'])
                (root / 'verified.json').write_text(json.dumps(receipt, indent=2) + '\n')
                print(json.dumps(receipt, indent=2), flush=True)
                break
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
            download = ([event for event in events if event['event'] == 'state' and event['status'] == 'downloading']
                        if plan.get('transport') == 'https' else
                        [event for event in events if event['event'] == 'transport' and event['path'] == '/CodexMulti.zip'])
            assert shutdown and download and shutdown[0]['time'] < download[0]['time']
            assert auth_before == (runtime / 'auth.json').read_bytes()
            assert not kill_phase or restart_receipt is not None
            receipt = dict(success, changed_runtime=plan['changedRuntime'], old_pid=old_pid,
                           old_boot_id=initial['boot_id'], new_boot_id=current['boot_id'],
                           active_connection_preserved=True, core_shutdown_preceded_download=True,
                           transport='HTTPS' if plan.get('transport') == 'https' else 'local URLProtocol fixture',
                           actual_sparkle_install=True)
            if restart_receipt:
                receipt['agent_recovery'] = restart_receipt
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
        bootout_owned(label)
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
