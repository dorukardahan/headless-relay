# Provider terms — when a branch is off-limits

Rationale and citations for the compliance gate in SKILL.md. The gate matters because this
skill is cross-platform: its `SKILL.md` can be installed into an OpenClaw, Nous Research /
Hermes, Codex, or Gemini agent's skills directory. When a non-Anthropic harness triggers it,
the Claude branch (`claude -p` or a Claude subagent) must be skipped. Route to Codex, GLM, or
Grok instead. Facts below verified against primary sources on 2026-07-02.

## The rule

| Orchestrator triggering this skill | Claude branch |
|-----------------------------------|-----------------------|
| First-party Anthropic Claude Code (the interactive session or its own subagents) | Allowed — any branch |
| OpenClaw / Nous Research (Hermes) / any non-Anthropic agent harness | Forbidden — use Codex / GLM / Grok only |
| Any workflow whose purpose is to build or train a competing model | Forbidden regardless of harness |

Never reverse-engineer the Claude Code harness or its auth to tap a Pro/Max plan from another
tool. A non-first-party harness that needs Claude must use a metered Anthropic API key, not a
subscription session — and even then, not for competing-model development.

## Reason 1 — subscription auth cannot flow through third-party harnesses

Anthropic subscriptions (Pro/Max) are provisioned for first-party tooling (Claude Code), which
uses optimizations like prompt caching that third-party harnesses bypass.

- On **April 4, 2026**, Anthropic blocked Pro/Max subscribers from routing flat-rate
  subscription usage through third-party agent frameworks, starting with OpenClaw (formerly
  Clawdbot), and said the restriction would extend to **all third-party harnesses**. Such usage
  moved to metered pay-as-you-go "extra usage" billing or API keys.
- Boris Cherny (Claude Code lead) on the block: "We've been working hard to meet the increase
  in demand for Claude, and our subscriptions weren't built for the usage patterns of these
  third-party tools… Capacity is a resource we manage thoughtfully and we are prioritizing our
  customers using our products and API."
- On May 13-14, 2026, Anthropic ANNOUNCED a further split of subscription usage into separate
  pools (interactive vs programmatic: Agent SDK, `claude -p` headless, GitHub Actions, ACP
  third-party apps), effective June 15 — then **paused the change on June 15 before it took
  effect**. As of 2026-07-02 the split is NOT in force: `claude -p` still draws from normal
  subscription limits, and Anthropic says it will give advance notice before any future change.
  Watch for reinstatement.

Implication: the `claude -p` branch of this skill draws on local Claude Code auth. Firing it
from a non-Anthropic harness routes subscription capacity through a third-party tool — the
exact pattern Anthropic blocked in April 2026.

## Reason 2 — Commercial Terms D.4 (use restrictions)

Section D.4 of Anthropic's Commercial Terms of Service: "Customer may not and must not attempt
to (a) access the Services to build a competing product or service, including to train
competing AI models or resell the Services except as expressly approved by Anthropic; (b)
reverse engineer or duplicate the Services". Anthropic's help center adds: "Our Terms do not
allow the use of Outputs to train models that are competitive with Anthropic's own."

Nous Research develops competing open models (the Hermes family). A Nous Research agent using
Claude to help build, train, or accelerate those models is squarely inside the D.4(a)
prohibition. This is independent of the subscription-routing issue in Reason 1 — it applies
even with a paid API key.

Narrow nuance: you *can* use first-party Claude Code to write code, even code for a product
that competes with Claude Code. The prohibited acts are (a) using Claude to train/develop
competing *models* and (b) reverse-engineering the harness/auth. The compliance gate targets
those two, not general coding.

## Reason 3 — Fable 5 degrades on frontier-LLM-development tasks

The **Claude Fable 5 system card** (released with the model June 9, 2026) disclosed "RSI
suppression" safeguards: when Fable 5 detects use for frontier LLM development — pretraining
pipelines, distributed training infrastructure, ML accelerator design, or accelerating
competing models — it limits its own effectiveness via prompt modification, steering vectors,
or parameter-efficient fine-tuning (estimated ~0.03% of traffic). System card: "Using Claude to
develop competing models already violates our Terms of Service, but enforcing this restriction
through our safeguards avoids accelerating the actors most willing to violate these terms."

As originally shipped the safeguard was **silent** (no user notification). After public
backlash, Anthropic reversed the silent design within ~48 hours (by June 11, 2026): triggering
requests now visibly fall back to Opus 4.8, and Anthropic publicly called the silent version
"the wrong tradeoff".

Implication: even setting terms aside, routing competing-model or frontier-LLM-dev work through
Fable is unreliable — the task is handed to a different model. Use a different provider for
that class of task.

## Enforcement history (this is actively policed)

| Date | Action |
|------|--------|
| June 2025 | Windsurf's first-party Claude access cut off amid OpenAI-acquisition rumors |
| August 2025 | OpenAI's Claude API access revoked ahead of GPT-5 (benchmarking/competitive use) |
| January 2026 | xAI's access restricted under competitive-use arguments (via Cursor), citing D.4; harness-spoofing crackdown |
| April 2026 | Third-party harness subscription routing blocked, starting with OpenClaw |
| June 2026 | Fable/Mythos frontier-LLM-dev safeguards disclosed (silent version reversed within 48h); pool-split announcement paused |

There is no public evidence of a *dedicated, named* ban aimed only at Nous Research or a
specific Hermes agent — those are covered by the general third-party-harness and
competing-model policies above, not a separate rule. Treat individual account-ban anecdotes as
case-by-case TOS enforcement, not a blanket prohibition on all agent use.

## Other providers (the terms are NOT symmetric)

A non-native orchestrator must respect the TARGET provider's terms. The providers differ
sharply on subscription routing; they converge on competing-model bans.

| Provider | Subscription routing via third-party harness | Competing-model / distillation | Notes |
|----------|----------------------------------------------|--------------------------------|-------|
| Anthropic (Claude) | BLOCKED (April 2026). Metered API key required. | Prohibited (Commercial Terms D.4; help-center output-training ban). | Sharpest and most-enforced gate; see above. |
| OpenAI (Codex / GPT) | OFFICIALLY PERMITTED since May 1, 2026 — Sam Altman publicly endorsed ChatGPT-plan OAuth inside OpenClaw. Plan credentials reach OpenAI models only; an API key is the alternative for other tooling/CI, not a requirement. | ToU (effective Jan 1, 2026), "What you cannot do": "Use Output to develop models that compete with OpenAI." | Codex CLI is Apache-2.0; custom providers work via `[model_providers]` (base_url + env_key) but ONLY Responses-API-compatible endpoints — `wire_api = "chat"` was removed and now errors. Native subagents: `[agents]`, defaults `max_threads=6`, `max_depth=1`. |
| xAI (Grok) | Enterprise ToS governs the API. | AUP (effective June 26, 2026) prohibits "Using the Service or any Output to develop machine learning models or related AI services that compete with xAI" and "Scraping, harvesting or reselling any Input or Output, or distilling model data or Outputs"; Enterprise ToS (May 12, 2026) additionally bans using Output to train customer ML/AI models. | Longstanding clauses, tightened through 2026. |
| Z.ai (GLM) | Coding Plan is restricted to officially supported tools. Current official list includes Claude Code, Claude for IDE, OpenCode, Cursor, Cline, TRAE, Qoder, Droid, Kilo Code, Roo Code, Crush, Goose, Eigent, plus general-purpose agents OpenClaw, Hermes Agent, SillyTavern. | No sharp anti-competing clause surfaced; flagship GLM weights (GLM-4.7, GLM-5.2) are open under MIT, so the concern is structurally different. | Aggressive quota / fair-use enforcement: 5-hour + weekly caps, 3x peak-hour / 2x off-peak deduction for GLM-5.2 and GLM-5-Turbo, account bans after repeat violations (no-warning bans reported). |
| Google (Gemini / Antigravity) | Antigravity CLI (`agy`) auth is a Google-account login; no policy against third-party-harness use surfaced as of 2026-07-08. | Gemini API Additional Terms (updated March 23, 2026): "You may not use the Services to develop models that compete with the Services (e.g., Gemini API or Google AI Studio). You also may not attempt to reverse engineer, extract or replicate any component of the Services, including the underlying data or models (e.g., parameter weights)." | The Antigravity model menu also serves Anthropic Claude 4.6 and GPT-OSS models through Google's platform; using them via `agy` runs under Google's terms, and competing-model work stays barred by the clause regardless. |

Practical upshot for a Nous Research / Hermes (competing-model) orchestrator: the Claude and
Grok branches are barred for competing-model development; GPT is reachable (even on a ChatGPT
plan) but its Output cannot feed competing-model work; GLM is the most permissive target —
open-weight AND Hermes Agent is on Z.ai's officially supported tools list. For a Codex-driven
orchestrator, reach GPT through Codex's own subagents, not a nested `codex exec`.

## Sources

- Anthropic Commercial Terms (D.4) — https://www.anthropic.com/legal/commercial-terms
- "Can I use my Outputs to train an AI model?" — https://support.claude.com/en/articles/12326764-can-i-use-my-outputs-to-train-an-ai-model
- TNW, OpenClaw subscription block (Apr 4, 2026; Cherny statement) — https://thenextweb.com/news/anthropic-openclaw-claude-subscription-ban-cost
- VentureBeat, Jan 2026 harness-spoofing / xAI-via-Cursor enforcement — https://venturebeat.com/technology/anthropic-cracks-down-on-unauthorized-claude-usage-by-third-party-harnesses
- Digital Applied, June 15 2026 credit overhaul ANNOUNCED then PAUSED — https://www.digitalapplied.com/blog/anthropic-claude-credit-overhaul-june-15-2026
- Zed, post-pause status of `claude -p` / ACP apps — https://zed.dev/blog/anthropic-subscription-changes
- Latent Space, Fable 5 / Mythos system card analysis — https://www.latent.space/p/ainews-anthropic-claude-fable-5-mythos
- Fortune / Gizmodo, Fable 5 silent-safeguard reversal (June 10-11, 2026) — https://fortune.com/2026/06/10/anthropic-accu-claude-fable-5-limits-capabilities-ai-researchers-developers/
- OpenAI Terms of Use (effective Jan 1, 2026) — https://openai.com/policies/terms-of-use
- OpenAI, using Codex with your ChatGPT plan — https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- Sam Altman, ChatGPT-plan OAuth in OpenClaw (May 1, 2026) — https://x.com/sama/status/2050357911915028689
- OpenAI Codex subagents — https://developers.openai.com/codex/subagents
- xAI Acceptable Use Policy (effective June 26, 2026) — https://x.ai/legal/acceptable-use-policy
- xAI Enterprise Terms of Service (May 12, 2026) — https://x.ai/legal/terms-of-service-enterprise
- Z.ai GLM Coding Plan usage policy — https://docs.z.ai/devpack/usage-policy
- Z.ai supported tools — https://docs.z.ai/devpack/tool/others
- Google Gemini API Additional Terms of Service (Mar 23, 2026) — https://ai.google.dev/gemini-api/terms
