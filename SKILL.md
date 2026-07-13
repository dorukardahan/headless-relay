---
name: headless-relay
description: Headless handoff guide for running other AI models from inside an agent session (any Agent Skills runtime - Claude Code, Codex, Grok Build, Cursor, OpenClaw, Hermes). Covers GPT (codex exec), GLM (opencode run or zcode --prompt), Grok (grok -p), Gemini (Antigravity agy -p), and Claude (claude -p or a subagent) - inline vs file prompts, parallel multi-model consensus, JSON output, session resume, image/video generation, provider-terms compliance. Use for "ask codex", "ask GLM", "ask grok", "ask gemini", "second opinion", "cross-model review", "generate an image", "run headless", "ask another model".
license: MIT. Complete terms in LICENSE.txt
metadata: {"version": "2.0.1"}
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
| Grok | `grok` (xAI Grok Build) | `grok -p` / `--single` — **⚠️ must run isolated, see the next section** | SuperGrok (`grok login`) |
| Gemini | `agy` (Google Antigravity CLI — replaced the retired Gemini CLI) | `agy -p` / `--print` | Google account via the Antigravity app/CLI |
| Claude | `claude` (Claude Code) | `claude -p`, or the harness's native subagent | Anthropic auth of the current session |

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
3. **If isolation cannot be guaranteed, do not run Grok.** Warn the user (link this section) and
   use another lane.
4. **A task that genuinely needs repo or diff context must NOT go to Grok.** Route it to Codex,
   Gemini, GLM, or Claude — all wire-verified to keep the repo local. Grok is text-in /
   answer-out only.

**Canonical isolated Grok call** — every Grok example below uses this shape:

```bash
# Run Grok with NO repo in its working directory. Fail-closed: refuse if isolation can't hold.
# This exact block is the shape every Grok call below reuses (swap the grok line).
GROK_ISO="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
if [ -z "$GROK_ISO" ] || ! command -v git >/dev/null 2>&1 || git -C "$GROK_ISO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "grok-relay: cannot isolate (mktemp failed, or temp dir is inside a git repo); refusing Grok" >&2
else
  ( cd "$GROK_ISO" && grok -p "your question here" -m grok-4.5 --disable-web-search 2>/dev/null )
fi
[ -n "$GROK_ISO" ] && rm -rf "$GROK_ISO"
```

The three guards matter: `[ -z "$GROK_ISO" ]` refuses if `mktemp` failed (an unset dir makes `cd`
a no-op and leaves Grok in the caller's repo); `! command -v git` refuses if the `git` binary is
absent (the check cannot verify, so fail closed); and `git … rev-parse` refuses if the temp dir
landed inside a git repo (e.g. a `TMPDIR` pointing into one). `--disable-web-search` is only for
output determinism; it does **nothing** for data egress. The isolation (empty non-git working
directory) is the safeguard against the whole-repo bundle.

**Second exposure — Grok's own tools.** Isolation stops the repo *bundle*, but an agentic Grok run
can still read elsewhere on the machine through its `Read` / `Bash` / MCP tools or absolute paths
and send what it reads to xAI as ordinary model context. For a pure text relay, harden the call:
add `--sandbox strict` (macOS Seatbelt limits filesystem reads to the CWD + system paths — so pass
the prompt inline with `-p`, or copy the prompt file INTO the isolated CWD, since a file outside
CWD is then unreadable) and deny the tools you do not need (`--deny 'Read' --deny 'Bash'`, or a
PreToolUse allow-list). Caveats, from xAI's own docs: `--permission-mode dontAsk` is accepted but
**not yet enforced** (rely on `--sandbox` + `--deny`, not the mode), and macOS does not block a
child process's network.

**Runtime kill-switch surface (secondary signal, never a guarantee).** As a preflight courtesy you
MAY read the user's `~/.grok/config.toml` for the community kill-switches
(`[harness] disable_codebase_upload`, `[telemetry] trace_upload`, `[features] telemetry`) and report
their state — e.g. "your config does not disable the codebase upload; relying on isolation." Read
only; never write the user's config, and never treat a present flag as proof (xAI controls whether
the binary honours it — see the `trace_upload_source` note in the availability ladder). Full
per-user hardening (those flags, the in-CLI `/privacy` retention command) is in
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
agentic but were wire-verified not to upload your repo. **Grok is the exception — it must run
isolated (see the Grok section above) or it uploads your whole repo. Never present the Grok
baseline as "read-only" or "local".**

```bash
# GPT (Codex) — default sandbox is read-only, no network
codex exec "your question here"

# GLM via OpenCode
echo "your question here" | opencode run -m "zai-coding-plan/glm-5.2" --variant max

# GLM via the ZCode app's bundled CLI (one-time setup: references/cli-reference.md)
zcode --prompt "your question here"

# Grok — MUST run isolated (uploads your whole repo otherwise; see the Grok section above).
#        --disable-web-search is output-determinism only, NOT a privacy control.
GROK_ISO="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
if [ -z "$GROK_ISO" ] || ! command -v git >/dev/null 2>&1 || git -C "$GROK_ISO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "grok-relay: cannot isolate; refusing Grok" >&2
else
  ( cd "$GROK_ISO" && grok -p "your question here" -m grok-4.5 --disable-web-search 2>/dev/null )
fi
[ -n "$GROK_ISO" ] && rm -rf "$GROK_ISO"

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
| Programmatic content blocks | JSON flag | `grok --prompt-json '…'` (Grok, like any Grok call, must run isolated — see the Grok section; never run it in the caller's repo) |

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

# Grok: takes a file flag directly (not stdin) — but MUST run isolated (see the Grok section).
# The prompt file is an absolute path, so it is still readable from the isolated working dir.
GROK_ISO="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
if [ -z "$GROK_ISO" ] || ! command -v git >/dev/null 2>&1 || git -C "$GROK_ISO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "grok-relay: cannot isolate; refusing Grok" >&2
else
  ( cd "$GROK_ISO" && grok --prompt-file /tmp/handoff.md -m grok-4.5 --disable-web-search 2>/dev/null )
fi
[ -n "$GROK_ISO" ] && rm -rf "$GROK_ISO"

# Antigravity: no stdin mode — substitute the file into the arg
agy -p "$(cat /tmp/handoff.md)"

# Claude: command-substitute the file into the prompt arg
claude -p "$(cat /tmp/handoff.md)" --model fable
```

## Scenarios

### Scenario A — quick one-off question to one model
Use the inline baseline command above. Read the stdout, summarize. For Codex this is read-only
with no network; for **Grok** use the isolated form — it is never "no network" and must not run
in the caller's repo.

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
# Grok lane runs ISOLATED + fail-closed in its own throwaway dir — never the repo cwd:
(
  GI="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
  if [ -z "$GI" ] || ! command -v git >/dev/null 2>&1 || git -C "$GI" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "grok-relay: cannot isolate; refusing Grok" >&2
  else
    ( cd "$GI" && grok --prompt-file /tmp/handoff.md -m grok-4.5 --disable-web-search )
  fi
  [ -n "$GI" ] && rm -rf "$GI"
) > /tmp/ans-grok.md 2>/dev/null &
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
review the diff / run git", use Codex (above), Gemini, GLM, or Claude — all wire-verified to
keep the repo local. `--disable-web-search` does not change this: it only affects Grok's
web-search tool, never data egress. If you want Grok's take on a diff, paste the diff text into
an isolated text-only Grok call — do not point Grok at the repo.

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
resume runs from the working directory, which under the mandatory isolation is a throwaway temp
dir — keep that dir alive for the whole session, or use another lane for multi-turn Grok work.

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
Gemini (agy) generate them and keep everything local; Grok can too, but only under isolation.
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

Grok media (image or video) obeys the **same mandatory isolation** — generate in an empty
non-git temp dir (NOT the output dir if that dir is inside a repo), then move the artifact out:

```bash
# Grok media — ISOLATED + fail-closed. Grok in a repo uploads the whole repo (see the Grok section).
# --disable-web-search does NOT disable the media tools and does NOT stop egress; isolation does.
GROK_ISO="$(mktemp -d "${TMPDIR:-/tmp}/grok-iso.XXXXXX")"
if [ -z "$GROK_ISO" ] || ! command -v git >/dev/null 2>&1 || git -C "$GROK_ISO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "grok-relay: cannot isolate; refusing Grok" >&2
else
  ( cd "$GROK_ISO" && grok --prompt-file /tmp/img-brief.md -m grok-4.5 --disable-web-search )
  # Move artifacts out with find (brace globs are not POSIX and would silently drop files under
  # dash, which the following rm -rf would then delete):
  find "$GROK_ISO" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o -name '*.mp4' \) -exec mv {} /path/to/output-dir/ \;
fi
[ -n "$GROK_ISO" ] && rm -rf "$GROK_ISO"
```

Briefs must say: "call your image tool immediately — do NOT research docs, spawn subagents, or
use any skill — generate <description>, save to the current directory, print `SAVED: <path>`."
Tool names differ: Grok/Codex = `image_gen`, agy = `generate_image`. Codex also mirrors outputs
to `~/.codex/generated_images/<session>/`.

Per-target support (detail in [references/cli-reference.md](references/cli-reference.md)):

| Target | Headless media generation |
|--------|---------------------------|
| GPT (Codex) | YES — built-in `image_gen` via `codex exec`; avoid `ultra` (auto-delegation spiral, `max` works in ~55s), close stdin (`</dev/null`), direct "call the tool now" prompt (verified: blue-circle + green-square PNGs). Local — no repo bundle |
| Gemini (agy) | YES (image only) — native `generate_image`, no API key / no OpenRouter (Google login covers it), ~34s, writes to cwd (verified: orange-triangle JPG). Run SOLO — the agy parallel-burst hang applies. No native video tool. Local — no repo bundle |
| Grok | YES — `image_gen` / `image_edit` / `image_to_video` / `reference_to_video`, Imagine backend; the ONLY lane with video. **Must run isolated** (uploads the whole repo otherwise — see the Grok section) |
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
6. **Grok is fail-closed.** Never run `grok` from the caller's repo, `$HOME`, or any dir with
   real data — it uploads the whole repo + git history to xAI (see the Grok section). Run every
   Grok call in a fresh non-git temp dir, context via prompt only; if that can't be guaranteed,
   don't run Grok — warn the user and use Codex / Gemini / GLM / Claude, which keep the repo local.

## Reference files

| File | Contents |
|------|----------|
| [SECURITY.md](SECURITY.md) | **Grok whole-repo upload**: the threat, primary sources, xAI's response, the 2026-07-13 wire-test, and per-user hardening / migration for people who already ran Grok |
| [references/cli-reference.md](references/cli-reference.md) | Full per-CLI flag tables, model ids, ZCode setup recipes, output-format shapes, session resume, sandbox/network detail, the Grok data-egress + isolation detail, troubleshooting |
| [references/anthropic-terms.md](references/anthropic-terms.md) | Compliance detail: Anthropic subscription-routing block, Commercial Terms D.4, Fable 5 safeguards, enforcement history, plus the OpenAI / xAI / Z.ai / Google provider-terms matrix, with citations |
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
