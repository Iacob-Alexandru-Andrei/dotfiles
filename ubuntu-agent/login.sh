#!/bin/sh
# Every interactive login this host needs, asked for once, in order.
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
      printf 'usage: login.sh [gh|copilot|az|wandb]\n\n' >&2
      printf 'With no argument, every missing login is offered in turn.\n' >&2
      printf 'With one, only that login is attempted, even if it already holds.\n' >&2
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
if wanted gh; then
  if ! have gh; then
    printf '\n!!  gh is not installed; run ubuntu-agent/install.sh first\n' >&2
  elif gh auth status >/dev/null 2>&1 && ! forced gh; then
    announce 'GitHub CLI'
    satisfied "$(gh auth status 2>&1 | sed -n 's/.*Logged in to [^ ]* account \([^ ]*\).*/\1/p' | head -1)"
  else
    announce 'GitHub CLI -- opens a device code, needs a browser'
    gh auth login --hostname github.com --git-protocol ssh --web || {
      printf '!!  gh login did not complete\n' >&2
    }
  fi
fi

# --- Copilot ----------------------------------------------------------------------
#
# The credential omp actually serves models with. It lands in ~/.config/github-copilot,
# which is what the endpoint proxy and `copilot` itself both read.
if wanted copilot; then
  if ! have copilot; then
    printf '\n!!  copilot is not installed; run ubuntu-agent/install.sh first\n' >&2
  elif [ -d "$HOME/.config/github-copilot" ] && ! forced copilot; then
    announce 'Copilot CLI'
    satisfied "$HOME/.config/github-copilot"
  else
    announce 'Copilot CLI -- opens a device code, needs a browser'
    copilot login || printf '!!  copilot login did not complete\n' >&2
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
    announce 'Azure CLI -- opens a device code, needs a browser'
    az login --use-device-code || printf '!!  az login did not complete\n' >&2
  fi
fi

# --- Weights & Biases -------------------------------------------------------------
#
# A pasted key rather than a device code, and read from ~/.ssh/wandb_api_key by the
# shell config when it is there. Offered last because nothing else depends on it.
if wanted wandb; then
  if ! have wandb; then
    printf '\n!!  wandb is not installed; run ubuntu-agent/install.sh first\n' >&2
  elif [ -f "$HOME/.netrc" ] && grep -q 'api.wandb.ai' "$HOME/.netrc" 2>/dev/null && ! forced wandb; then
    announce 'Weights & Biases'
    satisfied "$HOME/.netrc"
  elif [ -n "${WANDB_API_KEY:-}" ] && ! forced wandb; then
    announce 'Weights & Biases'
    satisfied 'WANDB_API_KEY is set'
  else
    announce 'Weights & Biases -- paste an API key, or Ctrl-C to skip'
    wandb login || printf '   skipped\n'
  fi
fi

printf '\n=== state now\n'
if have gh; then
  gh auth status >/dev/null 2>&1 &&
    printf '  ok      gh\n' ||
    printf '  MISSING gh\n'
fi
if have copilot; then
  [ -d "$HOME/.config/github-copilot" ] &&
    printf '  ok      copilot\n' ||
    printf '  MISSING copilot\n'
fi
if have az; then
  az account show >/dev/null 2>&1 &&
    printf '  ok      az        %s\n' "$(az account show --query 'user.name' -o tsv 2>/dev/null)" ||
    printf '  MISSING az\n'
fi
if have wandb; then
  { [ -f "$HOME/.netrc" ] && grep -q 'api.wandb.ai' "$HOME/.netrc" 2>/dev/null; } ||
    [ -n "${WANDB_API_KEY:-}" ] &&
    printf '  ok      wandb\n' ||
    printf '  MISSING wandb  (optional)\n'
fi

[ "$skipped" -eq 0 ] ||
  printf '\n%d already held; pass a name (gh|copilot|az|wandb) to force one.\n' "$skipped"
