#!/bin/sh
# shellcheck disable=SC2016
# Regression contract for the first-class Kimi K3 lane.
#
# The Kimi lane must use Moonshot's native `kimi` CLI and its own OAuth store. OpenCode remains
# the independent GLM transport and every documented OpenCode GLM invocation stays pinned to
# zai-coding-plan/glm-5.2. Users may override Kimi's model alias without changing the GLM model.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/headless-relay-kimi-check.XXXXXX")" || {
  echo "FAIL: could not create a private regression workspace" >&2
  exit 1
}
trap 'rm -rf "$CHECK_TMP" 2>/dev/null' EXIT HUP INT TERM
fail=0

need() { # file substring
  if ! grep -qF "$2" "$ROOT/$1" 2>/dev/null; then
    echo "FAIL: missing Kimi contract in $1: \"$2\""
    fail=1
  fi
}

# The single-quoted values below are literal documentation anchors, not shell expressions.
need "README.md"                   "Six model lanes ship ready to use"
need "README.md"                   "Kimi K3"
need "SKILL.md"                    "## The six targets"
need "SKILL.md"                    '| Kimi K3 | `kimi` (Kimi Code CLI) | `kimi -p` |'
need "SKILL.md"                    "Kimi OAuth and OpenCode/Z.AI auth are separate"
need "SKILL.md"                    'KIMI_MODEL="${HEADLESS_RELAY_KIMI_MODEL:-kimi-code/k3}"'
need "SKILL.md"                    'kimi_relay() ('
need "SKILL.md"                    'kimi_relay "your question here" "kimi-code/k3"'
need "SKILL.md"                    'For a generic "ask Kimi" request with no model named, use the configured override:'
need "SKILL.md"                    "perl -e 'alarm shift; exec @ARGV' \"\$limit\" kimi --skills-dir \"\$skills\""
need "SKILL.md"                    'Never invoke `kimi_relay` from cron, a scheduler, or an unattended batch.'
need "SKILL.md"                    "never reads, copies, moves, or rewrites Kimi's OAuth files"
need "SKILL.md"                    '`$KIMI_CODE_HOME/AGENTS.md` and'
need "SKILL.md"                    '`~/.agents/AGENTS.md` from the user'
need "SKILL.md"                    'opencode run -m "zai-coding-plan/glm-5.2" --variant max'
need "SKILL.md"                    'kimi login'
need "references/cli-reference.md" "## Kimi K3 — kimi print mode"
need "references/cli-reference.md" "Node.js 22.19.0 or later"
need "references/cli-reference.md" 'kimi_relay "List changed files" "$KIMI_MODEL" stream-json'
need "references/cli-reference.md" 'opencode run --attach http://localhost:4096 -m "zai-coding-plan/glm-5.2"'
need "references/anthropic-terms.md" '| Moonshot AI (Kimi) |'
need "references/custom-targets.md"  'built-in lanes (GPT, GLM, Kimi K3, Grok, Gemini, Claude)'

# A Kimi user override must never turn into an OpenCode/GLM override. Keep the GLM examples fixed.
if grep -E 'opencode run .*(-m|--model)[[:space:]]+.*(HEADLESS_RELAY_KIMI_MODEL|KIMI_MODEL|[Kk]imi|kimi-for-coding|moonshot)' \
    "$ROOT/SKILL.md" "$ROOT/references/cli-reference.md" >/dev/null 2>&1; then
  echo "FAIL: Kimi routing leaked into the OpenCode/GLM lane"
  fail=1
fi

# Every executable OpenCode GLM example must name the fixed Coding Plan model.
if awk '
  /^[[:space:]]*```bash[[:space:]]*$/ { in_bash=1; next }
  /^[[:space:]]*```/ { in_bash=0; next }
  in_bash && /opencode run/ && $0 !~ /^[[:space:]]*#/ &&
    $0 !~ /zai-coding-plan\/glm-5\.2/ { print NR ":" $0; bad=1 }
  END { exit bad }
' "$ROOT/SKILL.md" "$ROOT/references/cli-reference.md" >"$CHECK_TMP/glm"; then
  :
else
  echo "FAIL: unpinned executable OpenCode GLM example(s) in SKILL.md:"
  cat "$CHECK_TMP/glm"
  fail=1
fi

# Text-only copy/paste examples must not execute native print mode in the caller's cwd. The one
# raw `kimi ... -p` line allowed in a bash fence is the helper's guarded temp-CWD invocation.
if awk '
  /^[[:space:]]*```bash[[:space:]]*$/ { in_bash=1; next }
  /^[[:space:]]*```/ { in_bash=0; next }
  in_bash && /(^|[[:space:]&(])kimi[[:space:]].*-p([[:space:]]|$)/ &&
    $0 !~ /perl .* kimi .* -p/ { print FILENAME ":" FNR ":" $0; bad=1 }
  END { exit bad }
' "$ROOT/SKILL.md" "$ROOT/references/cli-reference.md" >"$CHECK_TMP/cwd"; then
  :
else
  echo "FAIL: native Kimi print example bypasses the isolated kimi_relay helper:"
  cat "$CHECK_TMP/cwd"
  fail=1
fi

# Native OAuth belongs to the first-party CLI. Documentation must never contain a fenced shell
# recipe that copies, moves, deletes, or redirects Kimi's auth/config home.
if awk '
  /^[[:space:]]*```bash[[:space:]]*$/ { in_bash=1; next }
  /^[[:space:]]*```/ { in_bash=0; next }
  in_bash && /(cp|mv|rm|install)[[:space:]].*([.]kimi|KIMI_CODE_HOME|kimi.*auth)/ {
    print FILENAME ":" FNR ":" $0; bad=1
  }
  END { exit bad }
' "$ROOT/SKILL.md" "$ROOT/references/cli-reference.md" >"$CHECK_TMP/auth"; then
  :
else
  echo "FAIL: fenced shell recipe mutates or copies Kimi auth/config state:"
  cat "$CHECK_TMP/auth"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: first-class Kimi K3 contract present; native OAuth/model override is isolated from fixed GLM 5.2 routing."
fi
exit "$fail"
