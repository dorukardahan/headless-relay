# Security: the Grok Build whole-repo upload

**TL;DR.** The xAI Grok Build CLI (`grok`), when run inside a git repository, uploads your
**entire tracked repository as a git bundle** (full commit history and every tracked file,
including a tracked `.env`) to xAI-controlled cloud storage, regardless of which files the model
actually reads. This is confirmed by xAI's own account and by independent wire capture. From
**v2.0.0**, headless-relay runs every Grok call **fail-closed**: isolated in an empty, non-git
temporary directory, never in your repository, and it refuses rather than risk a leak. From
**v2.0.3** every Grok call goes through two helper functions (`grok_relay` / `grok_media`) that add
two more layers: a **clean, temporary `GROK_HOME`** so Grok cannot load your global
`~/.grok/AGENTS.md`, rules, skills, or MCP servers into the model turn (a real egress, verified on
0.2.99 — see §4a), and **tool denial** (`--deny '*'` for text; non-media tools denied by name for
media) plus a best-effort `--sandbox strict`. These narrow the exposure to the prompt itself; they
do **not** make Grok local — it is still a cloud model, and what you put in the prompt still goes
to xAI. Repo- and diff-context work is routed to Codex, Gemini, GLM, or Claude, which a wire-test
showed send no whole-repo bundle (they are still cloud models that transmit the files they actually
read). The other four lanes are unaffected.

This document exists so that a user who has never heard of the incident cannot be surprised by
it, and so anyone who already used Grok Build can assess and contain their exposure.

---

## 1. What happens

Grok Build has two separate outbound data paths:

- **Channel A — model turns.** The prompt, the model's context, and the files the model actually
  opens (including a `.env` it reads) go to the inference backend (`POST /v1/responses` on
  `cli-chat-proxy.grok.com`). This is normal for any cloud model.
- **Channel B — whole-repo upload.** *Separately*, and *independently of Channel A*, the CLI
  packages the git repository at (or above) its working directory into a **git bundle** and
  uploads it (`POST /v1/storage`) to the Google Cloud Storage bucket `grok-code-session-traces`.
  The bundle contains the full commit history and every tracked file, **even files the model was
  never asked to read**.

What is in the bundle: every **tracked** file and the full history. A committed/tracked `.env`
is included. A file that was committed and later deleted is still in the history, so it is
included too. What is **not** in the bundle: untracked files and files that are gitignored and
were never committed (though a gitignored file that the model *reads* still leaves via Channel A).

None of these stop Channel B: `--disable-web-search`, denying file-read permission, a "do not
read any files" prompt, or turning the "Improve the model" toggle off.

---

## 2. Evidence, separated by confidence

**Confirmed** (first-party admission plus independent wire capture):
- xAI's official **Grok account on X** stated it directly (a first-party admission via its X
  account — strong, though not a formal security advisory): Grok Build "uploads your entire repo as a
  git bundle (full history + all tracked files) ... even files the agent never reads ... even with
  prompts like 'do not read any files.' This is by design ... 'Improve the model' toggle doesn't
  stop the upload. Advice: Don't use on sensitive/private repos."
  (x.com/grok/status/2076298375150911623)
- **cereblab** captured the traffic with mitmproxy and reconstructed the uploaded repo from the
  wire, recovering a planted **never-read canary file** from the bundle; on a 12 GB repo of
  never-read files, ~5.1 GiB went to `/v1/storage`. Same rig showed Claude Code, Codex, and Gemini
  sent no whole-repo bundle (they are still cloud models that transmit the files they read).

**Observed in our own wire-test** (2026-07-13, grok 0.2.99, single run; see §4): Codex, GLM
(opencode), and Gemini (agy) sent no whole-repo bundle during the measured window; Grok's upload
is currently *off* but only via a revocable server-side flag. (Codex and Gemini also have
cereblab's independent capture behind them; GLM does not.)

**Disputed / not a guarantee:** after the story broke, xAI's server began returning
`disable_codebase_upload: true` for the same client version. This is a **server-side, revocable**
change, possibly account-scoped (the researcher who found it thinks it may be targeted at his
account); xAI has published no statement about scope, retention, or deletion, and the CLI
changelog (0.2.94 through 0.2.99) says nothing about it.

**Unknown / untested:** whether xAI *trains* on the data (transmission and storage are proven;
training is a separate policy question). Whether running Grok from an isolated non-git directory
*empirically* stops the bundle could not be proven while the feature is server-suppressed (see
§4); it is a sound architectural inference (a git bundle can only be built from a git repo), not a
measured result on the current version.

---

## 3. Primary sources

- Reproduction repo: https://github.com/cereblab/grok-build-exfil-repro
- Wire-level analysis: https://gist.github.com/cereblab/dc9a40bc26120f4540e4e09b75ffb547
- xAI Grok account admission (X): https://x.com/grok/status/2076298375150911623
- xAI SpaceXAI account on `/privacy` + retention (X): https://x.com/SpaceXAI/status/2076692402442846289
- Discussion (secondary): https://news.ycombinator.com/item?id=48877371
- xAI docs (official controls): https://docs.x.ai/build/settings/reference ,
  https://docs.x.ai/build/enterprise (ZDR is enforced at the Team/Enterprise level; xAI also
  states API-key use of Grok Build respects ZDR)

---

## 4. Our wire-test (2026-07-13, grok 0.2.99)

Method: a synthetic, secret-free canary repo carrying a **19 MB incompressible never-read blob**
as a size discriminator; whole-machine egress measured as the `netstat -ib` output-byte delta on
the default interface; Grok cross-checked against its own `trace.upload.decision` log. Positive
control: a known 10 MB upload measured 11.5 MB, confirming the method catches multi-MB transfers
(baseline noise was ~0.25 MB).

| Lane | working dir | egress | whole-repo bundle? |
|------|-------------|-------:|--------------------|
| grok 0.2.99 (control) | inside canary repo | 0.25 MB | no |
| grok 0.2.99 | isolated non-git dir | 0.27 MB | no |
| codex 0.144.1 | inside canary repo | 0.51 MB | no |
| GLM / opencode | inside canary repo | 0.17 MB | no |
| Gemini / agy | inside canary repo | 0.31 MB | no |

Both Grok runs logged `uploads_enabled=False`, `upload_reason=feature_off`,
`trace_upload_source=remote`, `has_remote_settings=True`, `data_collection_disabled=False`. So the
upload is **off, but the reason is a remote/server setting** — no local configuration is
responsible, and the capability is still present in the 0.2.99 client. That is why this skill does
not trust the current "off" state: xAI can re-enable it remotely at any time, and other accounts
or versions may already have it on. It also means the isolation safeguard could not be positively
demonstrated (with the feature server-off, in-repo and isolated both show no bundle, and there is
no local switch to force it on for a contrast test).

**Update (2026-07-14):** a follow-up check on the same 0.2.99 client, after setting
`[telemetry] trace_upload = false` and `[features] telemetry = false` in `~/.grok/config.toml`,
logged `trace_upload_source=config` (was `remote`) with uploads off — so for the **trace/telemetry
channel** those config keys are honored locally on 0.2.99. The **bundle** switch
(`disable_codebase_upload`) still cannot be independently verified: with uploads globally off, the
codebase-upload path never fires, so there is no observable effect to measure. See §7.

### 4a. Global rules load into the model turn (2026-07-14, grok 0.2.99)

A separate egress, independent of the bundle, was confirmed on 0.2.99: Grok auto-loads **global
project rules from `~/.grok/`** — in particular `~/.grok/AGENTS.md` — into the model context on
every call, and sends it to xAI as part of the turn. Across five isolated canary sessions (empty
non-git dir, `--sandbox strict`, `--deny '*'`), the global `AGENTS.md` content appeared in each
session's model-turn record: 2 of 3 sampled content slices matched verbatim, and the leaking
transcripts ran ~5 KB larger than a clean-`GROK_HOME` run (consistent with the full ~5,367-char
file), while a clean `GROK_HOME` dropped this to 0 of 3. Grok's own doc (`12-project-rules.md`)
states global rules from `~/.grok/` apply to all projects. `--system-prompt-override` did **not** suppress it (the rules load
as a separate context block). Running with a **clean, temporary `GROK_HOME`** (seeded only with
auth) removed it entirely — verified: the `AGENTS.md` content no longer appeared, no MCP servers
loaded, and auth still worked. This is why v2.0.3 routes every call through a clean `GROK_HOME`
(§5). Catalog fetches (`grok models`) send no model turn, so they do not leak this way.

**Re-confirmed on grok 0.2.101 (2026-07-14):** after the CLI self-updated from 0.2.99 to 0.2.101,
every v2.0.3 behavior reproduced identically — the default leak persists, the clean `GROK_HOME`
stops it, `--deny '*'` refuses a forced tool call, `grok_media`'s by-name denial keeps `image_gen`
working, and three back-to-back `grok_relay` calls left the real `~/.grok` login intact (the
token sync-back, §5). The "verified on 0.2.99" notes elsewhere in this doc therefore hold on
0.2.101 as well.

During the measured window the alternative lanes (Codex, GLM, Gemini) sent no whole-repo bundle.
Each figure is a single whole-machine egress run (n=1, no per-process backstop), so this excludes
a *synchronous* whole-repo bundle at the ~100x margin but not a deferred/async upload after the
window closed. Codex and Gemini are independently corroborated by cereblab's capture; GLM is not.
That said, none of them has any known whole-repo-bundle mechanism, which is why repo-context work
is routed to them rather than to Grok.

---

## 5. What headless-relay does about it (v2.0.0 → v2.0.3)

From v2.0.3 every Grok call goes through one of two helper functions (`grok_relay` for text,
`grok_media` for image/video) defined in SKILL.md. Each layer below is applied by the helper:

- **Fail-closed isolation.** Every Grok call runs in a fresh, empty, non-git temporary directory.
  No repository in the working directory means no git repository to bundle. If isolation cannot be
  guaranteed — `mktemp` failed, the temp dir landed inside a git repo, or (since v2.0.1) the `git`
  binary is absent so the check cannot verify — the helper refuses to run Grok and says why. Keep
  `TMPDIR` out of your repositories; on a normal machine `mktemp` uses `/tmp` or `/var/folders`.
- **Clean `GROK_HOME` (v2.0.3) — the global-rule leak.** By default Grok loads your global
  `~/.grok/AGENTS.md`, rules, skills, and MCP servers into every model turn and sends them to xAI
  (§4a). The helper points `GROK_HOME` at a throwaway temp dir seeded with only auth (a copied
  token, or `XAI_API_KEY`), so none of that loads — verified on 0.2.99. This is the layer that
  makes the "isolated" call actually free of your machine's global context. **Auth caveat:** Grok
  refreshes the token during the call and xAI rotates refresh tokens, so a temp home that discarded
  the refresh would rotate your real `~/.grok` login OUT over repeated relays. The helper therefore
  copies the refreshed token back to `~/.grok/auth.json` (atomic, success-only); set `XAI_API_KEY`
  to avoid the token copy entirely.
- **Tools denied (v2.0.2, mechanism proven v2.0.3) — the "second exposure".** An agentic Grok run
  could otherwise read elsewhere on the machine via its `run_terminal_command` / `read_file` / MCP
  tools and send that as model context. `grok_relay` denies all of them with `--deny '*'`; verified
  on 0.2.99 by forcing a tool call, which the run refused with `Denied by permission policy: deny
  rule on any tool matching "*"`. `grok_media` cannot use `--deny '*'` (it would block `image_gen`),
  so it denies every non-media tool by name and leaves the four media tools usable (verified).
- **`--sandbox strict` is a second layer only.** It **fails open**: per xAI's docs, when a built-in
  profile can't be applied Grok warns and continues unenforced (only an explicit *custom* profile
  refuses to start). So isolation, the clean home, and the deny rules are load-bearing; the sandbox
  is a bonus. `--permission-mode dontAsk` is accepted but not yet enforced; macOS does not block a
  child's network.
- **Still a cloud model, not "local".** The layers above stop the repo bundle, the global-rule
  leak, and tool-driven reads. They do **not** stop the prompt you pass or Grok's reasoning from
  reaching xAI. The Grok lane is never described as "read-only", "local", or "no network".
- **No repo-context Grok.** "Read the repo", "review the diff", or any task that needs repository
  access is never sent to Grok. It goes to Codex, Gemini, GLM, or Claude, which sent no whole-repo
  bundle in the wire-test (still cloud models that transmit the files they actually read).
- **Media too.** `grok_media` applies the same isolation + clean `GROK_HOME` + sandbox + non-media
  tool denial, then moves the artifact out of the temp home. For image-only work, Codex or Gemini
  are preferred (no whole-repo bundle). Video is Grok-only, so it runs through `grok_media`.

---

## 6. If you have already used Grok Build in a real repository

Treat any repository you ran Grok Build inside — before isolation — as potentially uploaded in
full, including its history and any tracked secrets. To check your own machine safely, on your own
data (do not paste raw logs anywhere, and do not send them to a model):

```bash
# Which sessions logged an upload decision or a repo-state upload? Counts only, no content.
grep -rhoE 'repo_state\.upload\.[a-z]+|trace\.upload\.decision' "$HOME/.grok/logs" 2>/dev/null | sort | uniq -c

# Is a bundle currently staged locally?
du -sh "$HOME/.grok/upload_queue" 2>/dev/null
```

Interpreting it: `repo_state.upload.enqueued` means a bundle was **staged locally**; it is not by
itself proof of delivery, and an empty queue is not proof of non-delivery. `trace.upload.decision`
with `uploads_enabled=true` (or `trace_upload_source=remote` with the feature on) indicates the
upload path was active for that session. For a thorough, anonymised local forensic pass, use a
dedicated read-only audit that separates *staged* from *delivered* from *retained*, and never
prints secrets.

If a repository with real secrets was in scope, rotate what could have been exposed: API keys and
tokens (including any in a tracked `.env`), database credentials, SSH/private keys, cloud
credentials, and wallet/keystore/seed material. Then, on the account side, use the in-CLI
`/privacy` command (below) and, if needed, request access/deletion of your data through
https://x.ai/privacy-portal.

**This machine-level incident review is out of scope for the skill itself** — the skill only fixes
future behaviour. Run the review separately.

---

## 7. Optional hardening (defense-in-depth, not a substitute for isolation)

These reduce risk but do not make Grok "safe" for a private repo — they are *retention/telemetry*
controls, not a guarantee that data never transmits. Labels below separate what xAI documents from
what is only community-reported; verify for your version.

- **`/privacy`** (official, in-CLI): toggles data retention and, per xAI, deletes previously synced
  data. Retention only, not transmission. Note on ZDR: the consumer OAuth-login CLI session (this
  incident's context) is **not** ZDR; per xAI, ZDR applies to Team/Enterprise accounts and to
  API-key use of Grok Build.
- **`~/.grok/config.toml`** kill-switches — mixed provenance:
  `[telemetry] trace_upload = false` and `[features] telemetry = false` are **official settings**
  (xAI configuration reference) and were **verified honored on 0.2.99** (2026-07-14, one setup:
  setting them flipped the `trace.upload.decision` log from `trace_upload_source=remote` to
  `config`). `[harness] disable_codebase_upload = true` is **community-reported** (recognized by
  the binary; wire-verified only on 0.2.93, and its effect on the bundle channel is currently
  unmeasurable — see the §4 update). To confirm a control is *local* on your setup, run Grok once
  and check the log shows `trace_upload_source=config` or `env` — `source=remote` is not local
  protection. Edit this yourself; the skill never writes your config.
- **`[tools] respect_gitignore = true`** (official) limits search/read tools only; it does **not**
  stop the whole-repo bundle.
- **Clean `GROK_HOME` for the global-rule leak** — the `grok_relay` / `grok_media` helpers (v2.0.3,
  §5) point `GROK_HOME` at a throwaway temp dir seeded with only auth, so Grok cannot load your
  global `~/.grok/AGENTS.md` / rules / skills / MCP into the model turn (§4a). If you write your own
  Grok invocation, do the same: `GROK_HOME="$(mktemp -d)"` with `auth.json` copied in (or
  `XAI_API_KEY` set) — AND copy the refreshed `auth.json` back to `~/.grok/` afterward, or repeated
  runs will rotate your subscription login out (xAI rotates refresh tokens; a discarded temp home
  loses the refresh). Note this also means your `config.toml` kill-switches above do **not** apply
  to such a call — a relay relies on isolation + deny + clean home, not on those flags.
- **Sandbox + tool-deny for the "second exposure"** — baked into the helpers since v2.0.2/v2.0.3
  (see §5). If you write your own invocation, mirror it: `--deny '*'` for a text relay (verified on
  0.2.99 to refuse a forced tool call), non-media tools denied by name for media, plus
  `--sandbox strict`. Caveats: the sandbox **fails open** for built-in profiles (warning + continue;
  only an explicit custom profile refuses to start), `--deny '*'` also blocks the image/video tools
  (deny by name for media), `--permission-mode dontAsk` is accepted but not yet enforced, and macOS
  does not block a child process's network.
- **True zero egress:** if code must never leave the machine, do not use a cloud model at all — use
  a fully local model (e.g. via Ollama / LM Studio / MLX, connectable through
  `references/custom-targets.md`).

---

## Reporting

Security issues with this skill (not with Grok Build itself): open an issue at
https://github.com/dorukardahan/headless-relay . Issues with the Grok Build CLI go to xAI via the
in-CLI `/feedback` command.
