#!/bin/sh
# Tripwire: example-model docs must not teach a session-starting Codex catalog check.
#
# Fails if:
#   1. scripts/print-model-catalog.sh is missing or no longer names the safe Codex catalog;
#   2. README does not point at that script;
#   3. a docs line mentions `codex models` without also saying it starts a session / must not be run.
#
# Does not prove pins are current. Does not start a model turn.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

if [ ! -s "$ROOT/scripts/print-model-catalog.sh" ]; then
  echo "FAIL: scripts/print-model-catalog.sh is missing"
  fail=1
else
  grep -qF 'codex debug models' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer names \`codex debug models\`"
    fail=1
  }
  grep -qF 'codex models' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer warns against \`codex models\`"
    fail=1
  }
fi

grep -qF 'scripts/print-model-catalog.sh' "$ROOT/README.md" || {
  echo "FAIL: README.md does not point at scripts/print-model-catalog.sh"
  fail=1
}

for f in README.md SKILL.md references/cli-reference.md; do
  # A line that mentions the bad subcommand must also be a warning, not a how-to.
  awk -v F="$f" '
    $0 ~ /codex models/ {
      if ($0 !~ /starts a session|Do \*\*not\*\* run|Do not run|do not run|not a catalog|that starts/) {
        printf "FAIL: %s:%d mentions `codex models` without warning it starts a session\n", F, NR
        rc = 1
      }
    }
    END { exit rc }
  ' "$ROOT/$f" || fail=1
done

if [ "$fail" -eq 0 ]; then
  echo "OK: model-pin docs do not teach \`codex models\` as a catalog; print-model-catalog.sh is linked."
fi
exit "$fail"
