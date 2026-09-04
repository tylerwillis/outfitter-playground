# Playground

One pass through this repository teaches you how to use
[Outfitter](https://github.com/ai-outfitter/outfitter): you end with your
own copy of this repo whose committed [`.agents/`](.agents/settings.yml)
directory gave you a full agent roster from one pinned
[community catalog](https://github.com/ai-outfitter/community-profiles) — no
per-laptop setup — and you will have watched that roster run a real software
development lifecycle against a seeded bug: a scoped issue, an implementation
on a semantic branch, a CI-gated draft pull request, a cold-context
adversarial review, and a pull request left ready for you — the human — to
merge. Then you reset your copy and run it again, with a different harness,
prompt, or division of labor.

1. **Generate your playground** — a copy from this template, not a fork:
   forks need one-time UI clicks before Actions run and issues work;
   generated repos have both from the first commit (needs
   [Node.js](https://nodejs.org) 22.19+, [`gh`](https://cli.github.com/), and
   [`github-mcp-server`](https://github.com/github/github-mcp-server/releases/latest)
   on `PATH`; on macOS, install the server with
   `brew install github-mcp-server`):

   ```sh
   gh repo create outfitter-playground --template ai-outfitter/outfitter-playground --public --clone
   cd outfitter-playground
   git remote add upstream https://github.com/ai-outfitter/outfitter-playground.git
   ```

2. **Meet the bug:**

   ```sh
   node bin/split.js 100 3   # totals $99.99 — there's the seeded bug
   npm test                  # green: the suite misses the case
   ```

3. **Start Outfitter** — sync the pinned catalog, then launch. Pass
   `--harness claude` or `--harness codex` to run the same composed profile
   in a different harness, and on your first run in a harness type `/login`
   at its prompt to set up a model provider before pasting anything:

   ```sh
   npm install -g @ai-outfitter/outfitter
   outfitter sync
   export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"   # the agents' github MCP reads this
   outfitter run   # starts the engineer: .agents/settings.yml sets default_agent
   ```

4. **Paste this bug report** — nothing more; the process comes from the
   agent's loadout, not the prompt:

   ```text
   Splitting $100 among 3 people loses a cent — `node bin/split.js 100 3`
   totals $99.99. The shares should always sum to the amount. Do not merge.
   ```

5. **Watch the SDLC happen.** The engineer's loadout carries the lifecycle:
   its
   [`scoped-issues` skill](https://github.com/ai-outfitter/community-profiles/blob/main/skills/scoped-issues/SKILL.md)
   reproduces the report and files the scoped issue itself (acceptance
   criteria a reviewer can check mechanically), then it fixes `src/split.js`
   on a `fix/...` branch with a conventional commit, adds the regression
   test the issue demands, verifies with `npm test`, opens the pull request
   as a draft, waits for CI to go green, and marks it ready — then, per its
   `code-review` skill, **reviews its own PR adversarially**: it spawns
   cold-context subagents that judge only the diff, the criteria, and the
   checks, aggregates their JSON findings, posts one formal review through
   the github MCP, and fixes what blocks.
6. **Read the adversarial review.** The judgment comes from subagents with
   no stake in the change passing. Expect a formal PR review: one inline
   comment per finding, `REQUEST_CHANGES` if anything blocks, a `COMMENT`
   verdict when clean — never `APPROVE`, because approval is yours. To run
   a review pass by hand (or re-review a revision), start the engineer
   again:

   ```sh
   outfitter run
   ```

   ```text
   Review the open pull request against its linked issue's acceptance
   criteria.
   ```
7. **Merge the ready PR.** Verify the acceptance criteria yourself, then
   merge:

   ```sh
   node bin/split.js 100 3   # total must read $100.00
   npm test
   gh pr merge --squash
   ```

That loop — issue → implementation → adversarial review → human merge — is
the whole lesson. [docs/workflows/engineer.md](docs/workflows/engineer.md)
walks the same loop with more control at each step, including delegating the
issue-writing to `git-forge-delegator` and swapping yourself into either
lane.

## Reset and go again

Throw away the run and restore your copy to the upstream state:

```sh
git checkout main
git fetch upstream && git reset --hard upstream/main
git push --force origin main
git branch | grep -v ' main$' | xargs -r git branch -D   # local branches
gh pr list --state open --json number --jq '.[].number' \
  | xargs -rn1 gh pr close --delete-branch                # open PRs + branches
```

Closed issues and merged PRs stay in your copy's history — that is fine;
the next run starts from a fresh issue. (No `upstream` remote?
`git remote add upstream https://github.com/ai-outfitter/outfitter-playground.git`.)

## Take the workflow to a real project

The playground proves the loop; your `.agents/` tree is what makes the
method durable. Run `outfitter setup` from a real project to create project
or user configuration. To share the same agents and skills across a team,
create a personal or organization `.agents` repository in the
[Outfitter dashboard](https://ai-outfitter.com/dashboard/), then follow
[Share one catalog](https://ai-outfitter.com/docs/outfitter/runbooks/share-one-catalog/)
to pin, sync, and verify it.

## The exhibit

`split` is a zero-dependency Node CLI that splits a bill among people. Its
bug is deliberate: shares are floored, so uneven amounts lose cents while
the six-test suite stays green — fixing it requires both a code change and a
regression test, which gives the reviewer something real to check. The bug
report with acceptance criteria is seeded at
[docs/issues/0001-split-loses-cents.md](docs/issues/0001-split-loses-cents.md).

> [!NOTE]
> The bug stays unfixed **upstream on purpose** — it is the exhibit. Fix it
> in your generated copy as often as you like; pull requests fixing it here
> will be declined with thanks.

## Layout

```text
.agents/settings.yml     Outfitter settings: pinned community-profiles source
docs/issues/             seeded bug reports to file with `gh issue create`
docs/workflows/          workflow walkthroughs
src/split.js             the library (the bug lives here)
bin/split.js             the CLI
test/split.test.js       the suite that passes anyway
AGENTS.md                repository instructions agents follow (CLAUDE.md symlinks to it)
```

## Demo it

[e2e/demo.sh](e2e/README.md) launches the engineer session with everything
wired from what you already have — valid GitHub CLI authentication and your
Claude Code/Codex logins — under a persistent, isolated HOME in `/tmp`. It
runs in this checkout, whose origin must be **your generated playground** (the
script refuses an org-repo origin and verifies template lineage), and resets
it to the upstream state each run so issues and PRs land on your copy and the
seeded bug is back. Pick a harness per run; `check` is a free sanity pass that
does not require or inspect GitHub credentials (its catalog sync is the only
networked step), and `reset` wipes the demo HOME.

```sh
e2e/demo.sh            # claude — or: pi, codex, check, reset
```

## License

[MIT](LICENSE.md)
