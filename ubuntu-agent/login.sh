#!/bin/sh
# Every login on this host that genuinely requires a browser, asked for once, in order.
#
# Separate from install.sh on purpose. That script is unattended and safe to re-run from
# another machine; these are device-code flows that need a human at a browser, so they
# cannot run over a piped ssh and must not be buried in a 400-second provisioning run
# where the code scrolls past unseen and expires.
#
# Each step is SKIPPED when it already holds. Re-running this after one login expires is
# therefore cheap and asks only for the one that lapsed.
#
# Run it on the host, attached to a terminal:
#
#   ssh -t <host> '~/.dotfiles/ubuntu-agent/login.sh'
set -eu

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

only=''
if [ "$#" -gt 0 ]; then
  case $1 in
    -h|--help)
      printf 'usage: login.sh [gh|copilot|az]\n\n' >&2
      printf 'With no argument, every missing login is offered in turn.\n' >&2
      printf 'With one, only that login is attempted, even if it already holds.\n\n' >&2
      printf 'Only browser-bound logins are here. Anything that is a file on disk --\n' >&2
      printf 'the wandb key, the ssh keys -- is provisioning, and install-ubuntu-\n' >&2
      printf 'agent-on-host copies it. This script never asks you to paste a secret.\n' >&2
      exit 0
      ;;
    *) only=$1 ;;
  esac
fi

have() { command -v "$1" >/dev/null 2>&1; }

# A step runs when it was named explicitly, or when nothing was named and it is not
# already satisfied. Naming it forces it, which is how a working-but-wrong account gets
# replaced without logging out first.
wanted() {
  [ -z "$only" ] || [ "$only" = "$1" ]
}
forced() {
  [ "$only" = "$1" ]
}

step=0
skipped=0

announce() {
  step=$((step + 1))
  printf '\n=== %d. %s\n' "$step" "$1"
}

satisfied() {
  printf '    already done: %s\n' "$1"
  skipped=$((skipped + 1))
}

# --- GitHub -----------------------------------------------------------------------
#
# BOTH accounts, each through `god/memory/bin/gh-for-repo.py`. That wrapper is the
# canonical routing on the laptop -- it reads `.github/account-routing.toml`, selects
# that module's `GH_CONFIG_DIR`, and runs gh there. Calling it is what makes this host
# a mirror rather than an imitation: the account-to-key pairing lives in one committed
# file, and duplicating it here is how the two drift.
#
# A route is a MODULE PATH, not an account name: `.` is the god root, which routing
# maps to personal, and `repos/reactions` maps to work. Uploading a key through the
# wrong configuration is what attaches a personal key to the work account; running each
# upload inside its own config dir makes that impossible rather than merely unlikely.
#
# FIRST among the steps, and not by convention: the endpoint proxy reads a GitHub token
# and falls back to `gh auth token`, so a host that skips this has no Copilot whatever
# the next step reports.
#
# `--skip-ssh-key` declines gh's INTERACTIVE offer to upload a key, not the upload
# itself: that offer stops to ask permission and then asks for a title, which is how one
# key acquires a different name on every host -- this account already carries one called
# `corp_macbook`. The upload happens straight after, unattended, under the key's name.
GOD_ROOT="$HOME/projects/god"
GH_ROUTE="$GOD_ROOT/memory/bin/gh-for-repo.py"

# Every account this host should hold, as `route:key` -- the two halves the routing file
# already pairs, restated only as far as naming which module stands for which account.
GH_ACCOUNTS='.:github-personal repos/reactions:github-company'

route_gh() {
  route=$1
  shift
  python3 "$GH_ROUTE" --repo "$route" -- "$@"
}

# Uploaded automatically, under the SAME NAME the key already has on disk and on every
# other host. gh's own offer to do this is what `--skip-ssh-key` above declines: it
# stops the run to ask permission, then asks for a title, and a title typed per host is
# how one key ends up called `github-company.pub` here, `sandbox_cpu` there, and
# `laptop` on the third. The fingerprint is the identity, so a key already on the
# account is left alone rather than uploaded twice under a new name.
upload_key() {
  route=$1
  key_name=$2
  pub="$HOME/.ssh/$key_name.pub"

  [ -f "$pub" ] || return 0

  # Compare on the key BODY -- field 2 -- because the trailing comment differs between
  # what is on disk and what GitHub echoes back, so a whole-line match never hits and
  # every run would upload a duplicate. Measured against the live account rather than
  # assumed: `gh ssh-key list` does print the body, and the existing key matched.
  body=$(awk '{print $2}' "$pub")
  route_gh "$route" ssh-key list 2>/dev/null | grep -qF "$body" && return 0

  printf '    uploading %s\n' "$key_name"
  route_gh "$route" ssh-key add "$pub" --title "$key_name" >/dev/null 2>&1 ||
    printf '!!  could not upload %s (needs the admin:public_key scope)\n' "$key_name" >&2
}

if wanted gh; then
  if ! have gh; then
    printf '\n!!  gh is not installed; run ubuntu-agent/install.sh first\n' >&2
  elif [ ! -f "$GH_ROUTE" ]; then
    printf '\n!!  no gh routing wrapper at %s\n' "$GH_ROUTE" >&2
    printf '    clone the god root there first; this host cannot route two accounts\n' >&2
  else
    for pair in $GH_ACCOUNTS; do
      route=${pair%%:*}
      key=${pair#*:}

      if route_gh "$route" auth status >/dev/null 2>&1 && ! forced gh; then
        announce "GitHub -- $route"
        satisfied "$(route_gh "$route" api user --jq '.login' 2>/dev/null)"
      else
        announce "GitHub -- $route -- one device code, then a browser"
        route_gh "$route" auth login --hostname github.com --git-protocol ssh \
          --skip-ssh-key --web ||
          printf '!!  gh login did not complete for %s\n' "$route" >&2
      fi

      # Inside this account's configuration, so the key cannot land on the other one.
      route_gh "$route" auth status >/dev/null 2>&1 && upload_key "$route" "$key"
    done
  fi
fi


# --- Copilot ----------------------------------------------------------------------
#
# Through `agentic-search-omp login` rather than `copilot login`, and that is the whole
# point of this step. The standalone CLI stores its token in a system keychain, and a
# sandbox has none -- so it falls back to asking whether to write plaintext, and an
# unanswered prompt leaves "Login succeeded, but the token was not saved": an
# authentication that authenticated nothing. Observed exactly that on this host.
#
# The harness path never reaches that question. It runs the device flow itself, writes
# ~/.judge_copilot_token at mode 0600, and probes the actual Copilot exchange rather
# than trusting that a file appeared. It is also the credential omp and the endpoint
# proxy actually read, which the CLI's config directory is not.
if wanted copilot; then
  if ! have agentic-search-omp; then
    printf '\n!!  agentic-search-omp is not installed; run `uv tool install .`\n' >&2
    printf '    in ~/projects/god/repos/stack/agentic-search first\n' >&2
  elif [ -s "$HOME/.judge_copilot_token" ] && ! forced copilot; then
    announce 'Copilot (via the agentic-search harness)'
    satisfied "$HOME/.judge_copilot_token"
  else
    announce 'Copilot -- one device code, then a browser'
    agentic-search-omp login || printf '!!  copilot login did not complete\n' >&2
  fi
fi

# --- Azure ------------------------------------------------------------------------
#
# `--use-device-code` is not optional here. A sandbox has no browser to hand off to, and
# the default flow tries to open one and then waits on a redirect that never arrives.
if wanted az; then
  if ! have az; then
    printf '\n!!  az is not installed; run ubuntu-agent/install.sh first\n' >&2
  elif az account show >/dev/null 2>&1 && ! forced az; then
    announce 'Azure CLI'
    satisfied "$(az account show --query 'user.name' -o tsv 2>/dev/null)"
  else
    announce 'Azure CLI -- one device code, then a browser'
    az login --use-device-code || printf '!!  az login did not complete\n' >&2
  fi
fi

# Weights & Biases is deliberately NOT here. Its credential is a file --
# ~/.ssh/wandb_api_key, which the shell config exports -- so it is provisioning, copied
# by install-ubuntu-agent-on-host like any other key. `wandb login` asks a human to
# paste a secret they already have on disk, which is the one thing this script exists to
# avoid. If it is missing, copy the file; do not type it.

printf '\n=== state now\n'
if have gh; then
  gh auth status >/dev/null 2>&1 &&
    printf '  ok      gh\n' ||
    printf '  MISSING gh\n'
fi
if have agentic-search-omp; then
  [ -s "$HOME/.judge_copilot_token" ] &&
    printf '  ok      copilot\n' ||
    printf '  MISSING copilot\n'
fi
if have az; then
  az account show >/dev/null 2>&1 &&
    printf '  ok      az        %s\n' "$(az account show --query 'user.name' -o tsv 2>/dev/null)" ||
    printf '  MISSING az\n'
fi
# Reported, never prompted for: this is a file that provisioning copies.
[ -s "$HOME/.ssh/wandb_api_key" ] &&
  printf '  ok      wandb     ~/.ssh/wandb_api_key\n' ||
  printf '  MISSING wandb     copy ~/.ssh/wandb_api_key from your laptop\n'

[ "$skipped" -eq 0 ] ||
  printf '\n%d already held; pass a name (gh|copilot|az) to force one.\n' "$skipped"
