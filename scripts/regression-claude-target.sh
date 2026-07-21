#!/bin/sh
# Regression contract for Claude/Fable model routing.
#
# A printable "[1m]" suffix is part of Claude's long-context model id.  It is
# not the ANSI bold sequence (which would start with an ESC byte), so relay
# instructions must preserve it verbatim instead of collapsing it to the
# unavailable bare model.

# shellcheck disable=SC2016
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/headless-relay-claude-check.XXXXXX")" || {
  echo "FAIL: could not create a private regression workspace" >&2
  exit 1
}
trap 'rm -rf "$CHECK_TMP" 2>/dev/null' EXIT HUP INT TERM
fail=0

need() { # file substring
  if ! grep -qF "$2" "$ROOT/$1" 2>/dev/null; then
    echo "FAIL: missing Claude model contract in $1: \"$2\""
    fail=1
  fi
}

forbid() { # file substring
  if grep -qF "$2" "$ROOT/$1" 2>/dev/null; then
    echo "FAIL: forbidden Claude model guidance in $1: \"$2\""
    fail=1
  fi
}

need "SKILL.md" 'HEADLESS_RELAY_CLAUDE_MODEL'
need "SKILL.md" 'CLAUDE_MODEL="${CLAUDE_MODEL:-fable}"'
need "SKILL.md" 'claude -p "your question here" --model "$CLAUDE_MODEL"'
need "SKILL.md" 'The printable `[1m]` suffix is a model variant, not ANSI bold.'
need "references/cli-reference.md" 'claude-fable-5[1m]'
need "references/cli-reference.md" 'Never strip a printable `[1m]` suffix.'
need "README.md" 'scripts/regression-claude-target.sh'
need "SKILL.md" '`model: "inherit"` only when the parent already runs the desired variant'
forbid "SKILL.md" 'model: "fable"'
forbid "SKILL.md" 'Agent tool subagent (`fable`'

# Every executable Claude print-mode example must pass the resolved model
# variable. A raw alias can collapse an account's configured long-context id.
if awk '
  /^[[:space:]]*```bash[[:space:]]*$/ { in_bash=1; next }
  /^[[:space:]]*```/ { in_bash=0; next }
  in_bash && /claude[[:space:]].*-p/ && $0 !~ /^[[:space:]]*#/ &&
    $0 !~ /--model[[:space:]]+"[$]CLAUDE_MODEL"/ {
      print FILENAME ":" FNR ":" $0; bad=1
    }
  END { exit bad }
' "$ROOT/SKILL.md" "$ROOT/references/cli-reference.md" >"$CHECK_TMP/model"; then
  :
else
  echo "FAIL: Claude print example bypasses configured model resolution:"
  cat "$CHECK_TMP/model"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: Claude relay preserves configured full model ids, including the printable [1m] variant."
fi
exit "$fail"
