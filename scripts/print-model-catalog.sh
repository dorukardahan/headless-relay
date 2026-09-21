#!/bin/sh
# print-model-catalog.sh — list model ids THIS machine's CLIs currently serve.
#
# WHY. headless-relay example pins go stale every vendor launch. Do not copy ids
# out of README/SKILL as if they were a live menu. This script asks each
# installed CLI for its catalog and prints a dated, machine-local snapshot.
#
# WHAT IT IS NOT. It does not start a model turn, does not write credentials,
# does not refresh vendor blogs, and does not update SKILL.md. Missing binaries
# are skipped. A lane that is installed but whose catalog command fails is
# reported as skipped, not as an empty menu.
#
# Codex: use `codex debug models` (JSON). Never `codex models` — on the 0.144
# series that is not a catalog subcommand and starts an interactive session.
#
# No dependencies beyond POSIX sh + python3 (for Codex JSON). Run from anywhere.

set -eu

echo "# headless-relay local model catalog"
echo
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(uname -n 2>/dev/null || echo unknown)"
echo "This list is what THIS machine sees. It is not a published product menu."
echo "Do not commit it as the skill's source of truth."
echo

have() { command -v "$1" >/dev/null 2>&1; }

# --- Codex ---
echo "## Codex (\`codex debug models\`)"
if have codex; then
  echo "binary: $(command -v codex)"
  echo "version: $(codex --version 2>/dev/null | head -n 1 || echo unknown)"
  if python3 - <<'PY'
import json, subprocess, sys
try:
    p = subprocess.run(
        ["codex", "debug", "models"],
        capture_output=True, text=True, timeout=20,
    )
except Exception as e:
    print("skip: %s" % type(e).__name__)
    sys.exit(0)
if p.returncode != 0:
    print("skip: catalog command failed")
    sys.exit(0)
try:
    data = json.loads(p.stdout or "")
except json.JSONDecodeError:
    print("skip: catalog was not JSON")
    sys.exit(0)
ids = []
SKIP = {"priority", "default", "bundled", "current", "latest"}
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ("id", "slug") and isinstance(v, str) and v and v not in ids:
                if v not in SKIP and ("-" in v or v.startswith("gpt") or v.startswith("codex")):
                    ids.append(v)
            walk(v)
    elif isinstance(o, list):
        for i in o:
            walk(i)
walk(data)
if not ids:
    print("skip: no model ids in catalog")
    sys.exit(0)
for i in ids:
    print("- %s" % i)
PY
  then
    :
  else
    echo "skip: python3 catalog parse failed"
  fi
  echo
  echo "Do **not** run \`codex models\`. On 0.144 that starts a session."
else
  echo "skip: \`codex\` not on PATH"
fi
echo

# --- Antigravity / Gemini ---
echo "## Gemini (\`agy models\`)"
if have agy; then
  echo "binary: $(command -v agy)"
  if _out=$(agy models 2>/dev/null); then
    if [ -n "$_out" ]; then
      printf '%s\n' "$_out"
    else
      echo "skip: empty catalog"
    fi
  else
    echo "skip: \`agy models\` failed (not logged in?)"
  fi
else
  echo "skip: \`agy\` not on PATH"
fi
echo

# --- Grok ---
echo "## Grok (\`grok models\`)"
if have grok; then
  echo "binary: $(command -v grok)"
  if _out=$(grok models 2>/dev/null); then
    if [ -n "$_out" ]; then
      printf '%s\n' "$_out"
    else
      echo "skip: empty catalog"
    fi
  else
    echo "skip: \`grok models\` failed"
  fi
else
  echo "skip: \`grok\` not on PATH"
fi
echo

# --- Claude (help only; do not start a session) ---
echo "## Claude (aliases from \`claude --help\`; no session)"
if have claude; then
  echo "binary: $(command -v claude)"
  echo "Use \`claude --model <alias>\` with an alias from \`claude --help\` (fable / opus / sonnet) or a full id."
  echo "This script does not start \`claude -p\` and does not list billed models."
else
  echo "skip: \`claude\` not on PATH"
fi
echo

# --- OpenCode / ZCode ---
echo "## GLM"
if have opencode; then
  echo "OpenCode binary: $(command -v opencode)"
  echo "OpenCode has no safe catalog subcommand in this skill's contract. Current Coding Plan flagship pin is \`zai-coding-plan/glm-5.3\` (see SKILL.md). Confirm with the user's OpenCode auth, not a guessed id."
else
  echo "OpenCode: skip (\`opencode\` not on PATH)"
fi
if have zcode; then
  echo "ZCode binary: $(command -v zcode)"
  echo "ZCode recipes pin \`zai/glm-5.3\`. GLM-5.2 is previous generation."
else
  echo "ZCode: skip (\`zcode\` not on PATH)"
fi
echo
echo "Done. Copy an id from this snapshot into a one-shot command; do not paste it back into the skill as a new source of truth."
