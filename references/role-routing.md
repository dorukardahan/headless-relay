# Role-to-lane routing (configurable example)

A routing table answers one question before any relay call: **which lane should take this kind
of work, and what runs when it is down?** This page is a generic template for agent stacks that
split work by role (coding, judgment, exploration, review, and so on) across several headless
lanes. Every lane, model id and role below is an example. Replace them with the lanes you have
installed and verified; nothing here is a benchmark ranking or a recommendation of one vendor.

It builds on the rules in [SKILL.md](../SKILL.md): preflight every lane, never substitute a
model silently, and report which lane actually ran.

## Lane aliases

Give each installed lane a short alias and keep the table below in those aliases, so changing a
model id touches one place.

| Alias | Provider family | Headless entry point (example) |
|-------|-----------------|--------------------------------|
| `codex` | OpenAI | `codex exec -s read-only --skip-git-repo-check -m <codex-model> </dev/null` |
| `claude` | Anthropic | `claude -p --model <claude-model> --permission-mode plan --output-format json </dev/null` |
| `glm` | Zhipu | a Claude-Code-style custom lane, see below |
| `gemini` | Google | `agy -p "<prompt>" --model <agy-model> </dev/null`, always solo |

Notes per lane:

- **codex.** Read-only sandbox by default; pass `-m` explicitly so the model does not depend on
  local config. Move to a write-capable sandbox only for a task that is meant to edit files.
- **claude.** `--model <alias>` pins the model; without it the CLI uses its own default, which
  may not be the one you intended. `--permission-mode plan` keeps a review or reasoning call
  read-only. Mind the Claude gate in [anthropic-terms.md](anthropic-terms.md).
- **glm.** Some GLM setups ship a CLI that accepts the Claude Code flag set (`-p`,
  `--permission-mode`, `--output-format`) and points it at the GLM endpoint. Register it as a
  custom target (see [custom-targets.md](custom-targets.md)) rather than hard-coding it:

  ```json
  {
    "targets": [
      {
        "name": "glm",
        "binary_check": "command -v <glm-cli>",
        "auth_check": null,
        "invoke": "<glm-cli> -p --permission-mode plan --output-format json \"$(cat {PROMPT_FILE})\" </dev/null",
        "notes": "Claude-Code-style CLI pointed at a GLM endpoint; model id comes from that CLI's own config"
      }
    ]
  }
  ```

  A CLI that wraps another vendor's client may print harmless warnings on stderr (for example
  an unrecognized-model notice). Judge success by exit status and a non-empty answer, not by
  silent stderr.
- **gemini.** Run `agy` solo: never in parallel with another `agy` call, because bursts can
  hang it. Wrap it with the bounded `agy_run` / `agy_answer` helpers from SKILL.md so a stuck
  run still ends at a deadline. Where the model supports it, set the effort level (for example
  `--effort high`) per task rather than globally.

## Routing table

Order per role: primary, then fallback, then third. Move to the next lane only when the previous
one errors or times out (non-zero exit, deadline, or empty answer), and report which lane ran.
Multi-seat roles list one lane per seat.

| Role | Primary | Fallback | Third |
|------|---------|----------|-------|
| feature, refactoring | `codex` | `claude` | `gemini` |
| bug-fix | `codex` | `claude` | `gemini` |
| performance work | `codex` | `claude` | `gemini` |
| iterative hill-climbing | `codex` | `gemini` | `claude` |
| judgment and prose | `claude` | `codex` | `gemini` |
| hardest tasks | `claude` | `codex` | `gemini` |
| exploration (read many files, map a codebase) | `glm` | `gemini` | `codex` |
| explanation | `claude` | `codex` | `gemini` |
| parallel investigators | `glm` | `codex` | `gemini` |
| synthesis of investigator output | `claude` | `gemini` | `codex` |
| tool-heavy side work | `glm` | `codex` | `gemini` |
| judgment on tool output | `claude` | `codex` | `gemini` |
| competing runners (two seats) | `codex` + `claude` | `gemini` replaces the failed seat | `glm` |
| cross-judge of those runners | `gemini`, then `claude` | `glm` | `codex` only if no `codex` runner took part |
| design runners (two seats) | `claude` + `codex` | `gemini` replaces the failed seat | `glm` |
| adversarial reviewers (two seats) | `codex` + `gemini` | `claude` replaces the failed seat | `glm` |
| swarm workers | `glm` | `gemini`, one worker at a time | `codex` |

How to choose your own rows: pick the primary for a role from whatever evidence you trust for
that kind of work (your own task results, a public benchmark that matches the task), then fill
the fallback and third from a **different provider family**, closest to the primary on the same
measure. A fallback from the same family as the primary fails for the same account, outage or
quota reason, so it is not a fallback.

## Different-family rule for reviewers and judges

A model that reviews, judges or cross-checks work must come from a different provider family
than the model that wrote that work.

- For a single-writer task, the reviewer lane's family must differ from the writer's.
- For a contest between runners, the judge pool must exclude every runner's family, including a
  fallback runner that took over a seat mid-run. Skip any pool entry that matches, then continue
  down the pool.
- If no lane from another family is available, say so and report the result as unreviewed
  instead of letting a same-family model sign off.

## General fallback order

When a lane is down and the role has no row in the table, try, in order: `codex`, then `claude`,
then `gemini`. Skip a lane that fails preflight, and never retry a lane that failed on
authentication by logging in or copying credentials. Stop and tell the user instead.

Keep each call bounded: give every invocation its own deadline well below your harness's
overall limit (a short one, such as 180 seconds, for smoke tests), save raw output to a file,
and check the exit status and answer before moving to the next lane.

## Verifying a lane before it goes in the table

Before listing a model id as a primary or fallback, run one trivial read-only prompt through the
exact command line you will use and confirm a non-empty answer. Record the model id and the date
next to the lane. Catalog listings can include models your account cannot run, and a CLI may
silently fall back to a default model when a flag is omitted.
