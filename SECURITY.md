# Security: the Grok Build whole-repo upload

**TL;DR.** The xAI Grok Build CLI (`grok`), when run inside a git repository, uploads your
**entire tracked repository as a git bundle** (full commit history and every tracked file,
including a tracked `.env`) to xAI-controlled cloud storage, regardless of which files the model
actually reads. This is confirmed by xAI's own account and by independent wire capture. From
**v2.0.0**, headless-relay runs every Grok call **fail-closed**: isolated in an empty, non-git
temporary directory, never in your repository, and it refuses rather than risk a leak. Repo- and
diff-context work is routed to Codex, Gemini, GLM, or Claude, which a wire-test showed send no
whole-repo bundle (they are still cloud models that transmit the files they actually read). The
other four lanes are unaffected.

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

During the measured window the alternative lanes (Codex, GLM, Gemini) sent no whole-repo bundle.
Each figure is a single whole-machine egress run (n=1, no per-process backstop), so this excludes
a *synchronous* whole-repo bundle at the ~100x margin but not a deferred/async upload after the
window closed. Codex and Gemini are independently corroborated by cereblab's capture; GLM is not.
That said, none of them has any known whole-repo-bundle mechanism, which is why repo-context work
is routed to them rather than to Grok.

---

## 5. What headless-relay does about it (v2.0.0)

- **Fail-closed isolation.** Every Grok call runs in a fresh, empty, non-git temporary directory,
  with context passed only through the prompt / prompt file. No repository in the working
  directory means no git repository to bundle. If isolation cannot be guaranteed, the skill
  refuses to run Grok and says why. (One narrow residual: the guard uses `git rev-parse` to
  verify the temp dir is not inside a repo, so if the `git` binary is absent it cannot fire.
  Keep `TMPDIR` out of your repositories; on a normal machine `mktemp` uses `/tmp` or
  `/var/folders`, never a repo.)
- **No repo-context Grok.** "Read the repo", "review the diff", or any task that needs repository
  access is never sent to Grok. It goes to Codex, Gemini, GLM, or Claude, which sent no whole-repo bundle in the wire-test (still cloud models that transmit the files they actually read).
- **Honest labelling.** The Grok lane is never described as "read-only", "local", or "no network".
- **Media too.** Image/video generation with Grok obeys the same isolation (generate in a temp
  dir, move the file out). For image-only work, Codex or Gemini are preferred because they keep the
  repo local. Video is Grok-only, so it runs isolated.

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

These reduce risk but do not make Grok "safe" for a private repo, and some are **community-reported
and not documented by xAI** — verify them for your version, and remember they are *retention/
telemetry* controls, not a guarantee that data never transmits.

- **`/privacy`** (official, in-CLI): toggles data retention and, per xAI, deletes previously synced
  data. Retention only, not transmission. Note on ZDR: the consumer OAuth-login CLI session (this
  incident's context) is **not** ZDR; per xAI, ZDR applies to Team/Enterprise accounts and to
  API-key use of Grok Build.
- **`~/.grok/config.toml`** (community-reported, wire-verified only on 0.2.93, may change per
  version): `[harness] disable_codebase_upload = true`, `[telemetry] trace_upload = false`,
  `[features] telemetry = false`. To confirm a control is *local*, run Grok once and check the
  `trace.upload.decision` log shows `trace_upload_source=config` or `env` — `source=remote` is not
  local protection. Edit this yourself; the skill never writes your config.
- **`[tools] respect_gitignore = true`** (official) limits search/read tools only; it does **not**
  stop the whole-repo bundle.
- **Sandbox + tool-deny for the "second exposure."** Isolation stops the whole-repo bundle, but an
  agentic Grok run can still read elsewhere on the machine via `Read`/`Bash`/MCP and send it as
  model context. For a pure text relay, add `--sandbox strict` (macOS Seatbelt limits reads to the
  CWD + system paths — pass the prompt inline, or copy a prompt file into the isolated CWD) and
  `--deny 'Read' --deny 'Bash'`. Note: `--permission-mode dontAsk` is accepted but not yet enforced
  (rely on `--sandbox` + `--deny`), and macOS does not block a child process's network.
- **True zero egress:** if code must never leave the machine, do not use a cloud model at all — use
  a fully local model (e.g. via Ollama / LM Studio / MLX, connectable through
  `references/custom-targets.md`).

---

## Reporting

Security issues with this skill (not with Grok Build itself): open an issue at
https://github.com/dorukardahan/headless-relay . Issues with the Grok Build CLI go to xAI via the
in-CLI `/feedback` command.
