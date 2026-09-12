#!/bin/bash
set -euo pipefail

app="$(cd "${1:?usage: verify-signed-startup.sh /path/to/CodexMulti.app}" && pwd -P)"
/usr/bin/python3 - "$app" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

executable = Path(sys.argv[1]) / "Contents/MacOS/CodexMulti"
with tempfile.TemporaryDirectory(prefix="cm-startup-", dir="/private/tmp") as temporary:
    root = Path(temporary)
    store = root / "Library/Application Support/CodexMulti"
    store.mkdir(parents=True, mode=0o700)
    accounts = []
    for index in range(2):
        key = "codex-" + uuid.uuid4().hex
        accounts.append({"id": "acct-" + uuid.uuid4().hex, "provider": "codex",
                         "label": "Startup verification " + str(index + 1),
                         "storage_key": key, "auth_state": "connected",
                         "created_at_unix_s": 1700000000, "enabled": False})
        auth = store / "accounts" / key / "codex/auth.json"
        auth.parent.mkdir(parents=True, mode=0o700)
        auth.write_text('{"auth_mode":"chatgpt","tokens":{"access_token":"synthetic-startup-check","refresh_token":"synthetic-startup-check"}}')
        auth.chmod(0o600)
    registry = store / "accounts.json"
    registry.write_text(json.dumps({"schema_version": 1, "accounts": accounts}))
    registry.chmod(0o600)
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in store.rglob("*.json")}
    environment = dict(os.environ, HOME=str(root), CODEX_HOME=str(root / ".codex"))
    result = subprocess.run([str(executable), "--keychain-probe"], env=environment,
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise SystemExit("Signed application startup failed (exit " + str(result.returncode) + "): " + result.stderr.strip())
    try:
        report = json.loads(result.stdout)
    except ValueError:
        raise SystemExit("Signed application returned invalid startup evidence")
    if not (report.get("schema") == 1 and report.get("signer_valid") is True
            and report.get("runtime_started") is True and report.get("account_count") == 2
            and report.get("accounts") == []):
        raise SystemExit("Signed application did not start and load both saved accounts")
    after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in store.rglob("*.json")}
    if before != after:
        raise SystemExit("Signed application startup changed the saved account fixture")
print("Signed application startup: PASS; both saved accounts loaded; account files unchanged")
PY
