# headless-relay

headless-relay is an [Agent Skill](https://agentskills.io) that lets your coding agent use
the other AI models installed on your machine, without you leaving the session. You say
"ask Codex what it thinks of this function", "get a second opinion on this bug from GLM and
Grok", or "have Gemini generate an image for this post". Your agent quietly runs the right
tool in the background, reads the answer, and reports back to you. No new accounts, no API
juggling: it drives the AI tools you already have, with the logins you already use.

It works in any coding agent that reads Agent Skills and can run shell commands: Claude
Code, OpenAI Codex CLI, xAI Grok, Cursor, OpenClaw, Nous Research Hermes and friends. Five
model lanes ship ready to use (GPT, GLM, Grok, Gemini, Claude), and you can plug in your
own, including local models running through Ollama, LM Studio, or Apple MLX. Installation
is a single `git clone`; everything else on this page is detail for when you need it.

> ### ⚠️ Security: the Grok lane and your repository
>
> Earlier shipped versions of the xAI Grok Build CLI, run inside a git repository, uploaded
> your **entire repo: full git history and all tracked files, including a tracked `.env`** to
> xAI cloud storage, regardless of which files the model reads — confirmed by xAI's own Grok
> account on X and by independent wire capture. On 2026-07-15 xAI open-sourced Grok Build
> (Apache-2.0), deleted previously-retained coding data, and set retention off by default. A
> source audit of the released code (commit `c68e39f`) found the whole-repo bundle path is
> **gone** from source, the remaining trace-upload pipeline (the model's own turn I/O) defaults
> **off**, and your local `~/.grok/config.toml` beats xAI's remote settings — xAI cannot
> remotely re-enable an upload you've turned off locally. Two residuals remain, and this skill
> still guards both: Grok auto-loads global rules into every turn — your other tools' config (a
> Claude-Code/Cursor/Codex compatibility scan of `~/.claude` / `~/.cursor` / `~/.codex`, rooted at
> `$HOME`) AND grok's own `~/.grok/AGENTS.md` (rooted at `$GROK_HOME`) — and the shipped binary can't
> be verified against the source (no signed releases or reproducible build), true of any closed-binary
> relay target, not unique to Grok. So `grok_relay` / `grok_media` still run Grok under a **hermetic
> `env -i` child environment** (an allowlist — only a handful of vars reach grok, dropping your other
> secrets and grok's own endpoint / auth-provider-command / log / compat overrides) with an empty
> synthetic `HOME` AND a clean temporary `GROK_HOME` (your real login reached out-of-band via
> `GROK_AUTH_PATH`, or `XAI_API_KEY`), in an empty non-git directory (verified outside any git tree),
> with its tool use locked down and a real watchdog timeout. Scope is personal / consumer auth —
> team/enterprise managed-policy parity is unverified. None of this makes Grok local
> — it is still a cloud model; the prompt and Grok's reasoning go to xAI. For the full history, the
> audit, and what to do if you already used Grok Build in a real repo, read **[SECURITY.md](SECURITY.md)**.

## What it can do

- **Second opinions**: hand a diff, a bug, a PR review, or a design question to GPT, GLM,
  Grok, Gemini, or Claude
- **Consensus**: send the same prompt to several models in parallel and compare answers
- **Image / video generation**: headless, through Codex, Gemini, or Grok (Grok under a hermetic
  `env -i` + empty HOME + clean temp GROK_HOME, only the four media tools allowed, media published
  atomically); Grok is
  the only lane that also does video. The skill documents each CLI's quirks
- **Scripting**: JSON output parsing and session resume for multi-turn work
- **Safety rails**: a preflight gate (installed + logged in?), a provider-terms compliance gate
  for non-native harnesses, and a **hardened, tool-restricted helper for Grok (hermetic `env -i` + empty
  HOME + clean temp GROK_HOME, personal-scope auth)** (see the security note above and [SECURITY.md](SECURITY.md))
- **Custom targets**: add any one-shot CLI as a lane (local models included) via a small
  JSON registry, contributed by [@AytuncYildizli](https://github.com/AytuncYildizli)

## Pairs well with RePrompter

A lazy prompt relayed to another model is still a lazy prompt.
[RePrompter](https://github.com/AytuncYildizli/reprompter) structures your prompt first,
then hands it to headless-relay for delivery. Quality in, quality out. The pairing recipe
lives in `references/reprompter-relay.md`.

## What's inside

| File | Purpose |
|------|---------|
| `SKILL.md` | Core instructions (loaded by the agent) |
| `SECURITY.md` | Grok's historical whole-repo upload: primary sources, xAI's 2026-07-15 open-source response, the source audit, and migration notes for anyone who ran an old Grok Build version |
| `references/cli-reference.md` | Per-CLI flag tables, ZCode setup recipes, output shapes, troubleshooting |
| `references/anthropic-terms.md` | Provider-terms compliance detail with citations |
| `references/custom-targets.md` | Connect your own targets (local models via Ollama/LM Studio/MLX, any one-shot CLI) through `~/.agents/relay-targets.json` |
| `references/reprompter-relay.md` | Pairing recipe for [RePrompter](https://github.com/AytuncYildizli/reprompter): structure the prompt first, then relay it |
| `scripts/regression-grok-safety.sh` | Static text tripwire: fails if the Grok isolation safeguard or its security anchors regress |
| `scripts/test-grok-runtime.sh` | Runtime counterpart to the tripwire: extracts the shipped `grok_relay` / `grok_media` from `SKILL.md` and exercises the isolation, process-lifecycle, and fail-closed publish matrix under sh/bash/zsh against a fake `grok` (real grok / network never touched), with mutation red-green checks |
| `LICENSE.txt` | MIT license |

## Install

headless-relay is a plain [Agent Skill](https://agentskills.io): one `SKILL.md` plus
references. It runs in **any agent that reads Agent Skills and can execute shell commands**,
not just the ones named below. Copy (or clone) the `headless-relay/` directory into your
agent's skills directory:

| Platform | User-wide skills directory |
|----------|---------------------------|
| Claude Code | `~/.claude/skills/headless-relay/` (project: `.claude/skills/`) |
| OpenAI Codex CLI | `~/.agents/skills/headless-relay/` (repo: `.agents/skills/`; legacy `~/.codex/skills/` still works) |
| xAI Grok Build CLI | `~/.grok/skills/headless-relay/`. Grok also auto-loads `~/.claude/skills/` via its Claude compatibility path, so a Claude Code install covers Grok too |
| OpenClaw | `~/.openclaw/skills/headless-relay/` (or `<workspace>/skills/`; also scans `~/.agents/skills/`) |
| Nous Research Hermes | `~/.hermes/skills/headless-relay/` (also scans `~/.agents/skills/`) |
| Cursor, ZCode, and other agentskills.io-compatible runtimes | check your agent's skills directory convention; the skill has no platform-specific syntax |

Example:

```bash
git clone https://github.com/dorukardahan/headless-relay.git ~/.claude/skills/headless-relay
```

## Requirements

At least one target-model CLI installed and authenticated:

- `codex` (OpenAI Codex CLI) with a ChatGPT plan or API key
- `opencode` with a Z.ai Coding Plan credential, and/or the ZCode desktop app (its bundled
  `zcode` command works headlessly after a one-time setup, see `references/cli-reference.md`)
- `grok` (xAI Grok Build) with a SuperGrok login (or `XAI_API_KEY`). Note: the skill runs Grok
  under a hermetic `env -i` + empty `HOME` + a clean temp `GROK_HOME` with its tool use locked down — belt-and-suspenders now
  that xAI has open-sourced Grok Build and a source audit found the old whole-repo upload path gone.
  See [SECURITY.md](SECURITY.md)
- `agy` (Google Antigravity CLI, the Gemini CLI's replacement) with a Google login.
  Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
- `claude` (Claude Code), only usable as a TARGET when the orchestrator is first-party
  Claude Code; see the compliance gate in `SKILL.md`

The skill degrades gracefully: unavailable models are reported and skipped, never silently
substituted.

## Compliance note

Handing off to another provider's model is governed by that provider's terms. The skill embeds
a two-check gate (orchestrator identity, target-provider terms) and a citations file. Read
`references/anthropic-terms.md` before wiring this into a non-Anthropic harness.

## License

MIT, see `LICENSE.txt`. Command behavior was live-verified 2026-07-02 against codex-cli
0.142.5, opencode 1.14.31, claude 2.1.198, and ZCode 3.2.2 (CLI 0.15.0); the Grok lane was
re-verified 2026-07-08 on grok 0.2.91 with grok-4.5, then 2026-07-13 on grok 0.2.99 (two things
that day: the availability check was reworked because `grok models` can print "not authenticated"
on a merely-expired cached token while still listing models in the same output; and a data-egress
wire-test drove the v2.0.0 Grok isolation policy, see [SECURITY.md](SECURITY.md)), then
re-assessed again 2026-07-15 after xAI open-sourced Grok Build — a source audit of the released
code (commit `c68e39f`) found the whole-repo bundle path gone, see [SECURITY.md](SECURITY.md);
the Gemini lane was verified 2026-07-08 on Antigravity agy 1.1.0. CLIs drift fast, so re-verify
flags when something errors.
