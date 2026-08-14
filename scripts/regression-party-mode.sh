#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SKILL="$ROOT/SKILL.md"
REF="$ROOT/references/party-mode.md"
README="$ROOT/README.md"

fail() {
  printf 'party-mode regression: %s\n' "$1" >&2
  exit 1
}

require() {
  file=$1
  needle=$2
  label=$3
  grep -Fq -- "$needle" "$file" || fail "missing $label"
}

[ -f "$REF" ] || fail "missing references/party-mode.md"

require "$SKILL" 'Party Mode / Council Mode' 'skill trigger section'
require "$SKILL" 'references/party-mode.md' 'skill reference link'
require "$README" '**Party / Council Mode**' 'README feature'

require "$REF" 'ask everyone' 'English trigger'
require "$REF" 'her şeyi dene' 'Turkish trigger'
require "$REF" 'every built-in lane plus every valid custom target' 'complete candidate roster'
require "$REF" 'same frozen brief' 'identical-input contract'
require "$REF" 'Never install a binary, log in, rotate auth, or silently substitute another model' 'no-auth-churn/no-substitution rule'
require "$REF" 'Run Antigravity sequentially' 'Antigravity sequencing rule'
require "$REF" 'heavyweight local custom targets sequentially' 'local resource guard'
require "$REF" 'Preserve minority dissent' 'dissent preservation rule'
require "$REF" 'A majority vote is not evidence' 'anti-majority-truth rule'
require "$REF" 'blocked_egress' 'egress roster state'
require "$REF" 'degraded Party Mode' 'degraded-mode label'
require "$REF" 'no silent model/provider substitution occurred' 'GREEN exact-target gate'

printf 'party-mode regression: PASS\n'
