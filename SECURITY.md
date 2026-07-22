# Security: Grok Build and your data

**TL;DR.** Earlier *shipped* versions of the xAI Grok Build CLI (`grok`), run inside a git
repository, uploaded your **entire tracked repository as a git bundle** (full commit history and
every tracked file, including a tracked `.env`) to xAI-controlled cloud storage, regardless of which
files the model actually read. That was real — confirmed by xAI's own account and by independent
wire capture. On **2026-07-15 xAI open-sourced Grok Build** (Apache-2.0,
`github.com/xai-org/grok-build`), deleted previously-retained coding data, and set retention off by
default. A source audit of that release (commit `c68e39f`) found the **whole-repo bundle path is
gone from the source**, the remaining trace-upload defaults **off**, and your **local
`~/.grok/config.toml` beats xAI's remote settings**. Two residual concerns remain, so headless-relay
(v3.0.0) still routes Grok through two small helpers: they run `grok` under a **hermetic child
environment** (`env -i` allowlist — only a handful of vars reach grok, dropping your other secrets and
grok's own endpoint / auth-provider-command / log / compat overrides) with an **empty synthetic
`HOME`** AND a **clean temporary `GROK_HOME`** (so it reads neither your `~/.claude` / `~/.cursor` /
`~/.codex` config nor grok's own `~/.grok/AGENTS.md` into the model turn — both are still-default
scans), with auth supplied out-of-band via **`GROK_AUTH_PATH` → your real `auth.json`** (grok refreshes
it in place; the wrapper never reads or copies it) or **`XAI_API_KEY`**, in an **empty non-git dir**
(verified outside any git tree) **with tool use locked down**, under a real watchdog timeout (cheap insurance,
because the shipped binary can't be verified against the open source). Scope is **personal / consumer**
auth; team/enterprise managed-policy parity is unverified (§5). Grok is still a **cloud model** — the
prompt goes to xAI. The other four lanes are unaffected.

This document exists so a user who never heard of the incident cannot be surprised by it, so anyone
who already ran Grok Build can assess and contain their exposure, and to record exactly what the
2026-07-15 open-sourcing does and does not change.

---

## 1. What happened (the incident)

Grok Build has two separate outbound data paths:

- **Channel A — model turns.** The prompt, the model's context, and the files the model actually
  opens (including a `.env` it reads) go to the inference backend (`POST /v1/responses` on
  `cli-chat-proxy.grok.com`). This is normal for any cloud model.
- **Channel B — whole-repo upload (historical).** *Separately*, and *independently of Channel A*,
  earlier shipped versions packaged the git repository at (or above) the working directory into a
  **git bundle** and uploaded it (`POST /v1/storage`) to the Google Cloud Storage bucket
  `grok-code-session-traces` — the full commit history and every tracked file, **even files the
  model was never asked to read**. A committed/tracked `.env` was included; a file committed and
  later deleted was still in the history. It was **not** stopped by `--disable-web-search`, by
  denying file-read permission, by a "do not read any files" prompt, or by the "Improve the model"
  toggle. Section 4 covers what the open-sourcing changed about Channel B.

---

## 2. Evidence (the historical incident)

**Confirmed** (first-party admission plus independent wire capture):
- xAI's official **Grok account on X** stated it directly: Grok Build "uploads your entire repo as a
  git bundle (full history + all tracked files) ... even files the agent never reads ... even with
  prompts like 'do not read any files.' This is by design ... 'Improve the model' toggle doesn't
  stop the upload. Advice: Don't use on sensitive/private repos."
  (x.com/grok/status/2076298375150911623)
- **cereblab** captured the traffic with mitmproxy and reconstructed the uploaded repo from the
  wire, recovering a planted **never-read canary file** from the bundle; on a 12 GB repo of
  never-read files, ~5.1 GiB went to `/v1/storage`. The same rig showed Claude Code, Codex, and
  Gemini sent no whole-repo bundle (they are still cloud models that transmit the files they read).

**Also confirmed — a second, separate egress (global rules), still present.** Independent of the
bundle, Grok auto-loads global project rules into every model turn: `~/.grok/AGENTS.md`, and — via
its Claude/Cursor **compatibility scanners, every `[compat.*]` cell default ON** — your
`~/.claude/CLAUDE.md`, `~/.claude/settings.json` hooks, `~/.claude/skills`, and `~/.claude.json` MCP
servers, all resolved from `$HOME`. Verified with canary files on grok 0.2.99 / 0.2.101 (a canary
`~/.claude/CLAUDE.md` showed as an active "Project Instruction"; a synthetic `HOME` dropped it to
zero), and re-confirmed in the open-sourced code (§4). This is the residual the current helper
targets.

**Unknown / untested:** whether xAI *trains* on data it received (transmission and storage were
proven; training is a separate policy question).

---

## 3. Primary sources

- xAI open-source announcement (X): https://x.com/SpaceXAI/status/2077494535387828644
- Open-sourced code: https://github.com/xai-org/grok-build (Apache-2.0)
- Reproduction repo: https://github.com/cereblab/grok-build-exfil-repro
- Wire-level analysis: https://gist.github.com/cereblab/dc9a40bc26120f4540e4e09b75ffb547
- xAI Grok account admission (X): https://x.com/grok/status/2076298375150911623
- xAI SpaceXAI account on `/privacy` + retention (X): https://x.com/SpaceXAI/status/2076692402442846289
- Discussion (secondary): https://news.ycombinator.com/item?id=48877371
- xAI docs (official controls): https://docs.x.ai/build/settings/reference ,
  https://docs.x.ai/build/enterprise (ZDR is enforced at the Team/Enterprise level; xAI also
  states API-key use of Grok Build respects ZDR)
- Re-checked on X 2026-07-22: the incident, the 2026-07-13 server-side upload halt, and the 2026-07-15
  open-sourcing stay corroborated by the researcher (cereblab) and follow-up community analyses (through
  2026-07-20); nothing since contradicts the audit below. The shipped binary remains unverifiable against
  the source, which is why the helper isolates Grok rather than trusting the toggle, the audit, or the fix.

---

## 4. What the 2026-07-15 open-sourcing changed

On 2026-07-15 xAI open-sourced Grok Build (Apache-2.0), reset usage limits, deleted previously
retained coding data, and set retention off by default. A source audit of the published tree
(commit `c68e39f`) established:

- **The whole-repo bundle (Channel B) is gone from the source.** No `git bundle` / `codebase_upload`
  / whole-repo archive exists anywhere in the tree; the dedup/archive symbols the old path used are
  defined but unwired (the code comments it as removed). Every `tar` / `zip` builder in the workspace
  was read — none package the user's repo or working directory (they cover Grok's own
  `~/.grok/memory`, a manual local session export, and test fixtures). The remaining trace-upload
  pipeline serializes only the model's **own** turn I/O (conversation + tool-call records), and the
  per-turn `config_files.json` artifact is hard-disabled in code. It defaults **off** (telemetry
  defaults off; trace-upload inherits that).
- **Your local `~/.grok/config.toml` beats xAI's remote settings.** The config resolver's precedence
  is `requirements > CLI > env > config.toml > managed > remote > default`, and a repo test asserts a
  locally-disabled upload stays off even when a remote flag says enable. A server-pushed flag cannot
  silently re-enable an upload you turned off locally. (Note: the load-bearing local keys are
  `[features] telemetry` and `[telemetry] trace_upload`. The community-reported
  `disable_codebase_upload` is NOT a key the open source recognises: the loader parses each config layer
  into a lenient `toml::Value` with no top-level `deny_unknown_fields`, so this unknown key is parsed and
  ignored — its intended "disable upload" behaviour is **not implemented in the source**, and whether the
  *shipped binary* honours it is unverified. The helper still writes it as an unverified belt-and-suspenders
  but **does NOT rely on it as a control**; the actual upload defence is `env -i` + the empty synthetic
  `HOME` + the empty non-git CWD. Do not read `disable_codebase_upload` as a security guarantee (see §5).)
- **The global-rule scans are still on by default (residual #1).** `VendorCompat::default()` sets
  every `[compat.*]` cell `true` (a repo test asserts all 18 resolve true; the docs say the same), so
  Grok still reads your `~/.claude` / `~/.cursor` config from `$HOME` into the model turn unless
  disabled. Independently, grok's own `~/.grok/AGENTS.md` / skills / hooks / MCP load from `$GROK_HOME`
  (`agents_md.rs` always scans `grok_home()`). Both are closed by the helper's empty `HOME` + clean
  temp `GROK_HOME`.
- **Auth has an out-of-band override; managed policy does not.** Credential precedence is `GROK_AUTH`
  (inline JSON) > `GROK_AUTH_PATH` > `$GROK_HOME/auth.json` (`manager.rs:280-298`), and
  `AuthManager`'s read / write / refresh / lock all use the resolved path (`manager.rs:134`) — so
  pointing `GROK_AUTH_PATH` at your real `auth.json` lets grok read and refresh it in place while
  `GROK_HOME` stays a clean temp: the basis of the v3.0.0 helper (real login, temp home, no token
  copy). BUT several managed-policy readers (`managed_config.rs:89,103,831`, `config/reloader.rs:277`,
  `agent/app.rs:1405`) read `auth.json` **directly from `GROK_HOME`**, bypassing `GROK_AUTH_PATH`;
  under a temp `GROK_HOME` they find no auth, so any team / enterprise **managed policy tied to the
  account is not carried** into the relay. The wrapper cannot detect account type (reading auth
  content is out of scope), so it supports **personal / consumer** auth only — see §5.

**Residual #2 — the shipped binary can't be verified against the source.** There are no GitHub
releases, tags, signatures, or reproducible-build tooling in the repo; the official installer pulls
from a *different* (private) repo, and the auto-updater `exec()`s the downloaded binary after only a
`--version` smoke test; a literal `cargo build` reports a version string matching no shipped release;
the published tree is "synced periodically from a monorepo" and already advanced past `c68e39f` via
unsigned bot commits. So "the open source is clean" does **not** prove "the binary you run is clean."
This is a general caveat for **any** closed-binary relay target (Codex and agy included), not unique
to Grok — but it is why the helper keeps cheap belt-and-suspenders rather than trusting the binary.

Pre-open-source wire-tests (2026-07-13/14, grok 0.2.99 / 0.2.101) are consistent with all of the
above: the bundle upload was already server-*off* via a remote flag (not locally controllable then),
the `~/.grok/AGENTS.md` + `~/.claude` global-rule leak reproduced on every call and was removed by a
clean `GROK_HOME` + synthetic `HOME`, and `--deny '*'` refused a forced tool call. The open-sourced
code now explains each of those observations.

---

## 5. What headless-relay does about it (v3.0.0)

Every Grok call goes through one of two small helper functions (`grok_relay` for text, `grok_media`
for image/video) defined in SKILL.md. v3.0.0 keeps Grok isolated with layered controls, and — unlike
the v2.0.0 design built when Channel B was live — no longer copies your token into a throwaway home
(no copy, no sync-back, no lock): it reaches your real login through `GROK_AUTH_PATH` instead. Each
helper is a subshell (`name() ( … )`) with `set +eux` (no inherited errexit/nounset, and xtrace off so
a key can't be traced onto stderr) and cleanup `trap`s on EXIT / INT / TERM / HUP.

- **Hermetic child environment (`env -i` allowlist)** — the primary control. grok is launched with
  `env -i` and an explicit allowlist: only `PATH` (minimal `/usr/bin:/bin:/usr/sbin:/sbin`), `HOME`,
  `GROK_HOME`, `TMPDIR`, `TERM`, the three telemetry-off master switches, and exactly ONE auth var
  reach the child. Everything else in your shell is dropped before grok runs — your unrelated secrets
  AND grok's own behaviour-changing overrides alike: endpoint/gateway/proxy redirects
  (`XAI_API_BASE_URL`, `GROK_XAI_API_BASE_URL`, `GROK_GATEWAY_URL`, `GROK_CLI_CHAT_PROXY_BASE_URL`),
  the auth-provider **command** `GROK_AUTH_PROVIDER_COMMAND` (grok would otherwise *execute* it during
  refresh — `trace_classifier/mod.rs:2459`, `auth/config.rs:67`), `GROK_LOG_FILE`,
  `GROK_MANAGED_CONFIG*`, `GROK_AGENT_ENV*`, and the `GROK_<VENDOR>_*_ENABLED` compat toggles. Being an
  allowlist (not a blocklist), it drops future/unknown `GROK_*` knobs by default — the source reads
  ~150 of them, too many to blocklist safely. This single control subsumes what the earlier design
  attempted with a hand-maintained `env -u` list (which stripped only ~5 vars and missed the
  endpoint/provider-command class entirely).
- **Empty synthetic `HOME`** — blocks the Claude/Cursor/Codex compat scan. The compat scanners resolve
  `~/.claude` / `~/.cursor` / `~/.codex` from `$HOME`, so running grok with `HOME` set to an empty temp
  means there is nothing to scan or send. Verify (empty `HOME` + empty temp `GROK_HOME`, auth via
  `GROK_AUTH_PATH`): `HOME="$(mktemp -d)" GROK_HOME="$(mktemp -d)" GROK_AUTH_PATH=~/.grok/auth.json
  grok inspect` should report Project Instructions / MCP / Hooks all `0`.
- **Clean temporary `GROK_HOME`** — blocks grok's OWN globals. grok's native `~/.grok/AGENTS.md` /
  skills / hooks / MCP load from `$GROK_HOME` (`agents_md.rs` always scans `grok_home()`), so pointing
  `GROK_HOME` at an empty temp — not your real `~/.grok` — stops them loading. This is the improvement
  over the earlier design, which used the real `~/.grok` and therefore still loaded `~/.grok/AGENTS.md`.
  The helper writes a minimal `config.toml` into that temp pinning `[features] telemetry = false`,
  `[telemetry] trace_upload = false`, every `[compat.claude]` / `[compat.cursor]` / `[compat.codex]`
  cell `false` (all three vendors — `CompatConfigToml` in `xai-grok-tools/types/compat.rs`), and
  `[folder_trust] enabled = false` (so a headless `-p` run in the fresh dir is not gated). Those are
  all source-recognised keys. It ALSO writes `[harness] disable_codebase_upload = true`, which is NOT
  in the audited source: the config loader parses each layer into a lenient `toml::Value`
  (`loader.rs`), so an unknown key is accepted-then-ignored (`serde_ignored`) — on this source it does
  nothing and, crucially, cannot void the other keys (there is no top-level `deny_unknown_fields`). It
  is written only as an unverified belt-and-suspenders (NOT relied upon as a control); the real codebase-upload defence is the empty
  non-git CWD (below), not this key. Because grok's precedence is `env > config` (`flags.rs`;
  `TelemetryConfig::apply_env_overrides` reads `GROK_TELEMETRY_TRACE_UPLOAD`), a `config.toml` pin
  alone is not authoritative — but under the hermetic `env -i` there are no inherited
  telemetry/upload/endpoint vars left to outrank it, and the helper additionally forces
  `GROK_TELEMETRY_ENABLED` / `GROK_TELEMETRY_TRACE_UPLOAD` / `GROK_EXTERNAL_OTEL` off explicitly. (A
  managed *requirement* pin still outranks env — the documented team/enterprise out-of-scope case.)
- **Auth out-of-band; the wrapper never touches your credential store.** Subscription login →
  `GROK_AUTH_PATH` points at your REAL `auth.json`, resolved with grok's own precedence
  (`GROK_AUTH_PATH` → `${GROK_HOME:-$HOME/.grok}/auth.json`; `auth/manager.rs:296` + `paths.rs`
  `grok_home()`) and absolutised before any `cd`; grok reads and refreshes it in place, and the wrapper
  never reads, parses, copies, hashes, or syncs it. API key → `XAI_API_KEY` (or legacy
  `GROK_CODE_XAI_API_KEY`); no auth file is touched. The two branches are mutually clean by
  construction: under `env -i` the subscription branch passes ONLY `GROK_AUTH_PATH` (so the
  higher-precedence inline `GROK_AUTH`, plus `XAI_API_KEY` / `XAI_ROOT` / `XAI_USER`, are simply
  absent), and the API-key branch passes ONLY `XAI_API_KEY` (so `GROK_AUTH_PATH` / `GROK_AUTH` /
  `GROK_DISABLE_API_KEY_AUTH` are absent). Missing or unreadable subscription auth fails closed
  (nonzero, no call). `set +eux` disables xtrace in the subshell, so a `set -x` caller cannot trace the
  key onto stderr.
- **Empty non-git working dir (verified outside any git tree) + tool denial** — belt-and-suspenders
  against the unverifiable binary. The working dir is its own clean temp, separate from `HOME` and
  `GROK_HOME`, and the helper does **not** trust `TMPDIR`: it resolves the dir's **physical** path
  (`pwd -P`, so a symlinked `TMPDIR` is followed to its real target) and walks its ancestors for a
  `.git`, aborting the call if the working dir turns out to be inside a git worktree (so a `TMPDIR`
  pointed — directly or through a symlink — into a repo can never cause grok to run in your tree). `grok_relay` passes `--deny '*'`
  (binary-observed on 0.2.99 / 0.2.101 to refuse a forced tool call), so even a drifted binary has no
  tools to read a repo and no repo in the working dir to bundle. `grok_media` swaps that for a
  media-only `--tools image_gen,image_edit,image_to_video,reference_to_video` allow-list plus
  `--disallowed-tools search_tool,use_tool` to strip the always-on MCP meta-tools (binary-observed:
  `image_gen` still runs). `--disable-web-search` and a best-effort `--sandbox strict` are kept on both.
- **Media published atomically, never written in place.** `grok_media` never runs grok in your output
  dir. grok writes media under the temp `GROK_HOME` session dir (`paths.rs` `sessions_cwd_dir` =
  `grok_home()/sessions/…`); the helper then publishes only THIS call's artifacts by copying each into
  a temp in the output dir and **hard-linking** it into place — the ONE atomic, no-clobber, no-follow
  publish primitive (`ln` fails on an existing name or symlink). If the output-dir filesystem has **no
  hard-link support** the helper **FAILS CLOSED**: there is NO `mv` fallback and NO reserve-then-fill
  (an O_EXCL reserve followed by a reopen-by-path `cat >` is not atomic — a swapped symlink between the
  reserve and the fill would be followed — so it is rejected), and a name that cannot be atomically
  claimed is never published. It ALSO fails closed **before** publishing if any artifact name contains a
  newline (detected via a NUL-delimited `find`), and refuses any file not physically inside the sandbox —
  so an artifact named with an embedded newline cannot smuggle an unrelated (e.g. caller-CWD) file into
  your output dir. It is race-safe for concurrent cooperative calls (each collision picks the next free
  name). On any failure — publish error, nonzero grok exit, timeout, signal, newline name, or zero
  artifacts — it rolls back and returns nonzero, removing ONLY this call's own files (completed +
  in-flight) and **never removing the output directory** (a rolled-back call that created the dir leaves
  it empty rather than risk a reverse-timing `rmdir`/`rm -rf` that removes a dir a concurrent call is
  about to publish into). **One local-only limitation:** if a signal (INT/TERM/HUP) lands in the
  micro-window after `mktemp` creates the `.grokpub.XXXXXX` temp but before the shell assigns it to
  `$curtmp`, rollback does not yet know its name, so that one hidden temp can remain in your output dir.
  It is a *hidden copy of this call's own generated media in your own chosen output directory* — it is
  **never sent to xAI or any external system, carries no repo/source data, and is not user-data loss**;
  it is the "perfect pure-shell multi-file transaction" case that is out of scope. Delete it with
  `rm -f OUTPUT-DIR/.grokpub.*` if you hit it.
- **Control state is kept out of the paths grok is given.** The relay answer file and the media
  manifest live in a **separate control base** (`grok-ctl.*`) that grok is never handed a path to —
  distinct from the sandbox (`grok-sbx.*`, whose home / grok-home / cwd / tmp grok *is* given), so grok
  cannot derive it by walking up from its own dirs. Both are used only after grok exits, gated by a
  regular-file / no-symlink check (the answer) and an `rm`-of-any-pre-existing (the manifest). This
  neutralises a symlink/FIFO **planted ahead of the operation** and defeats a passive or accidental
  collision — it **raises the bar; it is not a jail**. It does NOT stop a same-UID binary that enumerates
  the temp namespace, locates the control base, and wins the narrow **check/open race** (between the
  manifest `rm -f` and the `find >` that re-creates it, or between the answer's `[ -f ] && [ ! -L ]`
  check and the following `cat`): such a process could still redirect the read, truncate a file, or hang
  the wrapper on a FIFO. Pure POSIX shell has no `O_NOFOLLOW` / atomic open-only-if-regular primitive to
  close that window; doing so requires an OS sandbox (see "Threat-model scope" below).
- **Auto-update, leader mode, and workspace data-collection are pinned or dropped.** The temp config
  sets `[cli] auto_update = false` (source `xai-grok-update/auto_update.rs`: `Some(false)` skips the
  self-update `exec()` for this call) and `[cli] use_leader = false` (no leader/cluster process;
  `GROK_LEADER_SOCKET` is also dropped by `env -i`). Workspace data-collection is off:
  `GROK_WORKSPACE_DATA_COLLECTION_DISABLED` (source `workspace/handle.rs`) is *unset ⇒ disabled* by
  default, `env -i` keeps a caller's `=false` (enable) out, and the helper additionally passes `=true`.
- **Real watchdog timeout + descendant cleanup.** Each call runs grok under a real watchdog
  (`GROK_RELAY_TIMEOUT`, default 300s; `GROK_MEDIA_TIMEOUT`, default 600s, both overridable). On
  timeout, or on `INT` / `TERM` / `HUP` delivered to the helper's own subshell (as a foreground
  `Ctrl-C` does via the terminal's process group), the helper reaps grok's process tree — child +
  grandchildren, via a `ps` parent-walk while grok is still alive — and removes its temp base.
  This reaping runs ONLY while grok is still alive (the signal/timeout paths). On **sh/bash** grok is
  additionally launched as its OWN process-group leader (`set -m`), and the helper negative-kills that
  group (`kill -TERM -<pgid>`) as belt-and-suspenders during those same still-alive paths — but **only
  after verifying** the child really is the group leader (`pgid == pid`). A shell where that is not true
  (dash keeps the child in the script's group; zsh rejects `set -m`; macOS ships no `setsid`) keeps pgok
  off and issues **no** process-group signal. After grok's OWN normal/nonzero exit the helper does **not**
  reap detached descendants: the post-wait negative kill was removed because grok is already dead and its
  pgid could be reused. grok's PID is cleared the instant it is waited on, so no later signal (e.g. during
  media publish) runs `_tree` on a stale/reused PID. **Honest limit:** a descendant that outlives grok's
  normal/nonzero exit (or a process that `setsid`s into a new session) is NOT reaped on any shell; that
  residual case needs an OS sandbox. Separately, if you *background* a relay (`grok_relay …
  &`) and kill it via `$!`, the shell's intermediate wrapper subshell absorbs the signal instead of the
  trap, so that one path falls back to the watchdog timeout. (macOS ships no GNU `timeout`; the watchdog
  is helper-owned, not a new dependency.)
- **Scope: personal / consumer auth only.** Supported: consumer subscription OAuth and `XAI_API_KEY`
  / legacy `GROK_CODE_XAI_API_KEY`. NOT supported / unverified: team or enterprise OAuth with
  client-side managed-policy parity — the managed-policy readers (`managed_config.rs`,
  `config/reloader.rs`, `agent/app.rs`) read `auth.json` directly from `GROK_HOME`, bypassing
  `GROK_AUTH_PATH`, so under the temp `GROK_HOME` they see no auth and any account-tied managed policy
  is not carried into the relay. This is a narrow gap: it does NOT mean "enterprise API-key use is
  broken" or "server-side ZDR is lost" — those are untouched; only the *client-side managed-policy
  carry* under a temp `GROK_HOME` is unverified. The wrapper cannot detect account type (reading auth
  content is out of scope), so treat team/enterprise use as unsupported here.
- **Login/logout is out of scope.** The helper only uses a pre-existing session; it never runs `grok
  login` / `grok logout` and never persists credentials. grok's own first-party refresh may update the
  real `auth.json` in place during a relay call (expected — that is grok, not the wrapper).
- **Still a cloud model, not "local".** The helper closes the global-rule leaks and denies tools. It
  does **not** stop the prompt you pass or Grok's reasoning from reaching xAI. The Grok lane is never
  described as "read-only", "local", or "no network".
- **No repo-context Grok.** "Read the repo", "review the diff", or any task that needs repository
  access goes to Codex, Gemini, GLM, or Claude, which read files in place. Grok relays only the
  prompt you give it.

**Threat-model scope — what the wrapper binds, and what only an OS sandbox could.** These layers are
strongest against grok's *documented default behavior* and against inherited environment; be precise
about the limits under a *fully malicious* binary (the unverifiable-binary case):
- **`env -i` is the one airtight layer.** A secret, endpoint redirect, or `GROK_AUTH_PROVIDER_COMMAND`
  that is never passed cannot be recovered by the child — this holds even against a malicious binary.
- **The empty `HOME` / clean `GROK_HOME` close grok's config *scans*, not the whole filesystem.** A
  malicious binary could still reach your real home via the passwd database (`getpwuid`) or any
  absolute path, or `cd` into a real repo — pure POSIX shell cannot sandbox the filesystem against a
  same-UID process. Binding that needs an OS sandbox (macOS `sandbox-exec`, Linux namespaces / `bwrap`),
  out of scope here; the empty non-git CWD + `--deny '*'` / `--tools` are defense-in-depth, not a jail.
- **Descendant cleanup runs only while grok is alive.** On the signal/timeout paths a `ps` parent-walk
  reaps grok's tree on every shell, plus (sh/bash) a process-group kill issued ONLY after verifying grok
  is its group's leader (`pgid == pid`). After grok's OWN normal/nonzero exit the helper does NOT reap a
  detached descendant — the post-wait negative kill was removed (grok is already dead and its pgid could
  be reused). So a descendant that outlives grok's normal/nonzero exit, or one that `setsid`s into a new
  session, is not reaped on any shell. Those need an OS sandbox (bounded: such a binary could egress
  directly regardless).
- **The API-key branch puts `XAI_API_KEY` in grok's environment** (grok's only key interface), so it is
  visible to a same-UID process via grok's `environ` / the `env` argv for grok's lifetime; the
  subscription branch passes a file *path* (`GROK_AUTH_PATH`), not the secret, and is clean. `set +eux`
  keeps the key off stderr in both.
- **The watchdog uses no grok-writable coordination file** — a malicious grok can derive the wrapper's
  temp base from its own dirs, so liveness is grok's own (`kill -0`) and the timeout verdict is the
  watchdog's exit code, neither of which grok can spoof.

**Verification status — three distinct evidence layers, never conflated.** (1) **Source-audited**: the
open-source snapshot `c68e39f` (env precedence, `grok_home()`, auth precedence, compat defaults across
all three vendors, telemetry schema, and the lenient `toml::Value` config parse — all cited above).
(2) **Installed-binary-observed**: grok 0.2.101 / build `5bc4b5df` (e.g. `--deny '*'` refuses a forced
tool call; `image_gen` runs under the media allow-list; the `disable_codebase_upload` string exists) —
NOT proven to be the same commit as the source. (3) **Fake-runtime-tested**:
`scripts/test-grok-runtime.sh` exercises the WRAPPER's isolation, lifecycle, and publish against a
fake `grok` on sh/bash/zsh (no real grok, no network), 60 scenarios × 3 shells. The pass policy: **every
non-skipped cell must PASS and all 26/26 mutations must be caught**; the only permitted skips are
documented ones — (a) the two normal/nonzero descendant-reaping scenarios (that cleanup is intentionally
NOT provided on any shell; only signal/timeout reaping, while grok is alive, is guaranteed), and (b) a
publish-time signal scenario ONLY when it observes the local `.grokpub.*` temp window described below.
The mutation set covers a watchdog-spoof attempt, control-base symlink/FIFO precreation at the answer and
manifest paths, a publish-dest swap, publish-time INT/TERM/HUP delivered to the helper, **no-hardlink
fail-closed** (no unsafe fallback), **newline-name fail-closed**, a **newline OUTPUT-DIR refused before
any write**, rollback ownership preserving a pre-existing collided file, concurrent-call rollback
isolation, reverse-timing directory safety, and a **behavioral dash test that a negative process-group
kill is only issued after `pgid == pid` verification** (no unverified negative kill), plus a
symlinked-`TMPDIR`-into-repo attempt. What remains **unverifiable** is the shipped binary's actual
runtime behaviour end-to-end, and whether xAI trains on data it received. So: **this is source-verified
and fake-runtime-verified; the shipped binary is end-to-end unverified.** Do not read it as "fully safe".
Set **`XAI_API_KEY`** to use metered API auth and skip the subscription login entirely; then the real
user auth file is neither passed to nor read by the helper.

---

## 6. If you already used Grok Build in a real repository (with an earlier version)

Treat any repository you ran an earlier Grok Build inside — before the fix — as potentially uploaded
in full, including its history and any tracked secrets. To check your own machine safely, on your
own data (do not paste raw logs anywhere, and do not send them to a model):

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
dedicated read-only audit that separates *staged* from *delivered* from *retained*, and never prints
secrets.

If a repository with real secrets was in scope, rotate what could have been exposed: API keys and
tokens (including any in a tracked `.env`), database credentials, SSH/private keys, cloud
credentials, and wallet/keystore/seed material. Then, on the account side, use the in-CLI `/privacy`
command (below), and request access/deletion of your data through https://x.ai/privacy-portal — xAI
also states it deleted previously-retained coding data on 2026-07-15, but a personal deletion request
is the way to confirm your own.

**This machine-level incident review is out of scope for the skill itself** — the skill only fixes
future behaviour. Run the review separately.

---

## 7. Optional hardening (defense-in-depth)

These reduce risk further; none of them is required by the helper (which already runs Grok under an
empty `HOME` + a clean temp `GROK_HOME` with tool use locked down). Labels separate what xAI documents from
what is community-reported; verify for your version.

- **`/privacy`** (official, in-CLI): toggles data retention and, per xAI, deletes previously synced
  data. Retention only, not transmission. The consumer OAuth-login CLI session is **not** ZDR; per
  xAI, ZDR applies to Team/Enterprise accounts and to API-key use of Grok Build.
- **`~/.grok/config.toml` kill-switches (for your own non-relay grok use).** `[telemetry]
  trace_upload = false` and `[features] telemetry = false` are **official** settings, verified honored
  on 0.2.99. Note the v3.0.0 relay runs under a clean temp `GROK_HOME`, so your `~/.grok/config.toml`
  does NOT apply to relay calls — but the helper's own minimal config already pins these (and the
  compat cells) off, so relay calls are covered regardless. Setting them in `~/.grok/config.toml`
  hardens grok when YOU run it directly. Edit this yourself; the skill never writes your config.
- **Disable the compatibility scan at the source.** If you would rather grok never read your
  `~/.claude` / `~/.cursor` config even outside the relay, set the `[compat.claude]` and
  `[compat.cursor]` cells to `false` in `~/.grok/config.toml` (or the `GROK_CLAUDE_*_ENABLED=0`
  env vars). The relay does not require this — its empty `HOME` + clean temp `GROK_HOME` already block
  the scan — and editing your own config is a personal choice, so the skill never does it for you.
- **`[tools] respect_gitignore = true`** (official) limits search/read tools only.
- **Write your own invocation?** Mirror the helper: capture the real auth path first
  (`ap="${GROK_AUTH_PATH:-${GROK_HOME:-$HOME/.grok}/auth.json}"`), make three fresh temp dirs (home,
  grok-home, and an empty non-git cwd), then run grok under a HERMETIC allowlist rather than a
  blocklist — `( cd "$iso" && env -i PATH=/usr/bin:/bin HOME="$hm" GROK_HOME="$gkh" TMPDIR="$tmp"
  TERM=dumb GROK_AUTH_PATH="$ap" grok … --deny '*' )` (or `XAI_API_KEY=…` in place of
  `GROK_AUTH_PATH`). `env -i` drops every other variable — your secrets and grok's
  endpoint/provider-command/log/compat overrides alike — so you never have to enumerate them. No token
  copying is needed; grok refreshes the real `auth.json` in place via the path.
- **True zero egress:** if code must never leave the machine, do not use a cloud model at all — use a
  fully local model (e.g. via Ollama / LM Studio / MLX, connectable through
  `references/custom-targets.md`).

---

## Reporting

Security issues with this skill (not with Grok Build itself): open an issue at
https://github.com/dorukardahan/headless-relay . Issues with the Grok Build CLI go to xAI via the
in-CLI `/feedback` command or its bug-bounty program (hackerone.com/x).
