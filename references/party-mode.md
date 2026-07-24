# Party Mode / Council Mode

Party Mode is the explicit **ask everyone who is safely available** workflow. It is broader than an ordinary two-model consensus run: the orchestrator preflights every built-in lane plus every valid custom target, gives each admitted lane the same frozen brief, then synthesizes agreement, dissent, and evidence without treating majority vote as truth.

## Triggers

Enter Party Mode only when the user explicitly asks for it, for example:

- `party mode`
- `council mode`
- `ask everyone` / `ask every model`
- `run all available models`
- `her şeyi dene` / `hepsine sor`

Do not turn a routine “second opinion” request into Party Mode. It consumes more quota, time, and local compute than a targeted relay.

## Contract

1. **Freeze one brief.** Write the complete question and allowed context to one prompt file. Every admitted lane receives those same bytes. Do not improve or shorten the brief differently per model.
2. **Build the candidate roster.** Include every built-in lane and every syntactically valid entry in `~/.agents/relay-targets.json`.
3. **Apply gates before invocation.** For every candidate, run its binary/auth preflight, the same-provider/native-subagent check, the provider-terms gate, and the task/data-egress check.
4. **Admit all safe and available lanes.** “Everyone” means all lanes that pass the gates, not all names the skill has ever heard of. Record unavailable, excluded, or policy-blocked lanes with a short reason. Never install a binary, log in, rotate auth, or silently substitute another model to make the roster look full.
5. **Schedule by resource class.** Parallelize independent cloud/CLI lanes that are safe together. Run Antigravity sequentially because of its documented burst hang. Run heavyweight local custom targets sequentially unless their registry notes explicitly say concurrent execution is safe. Never saturate the parent machine just to maximize lane count.
6. **Capture one artifact per lane.** Use a fresh run directory containing the frozen brief, each lane's stdout, a bounded stderr/status file, and a manifest. A failed lane must not erase successful outputs.
7. **Synthesize as the parent.** The parent orchestrator reads all successful artifacts. Report shared findings, unique findings by lane, direct contradictions, and unresolved questions. Preserve minority dissent. A majority vote is not evidence.
8. **Verify before promoting claims.** Concrete file:line, command, benchmark, or source claims outrank vague agreement, but still require verification through the parent’s tools or primary sources.

## Roster receipt

Before invoking, print or persist a compact roster with these states:

- `admitted` — preflight and gates passed
- `unavailable` — binary, endpoint, model, or auth missing
- `excluded_same_provider` — use a native subagent instead
- `blocked_policy` — provider terms or task policy forbids the handoff
- `blocked_egress` — the lane cannot safely receive the requested context

If only one external lane is admitted, continue only if the user asked to use whatever is available, and label the result **degraded Party Mode**. Otherwise stop and ask whether a single-lane answer is useful.

## Run directory

Use a private temporary directory and restrictive permissions:

```bash
run_dir=$(mktemp -d "${TMPDIR:-/tmp}/headless-party.XXXXXX")
chmod 700 "$run_dir"
cp /absolute/path/to/handoff.md "$run_dir/brief.md"
chmod 600 "$run_dir/brief.md"
```

Recommended artifact names:

```text
brief.md
manifest.json
answers/gpt.md
answers/glm.md
answers/grok.md
answers/gemini.md
answers/claude.md
answers/<custom-target>.md
status/<lane>.json
synthesis.md
```

Do not place credentials, raw auth output, or secret-bearing environment dumps in the manifest. The manifest records lane name, state, reason, started/finished timestamps, exit code, timeout, and artifact path—not tokens.

## Scheduling rules

- Start compatible parallel lanes in one shell burst, using the exact commands and safety wrappers from `SKILL.md`.
- Wait for that burst to finish before running Antigravity.
- Run heavyweight local custom targets one at a time unless the target notes explicitly permit concurrency.
- Give each lane a bounded timeout. Timeout is a lane-level failure, not a reason to discard other answers or retry indefinitely.
- Do not run Grok in the repository. Pass only the frozen prompt bytes through `grok_relay`.
- Do not grant repo or network access merely because Party Mode was requested. Each lane keeps its normal least-privilege contract.

## Synthesis format

```markdown
# Party Mode result

## Roster
- admitted: ...
- unavailable/excluded/blocked: lane — reason

## Shared findings
- finding — supporting lanes — verification receipt

## Unique findings
- lane: finding — evidence or verification status

## Contradictions
- claim A vs claim B — what was checked — current verdict

## Parent verdict
- decision/recommendation
- confidence and unresolved risks
```

## GREEN gate

Party Mode is GREEN only when:

- the frozen brief exists;
- the full candidate roster was evaluated;
- every admitted lane has an output or explicit timeout/error receipt;
- skipped lanes have reasons;
- the parent synthesis preserves dissent and distinguishes verified from unverified claims;
- no silent model/provider substitution occurred.

A shell burst that launched several commands is not a completed council. A model-generated summary that hides failed or dissenting lanes is not a completed council.