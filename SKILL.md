---
name: headless-relay
description: Headless handoff guide for running other AI models from inside an agent session (any Agent Skills runtime - Claude Code, Codex, Grok Build, Cursor, OpenClaw, Hermes). Covers GPT (codex exec), GLM (opencode run or zcode --prompt), Grok (grok -p), Gemini (Antigravity agy -p), and Claude (claude -p or a subagent) - inline vs file prompts, parallel multi-model consensus, JSON output, session resume, image/video generation, provider-terms compliance. Use for "ask codex", "ask GLM", "ask grok", "ask gemini", "second opinion", "cross-model review", "generate an image", "run headless", "ask another model".
license: MIT. Complete terms in LICENSE.txt
metadata: {"version": "3.0.0"}
---

# headless-relay

This skill provides instructions for delegating a task to another AI model without leaving the
current agent session. The user says "ask Codex", "get GLM's opinion", "run this by Grok"; the
orchestrating agent (Claude Code, Codex CLI, or another harness) writes the prompt, runs the
target model's headless CLI through its shell tool, reads the model's stdout, and summarizes
the answer back. Follow these patterns exactly.

## The five targets

| Target | CLI | Headless entry point | Auth / plan |
|--------|-----|----------------------|-------------|
| GPT | `codex` (OpenAI Codex CLI) | `codex exec` | ChatGPT plan or OpenAI API key (`codex login`) |
| GLM | `opencode`, or `zcode` (ships inside the ZCode desktop app) | `opencode run` / `zcode --prompt` | Z.ai Coding Plan (API key or ZCode app login) |
| Grok | `grok` (xAI Grok Build) | `grok -p` — via the `grok_relay` helper (empty `HOME` + clean temp `GROK_HOME` so it can't read your other tools' config or grok's own global rules; see the next section) | SuperGrok (`grok login`) or `XAI_API_KEY` |
| Gemini | `agy` (Google Antigravity CLI — replaced the retired Gemini CLI) | `agy -p` / `--print` | Google account via the Antigravity app/CLI |
| Claude | `claude` (Claude Code) | `claude -p`, or the harness's native subagent | Anthropic auth of the current session |

## Grok: read this before relaying

Grok Build had a real data-egress problem, and it has since changed. Both halves matter.

**What happened.** Earlier *shipped* versions of `grok`, run inside a git repository, uploaded your
**entire tracked repo — full commit history and every tracked file, including a tracked `.env`** —
to xAI cloud storage as a git bundle, independent of which files the model read, not stopped by any
prompt or flag. Confirmed by xAI's own Grok account on X and by independent mitmproxy wire capture
(a never-read canary file was recovered from the upload). Details: [SECURITY.md](SECURITY.md).

**What changed (2026-07-15).** xAI open-sourced Grok Build (Apache-2.0,
`github.com/xai-org/grok-build`), deleted previously-retained coding data, and set retention off by
default. A source audit of that release (commit `c68e39f`) found:
- **The whole-repo bundle path is gone from the source** — no `git bundle` / `codebase_upload` /
  whole-repo archive anywhere; the trace pipeline serializes only the model's own turn I/O, and it
  defaults **off** (telemetry defaults off; the per-turn `config_files.json` upload is hard-disabled).
- **Your local `~/.grok/config.toml` beats xAI's remote settings** (proven by the resolver plus a
  repo test): a server-pushed flag cannot re-enable an upload you turned off locally.

**Two residual concerns remain — the relay still uses a small helper for them:**

1. **Grok auto-loads global rules into every turn — from two roots.** (a) As a Claude-Code / Cursor /
   Codex *compatibility* feature (on by default — source-confirmed in `xai-grok-tools`
   `types/compat.rs`: `CompatConfig` defaults every cell ON for all three vendors), `grok` scans
   `~/.claude/CLAUDE.md`, `~/.cursor/…`, `~/.claude.json` MCP servers, skills, and hooks — all rooted
   at `$HOME` (Codex's `sessions` cell is the one runtime-consumed Codex surface). (b) Independently,
   `grok` reads its OWN `~/.grok/AGENTS.md` / skills / hooks / MCP, rooted at `$GROK_HOME`
   (source-verified: the loader always scans `grok_home()`). Either way that text is injected into the
   model turn and goes to xAI like any prompt — your setup leaving for xAI without you asking. The
   helper closes both: an **empty synthetic `HOME`** (nothing at `$HOME` to scan) **and a clean
   temporary `GROK_HOME`** (nothing at `$GROK_HOME` to scan), and belt-and-suspenders it pins every
   `[compat.claude]` / `[compat.cursor]` / `[compat.codex]` cell `false` in the temp `GROK_HOME`'s
   `config.toml` while the hermetic env drops the `GROK_<VENDOR>_*_ENABLED` overrides that would
   otherwise outrank that config.
2. **The shipped binary can't be verified against the source.** No GitHub releases / signatures /
   reproducible build; the official installer pulls from a *different* (private) repo; auto-update
   `exec()`s unsigned bytes; a `cargo build` reports a version matching no release. So "the source is
   clean" does not prove "the binary you run is clean." This is a general caveat for **any**
   closed-binary relay target (Codex and agy included), not unique to Grok — but it is why the helper
   keeps cheap belt-and-suspenders (empty non-git working dir + locked-down tool use) rather than trusting the
   binary.

Grok is still a **cloud model**: the prompt you pass and Grok's reasoning go to xAI. The helper stops
the global-rule leak and denies tools; it does not make Grok local, and it does not route
repo/diff context to Grok (relay only the prompt you give it).

**Two helper functions — define once, use for every Grok call.** Each is a subshell (`name() ( … )`)
with `set +eux` (never inherits the caller's errexit/nounset, and disables xtrace so a key can't be
traced to stderr) plus cleanup `trap`s. They run `grok` under a **hermetic child environment** —
`env -i` with an explicit allowlist, so only `PATH` (minimal), `HOME`, `GROK_HOME`, `TMPDIR`, `TERM`,
the telemetry-off master switches, and exactly ONE auth variable reach grok. Every other variable is
dropped: your unrelated secrets AND grok's own behaviour-changing overrides (endpoint / proxy /
gateway redirects, `GROK_AUTH_PROVIDER_COMMAND`, `GROK_LOG_FILE`, `GROK_MANAGED_CONFIG*`,
`GROK_*_ENABLED` compat toggles, …). Three **separate** clean temp dirs back it: an **empty synthetic
`HOME`** (no `~/.claude` / `~/.cursor` / `~/.codex` scan), a **clean temporary `GROK_HOME`** (no
`~/.grok/AGENTS.md` / skills / hooks / MCP scan), and an **empty non-git working dir** — the wrapper
verifies that dir sits outside any git worktree (it does not trust `TMPDIR`) or aborts. Auth is
out-of-band: **`GROK_AUTH_PATH` → your real `auth.json`** (subscription login refreshed in place,
nothing copied) *or* **`XAI_API_KEY`** (passed to grok as its key; the wrapper reads no auth file and passes no auth path in this branch). Each call also carries a **real
watchdog timeout** and reaps grok's process tree (child + grandchildren) on timeout / `INT` /
`TERM` / `HUP` / error. **Scope: personal / consumer subscription OAuth and API key. Team/enterprise
managed policy is NOT carried (see [SECURITY.md](SECURITY.md)).**

```bash
# grok_relay — TEXT relay to xAI Grok. Isolation: HERMETIC child env (env -i allowlist: only PATH,
# HOME, GROK_HOME, TMPDIR, TERM, telemetry-off, workspace-data-collection-off, and ONE auth var reach
# grok — every other var, including all endpoint/proxy/auth-provider/log/compat overrides and your
# unrelated secrets, is dropped) + empty synthetic HOME (no ~/.claude/~/.cursor/~/.codex scan) + clean
# temp GROK_HOME (no ~/.grok/AGENTS.md/skills/hooks/MCP scan) + empty non-git CWD (physical path
# verified outside any git worktree) + auth via GROK_AUTH_PATH->your real auth.json (refreshed in
# place; never read by the wrapper) OR XAI_API_KEY (passed to grok as its key; the wrapper reads no auth
# file and passes no auth PATH in this branch) + ALL tools denied + a real
# watchdog timeout. The wrapper's control state (the answer file) lives in a SEPARATE base that grok is
# never given a path under. Answer -> stdout.  Usage: grok_relay "your question"
# [GROK_RELAY_TIMEOUT=secs, default 300]
grok_relay() (
  { set +eux; } 2>/dev/null                                  # subshell-local: no errexit/nounset/xtrace (xtrace off => no key on stderr)
  _kids(){ for __k in $(ps -A -o pid=,ppid= 2>/dev/null | awk -v p="$1" '$2==p{print $1}'); do _kids "$__k"; echo "$__k"; done; }
  _killn(){ while IFS= read -r __q; do [ -n "$__q" ] && kill "-$1" "$__q" 2>/dev/null; done; }
  _tree(){ [ -n "${1:-}" ] || return 0; __L=$({ echo "$1"; _kids "$1"; }); printf '%s\n' "$__L" | _killn TERM; sleep 0.3; printf '%s\n' "$__L" | _killn KILL; }
  _ingit(){ __d=$(cd "$1" 2>/dev/null && pwd -P) || __d=$1; while [ -n "$__d" ] && [ "$__d" != / ]; do [ -e "$__d/.git" ] && return 0; __d=$(dirname "$__d"); done; return 1; }
  _reappg(){ [ "${pgok:-0}" = 1 ] && [ -n "${1:-}" ] && { kill -TERM "-$1" 2>/dev/null; sleep 0.2; kill -KILL "-$1" 2>/dev/null; }; return 0; }  # reap grok's process GROUP (sh/bash; no-op on zsh/dash)
  [ -n "${1:-}" ] || { echo "grok_relay: usage: grok_relay \"your question\"" >&2; exit 2; }
  grokbin=$(command -v grok 2>/dev/null || true)
  [ -n "$grokbin" ] || { echo "grok_relay: grok not found on PATH" >&2; exit 127; }
  key="${XAI_API_KEY:-${GROK_CODE_XAI_API_KEY:-}}"           # non-empty => API-key branch
  if [ -z "$key" ]; then                                     # subscription: grok precedence GROK_AUTH_PATH > $GROK_HOME/auth.json > $HOME/.grok/auth.json
    ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"
    case "$ap" in /*) ;; *) ap="$(pwd)/$ap" ;; esac          # absolutise before any cd
    [ -r "$ap" ] || { echo "grok_relay: no readable auth at $ap — run 'grok login', or set XAI_API_KEY" >&2; exit 1; }
  fi
  to=${GROK_RELAY_TIMEOUT:-300}; case "$to" in ''|*[!0-9]*) to=300 ;; esac; [ "$to" -gt 0 ] || to=300
  base=$(mktemp -d "${TMPDIR:-/tmp}/grok-ctl.XXXXXX") || { echo "grok_relay: mktemp failed" >&2; exit 1; }   # CONTROL (answer file); grok never told this path
  child=""; wd=""; pgok=0
  trap 'rm -rf "$base" "${sbx:-}" 2>/dev/null' EXIT          # armed BEFORE sandbox exists: nothing can leak
  trap 'trap - INT TERM HUP EXIT; [ -n "$child" ] && { _tree "$child"; _reappg "$child"; }; [ -n "$wd" ] && _tree "$wd"; rm -rf "$base" "${sbx:-}" 2>/dev/null; exit 130' INT TERM HUP
  sbx=$(mktemp -d "${TMPDIR:-/tmp}/grok-sbx.XXXXXX") || { echo "grok_relay: mktemp failed" >&2; exit 1; }     # SANDBOX given to grok
  hm="$sbx/home"; gkh="$sbx/grok"; iso="$sbx/cwd"; tmp="$sbx/tmp"
  mkdir -p "$hm" "$gkh" "$iso" "$tmp" || { echo "grok_relay: mkdir failed" >&2; exit 1; }
  _ingit "$iso" && { echo "grok_relay: working dir is inside a git worktree (TMPDIR points into a repo?) — aborting" >&2; exit 1; }
  printf '%s' '[features]
telemetry = false
[telemetry]
trace_upload = false
[folder_trust]
enabled = false
[cli]
auto_update = false
use_leader = false
[harness]
disable_codebase_upload = true
[compat.claude]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
[compat.cursor]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
[compat.codex]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
' > "$gkh/config.toml" || { echo "grok_relay: could not write config" >&2; exit 1; }
  [ -s "$gkh/config.toml" ] || { echo "grok_relay: config incomplete" >&2; exit 1; }
  if ( set -m ) 2>/dev/null; then set -m 2>/dev/null; fi   # enable monitor mode where allowed so the grok job gets its OWN process group (sh/bash); pgok is set below ONLY after verifying grok is that group's leader   # per-job process groups (sh/bash) so grok's descendants are reapable even after it exits; zsh/dash: no-op (documented limit)
  if [ -n "$key" ]; then                                     # API key: no auth file read; env -i drops GROK_DISABLE_API_KEY_AUTH etc.
    ( cd "$iso" && exec env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$hm" GROK_HOME="$gkh" TMPDIR="$tmp" TERM=dumb \
        GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_WORKSPACE_DATA_COLLECTION_DISABLED=true XAI_API_KEY="$key" \
        "$grokbin" -p "$1" -m grok-4.5 --disable-web-search --sandbox strict --deny '*' ) > "$base/out" 2>/dev/null &
  else                                                       # subscription: only GROK_AUTH_PATH reaches grok (GROK_AUTH inline etc. dropped by env -i)
    ( cd "$iso" && exec env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$hm" GROK_HOME="$gkh" TMPDIR="$tmp" TERM=dumb \
        GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_WORKSPACE_DATA_COLLECTION_DISABLED=true GROK_AUTH_PATH="$ap" \
        "$grokbin" -p "$1" -m grok-4.5 --disable-web-search --sandbox strict --deny '*' ) > "$base/out" 2>/dev/null &
  fi
  child=$!
  __pg=$(ps -o pgid= -p "$child" 2>/dev/null | tr -d ' '); [ -n "$__pg" ] && [ "$__pg" = "$child" ] && pgok=1   # negative-kill ONLY if grok is VERIFIED to be its own process-group leader; false on dash (job control off) / zsh (set -m rejected) -> pgok stays 0
  # Watchdog with NO grok-writable coordination files: grok is never given a path under $base, and even
  # if it enumerated temp, liveness is grok's own (kill -0, unspoofable) and the timeout verdict is the
  # watchdog's EXIT CODE (77), which grok cannot touch.
  ( __n=0; __max=$((to * 5)); [ "$__max" -gt 0 ] || __max=1
    while [ "$__n" -lt "$__max" ]; do kill -0 "$child" 2>/dev/null || exit 0; sleep 0.2; __n=$((__n + 1)); done
    _tree "$child"; _reappg "$child"; exit 77 ) &
  wd=$!
  while kill -0 "$child" 2>/dev/null; do sleep 0.2; done
  wait "$child" 2>/dev/null; rc=$?; child=""                 # take grok's exit code, then IMMEDIATELY forget the PID: NO negative process-group kill post-wait (pgid could be reused), and no _tree ever on a stale PID
  wait "$wd" 2>/dev/null; wdrc=$?; wd=""
  if [ "$wdrc" = 77 ]; then echo "grok_relay: timed out after ${to}s" >&2; exit 124; fi
  [ "$rc" = 0 ] || { echo "grok_relay: grok exited $rc" >&2; exit "$rc"; }
  # Read the answer from $base/out (grok was never given $base). Defence-in-depth vs a temp-enumerating
  # binary: require a regular, non-symlink file so a swapped symlink/FIFO can't redirect the read or hang.
  { [ -f "$base/out" ] && [ ! -L "$base/out" ]; } || { echo "grok_relay: answer file missing or tampered" >&2; exit 1; }
  cat "$base/out"
  exit 0
)
```

And the media helper — same hermetic isolation + auth branches + watchdog, but it **allow-lists only
the four media tools** (a text relay's `--deny '*'` would block `image_gen`). Grok writes media under
the temp `GROK_HOME` session dir; the helper then publishes **only this call's** artifacts to your
output dir by copying each into a temp there and **hard-linking** it into place — the ONE atomic,
no-clobber, no-follow publish primitive. If the output-dir filesystem has no hard-link support the
helper **fails closed** (no `mv`, no reserve-then-fill — a reopen-by-path could follow a swapped
symlink; put the output dir on a hard-link-capable fs). It also **fails closed before publishing** if
any artifact name contains a newline, and refuses any file not physically inside the sandbox — so a
newline-named artifact can't smuggle in an unrelated file. Safe under concurrent cooperative calls. On
any failure / timeout / signal it rolls back only this call's own files and **never removes the output
dir** (a rolled-back call that created it leaves it in place — usually empty (see the local `.grokpub`
signal-window note in SECURITY.md) — so it can't win a reverse-timing race against
a concurrent call about to publish there). grok never runs in the output dir. Grok is the only
lane with video:

```bash
# grok_media — image/video. Same HERMETIC isolation + auth + watchdog as grok_relay, but allow-lists
# only the four media tools (a text relay's --deny '*' would block image_gen) and strips the always-on
# MCP meta-tools. grok runs in the empty non-git CWD (never OUTPUT-DIR); grok writes media under the
# temp GROK_HOME session dir; the helper then publishes ONLY this call's artifacts to OUTPUT-DIR by
# copying each into a temp in the output dir and hard-linking it into place — the ONE atomic, no-clobber,
# NO-FOLLOW publish primitive. If the OUTPUT-DIR filesystem has no hard-link support the helper FAILS
# CLOSED (no reserve-then-fill, no mv): a name is never published unsafely. It also FAILS CLOSED before
# publishing if any artifact name contains a newline, and refuses any file not physically inside the
# sandbox. On any failure / timeout / signal it rolls back ONLY this call's own files (completed +
# in-flight) and NEVER removes the output directory (a rolled-back call that created it leaves it in place
# — usually empty; see the local .grokpub signal-window note in SECURITY.md — rather than win a
# reverse-timing race against a concurrent call about to publish there). The manifest
# lives in a separate control base grok is not given a path to (raises the bar against a temp-enumerating
# binary; not a jail; see SECURITY.md). grok's descendants are reaped ONLY while grok is still alive
# (signal / timeout, via a ps-walk on all shells, plus a VERIFIED process-group kill on sh/bash). After
# grok's own normal/nonzero exit the helper does NOT chase a detached descendant (no post-wait negative
# kill — the pgid could be reused); that cleanup is out of scope and needs an OS sandbox.
# Usage: grok_media /abs/brief.md /abs/out-dir   [GROK_MEDIA_TIMEOUT=secs, default 600]
grok_media() (
  { set +eux; } 2>/dev/null
  _kids(){ for __k in $(ps -A -o pid=,ppid= 2>/dev/null | awk -v p="$1" '$2==p{print $1}'); do _kids "$__k"; echo "$__k"; done; }
  _killn(){ while IFS= read -r __q; do [ -n "$__q" ] && kill "-$1" "$__q" 2>/dev/null; done; }
  _tree(){ [ -n "${1:-}" ] || return 0; __L=$({ echo "$1"; _kids "$1"; }); printf '%s\n' "$__L" | _killn TERM; sleep 0.3; printf '%s\n' "$__L" | _killn KILL; }
  _ingit(){ __d=$(cd "$1" 2>/dev/null && pwd -P) || __d=$1; while [ -n "$__d" ] && [ "$__d" != / ]; do [ -e "$__d/.git" ] && return 0; __d=$(dirname "$__d"); done; return 1; }
  _reappg(){ [ "${pgok:-0}" = 1 ] && [ -n "${1:-}" ] && { kill -TERM "-$1" 2>/dev/null; sleep 0.2; kill -KILL "-$1" 2>/dev/null; }; return 0; }  # reap grok's process GROUP (sh/bash; no-op on zsh/dash)
  # Roll back ONLY this call's OWN files: completed ($published) + the in-flight one ($pending, set ONLY
  # after we create it, so it can never name a pre-existing/concurrent file) + the temp. NEVER remove the
  # output directory: a concurrent cooperative call may have created it or be about to publish into it, so
  # a rolled-back call that created the dir leaves it in place (usually empty) rather than risk a
  # reverse-timing rmdir that breaks the other call.
  _rollback(){
    printf '%s' "$published" | while IFS= read -r __p; do [ -n "$__p" ] && rm -f "$__p" 2>/dev/null; done
    # in-flight: remove $pending ONLY if it is the file WE just created — proven by sharing our live
    # temp's inode (a hard link; `-ef`). A pre-existing/concurrent file at that name has a DIFFERENT inode
    # and is left untouched. ($curtmp is kept alive until $dest is recorded in $published, so this check
    # is valid across the window between the ln and the record.)
    [ -n "${pending:-}" ] && [ -n "${curtmp:-}" ] && [ "$pending" -ef "$curtmp" ] 2>/dev/null && rm -f "$pending" 2>/dev/null
    [ -n "${curtmp:-}" ] && rm -f "$curtmp" 2>/dev/null
    return 0
  }
  { [ -n "${1:-}" ] && [ -n "${2:-}" ]; } || { echo "grok_media: usage: grok_media BRIEF-FILE OUTPUT-DIR" >&2; exit 2; }
  brief="$1"; out="$2"
  __nl=$(printf '\nx'); __nl=${__nl%x}                       # a single literal LF (command substitution can't carry one directly)
  case "$brief$out" in *"$__nl"*) echo "grok_media: a path argument contains a newline — refusing before any file is created (fail-closed)" >&2; exit 2 ;; esac  # a newline in OUTPUT-DIR would split one path into two rollback targets in the newline-delimited $published list
  [ -r "$brief" ] || { echo "grok_media: brief not readable: $brief" >&2; exit 2; }
  briefdata=$(cat "$brief") || { echo "grok_media: cannot read brief: $brief" >&2; exit 2; }
  [ -n "$briefdata" ] || { echo "grok_media: brief is empty: $brief" >&2; exit 2; }
  case "$out" in /*) ;; *) out="$(pwd)/$out" ;; esac         # absolutise output before any cd
  out_pre=1; [ -d "$out" ] || out_pre=0                      # did the output dir exist before this call?
  mkdir -p "$out" || { echo "grok_media: cannot create output dir: $out" >&2; exit 2; }
  grokbin=$(command -v grok 2>/dev/null || true)
  [ -n "$grokbin" ] || { echo "grok_media: grok not found on PATH" >&2; exit 127; }
  key="${XAI_API_KEY:-${GROK_CODE_XAI_API_KEY:-}}"
  if [ -z "$key" ]; then
    ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"
    case "$ap" in /*) ;; *) ap="$(pwd)/$ap" ;; esac
    [ -r "$ap" ] || { echo "grok_media: no readable auth at $ap — run 'grok login', or set XAI_API_KEY" >&2; exit 1; }
  fi
  to=${GROK_MEDIA_TIMEOUT:-600}; case "$to" in ''|*[!0-9]*) to=600 ;; esac; [ "$to" -gt 0 ] || to=600
  base=$(mktemp -d "${TMPDIR:-/tmp}/grok-ctl.XXXXXX") || { echo "grok_media: mktemp failed" >&2; exit 1; }    # CONTROL (manifest); grok never told this path
  child=""; wd=""; published=""; curtmp=""; pending=""; pgok=0
  trap 'rm -rf "$base" "${sbx:-}" 2>/dev/null' EXIT
  trap 'trap - INT TERM HUP EXIT; [ -n "$child" ] && { _tree "$child"; _reappg "$child"; }; [ -n "$wd" ] && _tree "$wd"; _rollback; rm -rf "$base" "${sbx:-}" 2>/dev/null; exit 130' INT TERM HUP
  sbx=$(mktemp -d "${TMPDIR:-/tmp}/grok-sbx.XXXXXX") || { echo "grok_media: mktemp failed" >&2; exit 1; }
  hm="$sbx/home"; gkh="$sbx/grok"; iso="$sbx/cwd"; tmp="$sbx/tmp"
  mkdir -p "$hm" "$gkh" "$iso" "$tmp" || { echo "grok_media: mkdir failed" >&2; exit 1; }
  _ingit "$iso" && { echo "grok_media: working dir is inside a git worktree (TMPDIR points into a repo?) — aborting" >&2; exit 1; }
  printf '%s' '[features]
telemetry = false
[telemetry]
trace_upload = false
[folder_trust]
enabled = false
[cli]
auto_update = false
use_leader = false
[harness]
disable_codebase_upload = true
[compat.claude]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
[compat.cursor]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
[compat.codex]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false
' > "$gkh/config.toml" || { echo "grok_media: could not write config" >&2; exit 1; }
  [ -s "$gkh/config.toml" ] || { echo "grok_media: config incomplete" >&2; exit 1; }
  if ( set -m ) 2>/dev/null; then set -m 2>/dev/null; fi   # enable monitor mode where allowed so the grok job gets its OWN process group (sh/bash); pgok is set below ONLY after verifying grok is that group's leader   # per-job process groups? sh/bash: yes (grok becomes a group leader, so its descendants are reapable even after it exits/reparents); zsh/dash: no (documented limit)
  mt="image_gen,image_edit,image_to_video,reference_to_video"
  if [ -n "$key" ]; then
    ( cd "$iso" && exec env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$hm" GROK_HOME="$gkh" TMPDIR="$tmp" TERM=dumb \
        GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_WORKSPACE_DATA_COLLECTION_DISABLED=true XAI_API_KEY="$key" \
        "$grokbin" -p "$briefdata" -m grok-4.5 --disable-web-search --sandbox strict --tools "$mt" --disallowed-tools search_tool,use_tool ) >/dev/null 2>&1 &
  else
    ( cd "$iso" && exec env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$hm" GROK_HOME="$gkh" TMPDIR="$tmp" TERM=dumb \
        GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_WORKSPACE_DATA_COLLECTION_DISABLED=true GROK_AUTH_PATH="$ap" \
        "$grokbin" -p "$briefdata" -m grok-4.5 --disable-web-search --sandbox strict --tools "$mt" --disallowed-tools search_tool,use_tool ) >/dev/null 2>&1 &
  fi
  child=$!
  __pg=$(ps -o pgid= -p "$child" 2>/dev/null | tr -d ' '); [ -n "$__pg" ] && [ "$__pg" = "$child" ] && pgok=1   # negative-kill ONLY if grok is VERIFIED to be its own process-group leader; false on dash (job control off) / zsh (set -m rejected) -> pgok stays 0, so no unverified process-group kill
  ( __n=0; __max=$((to * 5)); [ "$__max" -gt 0 ] || __max=1
    while [ "$__n" -lt "$__max" ]; do kill -0 "$child" 2>/dev/null || exit 0; sleep 0.2; __n=$((__n + 1)); done
    _tree "$child"; _reappg "$child"; exit 77 ) &
  wd=$!
  while kill -0 "$child" 2>/dev/null; do sleep 0.2; done
  wait "$child" 2>/dev/null; rc=$?; child=""                 # take grok's exit code, then IMMEDIATELY forget the PID: NO negative process-group kill post-wait (pgid could be reused), and no _tree ever on a stale PID
  wait "$wd" 2>/dev/null; wdrc=$?; wd=""
  [ "$wdrc" = 77 ] && { echo "grok_media: timed out after ${to}s" >&2; rc=124; }
  # Enumerate this call's artifacts. FIRST fail CLOSED if any artifact name contains a newline: a
  # newline-delimited manifest would otherwise let such a name smuggle a second path (e.g. a caller-CWD
  # file) into the publish loop. Use a NUL-delimited find and count embedded newlines; if any, refuse to
  # publish (nothing written yet). Manifest lives in $base (grok never given that path); the pre-existing
  # one is removed first so a planted symlink can't redirect the write (pre-planting defeated; a same-UID
  # enumerator that wins the rm/create race is out of scope — needs an OS sandbox; see SECURITY.md).
  rm -f "$base/manifest" "$base/manifest0" 2>/dev/null
  find "$hm" "$gkh" "$iso" "$tmp" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o -name '*.mp4' -o -name '*.mov' \) -print0 > "$base/manifest0" 2>/dev/null
  if [ "$(tr -dc '\n' < "$base/manifest0" 2>/dev/null | wc -c | tr -d ' ')" != 0 ]; then
    echo "grok_media: refusing to publish — an artifact name contains a newline (fail-closed)" >&2
    _rollback; exit 3
  fi
  tr '\0' '\n' < "$base/manifest0" > "$base/manifest" 2>/dev/null   # no embedded newlines remain -> safe to read line-by-line
  sbxreal=$(cd "$sbx" 2>/dev/null && pwd -P) || sbxreal="$sbx"   # physical sandbox root for containment
  fail=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ ! -L "$f" ] || continue                                  # never a symlink
    [ -f "$f" ] || continue                                    # regular files only (skips FIFO/dir + newline-split fragments)
    fdir=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || continue
    case "$fdir/" in "$sbxreal"/*) ;; *) continue ;; esac      # MUST be physically inside the sandbox: a newline-split manifest
                                                               # fragment resolving to the caller's CWD (or anywhere else) is
                                                               # refused, so no unrelated file is ever copied into OUTPUT-DIR
    curtmp=$(mktemp "$out/.grokpub.XXXXXX" 2>/dev/null) || { fail=1; break; }   # temp IN $out (same fs as dest)
    cat "$f" > "$curtmp" 2>/dev/null || { fail=1; break; }     # copy full content; dest not yet visible
    b=${f##*/}; dest="$out/$b"; n=1
    while :; do
      pending="$dest"                                          # record intended dest BEFORE the ln (closes the ln-success->record window); rollback verifies OWNERSHIP by inode, so a failed ln on a pre-existing name is safe
      if ln "$curtmp" "$dest" 2>/dev/null; then break; fi       # ATOMIC + no-clobber + no-follow; on success $dest and $curtmp share an inode
      pending=""                                               # ln failed -> we did NOT create $dest
      if [ -e "$dest" ] || [ -L "$dest" ]; then                 # name taken (incl. a symlink) -> next free name
        case "$b" in *.*) dest="$out/${b%.*}-$n.${b##*.}" ;; *) dest="$out/$b-$n" ;; esac
        n=$((n + 1)); [ "$n" -gt 9999 ] && { fail=1; break; }; continue
      fi
      # ln failed with the name FREE -> the OUTPUT-DIR filesystem has no hard-link support. POSIX shell
      # has no atomic, no-clobber, NO-FOLLOW way to publish without a hard link (reserve-then-fill re-opens
      # the path and can follow a swapped symlink; mv clobbers), so FAIL CLOSED — never publish unsafely.
      # Put OUTPUT-DIR on a hard-link-capable fs (APFS/ext/xfs/tmpfs...).   [NO-HARDLINK-FAILCLOSED]
      fail=1; break
    done
    [ "$fail" = 1 ] && { [ -n "$curtmp" ] && rm -f "$curtmp" 2>/dev/null; curtmp=""; break; }
    published="$published$dest
"                                                            # record dest BEFORE dropping curtmp, so rollback always covers it (via $published or the -ef in-flight check)
    [ -n "$curtmp" ] && rm -f "$curtmp" 2>/dev/null; curtmp=""  # drop the temp link (dest keeps the inode)
    pending=""                                                 # dest now recorded in $published
  done < "$base/manifest"
  if [ "$fail" = 1 ] || [ "$rc" != 0 ] || [ -z "$published" ]; then
    _rollback
    if [ "$rc" = 124 ]; then exit 124; fi                      # timeout keeps its OWN distinct code (message already printed)
    if [ "$fail" = 1 ]; then echo "grok_media: could not publish into $out — rolled back this call's output" >&2
    elif [ "$rc" != 0 ]; then echo "grok_media: grok exited $rc — rolled back this call's output" >&2
    else echo "grok_media: grok produced no media artifact" >&2; fi
    exit 3
  fi
  printf '%s' "$published"
  exit 0
)
```

Why it's built this way:

- **Hermetic child environment (`env -i` allowlist).** grok is launched with `env -i` plus an explicit
  allowlist — only `PATH` (a minimal `/usr/bin:/bin:/usr/sbin:/sbin`), `HOME`, `GROK_HOME`, `TMPDIR`,
  `TERM`, the telemetry-off master switches, and exactly ONE auth var are passed. Everything else in
  your shell is dropped before grok sees it: your unrelated secrets (`AWS_*`, `GITHUB_TOKEN`, other
  providers' keys) AND grok's own behaviour-changing overrides — endpoint/gateway/proxy redirects
  (`XAI_API_BASE_URL`, `GROK_XAI_API_BASE_URL`, `GROK_GATEWAY_URL`, `GROK_CLI_CHAT_PROXY_BASE_URL`),
  the auth-provider **command** `GROK_AUTH_PROVIDER_COMMAND` (which grok would otherwise *execute* to
  fetch credentials), `GROK_LOG_FILE`, `GROK_MANAGED_CONFIG*`, `GROK_AGENT_ENV*`, and the
  `GROK_<VENDOR>_*_ENABLED` compat toggles. It is an allowlist, not a blocklist: new grok env knobs are
  dropped by default, so the wrapper never has to enumerate all ~150 `GROK_*` / `XAI_*` vars the source
  reads (a blocklist would silently miss any it forgot).
- **Empty synthetic `HOME`** blocks the Claude/Cursor/Codex compat scan. Those scanners resolve
  `~/.claude` / `~/.cursor` / `~/.codex` from `$HOME` (source-verified in the open-sourced tree), so an
  empty `HOME` means there is nothing there to scan or send. Verify on your own machine (empty `HOME` +
  empty temp `GROK_HOME`, auth via `GROK_AUTH_PATH`): `HOME="$(mktemp -d)" GROK_HOME="$(mktemp -d)"
  GROK_AUTH_PATH=~/.grok/auth.json grok inspect` should list zero `.claude` / `.cursor` / `.codex`
  instruction / skill / MCP / hook entries.
- **Clean temporary `GROK_HOME`** (a temp dir, NOT your real `~/.grok`) blocks grok's OWN globals.
  grok's native `~/.grok/AGENTS.md` / skills / hooks / MCP load from `$GROK_HOME` (source-verified:
  the loader always scans `grok_home()`), so pointing `GROK_HOME` at an empty temp stops them loading
  into the turn — the improvement over the earlier design, which used the real `~/.grok` and therefore
  still loaded `~/.grok/AGENTS.md`. The minimal `config.toml` written into that temp also pins
  `[features] telemetry = false`, `[telemetry] trace_upload = false`, every `[compat.claude]` /
  `[compat.cursor]` / `[compat.codex]` cell `false`, and `[folder_trust] enabled = false` (so a
  headless `-p` run in the fresh dir isn't gated) — all source-recognised keys (`xai-grok-config` /
  `xai-grok-telemetry` / `xai-grok-tools`). It also writes `[harness] disable_codebase_upload = true`,
  which is **NOT** in the audited source: the config loader parses to a lenient `toml::Value`
  (`loader.rs`), so an unknown key is accepted-then-ignored (`serde_ignored`) — it does nothing on this
  source and cannot void the other keys. It is kept ONLY as **binary-observed defense-in-depth**; the
  real codebase-upload defence is the empty non-git CWD below, not this key. grok's precedence is
  `env > config` (`flags.rs`; `TelemetryConfig::apply_env_overrides`), so a config pin alone is not
  authoritative — but under the hermetic `env -i` there are no inherited telemetry/upload/endpoint vars
  left to outrank it, and the three master switches are additionally forced off explicitly.
- **Auth without the wrapper touching your credential store.** Subscription login → `GROK_AUTH_PATH`
  points at your REAL `auth.json`, resolved with grok's own precedence
  (`GROK_AUTH_PATH` → `${GROK_HOME:-$HOME/.grok}/auth.json`; source: `auth/manager.rs:296` +
  `paths.rs` `grok_home()`) and absolutised before any `cd`; grok reads and refreshes it in place, and
  the wrapper never reads, parses, copies, hashes, or syncs it. API key → `XAI_API_KEY` (or legacy
  `GROK_CODE_XAI_API_KEY`); no auth file is touched. The two branches are mutually clean by
  construction: under `env -i` the subscription branch passes ONLY `GROK_AUTH_PATH` (so higher-priority
  inline `GROK_AUTH`, plus `XAI_API_KEY` / `XAI_ROOT` / `XAI_USER`, are all absent), and the API-key
  branch passes ONLY `XAI_API_KEY` (so `GROK_AUTH_PATH` / `GROK_AUTH` / `GROK_DISABLE_API_KEY_AUTH` are
  all absent). Missing/unreadable subscription auth fails closed (no grok call). `set +eux` disables
  xtrace inside the subshell, so a `set -x` caller can never trace the key onto stderr.
- **Empty non-git working dir + tool restriction** is belt-and-suspenders against the unverifiable
  binary: a text relay needs no tools, so `grok_relay` denies all (`--deny '*'`), and even if the
  shipped binary diverged from the audited source there is no repo in the working dir to bundle. The
  dir is its own clean temp (separate from `HOME` and `GROK_HOME`), and the wrapper **verifies it sits
  outside any git worktree** by walking up for a `.git` — it does **not** trust `TMPDIR`: if `TMPDIR`
  points into a repo, the call aborts rather than run grok inside your tree. `grok_media` swaps
  `--deny '*'` for a media-only `--tools` allow-list, plus `--disallowed-tools search_tool,use_tool` to
  strip the always-on MCP meta-tools (binary-observed on 0.2.101: `image_gen` still runs under those
  flags). grok runs in the empty temp CWD, never your output dir; `grok_media` writes media under the
  temp `GROK_HOME` session dir (source: `paths.rs` `sessions_cwd_dir` = `grok_home()/sessions/…`), then
  publishes only this call's artifacts by copying each into a temp in the output dir and **hard-linking**
  it into place — the ONE atomic, no-clobber, no-follow publish primitive. A no-hardlink filesystem
  **fails closed** (no `mv`, no reserve-then-fill — a reopen-by-path could follow a swapped symlink). It
  also fails closed before publishing on any newline-in-name, and refuses any file not physically inside
  the sandbox (a newline-split manifest fragment pointing outside is refused). The answer file (relay)
  and the media manifest live in a **separate control base** grok is never handed a path to, read/written
  only after a regular-file/no-symlink check and an `rm`-of-any-pre-existing — which neutralises a
  symlink/FIFO planted ahead of the operation and raises the bar against a temp-enumerating binary, but
  is **not a jail**: a same-UID binary that wins the check/open race needs an OS sandbox to stop (see
  SECURITY.md). On any failure / timeout / signal the publish rolls back ONLY this call's own files
  (completed + in-flight) and **never removes the output dir** (a rolled-back call that created it leaves
  it in place — usually empty; see the local `.grokpub` signal-window note in SECURITY.md — avoiding a
  reverse-timing race with a concurrent call about to publish there).
- **Subshell + real watchdog + process-tree cleanup.** Each helper is a subshell `name() ( … )` with
  `set +eux` so it never inherits the caller's `errexit` / `nounset` / `xtrace`; everything lives under
  one `mktemp -d` base with the `EXIT` trap armed **before** any sub-dir is created (a mid-setup
  failure won't leave a temp dir behind). grok runs under a **real watchdog timeout** (`GROK_RELAY_TIMEOUT`,
  default 300s; `GROK_MEDIA_TIMEOUT`, default 600s); on timeout or on `INT` / `TERM` / `HUP` the helper
  reaps grok's **process tree** (child + any grandchildren, via a `ps`-walk) and removes the base
  — no orphaned process, no leftover temp dir. (A `Ctrl-C` in the foreground also reaches grok directly
  through the terminal's process group.)
- Set **`XAI_API_KEY`** (metered) to skip the subscription login entirely — then no auth file is read
  at all. Full background and the source-audit detail are in [SECURITY.md](SECURITY.md).

## Preflight: is the model available?

Before attempting a model, confirm its CLI is installed AND authenticated. Skip any model that
fails the check — never brute-force a missing binary, retry with different flags, or silently
substitute a different model to fill the gap.

| Model | Binary check | Auth / plan check |
|-------|--------------|-------------------|
| GPT (Codex) | `command -v codex` | fails fast with an auth error when logged out (`codex login`) |
| GLM via OpenCode | `command -v opencode` | `opencode auth list` shows a Z.AI credential |
| GLM via ZCode | `command -v zcode` (add a PATH wrapper if only the app is installed) | `~/.zcode/cli/config.json` exists or `ZCODE_API_KEY` is set. `zcode login` is currently broken — see [references/cli-reference.md](references/cli-reference.md) |
| Grok | `command -v grok` | Run `grok models` (a catalog fetch — no repo bundle, no model turn). Grok is available if the output lists models (`Default model:` / `Available models:`), EVEN IF a "You are not authenticated." line appears above the list — that header just mirrors an expired cached token that the same call silently refreshes before fetching the catalog. Only "not authenticated" with NO model list is a real problem: auth.json missing → logged out; auth.json present → confirm with one bounded real call via `grok_relay`. Walk the availability ladder in [references/cli-reference.md](references/cli-reference.md) |
| Gemini via Antigravity | `command -v agy` | `agy models` lists the model menu when logged in; the default model comes from the user's Antigravity config |
| Claude | in-session already (native subagent); `command -v claude` only for headless | current session auth |

Rules:
- Missing binary or failed auth means that model is unavailable. Report it plainly ("Grok CLI not
  installed / not logged in — skipping") and continue with the models that ARE available.
- If the user asked for ONLY an unavailable model, stop and ask how to proceed (install it, or
  use an available one). Do not quietly answer with a different model.
- No subscription / plan makes the run error quickly — surface that error, do not keep retrying.
- GLM has two first-class setups — use whichever the user already has: OpenCode (standalone
  terminal agent) or the ZCode desktop app's bundled `zcode` command. `zcode` ships INSIDE the
  app; there is no separately installable ZCode CLI, and the npm packages named `zcode` /
  `zcode-cli` are unrelated third-party stubs — never install them.

## Custom targets

Users can connect additional one-shot model CLIs — local models (Ollama, LM
Studio, Apple MLX) or other providers — by declaring them in
`~/.agents/relay-targets.json`. Read
[references/custom-targets.md](references/custom-targets.md) the first time a
session needs the target list: each entry carries its own binary/auth preflight
and an invoke template, and joins every flow in this skill (offers, consensus
bursts) as a first-class lane. The preflight and compliance rules above apply to
custom targets unchanged. **If a custom target wraps a CLI that runs an agent in the
caller's working directory, treat it like any cloud agent — it can transmit whatever
it reads, so relay only the prompt, never point it at the repo.** The registry is
user-authored configuration: only read it — never create, edit, or repair it on the
user's behalf.

## Compliance gate: check the orchestrator and the target

This skill is portable — it may run inside Claude Code, Codex CLI, or an OpenClaw / Nous
Research (Hermes) agent whose main model is anything. Before any handoff, two independent checks.

### Check 1 — do not hand off to the model you already are

Reaching a *different* provider's model is what needs a headless CLI. Reaching the SAME provider
(for fresh context or to delegate a subtask) should use the orchestrator's native subagent:
cheaper, no subprocess, and it stays inside the harness's own session accounting.

| Orchestrator | Same-provider model | Other-provider model |
|--------------|---------------------|----------------------|
| Claude Code | Agent tool subagent (`fable`/`opus`/`sonnet`) | headless CLI |
| Codex CLI | Codex native subagents (`[agents]` config; ask "spawn one agent per…") | headless CLI |
| OpenClaw / Hermes / other | the harness's own subagent / task mechanism | headless CLI |

So a Codex-driven session that wants GPT should spawn a Codex subagent, not nest `codex exec`.
It reaches Claude/GLM/Grok only through a headless CLI — subject to Check 2.

### Check 2 — the target model's provider terms bind you

Reaching another provider's model is governed by THAT provider's terms, and being a non-native
harness (Codex, OpenClaw, Hermes) is exactly the trigger.

| Target | Constraints from a non-native harness |
|--------|----------------------------------------|
| Claude | Graded gate. HARD bans: reusing subscription OAuth in a non-Anthropic client (blocked April 2026 — foreign clients need a metered API key), reverse-engineering the harness/auth, and competing-model development (Commercial Terms D.4). TOLERATED today: shelling out to the genuine first-party `claude -p` with the user's own login at occasional second-opinion volume — Anthropic's pool split that would meter this was paused June 2026; keep volume low, avoid always-on pipelines on a Pro/Max plan. Fable 5 hands frontier-LLM-dev tasks to Opus 4.8 (visible fallback). Detail: [references/anthropic-terms.md](references/anthropic-terms.md) |
| GPT (Codex) | ChatGPT-plan OAuth from third-party harnesses is officially permitted (May 2026, OpenClaw explicitly endorsed). Plan credentials reach OpenAI models only. Using Output to develop competing models is banned (ToU, Jan 2026). |
| Grok | xAI Acceptable Use Policy + Enterprise ToS prohibit using the Service or Output to develop competing models, and ban scraping, reselling, or distilling Output. |
| Gemini (Antigravity) | Gemini API Additional Terms (updated March 2026) prohibit using the Services to develop models that compete with them, and ban reverse engineering / extracting / replicating components including model weights. Note the agy model menu also serves Claude and GPT-OSS models under Google's platform terms. |
| GLM | Coding Plan is limited to officially supported tools — Claude Code, OpenCode, OpenClaw, and Hermes Agent are all on the current list. Open-weight (MIT), no sharp competing-model clause, but quota / fair-use enforcement is aggressive. |

Two rules hold regardless of orchestrator. First, check the target provider's stance on
subscription auth from non-native harnesses: Anthropic blocks foreign CLIENTS on subscription
creds (metered API key for those) while currently tolerating occasional calls into the genuine
`claude -p` binary; OpenAI explicitly permits plan OAuth in third-party harnesses; Z.ai ties
the plan to its supported-tools list. Second, never use any model to build or train a
competing model or to reverse-engineer a harness. A Nous Research / Hermes agent working on
Hermes models is therefore barred from the Claude AND Grok branches for that work; GLM
(open-weight, and Hermes Agent is officially supported) is the most permissive target.

## Copy-paste baseline commands

For Codex, GLM, Gemini, and Claude these are minimal forms — the model reasons over the prompt
text you give it. Codex's default sandbox is read-only with no network; GLM/Gemini/Claude run
agentic but were wire-verified not to upload your repo. **Grok goes through the `grok_relay` helper
(empty `HOME` + clean temp `GROK_HOME` so it can't read your other tools' config or grok's own global
rules; see the Grok section). It is still a cloud model — never present it as "read-only" or "local".**

```bash
# GPT (Codex) — default sandbox is read-only, no network
codex exec "your question here"

# GLM via OpenCode
echo "your question here" | opencode run -m "zai-coding-plan/glm-5.2" --variant max

# GLM via the ZCode app's bundled CLI (one-time setup: references/cli-reference.md)
zcode --prompt "your question here"

# Grok — via the grok_relay helper (define it once, see the Grok section above): empty HOME + clean
#        temp GROK_HOME so it can't read your ~/.claude config or grok's own globals; auth via
#        GROK_AUTH_PATH (your real auth.json, which grok refreshes in place) or XAI_API_KEY; tools denied.
#        Still a cloud model — never present it as "read-only" or "local".
grok_relay "your question here"

# Gemini via Antigravity — model name is the display string from `agy models`
agy -p "your question here" --model "Gemini 3.1 Pro (High)"

# Claude (headless subprocess)
claude -p "your question here" --model fable
```

## How to pass the prompt (three forms)

| Prompt shape | Form | Example |
|--------------|------|---------|
| Short, one line, no special chars | Inline argument or `echo … \|` | `codex exec "is this regex safe?"` |
| Long, multi-line, or contains backticks / `$` / quotes / a diff | File + stdin | write `/tmp/handoff.md`, then `< /tmp/handoff.md` |
| Programmatic content blocks | JSON flag | `grok --prompt-json '…'` — run it through the `grok_relay` shape (empty HOME + clean temp GROK_HOME + `GROK_AUTH_PATH`/`XAI_API_KEY` + `--deny '*'`); swap `-p "$1"` for `--prompt-json "$1"` in a copy of the helper |

**Why a file for anything non-trivial:** passing a long prompt inside `"…"` lets the shell
interpret backticks (`` ` ``) as command substitution, `$` as variables, and newlines/quotes
break the quoting. Writing the prompt to a file and feeding it on stdin passes the bytes
verbatim. This is the same reason `gh … --body-file` beats `--body "…"`.

`stdin` = a command's standard input stream. Two equivalent ways to fill it:
- `< /tmp/handoff.md` — redirect the file's contents into the command's stdin.
- `cat /tmp/handoff.md | cmd` — `cat` prints the file, the pipe `|` feeds it to `cmd`'s stdin.

Per-CLI stdin behavior:

```bash
# Codex: reads stdin when no prompt arg is given (or when the arg is "-")
codex exec < /tmp/handoff.md

# OpenCode: no stdin-redirect; pipe it
cat /tmp/handoff.md | opencode run -m "zai-coding-plan/glm-5.2" --variant max

# ZCode: no stdin mode — substitute the file into the arg (a quoted "$()" passes the
# bytes verbatim; the file's backticks/$ are NOT re-interpreted by the shell)
zcode --prompt "$(cat /tmp/handoff.md)"

# Grok: pass the file's bytes as the inline arg via command substitution — the grok_relay helper
# uses `grok -p`, so no file needs to be readable from the isolated CWD. "$(cat …)" is NOT
# re-interpreted, so backticks/$ in the file are safe (same reason `gh --body-file` beats --body).
grok_relay "$(cat /tmp/handoff.md)"

# Antigravity: no stdin mode — substitute the file into the arg
agy -p "$(cat /tmp/handoff.md)"

# Claude: command-substitute the file into the prompt arg
claude -p "$(cat /tmp/handoff.md)" --model fable
```

## Scenarios

### Scenario A — quick one-off question to one model
Use the inline baseline command above. Read the stdout, summarize. For Codex this is read-only
with no network; for **Grok** use the `grok_relay` helper — it is a cloud model (never "no
network"), and the helper keeps your other tools' config AND grok's own global rules out of the turn.

### Scenario B — long prompt (a diff, a file, a spec)
1. Write the full context to `/tmp/handoff.md` (question at the top, then the code/diff).
2. Feed it via the per-CLI stdin form above.
3. Summarize the model's answer; quote its concrete file:line claims verbatim.

### Scenario C — parallel multi-model second opinion / consensus
Run 2+ models on the SAME prompt file at once (independent shell calls in one message so they
run concurrently), then compare where they agree and diverge.

```bash
codex exec < /tmp/handoff.md > /tmp/ans-gpt.md 2>/dev/null &
cat /tmp/handoff.md | opencode run -m "zai-coding-plan/glm-5.2" --variant max > /tmp/ans-glm.md 2>/dev/null &
# Grok lane — grok_relay runs with empty HOME + clean temp GROK_HOME (no config leak) + tools denied:
grok_relay "$(cat /tmp/handoff.md)" > /tmp/ans-grok.md 2>/dev/null &
wait
# Gemini runs SEQUENTIALLY, AFTER the burst — agy 1.1.0 wedges inside a 3+ CLI burst (see below):
agy -p "$(cat /tmp/handoff.md)" --model "Gemini 3.1 Pro (High)" > /tmp/ans-gemini.md 2>/dev/null
```

On a machine with ZCode instead of OpenCode, swap the GLM lane:
`zcode --prompt "$(cat /tmp/handoff.md)" > /tmp/ans-glm.md 2>/dev/null &`

Gemini caution: run the `agy` lane SEQUENTIALLY (before the burst or after it finishes), not
inside it — agy 1.1.0 reliably wedges when started alongside 3+ other concurrent model CLIs
(solo and pairwise runs are fine; a 5s stagger does not help). It is fast solo (~10-30s). See
the Antigravity section of [references/cli-reference.md](references/cli-reference.md).

Then read the answer files and present a merged view: shared findings first, then each model's
unique points, then contradictions to resolve. A finding cited with a specific file:line by one
model beats a vague agreement from the others — verify before dismissing it as an outlier.

### Scenario D — the model must read the repo or run git/gh
Only Codex needs special handling: its default sandbox blocks file writes AND the network.
Sandbox and network are independent axes — enable both explicitly:

```bash
codex exec --sandbox workspace-write \
  -c 'sandbox_workspace_write.network_access=true' \
  "review the uncommitted changes and flag correctness bugs"
```

`codex exec` is non-interactive and never prompts for approval. Do NOT pass
`--ask-for-approval` — exec rejects it with `unexpected argument` (that flag belongs to
interactive `codex`). `--full-auto` still parses but is a hidden deprecated compat alias: it
sets `--sandbox workspace-write` and pins approvals to `never` — it does NOT enable network,
and it suppresses any config-driven approval escalation. Also note `codex exec` LOADS
`~/.codex/config.toml` (`sandbox_mode`, `approval_policy`, reviewer features), so headless
behavior varies per machine — pass explicit flags, or add `--ignore-user-config` when you need
machine-independent runs. OpenCode runs agentic with repo access in its default run mode.

**Grok is not the lane for repo- or diff-context work** — the `grok_relay` helper denies all tools
and runs in an empty dir, so Grok never reads your repo (by design: it relays only the prompt you
give it). For "read the repo / review the diff / run git", use Codex (above), Gemini, GLM, or
Claude, which read files in place. To get Grok's take on a diff, capture it to a file and pass the
text: `grok_relay "$(cat /tmp/diff.txt)"`.

### Scenario E — structured JSON output for scripting

| CLI | Flag | Extract the answer |
|-----|------|--------------------|
| Codex | `--json` (JSONL events) or `-o out.txt` (last message to file) | parse JSONL, or read `out.txt` |
| OpenCode | `--format json` | `jq` over the raw event JSON |
| ZCode | `--json` | `jq -r '.response'`; session id = `.sessionId`, token usage under `.usage` |
| Grok | `--output-format json` | `jq -r '.text // .result'` |
| Antigravity | (none) | No JSON mode — stdout is plain text; capture and use it directly |
| Claude | `--output-format json` | `jq -r '.result'`; session id = `.session_id`, cost = `.total_cost_usd` |

```bash
result=$(claude -p "summarize the repo" --model fable --output-format json)
echo "$result" | jq -r '.result'
```

### Scenario F — multi-turn / resume a session
Every CLI is stateless per headless call unless you thread the session id (run from the same
directory).

```bash
sid=$(claude -p "start a review" --model fable --output-format json | jq -r '.session_id')
claude -p "now check the error paths" --resume "$sid"
```

`codex exec resume --last`, `opencode run -c` (continue) or `-s <id>`, `grok -r [id]` /
`grok -c`, `zcode --resume sess_<id>` / `zcode -c`, `agy -c` / `agy --conversation <id>` are
the equivalents. See [references/cli-reference.md](references/cli-reference.md). **Grok caveat:**
`grok_relay` uses a fresh temp working dir per call and Grok keys sessions by working dir, so
relayed calls don't resume one another. For multi-turn Grok work, run `grok` yourself from one
stable dir (point `HOME` and `GROK_HOME` at empty dirs, and auth via `GROK_AUTH_PATH`, to keep both
config leaks closed), or use another lane.

### Scenario G — built-in code review of the current repo
Use **Codex** for repo-diff review; its review affordance beats a hand-written prompt:

```bash
codex exec review --uncommitted          # reviews staged + unstaged + untracked
```

Prefer Codex for repo review. `grok --check` runs Grok in the repo with its tools, so it reads
your files and (as a cloud model) transmits what it reads. If you want Grok's opinion on a diff,
capture it to a file (`git diff > /tmp/diff.txt`) and pass the text through `grok_relay` (tools
denied, empty working dir) — don't point Grok at the repo itself.

### Scenario H — image / video generation (not just text)
Media generation is model-agnostic — use whichever lane the user prefers. **Images**: Codex or
Gemini (agy) generate them with no whole-repo bundle (still cloud models that transmit what they
read); Grok can too, via `grok_media`.
**Video**: only Grok has it (`image_to_video`, `reference_to_video`), so video means a `grok_media`
call. The pattern: tell the model to call its image tool IMMEDIATELY, save to the working
directory, print the path, then read it back.

Codex and agy do NOT bundle the repo (wire-verified), so they may write straight into your output
directory:

```bash
# GPT (Codex): built-in image_gen. Two reliability rules (see reference for the why):
#   1. Avoid `ultra` effort — it auto-delegates subagents and spirals into doc lookups
#      instead of calling the tool. `max` and below work fine (max ran in ~55s).
#   2. Redirect stdin from /dev/null — a positional-arg prompt can otherwise block on
#      "Reading additional input from stdin". macOS has no `timeout`; use perl's alarm.
cd /path/to/output-dir
perl -e 'alarm shift; exec @ARGV' 480 \
  codex exec --sandbox workspace-write -c model="gpt-5.6-sol" \
  -c model_reasoning_effort="max" "$(cat /tmp/img-brief.md)" </dev/null

# Gemini (agy): native generate_image tool, works headless. Run it SOLO (the agy parallel-burst
# hang applies to media too); the Google-account login covers it — no API key, no OpenRouter.
cd /path/to/output-dir
agy -p "$(cat /tmp/img-brief.md)" --model "Gemini 3.1 Pro (High)" --add-dir "$PWD" </dev/null
```

Grok media (image or video) goes through the `grok_media` helper (define it once, see the Grok
section): empty `HOME` + clean temp `GROK_HOME` (no config leak), auth via `GROK_AUTH_PATH` or
`XAI_API_KEY`, a media-only `--tools` allow-list (MCP meta-tools stripped). grok runs in an empty
non-git dir (never your output dir); media is written under the temp `GROK_HOME`, then the helper
publishes only this call's artifacts into your output dir (collision-safe, rolled back on failure):

```bash
# grok_media BRIEF-FILE OUTPUT-DIR — empty HOME + clean temp GROK_HOME, media tools only. The brief
# tells Grok to call image_gen and save to the current directory (the temp GROK_HOME session dir);
# the helper then publishes that artifact into OUTPUT-DIR, collision-safe, rolled back on failure.
grok_media /tmp/img-brief.md /path/to/output-dir
```

Briefs must say: "call your image tool immediately — do NOT research docs, spawn subagents, or
use any skill — generate <description>, save to the current directory, print `SAVED: <path>`."
Tool names differ: Grok/Codex = `image_gen`, agy = `generate_image`. Codex also mirrors outputs
to `~/.codex/generated_images/<session>/`.

Per-target support (detail in [references/cli-reference.md](references/cli-reference.md)):

| Target | Headless media generation |
|--------|---------------------------|
| GPT (Codex) | YES — built-in `image_gen` via `codex exec`; avoid `ultra` (auto-delegation spiral, `max` works in ~55s), close stdin (`</dev/null`), direct "call the tool now" prompt (verified: blue-circle + green-square PNGs). No whole-repo bundle (still a cloud image API) |
| Gemini (agy) | YES (image only) — native `generate_image`, no API key / no OpenRouter (Google login covers it), ~34s, writes to cwd (verified: orange-triangle JPG). Run SOLO — the agy parallel-burst hang applies. No native video tool. No whole-repo bundle (still a cloud image API) |
| Grok | YES — `image_gen` / `image_edit` / `image_to_video` / `reference_to_video`, Imagine backend; the ONLY lane with video. Run via **`grok_media`** (hermetic `env -i` + empty HOME + clean temp GROK_HOME; allow-lists ONLY the 4 media tools with `--tools` — `--deny '*'` would block image_gen — binary-observed on 0.2.101). grok runs in an empty non-git dir; image_gen writes under the temp GROK_HOME, and the helper publishes the artifact into your output dir by copying it to a temp there and atomically hard-linking it to a free name (no-clobber, no-follow; a no-hardlink fs and newline-in-name both **fail closed**; rolls back only this call's own files on failure and never removes the output dir). The answer/manifest live in a separate control base grok is never given a path to |
| GLM / Claude | No headless image generation in these CLIs |

## Claude target: subprocess vs in-session subagent

First clear the compliance gate above — both methods below are off-limits when a non-Anthropic
harness is the orchestrator. Two ways to hand off to Claude, and they are NOT interchangeable:

| Method | When to use |
|--------|-------------|
| Native subagent (e.g. Agent tool, `model: "fable"`) | Default. In-session, no subprocess, result returns straight to the orchestrator. Cheapest. |
| `claude -p … --model fable` | When Claude must run truly parallel alongside the codex/opencode/grok subprocesses in one shell burst, or you need a clean JSON transcript with its own session id. |

An orchestrator's native subagents spawn its OWN provider's models only — they cannot reach
another provider. That is why cross-provider targets ALWAYS require a headless shell call,
while a same-provider second opinion should stay in-session as a subagent.

## Orchestration rules

1. The orchestrating agent does the work. The user only says "ask X" — the orchestrator
   prepares the prompt, picks inline vs file, runs the shell command(s), and reports the result.
2. Default to the read-only baseline. Escalate to `workspace-write` + network (Codex) only when
   the model genuinely must touch the repo — never silently.
3. For multi-model runs, launch all commands in one message so they run concurrently, then
   `wait`.
4. Never paste secrets into a prompt file or command. Reference config by name only.
5. Report faithfully: if a model errored or timed out, say so with its stderr — do not fabricate
   an answer.
6. **Grok goes through `grok_relay` / `grok_media`.** They run it under a hermetic `env -i` (only an
   allowlist reaches grok) with an empty `HOME` + a clean temp `GROK_HOME` (so it can't read your
   `~/.claude` / `~/.cursor` / `~/.codex` config OR grok's own `~/.grok/AGENTS.md` into the turn) with
   tools denied; never hand-roll a raw `grok` call for a relay. It stays a cloud model — relay only the
   prompt you give it, never point Grok at the repo.

## Reference files

| File | Contents |
|------|----------|
| [SECURITY.md](SECURITY.md) | **Grok data egress**: the historical whole-repo upload, xAI's 2026-07-15 open-sourcing + the source audit, the residual concerns (global-rule leak, unverifiable binary), and per-user hardening / migration for people who already ran Grok |
| [references/cli-reference.md](references/cli-reference.md) | Full per-CLI flag tables, model ids, ZCode setup recipes, output-format shapes, session resume, sandbox/network detail, the Grok data-egress detail, troubleshooting |
| [references/anthropic-terms.md](references/anthropic-terms.md) | Compliance detail: Anthropic subscription-routing block, Commercial Terms D.4, Fable 5 safeguards, enforcement history, plus the OpenAI / xAI / Z.ai / Google provider-terms matrix, with citations |
| [references/reprompter-relay.md](references/reprompter-relay.md) | Pairing recipe: run a prompt-engineering skill (e.g. RePrompter) before relaying a nontrivial task; documents the RePrompter handoff contract |
| [references/custom-targets.md](references/custom-targets.md) | User-connected targets: `~/.agents/relay-targets.json` registry for local models (Ollama, LM Studio, MLX) and other one-shot CLIs — field contract, preflight, security rules |

## Troubleshooting (core)

| Symptom | Fix |
|---------|-----|
| You ran an OLD `grok` (pre-open-source) inside a real repo | Earlier shipped versions uploaded the whole repo + git history to xAI. Update grok; follow [SECURITY.md](SECURITY.md) to check your logs and rotate any exposed secrets. New calls via `grok_relay` relay only the prompt |
| "Is the Grok lane read-only / local?" | No — Grok is a cloud model; your prompt goes to xAI. `grok_relay` keeps your other tools' config and grok's own globals out of the turn and denies tools, but never call it "read-only" or "local" |
| Codex: `unexpected argument '--ask-for-approval'` | `codex exec` never prompts; drop the flag (Scenario D) |
| Codex: "network access restricted" / `gh` fails | Add `--sandbox workspace-write -c 'sandbox_workspace_write.network_access=true'` (Scenario D) |
| Codex answer seems shallow | GPT-5.6 models default to LOW reasoning effort — pass `-c model_reasoning_effort="high"`/`"ultra"` explicitly |
| Prompt with backticks / `$` mangled or runs as a command | Use the file + stdin form, not inline `"…"` |
| Grok stderr shows `AuthorizationRequired` / `Skipping MCP tool` but stdout arrives | Cosmetic startup noise — pipe `2>/dev/null` |
| `grok models` prints "You are not authenticated." — but a model list appears right below it | Cosmetic: the header mirrors the expired cached token read at process start; the same call then refreshes the token and fetches the catalog. A model list in the output means Grok is **available** — do not skip the lane. Only "not authenticated" with NO model list is real (auth.json missing → `grok login`; auth.json present → one bounded real call decides). See the Grok availability ladder in [references/cli-reference.md](references/cli-reference.md). `--yolo` / `--always-approve` are permission flags, never an auth fix |
| Grok `-p` prints nothing for 2+ minutes (stderr may show `worker quit with fatal: Transport channel closed, when Auth(AuthorizationRequired)`, or nothing at all) | The run hangs instead of exiting. Kill it; if the fatal auth line is present run `grok login` and retry once; if it hangs again the relay/service side is down — skip Grok and report it. Always wrap unattended grok calls in a timeout |
| Grok cites unrelated tweets / web pages | You're not going through `grok_relay` — its `--deny '*'` blocks the web-search tool. Route the call through the helper |
| Grok says a tool was "blocked by policy" | Expected under `grok_relay`'s `--deny '*'` — a text relay needs no tools, the text answer still arrives. For media use `grok_media` (allow-lists only the 4 media tools via `--tools`, so image_gen still runs) |
| Grok's answer references your `~/.claude` rules / `AGENTS.md` / a convention you didn't send | The isolation was skipped (raw `grok` call). `~/.claude` / `~/.cursor` rules load from `$HOME` (compat scan); `~/.grok/AGENTS.md` loads from `$GROK_HOME` (grok's own scan). Always call through `grok_relay` / `grok_media` — they run under an empty `HOME` AND a clean temp `GROK_HOME`, closing both |
| Grok: `Couldn't set model 'grok-build': … "unknown model id"` | `grok-build` was retired from the CLI when grok-4.5 launched (July 2026) — use `-m grok-4.5` |
| zcode: `Model config is missing. Create ~/.zcode/cli/config.json …` | One-time setup — follow the ZCode recipes in [references/cli-reference.md](references/cli-reference.md) |
| `zcode login`: `OAuth response is not valid JSON` | Known open bug — skip login entirely; use the config-file or env-var recipe instead |
| OpenCode `-f` file attach errors | Pipe via stdin instead (`cat file \| opencode run …`) |
| agy reads/writes files in `~/.gemini/antigravity-cli/scratch` instead of your repo | Antigravity's default working dir is its own scratch workspace — pass `--add-dir /path/to/repo` (it becomes the working directory) |
| agy: `flag needs an argument: -print` | No stdin pipe — use `agy -p "$(cat /tmp/handoff.md)"` |
| agy `-p` never returns when launched inside a parallel multi-CLI burst | Known agy 1.1.0 timing bug (solo/pairwise runs are reliable) — run the Gemini lane sequentially around the burst, and always cap it with a timeout |
| GLM cites a CI/workflow/env change not in the diff | Known GLM infra-hallucination — verify against the actual file before acting |
| A CLI is missing or unauthenticated | Report it and skip that model; do not substitute another silently |
| A non-Anthropic harness (OpenClaw / Hermes) triggered this skill | Apply the graded Claude gate: never reuse subscription auth in a foreign client, never do competing-model work; occasional handoffs into the genuine `claude -p` are tolerated today (keep volume low). When in doubt, use Codex / GLM / Grok / Gemini. See [references/anthropic-terms.md](references/anthropic-terms.md) |

See [references/cli-reference.md](references/cli-reference.md) for the full table.
