#!/bin/bash
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?usage: verify-theme-transitions.sh /path/to/evidence}"
cd "$app_dir"
swift build --build-tests
build_dir="$(swift build --show-bin-path)"
/usr/bin/python3 - "$app_dir" "$build_dir" "$output" "${2:-}" <<'PY'
from pathlib import Path
import subprocess
import sys

app, build, output = (Path(value).resolve() for value in sys.argv[1:4])
output.mkdir(parents=True, exist_ok=True)
objects = [p for p in (build / "CodexMulti.build").glob("*.swift.o") if p.name != "CodexMultiApp.swift.o"]
objects += list((build / "CodexMultiResources.build").glob("*.swift.o"))
probe = output / "ThemeProbe"
sdk = subprocess.check_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
command = ["/usr/bin/swiftc", "-parse-as-library", "-target", "arm64-apple-macosx26.0", "-sdk", sdk,
           "-I", str(build / "Modules"), "-I", str(app / "Sources/CMCore"),
           str(app / "scripts/ThemeTransitionProbe.swift")]
command += [str(p) for p in objects]
command += [str(app / "zig/zig-out/lib/cmcore.o"), "-framework", "ServiceManagement",
            "-framework", "Security", "-o", str(probe)]
subprocess.run(command, check=True)
failed = []
query = ["/usr/bin/osascript", "-e", 'tell application "System Events" to tell appearance preferences to get dark mode']
original = subprocess.check_output(query, text=True).strip() if sys.argv[4] == "--system-changes" else None
try:
    for mode in ["settings", "accounts", "add-account", "rename"]:
        log = output / (mode + ".log")
        with log.open("w") as stream:
            arguments = [str(probe), str(app.parent / "core/fixtures/bridge"), str(output), mode]
            if original is not None and mode in ["settings", "accounts"]:
                arguments.append("--system-changes")
            result = subprocess.run(arguments, stdout=stream, stderr=subprocess.STDOUT, timeout=40)
        print(mode + ": " + ("PASS" if result.returncode == 0 else "FAIL") + " — " + str(log))
        if result.returncode:
            failed.append(mode)
            print("\n".join(line for line in log.read_text().splitlines() if "MISMATCH" in line or "ERROR" in line))
finally:
    if original is not None:
        subprocess.run(["/usr/bin/osascript", "-e", 'tell application "System Events" to tell appearance preferences to set dark mode to ' + original], check=True, capture_output=True)
if failed:
    raise SystemExit("Theme transition verification failed: " + ", ".join(failed))
PY
