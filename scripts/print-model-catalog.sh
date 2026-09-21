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
# No dependencies beyond POSIX sh + python3 (Codex JSON + per-lane watchdogs
# in scripts/catalog_watchdog.py). Perl is not required.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WATCHDOG="$ROOT/scripts/catalog_watchdog.py"

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
if [ ! -f "$WATCHDOG" ]; then
  echo "missing $WATCHDOG"
  exit 1
fi

# Bound a catalog CLI: print stdout on success, else empty. Never hangs the script.
# catalog_watchdog.py starts a new process group, TERMs then KILLs remaining
# members even if the leader already exited, and reaps on INT/TERM.
# Usage: _out=$(run_to SECS CMD [args...]) || _out=
# Never pass secrets as CMD args — they land in the watchdog argv.
run_to() {
  _secs=$1
  shift
  python3 "$WATCHDOG" --timeout "$_secs" -- "$@"
}

# Isolated Grok catalog. Seconds, grokbin, iso dir, synthetic home, optional auth path.
# API key is inherited from this shell's environment — never placed in argv.
run_grok_catalog() {
  _secs=$1
  _bin=$2
  _iso=$3
  _home=$4
  _auth=${5:-}
  if [ -n "$_auth" ]; then
    python3 "$WATCHDOG" --timeout "$_secs" --cwd "$_iso" \
      --hermetic-home "$_home" --auth-path "$_auth" -- \
      "$_bin" models
  else
    python3 "$WATCHDOG" --timeout "$_secs" --cwd "$_iso" \
      --hermetic-home "$_home" -- \
      "$_bin" models
  fi
}

# Availability ladder: a catalog is real only if it lists models.
accept_grok_catalog() {
  printf '%s\n' "$1" | grep -qE 'Available models:|Default model:'
}

# --- Codex ---
echo "## Codex (\`codex debug models\`)"
if have codex; then
  echo "binary: $(command -v codex)"
  _ver=$(run_to 5 codex --version) || _ver=
  echo "version: $(printf '%s\n' "$_ver" | head -n 1 || echo unknown)"
  _raw=$(run_to 20 codex debug models) || _raw=
  if [ -z "$_raw" ]; then
    echo "skip: catalog command failed or timed out"
  else
    printf '%s\n' "$_raw" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
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
'
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
  _gh=
  _iso=
  _cleanup_grok_tmp() {
    [ -n "${_gh:-}" ] && rm -rf "$_gh"
    [ -n "${_iso:-}" ] && rm -rf "$_iso"
    _gh=
    _iso=
  }
  _stop_grok() {
    _cleanup_grok_tmp
    trap - EXIT INT TERM HUP
    exit "$1"
  }
  trap '_stop_grok 130' INT
  trap '_stop_grok 143' TERM
  trap '_stop_grok 129' HUP
  trap '_cleanup_grok_tmp' EXIT
  _gh=$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX") || _gh=
  _iso=$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX") || _iso=
  # mktemp may return a relative path when TMPDIR is relative. Absolutize
  # before the watchdog cds into $_iso — otherwise Grok resolves HOME from
  # inside that dir and misses the synthetic home we created.
  [ -n "$_gh" ] && _gh=$(cd "$_gh" && pwd)
  [ -n "$_iso" ] && _iso=$(cd "$_iso" && pwd)
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
    # Key stays in this shell env; catalog_watchdog inherits it. Never argv.
    _out=$(run_grok_catalog 40 "$_grokbin" "$_iso" "$_gh") || _out=
    if accept_grok_catalog "$_out"; then
      printf '%s\n' "$_out"
    else
      echo "skip: isolated \`grok models\` (API-key) failed, timed out, or printed no model list"
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
        # Absolutize before isolation — same rule as grok_relay.
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
      if accept_grok_catalog "$_out"; then
        printf '%s\n' "$_out"
      else
        echo "skip: isolated \`grok models\` failed, timed out, or printed no model list"
      fi
    elif [ -n "$_ap" ]; then
      echo "skip: no readable auth file at the resolved path (set GROK_AUTH_PATH or run grok login)"
    fi
  fi
  _cleanup_grok_tmp
  trap - EXIT INT TERM HUP
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
