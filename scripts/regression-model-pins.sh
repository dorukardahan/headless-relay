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
  grep -qF -- '--hermetic-home' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Grok catalog lost hermetic-home isolation"
    fail=1
  }
  grep -qF 'run_to 20 agy models' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Gemini catalog lost the 20s watchdog"
    fail=1
  }
  grep -qF 'run_to 20 codex debug models' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Codex catalog lost the 20s group watchdog"
    fail=1
  }
  grep -qF 'catalog_watchdog.py' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer uses catalog_watchdog.py"
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
  grep -qF '${HOME:-}' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer guards \$HOME under set -u in the subscription branch"
    fail=1
  }
  grep -qF '$(pwd)/$_ap' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer absolutizes a relative GROK_AUTH_PATH before isolation"
    fail=1
  }
  grep -qF 'auth update disk written' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer discloses in-place Grok token refresh"
    fail=1
  }
  grep -qF 'Available models:|Default model:' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer requires Grok model-list markers"
    fail=1
  }
  grep -qF "trap '_stop_grok 130' INT" "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer exits on SIGINT after Grok cleanup"
    fail=1
  }
  grep -qF 'run_to 5 codex --version' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh Codex --version probe is unbounded"
    fail=1
  }
  grep -qF '_gh=$(cd "$_gh" && pwd)' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer absolutizes Grok temp dirs"
    fail=1
  }
  grep -qF 'python3 "$WATCHDOG" --timeout "$_secs" -- "$@"' "$ROOT/scripts/print-model-catalog.sh" || {
    echo "FAIL: print-model-catalog.sh no longer separates child args from watchdog options"
    fail=1
  }
fi

if [ ! -s "$ROOT/scripts/catalog_watchdog.py" ]; then
  echo "FAIL: scripts/catalog_watchdog.py is missing"
  fail=1
else
  grep -qF 'start_new_session=True' "$ROOT/scripts/catalog_watchdog.py" || {
    echo "FAIL: catalog_watchdog.py no longer starts a new process group"
    fail=1
  }
  grep -qF 'live_pgid != proc.pid' "$ROOT/scripts/catalog_watchdog.py" || {
    echo "FAIL: catalog_watchdog.py no longer verifies the leader still owns its pgid before killpg"
    fail=1
  }
  if grep -qF 'Leader may have exited while a background worker' "$ROOT/scripts/catalog_watchdog.py"; then
    echo "FAIL: catalog_watchdog.py still killpg's after the leader was reaped (PID-reuse)"
    fail=1
  fi
  grep -qF 'signal.SIGINT' "$ROOT/scripts/catalog_watchdog.py" || {
    echo "FAIL: catalog_watchdog.py no longer traps SIGINT"
    fail=1
  }
  grep -qF 'SIGHUP' "$ROOT/scripts/catalog_watchdog.py" || {
    echo "FAIL: catalog_watchdog.py no longer traps SIGHUP"
    fail=1
  }
  if grep -qE 'str \| None|list\[str\]|dict\[str' "$ROOT/scripts/catalog_watchdog.py"; then
    echo "FAIL: catalog_watchdog.py still uses PEP 604 / 3.9-incompatible annotations"
    fail=1
  fi
  grep -qF 'os.environ.get("XAI_API_KEY")' "$ROOT/scripts/catalog_watchdog.py" || {
    echo "FAIL: catalog_watchdog.py no longer reads the API key from the environment"
    fail=1
  }
fi

grep -qF 'scripts/print-model-catalog.sh' "$ROOT/README.md" || {
  echo "FAIL: README.md does not point at scripts/print-model-catalog.sh"
  fail=1
}

# New Grok generations are account-specific. The two copy-paste helpers must
# keep a known prior default and make 4.7 an explicit catalog-gated opt-in.
if [ "$(grep -Fc 'model=${GROK_RELAY_MODEL:-grok-4.6}' "$ROOT/SKILL.md")" -ne 2 ] ||
   [ "$(grep -Fc -- '-m "$model" --disable-web-search' "$ROOT/SKILL.md")" -ne 4 ]; then
  echo "FAIL: Grok helpers lost the account-gated model selection"
  fail=1
fi
grep -qF 'require an exact `grok-4.7` entry under `Available models:`' "$ROOT/SKILL.md" || {
  echo "FAIL: Grok 4.7 preflight no longer checks the authenticated account catalog"
  fail=1
}

# A requested Claude model id is not proof of the served model. Keep the
# documented Opus 5.5 probe bounded, noninteractive and tied to modelUsage.
for needle in '"claude", "-p"' '"--model", "claude-opus-5-5"' '"--tools", ""' '"--output-format", "json"' 'timeout=90, check=False' 'result.get("modelUsage")' '"claude-opus-5-5" not in served'; do
  grep -qF -- "$needle" "$ROOT/references/cli-reference.md" || {
    echo "FAIL: Claude Opus 5.5 probe lost a bounded served-model assertion"
    fail=1
  }
done

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
