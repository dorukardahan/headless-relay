# Reprompt before you relay

The relay carries whatever prompt you give it. Quality-in determines quality-out:
a vague prompt relayed to Codex, GLM, Grok, or Gemini comes back as a vague answer
from a different model. If the orchestrating agent has a prompt-engineering skill
installed, run it BEFORE relaying a nontrivial task.

## Known integration: RePrompter

[RePrompter](https://github.com/AytuncYildizli/reprompter) (v12.16.0+) integrates
with this skill from the other side. Its Single and Reverse lanes end with a
post-output delivery step: when headless-relay is installed in the same session,
RePrompter offers once to deliver the finished prompt through this skill, then
hands off three things:

1. the finished prompt text,
2. the target model (Codex / GLM / Grok / Gemini — never Claude, per Check 1),
3. output expectations (for example "JSON only").

Everything downstream stays owned by headless-relay: preflight availability, the
provider-terms compliance gate, CLI flags, and output parsing. RePrompter's docs
deliberately contain no CLI mechanics, so the two skills cannot drift apart.
See the "Deliver via headless-relay (post-output step)" section of RePrompter's
SKILL.md.

## When NOT to reprompt first

- Short factual asks ("what does this error mean") — relay directly.
- Consensus runs where the SAME prompt must go to several models — reprompt once,
  then fan out, honoring this skill's parallel rules (Gemini lane stays sequential).
- The user already supplied a structured, complete prompt.

Skill by @dorukardahan. Integration contributed by @AytuncYildizli.
