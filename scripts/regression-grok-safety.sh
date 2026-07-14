#!/bin/sh
# Regression guard for the Grok data-egress safeguard (headless-relay v2.0.0+).
#
# Grok Build leaks in three ways when run carelessly: (1) it uploads the whole tracked repo + git
# history when run inside a repo; (2) it auto-loads your global ~/.grok/AGENTS.md / rules / MCP into
# the model turn (verified 0.2.99/0.2.101); (3) its own tools can read elsewhere on the machine. From
# v2.0.3 the skill's defence is two helper functions (grok_relay / grok_media) that, for every Grok
# call, run in an empty non-git temp dir (signature: `rev-parse --is-inside-work-tree`), with a clean
# temporary `GROK_HOME`, a tool restriction (text: `--deny '*'`; media: a `--tools` allow-list), and
# `--sandbox strict` — all fail-closed (v2.0.4: subshell `trap` cleanup + change-based token sync).
#
# This check fails if:
#   1. a required security anchor (SECURITY.md, the SKILL/README/cli-reference/terms warnings) is gone;
#   2. the `grok_relay` and `grok_media` helper functions are not defined in SKILL.md;
#   3. in any fenced ```bash block, a RAW `grok <flag>` binary call (i.e. NOT a grok_relay/grok_media
#      helper invocation — those have no space after `grok`) is missing any layer it needs:
#        - every raw call (relay OR `grok models`/`grok agent`) needs the isolation guards
#          (`rev-parse --is-inside-work-tree` and `command -v git`), counted per call;
#        - every raw RELAY call (grok -p / --single / --prompt-file / --prompt-json / --check /
#          --resume / --continue / -r / -c) additionally needs `GROK_HOME`, `--sandbox strict`,
#          and a tool restriction (`--deny` OR a `--tools` allow-list), counted per call.
# Counting is per-block and layer-independent (a flag may sit on a line-continuation), so a raw call
# that drops GROK_HOME, the sandbox, the deny, or a guard trips the count. Comment-only lines are
# excluded, so prose mentions do not count. Helper invocations (`grok_relay "…"`, `grok_media …`)
# are NOT raw calls: `grok` is immediately followed by `_`, never a space, so they never match.
#
# WHAT THIS IS — and IS NOT. This is a text-signature TRIPWIRE, not a security proof. It catches the
# likely regressions (a fenced raw Grok call that lost its isolation guard, clean GROK_HOME, sandbox,
# or deny). It does NOT:
#   - prove the guard isolates at runtime (the unverified negative documented in SECURITY.md — a git
#     bundle can only come from a git repo, but it was never wire-measured);
#   - scan inline/prose command mentions — only ```-fenced blocks are scanned (docs use no other fence);
#   - tie a specific flag to a specific call within a block — it counts layer occurrences per block, so
#     a raw call co-located with an unrelated `--deny`/`GROK_HOME` could in principle slip. None of
#     these forms exist in the repo today; the tripwire's job is to keep it that way.
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
need "SKILL.md"                      "grok_relay()"
need "SKILL.md"                      "grok_media()"
need "SKILL.md"                      "GROK_HOME"
need "README.md"                     "Security: the Grok lane and your repository"
need "references/cli-reference.md"   "Data egress: Grok uploads the whole repo"
need "references/cli-reference.md"   "rev-parse --is-inside-work-tree"
need "references/anthropic-terms.md" "Data ingestion"

# Per fenced code block, over CODE lines only (comments stripped): every RAW grok binary call must
# carry the layers it needs. Layer occurrences are counted per block (line-continuation safe).
for f in "SKILL.md" "references/cli-reference.md"; do
  # gsub(re,"&",copy) returns the match count without changing content.
  awk -v F="$f" '
    /^[[:space:]]*```/ {
      if (inb) {
        # ANY raw grok binary call = "grok" + space(s) + a non-space arg. This is flag-ORDER
        # independent (catches "grok -m grok-4.5 -p …" as well as "grok -p …"). It excludes the
        # helper invocations grok_relay/grok_media (a "_" follows "grok", never a space) and the
        # model-id token "grok-4.5" (a "-" follows "grok", never a space).
        t0 = code; nany = gsub(/grok +[^ ]/, "&", t0)
        # Catalog subcommands (grok models / grok agent) send no model turn → isolation guards only.
        t2 = code; ncat = gsub(/grok +(models|agent)/, "&", t2)
        # Benign non-egress commands (auth / version / help) need no guards at all.
        tb = code; nbenign = gsub(/grok +(login|--version|--help|-V|-h)/, "&", tb)
        ncall  = nany - nbenign          # every real grok call (relay + catalog) needs isolation guards
        nrelay = nany - ncat - nbenign   # relay calls additionally need GROK_HOME / --sandbox / tool-restriction
        t3 = code; nguard = gsub(/rev-parse --is-inside-work-tree/, "&", t3)
        t4 = code; ngit   = gsub(/command -v git/, "&", t4)
        # Count only the load-bearing env ASSIGNMENT (GROK_HOME="…"), not variable-name references
        # like $GROK_HOME_TMP — else a block that names its var GROK_HOME_TMP inflates the count and
        # the check goes dead. (GROK_HOME_TMP= does not match GROK_HOME= : the char after E is "_".)
        t5 = code; nhome  = gsub(/GROK_HOME=/, "&", t5)
        t6 = code; nsand  = gsub(/--sandbox strict/, "&", t6)
        # Tool restriction = a --deny rule (text: --deny '*') OR a --tools allow-list (media). Either
        # satisfies "the relay call restricts tools". Count both.
        t7 = code; nrestrict = gsub(/--deny|--tools/, "&", t7)
        if (ncall > 0 && nguard < ncall) {
          printf "FAIL: %d raw Grok call(s) but only %d isolation guard(s) (rev-parse) in %s (block near line %d)\n", ncall, nguard, F, start; rc = 1
        }
        if (ncall > 0 && ngit < ncall) {
          printf "FAIL: %d raw Grok call(s) but only %d git-absent guard(s) (command -v git) in %s (block near line %d)\n", ncall, ngit, F, start; rc = 1
        }
        if (nrelay > 0 && nhome < nrelay) {
          printf "FAIL: %d raw Grok relay call(s) but only %d clean-GROK_HOME(s) in %s (block near line %d)\n", nrelay, nhome, F, start; rc = 1
        }
        if (nrelay > 0 && nsand < nrelay) {
          printf "FAIL: %d raw Grok relay call(s) but only %d with --sandbox strict in %s (block near line %d)\n", nrelay, nsand, F, start; rc = 1
        }
        if (nrelay > 0 && nrestrict < nrelay) {
          printf "FAIL: %d raw Grok relay call(s) but only %d with tool restriction (--deny/--tools) in %s (block near line %d)\n", nrelay, nrestrict, F, start; rc = 1
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
  echo "OK: Grok data-egress safeguard intact (anchors + helpers present; every fenced raw Grok call is isolation-guarded, git-absent-guarded, clean-GROK_HOME'd, sandboxed, and tool-restricted (--deny/--tools)."
fi
exit "$fail"
