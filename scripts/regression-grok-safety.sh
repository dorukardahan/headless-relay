#!/bin/sh
# Regression guard for the Grok data-egress safeguard (headless-relay v2.0.0+).
#
# Grok Build uploads the whole tracked repo + git history to xAI when run inside a repo. The
# skill's defence is a fail-closed working-directory isolation block whose signature is the guard
# `git ... rev-parse --is-inside-work-tree`. This check fails if:
#   1. a required security anchor (SECURITY.md, the SKILL/README/cli-reference/terms warnings) is gone;
#   2. any fenced shell block that invokes a Grok call that runs a session — generation/resume
#      (grok -p / --single / --prompt-file / --check / --resume / --continue / -r / -c) OR the
#      availability/agent subcommands (grok models / grok agent) — carries fewer fail-closed
#      guards (`rev-parse --is-inside-work-tree`) than Grok calls: i.e. a call is unisolated, or a
#      naked call was added next to a guarded one (masking).
# Comment-only lines are excluded, so prose mentions of `grok -p` inside a block do not count.
# Limitation: only ```-fenced blocks are scanned (the docs use no other fence style); non-fenced
# shell in prose is out of scope by design.
#
# No dependencies beyond POSIX sh + awk + grep. Run from anywhere.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

need() { # file  substring
  if ! grep -qF "$2" "$ROOT/$1" 2>/dev/null; then
    echo "FAIL: missing security anchor in $1: \"$2\""
    fail=1
  fi
}

[ -s "$ROOT/SECURITY.md" ] || { echo "FAIL: SECURITY.md is missing or empty"; fail=1; }
need "SKILL.md"                      "isolation is mandatory"
need "SKILL.md"                      "rev-parse --is-inside-work-tree"
need "README.md"                     "Security: the Grok lane and your repository"
need "references/cli-reference.md"   "Data egress: Grok uploads the whole repo"
need "references/cli-reference.md"   "rev-parse --is-inside-work-tree"
need "references/anthropic-terms.md" "Data ingestion"

# Per fenced code block, over CODE lines only (comments stripped): every Grok generation/resume
# call must be matched by a fail-closed guard.
for f in "SKILL.md" "references/cli-reference.md"; do
  # gsub(re,"&",copy) returns the match count without changing content. (Passing a /regex/
  # literal as an awk function arg silently matches it against $0 instead — so count inline.)
  awk -v F="$f" '
    /^[[:space:]]*```/ {
      if (inb) {
        code = code "\n"   # anchor: a bare "-c"/"-r" as the last code line needs a trailing space/newline to match
        t1 = code; ncall  = gsub(/grok[^\n]*(-p|--single|--prompt-file|--check|--resume|--continue|-r[ \n]|-c[ \n]|models|agent)/, "&", t1)
        t2 = code; nguard = gsub(/rev-parse --is-inside-work-tree/, "&", t2)
        if (ncall > 0 && nguard < ncall) {
          printf "FAIL: %d Grok call(s) but only %d fail-closed guard(s) in %s (block near line %d)\n", ncall, nguard, F, start
          rc = 1
        }
        inb = 0
      } else { inb = 1; code = ""; start = NR }
      next
    }
    inb {
      t = $0; sub(/^[[:space:]]+/, "", t)
      if (substr(t, 1, 1) != "#") code = code "\n" $0
    }
    END { exit rc }
  ' "$ROOT/$f" || fail=1
done

if [ "$fail" -eq 0 ]; then
  echo "OK: Grok data-egress safeguard intact (anchors present; every fenced Grok call fail-closed-isolated)."
fi
exit "$fail"
