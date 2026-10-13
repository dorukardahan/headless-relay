# Changelog

## [Unreleased]

### Fixed

- Kimi relay on macOS: every run ended with `kimi-relay: refusing: [Errno 3] No such process`, which also hid Kimi's real exit status. macOS answers `getpgid` with ESRCH for an exited-but-unreaped leader and `killpg` with EPERM when that zombie is the only member left; the old code treated both as ownership loss. The relay now proves ownership with `waitid(P_PID, WNOWAIT)`, which only succeeds for its own unreaped child, and accepts EPERM only when `ps` shows no live member in the group. A live member it cannot signal still refuses.

### Documentation and safety

- Kimi preflight: the archived Python `kimi-cli` prints `kimi, version 1.x` and fails this lane with `Output format is only supported for print UI`; the Kimi Code CLI prints a bare version.
- Kimi's free Adagio plan has no Kimi Code access, so native OAuth needs a paid membership; the metered Open Platform API key is the other login.
- Kimi `auto` permissions are the "Never Ask" mode: sensitive-file access and dangerous commands are approved without asking. Only static deny rules still apply.

### Verification

- `scripts/test-kimi-runtime.py`: 22 tests pass on macOS 27 (Darwin), including 4 new tests that emulate the macOS answers on any POSIX host. Before the fix, 26 subtests failed on the same machine, and the 4 new tests fail against the old relay. The other regression scripts and the Grok runtime matrix (228 passed, 0 failed) still pass. No real Kimi inference was run.

## [3.2.0] - 2026-10-13

This minor release includes the accumulated changes since v3.1.1.

### Added

- Native Kimi K3 lane using the first-party Kimi CLI and its own OAuth login, separate from GLM/OpenCode credentials. The wrapper provides an external watchdog, process-group cleanup, physical non-git working-directory checks and an empty skills directory.
- Party / Council Mode instructions for consulting every safely available built-in and custom lane, including independent native subagents. The protocol records replies, failures and skips, preserves dissent, and distinguishes complete bookkeeping from useful success. This is a skill/protocol, not an executable council engine.
- Machine-local model catalog script with a process-group watchdog. It queries installed CLI catalogs rather than maintaining a published account-independent model menu.
- Video-understanding guidance: Gemini through Antigravity can use frames and speech transcription; the documented GLM-5.3-Flash API route uses frames only. The documented Grok route cannot read video. These are prior observations, not fresh inference verification for this release.

### Fixed

- Claude relays leave native model selection to Claude unless an explicit override is supplied. Full model identifiers and printable `[1m]` suffixes remain opaque single arguments; resume and error statuses are preserved.
- Kimi timeout, descendant cleanup, inherited signal handling, cancellation during temporary-directory cleanup, relative paths and PATH/interpreter resolution are guarded. File handoffs accept regular UTF-8 files up to 32 KiB, reject NUL and oversized input before invoking Kimi, and never silently truncate.
- Consensus examples preserve each lane's exit status rather than treating nonempty output as success.

### Documentation and safety

- Updated account-catalog gates and examples for GPT-6 Astra/Sol/Luna, GLM-5.3, Gemini 3.8 Flash and opt-in Grok 4.7. The Grok helper retains its 4.6 default; newer models require per-login catalog verification.
- Documented Claude Opus 5.5 CLI compatibility and served-model verification, separate OpenCode headless-CLI updates, and the ZCode 3.14.5 setup shim.
- Kimi is an explicitly opt-in agentic lane, not a sandbox: global instructions, MCP/hooks, inherited environment and native session/log retention remain active. Subscription handoffs must be direct user-triggered turns, not unattended cron or batch jobs.
- Payload-only Council requests skip lanes whose repository/tool access cannot be safely restricted; asking every model does not grant broader access.

### Verification and limitations

- Offline release gates passed: 356 shipped Claude argv cases and negative mutations; 11 Council documentation/record-rule tests; 18 synthetic Kimi runtime tests; Grok safety and model-pin documentation tripwires.
- The serial Grok synthetic runtime matrix passed 152 cells with zero failures, 82 documented skips and all 43 negative mutations caught. Missing zsh and platform/privilege prerequisites limit coverage; this is not a full three-shell pass.
- No fresh real-provider inference, auth-refresh or egress verification was performed for this release. The unchanged Grok helpers previously had an intermittent cancellation/publication test failure during concurrent testing; serial reruns passed, but its root cause remains undetermined. This release does not claim to fix that observation.

### Contributors

Thanks to [@AytuncYildizli](https://github.com/AytuncYildizli) for the native Kimi lane, Claude model-selection contribution and Party / Council Mode. Their original contribution commits and authorship are retained in the repository history.

[3.2.0]: https://github.com/dorukardahan/headless-relay/compare/v3.1.1...v3.2.0
