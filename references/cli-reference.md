# CLI reference — headless flags per model

Full per-CLI detail for `headless-relay`. Flags verified 2026-07-02 against installed
binaries: codex-cli 0.142.5, opencode 1.14.31, grok 0.2.22, claude (Claude Code) 2.1.198,
zcode CLI 0.15.0 (ZCode desktop app 3.2.2). Flags drift — re-check `--help` when a command
errors with `unexpected argument`.

## Contents
- [GPT — codex exec](#gpt--codex-exec)
- [GLM via OpenCode — opencode run](#glm-via-opencode--opencode-run)
- [GLM via ZCode — zcode --prompt](#glm-via-zcode--zcode---prompt)
- [Grok — grok headless](#grok--grok-headless)
- [Claude — claude print mode](#claude--claude-print-mode)
- [Output-format shapes and jq parsing](#output-format-shapes-and-jq-parsing)
- [Full troubleshooting](#full-troubleshooting)

## GPT — codex exec

`codex exec` runs Codex non-interactively. Prompt comes from the argument, or from stdin when
no argument is given (or the argument is `-`). If both are supplied, stdin is appended as a
`<stdin>` block.

| Flag | Meaning |
|------|---------|
| `-m, --model <MODEL>` | Model id, e.g. `gpt-5.5`. Omit to use the `~/.codex/config.toml` default. |
| `-c, --config <key=value>` | Override a config value (TOML). E.g. `-c model_reasoning_effort="xhigh"`. |
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
belongs to interactive `codex`). `--full-auto` still parses as a hidden deprecated alias but
grants nothing extra and still blocks the network.

**Sandbox and network are independent axes.** `workspace-write` does NOT allow the network by
default, so `gh` / `git fetch` / `curl` fail unless you add the config override:

```bash
codex exec --sandbox workspace-write \
  -c 'sandbox_workspace_write.network_access=true' "<task>"
```

Reasoning effort: set via config, e.g. `-c model="gpt-5.5" -c model_reasoning_effort="xhigh"`.
Check `~/.codex/config.toml` for the machine's defaults; pass explicit `-c` overrides when
reproducibility matters.

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

Headless via `-p`. Always pass `-m grok-build` explicitly (the 512K-context, 16-agent Heavy
model): the CLI's default model may be a lighter one (`grok models` showed
`grok-composer-2.5-fast` as default on 0.2.22).

| Flag | Meaning |
|------|---------|
| `-p, --single <PROMPT>` | Single-turn prompt to stdout, then exit. |
| `--prompt-file <PATH>` | Single-turn prompt from a file. |
| `--prompt-json <JSON>` | Prompt as JSON content blocks. |
| `-m, --model <MODEL>` | Model id, e.g. `grok-build`. |
| `--output-format <FMT>` | `plain` (default), `json`, `streaming-json`. |
| `--disable-web-search` | Disable web search + fetch. Mandatory for diff-deterministic review. |
| `--effort <LEVEL>` | `low\|medium\|high\|xhigh\|max`. `--reasoning-effort` also exists. `grok-build` bakes reasoning into Heavy mode and may ignore it; harmless to omit. |
| `--best-of-n <N>` | Run the task N ways in parallel, pick the best (headless only). |
| `--check` | Append a self-verification loop to the prompt (headless only). |
| `-r, --resume [id]` / `-c, --continue` | Resume by id / most recent. |
| `--verbatim` | Send the prompt exactly as given. |
| `--cwd <dir>` | Working directory. |
| `--always-approve` | Auto-approve tool executions (write mode). Omit for read-only audits. |

`grok agent` runs Grok without the interactive UI; subcommands `stdio` (ACP), `headless`
(WebSocket relay), `serve` (WebSocket server).

Startup stderr noise: `AuthorizationRequired` and `Skipping MCP tool with invalid name` lines
are usually cosmetic — pipe `2>/dev/null`; stdout stays clean. BUT `grok -p` can also hang
forever instead of exiting (observed live, in two flavors: stderr showing `worker quit with
fatal: Transport channel closed, when Auth(AuthorizationRequired)`, and a silent stall with no
stderr error at all even after a fresh login). Diagnose definitively before blaming auth:

```bash
RUST_LOG=debug grok -p "test" -m grok-build --disable-web-search 2>/tmp/grok-debug.log &
sleep 75; grep -c errorcode_502 /tmp/grok-debug.log
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

Grok `--output-format json`: extract with `jq -r '.text // .result'` (field name varies by
version — inspect once if empty). `streaming-json` emits incremental events (files modified,
commands run) for CI integration.

Codex `--json`: JSONL event stream on stdout. Simpler for a single final answer: use
`-o /tmp/last.txt` to write only the last message, then read the file.

Do not hardcode exit-code assumptions beyond zero-vs-nonzero; branch on that and read the
structured output for the precise reason. When capturing a piped tool's exit through `tee`, use
`${PIPESTATUS[0]}` — `$?` reports `tee`'s status, not the model CLI's.

## Full troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Codex: `unexpected argument '--ask-for-approval'` (or `--full-auto` warning) | exec is non-interactive; approval flags belong to interactive `codex` | Drop the flag; use `--sandbox` + the network `-c` override only |
| Codex "network access restricted", `gh`/`curl` fail | `workspace-write` blocks network by default | Add `-c 'sandbox_workspace_write.network_access=true'` |
| Codex stops with a clarifying question instead of reviewing | Default read-only sandbox blocked a command it needed | Escalate sandbox only as far as needed; or pre-fetch data into the prompt file |
| Prompt with backticks / `$` / newlines mangled or executed | Shell interpreted the inline `"…"` | Write to a file; feed via stdin, `--prompt-file`, or a quoted `"$(cat file)"` |
| Grok stderr noise: `AuthorizationRequired`, `Skipping MCP tool` (stdout still arrives) | Cosmetic startup noise + digit-prefixed MCP tool names | Pipe `2>/dev/null` |
| Grok `-p` hangs 2+ min, no stdout (stderr may show `worker quit with fatal … Auth(AuthorizationRequired)`, or nothing) | Provider-side 502 from `cli-chat-proxy.grok.com` (CLI swallows it), or a stale cached token | Run the `RUST_LOG=debug` diagnosis in the Grok section: 502s in the log = provider outage, skip Grok and retry later; no 502s + fatal auth line = `grok login` + one retry. Wrap unattended calls in a timeout |
| Grok surfaces unrelated tweets/blogs as "evidence" | Web search left on | Add `--disable-web-search` |
| Grok answer seems shallow | Default model is not grok-build | Pass `-m grok-build` explicitly |
| `--effort` has no visible effect on grok-build | grok-build bakes reasoning into Heavy mode | Omit the flag; do not fight it |
| OpenCode `-f` file attach errors | Known `-f` issue on some versions | Pipe the prompt on stdin instead |
| zcode: `Model config is missing. Create ~/.zcode/cli/config.json …` | No CLI config and no env vars | Apply Recipe A, B, or C above |
| zcode config written but `model: Invalid input` in `~/.zcode/cli/log/` | `model.main` written as an object or bad ref | `model.main` must be a `provider/model` STRING, e.g. `"zai/glm-5.2"` |
| `zcode login`: `OAuth response is not valid JSON` | Open Z.ai bug (feedback #51, #20) | Skip login; use Recipe A/B/C |
| GLM cites a CI yml / vercel.json / env change absent from the diff | GLM tends to hallucinate infrastructure claims | Verify against the real file before acting |
| GLM confuses similar functions across files | Known limitation | Cross-check its findings against actual file paths |
| A model returns empty JSON `.text`/`.result`/`.response` | Field name differs by version | Inspect the raw JSON once; adjust the `jq` path |
| CLI missing or "not authenticated" | Not installed / logged out | Report it, skip that model; run `codex login` / `opencode auth login` / `grok login` as needed — do not substitute another model silently |
| Long run hangs the shell tool | Tool-level timeout | Set an explicit timeout, or run in background and poll |
