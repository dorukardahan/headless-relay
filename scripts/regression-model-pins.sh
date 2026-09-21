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
  grep -qF 'data.get("models")' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer reads the Codex models-list schema"
    fail=1
  }
  # Grok catalog must stay isolated + bounded (availability ladder step 2).
  grep -qF 'env -i' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Grok catalog lost hermetic env -i"
    fail=1
  }
  grep -qF 'run_to 20 agy models' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Gemini catalog lost the 20s watchdog"
    fail=1
  }
  grep -qF 'start_new_session=True' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh watchdog no longer starts a new process group"
    fail=1
  }
  grep -qF 'run_grok_catalog' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh lost the isolated Grok catalog helper"
    fail=1
  }
  if grep -qE 'XAI_API_KEY="\$' "$ROOT/scripts/print-model-catalog.sh"; then
    echo "FAIL: print-model-catalog.sh still interpolates XAI_API_KEY onto a command line"
    fail=1
  fi
  grep -qF 'os.environ.get("XAI_API_KEY")' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer reads the API key from the environment"
    fail=1
  }
  grep -qF 'GROK_AUTH_PATH' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Grok catalog lost GROK_AUTH_PATH"
    fail=1
  }
  grep -qF 'XAI_API_KEY' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Grok catalog lost the API-key auth branch"
    fail=1
  }
  grep -qF '${HOME:-}' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer guards \$HOME under set -u in the subscription branch"
    fail=1
  }
  grep -qF '$(pwd)/$_ap' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer absolutizes a relative GROK_AUTH_PATH before cd"
    fail=1
  }
  grep -qF 'auth update disk written' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer discloses in-place Grok token refresh"
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
