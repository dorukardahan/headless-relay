#!/usr/bin/env python3
"""Kimi-only, native-auth relay; cwd/skills reduction, NOT an OS sandbox.

Requires POSIX process groups and waitid(WNOWAIT). Keep the child leader owned
and UNREAPED until group cancellation finishes, including normal exit. Never
poll()/wait()/communicate() before killpg: those may free the leader's PID.
Inherited HOME/config/env remain intentional; only the CLI owns native auth.
"""
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time


def non_git(path):
    """Check physical ancestors, independent of inherited Git discovery settings."""
    for parent in (path, *path.parents):
        if os.path.lexists(parent / '.git') or (
            (parent / 'HEAD').exists() and (parent / 'objects').is_dir() and (parent / 'refs').is_dir()
        ):
            return False
    return True


def cancel_owned_group(proc):
    """TERM then KILL before reaping; an exited zombie still pins its PID/PGID."""
    # This function is called exactly once, and no other code reaps this child.
    if os.getpgid(proc.pid) != proc.pid:
        raise RuntimeError('Kimi leader no longer owns its process group')
    os.killpg(proc.pid, signal.SIGTERM)
    time.sleep(.2)
    # Do not wait/poll in the grace period: TERM can exit the leader while a
    # descendant ignores it. The unreaped leader prevents PGID reuse here.
    if os.getpgid(proc.pid) != proc.pid:
        raise RuntimeError('Kimi process-group ownership changed')
    os.killpg(proc.pid, signal.SIGKILL)
    return proc.wait()


def main():
    args = sys.argv[1:]
    from_file = bool(args and args[0] == '--file')
    if args and args[0] in ('--file', '--inline'):
        args = args[1:]
    if not 1 <= len(args) <= 3:
        print('kimi-relay: usage: [--inline|--file] PROMPT_OR_FILE [MODEL] [text|stream-json]', file=sys.stderr)
        return 2
    model = (args[1] if len(args) > 1 else '') or os.environ.get('HEADLESS_RELAY_KIMI_MODEL') or 'kimi-code/k3'
    output = (args[2] if len(args) > 2 else '') or 'text'
    limit = os.environ.get('HEADLESS_RELAY_KIMI_TIMEOUT_SECONDS', '600')
    if output not in ('text', 'stream-json') or not re.fullmatch(r'[0-9]+', limit) or len(limit) > 9 or int(limit) == 0:
        print('kimi-relay: invalid format or positive-integer timeout', file=sys.stderr)
        return 2
    if os.name != 'posix' or not all(hasattr(os, name) for name in ('waitid', 'WNOWAIT', 'WEXITED', 'WNOHANG', 'P_PID')):
        print('kimi-relay: POSIX waitid(WNOWAIT) required; refusing', file=sys.stderr)
        return 1
    if from_file:
        fd = os.open(args[0], os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        with os.fdopen(fd, 'rb') as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                print('kimi-relay: prompt source must be a regular file', file=sys.stderr)
                return 2
            payload = source.read(32769)
    else:
        payload = args[0].encode('utf-8')
    if len(payload) > 32768 or b'\0' in payload:
        print('kimi-relay: prompt must be UTF-8 without NUL and at most 32 KiB; no truncation', file=sys.stderr)
        return 2
    prompt = payload.decode('utf-8')
    # Preserve caller-side lookup semantics for both Kimi and env-shebang tools.
    # Empty PATH entries mean the caller cwd, not the later isolated cwd.
    search_path = os.pathsep.join(os.path.abspath(entry or os.curdir)
                                  for entry in os.environ.get('PATH', os.defpath).split(os.pathsep))
    kimi_binary = shutil.which('kimi', path=search_path)
    if kimi_binary is None:
        print('kimi-relay: Kimi executable unavailable; refusing', file=sys.stderr)
        return 1
    child_env = {**os.environ, 'PATH': search_path}
    # Kimi has no stdin prompt route: refuse before launch if inherited env/argv
    # leave insufficient OS exec budget, even for an otherwise bounded prompt.
    argv_bytes = sum(len(os.fsencode(v)) + 1 for v in (prompt, model, output))
    env_bytes = sum(len(os.fsencode(k)) + len(os.fsencode(v)) + 2 for k, v in child_env.items())
    if argv_bytes + env_bytes + 8192 > os.sysconf('SC_ARG_MAX'):
        print('kimi-relay: insufficient OS argument budget; refusing', file=sys.stderr)
        return 2
    stopped = 0

    def on_signal(signum, _frame):
        nonlocal stopped
        stopped = stopped or signum

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, on_signal)
    # Ignored SIGCHLD survives exec and enables kernel auto-reaping on POSIX.
    # Establish the ownership prerequisite before spawning our sole child.
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    # Resolve BEFORE the child's cwd changes; honour relative TMPDIR explicitly.
    temp_root = Path(os.environ.get('TMPDIR') or tempfile.gettempdir()).resolve(strict=True)
    result = None
    status = None
    with tempfile.TemporaryDirectory(prefix='kimi-iso.', dir=str(temp_root)) as temp:
        cwd = Path(temp).resolve(strict=True)
        if not non_git(cwd):
            print('kimi-relay: temporary cwd is inside a git repository; refusing', file=sys.stderr)
            result = 1
        elif stopped:
            result = 128 + stopped
        else:
            skills = cwd / 'skills'
            skills.mkdir(mode=0o700)
            proc = subprocess.Popen([kimi_binary, '--skills-dir', str(skills), '-m', model,
                                     '-p', prompt, '--output-format', output], cwd=str(cwd),
                                    env=child_env, stdin=subprocess.DEVNULL, start_new_session=True)
            deadline = time.monotonic() + int(limit)
            try:
                while True:
                    if stopped:
                        result = 128 + stopped
                        break
                    # Observe exit without reaping the leader (and freeing its PID).
                    exited = os.waitid(os.P_PID, proc.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                    if exited is not None:
                        break
                    if time.monotonic() >= deadline:
                        result = 124
                        break
                    time.sleep(.02)
            finally:
                status = cancel_owned_group(proc)
    # Select status only AFTER group cancellation AND temporary-directory cleanup.
    # Preserve a timeout/cancellation established before cleanup; otherwise account
    # for a newly received signal instead of returning an earlier success/error.
    if result is not None and (result == 124 or result >= 128):
        return result
    if stopped:
        return 128 + stopped
    if result is not None:
        return result
    if status is None:
        raise RuntimeError('Kimi exit status was not collected')
    return status if status >= 0 else 128 - status


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print('kimi-relay: refusing: ' + str(exc), file=sys.stderr)
        raise SystemExit(1)
