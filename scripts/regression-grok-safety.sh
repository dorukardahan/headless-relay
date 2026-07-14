#!/bin/sh
# Regression guard for the Grok data-egress safeguard (headless-relay v2.0.0+).
#
# Grok Build uploads the whole tracked repo + git history to xAI when run inside a repo. The
# skill's defence is a fail-closed working-directory isolation block whose signature is the guard
# `git ... rev-parse --is-inside-work-tree`, plus (v2.0.2) per-call tool-deny and sandbox flags.
# This check fails if:
#   1. a required security anchor (SECURITY.md, the SKILL/README/cli-reference/terms warnings) is gone;
#   2. any fenced shell block that invokes a Grok call that runs a session — generation/resume
#      (grok -p / --single / --prompt-file / --check / --resume / --continue / -r / -c) OR the
#      availability/agent subcommands (grok models / grok agent) — carries fewer fail-closed
#      guards (`rev-parse --is-inside-work-tree`) than Grok calls: i.e. a call is unisolated, or a
#      naked call was added next to a guarded one (masking);
#   3. a block's Grok calls outnumber its `command -v git` git-absent guards (the guard that
#      makes the isolation check fail closed when git is missing);
#   4. a fenced relay call (grok -p / --single / --prompt-file / --check / resume forms) lost its
#      `--sandbox strict`, or a non-media relay call lost its `--deny` (media calls — identified
#      by the `img-brief` prompt-file convention — are deny-exempt: a deny rule blocks the
#      image/video tools; they still need isolation + sandbox).
# Comment-only lines are excluded, so prose mentions of `grok -p` inside a block do not count.
#
# WHAT THIS IS — and IS NOT. This is a text-signature TRIPWIRE, not a security proof. It catches
# the most likely regressions (a fenced Grok call that lost its fail-closed guard, its git-absent
# guard, its sandbox, or its deny rule). It does NOT:
#   - prove the guard actually isolates at runtime (that is the unverified negative documented in
#     SECURITY.md — a git bundle can only come from a git repo, but it was never wire-measured);
#   - scan inline/prose command mentions (e.g. a `grok --prompt-json` table cell) — only ```-fenced
#     blocks are scanned (the docs use no other fence style);
#   - distinguish a real guard from an unrelated `rev-parse` / `command -v git` string that happens
#     to share a block (a single naked Grok call co-located with unrelated matches would slip the
#     per-block count);
#   - robustly tell a media call from a text relay: the `--deny` exemption is keyed on the literal
#     `img-brief` prompt-file convention, so a *text* relay that (against convention) names its
#     prompt file `img-brief` would wrongly skip the `--deny` check. The `--sandbox strict` and
#     isolation checks still apply to it; only the tool-deny requirement is bypassed. Keep media
#     briefs named `img-brief*` and text prompts named otherwise.
# None of these forms exist in the repo today; the tripwire's job is to keep it that way.
# Treat a green result as "no obvious regression", not "proven safe".
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
# call must be matched by a fail-closed guard, a git-absent guard, and (relay calls) the
# sandbox + deny flags.
for f in "SKILL.md" "references/cli-reference.md"; do
  # gsub(re,"&",copy) returns the match count without changing content. (Passing a /regex/
  # literal as an awk function arg silently matches it against $0 instead — so count inline.)
  awk -v F="$f" '
    /^[[:space:]]*```/ {
      if (inb) {
        code = code "\n"   # anchor: a bare "-c"/"-r" as the last code line needs a trailing space/newline to match
        t1 = code; ncall  = gsub(/grok[^\n]*(-p|--single|--prompt-file|--check|--resume|--continue|-r[ \n]|-c[ \n]|models|agent)/, "&", t1)
        t2 = code; nguard = gsub(/rev-parse --is-inside-work-tree/, "&", t2)
        t3 = code; ngit   = gsub(/command -v git/, "&", t3)
        t4 = code; nrelay = gsub(/grok[^\n]*(--single|--prompt-file|--check|--resume|--continue|-p[ \n]|-r[ \n]|-c[ \n])/, "&", t4)
        t5 = code; ndeny  = gsub(/grok[^\n]*--deny/, "&", t5)
        t6 = code; nsand  = gsub(/grok[^\n]*--sandbox strict/, "&", t6)
        t7 = code; nmedia = gsub(/grok[^\n]*img-brief/, "&", t7)
        if (ncall > 0 && nguard < ncall) {
          printf "FAIL: %d Grok call(s) but only %d fail-closed guard(s) in %s (block near line %d)\n", ncall, nguard, F, start
          rc = 1
        }
        if (ncall > 0 && ngit < ncall) {
          printf "FAIL: %d Grok call(s) but only %d git-absent guard(s) (command -v git) in %s (block near line %d)\n", ncall, ngit, F, start
          rc = 1
        }
        if (nrelay > 0 && nsand < nrelay) {
          printf "FAIL: %d Grok relay call(s) but only %d with --sandbox strict in %s (block near line %d)\n", nrelay, nsand, F, start
          rc = 1
        }
        if (nrelay > 0 && ndeny < nrelay - nmedia) {
          printf "FAIL: %d non-media Grok relay call(s) but only %d with --deny in %s (block near line %d)\n", nrelay - nmedia, ndeny, F, start
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
  echo "OK: Grok data-egress safeguard intact (anchors present; every fenced Grok call fail-closed-isolated, git-absent-guarded, sandboxed; non-media relays tool-denied)."
fi
exit "$fail"
