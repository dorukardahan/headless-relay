#!/bin/bash
# Offline regression for the Gemini (agy) read-only rules. Never calls a real model: a stub `agy`
# on PATH records its arguments. Checks that agy_answer passes AGY_RO before the caller's
# arguments, refuses flags that would undo it, and that the documented answer-only recipes keep
# --settings "$AGY_RO" and do not fall back to --mode plan.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SKILL="$ROOT/SKILL.md"
fail() { printf 'agy read-only regression: FAIL: %s\n' "$1" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/agyro.XXXXXX")
trap 'rm -rf "$T"' EXIT

# Extract AGY_RO, agy_run and agy_answer exactly as documented.
awk '/^# agy_run SECS AGY-ARGS/{f=1} f{print} f && /^agy_answer\(\) \($/{g=1} g && /^\)$/{exit}' \
  "$SKILL" > "$T/helpers.sh"
grep -q '^AGY_RO=' "$T/helpers.sh" || fail "AGY_RO is not defined next to agy_run"
grep -q '^agy_answer() ($' "$T/helpers.sh" || fail "agy_answer was not extracted"
bash -n "$T/helpers.sh" || fail "helpers do not parse"

# Stub agy: record argv (one per line), then answer.
mkdir "$T/bin"
cat > "$T/bin/agy" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$AGY_STUB_ARGS"
[ -n "${AGY_STUB_EMPTY:-}" ] || printf 'stub answer\n'
EOF
chmod +x "$T/bin/agy"
export PATH="$T/bin:$PATH" AGY_STUB_ARGS="$T/args"

run() { bash -c '. "$1"; shift; agy_answer "$@"' _ "$T/helpers.sh" "$@"; }

out=$(run 30 -p "question" --model m) || fail "agy_answer failed on a plain call"
[ "$out" = "stub answer" ] || fail "unexpected answer: $out"
expected=$(printf '%s\n' --settings \
  '{"permissions":{"deny":["write_file(*)","command(*)","execute_url(*)","mcp(*)"]}}' \
  -p question --model m)
[ "$(cat "$T/args")" = "$expected" ] || fail "agy argv is not --settings AGY_RO then the caller's args: $(tr '\n' ' ' < "$T/args")"

# Values of option flags are skipped, so a prompt equal to a refused flag still passes the check.
run 30 -p "--mode" >/dev/null || fail "a prompt value was mistaken for a flag"

for bad in "--settings {}" "--settings={}" "--mode plan" "--mode=auto" "--output-format json" "--output-format=json" "--"; do
  # shellcheck disable=SC2086
  if run 30 -p q $bad >/dev/null 2>&1; then fail "agy_answer accepted $bad"; fi
  # shellcheck disable=SC2086
  rc=0; run 30 -p q $bad >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "agy_answer exited $rc (want 2) for $bad"
done

rc=0; AGY_STUB_EMPTY=1 run 30 -p q >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "empty answer exited $rc (want 3)"

# Documented answer-only recipes keep AGY_RO; watch_clip no longer uses --mode plan.
for f in "$SKILL" "$ROOT/references/cli-reference.md"; do
  awk '/^watch_clip\(\) \(/,/^\)$/' "$f" > "$T/watch"
  [ -s "$T/watch" ] || fail "watch_clip not found in ${f#"$ROOT"/}"
  grep -q -- '--settings "\$AGY_RO"' "$T/watch" || fail "watch_clip lacks AGY_RO in ${f#"$ROOT"/}"
  ! grep -v '^[[:space:]]*#' "$T/watch" | grep -q -- '--mode plan' || fail "watch_clip still uses --mode plan in ${f#"$ROOT"/}"
done
grep -q 'agy_run 300 -p "$(cat /tmp/handoff.md)" --model "Gemini 4 Hydrogen (High)" --settings "$AGY_RO"' "$SKILL" \
  || fail "consensus Gemini example lacks AGY_RO or the Hydrogen pin"
grep -q 'agy_run 900 -p "$(cat prompt.md)" --model gemini-4-hydrogen-high --add-dir "$1" --settings "$AGY_RO"' "$SKILL" \
  || fail "parallel agy batch lacks AGY_RO"

printf 'agy read-only regression: PASS\n'
