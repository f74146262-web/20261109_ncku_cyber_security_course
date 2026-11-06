#!/usr/bin/env python3
"""Check that every published Compose port is bound to loopback only.

Usage:
    python3 scripts/check_ports.py compose.yaml
    python3 scripts/check_ports.py compose.yaml compose.vuln.yaml compose.patched.yaml

All paths are passed to one `docker compose -f ... config` call, so overlays
are resolved together.

Exit code 0 means every published port is bound to 127.0.0.1.
Exit code 1 means a port is exposed on another interface, or a file could not
be parsed.
"""

import json
import subprocess
import sys


def load(paths):
    command = ["docker", "compose"]
    for path in paths:
        command += ["-f", path]
    command += ["config", "--format", "json"]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "docker compose config failed")
    return json.loads(result.stdout)


def main(paths):
    try:
        data = load(paths)
    except Exception as exc:  # noqa: BLE001 - report and exit
        print(f"  [FAIL] {' '.join(paths)}: {exc}")
        return 1

    ok = True
    found = False
    for name, service in sorted(data.get("services", {}).items()):
        for port in service.get("ports") or []:
            found = True
            host = port.get("host_ip", "")
            published = port.get("published", "?")
            target = port.get("target", "?")
            if host == "127.0.0.1":
                print(f"  [PASS] {name} {host}:{published} -> {target}")
            else:
                shown = host or "0.0.0.0 (all interfaces)"
                print(f"  [FAIL] {name} binds {shown}:{published}, reachable from the LAN")
                ok = False

    if not found:
        print("  [WARN] no published ports")
    return 0 if ok else 1


if __name__ == "__main__":
    args = sys.argv[1:] or ["compose.yaml"]
    sys.exit(main(args))
