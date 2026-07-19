---
name: headless-relay
description: Headless handoff guide for running other AI models from inside an agent session (any Agent Skills runtime - Claude Code, Codex, Grok Build, Cursor, OpenClaw, Hermes). Covers GPT (codex exec), GLM (opencode run or zcode --prompt), Kimi K3 (native kimi -p), Grok (grok -p), Gemini (Antigravity agy -p), and Claude (claude -p or a subagent) - inline vs file prompts, parallel multi-model consensus, JSON output, session resume, image/video generation, provider-terms compliance. Use for "ask codex", "ask GLM", "ask Kimi", "ask grok", "ask gemini", "second opinion", "cross-model review", "generate an image", "run headless", "ask another model".
license: MIT. Complete terms in LICENSE.txt
metadata: {"version": "2.1.0"}
---

# headless-relay

This skill provides instructions for delegating a task to another AI model without leaving the
current agent session. The user says "ask Codex", "get GLM's opinion", "run this by Kimi"; the
orchestrating agent (Claude Code, Codex CLI, or another harness) writes the prompt, runs the
target model's headless CLI through its shell tool, reads the model's stdout, and summarizes
the answer back. Follow these patterns exactly.

## The six targets

| Target | CLI | Headless entry point | Auth / plan |
|--------|-----|----------------------|-------------|
| GPT | `codex` (OpenAI Codex CLI) | `codex exec` | ChatGPT plan or OpenAI API key (`codex login`) |
| GLM | `opencode`, or `zcode` (ships inside the ZCode desktop app) | `opencode run` / `zcode --prompt` | Z.ai Coding Plan (API key or ZCode app login) |
| Kimi K3 | `kimi` (Kimi Code CLI) | `kimi -p` | Kimi membership through native device-code OAuth (`kimi login`) |
| Grok | `grok` (xAI Grok Build) | `grok -p` / `--single` — **⚠️ must run isolated, see the next section** | SuperGrok (`grok login`) |
| Gemini | `agy` (Google Antigravity CLI — replaced the retired Gemini CLI) | `agy -p` / `--print` | Google account via the Antigravity app/CLI |
| Claude | `claude` (Claude Code) | `claude -p`, or the harness's native subagent | Anthropic auth of the current session |

## Kimi text relay — isolate the working directory

Kimi print mode is agentic: it starts in the current directory, uses `auto` permissions, and
cannot be combined with `--plan`. A text-only review therefore runs from a fresh empty non-git
directory with an empty skills directory. This reduces accidental project access; it is neither
full context isolation nor an OS sandbox. Kimi 0.27.0 still loads `$KIMI_CODE_HOME/AGENTS.md` and
`~/.agents/AGENTS.md` from the user's real home; review those files before relay because their
contents enter the model context. Give native Kimi a real repository cwd only for an explicitly
requested agentic task.

Define this helper once and use it for every text-only Kimi call. The helper shell leaves the
real Kimi home untouched: it never reads, copies, moves, or rewrites Kimi's OAuth files. The
first-party CLI itself necessarily reads and may refresh its own OAuth store. The helper also
bounds Kimi's background-task wait, which can otherwise be effectively unbounded.

```bash
# Usage: kimi_relay PROMPT [NATIVE-MODEL-ALIAS] [text|stream-json]
kimi_relay() (
  [ "$#" -ge 1 ] && [ "$#" -le 3 ] || { echo "kimi-relay: usage: kimi_relay PROMPT [MODEL] [FORMAT]" >&2; exit 2; }
  prompt="$1"; model="${2:-${HEADLESS_RELAY_KIMI_MODEL:-kimi-code/k3}}"; format="${3:-text}"
  limit="${HEADLESS_RELAY_KIMI_TIMEOUT_SECONDS:-600}"
  case "$format" in text|stream-json) ;; *) echo "kimi-relay: format must be text or stream-json" >&2; exit 2;; esac
  case "$limit" in ''|*[!0-9]*) echo "kimi-relay: timeout must be a positive integer" >&2; exit 2;; esac
  [ "$limit" -gt 0 ] || { echo "kimi-relay: timeout must be greater than zero" >&2; exit 2; }
  iso="$(mktemp -d "${TMPDIR:-/tmp}/kimi-iso.XXXXXX" 2>/dev/null)" || { echo "kimi-relay: mktemp failed" >&2; exit 1; }
  trap 'rm -rf "$iso" 2>/dev/null' EXIT INT TERM HUP
  skills="$iso/skills"; mkdir "$skills" || exit 1
  if ! command -v git >/dev/null 2>&1 || ! command -v perl >/dev/null 2>&1 \
     || git -C "$iso" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "kimi-relay: cannot verify an isolated non-git cwd or enforce timeout; refusing" >&2; exit 1
  fi
  ( cd "$iso" && perl -e 'alarm shift; exec @ARGV' "$limit" kimi --skills-dir "$skills" \
      -m "$model" -p "$prompt" --output-format "$format" )
)
```

Never invoke `kimi_relay` from cron, a scheduler, or an unattended batch. Native subscription
OAuth is for direct user-triggered turns; use metered Kimi Platform credentials for automation.

## ⚠️ Grok uploads your whole repo — isolation is mandatory

**Read this before any Grok call. It is not optional.**

The xAI Grok Build CLI, when run inside a git repository, packages the **entire tracked repo as
a git bundle — full commit history and every tracked file, including a tracked `.env` — and
uploads it** to an xAI-controlled Google Cloud Storage bucket (`grok-code-session-traces`, via
`POST /v1/storage`). This happens **independently of which files the model reads**, and is
**not** stopped by `--disable-web-search`, by denying file-read permission, by a "do not read
any files" prompt, or by the "Improve the model" toggle. Confirmed by xAI's own Grok account on X
and by independent mitmproxy wire capture (a never-read canary file was recovered from the
uploaded bundle). Full evidence and per-user hardening: [SECURITY.md](SECURITY.md).

A 2026-07-13 wire-test on grok 0.2.99 found the upload currently **off — but only via a
revocable server-side flag** (`trace_upload_source=remote`, `upload_reason=feature_off`); no
local setting is responsible, and the capability is still in the client. xAI can re-enable it
for any account or version at any time, so **do not rely on the current state.** The same test
showed Codex, GLM (opencode), and Gemini (agy) send **no** whole-repo bundle.

**The rule (fail-closed):**

1. **Never run `grok` from the caller's repository, from `$HOME`, or from any directory holding
   real user data.** Running Grok inside a git repo is what triggers the upload.
2. **Every Grok call runs in a fresh, empty, non-git temporary directory**, with context passed
   only via `-p` / `--prompt-file`. No repo in the working directory → no git repo to bundle.
   (Logically sound; it could not be empirically confirmed in the 2026-07-13 test because xAI
   currently server-suppresses the feature — re-verify if they re-enable it.)
3. **Every Grok call also runs with a clean, temporary `GROK_HOME` and a synthetic `HOME`**
   (v2.0.3–2.0.5). Grok otherwise auto-loads your global `~/.grok/AGENTS.md` **and** — via its
   Claude/Cursor compat scanners — your `~/.claude/CLAUDE.md`, `~/.claude/settings.json` hooks,
   skills, plugins, and `~/.claude.json` MCP servers into the model turn, sending them to xAI
   (verified on grok 0.2.99 / 0.2.101). Pointing both `GROK_HOME` and (for the grok process only)
   `HOME` at a throwaway temp, plus a minimal config that disables every compat cell, removes that
   global context — narrowing what leaves your machine to the prompt itself. It does **not** make
   Grok local — see the "Not pure text-in / answer-out" note below the helpers.
4. **If isolation cannot be guaranteed, do not run Grok.** Warn the user (link this section) and
   use another lane.
5. **A task that genuinely needs repo or diff context must NOT go to Grok.** Route it to Codex,
   Gemini, GLM, or Claude — none of which sent a whole-repo bundle in the wire-test (they are
   still cloud models that transmit the files they actually read). Grok relays only the prompt you
   give it — never point it at the repo.

**Two helper functions — define once, use for EVERY Grok call.** Isolation stops the repo bundle; a
clean `GROK_HOME` + synthetic `HOME` (with a minimal safe config) stop the global-rule / `~/.claude`
leak; tool restriction stops the tools. Each helper is a **subshell** (`name() ( … )`, not `{ … }`)
so its `trap` cleans up the temp dirs on every exit path — normal return, error, or a kill signal.
Paste these once; every Grok example below is then a one-liner `grok_relay` / `grok_media` call.

```bash
# grok_relay — TEXT relay. No repo bundle (empty non-git CWD), no global-rule leak (clean
# GROK_HOME + minimal safe config), no tools (--deny '*'), best-effort sandbox. Answer -> stdout.
# Usage:  grok_relay "your question"        long/complex:  grok_relay "$(cat /tmp/handoff.md)"
grok_relay() (
  gh="$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX")"; iso="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
  trap 'rm -rf "$iso" "$gh" 2>/dev/null' EXIT INT TERM HUP   # cleanup on exit + Ctrl-C/group signal
  if [ -z "$gh" ] || [ -z "$iso" ] || ! command -v git >/dev/null 2>&1 \
     || git -C "$iso" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "grok-relay: cannot isolate (mktemp failed, git absent, or temp in a repo); refusing Grok" >&2; exit 1
  fi
  # minimal SAFE config in the clean home: telemetry/upload off, and EVERY Claude/Cursor compat cell
  # (skills/rules/agents/mcps/hooks/sessions) disabled — belt-and-suspenders to the synthetic HOME below.
  printf '[features]\ntelemetry = false\n[telemetry]\ntrace_upload = false\n[harness]\ndisable_codebase_upload = true\n[compat.claude]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n[compat.cursor]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n' > "$gh/config.toml"
  # Auth: copy the subscription token in (or set XAI_API_KEY, metered, to skip the copy entirely).
  [ -n "$XAI_API_KEY" ] || { cp "$HOME/.grok/auth.json" "$gh/auth.json" 2>/dev/null; seed="$(cksum < "$gh/auth.json" 2>/dev/null)"; }
  # HOME="$gh" (synthetic, only for grok) so grok cannot scan the real ~/.claude for CLAUDE.md /
  # settings.json hooks / skills / plugins / ~/.claude.json MCP. The helper's own $HOME (auth
  # copy + token sync-back below) stays REAL — HOME is overridden only on this grok line.
  ( cd "$iso" && HOME="$gh" GROK_HOME="$gh" grok -p "$1" -m grok-4.5 --disable-web-search --sandbox strict --deny '*' 2>/dev/null ); rc=$?
  # Sync grok's refreshed token back IF it CHANGED (a refresh can succeed even if the turn later
  # errors) — else a discarded temp home rotates your subscription login OUT. Atomic; changed-only.
  [ -z "$XAI_API_KEY" ] && [ -s "$gh/auth.json" ] && [ "$(cksum < "$gh/auth.json" 2>/dev/null)" != "$seed" ] && \
    { stg="$(mktemp "$HOME/.grok/.auth.relay.XXXXXX" 2>/dev/null)" && cp "$gh/auth.json" "$stg" && mv -f "$stg" "$HOME/.grok/auth.json"; }
  exit "$rc"
)
```

And the media helper — same isolation + clean `GROK_HOME` + sandbox, but it **allow-lists only the
four media tools** with `--tools` (a denylist can miss a tool; `--deny '*'` would block `image_gen`):

```bash
# grok_media — image/video. Allow-lists ONLY the 4 media tools. Moves the artifact into $2
# (created if needed); returns non-zero if Grok succeeded but produced no artifact.
# Usage:  grok_media /abs/brief.md /abs/output-dir
grok_media() (
  [ -n "$2" ] || { echo "grok_media: usage: grok_media BRIEF-FILE OUTPUT-DIR" >&2; exit 2; }
  mkdir -p "$2" || { echo "grok_media: cannot create output dir $2" >&2; exit 2; }
  gh="$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX")"; iso="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
  trap 'rm -rf "$iso" "$gh" 2>/dev/null' EXIT INT TERM HUP
  if [ -z "$gh" ] || [ -z "$iso" ] || ! command -v git >/dev/null 2>&1 \
     || git -C "$iso" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "grok-relay: cannot isolate; refusing Grok" >&2; exit 1
  fi
  printf '[features]\ntelemetry = false\n[telemetry]\ntrace_upload = false\n[harness]\ndisable_codebase_upload = true\n[compat.claude]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n[compat.cursor]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n' > "$gh/config.toml"
  [ -n "$XAI_API_KEY" ] || { cp "$HOME/.grok/auth.json" "$gh/auth.json" 2>/dev/null; seed="$(cksum < "$gh/auth.json" 2>/dev/null)"; }
  # --tools keeps the 4 media tools; --disallowed-tools removes the always-on MCP meta-tools
  # (search_tool/use_tool) so media cannot reach an MCP server even if one is configured.
  # HOME="$gh" (synthetic, only for grok) — see grok_relay; keeps real ~/.claude out of the turn.
  ( cd "$iso" && HOME="$gh" GROK_HOME="$gh" grok -p "$(cat "$1")" -m grok-4.5 --disable-web-search --sandbox strict \
      --tools image_gen,image_edit,image_to_video,reference_to_video --disallowed-tools search_tool,use_tool 2>/dev/null ); rc=$?
  [ -z "$XAI_API_KEY" ] && [ -s "$gh/auth.json" ] && [ "$(cksum < "$gh/auth.json" 2>/dev/null)" != "$seed" ] && \
    { stg="$(mktemp "$HOME/.grok/.auth.relay.XXXXXX" 2>/dev/null)" && cp "$gh/auth.json" "$stg" && mv -f "$stg" "$HOME/.grok/auth.json"; }
  # image_gen writes under the temp GROK_HOME (or iso dir) — move the artifact(s) out BEFORE cleanup.
  # Count SUCCESSFUL moves (not files found): if a move fails (e.g. $2 unwritable), relocate that
  # artifact to a durable recovery dir so the EXIT trap does not delete it with the temp home.
  moved=0; failed=0; rec=""; keep=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if mv "$f" "$2"/ 2>/dev/null; then moved=$((moved + 1)); continue; fi
    failed=$((failed + 1))
    [ -n "$rec" ] || rec="$(mktemp -d "${TMPDIR:-/tmp}/grok-media-recovered.XXXXXX" 2>/dev/null)"
    # If the recovery dir couldn't be made (e.g. TMPDIR itself full/broken), leave the artifact in
    # the temp home and set keep=1 so the EXIT trap does NOT delete it — never silently drop it.
    if [ -n "$rec" ]; then mv "$f" "$rec"/ 2>/dev/null || keep=1; else keep=1; fi
  done <<REC
$(find "$gh" "$iso" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o -name '*.mp4' \))
REC
  if [ "$failed" -gt 0 ]; then
    if [ -n "$keep" ]; then
      trap - EXIT INT TERM HUP   # keep the temp so the un-recoverable artifact survives
      echo "grok_media: $failed artifact(s) could not be moved into $2 and recovery failed — left in $gh (which also holds a copied auth token; delete it after recovering)" >&2
    else
      echo "grok_media: $failed artifact(s) could not be moved into $2 — preserved in $rec" >&2
    fi
    exit 3
  fi
  if [ "$rc" = 0 ] && [ "$moved" -eq 0 ]; then
    echo "grok_media: Grok returned success but produced no media artifact" >&2; exit 3
  fi
  exit "$rc"
)
```

Why each part is load-bearing:

- **Three isolation guards** (`[ -z ]` on both temps, `! command -v git`, `git … rev-parse`): refuse
  if `mktemp` failed (an unset dir makes `cd` a no-op → Grok runs in the caller's repo), if the
  `git` binary is absent (the check can't verify → fail closed), or if the temp landed inside a git
  repo (e.g. `TMPDIR` points into one). The empty non-git CWD is the safeguard against the bundle.
- **Subshell body + `trap` (v2.0.4)**: each helper is `name() ( … )`, so its
  `trap 'rm -rf …' EXIT INT TERM HUP` fires on normal return, error, and the interactive/group
  signal path (Ctrl-C, or a `timeout` that kills grok) — cleaning the temp home that holds the
  copied token. Caveat: if only the helper's own PID is signalled while grok is mid-call, the shell
  defers the trap until grok exits, and `SIGKILL` skips it entirely — the mode-0700 temp home then
  lingers until grok ends or the OS tmp-reaper runs. The trap is scoped to the subshell, so it does
  not clobber the caller's own traps.
- **Clean `GROK_HOME` + synthetic `HOME` + minimal safe config** (v2.0.3–2.0.5): without them, Grok
  loads your global `~/.grok/AGENTS.md` **and** — because its Claude/Cursor compat scanners default
  ON — your `~/.claude/CLAUDE.md`, `~/.claude/settings.json` hooks, `~/.claude/skills`, plugins, and
  `~/.claude.json` MCP servers into the model turn, sending them to xAI (verified on grok 0.2.99 /
  0.2.101 via `grok inspect` with canary files). Two layers stop this: (1) **`GROK_HOME` → a
  throwaway temp** with a **minimal config** that turns telemetry / trace-upload / codebase-upload
  off and sets `[compat.claude]`/`[compat.cursor]` `skills`/`rules`/`agents`/`mcps`/`hooks`/`sessions
  = false`; and (2, v2.0.5) **`HOME` → that same temp for the grok process only**, so Grok has no
  real `~/.claude` / `~/.claude.json` to scan at all — the load-bearing fix, since those live under
  `$HOME`, not `GROK_HOME` (verified: with a synthetic `HOME`, `grok inspect` shows Project
  Instructions / MCP / Hooks all `0`). `HOME` is overridden only on the grok line, so the helper's
  own auth copy and token sync-back still use your real `~/.grok`.
- **Token sync-back on CHANGE (v2.0.4/2.0.5)**: the subscription path copies your OAuth token in;
  Grok refreshes it during the call. A discarded temp home would *lose* that refresh, and since xAI
  rotates refresh tokens, repeated relays would rotate your real `~/.grok` login OUT. So the helper
  copies the token back to `~/.grok/auth.json` **whenever it changed** (`cksum` differs) — not only
  when the turn exited 0, because a refresh can succeed even if the *inference* step later errors
  (v2.0.3 gated on exit 0 and could still rotate you out on that path). The staging file is
  **`mktemp`-unique** (v2.0.5), not `.auth.relay.$$` — two relays launched from the same shell share
  `$$` and would otherwise collide on the staging path. Atomic (`mktemp` → `mv -f`),
  changed-and-non-empty only. Two truly-concurrent relays still race last-writer-wins on
  `~/.grok/auth.json` (both write a valid token); for strict concurrency serialize the Grok lane or
  use `XAI_API_KEY`. **Set `XAI_API_KEY` to skip the token copy and sync-back entirely.**
- **`--deny '*'` (text)** genuinely refuses every tool — verified on 0.2.99/0.2.101 by forcing a
  tool call: the run logs `Denied by permission policy: deny rule on any tool matching "*"`. This
  closes the "second exposure" (an agentic Grok reading elsewhere via
  `run_terminal_command`/`read_file`/MCP and sending it as context). A text relay needs no tools.
- **`--tools` allowlist (media, v2.0.4)** — `--deny '*'` would block `image_gen`, and a hand-kept
  denylist can miss a tool (v2.0.3's list omitted 5). `grok_media` instead **allow-lists only the
  four media tools** (`--tools image_gen,image_edit,image_to_video,reference_to_video`). `--tools`
  keeps the always-on MCP meta-tools (`search_tool`/`use_tool`), so the helper also passes
  `--disallowed-tools search_tool,use_tool` (which wins) to strip them — with MCP servers already
  disabled in the config, media has no route to an MCP server. Verified on 0.2.101: `image_gen`
  still runs under these flags.
- **`--sandbox strict`** is a second layer only. It **fails open**: per xAI's sandbox doc, when a
  built-in profile can't be applied Grok warns and continues UNENFORCED (only an explicit *custom*
  profile refuses to start). So the tool restriction, the clean home, and the isolation are
  load-bearing; the sandbox is a bonus. `--permission-mode dontAsk` is accepted but not yet enforced
  (never rely on the mode), and macOS does not block a child process's network.

**Not "pure text-in / answer-out":** even hardened, the prompt you pass and Grok's reasoning still
go to xAI — it is a cloud model. The helpers stop the *repo bundle*, the *global-rule leak*, and
*tool-driven reads*; they do not make Grok local.

**Runtime kill-switch surface (secondary signal, never a guarantee).** As a preflight courtesy you
MAY read the user's `~/.grok/config.toml` for the kill-switches (`[telemetry] trace_upload` and
`[features] telemetry` — official settings; `[harness] disable_codebase_upload` —
community-reported) and report their state. Read only; never write the user's config, and never
treat a present flag as proof for the *bundle* channel: a 2026-07-14 check on 0.2.99 showed
config-set values flip `trace_upload_source` to `config` for the trace/telemetry channel, but the
bundle switch stays unverifiable while uploads are server-off (see SECURITY.md §7). Note the
helpers use a clean `GROK_HOME`, so the user's `config.toml` kill-switches do not apply to a relay
call — the relay relies on isolation + deny, not on those flags. Full per-user hardening is in
[SECURITY.md](SECURITY.md); all of it is defense-in-depth, never a substitute for isolation.

## Preflight: is the model available?

Before attempting a model, confirm its CLI is installed AND authenticated. Skip any model that
fails the check — never brute-force a missing binary, retry with different flags, or silently
substitute a different model to fill the gap.

| Model | Binary check | Auth / plan check |
|-------|--------------|-------------------|
| GPT (Codex) | `command -v codex` | fails fast with an auth error when logged out (`codex login`) |
| GLM via OpenCode | `command -v opencode` | `opencode auth list` shows a Z.AI credential |
| GLM via ZCode | `command -v zcode` (add a PATH wrapper if only the app is installed) | `~/.zcode/cli/config.json` exists or `ZCODE_API_KEY` is set. `zcode login` is currently broken — see [references/cli-reference.md](references/cli-reference.md) |
| Kimi K3 | `command -v kimi` | `kimi doctor` validates configuration but not OAuth. Let the requested call fail once if the session is absent, then ask the user to run `kimi login`; never inspect or copy Kimi's token files |
| Grok | `command -v grok` | **First apply the Grok isolation rule above — never run any `grok` command in the caller's repo.** Availability: run `grok models` **from an isolated non-git dir too**, with the same fail-closed guard (`GI="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"; if [ -z "$GI" ] || ! command -v git >/dev/null 2>&1 || git -C "$GI" rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "grok-relay: cannot isolate; refusing" >&2; else ( cd "$GI" && grok models ); fi; [ -n "$GI" ] && rm -rf "$GI"`), bounded — it is a catalog fetch, but isolate it the same way so the rule has no exception. Grok is available if the output lists models (`Default model:` / `Available models:`), EVEN IF a "You are not authenticated." line appears above the list — that header just mirrors an expired cached token that the same call silently refreshes before fetching the catalog. Only "not authenticated" with NO model list is a real problem: auth.json missing → logged out; auth.json present → confirm with one bounded real call (isolated — it is a real `grok -p`). Walk the availability ladder in [references/cli-reference.md](references/cli-reference.md) |
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
- **Kimi OAuth and OpenCode/Z.AI auth are separate credential stores.** `kimi login` signs the
  native Kimi CLI into a Kimi account; `opencode auth login` manages OpenCode providers for the
  GLM lane. Never copy tokens between them, and never log out of one CLI to switch the other.
- Kimi defaults to the native alias `kimi-code/k3`. Treat an explicit "K3" / "Kimi K3" request as
  that exact alias. If the user names a different native Kimi alias, pass it verbatim; with no
  model named, honor `HEADLESS_RELAY_KIMI_MODEL` when set, then fall back to `kimi-code/k3`.
  This override never changes GLM: OpenCode stays pinned to `zai-coding-plan/glm-5.2`.

## Custom targets

Users can connect additional one-shot model CLIs — local models (Ollama, LM
Studio, Apple MLX) or other providers — by declaring them in
`~/.agents/relay-targets.json`. Read
[references/custom-targets.md](references/custom-targets.md) the first time a
session needs the target list: each entry carries its own binary/auth preflight
and an invoke template, and joins every flow in this skill (offers, consensus
bursts) as a first-class lane. The preflight and compliance rules above apply to
custom targets unchanged. **If a custom target wraps Grok (or any CLI with the same
whole-repo-upload behaviour) — i.e. it runs an agent in the caller's working
directory — the Grok isolation rule applies to it too: run it from an isolated
non-git dir, fail-closed.** The registry is user-authored configuration: only read
it — never create, edit, or repair it on the user's behalf.

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
| Kimi K3 | Kimi Code explicitly supports Kimi CLI, OpenCode, OpenClaw, and other agent frameworks, but subscription use must remain personal and interactive. Conservatively limit this lane to user-triggered relays; cron jobs, batch/data-annotation pipelines, account/API resale, reverse proxies, and client-identity spoofing are not allowed. Use the metered Kimi Platform for automation. |

Two rules hold regardless of orchestrator. First, check the target provider's stance on
subscription auth from non-native harnesses: Anthropic blocks foreign CLIENTS on subscription
creds (metered API key for those) while currently tolerating occasional calls into the genuine
`claude -p` binary; OpenAI explicitly permits plan OAuth in third-party harnesses; Z.ai ties
the plan to its supported-tools list. Second, never use any model to build or train a
competing model or to reverse-engineer a harness. A Nous Research / Hermes agent working on
Hermes models is therefore barred from the Claude AND Grok branches for that work; GLM
(open-weight, and Hermes Agent is officially supported) is the most permissive target.

## Copy-paste baseline commands

For Codex, GLM, Kimi, Gemini, and Claude these are minimal forms — the model reasons over the
prompt text you give it. Codex's default sandbox is read-only with no network; GLM/Gemini/Claude
were wire-verified not to upload a whole-repo bundle. Kimi was not part of that wire-test and its
`-p` mode auto-handles regular tool permissions, so do not treat the minimal command as read-only.
For text-only relay, run it outside the repository and pass the required context in the prompt.
**Grok is the exception — it must run isolated (see the
Grok section above) or it uploads your whole repo. Never present the Grok baseline as "read-only"
or "local".**

```bash
# GPT (Codex) — default sandbox is read-only, no network
codex exec "your question here"

# GLM via OpenCode
echo "your question here" | opencode run -m "zai-coding-plan/glm-5.2" --variant max

# GLM via the ZCode app's bundled CLI (one-time setup: references/cli-reference.md)
zcode --prompt "your question here"

# Kimi K3 via the native CLI and its own OAuth. Explicit K3 always selects the exact native alias.
kimi_relay "your question here" "kimi-code/k3"

# For a generic "ask Kimi" request with no model named, use the configured override:
KIMI_MODEL="${HEADLESS_RELAY_KIMI_MODEL:-kimi-code/k3}"
kimi_relay "your question here" "$KIMI_MODEL"

# Grok — via the grok_relay helper (define it once, see the Grok section above). It is the ONLY
#        lane that uploads your whole repo unless isolated; the helper isolates + denies tools +
#        uses a clean GROK_HOME. Never present the Grok baseline as "read-only" or "local".
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
| Programmatic content blocks | JSON flag | `grok --prompt-json '…'` — must run inside the `grok_relay` shape (isolated + clean GROK_HOME + `--sandbox strict --deny '*'`); swap `-p "$1"` for `--prompt-json "$1"` in a copy of the helper. Never run it in the caller's repo |

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

# Kimi: no stdin prompt mode — pass the file bytes to the isolated helper.
kimi_relay "$(cat /tmp/handoff.md)" "$KIMI_MODEL"

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
with no network; Kimi is agentic and must not be described as read-only; for **Grok** use the
isolated form — it is never "no network" and must not run in the caller's repo.

### Scenario B — long prompt (a diff, a file, a spec)
1. Write the full context to `/tmp/handoff.md` (question at the top, then the code/diff).
2. Feed it via the per-CLI stdin form above.
3. Summarize the model's answer; quote its concrete file:line claims verbatim.

### Scenario C — parallel multi-model second opinion / consensus
Run 2+ models on the SAME prompt file at once (independent shell calls in one message so they
run concurrently), then compare where they agree and diverge.

```bash
KIMI_MODEL="${HEADLESS_RELAY_KIMI_MODEL:-kimi-code/k3}"
codex exec < /tmp/handoff.md > /tmp/ans-gpt.md 2>/dev/null &
cat /tmp/handoff.md | opencode run -m "zai-coding-plan/glm-5.2" --variant max > /tmp/ans-glm.md 2>/dev/null &
# kimi_relay is isolated and defaults to a 600s wall-clock limit; preserve diagnostics separately.
kimi_relay "$(cat /tmp/handoff.md)" "$KIMI_MODEL" > /tmp/ans-kimi.md 2>/tmp/ans-kimi.err &
# Grok lane — the grok_relay helper already isolates + denies tools + uses a clean GROK_HOME:
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

**Grok must NOT be used for repo- or diff-context work at all** — running it inside a repo
uploads the entire repo plus its git history (see the Grok section). For "read the repo /
review the diff / run git", use Codex (above), Gemini, GLM, or Claude — none of which sent a
whole-repo bundle in the wire-test. `--disable-web-search` does not change this: it only affects Grok's
web-search tool, never data egress. If you want Grok's take on a diff, paste the diff text into
an isolated text-only Grok call — do not point Grok at the repo.

**Kimi `-p` is agentic and uses its `auto` permission policy.** It cannot be combined with
`--plan`, so do not describe a native Kimi headless run as read-only. For a review, pass the diff
or relevant file text in the prompt. Give Kimi a repository working directory only when the user
explicitly wants an agentic repo task and the user's static Kimi permission rules are suitable.

### Scenario E — structured JSON output for scripting

| CLI | Flag | Extract the answer |
|-----|------|--------------------|
| Codex | `--json` (JSONL events) or `-o out.txt` (last message to file) | parse JSONL, or read `out.txt` |
| OpenCode | `--format json` | `jq` over the raw event JSON |
| ZCode | `--json` | `jq -r '.response'`; session id = `.sessionId`, token usage under `.usage` |
| Kimi | helper arg `stream-json` | JSONL Assistant/Tool messages; capture and inspect the raw stream before selecting the final Assistant message |
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
`grok -c`, `zcode --resume sess_<id>` / `zcode -c`, and `agy -c` / `agy --conversation <id>`
are the equivalents. Kimi's `-c` / `-S <id>` resume flags are only for an explicitly approved
agentic session from the same stable working directory; the fresh-directory `kimi_relay` helper
is intentionally one-shot. See [references/cli-reference.md](references/cli-reference.md).
**Grok caveat:**
the `grok_relay` helper creates and destroys its temp dirs per call, so it cannot resume. Grok
resume needs the SAME working dir AND `GROK_HOME` kept alive across turns — build a persistent
pair by hand using the helper's exact shape (empty non-git CWD, clean `GROK_HOME` seeded with auth,
`--sandbox strict --deny '*'`), or just use another lane for multi-turn Grok work.

### Scenario G — built-in code review of the current repo
Use **Codex** for repo-diff review; its review affordance beats a hand-written prompt:

```bash
codex exec review --uncommitted          # reviews staged + unstaged + untracked
```

Do **not** use `grok --check` for repo review: it runs Grok inside the repo, which uploads the
whole repo + history (see the Grok section). If you want Grok's opinion on a diff, capture the
diff to a file (`git diff > /tmp/diff.txt`) and pass it to an **isolated** text-only Grok call —
never point Grok at the repo itself.

### Scenario H — image / video generation (not just text)
Media generation is model-agnostic — use whichever lane the user prefers. **Images**: Codex or
Gemini (agy) generate them with no whole-repo bundle (still cloud models that transmit what they
read); Grok can too, but only under isolation.
**Video**: only Grok has it (`image_to_video`, `reference_to_video`), so video means an isolated
Grok call. The pattern: tell the model to call its image tool IMMEDIATELY, save to the working
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

Grok media (image or video) obeys the **same mandatory isolation** via the `grok_media` helper
(define it once, see the Grok section). It isolates, uses a clean `GROK_HOME`, allow-lists only the
four media tools with `--tools` (and strips the MCP meta-tools), and moves the artifact into your
output dir:

```bash
# grok_media BRIEF-FILE OUTPUT-DIR — isolated, clean GROK_HOME, dangerous tools denied, media
# tools allowed. The brief tells Grok to call image_gen and save to the working dir; the helper
# finds the artifact (image_gen writes it under the temp GROK_HOME) and moves it to OUTPUT-DIR.
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
| Grok | YES — `image_gen` / `image_edit` / `image_to_video` / `reference_to_video`, Imagine backend; the ONLY lane with video. **Must run via `grok_media`** (isolated + clean GROK_HOME; allow-lists ONLY the 4 media tools with `--tools` — `--deny '*'` would block image_gen — verified 0.2.101). image_gen saves under the temp GROK_HOME; the helper moves it to your output dir and errors if nothing was produced |
| GLM / Kimi / Claude | No documented headless image/video generation in these CLIs (Kimi K3 can understand media, but CLI 0.27.0 exposes no headless generation tool) |

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
2. Default to the safest target-specific baseline. Codex is read-only/no-network by default;
   Kimi `-p` is agentic, so pass review context as prompt text unless repo access was explicitly
   requested. Escalate write/network capability only when genuinely needed — never silently.
3. For multi-model runs, launch all commands in one message so they run concurrently, then
   `wait`.
4. Never paste secrets into a prompt file or command. Reference config by name only.
5. Report faithfully: if a model errored or timed out, say so with its stderr — do not fabricate
   an answer.
6. Keep the Kimi subscription lane user-triggered and interactive. Do not put native OAuth-backed
   `kimi -p` calls into cron, unattended batch, data annotation, or an always-on service; use the
   metered Kimi Platform for automation.
7. **Grok is fail-closed.** Never run `grok` from the caller's repo, `$HOME`, or any dir with
   real data — it uploads the whole repo + git history to xAI (see the Grok section). Run every
   Grok call in a fresh non-git temp dir, context via prompt only; if that can't be guaranteed,
   don't run Grok — warn the user and use Codex / Gemini / GLM / Claude, which sent no whole-repo
   bundle in the wire-test.

## Reference files

| File | Contents |
|------|----------|
| [SECURITY.md](SECURITY.md) | **Grok whole-repo upload**: the threat, primary sources, xAI's response, the 2026-07-13 wire-test, and per-user hardening / migration for people who already ran Grok |
| [references/cli-reference.md](references/cli-reference.md) | Full per-CLI flag tables, Kimi OAuth/model selection, ZCode setup recipes, output-format shapes, session resume, sandbox/network detail, the Grok data-egress + isolation detail, troubleshooting |
| [references/anthropic-terms.md](references/anthropic-terms.md) | Compliance detail: Anthropic subscription-routing block, Commercial Terms D.4, Fable 5 safeguards, enforcement history, plus the OpenAI / xAI / Z.ai / Moonshot / Google provider-terms matrix, with citations |
| [references/reprompter-relay.md](references/reprompter-relay.md) | Pairing recipe: run a prompt-engineering skill (e.g. RePrompter) before relaying a nontrivial task; documents the RePrompter handoff contract |
| [references/custom-targets.md](references/custom-targets.md) | User-connected targets: `~/.agents/relay-targets.json` registry for local models (Ollama, LM Studio, MLX) and other one-shot CLIs — field contract, preflight, security rules |

## Troubleshooting (core)

| Symptom | Fix |
|---------|-----|
| Grok ran inside a real repo (no isolation) | It may have uploaded the whole repo + git history to xAI (see the Grok section + [SECURITY.md](SECURITY.md)). Stop, isolate all future Grok calls, and follow SECURITY.md to check your own logs and rotate any exposed secrets |
| "Is the Grok lane safe / read-only / local?" | No. Grok is the one lane that can upload your whole repo. It is only usable text-in/answer-out from an isolated non-git dir; never call it "read-only" or "local", and never run it in the caller's repo |
| Codex: `unexpected argument '--ask-for-approval'` | `codex exec` never prompts; drop the flag (Scenario D) |
| Codex: "network access restricted" / `gh` fails | Add `--sandbox workspace-write -c 'sandbox_workspace_write.network_access=true'` (Scenario D) |
| Codex answer seems shallow | GPT-5.6 models default to LOW reasoning effort — pass `-c model_reasoning_effort="high"`/`"ultra"` explicitly |
| Prompt with backticks / `$` mangled or runs as a command | Use the file + stdin form, not inline `"…"` |
| Grok stderr shows `AuthorizationRequired` / `Skipping MCP tool` but stdout arrives | Cosmetic startup noise — pipe `2>/dev/null` |
| `grok models` prints "You are not authenticated." — but a model list appears right below it | Cosmetic: the header mirrors the expired cached token read at process start; the same call then refreshes the token and fetches the catalog. A model list in the output means Grok is **available** — do not skip the lane. Only "not authenticated" with NO model list is real (auth.json missing → `grok login`; auth.json present → one bounded real call decides). See the Grok availability ladder in [references/cli-reference.md](references/cli-reference.md). `--yolo` / `--always-approve` are permission flags, never an auth fix |
| Grok `-p` prints nothing for 2+ minutes (stderr may show `worker quit with fatal: Transport channel closed, when Auth(AuthorizationRequired)`, or nothing at all) | The run hangs instead of exiting. Kill it; if the fatal auth line is present run `grok login` and retry once; if it hangs again the relay/service side is down — skip Grok and report it. Always wrap unattended grok calls in a timeout |
| Grok cites unrelated tweets / web pages | Missing `--disable-web-search` |
| Grok says a tool was "blocked by policy" | Expected under `grok_relay`'s `--deny '*'` — a text relay needs no tools, the text answer still arrives. For media use `grok_media` (allow-lists only the 4 media tools via `--tools`, so image_gen still runs) |
| Grok's answer references your global rules / `AGENTS.md` / a project convention you didn't send | The clean `GROK_HOME` was skipped (raw `grok` call, or `GROK_HOME` not set). Grok auto-loads `~/.grok/AGENTS.md` + rules into the model turn and sends them to xAI. Always call through `grok_relay` / `grok_media` (they set a clean temp `GROK_HOME`) |
| Grok: `Couldn't set model 'grok-build': … "unknown model id"` | `grok-build` was retired from the CLI when grok-4.5 launched (July 2026) — use `-m grok-4.5` |
| zcode: `Model config is missing. Create ~/.zcode/cli/config.json …` | One-time setup — follow the ZCode recipes in [references/cli-reference.md](references/cli-reference.md) |
| `zcode login`: `OAuth response is not valid JSON` | Known open bug — skip login entirely; use the config-file or env-var recipe instead |
| OpenCode `-f` file attach errors | Pipe via stdin instead (`cat file \| opencode run …`) |
| Kimi says no provider / not logged in | Run `kimi login` and complete the device-code flow. This is the native Kimi OAuth store; do not log out of or rewrite OpenCode/Z.AI auth |
| Kimi K3 is unavailable / returns a plan entitlement error | Keep the requested model visible and report the plan error. Let the user name another native alias such as `kimi-code/kimi-for-coding`; never silently route Kimi through GLM or OpenCode Go |
| Kimi `-p` changed files during a review | Print mode uses the `auto` permission policy and cannot combine with `--plan`. Pass the diff/file text in the prompt, or configure static Kimi deny rules before granting repo access |
| agy reads/writes files in `~/.gemini/antigravity-cli/scratch` instead of your repo | Antigravity's default working dir is its own scratch workspace — pass `--add-dir /path/to/repo` (it becomes the working directory) |
| agy: `flag needs an argument: -print` | No stdin pipe — use `agy -p "$(cat /tmp/handoff.md)"` |
| agy `-p` never returns when launched inside a parallel multi-CLI burst | Known agy 1.1.0 timing bug (solo/pairwise runs are reliable) — run the Gemini lane sequentially around the burst, and always cap it with a timeout |
| GLM cites a CI/workflow/env change not in the diff | Known GLM infra-hallucination — verify against the actual file before acting |
| A CLI is missing or unauthenticated | Report it and skip that model; do not substitute another silently |
| A non-Anthropic harness (OpenClaw / Hermes) triggered this skill | Apply the graded Claude gate: never reuse subscription auth in a foreign client, never do competing-model work; occasional handoffs into the genuine `claude -p` are tolerated today (keep volume low). When in doubt, use Codex / GLM / Grok / Gemini. See [references/anthropic-terms.md](references/anthropic-terms.md) |

See [references/cli-reference.md](references/cli-reference.md) for the full table.
