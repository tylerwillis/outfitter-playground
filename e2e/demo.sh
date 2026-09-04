#!/usr/bin/env bash
# Demo/test the engineer flow on your host — no container. Runs Outfitter
# under a persistent, isolated HOME in /tmp so harness state (logins,
# onboarding, the synced catalog) survives between runs without touching
# your real ~. It runs in this checkout, whose origin must be YOUR OWN
# playground generated from the ai-outfitter/outfitter-playground template,
# so issues and pull requests land there, never upstream. The checkout is
# reset to the upstream state each run so the seeded bug is back.
#
# usage: e2e/demo.sh [pi|claude|codex]  launch the engineer session (default: claude)
#        e2e/demo.sh check              free sanity check: no model calls
#        e2e/demo.sh reset              wipe the demo HOME for a from-scratch start
#
# env: PLAYGROUND_HOME  demo HOME (default /tmp/outfitter-playground-home)
#      ANTHROPIC_API_KEY / OPENAI_API_KEY are passed through when set.
#
# Credentials: your Claude Code / Codex logins are COPIED into the demo HOME
# on first run (originals untouched); live modes validate `gh` and pass its
# token through. Check mode does not read or require GitHub authentication.
set -eu
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel)
demo_home=${PLAYGROUND_HOME:-/tmp/outfitter-playground-home}

# Resolve npm's active runtime before the isolated HOME hides version-manager
# configuration (mise, nvm, asdf, and similar tools commonly own this path).
# Prepending the real global bin keeps both node and outfitter executable after
# run_demo switches HOME, while ordinary system installations remain unchanged.
npm_prefix=$(npm prefix -g 2>/dev/null || true)
case "$npm_prefix" in
  */) runtime_bin="${npm_prefix}bin" ;;
  ?*) runtime_bin="${npm_prefix}/bin" ;;
  *) runtime_bin="" ;;
esac
if [ -n "$runtime_bin" ] && [ -x "$runtime_bin/outfitter" ]; then
  demo_path="$runtime_bin:$PATH"
else
  demo_path="$PATH"
fi

cmd=${1:-claude}
case "$cmd" in
  reset) rm -rf "$demo_home"; echo "wiped $demo_home"; exit 0 ;;
  pi|claude|codex|check) ;;
  *) echo "usage: e2e/demo.sh [pi|claude|codex|check|reset]" >&2; exit 2 ;;
esac

# --- demo HOME: refresh credentials from the host on EVERY run -------------
# Host logins are the source of truth: OAuth tokens rotate, and a stale or
# emptied copy in the demo HOME (pi clears auth.json when a refresh fails)
# would otherwise stick around forever.
mkdir -p "$demo_home"
seed() { # seed <host-file> <demo-relative-path>
  [ -f "$1" ] || return 0
  mkdir -p "$demo_home/$(dirname "$2")"
  cp -f "$1" "$demo_home/$2"
}
seed "$HOME/.claude/.credentials.json" .claude/.credentials.json
# Claude Code keeps its account/onboarding state in ~/.claude.json — without
# it a fresh HOME asks to authenticate even with credentials present.
[ -f "$HOME/.claude.json" ] && [ ! -f "$demo_home/.claude.json" ] \
  && cp "$HOME/.claude.json" "$demo_home/.claude.json"
seed "$HOME/.codex/auth.json" .codex/auth.json
for f in auth.json settings.json models.json models-store.json; do
  seed "$HOME/.pi/agent/$f" ".pi/agent/$f"
done
# Fast mode is only available on codex right now: seed the codex config and
# set service_tier = "priority" in the DEMO copy only — your real
# ~/.codex/config.toml keeps its own tier.
seed "$HOME/.codex/config.toml" .codex/config.toml
if [ -f "$demo_home/.codex/config.toml" ]; then
  if grep -q '^service_tier' "$demo_home/.codex/config.toml"; then
    config_tmp="$demo_home/.codex/config.toml.tmp.$$"
    sed 's/^service_tier *=.*/service_tier = "priority"/' "$demo_home/.codex/config.toml" > "$config_tmp"
    cat "$config_tmp" > "$demo_home/.codex/config.toml"
    rm -f "$config_tmp"
  else
    printf 'service_tier = "priority"\n' >> "$demo_home/.codex/config.toml"
  fi
fi
if [ ! -f "$demo_home/.gitconfig" ]; then
  HOME="$demo_home" git config --global user.name  "$(git config user.name  || echo playground-demo)"
  HOME="$demo_home" git config --global user.email "$(git config user.email || echo demo@playground.invalid)"
  # git speaks to github over https through gh, so no token ever hits disk
  HOME="$demo_home" git config --global credential."https://github.com".helper '!gh auth git-credential'
  # the demo HOME has no signing keys; the host's signing config must not leak in
  HOME="$demo_home" git config --global commit.gpgsign false
fi

demo_github_token=""

run_demo() { # run a command in the demo environment
  # github-mcp-server (the agents' forge MCP) reads GITHUB_PERSONAL_ACCESS_TOKEN.
  # XDG_CONFIG_HOME pins git (and friends) to the demo HOME's config, so a host
  # signing setup never leaks into unsigned demo commits.
  # Pi installs profile extensions through npm on first launch. Package auditing
  # is unrelated to this disposable demo and can block that install indefinitely
  # on otherwise healthy registry connections, so keep the bootstrap deterministic.
  local -a demo_env
  demo_env=(
    HOME="$demo_home"
    XDG_CONFIG_HOME="$demo_home/.config"
    PATH="$demo_path"
    NPM_CONFIG_AUDIT=false
    NPM_CONFIG_FUND=false
  )
  if [ -n "$demo_github_token" ]; then
    demo_env+=(
      GH_TOKEN="$demo_github_token"
      GITHUB_PERSONAL_ACCESS_TOKEN="$demo_github_token"
    )
  fi
  env -u GH_TOKEN -u GITHUB_TOKEN -u GITHUB_PERSONAL_ACCESS_TOKEN \
    "${demo_env[@]}" \
    ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"} \
    ${OPENAI_API_KEY:+OPENAI_API_KEY="$OPENAI_API_KEY"} \
    "$@"
}

require_github_auth() {
  local github_token
  if ! github_token=$(gh auth token 2>/dev/null) || [ -z "$github_token" ]; then
    echo "gh is not authenticated; run gh auth login" >&2
    exit 1
  fi
  if ! GH_TOKEN="$github_token" gh api user >/dev/null 2>&1; then
    echo "gh authentication is invalid; run gh auth login" >&2
    exit 1
  fi
  demo_github_token=$github_token
  GH_TOKEN=$github_token
  export GH_TOKEN
  unset github_token
}

# Outfitter installs a profile's Pi extensions before it launches the harness. Validate the exact
# provider/model path first with an extension-free profile so bad credentials fail in seconds,
# before the demo arena is reset or npm downloads anything. A successful probe also persists any
# refreshed Pi OAuth state inside the isolated demo HOME.
preflight_pi_auth() {
  [ "$cmd" = pi ] || return 0
  if [ "${#pi_args[@]}" -eq 0 ]; then
    echo "Pi has no default provider/model in $demo_home/.pi/agent/settings.json." >&2
    echo "Run pi normally, select a model, and authenticate before retrying the demo." >&2
    exit 1
  fi

  auth_probe_root=$(mktemp -d "${TMPDIR:-/tmp}/outfitter-pi-auth.XXXXXX")
  cleanup_auth_probe() { rm -rf -- "$auth_probe_root"; }
  trap cleanup_auth_probe EXIT
  mkdir -p "$auth_probe_root/.agents/agents/auth-check"
  printf '%s\n' 'default_agent: auth-check' 'default_harness: pi' > "$auth_probe_root/.agents/settings.yml"
  printf '%s\n' '---' 'name: auth-check' 'description: Verifies that the selected model provider is reachable.' '---' '' '# Authentication check' > "$auth_probe_root/.agents/agents/auth-check/agent.md"

  auth_probe_log="$auth_probe_root/output.log"
  echo "checking Pi provider authentication before resetting the demo..."
  if (cd "$auth_probe_root" && run_demo outfitter run auth-check --harness pi -- "${pi_args[@]}" -p \
    'Reply with exactly OUTFITTER_AUTH_OK.') > "$auth_probe_log" 2>&1; then
    auth_probe_rc=0
  else
    auth_probe_rc=$?
  fi
  cat "$auth_probe_log"
  if [ "$auth_probe_rc" -ne 0 ] || ! grep -qx 'OUTFITTER_AUTH_OK' "$auth_probe_log"; then
    cleanup_auth_probe
    trap - EXIT
    echo "FAIL  Pi could not complete a model call; the demo arena was not reset." >&2
    echo "Run pi normally, authenticate the selected provider, then retry." >&2
    auth_failure_rc=$auth_probe_rc
    [ "$auth_failure_rc" -ne 0 ] || auth_failure_rc=1
    exit "$auth_failure_rc"
  fi
  cleanup_auth_probe
  trap - EXIT
  echo "PASS  Pi provider authentication"
}

run_engineer_session() {
  echo "launching the engineer session ($cmd) — paste the prompt above when it opens..."
  if run_demo outfitter run --harness "$cmd" ${pi_args[@]:+-- "${pi_args[@]}"}; then
    return 0
  else
    session_rc=$?
  fi
  if [ "$session_rc" -eq 130 ]; then
    echo "Engineer session closed (exit 130); opening the verification shell."
    return 0
  else
    echo "FAIL  engineer session exited with code $session_rc; not opening the demo shell." >&2
  fi
  return "$session_rc"
}

cd "$repo_root"

# Outfitter's pi projection replaces pi's agent dir, which drops the user's
# defaultProvider/defaultModel — pi then falls back to an arbitrary model.
# Re-assert the demo HOME's pi defaults explicitly.
pi_args=()
if [ "$cmd" = pi ] && [ -f "$demo_home/.pi/agent/settings.json" ]; then
  defaults=$(node -e 's=require(process.argv[1]);if(s.defaultProvider)console.log(s.defaultProvider+" "+(s.defaultModel||""))' "$demo_home/.pi/agent/settings.json" 2>/dev/null || true)
  if [ -n "$defaults" ]; then
    # shellcheck disable=SC2086
    set -- $defaults
    pi_args=(--provider "$1"); [ -n "${2:-}" ] && pi_args+=(--model "$2")
    echo "pi model: ${1}${2:+/$2} (from your pi settings)"
  fi
fi

# --- free sanity check -----------------------------------------------------
if [ "$cmd" = check ]; then
  total=$(node bin/split.js 100 3 | awk '/^total/ {print $2}')
  [ "$total" = '$99.99' ] && echo "PASS  exhibit bug present (total $total)" \
    || { echo "FAIL  exhibit bug missing (total $total)"; exit 1; }
  npm test >/dev/null 2>&1 && echo "PASS  baseline suite green" \
    || { echo "FAIL  baseline suite red"; exit 1; }
  out=$(run_demo outfitter sync 2>&1) || { echo "FAIL  outfitter sync"; echo "$out" | tail -3; exit 1; }
  echo "$out" | grep -qE '⚠|✗' && { echo "FAIL  sync warnings:"; echo "$out" | grep -E '⚠|✗' | head -3; exit 1; }
  echo "PASS  outfitter sync clean"
  out=$(run_demo outfitter validate --strict 2>&1) && validate_rc=0 || validate_rc=$?
  # A settings.local.yml catalog override is deliberate, visible divergence;
  # its replaced-source warning is the only one a local-dev checkout may show.
  real_warnings=$(echo "$out" | grep -E '⚠|✗' | grep -vE "replaced by .*settings.local.yml|Validation failed" || true)
  if [ -n "$real_warnings" ]; then
    echo "FAIL  validate warnings:"; echo "$real_warnings" | head -3; exit 1
  fi
  if [ "$validate_rc" -ne 0 ] && [ ! -f .agents/settings.local.yml ]; then
    echo "FAIL  outfitter validate --strict"; echo "$out" | tail -5; exit 1
  fi
  if [ -f .agents/settings.local.yml ]; then
    echo "PASS  outfitter validate clean (local catalog override active)"
  else
    echo "PASS  outfitter validate --strict clean"
  fi
  out=$(run_demo outfitter list 2>&1)
  for agent in engineer git-forge-delegator; do
    echo "$out" | grep -qE "^\s+$agent\s+\[(github:ai-outfitter/community-profiles#|/.*community-profiles)" \
      || { echo "FAIL  $agent not resolved from community-profiles"; exit 1; }
  done
  echo "PASS  engineer/git-forge-delegator resolve from community-profiles"
  exit 0
fi

# Live sessions create issues and pull requests, so validate GitHub access
# before the MCP preflight, template-lineage lookup, or destructive arena reset.
# Check mode stays local except for its expected public catalog sync and never
# reads or validates a GitHub credential.
require_github_auth

# The engineer can use gh for issue and pull-request lifecycle operations, but
# its formal adversarial review is delivered through the selected GitHub MCP.
# Fail before resetting the arena instead of launching a session that cannot
# complete the advertised workflow.
if ! PATH="$demo_path" command -v github-mcp-server >/dev/null 2>&1; then
  echo "github-mcp-server is required for the demo's review step." >&2
  echo "macOS: brew install github-mcp-server" >&2
  echo "Other platforms: https://github.com/github/github-mcp-server/releases/latest" >&2
  exit 1
fi

# --- demo arena: this checkout, generated from the template ----------------
# Issues and PRs land wherever origin points. The arena is a repo GENERATED
# from ai-outfitter/outfitter-playground ("Use this template"), not a fork:
# generated repos run Actions immediately and have issues enabled, where
# forks need one-time UI clicks for both. Refuse the org repo itself.
case "$(git remote get-url origin)" in
  *ai-outfitter/outfitter-playground*)
    echo "origin is the upstream org repo. Generate your own playground and point origin at it:" >&2
    echo "  gh repo create <you>/outfitter-playground --template ai-outfitter/outfitter-playground --public" >&2
    echo "  git remote set-url origin git@github.com:<you>/outfitter-playground.git" >&2
    exit 1 ;;
esac
# Derive the arena from origin — with two github remotes, gh's own
# resolution prefers upstream, which is exactly the wrong target here.
arena=$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')
lineage=$(gh api "repos/$arena" --jq '.template_repository.full_name // ""' 2>/dev/null)
if [ "$lineage" != ai-outfitter/outfitter-playground ]; then
  echo "$arena was not generated from ai-outfitter/outfitter-playground; refusing to reset it." >&2
  echo "  gh repo create <you>/outfitter-playground --template ai-outfitter/outfitter-playground --public" >&2
  exit 1
fi
git remote get-url upstream >/dev/null 2>&1 \
  || git remote add upstream https://github.com/ai-outfitter/outfitter-playground.git
# Bare gh commands in the demo session (the agent's `gh issue create`,
# `gh pr create`) must target the arena, not upstream.
gh repo set-default "$arena" >/dev/null 2>&1 || true

if [ -z "${E2E_NO_LAUNCH:-}" ]; then
  preflight_pi_auth
fi

echo "resetting checkout to the upstream state (uncommitted changes and extra branches are discarded)..."
git fetch -q upstream
git checkout -qf main
git reset -q --hard upstream/main
git clean -qfd
# Agents follow the worktree convention, so demo branches may live in
# sibling worktrees; nuke them all before deleting the branches — a dead
# session's lock is no reason to stop a reset (hence --force --force).
git worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2 \
  | xargs -rn1 git worktree remove --force --force
git worktree prune
git for-each-ref --format='%(refname:short)' refs/heads \
  | grep -v '^main$' | xargs -r git branch -qD
git push -q --force origin main
gh pr list -R "$arena" --state open --json number --jq '.[].number' \
  | xargs -rn1 gh pr close -R "$arena" --delete-branch >/dev/null 2>&1 || true
# a leftover open issue would suppress the issue-filing step the demo showcases
gh issue list -R "$arena" --state open --json number --jq '.[].number' \
  | xargs -rn1 gh issue close -R "$arena" >/dev/null 2>&1 || true

echo "syncing the community-profiles catalog..."
run_demo outfitter sync

cat <<EOF

┌─────────────────────────────────────────────────────────────────────┐
  playground demo — $repo_root
  arena: $arena   (HOME: $demo_home)

  The bug: node bin/split.js 100 3   totals \$99.99

  1. You are about to land in the ENGINEER agent ($cmd harness).
     Paste this bug report — nothing more:

     Splitting \$100 among 3 people loses a cent — 'node bin/split.js
     100 3' totals \$99.99. The shares should always sum to the
     amount. Do not merge.

  2. Watch the SDLC come from the loadout, not the prompt: the
     engineer's scoped-issues skill reproduces the report and files
     the scoped issue itself; then fix/ branch, regression test, draft
     PR, CI green, PR marked ready — and per its code-review skill it
     REVIEWS its own PR: cold-context subagents return JSON findings,
     it posts one formal review via the github MCP, then fixes blockers.

  3. Want a review pass by hand (or a re-review)? Run:

     outfitter run --harness $cmd

     Paste: Review the open pull request against its linked issue's
     acceptance criteria.

  4. Verify and merge yourself:

     node bin/split.js 100 3    # \$100.00
     npm test && gh pr merge --squash
└─────────────────────────────────────────────────────────────────────┘

EOF

if [ -n "${E2E_NO_LAUNCH:-}" ]; then
  echo "(E2E_NO_LAUNCH set — bootstrap verified, not launching)"
  exit 0
fi

run_engineer_session || exit $?

cat <<EOF

Engineer session ended. This shell stays in the demo environment — next:
  outfitter run --harness $cmd${pi_args:+ -- ${pi_args[@]}}   # re-review: paste the review prompt
  gh pr view --web ; npm test ; gh pr merge --squash
(exit to leave; e2e/demo.sh to go again with a fresh slate)
EOF
exec env HOME="$demo_home" GH_TOKEN="$demo_github_token" \
  ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"} \
  ${OPENAI_API_KEY:+OPENAI_API_KEY="$OPENAI_API_KEY"} bash
