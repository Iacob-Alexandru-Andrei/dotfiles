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
# FIRST, and not merely by convention: `copilot login` and the endpoint proxy both read
# a GitHub token, and `gh auth token` is where the proxy looks after $GITHUB_TOKEN. A
# host that skips this has no Copilot regardless of what the next step reports.
#
# `--skip-ssh-key` declines gh's INTERACTIVE offer to upload a key, not the upload
# itself: that offer stops the run to ask permission and then asks for a title, which
# is how one key acquires a different name on every host -- this account already
# carries one called `corp_macbook`. The upload happens straight after, unattended and
# under the key's own name; see `upload_key` below.
if wanted gh; then
  if ! have gh; then
    printf '\n!!  gh is not installed; run ubuntu-agent/install.sh first\n' >&2
  elif gh auth status >/dev/null 2>&1 && ! forced gh; then
    announce 'GitHub CLI'
    satisfied "$(gh auth status 2>&1 | sed -n 's/.*Logged in to [^ ]* account \([^ ]*\).*/\1/p' | head -1)"
  else
    announce 'GitHub CLI -- one device code, then a browser'
    gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web ||
      printf '!!  gh login did not complete\n' >&2
  fi
fi

# Uploaded automatically, under the SAME NAME the key already has on disk and on every
# other host. gh's own offer to do this is what `--skip-ssh-key` above declines: it
# stops the run to ask permission, then asks for a title, and a title typed per host is
# how one key ends up called `github-company.pub` here, `sandbox_cpu` there, and
# `laptop` on the third. The fingerprint is the identity, so a key already on the
# account is left alone rather than uploaded twice under a new name.
upload_key() {
  key_name=$1
  pub="$HOME/.ssh/$key_name.pub"

  [ -f "$pub" ] || return 0

  # Compare on the key BODY -- field 2 -- because the trailing comment differs between
  # what is on disk and what GitHub echoes back, so a whole-line match never hits and
  # every run would upload a duplicate.
  body=$(awk '{print $2}' "$pub")
  if gh ssh-key list 2>/dev/null | grep -qF "$body"; then
    return 0
  fi

  printf '    uploading %s\n' "$key_name"
  gh ssh-key add "$pub" --title "$key_name" >/dev/null 2>&1 ||
    printf '!!  could not upload %s (needs the admin:public_key scope)\n' "$key_name" >&2
}

# ONE key, chosen by which account gh is actually logged in as. There is a single gh
# session here, so uploading both would attach the personal key to the work account --
# which is precisely the cross-account leak the per-module routing in the god repo
# exists to prevent. The account name decides, and an unrecognised one uploads nothing
# rather than guessing.
if wanted gh && have gh && gh auth status >/dev/null 2>&1; then
  gh_account=$(gh api user --jq '.login' 2>/dev/null)
  case $gh_account in
    *_microsoft|*-microsoft) upload_key github-company ;;
    '') printf '    could not read the gh account; skipping key upload\n' ;;
    *) upload_key github-personal ;;
  esac
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
