# CLI reference — headless flags per model

Full per-CLI detail for `headless-relay`. Flags verified 2026-07-02 against installed
binaries: opencode 1.14.31, claude (Claude Code) 2.1.198, zcode CLI 0.15.0 (ZCode desktop app
3.2.2, recipes re-verified on app 3.3.3); GPT section re-verified 2026-07-10 on codex-cli
0.144.0 (GPT-5.6 launch); Grok section re-verified 2026-07-08 on grok 0.2.91 (grok-4.5 launch),
then re-assessed 2026-07-15 after xAI open-sourced Grok Build (source audit of commit
`c68e39f`) — the whole-repo bundle is gone from source; the residuals are the two-root
global-rule leak (Claude/Cursor compat from `$HOME` + grok's own `~/.grok/AGENTS.md`) and the
unverifiable shipped binary; Antigravity section verified
2026-07-08 on agy 1.1.0. Flags drift — re-check `--help` when a command errors with
`unexpected argument`.

## Contents
- [GPT — codex exec](#gpt--codex-exec)
- [GLM via OpenCode — opencode run](#glm-via-opencode--opencode-run)
- [GLM via ZCode — zcode --prompt](#glm-via-zcode--zcode---prompt)
- [Grok — grok headless](#grok--grok-headless)
- [Gemini via Antigravity — agy print mode](#gemini-via-antigravity--agy-print-mode)
- [Claude — claude print mode](#claude--claude-print-mode)
- [Output-format shapes and jq parsing](#output-format-shapes-and-jq-parsing)
- [Full troubleshooting](#full-troubleshooting)

## GPT — codex exec

`codex exec` runs Codex non-interactively. Prompt comes from the argument, or from stdin when
no argument is given (or the argument is `-`). If both are supplied, stdin is appended as a
`<stdin>` block.

| Flag | Meaning |
|------|---------|
| `-m, --model <MODEL>` | Model id, e.g. `gpt-5.6-sol`. Omit to use the `~/.codex/config.toml` default. |
| `-c, --config <key=value>` | Override a config value (TOML). E.g. `-c model_reasoning_effort="ultra"`. |
| `-s, --sandbox <MODE>` | `read-only` (default), `workspace-write`, `danger-full-access`. |
| `--dangerously-bypass-approvals-and-sandbox` | No sandbox. EXTREMELY DANGEROUS; isolated containers only. |
| `-C, --cd <DIR>` | Working root for the agent. |
| `--add-dir <DIR>` | Extra writable directories alongside the workspace. |
| `--skip-git-repo-check` | Allow running outside a git repository. |
| `--json` | Emit events to stdout as JSONL. |
| `-o, --output-last-message <FILE>` | Write the agent's final message to a file. |
| `--output-schema <FILE>` | JSON Schema for the final response shape (structured output). |
| `-i, --image <FILE>` | Attach image(s) to the prompt. |
| `--ephemeral` | Do not persist session files. |
| `--ignore-user-config` / `--ignore-rules` | Reproducible CI runs; skip user config / execpolicy rules. |

Subcommands: `codex exec resume [id | --last] [prompt]`, `codex exec review [--uncommitted |
--base <branch> | --commit <sha>]`.

**Approval flags do not exist on exec.** `codex exec` is non-interactive and never prompts, so
it accepts no approval policy: `--ask-for-approval` fails with `unexpected argument` (it
belongs to interactive `codex`). `--full-auto` still parses but is a hidden deprecated compat
alias (`removed_full_auto` in the source): it sets `sandbox_mode = "workspace-write"` and pins
`approval_policy = "never"` — it does NOT enable network. Expect it to be removed the way
`--ask-for-approval` was; use `--sandbox workspace-write` instead.

**exec loads `~/.codex/config.toml` — headless behavior is machine-dependent.** A config with
`sandbox_mode = "workspace-write"` makes even flag-less `codex exec` writable, and a config
with `approval_policy = "on-request"` plus an auto-reviewer (e.g. `approvals_reviewer =
"guardian_subagent"` with `features.guardian_approval`) can ESCALATE a failed sandboxed
command and re-run it OUTSIDE the sandbox — live-verified: a network-blocked `curl` (exit 6)
was auto-approved and re-run to a 200 with no network flag at all. This escalation is
model-discretionary (not guaranteed per run), and `--full-auto` suppresses it by pinning
approvals to `never`. For deterministic cross-machine behavior, pass explicit `--sandbox` +
`-c` flags or add `--ignore-user-config` (auth still works).

**Sandbox and network are independent axes.** `workspace-write` does NOT allow the network by
default, so `gh` / `git fetch` / `curl` fail unless you add the config override:

```bash
codex exec --sandbox workspace-write \
  -c 'sandbox_workspace_write.network_access=true' "<task>"
```

Models (GPT-5.6 launch, 2026-07-09): `gpt-5.6-sol` (frontier agentic coding), `gpt-5.6-terra`
(balanced), `gpt-5.6-luna` (fast/affordable); `gpt-5.5` and `gpt-5.4` moved to legacy.
Reasoning effort ladder is now `low | medium | high | xhigh | max | ultra` — `ultra` is
"maximum reasoning with automatic task delegation" (codex may fan out its own subagents).
Two load-bearing notes, live-verified on 0.144.0: the 5.6 models DEFAULT TO `low` effort, so
always pass `-c model="gpt-5.6-sol" -c model_reasoning_effort="ultra"` (or your chosen tier)
explicitly for review-grade output; and the 0.142.x exec flag semantics are unchanged
(`--ask-for-approval` still rejected, network still requires the `-c` override above).

Piping example (feed a `gh` log in, post the summary out):

```bash
gh run view 123456 --log | codex exec "summarize the failure in 5 bullets" | gh pr comment 789 --body-file -
```

## GLM via OpenCode — opencode run

`opencode run [message..]` sends a message without launching the TUI. Positional message args
or stdin pipe both work.

| Flag | Meaning |
|------|---------|
| `-m, --model <provider/model>` | e.g. `zai-coding-plan/glm-5.2`. |
| `--variant <name>` | Provider reasoning effort: `minimal`, `high`, `max`. Z.ai recommends `max` for coding. |
| `--format <default\|json>` | `json` emits raw JSON events. |
| `-c, --continue` | Continue the last session. |
| `-s, --session <id>` | Continue a specific session. |
| `--fork` | Fork the session before continuing (needs `-c` or `-s`). |
| `--agent <name>` | Use a named agent. |
| `--dir <path>` | Directory to run in. |
| `--thinking` | Show thinking blocks. |
| `--dangerously-skip-permissions` | Auto-approve permissions not explicitly denied. |

Model id note: in OpenCode use the bare `zai-coding-plan/glm-5.2`. The `[1m]` suffix is the
Anthropic-endpoint convention used by other tools and does not apply here; review-sized prompts
sit under the default context anyway.

Do not use `-f`/`--file` for prompt attachment in scripts — it has misbehaved on prior
versions. Pipe on stdin instead. For repeated calls, start `opencode serve` once and attach:
`opencode run --attach http://localhost:4096 "…"` avoids MCP cold-boot per call.

## GLM via ZCode — zcode --prompt

The ZCode desktop app (Z.ai's own GUI coding app) bundles a CLI. It is a first-class GLM path
for users who do not have OpenCode. Status, verified live 2026-07-02 on app 3.2.2 / CLI 0.15.0:

| Item | Status |
|------|--------|
| `zcode --prompt` headless | WORKS with a one-time manual setup (recipes below, live-verified) |
| `zcode login` (OAuth) | BROKEN — `OAuth response is not valid JSON` (open bugs zai-org/feedback #51, #20) |
| Official CLI / headless docs | None. Z.ai does not document the bundled CLI; non-interactive mode is open feature request #29. Treat this path as community-verified, may break on app updates |
| API key for the free in-app tier | Not issued — free quota is app-locked. Paid Coding Plan users create a key at z.ai ("Individual Coding Plan" then "Plan Overview"). App users on any tier can bridge the app's own credential (recipe C) |

The `zcode` command ships inside the app bundle. If it is not on PATH, add a wrapper (macOS
example):

```sh
# ~/.local/bin/zcode  (chmod +x)
#!/bin/sh
exec /Applications/ZCode.app/Contents/Resources/glm/zcode.cjs "$@"
```

Do NOT `npm install zcode` or `zcode-cli` — unrelated 0.0.1 third-party stubs (supply-chain
risk).

### Setup — pick ONE recipe

Because `zcode login` is broken, configure the CLI manually. All three recipes below were
live-verified end-to-end on CLI 0.15.0.

**Recipe A — persistent config file (recommended).** Write `~/.zcode/cli/config.json` in
exactly the shape the (broken) login flow would have written, then `chmod 600` it:

```json
{
  "model": { "main": "zai/glm-5.2", "lite": "zai/glm-4.7" },
  "provider": {
    "zai": {
      "kind": "anthropic",
      "name": "Z.AI Coding Plan",
      "options": {
        "apiKey": "YOUR_ZAI_API_KEY",
        "apiKeyRequired": true,
        "baseURL": "https://api.z.ai/api/anthropic"
      },
      "models": {
        "glm-5.2": { "name": "GLM-5.2" },
        "glm-4.7": { "name": "GLM-4.7" }
      }
    }
  }
}
```

Schema notes: `model.main` / `model.lite` are `provider/model` STRINGS (an object here fails
validation with `model: Invalid input`); the provider id is plain `zai` (the `builtin:` prefix
seen in app logs is added at runtime); `kind: "anthropic"` selects the Anthropic-compatible
wire format.

**Recipe B — env vars only (no file).** Useful for CI or one-off runs:

```bash
ZCODE_API_KEY="YOUR_ZAI_API_KEY" \
ZCODE_MODEL="zai/glm-5.2" \
ZCODE_BASE_URL="https://api.z.ai/api/anthropic" \
zcode --prompt "your question here"
```

Env-var names the CLI actually reads (from its own config loader): `ZCODE_API_KEY` (any
provider), `ANTHROPIC_API_KEY` (anthropic-kind providers), `ZAI_API_KEY` (provider `zai`).
It does NOT read `ZHIPU_API_KEY` — that name belongs to other Z.ai tooling.

**Recipe C — bridge the desktop app's own login.** The app's GUI login works even though
`zcode login` does not, and it stores a reusable credential in `~/.zcode/v2/config.json`.
Log in once in the app, then generate the CLI config from it (this one-liner never prints
the key):

```bash
jq -n --arg key "$(jq -r '.provider["builtin:zai"].options.apiKey' ~/.zcode/v2/config.json)" '{
  model: {main: "zai/glm-5.2", lite: "zai/glm-4.7"},
  provider: {zai: {kind: "anthropic", name: "Z.AI Coding Plan",
    options: {apiKey: $key, apiKeyRequired: true, baseURL: "https://api.z.ai/api/anthropic"},
    models: {"glm-5.2": {name: "GLM-5.2"}, "glm-4.7": {name: "GLM-4.7"}}}}}' \
  > ~/.zcode/cli/config.json && chmod 600 ~/.zcode/cli/config.json
```

If `builtin:zai` is missing or empty in `~/.zcode/v2/config.json`, list the active entries with
`jq -r '.provider | to_entries[] | select(.value.systemDisabledReason == null) | .key'` and use
that provider's `apiKey` + `baseURL` instead. The free-tier `builtin:zai-start-plan` entry uses
a different baseURL (`https://zcode.z.ai/api/v1/zcode-plan/anthropic`) — bridging it is
UNVERIFIED; only the paid-plan `builtin:zai` / `builtin:zai-coding-plan` bridge is tested.

### Endpoints

| Endpoint | Protocol | Used by |
|----------|----------|---------|
| `https://api.z.ai/api/anthropic` | Anthropic Messages-compatible | zcode CLI, Claude Code integration |
| `https://api.z.ai/api/coding/paas/v4` | OpenAI-compatible (Coding-Plan-only) | other coding tools |
| `https://open.bigmodel.cn/api/anthropic` | Anthropic-compatible | BigModel (mainland China) accounts |

### Headless flags

| Flag | Meaning |
|------|---------|
| `--prompt <text>` | Run a single prompt without the TUI. No stdin mode — use `--prompt "$(cat file)"` for long prompts. |
| `--attach <path>` | Attach a local file to `--prompt`; repeatable. |
| `--cwd <path>` | Working directory. |
| `--mode <mode>` | Permission mode: `build`, `edit`, `plan`, `yolo`. Default for `--prompt` is `yolo` (auto-approves) — pass `--mode plan` for advice-only runs. |
| `--json` | Machine-readable JSON result (see output shapes below). |
| `--resume <sessionId>` / `-c, --continue` | Resume a persisted session (`sess_…`) / the latest in cwd. |
| `--target <text>` | Set a session goal in headless mode. |
| `--no-color` / `--verbose` | Plain output / extra diagnostics. |

## Grok — grok headless

### Data egress: Grok's whole-repo upload was real, then fixed — two residuals remain

**Historical.** Run inside a git repository, older shipped versions of Grok Build packaged the
**entire tracked repo as a git bundle (full commit history + every tracked file, including a
tracked `.env`)** and uploaded it to xAI's Google Cloud Storage bucket `grok-code-session-traces`
(`POST /v1/storage`), separate from and independent of the files the model reads on the
model-turn channel (`/v1/responses` on `cli-chat-proxy.grok.com`). It was not stopped by
`--disable-web-search`, deny rules, a "don't read files" prompt, or the "Improve the model"
toggle. Confirmed by xAI's Grok account on X (status 2076298375150911623) and by cereblab's
mitmproxy capture (github.com/cereblab/grok-build-exfil-repro; gist
dc9a40bc26120f4540e4e09b75ffb547), which recovered a never-read canary from the uploaded bundle.
Only untracked / gitignored-and-never-committed files stayed out of the bundle; a tracked `.env`
and any file ever committed (even if later deleted) was in it. See
[../SECURITY.md](../SECURITY.md) for the full write-up.

**2026-07-15: xAI open-sourced Grok Build** (Apache-2.0, github.com/xai-org/grok-build), deleted
previously-retained coding data, and set retention off by default. A source audit of the released
code (commit `c68e39f`) found:

- The whole-repo bundle path is **gone**: no `git bundle`, `codebase_upload`, or whole-repo
  archive route exists in the source anymore.
- The remaining trace-upload pipeline serializes only the model's own turn I/O, and telemetry
  **defaults off**.
- `config_files.json` upload is **hard-disabled** in source.
- Your local `~/.grok/config.toml` **beats xAI's remote settings** (confirmed by reading the
  resolver, and by a repo test) — xAI cannot remotely re-enable an upload you've turned off
  locally.

**Wire-test, 2026-07-13, grok 0.2.99, this-machine** (predates the 2026-07-15 open-source release;
kept for history. Method: whole-machine en0 egress delta on a synthetic canary repo carrying a
19 MB incompressible never-read blob; grok cross-checked via its own `trace.upload.decision` log;
positive control: a 10 MB POST measured 11.5 MB, so the method catches multi-MB uploads; baseline
noise ~0.25 MB):

| Lane | cwd | egress | whole-repo bundle? |
|------|-----|-------:|--------------------|
| grok 0.2.99 (control) | inside canary repo | 0.25 MB | NO |
| grok 0.2.99 | isolated non-git dir | 0.27 MB | NO |
| codex 0.144.1 | inside canary repo | 0.51 MB | NO |
| GLM / opencode | inside canary repo | 0.17 MB | NO |
| Gemini / agy | inside canary repo | 0.31 MB | NO |

At the time, both grok runs logged `trace.upload.decision`: `uploads_enabled=False`,
`upload_reason=feature_off`, `trace_upload_source=remote`, `has_remote_settings=True`,
`data_collection_disabled=False` — off via a revocable server-side flag, with the capability
still present in the 0.2.99 client and no local setting responsible. The xAI CLI changelog
(0.2.94→0.2.99) said nothing about upload/telemetry/privacy: there was no documented client fix
at the time. **The 2026-07-15 source audit above supersedes this finding**: the capability is
gone from source, not merely server-suppressed. Codex, GLM (opencode), and Gemini (agy) sent no
whole-repo bundle in the same test.

**Two residuals remain**, and the `grok_relay` / `grok_media` helpers in `SKILL.md` still guard
both:

1. **Global-rule leak (two roots).** Grok auto-loads global rules into every turn. (a) A
   Claude-Code/Cursor compatibility scan — every `[compat.*]` cell defaults `true` in source — reads
   `~/.claude/CLAUDE.md`, `~/.cursor`, `~/.claude.json` MCP config, skills, and hooks, all rooted at
   `$HOME`. (b) grok's OWN `~/.grok/AGENTS.md` / skills / hooks / MCP, rooted at `$GROK_HOME`
   (`agents_md.rs` always scans `grok_home()`). Either way the text is injected into the model turn,
   which then goes to xAI (observed with canary files on 0.2.99/0.2.101; §4 of [../SECURITY.md](../SECURITY.md)).
2. **Unverifiable binary.** The shipped binary can't be verified against the audited source: no
   GitHub releases or signatures, no reproducible build, the installer pulls from a different
   private repo, auto-update `exec()`s unsigned bytes, and a local `cargo build` reports a
   version matching no release. This is a general caveat for **any** closed-binary relay target
   (Codex, agy included), not unique to Grok.

Grok remains a **cloud model** either way — the prompt and Grok's reasoning go to xAI, open-source
client or not.

**Helpers (v3.0.0):** `grok_relay` (text) and `grok_media` (image/video) run every Grok call under a
**hermetic child environment** — `env -i` with an allowlist, so only `PATH`, `HOME`, `GROK_HOME`,
`TMPDIR`, `TERM`, the telemetry-off master switches, and ONE auth var reach grok; everything else
(your other secrets AND grok's own endpoint / proxy / auth-provider-command / log / managed-config /
compat overrides) is dropped. Three separate clean temp dirs back it: an empty synthetic `HOME`
(compat scanners find nothing), a clean temporary `GROK_HOME` (grok's own `~/.grok/AGENTS.md` / skills
/ hooks / MCP find nothing) — NOT your real `~/.grok` — and an empty non-git working dir the helper
verifies is OUTSIDE any git worktree (it does not trust `TMPDIR`). Auth is supplied out-of-band:
subscription login via `GROK_AUTH_PATH` → your real `auth.json` (grok precedence
`${GROK_HOME:-$HOME/.grok}/auth.json`; grok refreshes it in place; the wrapper never reads, copies, or
syncs it), or `XAI_API_KEY` (no auth file touched); the branches are mutually clean by construction
(under `env -i`, only the chosen branch's auth var is present). grok runs with `--deny '*'` (text) or a
media-only `--tools` allow-list (`grok_media`) as belt-and-suspenders against the unverifiable binary,
under a real watchdog timeout that reaps grok's process tree on timeout/INT/TERM/HUP. Each helper
is a subshell (`name() ( … )`) with `set +eux` (xtrace off, so a key can't be traced onto stderr) and
cleanup `trap`s on EXIT/INT/TERM/HUP. Scope is personal/consumer auth (subscription OAuth or
`XAI_API_KEY`); team/enterprise managed-policy parity is unverified — managed-policy readers read
`auth.json` directly from `GROK_HOME`, bypassing `GROK_AUTH_PATH`, so under the temp `GROK_HOME` it is
not carried. The shape, for reference (use the real helpers in `SKILL.md`, don't hand-roll):

```bash
gh=$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX")    # empty synthetic HOME + clean temp GROK_HOME (no external-config scan)
iso=$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")     # empty non-git CWD (verify it is OUTSIDE any git worktree before use)
ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"   # real auth path (grok precedence), absolutised BEFORE the cd
grokbin=$(command -v grok)                             # env -i uses a minimal PATH, so pass grok's absolute path
printf '[features]\ntelemetry = false\n[telemetry]\ntrace_upload = false\n[folder_trust]\nenabled = false\n[harness]\ndisable_codebase_upload = true\n[compat.claude]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n[compat.cursor]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n[compat.codex]\nskills = false\nrules = false\nagents = false\nmcps = false\nhooks = false\nsessions = false\n' > "$gh/config.toml"
# HERMETIC: env -i is an ALLOWLIST — only these vars reach grok; EVERYTHING else (your other secrets
# AND grok's endpoint/proxy/auth-provider-command/log/managed-config/compat overrides) is dropped.
( cd "$iso" && env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$gh" GROK_HOME="$gh" TMPDIR="$gh" TERM=dumb \
    GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_AUTH_PATH="$ap" \
    "$grokbin" -p "…" -m grok-4.5 --disable-web-search --sandbox strict --deny '*' )
rm -rf "$gh" "$iso"
```

`--deny '*'` is the load-bearing tool block — binary-observed on 0.2.99 to actually refuse tool calls
(forcing one produced `Denied by permission policy`) and it already covers `web_search`. `grok_relay`
additionally keeps `--disable-web-search` and a best-effort `--sandbox strict` as cheap extra layers
(the sandbox fails open for built-in profiles — an inapplicable profile warns and continues
unenforced rather than refusing to start — so it is not relied on). `--deny '*'` also blocks
`image_gen`/`image_edit`, which is why `grok_media` swaps it for a `--tools` allow-list of just the
four media tools (plus `--disallowed-tools search_tool,use_tool`). For the API-key branch, pass
`XAI_API_KEY` in place of `GROK_AUTH_PATH` — under `env -i` the other branch's vars are simply absent
(no scrubbing needed) — which skips subscription login entirely and reads no auth file.

**Per-user hardening (optional, defense-in-depth).** These are retention/telemetry controls, not a
promise the data never transmits — worth setting regardless, now that the bundle path is gone
from source. Provenance is mixed — labels below; verify per version:
- In-CLI **`/privacy`** (official) toggles data retention and, per xAI, deletes previously synced
  data. Retention, not transmission. Consumer opt-out is **not** ZDR — official ZDR is Team/
  Enterprise-only (docs.x.ai/build/enterprise).
- `~/.grok/config.toml`: `[telemetry] trace_upload = false` and `[features] telemetry = false` are
  **official settings** (xAI configuration reference) and were **verified honored on 0.2.99**
  (2026-07-14, one setup: setting them flipped `trace_upload_source` from `remote` to `config`).
  `[harness] disable_codebase_upload = true` is **community-reported**: it is NOT in the 2026-07-15
  source snapshot, but it IS present in the installed binary's static strings, so the helpers set it
  in their minimal temp config as binary-observed defense-in-depth (effect not independently proven).
  Note the v3.0.0 relay runs under a clean temp `GROK_HOME`, so your `~/.grok/config.toml` does not
  apply to relay calls — the helper's own minimal config (which pins all three of these plus the
  compat cells off) does; setting them in `~/.grok/config.toml` hardens grok when YOU run it directly.
  To confirm a control is LOCAL on your own runs, check the `trace.upload.decision` log shows
  `trace_upload_source=config` or `env` — `source=remote` is not local protection. The skill only
  READS your `~/.grok/config.toml`; it never writes it (its minimal config lives in the throwaway
  temp `GROK_HOME`).
- The official `[tools] respect_gitignore=true` limits search/read tools only.

See the helper definitions and kill-switch notes in `SKILL.md`.

Headless via `-p`. Use `-m grok-4.5` — xAI's coding/agents frontier model (launched
2026-07-08, trained with Cursor; 500K context; reasoning-effort supported, default `high`).
It is the CLI default on 0.2.91, but pass `-m` explicitly anyway: defaults drift, and the
alternative `grok-composer-2.5-fast` (Cursor's fast coding model) is a lighter tier. The
former `grok-build` model id was RETIRED from the CLI at the 4.5 launch and now fails with
`unknown model id`; the separate `grok-build-0.1` survives only on the metered Code API, not
as a CLI model.

| Flag | Meaning |
|------|---------|
| `-p, --single <PROMPT>` | Single-turn prompt to stdout, then exit. |
| `--prompt-file <PATH>` | Single-turn prompt from a file. |
| `--prompt-json <JSON>` | Prompt as JSON content blocks. |
| `-m, --model <MODEL>` | Model id, e.g. `grok-4.5`. |
| `--output-format <FMT>` | `plain` (default), `json`, `streaming-json`. |
| `--disable-web-search` | Disable web search + fetch. Mandatory for diff-deterministic review. |
| `--effort <LEVEL>` | `low\|medium\|high\|xhigh\|max`. `--reasoning-effort` also exists. grok-4.5 supports reasoning effort (model default `high`; `--effort high` live-verified). |
| `--best-of-n <N>` | Run the task N ways in parallel, pick the best (headless only). |
| `--check` | Append a self-verification loop to the prompt (headless only). |
| `-r, --resume [id]` / `-c, --continue` | Resume by id / most recent. |
| `--verbatim` | Send the prompt exactly as given. |
| `--cwd <dir>` | Working directory. Historically tied to the data-egress risk above (older versions bundled the repo at/above this directory) — the source audit shows that path is gone, but `grok_relay` / `grok_media` still `cd` into a fresh empty non-git temp dir as defense-in-depth against the unverifiable binary. |
| `--always-approve` | Auto-approve tool executions (write mode). Omit for read-only audits. |

`grok agent` runs Grok without the interactive UI; subcommands `stdio` (ACP), `headless`
(WebSocket relay), `serve` (WebSocket server).

Startup stderr noise: `AuthorizationRequired` and `Skipping MCP tool with invalid name` lines
are usually cosmetic — pipe `2>/dev/null`; stdout stays clean. BUT `grok -p` can also hang
forever instead of exiting (observed live, in two flavors: stderr showing `worker quit with
fatal: Transport channel closed, when Auth(AuthorizationRequired)`, and a silent stall with no
stderr error at all even after a fresh login). Diagnose definitively before blaming auth:

```bash
# Run this diagnostic with the same hermetic isolation as grok_relay (env -i allowlist + empty HOME +
# clean temp GROK_HOME + auth via GROK_AUTH_PATH; see the data-egress section above) — a real grok -p,
# timeout-wrapped. (Minimal config.toml omitted for brevity; env -i + empty HOME + GROK_HOME isolate.)
gh=$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX")
iso=$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")
ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"
grokbin=$(command -v grok)
( cd "$iso" && env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$gh" GROK_HOME="$gh" TMPDIR="$gh" TERM=dumb \
    GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_AUTH_PATH="$ap" \
    RUST_LOG=debug "$grokbin" -p "test" -m grok-4.5 --disable-web-search --sandbox strict --deny '*' 2>/tmp/grok-debug.log ) &
GROK_PID=$!; sleep 75; grep -c errorcode_502 /tmp/grok-debug.log; kill "$GROK_PID" 2>/dev/null
rm -rf "$gh" "$iso"
```

A nonzero count means xAI's inference proxy (`cli-chat-proxy.grok.com`) is returning Cloudflare
502 upstream — auth is fine (the log will show `authenticate request method=cached_token`
succeeding), the CLI just swallows the 502 and never exits. That is a provider-side outage:
skip Grok, report it, retry later. Zero 502s plus the fatal auth line means the cached token is
the problem: run `grok login` and retry once. Always wrap unattended grok calls in a timeout.

Auth methods for headless (per docs.x.ai/build/enterprise): the OAuth session token from
`grok login` (subscription-covered, refreshable), `grok login --device-auth` for SSH/containers,
or `XAI_API_KEY` env — the officially recommended path for scripts/CI (refresh-free, but routes
via `api.x.ai` and bills METERED API credits, not the SuperGrok subscription). Credential
resolution order: `model.api_key`, then `model.env_key`, then active session token, then
`XAI_API_KEY`. Note the CLI self-updates on login/startup — pin expectations to `grok --version`
output, not memory.

### Availability — read the model list, not the "not authenticated" line

`grok models` prints its auth-status line ("You are logged in with grok.com." /
"You are not authenticated.") from the token state read off disk at process START. When the
cached access token is expired, that top line says "not authenticated" — but the command then
runs the standard background OIDC refresh (using the still-valid `refresh_token`) and, on
success, fetches the model catalog from the server and prints it, all in the SAME invocation.
So an expired-but-refreshable token produces output that contains BOTH the stale
"You are not authenticated." header AND the real model list below it. The header is a cosmetic
race artifact; **the model list is the proof auth works.** Access tokens expire on an hours
scale, so the first Grok touch after an idle stretch routinely shows this.

Verbatim capture of the false negative (grok 0.2.93, 2026-07-13 07:54, expired cached token —
a Codex session ran `grok models` and misread it as logged-out):

```
You are not authenticated.

 WARN preferred model not in available models, falling back model_id=grok-build source=config
Default model: grok-4.5

Available models:
  * grok-4.5 (default)
  - grok-composer-2.5-fast
```

The matching `~/.grok/logs/unified.jsonl` trace for that same process: token loaded
`is_expired: true` → `oidc try_refresh_pure succeeded` → `auth update disk written` →
`model catalog: fetch succeeded`. The refresh and catalog fetch happened inside the one
`grok models` call; only the printed header was stale. (A live re-check on 0.2.99 with a fresh
token printed the clean "You are logged in" path — the header is correct once the on-disk
token is current, confirming it simply mirrors process-start state.)

Walk this ladder in order and stop at the first verdict:

1. `command -v grok` fails → **not installed**.
2. Run `grok models` with the same hermetic isolation shape as `grok_relay` (env -i allowlist + empty
   HOME + clean temp GROK_HOME + auth via GROK_AUTH_PATH), bounded by a timeout
   (`gh=$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX"); iso=$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX"); ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"; grokbin=$(command -v grok); ( cd "$iso" && env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$gh" GROK_HOME="$gh" TMPDIR="$gh" TERM=dumb GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_AUTH_PATH="$ap" perl -e 'alarm shift; exec @ARGV' 40 "$grokbin" models ); rm -rf "$gh" "$iso"`).
   It is only a catalog fetch. If the output lists models — a `Default model:` line or an
   `Available models:` block — Grok is **available**, whether the header says "You are logged
   in" OR "You are not authenticated". The catalog was just fetched over an authenticated
   connection; the expired token, if any, was refreshed in the same call. (Match on the
   model-list text, e.g. `grep -qE 'Available models:|Default model:'`, not on the header line.)
3. Output shows "You are not authenticated." with NO model list, and `~/.grok/auth.json` is
   missing or empty (`[ ! -s ~/.grok/auth.json ]` — test existence only, never print
   contents) → **genuinely logged out**. Tell the user to run `grok login` (interactive;
   never run it for them).
4. "You are not authenticated." with NO model list but auth.json exists → the refresh itself
   failed (dead/revoked refresh token, or a provider blip). Confirm with ONE bounded real
   call — at most one, never a retry loop:

   ```bash
   # Run the sentinel with the same hermetic isolation as grok_relay (env -i allowlist + empty HOME +
   # clean temp GROK_HOME + auth via GROK_AUTH_PATH) — a real grok -p, timeout-wrapped.
   gh=$(mktemp -d "${TMPDIR:-/tmp}/grok-home.XXXXXX")
   iso=$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")
   ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"
   grokbin=$(command -v grok)
   ( cd "$iso" && env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$gh" GROK_HOME="$gh" TMPDIR="$gh" TERM=dumb \
       GROK_TELEMETRY_ENABLED=false GROK_TELEMETRY_TRACE_UPLOAD=false GROK_EXTERNAL_OTEL=false GROK_AUTH_PATH="$ap" \
       perl -e 'alarm shift; exec @ARGV' 120 \
       "$grokbin" -p "Reply with exactly GROK_OK and nothing else." -m grok-4.5 --disable-web-search --sandbox strict --deny '*' ); rc=$?
   rm -rf "$gh" "$iso"
   ```

   If the session is about to send Grok a real prompt anyway, skip the sentinel and run that
   real call with the same timeout instead — its outcome IS the availability verdict, and a
   successful call rewrites auth.json so the rest of the session preflights clean.

Interpreting step 4:

| Outcome | Verdict |
|---------|---------|
| `GROK_OK` (or the real answer) on stdout | **Available** — token refreshed as a side effect; stderr `AuthorizationRequired` noise stays ignorable |
| Fast exit with an auth error | **Real auth problem** (refresh token dead/revoked) — user runs `grok login` |
| `Couldn't set model … "unknown model id"` | **Model id / config error**, not auth — fix the `-m` value |
| Killed by the timeout, no stdout | **Hang** — provider outage or the auth-refresh hang; run the `RUST_LOG=debug` 502 diagnosis above before blaming auth |
| DNS / connection-refused errors | **Network or provider outage**, not auth — report, retry later |

`--yolo` (absent from `--help` but documented in xAI's headless guide as "Auto-approve all
tool executions"; persisted as `[ui] yolo` in config.toml) is a permission flag with zero
auth effect. An interactive `grok --yolo` session working proves login state only as a side
observation (it forced a token refresh on startup); suggesting `--yolo` as a login fix is
always wrong.

## Gemini via Antigravity — agy print mode

Google retired the standalone Gemini CLI; its replacement is the Antigravity CLI, `agy`
(install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`; the old `gemini`
binary may linger on PATH — do not use it). Auth comes from the Antigravity app/CLI Google
login. All behavior below live-verified 2026-07-08 on agy 1.1.0.

| Flag | Meaning |
|------|---------|
| `-p, --print <PROMPT>` | Run a single prompt non-interactively, print the response, exit. `--prompt` is an alias. |
| `--print-timeout <dur>` | Print-mode wait cap, default `5m0s`. |
| `--model <name>` | Display-string model name from `agy models`, e.g. `"Gemini 3.1 Pro (High)"`. Omit to use the user's configured default. |
| `--add-dir <path>` | Add a directory to the workspace (repeatable) — it also BECOMES the working directory. Without it agy works in its own scratch dir, `~/.gemini/antigravity-cli/scratch`. |
| `--mode <mode>` | `accept-edits`, `plan`. Use `plan` for advice-only runs. |
| `--sandbox` | Enable terminal restrictions. |
| `--dangerously-skip-permissions` | Auto-approve tool permission prompts. |
| `-c, --continue` / `--conversation <id>` | Resume the most recent conversation / a specific one. |
| `-i, --prompt-interactive` | Run a prompt then stay interactive — NOT headless; avoid in scripts. |

Model menu (`agy models`, 2026-07-08): Gemini 3.5 Flash (Low/Medium/High), Gemini 3.1 Pro
(Low/High), Claude Sonnet 4.6 (Thinking), Claude Opus 4.6 (Thinking), GPT-OSS 120B (Medium) —
the non-Google models are served through Google's platform. The reasoning tier is baked into
the model name; `"Gemini 3.1 Pro (High)"` is the top Gemini tier.

Notes, all live-verified:
- **The old Gemini CLI's per-user API concurrency cap is gone**: three parallel `agy -p` runs
  completed in 8s wall clock — identical to a single run.
- **BUT do not launch agy inside a parallel burst with other model CLIs.** Bisected over 19
  live runs (2026-07-09): `agy -p` hangs indefinitely (9/9) when started alongside 3+ other
  concurrent CLIs (codex/opencode/grok) whose lanes run for more than a few seconds; solo and
  pairwise runs pass 100%, and a 5s stagger does not help. Timing/load-sensitive bug in agy
  1.1.0 — run the Gemini lane sequentially (before or after the burst), cap it with a timeout,
  and retest on future agy releases. Reported upstream with the full repro matrix:
  github.com/google-antigravity/antigravity-cli/issues/573.
- Baseline latency ~8s for a trivial prompt; agentic runs (tool calls) ~20s.
- No stdin pipe (`flag needs an argument: -print`) — pass files as `agy -p "$(cat file)"`.
- No JSON output format; stdout is plain text.
- Print mode executes shell/file/network tools WITHOUT prompting (file write, `curl` (200),
  and authenticated `gh` all ran unprompted) — treat it like a yolo mode. Constrain with
  `--mode plan` or `--sandbox` for advice-only handoffs.
- Working-directory gotcha: file operations land in the scratch workspace unless you pass
  `--add-dir /path/to/repo`; reads of absolute paths outside the workspace worked.

## Media generation (image / video)

A few targets can generate media, not just text. Only Grok does it headlessly today. All
notes live-verified 2026-07-10.

### Grok — native media tools (headless, works)

`grok -p` / `--prompt-file` in the default agentic mode exposes four Imagine-backed media
tools (confirmed by asking grok to list them, and by the CHANGELOG line "Image edits now use
the higher-quality Imagine model"):

| Tool | Purpose |
|------|---------|
| `image_gen` | text → new image |
| `image_edit` | edit / transform an existing image |
| `image_to_video` | single image → video |
| `reference_to_video` | multi-image references + prompt → video |

There is no dedicated flag — you drive the tool through the prompt. Grok is the **only** lane with
video (`image_to_video` / `reference_to_video`). The same residual concerns apply to media as to
text (the global-rule leak + the unverifiable binary — see the data-egress section above), so
media goes through the **`grok_media` helper defined in `SKILL.md`**: a hermetic `env -i` allowlist +
empty `HOME` + a clean temp `GROK_HOME` (not your real `~/.grok`; auth via `GROK_AUTH_PATH` or
`XAI_API_KEY`), an empty non-git CWD (verified outside any git tree), a real watchdog timeout, and a
`--tools` allow-list of ONLY the four media tools (`--deny '*'` would block `image_gen` too —
binary-observed on 0.2.101). `image_gen` writes under the temp `GROK_HOME` session dir; the helper then
publishes only this call's artifacts by copying each into a temp in the output dir and claiming the
final name by **hard-linking** it into place — the ONE atomic, no-clobber, no-follow publish primitive.
A no-hardlink filesystem **fails closed** (no `mv`, no reserve-then-fill — a reopen-by-path could follow
a swapped symlink). It also fails closed *before* publishing on any newline-in-name, and refuses any
file not physically inside the sandbox. Race-safe under concurrent cooperative calls. It returns
non-zero and rolls back ONLY this call's own files (verified by inode) if nothing was produced or grok
failed/timed out/was signalled; it **never removes the output dir** (a rolled-back call that created it
leaves it in place (usually empty; a rare local `.grokpub` signal-window temp may remain — see
SECURITY.md), avoiding a reverse-timing race with a concurrent call). The answer file and the media
manifest live in a separate control base grok is not handed a path to (raises the bar against a
temp-enumerating binary; not a jail — see SECURITY.md).

```bash
grok_media /tmp/img-brief.md /path/to/output-dir
```

where the brief instructs: "Use your `image_gen` tool to generate <description>. Save the file
in the current working directory. Print the saved absolute path on its own line prefixed with
`SAVED:`. If you have no image tool, print `IMAGE TOOL: NONE`." `--disable-web-search` does NOT
disable the media tools — the `--tools` allow-list is the safeguard, not that flag.
For image-only work, Codex or agy (below) need no such helper — neither has a global-rule-leak or
data-egress history, so they write straight into your output dir. Live-verified on 0.2.101:
`image_gen` runs under `grok_media`'s empty non-git CWD + clean temp `GROK_HOME` with a `--tools`
allow-list of only the four media tools (a blanket `--deny '*'` blocks `image_gen`).

### GPT (Codex) — image_gen works headless (with an effort caveat)

The Codex CLI ships a built-in `image_gen` tool (modes `generate` / `edit` / `generate-batch`;
default mode needs no `OPENAI_API_KEY`; a CLI fallback `scripts/image_gen.py` uses
`gpt-image-2`). It works headless via `codex exec` — verified 2026-07-10 on codex-cli 0.144.0,
which generated a blue-circle PNG into the target dir. Output also mirrors to
`~/.codex/generated_images/<session>/exec-<uuid>.png`.

```bash
cd /path/to/output-dir
perl -e 'alarm shift; exec @ARGV' 480 \
  codex exec --sandbox workspace-write -c model="gpt-5.6-sol" \
  -c model_reasoning_effort="max" \
  "Call your image_gen tool immediately — do not research docs, spawn subagents, or use any
   skill. Generate a <description>. Save it to the current directory as out.png. Print exactly:
   SAVED: <absolute path>." </dev/null
```

Three findings from bisecting the failure modes (codex-cli 0.144.0):
- **Reasoning effort is NOT the bottleneck.** `max` (one tier below `ultra`) generated a PNG
  in ~55s. The only bad tier is **`ultra`**, whose "automatic task delegation" makes the model
  spawn subagents and disappear into doc/skill lookups instead of calling the tool (a 43-min
  no-output hang). Use `max` or lower for image gen.
- **Close stdin.** With the prompt passed as a positional argument, `codex exec` can block on
  `Reading additional input from stdin...` and never start. Append `</dev/null` (the same run
  that hung then completed in 55s once stdin was closed).
- **Prompt must be imperative:** "call the tool now, don't research/delegate/use skills," or
  even a non-ultra run may wander into the openai-docs skill.
macOS has no `timeout`; wrap with `perl -e 'alarm shift; exec @ARGV' <secs> <cmd>` as above.

### Gemini (agy) — native generate_image, works headless (image only)

agy has a built-in `generate_image` tool. Like Grok's and Codex's media tools it is NOT a CLI
flag (so it does not show in `agy models` / `agy --help`) — you drive it through the prompt.
Verified 2026-07-10 on agy 1.1.0: a solo `agy -p` run generated an orange-triangle JPG into
the target dir in ~34s. No API key and no OpenRouter needed — the Google-account login covers
it (agy also self-reports the tool and offers a 0G Compute text-to-image route as an
alternative). No native VIDEO tool (agy self-reports video is unsupported).

```bash
cd /path/to/output-dir
agy -p "Call your generate_image tool immediately — do not research, spawn subagents, or use a
   skill. Generate a <description>. Save it to the current directory. Print exactly:
   SAVED: <absolute path>." --model "Gemini 3.1 Pro (High)" --add-dir "$PWD" </dev/null
```

Caveat: run the image lane **solo / sequentially** — the agy parallel-burst hang
(google-antigravity/antigravity-cli#573) applies to media runs too. `--add-dir "$PWD"` (or the
repo path) makes agy write to your dir instead of its scratch workspace; close stdin
(`</dev/null`) as with the text lane. An earlier "agy has no image tool" reading was wrong: it
came from checking `agy models`/`--help` (which never list runtime tools) and from a
concurrency-hung attempt in a parallel burst — solo, the native tool works. The OpenRouter
`google/gemini-3-pro-image` path remains a separate, metered, operator-gated fallback, not a
requirement.

### GLM / Claude

No image or video generation in `opencode` / `zcode` / `claude -p`. Text only.

## Claude — claude print mode

`claude -p` / `--print` runs Claude Code non-interactively: same agent loop, prints a result,
exits. Any CLI option works with `-p`.

| Flag | Meaning |
|------|---------|
| `--model <model>` | Alias (`fable`, `opus`, `sonnet`) or full name (`claude-fable-5`). |
| `--output-format <fmt>` | `text` (default), `json` (single result), `stream-json` (NDJSON). |
| `--input-format <fmt>` | `text` (default), `stream-json`. |
| `--effort <level>` | `low\|medium\|high\|xhigh\|max`. |
| `-c, --continue` | Continue the most recent conversation in the cwd. |
| `-r, --resume [id]` | Resume by session id. |
| `--fork-session` | On resume, create a new session id. |
| `--append-system-prompt <text>` | Append to the system prompt. |
| `--agents <json>` | Define custom inline agents. |
| `--allowedTools "Bash,Read,Edit"` | Pre-approve tools for unattended runs. |
| `--permission-mode <mode>` | `acceptEdits`, `auto`, `bypassPermissions`, `default`, `dontAsk`, `plan`. |
| `--max-budget-usd <N>` | Spend guardrail (print mode only). A `--max-turns` flag no longer exists on 2.1.198. |
| `--fallback-model <model>` | Auto-fallback when the default is unavailable (comma-separated list). |

`stream-json` requires `--verbose`; token-level deltas also need `--include-partial-messages`.
Session id lookup for `--resume` is scoped to the current directory and its git worktrees.

In-session alternative (usually preferred for a single same-provider opinion): the harness's
native subagent — no subprocess, result returns straight to the orchestrator.

## Output-format shapes and jq parsing

Claude `--output-format json` returns one object:

```json
{ "type": "result", "subtype": "success", "is_error": false,
  "total_cost_usd": 0.0034, "num_turns": 4,
  "result": "…answer text…", "session_id": "abc-123" }
```

```bash
result=$(claude -p "task" --model fable --output-format json)
echo "$result" | jq -r '.result'          # answer text
echo "$result" | jq -r '.session_id'       # for --resume
echo "$result" | jq -r '.total_cost_usd'   # spend
```

Claude `stream-json`: one JSON object per line. First line is a `system` event, `subtype:init`
(session id, model, tools, MCP servers). Tee the raw stream before parsing:

```bash
claude -p "refactor the config loader" --model fable \
  --output-format stream-json --verbose \
  | tee /tmp/run.jsonl \
  | jq -r 'select(.type=="result") | .result'
```

ZCode `--json` returns one object (live-captured shape, CLI 0.15.0):

```json
{ "sessionId": "sess_…", "traceId": "…", "turnId": "turn_…",
  "response": "…answer text…",
  "usage": { "inputTokens": 7913, "outputTokens": 8, "cacheReadTokens": 7552 },
  "eventCount": 16,
  "projection": { "status": "idle", "turnCount": 1, "contextWindow": 1000000 } }
```

Extract with `jq -r '.response'`; resume later with `--resume "$(… | jq -r '.sessionId')"`.

Grok `--output-format json`: one object with keys `requestId`, `sessionId`, `stopReason`,
`text`, `thought` (verified 0.2.91) — extract with `jq -r '.text'`. `streaming-json` emits
incremental events (files modified, commands run) for CI integration.

Codex `--json`: JSONL event stream on stdout. Simpler for a single final answer: use
`-o /tmp/last.txt` to write only the last message, then read the file.

Do not hardcode exit-code assumptions beyond zero-vs-nonzero; branch on that and read the
structured output for the precise reason. When capturing a piped tool's exit through `tee`, use
`${PIPESTATUS[0]}` — `$?` reports `tee`'s status, not the model CLI's.

## Full troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Codex: `unexpected argument '--ask-for-approval'` (or `--full-auto` warning) | exec is non-interactive; approval flags belong to interactive `codex` | Drop the flag; use `--sandbox` + the network `-c` override only |
| Codex behaves differently on another machine (writes/network that "shouldn't" work) | exec loads `~/.codex/config.toml`; `on-request` + auto-reviewer configs can escalate failed commands out of the sandbox | Pass explicit `--sandbox`/`-c` flags, or `--ignore-user-config` for reproducible runs |
| Codex "network access restricted", `gh`/`curl` fail | `workspace-write` blocks network by default | Add `-c 'sandbox_workspace_write.network_access=true'` |
| Codex stops with a clarifying question instead of reviewing | Default read-only sandbox blocked a command it needed | Escalate sandbox only as far as needed; or pre-fetch data into the prompt file |
| Codex answer seems shallow on a 5.6 model | GPT-5.6 models default to LOW reasoning effort | Pass `-c model_reasoning_effort="high"` / `"ultra"` explicitly (or pin it in config.toml) |
| Prompt with backticks / `$` / newlines mangled or executed | Shell interpreted the inline `"…"` | Write to a file; feed via stdin, `--prompt-file`, or a quoted `"$(cat file)"` |
| You ran an old, pre-2026-07-15 Grok Build in a real repo | Older versions bundled + uploaded the whole tracked repo + git history to xAI GCS (see the data-egress section above; the path is gone from source in the open-sourced release) | Follow [../SECURITY.md](../SECURITY.md) to check logs and rotate any exposed secrets |
| "Is Grok read-only / local / safe?" | No — it's a cloud model like the others. The whole-repo upload is gone per the 2026-07-15 source audit; the global-rule leak and the unverifiable binary remain | Never present Grok as local; run it through `grok_relay`'s hermetic env-i + empty-HOME + clean-temp-GROK_HOME shape either way |
| Grok stderr noise: `AuthorizationRequired`, `Skipping MCP tool` (stdout still arrives) | Cosmetic startup noise + digit-prefixed MCP tool names | Pipe `2>/dev/null` |
| Grok `-p` hangs 2+ min, no stdout (stderr may show `worker quit with fatal … Auth(AuthorizationRequired)`, or nothing) | Provider-side 502 from `cli-chat-proxy.grok.com` (CLI swallows it), or a stale cached token | Run the `RUST_LOG=debug` diagnosis in the Grok section: 502s in the log = provider outage, skip Grok and retry later; no 502s + fatal auth line = `grok login` + one retry. Wrap unattended calls in a timeout |
| Grok surfaces unrelated tweets/blogs as "evidence" | Web search left on | Add `--disable-web-search` |
| Grok: `Couldn't set model 'grok-build': Invalid params: "unknown model id"` | `grok-build` retired from the CLI at the grok-4.5 launch (2026-07-08) | Use `-m grok-4.5` |
| Grok: `grok models` prints "You are not authenticated." though login should be fine | Header mirrors an expired cached access token read at process start; the same call then refreshes and fetches the catalog (routine after idle) | If a model list appears below the header → **available**, use the lane. Only "not authenticated" with NO model list is real: auth.json present → one bounded real call decides; auth.json absent → `grok login`. Match on `Available models:` / `Default model:`, not the header. `--yolo` / `--always-approve` are permission flags, never the fix |
| Grok answer seems shallow | A lighter model (e.g. `grok-composer-2.5-fast`) was selected | Pass `-m grok-4.5` explicitly |
| OpenCode `-f` file attach errors | Known `-f` issue on some versions | Pipe the prompt on stdin instead |
| zcode: `Model config is missing. Create ~/.zcode/cli/config.json …` | No CLI config and no env vars | Apply Recipe A, B, or C above |
| zcode config written but `model: Invalid input` in `~/.zcode/cli/log/` | `model.main` written as an object or bad ref | `model.main` must be a `provider/model` STRING, e.g. `"zai/glm-5.2"` |
| `zcode login`: `OAuth response is not valid JSON` | Open Z.ai bug (feedback #51, #20) | Skip login; use Recipe A/B/C |
| GLM cites a CI yml / vercel.json / env change absent from the diff | GLM tends to hallucinate infrastructure claims | Verify against the real file before acting |
| GLM confuses similar functions across files | Known limitation | Cross-check its findings against actual file paths |
| A model returns empty JSON `.text`/`.result`/`.response` | Field name differs by version | Inspect the raw JSON once; adjust the `jq` path |
| agy file operations land in `~/.gemini/antigravity-cli/scratch` | Antigravity's default working dir is its own scratch workspace, not your cwd | Pass `--add-dir /path/to/repo` (it becomes the working directory); use absolute paths in prompts |
| agy: `flag needs an argument: -print` | stdin piping is not supported | Use `agy -p "$(cat file)"` — quoted command substitution passes the bytes verbatim |
| agy modifies files you only wanted reviewed | Print mode runs tools unprompted (yolo-like) | Add `--mode plan` (advice-only) or `--sandbox` |
| agy `-p` hangs forever inside a parallel multi-CLI burst | agy 1.1.0 timing/load bug when 3+ other model CLIs run concurrently (solo/pairwise reliable; stagger insufficient) | Run the Gemini lane sequentially around the burst; always cap agy with a timeout |
| CLI missing or "not authenticated" | Not installed / logged out | Report it, skip that model; run `codex login` / `opencode auth login` / `grok login` as needed — do not substitute another model silently. Exception: Grok's "not authenticated" from `grok models` is not conclusive — walk the Grok availability ladder first |
| Long run hangs the shell tool | Tool-level timeout | Set an explicit timeout, or run in background and poll |
