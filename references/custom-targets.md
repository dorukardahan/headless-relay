# Custom targets

The built-in lanes (GPT, GLM, Grok, Gemini, Claude) cover the major hosted
providers, but any model with a one-shot headless CLI can be a relay target:
local models (Ollama, LM Studio, Apple MLX), regional providers, or an internal
inference endpoint wrapped in a CLI.

## The registry

Declare custom targets in `~/.agents/relay-targets.json` — the same `~/.agents`
root the major harnesses already scan for skills, so one file serves every
orchestrator on the machine. The orchestrating agent reads it when building the
target list and treats each entry as an additional lane:

```json
{
  "targets": [
    {
      "name": "qwen-local",
      "binary_check": "command -v ollama",
      "auth_check": null,
      "invoke": "ollama run qwen3:32b \"$(cat {PROMPT_FILE})\"",
      "notes": "local, open-weight, no provider terms; slow on long prompts"
    },
    {
      "name": "minimax-mlx",
      "binary_check": "command -v mlx_lm.generate",
      "auth_check": null,
      "invoke": "mlx_lm.generate --model MiniMax-M2.7 --prompt \"$(cat {PROMPT_FILE})\"",
      "notes": "Apple-silicon local lane"
    }
  ]
}
```

Field contract:

| Field | Meaning |
|-------|---------|
| `name` | Shown in offers and consensus runs. Must not collide with a built-in lane name. |
| `binary_check` | Shell command; exit 0 = installed. Plays the same role as the built-in preflight table. |
| `auth_check` | Shell command, or `null` when none is needed (typical for local models); exit 0 = authenticated. |
| `invoke` | One-shot command template. `{PROMPT_FILE}` is replaced with the handoff file path. Prefer the `"$(cat {PROMPT_FILE})"` form so prompt bytes pass verbatim (same reasoning as the file + stdin rule in SKILL.md). |
| `notes` | Free text surfaced next to the target when offering it. |

## Rules

- **Preflight applies unchanged.** Run `binary_check` (and `auth_check` when
  set) before offering or invoking a custom target. Skip unavailable entries;
  never substitute another model silently.
- **Check 1 applies unchanged.** If a custom entry reaches the same provider as
  the orchestrator's own model, use the harness's native subagent instead.
- **Check 2 is the user's homework for hosted entries.** A custom target
  pointing at a hosted provider is governed by that provider's terms exactly
  like a built-in lane. Local open-weight models carry no such constraint.
- **Security.** Registry entries execute as shell commands under the user's
  account. The file is user-authored configuration: the agent only READS it —
  never creates, edits, or "fixes" it. If an entry appears to do more than
  invoke a model CLI, stop and ask the user before running it.
- **Data-egress caution carries over.** A custom target that runs an agent in the
  caller's working directory can transmit whatever it reads — treat it like any
  cloud agent: relay only the prompt, never point it at the repo. If a wrapped CLI
  is known to package or upload the repo, run it from an empty non-git dir with
  tools denied. Do not assume a custom lane is "local" just because it is
  user-connected — a hosted/cloud CLI still sends your data to its provider.
- **Parallel runs.** Custom targets join consensus bursts like built-ins, but
  local models can saturate RAM/GPU — run heavyweight local lanes sequentially,
  the same way the Gemini lane is sequenced.

## Consumers

Skills that build on headless-relay (for example RePrompter's delivery step —
see [reprompter-relay.md](reprompter-relay.md)) should offer custom targets
exactly like built-in lanes once they pass preflight.
