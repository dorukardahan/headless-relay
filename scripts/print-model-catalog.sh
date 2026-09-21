#!/bin/sh
# print-model-catalog.sh — list model ids THIS machine's CLIs currently serve.
#
# WHY. headless-relay example pins go stale every vendor launch. Do not copy ids
# out of README/SKILL as if they were a live menu. This script asks each
# installed CLI for its catalog and prints a dated, machine-local snapshot.
#
# WHAT IT IS NOT. It does not start a model turn, does not refresh vendor blogs,
# and does not update SKILL.md. Missing binaries are skipped. A lane that is
# installed but whose catalog command fails is reported as skipped, not as an
# empty menu.
# Grok subscription catalog (`grok models` with GROK_AUTH_PATH) MAY refresh an
# expired access token in place on that auth.json — the CLI writes
# `auth update disk written`. API-key mode (`XAI_API_KEY`) does not touch the
# file. This is a catalog fetch, not a credential-free guarantee.
#
# Codex: use `codex debug models` (JSON). Never `codex models` — on the 0.144
# series that is not a catalog subcommand and starts an interactive session.
#
# No dependencies beyond POSIX sh + python3 (Codex JSON + per-lane watchdogs).
# Perl is not required.

set -eu

echo "# headless-relay local model catalog"
echo
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(uname -n 2>/dev/null || echo unknown)"
echo "This list is what THIS machine sees. It is not a published product menu."
echo "Do not commit it as the skill's source of truth."
echo

have() { command -v "$1" >/dev/null 2>&1; }

if ! have python3; then
  echo "python3 is required (Codex JSON parse + catalog watchdogs)."
  exit 1
fi

# Bound a catalog CLI: print stdout on success, else empty. Never hangs the script.
# Starts the command in its own process group and reaps the group on timeout
# (agy/grok workers that fork would otherwise outlive subprocess.run's child).
# Usage: _out=$(run_to SECS CMD [args...]) || _out=
# Never pass secrets as CMD args — they land in the watchdog argv.
run_to() {
  python3 - "$@" <<'PY'
import os, signal, subprocess, sys
secs = int(sys.argv[1])
cmd = sys.argv[2:]
try:
    p = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        start_new_session=True,
    )
except Exception:
    sys.exit(1)

def _reap_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass

try:
    out, _err = p.communicate(timeout=secs)
except subprocess.TimeoutExpired:
    _reap_group(p)
    sys.exit(124)
except Exception:
    _reap_group(p)
    sys.exit(1)
sys.stdout.write(out or "")
sys.exit(0 if p.returncode == 0 else (p.returncode or 1))
PY
}

# Isolated Grok catalog. Seconds, grokbin, iso dir, synthetic home, optional auth path.
# API key is inherited from this shell's environment — never placed in argv.
run_grok_catalog() {
  python3 - "$1" "$2" "$3" "$4" "${5:-}" <<'PY'
import os, signal, subprocess, sys
secs, grokbin, iso, home, auth_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
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
        sys.exit(1)
    env["XAI_API_KEY"] = key
try:
    p = subprocess.Popen(
        [grokbin, "models"],
        cwd=iso,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        start_new_session=True,
    )
except Exception:
    sys.exit(1)

def _reap_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass

try:
    out, _err = p.communicate(timeout=int(secs))
except subprocess.TimeoutExpired:
    _reap_group(p)
    sys.exit(124)
except Exception:
    _reap_group(p)
    sys.exit(1)
sys.stdout.write(out or "")
sys.exit(0 if p.returncode == 0 else (p.returncode or 1))
PY
}

# --- Codex ---
echo "## Codex (\`codex debug models\`)"
if have codex; then
  echo "binary: $(command -v codex)"
  echo "version: $(codex --version 2>/dev/null | head -n 1 || echo unknown)"
  if python3 - <<'PY'
import json, subprocess, sys
try:
    p = subprocess.run(
        ["codex", "debug", "models"],
        capture_output=True, text=True, timeout=20,
    )
except Exception as e:
    print("skip: %s" % type(e).__name__)
    sys.exit(0)
if p.returncode != 0:
    print("skip: catalog command failed")
    sys.exit(0)
try:
    data = json.loads(p.stdout or "")
except json.JSONDecodeError:
    print("skip: catalog was not JSON")
    sys.exit(0)
# Schema (codex-cli 0.144): {"models": [{"slug": "gpt-5.6-sol", "priority": ..., ...}, ...]}
# Take each model-entry slug (or id). Do not walk nested fields — that picks up
# metadata values and drops short slugs such as o3.
models = data.get("models") if isinstance(data, dict) else None
if not isinstance(models, list):
    print("skip: catalog has no models list")
    sys.exit(0)
ids = []
for m in models:
    if not isinstance(m, dict):
        continue
    slug = m.get("slug") or m.get("id")
    if isinstance(slug, str) and slug.strip() and slug not in ids:
        ids.append(slug)
if not ids:
    print("skip: no model ids in catalog")
    sys.exit(0)
for i in ids:
    print("- %s" % i)
PY
  then
    :
  else
    echo "skip: python3 catalog parse failed"
  fi
  echo
  echo "Do **not** run \`codex models\`. On 0.144 that starts a session."
else
  echo "skip: \`codex\` not on PATH"
fi
echo

# --- Antigravity / Gemini ---
echo "## Gemini (\`agy models\`)"
if have agy; then
  echo "binary: $(command -v agy)"
  _out=$(run_to 20 agy models) || _out=
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out"
  else
    echo "skip: \`agy models\` failed, timed out, or not logged in"
  fi
else
  echo "skip: \`agy\` not on PATH"
fi
echo

# --- Grok ---
# Catalog only. Same hermetic shape as the availability ladder in
# references/cli-reference.md step 2: env -i allowlist, empty HOME, clean temp
# GROK_HOME, 40s python watchdog. Auth is ONE of: XAI_API_KEY (no auth file) OR
# GROK_AUTH_PATH -> auth.json. Not a model turn (no -p). Subscription catalog
# may refresh the named auth.json in place.
echo "## Grok (\`grok models\`)"
if have grok; then
  echo "binary: $(command -v grok)"
  _gh=$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX") || _gh=
  _iso=$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX") || _iso=
  _grokbin=$(command -v grok)
  case "$_grokbin" in
    "") ;;
    /*) ;;
    *)
      if [ "$(pwd)" -ef . ]; then
        _grokbin="$(pwd)/$_grokbin"
      else
        echo "skip: grok binary path is relative and the working directory name is unsafe"
        _grokbin=
      fi
      ;;
  esac
  _key="${XAI_API_KEY:-${GROK_CODE_XAI_API_KEY:-}}"
  if [ -z "$_gh" ] || [ -z "$_iso" ] || [ -z "$_grokbin" ]; then
    [ -z "$_grokbin" ] || echo "skip: mktemp failed"
  elif [ -n "$_key" ]; then
    # Key stays in this shell env; run_grok_catalog inherits it. Never argv.
    _out=$(run_grok_catalog 40 "$_grokbin" "$_iso" "$_gh") || _out=
    if [ -n "$_out" ]; then
      printf '%s\n' "$_out"
    else
      echo "skip: isolated \`grok models\` (API-key) failed or timed out"
    fi
  else
    # Subscription branch only: do not expand $HOME until we know we need a file.
    if [ -n "${GROK_AUTH_PATH:-}" ]; then
      _ap="$GROK_AUTH_PATH"
    elif [ -n "${GROK_HOME:-}" ]; then
      _ap="$GROK_HOME/auth.json"
    elif [ -n "${HOME:-}" ]; then
      _ap="$HOME/.grok/auth.json"
    else
      _ap=
    fi
    case "$_ap" in
      "") echo "skip: no XAI_API_KEY and no auth path (set GROK_AUTH_PATH / GROK_HOME / HOME, or run grok login)" ;;
      /*) ;;
      *)
        # Absolutize before cd into $_iso — same rule as grok_relay.
        if [ "$(pwd)" -ef . ]; then
          _ap="$(pwd)/$_ap"
        else
          echo "skip: working directory name is unsafe to prefix onto a relative GROK_AUTH_PATH"
          _ap=
        fi
        ;;
    esac
    if [ -n "$_ap" ] && [ -f "$_ap" ] && [ -r "$_ap" ]; then
      _out=$(run_grok_catalog 40 "$_grokbin" "$_iso" "$_gh" "$_ap") || _out=
      if [ -n "$_out" ]; then
        printf '%s\n' "$_out"
      else
        echo "skip: isolated \`grok models\` failed or timed out"
      fi
    elif [ -n "$_ap" ]; then
      echo "skip: no readable auth file at the resolved path (set GROK_AUTH_PATH or run grok login)"
    fi
  fi
  [ -n "${_gh:-}" ] && rm -rf "$_gh"
  [ -n "${_iso:-}" ] && rm -rf "$_iso"
else
  echo "skip: \`grok\` not on PATH"
fi
echo

# --- Claude (help only; do not start a session) ---
echo "## Claude (aliases from \`claude --help\`; no session)"
if have claude; then
  echo "binary: $(command -v claude)"
  echo "Use \`claude --model <alias>\` with an alias from \`claude --help\` (fable / opus / sonnet) or a full id."
  echo "This script does not start \`claude -p\` and does not list billed models."
else
  echo "skip: \`claude\` not on PATH"
fi
echo

# --- OpenCode / ZCode ---
echo "## GLM"
if have opencode; then
  echo "OpenCode binary: $(command -v opencode)"
  echo "OpenCode has no safe catalog subcommand in this skill's contract. Current Coding Plan flagship pin is \`zai-coding-plan/glm-5.3\` (see SKILL.md). Confirm with the user's OpenCode auth, not a guessed id."
else
  echo "OpenCode: skip (\`opencode\` not on PATH)"
fi
if have zcode; then
  echo "ZCode binary: $(command -v zcode)"
  echo "ZCode recipes pin \`zai/glm-5.3\`. GLM-5.2 is previous generation."
else
  echo "ZCode: skip (\`zcode\` not on PATH)"
fi
echo
echo "Done. Copy an id from this snapshot into a one-shot command; do not paste it back into the skill as a new source of truth."
