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

## What it can do

- **Second opinions**: hand a diff, a bug, a PR review, or a design question to GPT, GLM,
  Grok, Gemini, or Claude
- **Consensus**: send the same prompt to several models in parallel and compare answers
- **Image generation**: headless, through Grok, Codex, or Gemini; the skill documents each
  CLI's quirks (Grok also does video)
- **Scripting**: JSON output parsing and session resume for multi-turn work
- **Safety rails**: a preflight gate (is the CLI installed and logged in?) and a
  provider-terms compliance gate for non-native harnesses
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
| `references/cli-reference.md` | Per-CLI flag tables, ZCode setup recipes, output shapes, troubleshooting |
| `references/anthropic-terms.md` | Provider-terms compliance detail with citations |
| `references/custom-targets.md` | Connect your own targets (local models via Ollama/LM Studio/MLX, any one-shot CLI) through `~/.agents/relay-targets.json` |
| `references/reprompter-relay.md` | Pairing recipe for [RePrompter](https://github.com/AytuncYildizli/reprompter): structure the prompt first, then relay it |
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
- `grok` (xAI Grok Build) with a SuperGrok login
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
re-verified 2026-07-08 on grok 0.2.91 with grok-4.5, then 2026-07-13 on grok 0.2.99 (the
availability check was reworked: `grok models` can print "not authenticated" on a merely
expired cached token while still listing models in the same output, so the skill now reads the
model list rather than that header); the Gemini lane was verified 2026-07-08 on Antigravity
agy 1.1.0. CLIs drift fast, so re-verify flags when something errors.
