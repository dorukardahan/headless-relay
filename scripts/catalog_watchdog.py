#!/usr/bin/env python3
"""Run a catalog CLI in a new process group with a hard timeout.

Used by print-model-catalog.sh. Never pass secrets on argv: Grok API-key
mode inherits XAI_API_KEY / GROK_CODE_XAI_API_KEY from the environment and
injects it only into the child's env.

On timeout, INT, or TERM: SIGTERM the whole group, then SIGKILL remaining
members even if the leader already exited (forked workers that ignore TERM).
"""
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys


def reap_group(proc: subprocess.Popen, pgid: int) -> None:
    """TERM then KILL the process group. Leader exit is not enough."""
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
    except Exception:
        pass
    # Leader may have died while a worker ignored TERM. Probe the group.
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return
    except OSError:
        pass
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        return
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
    except Exception:
        pass


def run(cmd: list[str], timeout: int, cwd: str | None = None, env: dict | None = None) -> tuple[int, str]:
    proc: subprocess.Popen | None = None
    pgid: int | None = None

    def _on_signal(signum: int, _frame) -> None:
        if proc is not None and pgid is not None:
            reap_group(proc, pgid)
        sys.exit(128 + signum)

    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            start_new_session=True,
        )
        pgid = os.getpgid(proc.pid)
    except Exception:
        return 1, ""
    try:
        out, _err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        reap_group(proc, pgid)
        return 124, ""
    except Exception:
        reap_group(proc, pgid)
        return 1, ""
    return (0 if proc.returncode == 0 else (proc.returncode or 1)), (out or "")


def grok_env(home: str, auth_path: str) -> dict[str, str]:
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": home,
        "GROK_HOME": home,
        "TMPDIR": home,
        "TERM": "dumb",
        "GROK_TELEMETRY_ENABLED": "false",
        "GROK_TELEMETRY_TRACE_UPLOAD": "false",
        "GROK_EXTERNAL_OTEL": "false",
    }
    if auth_path:
        env["GROK_AUTH_PATH"] = auth_path
    else:
        key = os.environ.get("XAI_API_KEY") or os.environ.get("GROK_CODE_XAI_API_KEY") or ""
        if not key:
            raise SystemExit(1)
        env["XAI_API_KEY"] = key
    return env


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, required=True)
    parser.add_argument("--cwd")
    parser.add_argument("--hermetic-home", help="build the isolated Grok env with this HOME/GROK_HOME")
    parser.add_argument("--auth-path", default="", help="GROK_AUTH_PATH; omit to use XAI_API_KEY from env")
    parser.add_argument("cmd", nargs="+")
    args = parser.parse_args()
    env = None
    cwd = args.cwd
    if args.hermetic_home:
        env = grok_env(args.hermetic_home, args.auth_path)
        cwd = cwd or args.hermetic_home
    rc, out = run(args.cmd, args.timeout, cwd=cwd, env=env)
    sys.stdout.write(out)
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
