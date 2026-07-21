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
> The xAI Grok Build CLI, run inside a git repository, uploads your **entire repo: full git
> history and all tracked files, including a tracked `.env`**, to xAI cloud storage, regardless
> of which files the model reads. This is confirmed by xAI's own Grok account on X and by independent
> wire capture, and it is **not** stopped by `--disable-web-search` or by telling the model not to
> read files. As of v2.0.0 this skill runs every Grok call **fail-closed**: isolated in an empty
> non-git directory, never in your repo, and it refuses rather than risk leaking. As of **v2.0.3**
> every Grok call goes through two helper functions that add a clean, temporary `GROK_HOME` (so
> Grok can't load your global `~/.grok/AGENTS.md` — nor (v2.0.5, via a synthetic `HOME`) your
> `~/.claude/CLAUDE.md` / hooks / skills / MCP — into the model turn (real egress paths, verified on
> grok 0.2.99/0.2.101) and deny Grok's own tools (`--deny '*'`), plus a best-effort sandbox. These
> narrow the exposure to the prompt itself — they do **not** make Grok local; it is still a cloud
> model. (The isolation stops the bundle because a git bundle can only come from a git repo; we
> could not measure that directly while xAI server-disables the feature, so SECURITY.md states it
> as a sound inference, not a lab result.) Repo-context work is routed to Codex, Gemini, GLM, or
> Claude — a wire-test showed none of them send a whole-repo bundle (they are still cloud models
> that transmit the files they actually read). If you have already used Grok Build in a real repo,
> read **[SECURITY.md](SECURITY.md)**.

## What it can do

- **Second opinions**: hand a diff, a bug, a PR review, or a design question to GPT, GLM,
  Grok, Gemini, or Claude
- **Consensus**: send the same prompt to several models in parallel and compare answers
- **Image / video generation**: headless, through Codex or Gemini (no repo bundle) or Grok (isolated);
  Grok is the only lane that also does video. The skill documents each CLI's quirks
- **Scripting**: JSON output parsing and session resume for multi-turn work
- **Safety rails**: a preflight gate (installed + logged in?), a provider-terms compliance gate
  for non-native harnesses, and a **fail-closed data-egress guard for Grok** (see the security
  note above and [SECURITY.md](SECURITY.md))
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
| `SECURITY.md` | Grok whole-repo upload: threat, primary sources, xAI's response, the wire-test, and hardening/migration for anyone who already ran Grok |
| `references/cli-reference.md` | Per-CLI flag tables, ZCode setup recipes, output shapes, troubleshooting |
| `references/anthropic-terms.md` | Provider-terms compliance detail with citations |
| `references/custom-targets.md` | Connect your own targets (local models via Ollama/LM Studio/MLX, any one-shot CLI) through `~/.agents/relay-targets.json` |
| `references/reprompter-relay.md` | Pairing recipe for [RePrompter](https://github.com/AytuncYildizli/reprompter): structure the prompt first, then relay it |
| `scripts/regression-grok-safety.sh` | Deterministic guard that fails if the Grok isolation safeguard or its security anchors regress |
| `scripts/regression-claude-target.sh` | Deterministic guard that preserves configured Claude model variants such as Fable's printable `[1m]` suffix |
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
- `grok` (xAI Grok Build) with a SuperGrok login. Note: the skill runs Grok isolated (never in
  your repo) because Grok Build uploads the whole repo to xAI. See [SECURITY.md](SECURITY.md)
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
wire-test drove the v2.0.0 Grok isolation policy, see [SECURITY.md](SECURITY.md)); the Gemini
lane was verified 2026-07-08 on Antigravity agy 1.1.0. CLIs drift fast, so re-verify flags when
something errors.
