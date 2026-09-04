# The engineer workflow: issue → pull request → adversarial review

This walkthrough exercises the community catalog's
[`engineer` workflow](https://github.com/ai-outfitter/community-profiles/blob/main/workflows/engineer/workflow.yaml)
on the seeded bug
([docs/issues/0001-split-loses-cents.md](../issues/0001-split-loses-cents.md)):
research → implement → draft pull request → independent
[adversarial review](https://github.com/ai-outfitter/community-profiles/blob/main/workflows/adversarial-review/workflow.yaml)
→ merge as the human. Run it in **your generated copy** — see the
[README](../../README.md#reset-and-go-again) for reset instructions.

Every step lands on the forge, so the record outlives the session: the bug
becomes an issue, the fix becomes a pull request that references it, the
review is a formal PR review, and a human merges.

## 0. Sync the catalog

```sh
outfitter sync
outfitter list
```

`outfitter sync` fetches the community catalog pinned in
[.agents/settings.yml](../../.agents/settings.yml). `outfitter list` should
show `engineer`, `git-forge-delegator`, and the rest of the catalog; the
engineer's loadout includes the `code-review` skill.

## 1. File the issue (delegate)

Template-generated copies start without issues. Either file one yourself:

```sh
gh issue create \
  --title "split loses cents on uneven amounts" \
  --body-file docs/issues/0001-split-loses-cents.md
```

or hand the raw bug report to the delegator agent and let it write the scoped
issue:

```sh
outfitter run git-forge-delegator
```

and paste:

```text
Splitting $100 among 3 people prints a $99.99 total — run
`node bin/split.js 100 3` to reproduce. File one scoped issue on this
repository with acceptance criteria a reviewer can check mechanically.
```

Read the issue it files. Good acceptance criteria name the command that
proves the work and its expected output — a reviewer should be able to check
them without judgment calls.

## 2. Implement (engineer)

```sh
outfitter run
```

```text
Work issue #1 in this repository. Do not merge.
```

The catalog engineer carries the `scoped-issues` skill, so handed a raw bug
report instead of an issue number it files the scoped issue itself (the
README's guided run does exactly that, making step 1 optional).

The engineer owns implementation, verification, and review. Its loadout
already carries the draft-pull-request lifecycle: it fixes `src/split.js`,
adds the regression test the issue demands, verifies with `npm test`, pushes
a semantic branch (`fix/...`), opens the pull request **as a draft**, iterates
until CI is green, and only then marks it ready. Ready is the signal that
requests review. With no external reviewer configured in the playground, the
engineer starts its own adversarial review with cold-context subagents and
fixes any blocking findings. If it stops to report a scope conflict instead
of pushing, that is the agent working as designed — answer it and re-run.

Prefer a different harness? The same composed profile runs through any of
them:

```sh
outfitter run --harness pi
outfitter run --harness claude
outfitter run --harness codex
```

## 3. Inspect or repeat the adversarial review

The engineer's `code-review` skill delegates each review lens to a
**cold-context subagent** with no stake in the change passing, then merges the
findings into one formal review. The first pass happens automatically after
the pull request becomes ready. Inspect it with `gh pr view --web`. To repeat
the review against a new revision, start a fresh engineer session:

```sh
outfitter run engineer
```

```text
Review pull request #2 against issue #1's acceptance criteria.
```

Expect a formal review, not chat: one inline comment per finding anchored to
the file and line, a body that states the verdict and ranks the findings,
`REQUEST_CHANGES` when any finding blocks. A clean verdict arrives as a
`COMMENT` review — approval is an explicit organization grant the playground
does not give, so approving and merging stay with you. A passing CI job is
not evidence the change is correct; the reviewer reads what the check
actually asserts, and so should you.

Try to break the fix: ask the reviewer about `split(0.01, 3)` or
`split(100, 7)`. If the engineer only special-cased the example from the
issue, the review should catch it.

## 4. Rework, then merge (human)

If the review requested changes and the original session did not already fix
them, send the findings back through the engineer:

```sh
outfitter run engineer
```

```text
Address the review findings on pull request #2, push, and answer each
finding with what changed or why not.
```

then re-run step 3 — a new revision gets a fresh cold-context pass.

When a review pass comes back with no blocking findings, verify the
acceptance criteria yourself and merge:

```sh
node bin/split.js 100 3   # total must read $100.00
npm test
gh pr merge 2 --squash
```

You just ran the loop this playground exists to teach: scoped issue →
implementation on a branch → draft PR gated on CI → cold-context adversarial
review → rework → human merge. Now
[reset your copy](../../README.md#reset-and-go-again) and run it again with a
different harness, a different prompt, or with yourself playing one of the
lanes.

## Variations

- **You implement, the agent reviews.** Fix the bug by hand, open the PR,
  and run step 3 against your own diff.
- **The agent implements, you review.** Stop after step 2 and hold the PR to
  the issue's acceptance criteria yourself, one inline comment per finding.
- **Delegated end-to-end.** The catalog's
  [`software-factory` workflow](https://github.com/ai-outfitter/community-profiles/blob/main/workflows/software-factory/workflow.yaml)
  runs the same loop with a delegated implementer instead of your
  workstation session — typed issue in, CI-gated draft PR and independent
  review out. Community-profiles v1.7.0 names a `repo-contributor`
  composition for that lane; bump the pin in
  [.agents/settings.yml](../../.agents/settings.yml) when it releases.
