# Demo the engineer flow

One script, no container. It runs Outfitter under a **persistent, isolated
HOME** at `/tmp/outfitter-playground-home` — your harness logins are copied
in from the host every run (originals untouched), onboarding state and the
synced catalog persist between runs, and your real `~` is never touched.
It runs in this checkout, whose origin must be **your own playground
generated from the template** (the script verifies the lineage and refuses
the org repo itself). Each run resets the checkout to the upstream state —
uncommitted changes and extra branches are discarded — so the seeded bug is
back and issues and PRs land on your copy, never upstream.

```sh
e2e/demo.sh            # engineer session, claude harness
e2e/demo.sh pi         # same flow under pi
e2e/demo.sh codex      # same flow under codex
```

You land in an interactive engineer session with the demo script printed:
paste the prompt, watch it file the issue and work it into a CI-gated,
ready-for-review PR. With no external reviewer configured, the engineer then
runs the adversarial review itself using cold-context subagents and fixes any
blocking findings. When the session exits, you stay in a shell inside the
demo environment; run `gh pr view --web` to inspect the review before you
merge. To repeat the review in a fresh session, run
`outfitter run engineer --harness <h>` and ask it to review the open pull
request against the linked issue's acceptance criteria.

Live sessions validate GitHub CLI authentication before any arena reset, then
pass the resulting token to `gh` and the GitHub MCP. `ANTHROPIC_API_KEY` /
`OPENAI_API_KEY` are passed through when set (pi needs one of them).

The Pi path makes one extension-free `OUTFITTER_AUTH_OK` model call before it
resets the arena or installs profile extensions. This both verifies the selected
provider and refreshes OAuth state inside the isolated demo HOME. If it fails,
authenticate with Pi normally and rerun the demo; your checkout is left intact.

## Other commands

```sh
e2e/demo.sh check      # free, no model calls: bug present, suite green,
                       # sync + validate --strict with zero warnings,
                       # agents resolved from community-profiles
e2e/demo.sh reset      # wipe the demo HOME for a from-scratch start
```

Use `e2e/demo.sh check` as the demo preflight. It does not require or inspect a
GitHub credential; only the public catalog sync uses the network. It runs sync
and strict validation inside the isolated demo HOME; a plain `outfitter
validate --strict` also composes user-level settings from the host and can
report unrelated personal configuration.

`PLAYGROUND_HOME=<dir>` overrides the demo HOME location.
