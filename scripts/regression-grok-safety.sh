#!/bin/sh
# Regression guard for the Grok data-egress safeguard (headless-relay v3.0.0+, "M6" hermetic design).
#
# BACKGROUND. Earlier *shipped* Grok Build versions uploaded the whole tracked repo (+ git history)
# to xAI when run inside a repo. xAI open-sourced Grok Build on 2026-07-15 (Apache-2.0); a source
# audit of that release found the whole-repo bundle path GONE, uploads default off, and local config
# beating remote settings (see SECURITY.md §4). Two egress residuals remain — the Claude/Cursor/Codex
# compat scan (from $HOME) and grok's own ~/.grok/AGENTS.md scan (from $GROK_HOME) — plus a large
# surface of behaviour-changing env vars (endpoint/proxy redirects, GROK_AUTH_PROVIDER_COMMAND, log
# files, managed config, compat toggles). So the skill's Grok defence is two subshell helper functions
# (grok_relay / grok_media) that run every Grok call under a HERMETIC child environment:
#   - `env -i` with an ALLOWLIST      (only PATH/HOME/GROK_HOME/TMPDIR/TERM/telemetry-off/ONE auth var
#                                      reach grok; every other var — secrets AND grok overrides — dropped);
#   - an EMPTY synthetic HOME         (so the $HOME-rooted compat scan finds nothing);
#   - a CLEAN temporary GROK_HOME     (so the $GROK_HOME-rooted grok-native scan finds nothing);
#   - auth OUT-OF-BAND: GROK_AUTH_PATH -> the user's real auth.json, OR XAI_API_KEY (no auth file);
#   - an empty non-git working dir (verified outside any git worktree) + a tool restriction
#     (text: `--deny '*'`; media: a `--tools` allow-list) + a real watchdog timeout.
#
# This check fails if:
#   1. a required security anchor (SECURITY.md, the SKILL/README/cli-reference notes, the helpers) is gone;
#   2. in any fenced ```bash block, a RAW relay `grok`/`"$grokbin"` call (one that sends a MODEL TURN:
#      -p / --single / --prompt-file / --prompt-json / --check / --resume / --continue / -r / -c) is
#      missing any M6 layer it needs, counted per block:
#        - `env -i`                 (HERMETIC allowlist — the M6 marker; a blocklist `env -u` is FORBIDDEN);
#        - a synthetic ` HOME=`     (empty home so the compat scanners find no ~/.claude / ~/.cursor / ~/.codex);
#        - a `GROK_HOME=`           (clean temp home so grok's own ~/.grok/AGENTS.md is not scanned);
#        - a tool restriction       (`--deny` OR a `--tools` allow-list);
#        - an auth mechanism        (`GROK_AUTH_PATH=` OR `XAI_API_KEY=`).
# Relay calls are matched POSITIVELY by their relay flag, so `command -v grok`, `grok login`, a "grok
# not found" string, the model id `grok-4.5`, and catalog calls (`grok models`/`agent`/`inspect`) are
# NOT counted and need nothing. Helper INVOCATIONS (`grok_relay "…"`, `grok_media …`) are not raw calls.
# Counting is per-block and layer-independent (a flag/assignment may sit on a line-continuation).
#
# WHAT THIS IS — and IS NOT. A text-signature TRIPWIRE, not a security proof (the runtime proof is
# scripts/test-grok-runtime.sh). It catches the likely regression (a fenced raw relay call that lost
# its hermetic env / empty HOME / clean GROK_HOME / auth / tool restriction, or that reverted to an
# `env -u` blocklist). It does NOT prove runtime isolation. Treat green as "no obvious regression".
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
need "SKILL.md"                      "grok_relay()"
need "SKILL.md"                      "grok_media()"
need "SKILL.md"                      "empty synthetic"
need "SKILL.md"                      "env -i"
need "SKILL.md"                      "GROK_AUTH_PATH"
need "SKILL.md"                      "GROK_HOME"
need "SECURITY.md"                   "is gone from the source"
need "SECURITY.md"                   "empty synthetic"
need "SECURITY.md"                   "env -i"
need "README.md"                     "SECURITY.md"
need "references/cli-reference.md"   "GROK_AUTH_PATH"
need "references/cli-reference.md"   "env -i"

# Per fenced code block, over CODE lines only (comments stripped): every RAW relay grok/"$grokbin"
# call must carry env -i, a synthetic HOME=, a GROK_HOME=, a tool restriction, and an auth mechanism;
# and must NOT use an `env -u` blocklist. Counted per block.
for f in "SKILL.md" "references/cli-reference.md"; do
  awk -v F="$f" '
    /^[[:space:]]*```/ {
      if (inb) {
        # Relay calls: a grok / "$grokbin" token immediately followed by a relay (model-turn) flag.
        # This positively excludes `command -v grok`, `grok login`, "grok not found", `grok-4.5`,
        # and catalog `grok models`/`agent`/`inspect` (none are followed by a relay flag).
        t0 = code
        nrelay = gsub(/(grok|grokbin")[ ]+(-p|--prompt-file|--prompt-json|--single|--check|--resume|--continue|-r|-c)([ "]|$)/, "&", t0)
        # Hermetic allowlist marker.
        te = code; nenvi = gsub(/env -i/, "&", te)
        # A blocklist reversion is forbidden in a relay block.
        tu = code; nblock = gsub(/env -u/, "&", tu)
        # Synthetic HOME assignment - " HOME=" with a leading space so it does NOT match "GROK_HOME="
        # nor "${HOME:-...}"/"$HOME/" (":" or "/" follows, not "=").
        th = code; nhome = gsub(/ HOME=/, "&", th)
        # Clean temp GROK_HOME assignment (the ASSIGNMENT only; "GROK_HOME:-" ref is not counted).
        tg = code; ngrok = gsub(/GROK_HOME=/, "&", tg)
        # Tool restriction = --deny (text) OR --tools allow-list (media).
        t7 = code; nrestrict = gsub(/--deny|--tools/, "&", t7)
        # Auth mechanism = GROK_AUTH_PATH= (subscription) OR XAI_API_KEY= (API key). ASSIGNMENT only.
        ta = code; nauth = gsub(/GROK_AUTH_PATH=|XAI_API_KEY=/, "&", ta)
        if (nrelay > 0) {
          if (nblock > 0) {
            printf "FAIL: relay block uses a forbidden `env -u` blocklist (M6 requires the `env -i` allowlist) in %s (block near line %d)\n", F, start; rc = 1
          }
          if (nenvi < nrelay) {
            printf "FAIL: %d raw Grok relay call(s) but only %d hermetic `env -i`(s) in %s (block near line %d)\n", nrelay, nenvi, F, start; rc = 1
          }
          if (nhome < nrelay) {
            printf "FAIL: %d raw Grok relay call(s) but only %d synthetic-HOME(s) in %s (block near line %d)\n", nrelay, nhome, F, start; rc = 1
          }
          if (ngrok < nrelay) {
            printf "FAIL: %d raw Grok relay call(s) but only %d clean-GROK_HOME(s) in %s (block near line %d)\n", nrelay, ngrok, F, start; rc = 1
          }
          if (nrestrict < nrelay) {
            printf "FAIL: %d raw Grok relay call(s) but only %d tool restriction(s) (--deny/--tools) in %s (block near line %d)\n", nrelay, nrestrict, F, start; rc = 1
          }
          if (nauth < nrelay) {
            printf "FAIL: %d raw Grok relay call(s) but only %d auth mechanism(s) (GROK_AUTH_PATH/XAI_API_KEY) in %s (block near line %d)\n", nrelay, nauth, F, start; rc = 1
          }
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
  echo "OK: Grok data-egress safeguard intact (anchors + helpers present; every fenced raw Grok relay call runs under a hermetic env -i allowlist with a synthetic HOME, a clean GROK_HOME, an auth mechanism (GROK_AUTH_PATH/XAI_API_KEY), and a tool restriction (--deny/--tools); no env -u blocklist)."
fi
exit "$fail"
