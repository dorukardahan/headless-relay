# headless-relay

An [Agent Skill](https://agentskills.io) that teaches a coding agent to hand a task off to a
DIFFERENT AI model headlessly, without leaving the session. The user says "ask Codex", "get
GLM's opinion", "run this by Grok" — the orchestrating agent writes the prompt, runs the
target model's CLI (`codex exec`, `opencode run`, `zcode --prompt`, `grok -p`, `agy -p`,
`claude -p`), reads stdout, and reports back. Five target lanes: GPT, GLM, Grok, Gemini
(via Google's Antigravity CLI), and Claude. Includes a preflight availability gate, a
provider-terms compliance gate for non-native harnesses, parallel multi-model consensus,
JSON output parsing, session resume, headless image/video generation (Grok's Imagine-backed
media tools), and live-verified troubleshooting — including working setup recipes for the
ZCode desktop app's bundled CLI, whose official login flow is currently broken.

## What's inside

| File | Purpose |
|------|---------|
| `SKILL.md` | Core instructions (loaded by the agent) |
| `references/cli-reference.md` | Per-CLI flag tables, ZCode setup recipes, output shapes, troubleshooting |
| `references/anthropic-terms.md` | Provider-terms compliance detail with citations |
| `LICENSE.txt` | MIT license |

## Install

Copy (or clone) the `headless-relay/` directory into your agent's skills directory:

| Platform | User-wide skills directory |
|----------|---------------------------|
| Claude Code | `~/.claude/skills/headless-relay/` (project: `.claude/skills/`) |
| OpenAI Codex CLI | `~/.agents/skills/headless-relay/` (repo: `.agents/skills/`; legacy `~/.codex/skills/` still works) |
| OpenClaw | `~/.openclaw/skills/headless-relay/` (or `<workspace>/skills/`; also scans `~/.agents/skills/`) |
| Nous Research Hermes | `~/.hermes/skills/headless-relay/` (also scans `~/.agents/skills/`) |

Example:

```bash
git clone https://github.com/dorukardahan/headless-relay.git ~/.claude/skills/headless-relay
```

## Requirements

At least one target-model CLI installed and authenticated:

- `codex` (OpenAI Codex CLI) with a ChatGPT plan or API key
- `opencode` with a Z.ai Coding Plan credential, and/or the ZCode desktop app (its bundled
  `zcode` command works headlessly after a one-time setup — see `references/cli-reference.md`)
- `grok` (xAI Grok Build) with a SuperGrok login
- `agy` (Google Antigravity CLI, the Gemini CLI's replacement) with a Google login —
  install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
- `claude` (Claude Code) — only usable as a TARGET when the orchestrator is first-party
  Claude Code; see the compliance gate in `SKILL.md`

The skill degrades gracefully: unavailable models are reported and skipped, never silently
substituted.

## Compliance note

Handing off to another provider's model is governed by that provider's terms. The skill embeds
a two-check gate (orchestrator identity, target-provider terms) and a citations file. Read
`references/anthropic-terms.md` before wiring this into a non-Anthropic harness.

## License

MIT — see `LICENSE.txt`. Command behavior was live-verified 2026-07-02 against codex-cli
0.142.5, opencode 1.14.31, claude 2.1.198, and ZCode 3.2.2 (CLI 0.15.0); the Grok lane was
re-verified 2026-07-08 on grok 0.2.91 with grok-4.5; the Gemini lane was verified 2026-07-08
on Antigravity agy 1.1.0. CLIs drift fast, so re-verify flags when something errors.
