#!/usr/bin/env python3
"""Offline argv contract: execute the shipped Claude block, never a real CLI.

This verifies delegation/argument preservation, NOT vendor settings precedence,
model availability, entitlement, or the model actually served.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def shipped(text):
    blocks = re.findall(r"```bash\n(.*?)\n```", text, re.S)
    helpers = [b for b in blocks if "HEADLESS_RELAY_CLAUDE_MODEL" in b]
    if len(helpers) != 1:
        raise AssertionError("expected exactly one shipped Claude selection block")
    calls = re.findall(r'^(?:claude|claude_relay) -p "your question here"[^\n]*', text, re.M)
    if len(calls) != 1:
        raise AssertionError("expected exactly one shipped baseline call")
    return helpers[0], calls[0]


def contract(text):
    helper, call = shipped(text)
    failures = []
    count = 0
    # Each profile/settings state must be left to Claude, not reimplemented here.
    states = {
        "user": {"home": '{"model":"user-full[1m]"}'},
        "project": {"home": '{"model":"user"}', "project": '{"model":"project[1m]"}'},
        "local": {"home": '{"model":"user"}', "project": '{"model":"project"}', "local": '{"model":"local[1m]"}'},
        "native-env": {"home": '{"model":"user"}', "env_model": "env-full[1m]"},
        "profile-full": {"home": '{"model":"foreign-home"}', "profile": '{"model":"profile[1m]"}'},
        "profile-empty": {"home": '{"model":"foreign-home"}', "profile": "{}"},
        "profile-missing": {"home": '{"model":"foreign-home"}', "profile": None},
        "profile-malformed": {"home": '{"model":"foreign-home"}', "profile": "{bad-json"},
        "empty-model": {"home": '{"model":""}'},
        "malformed-user": {"home": "{bad-json"},
        "no-settings": {},
    }
    with tempfile.TemporaryDirectory(prefix="claude-argv-", dir=os.environ.get("TMPDIR")) as tmp:
        base = Path(tmp)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        # Resolve the active interpreter via PATH; a spaced path is invalid in a shebang.
        (bin_dir / "python3").symlink_to(sys.executable)
        stub = bin_dir / "claude"
        stub.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\nPath(os.environ['ARGV_RECEIPT']).write_text(json.dumps({'argv':sys.argv[1:], 'native_model':os.environ.get('ANTHROPIC_MODEL'), 'config_dir':os.environ.get('CLAUDE_CONFIG_DIR')}))\nsys.exit(int(os.environ.get('STUB_RC', '0')))\n")
        stub.chmod(0o700)
        # No jq is on PATH. A poison jq in separate runs detects parser dependence.
        poison = base / "poison"
        poison.mkdir()
        (poison / "jq").write_text("#!/bin/sh\nprintf 'unexpected settings parser\\n' >&2\nexit 91\n")
        (poison / "jq").chmod(0o700)
        shells = ["/bin/sh", "/bin/bash"]
        for name, state in states.items():
            case = base / name
            home, project, profile = case / "home", case / "project", case / "profile"
            for folder in (home / ".claude", project / ".claude", profile):
                folder.mkdir(parents=True)
            for key, target in (("home", home / ".claude/settings.json"), ("project", project / ".claude/settings.json"), ("local", project / ".claude/settings.local.json"), ("profile", profile / "settings.json")):
                if state.get(key) is not None:
                    target.write_text(state[key])
            overrides = [None, "", "account-full[1m]", "opaque id [1m] ' \" $HOME; *\nsecond-line"]
            for shell in shells:
                for strict in (False, True):
                    for parser in (False, True):
                        for override in overrides:
                            env = {"HOME": str(home), "PATH": str(bin_dir) + (":" + str(poison) if parser else ""), "ARGV_RECEIPT": str(case / "argv.json")}
                            if "profile" in state:
                                env["CLAUDE_CONFIG_DIR"] = str(profile)
                            if "env_model" in state:
                                env["ANTHROPIC_MODEL"] = state["env_model"]
                            if override is not None:
                                env["HEADLESS_RELAY_CLAUDE_MODEL"] = override
                            receipt = Path(env["ARGV_RECEIPT"])
                            receipt.unlink(missing_ok=True)
                            run = subprocess.run([shell, "-c", ("set -eu\n" if strict else "") + helper + "\n" + call], env=env, cwd=project, capture_output=True, text=True, timeout=5)
                            expected = ["-p", "your question here"] + (["--model", override] if override else [])
                            actual = json.loads(receipt.read_text(encoding="utf-8")) if receipt.exists() else {}
                            count += 1
                            if run.returncode or run.stderr or actual.get("argv") != expected or actual.get("native_model") != env.get("ANTHROPIC_MODEL") or actual.get("config_dir") != env.get("CLAUDE_CONFIG_DIR"):
                                failures.append(f"{name}/{Path(shell).name}/strict={strict}/parser={parser}/override={override!r}: rc={run.returncode}, expected={expected!r}, actual={actual!r}, stderr={run.stderr!r}")
        # Preserve caller arguments, resume selection, and native failure status.
        home = base / "no-settings/home"
        project = base / "no-settings/project"
        if "claude_relay()" in helper:
            for shell in shells:
                for override in (None, "exact-full[1m]"):
                    env = {"HOME": str(home), "PATH": str(bin_dir), "ARGV_RECEIPT": str(base / "resume.json"), "STUB_RC": "23"}
                    if override:
                        env["HEADLESS_RELAY_CLAUDE_MODEL"] = override
                    command = 'claude_relay -p "follow up" --resume "session-id" --output-format json'
                    run = subprocess.run([shell, "-c", "set -eu\n" + helper + "\n" + command], env=env, cwd=project, capture_output=True, text=True, timeout=5)
                    actual = json.loads(Path(env["ARGV_RECEIPT"]).read_text(encoding="utf-8"))["argv"]
                    expected = ["-p", "follow up", "--resume", "session-id", "--output-format", "json"] + (["--model", override] if override else [])
                    count += 1
                    if actual != expected or run.returncode != 23:
                        failures.append(f"resume/{Path(shell).name}: expected argv={expected!r} rc=23; got argv={actual!r} rc={run.returncode}")
    return count, failures


def main():
    text = (ROOT / "SKILL.md").read_text(encoding="utf-8")
    count, failures = contract(text)
    if failures:
        print(f"FAIL: {len(failures)}/{count} Claude argv cases")
        for failure in failures[:6]:
            print(failure)
        return 1
    print(f"OK: {count} shipped Claude argv cases; native selection delegated, opaque override preserved")
    # Semantic mutations must fail against the same actual-block harness.
    mutations = {
        "forced default": ('claude "$@"\n', 'claude "$@" --model always-wrong\n'),
        "lost override": ('--model "$HEADLESS_RELAY_CLAUDE_MODEL"', '--model always-wrong'),
        "split override": ('--model "$HEADLESS_RELAY_CLAUDE_MODEL"', '--model $HEADLESS_RELAY_CLAUDE_MODEL'),
    }
    for name, (old, new) in mutations.items():
        if text.count(old) != 1:
            raise AssertionError(f"mutation anchor missing or ambiguous: {name}")
        _, broken = contract(text.replace(old, new))
        if not broken:
            raise AssertionError(f"mutation survived: {name}")
        print(f"OK: mutation rejected: {name}")
    # Generic examples use the tested helper; the deliberate capability probe stays explicit.
    ref = (ROOT / "references/cli-reference.md").read_text(encoding="utf-8")
    for name, doc in (("SKILL.md", text), ("references/cli-reference.md", ref)):
        if re.search(r'^\s*(?:result=\$\(|sid=\$\()?claude -p ', doc, re.M):
            raise AssertionError(f"untested generic raw Claude call in {name}")
    if '"--model", "claude-opus-5-5"' not in ref or '"modelUsage"' not in ref:
        raise AssertionError("deliberate served-model capability probe was lost")
    print("OK: generic examples use tested helper; explicit capability probe retained")
    return 0


if __name__ == "__main__":
    sys.exit(main())
