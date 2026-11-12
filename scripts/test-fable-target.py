#!/usr/bin/env python3
"""Offline contract for the shipped fable_relay helper: execute the SKILL.md block with a
`claude` argv stub, never a real CLI. It checks the model, effort, the ultrathink keyword,
the effort environment variable, overrides and passthrough; not the model actually served.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SHELLS = ["/bin/sh", "/bin/bash"]


def shipped(text):
    blocks = [b for b in re.findall(r"```bash\n(.*?)\n```", text, re.S) if "fable_relay() (" in b]
    if len(blocks) != 1:
        raise AssertionError("expected exactly one shipped fable_relay block")
    return blocks[0]


def cases():
    # name, prompt file text (None = missing file), extra env, extra args, expected argv tail, effort env, rc
    plain = "Review the plan below.\n\nStep 1."
    yield "default", plain, {}, [], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\n" + plain], "max", 0
    yield "already-first", "ultrathink\nReview it.", {}, [], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\nReview it."], "max", 0
    yield "keyword-later", "Review it. ultrathink", {}, [], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\nReview it. ultrathink"], "max", 0
    yield "prefix-word", "ultrathinking is not the keyword", {}, [], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\nultrathinking is not the keyword"], "max", 0
    yield "passthrough", plain, {}, ["--tools", "", "--output-format", "json"], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\n" + plain, "--tools", "", "--output-format", "json"], "max", 0
    yield "parent-effort-low", plain, {"CLAUDE_CODE_EFFORT_LEVEL": "low"}, [], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\n" + plain], "max", 0
    yield "overrides", plain, {"HEADLESS_RELAY_FABLE_MODEL": "claude-fable-5-2[1m]", "HEADLESS_RELAY_FABLE_EFFORT": "xhigh"}, [], ["--model", "claude-fable-5-2[1m]", "--effort", "xhigh", "-p", "ultrathink\n" + plain], "xhigh", 0
    yield "exit-status", plain, {"STUB_RC": "23"}, [], ["--model", "claude-fable-5-2", "--effort", "max", "-p", "ultrathink\n" + plain], "max", 23
    yield "missing-file", None, {}, [], None, None, 2


def contract(helper):
    failures, count = [], 0
    with tempfile.TemporaryDirectory(prefix="fable-argv-", dir=os.environ.get("TMPDIR")) as tmp:
        base = Path(tmp)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        (bin_dir / "python3").symlink_to(sys.executable)
        stub = bin_dir / "claude"
        stub.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\n"
                        "Path(os.environ['ARGV_RECEIPT']).write_text(json.dumps({'argv': sys.argv[1:], 'effort_env': os.environ.get('CLAUDE_CODE_EFFORT_LEVEL')}))\n"
                        "sys.exit(int(os.environ.get('STUB_RC', '0')))\n")
        stub.chmod(0o700)
        for name, prompt, extra_env, args, want_argv, want_env, want_rc in cases():
            pf = base / f"{name}.md"
            if prompt is not None:
                pf.write_text(prompt + "\n")
            for shell in SHELLS:
                for strict in (False, True):
                    receipt = base / "argv.json"
                    receipt.unlink(missing_ok=True)
                    env = {"HOME": str(base), "PATH": str(bin_dir) + ":/usr/bin:/bin", "ARGV_RECEIPT": str(receipt), **extra_env}
                    quoted = " ".join("'" + a.replace("'", "'\\''") + "'" for a in args)
                    script = ("set -eu\n" if strict else "") + helper + f"\nfable_relay '{pf}' {quoted}\n"
                    run = subprocess.run([shell, "-c", script], env=env, capture_output=True, text=True, timeout=10)
                    got = json.loads(receipt.read_text()) if receipt.exists() else None
                    count += 1
                    tag = f"{name}/{Path(shell).name}/strict={strict}"
                    if run.returncode != want_rc:
                        failures.append(f"{tag}: rc {run.returncode} != {want_rc}; stderr={run.stderr!r}")
                    elif want_argv is None:
                        if got is not None:
                            failures.append(f"{tag}: claude ran despite a missing prompt file")
                    elif got is None or got["argv"] != want_argv or got["effort_env"] != want_env:
                        failures.append(f"{tag}: expected argv={want_argv!r} env={want_env!r}; got {got!r}")
    return count, failures


def main():
    text = (ROOT / "SKILL.md").read_text(encoding="utf-8")
    helper = shipped(text)
    count, failures = contract(helper)
    if failures:
        print(f"FAIL: {len(failures)}/{count} fable_relay cases")
        for f in failures[:8]:
            print(f)
        return 1
    print(f"OK: {count} fable_relay cases (sh/bash, plain and set -eu)")
    mutations = {
        "no ultrathink": ('    *) p="ultrathink\n$p" ;;', '    *) ;;'),
        "no effort env": ("CLAUDE_CODE_EFFORT_LEVEL=$e claude", "claude"),
        "no effort flag": (' --effort "$e"', ""),
        "wrong default model": ("claude-fable-5-2}", "claude-fable-5-1}"),
        "args dropped": ('-p "$p" "$@"', '-p "$p"'),
    }
    for name, (old, new) in mutations.items():
        if helper.count(old) != 1:
            raise AssertionError(f"mutation anchor missing or ambiguous: {name}")
        _, broken = contract(helper.replace(old, new))
        if not broken:
            raise AssertionError(f"mutation survived: {name}")
        print(f"OK: mutation rejected: {name}")
    ref = (ROOT / "references/reprompter-relay.md").read_text(encoding="utf-8")
    if "Fable 5.2" not in ref or "ultrathink" not in ref or "fable_relay" not in ref:
        raise AssertionError("reprompter-relay.md lost the Fable 5.2 rule")
    print("OK: reprompter rule for the Fable 5.2 lane is documented")
    return 0


if __name__ == "__main__":
    sys.exit(main())
