#!/usr/bin/env python3
"""Run a catalog CLI in a new process group with a hard timeout.

Used by print-model-catalog.sh. Never pass secrets on argv: Grok API-key
mode inherits XAI_API_KEY / GROK_CODE_XAI_API_KEY from the environment and
injects it only into the child's env.

On timeout, INT, TERM, or HUP: SIGTERM the whole group, then SIGKILL remaining
members, but only while this process still owns the group (pgid == leader pid).
After the catalog CLI's own normal/nonzero exit the watchdog does NOT signal
the group — the leader is already reaped and that pgid could be reused
(same rule as grok_relay; see SECURITY.md).
"""
import argparse
import os
import signal
import subprocess
import sys


def reap_group(proc, pgid):
    """TERM then KILL the process group, only while we still own it.

    Must be called while the leader is still this process's child. After
    wait/communicate has reaped the leader, do not signal the pgid — it
    may already belong to someone else (SECURITY.md descendant-cleanup).
    """
    if proc is None or pgid is None:
        return
    if proc.poll() is not None:
        return
    try:
        live_pgid = os.getpgid(proc.pid)
    except OSError:
        return
    if live_pgid != proc.pid or live_pgid != pgid:
        return
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
        return
    except Exception:
        pass
    try:
        if os.getpgid(proc.pid) != proc.pid:
            return
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        return
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
    except Exception:
        pass


def run(cmd, timeout, cwd=None, env=None):
    # Runtime-plain values so python3.9 (and the advertised unversioned
    # python3) can import this module. No PEP 604 unions.
    proc = None
    pgid = None

    def _on_signal(signum: int, _frame) -> None:
        if proc is not None and pgid is not None:
            reap_group(proc, pgid)
        sys.exit(128 + signum)

    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, _on_signal)
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
    # Leader already reaped. Do not killpg — pgid may have been reused.
    return (0 if proc.returncode == 0 else (proc.returncode or 1)), (out or "")


def grok_env(home, auth_path):
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
    parser.add_argument("cmd", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    env = None
    cwd = args.cwd
    if args.hermetic_home:
        env = grok_env(args.hermetic_home, args.auth_path)
        cwd = cwd or args.hermetic_home
    if not args.cmd or args.cmd == ["--"]:
        parser.error("missing catalog command")
    cmd = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
    rc, out = run(cmd, args.timeout, cwd=cwd, env=env)
    sys.stdout.write(out)
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
