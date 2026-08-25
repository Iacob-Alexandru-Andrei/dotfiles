#!/bin/sh
set -eu

# Cross-platform dotfiles installer (macOS + Debian/Ubuntu).
# - Symlinks zsh / zim / tmux configs (always).
# - Installs modern CLI tools the configs expect (zoxide, fzf, eza, bat, ...).
# - Installs helix (the default editor) and fresh.
# - Installs the omp coding harness and its Copilot endpoint.
#
# Usage:
#   ./install.sh                full setup (symlinks + packages + editors + omp)
#   ./install.sh --minimal      symlinks only (no package installs)
#   ./install.sh --no-editors   everything except fresh/helix
#   ./install.sh --no-omp       everything except the omp harness
#   ./install.sh --no-packages  alias of --minimal

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
timestamp=$(date +%Y%m%d%H%M%S)

INSTALL_PACKAGES=1
INSTALL_EDITORS=1
INSTALL_OMP=1
for arg in "$@"; do
  case "$arg" in
    --minimal|--no-packages) INSTALL_PACKAGES=0; INSTALL_EDITORS=0; INSTALL_OMP=0 ;;
    --no-editors) INSTALL_EDITORS=0 ;;
    --no-omp) INSTALL_OMP=0 ;;
    -h|--help) printf 'usage: %s [--minimal] [--no-editors] [--no-omp]\n' "$0"; exit 0 ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

info() { printf '\033[1;34m::\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------
# Symlink dotfiles (idempotent; backs up pre-existing real files)
# --------------------------------------------------------------------------
link_file() {
  source_path=$1
  target_path=$2

  if [ ! -e "$source_path" ]; then
    printf 'missing source: %s\n' "$source_path" >&2
    exit 1
  fi

  target_dir=$(dirname -- "$target_path")
  mkdir -p "$target_dir"

  if [ -L "$target_path" ]; then
    current_link=$(readlink "$target_path")
    if [ "$current_link" = "$source_path" ]; then
      printf 'already linked: %s -> %s\n' "$target_path" "$source_path"
      return
    fi
    printf 'removing stale symlink: %s -> %s\n' "$target_path" "$current_link"
    rm "$target_path"
  elif [ -e "$target_path" ]; then
    backup_path="${target_path}.backup.${timestamp}"
    printf 'backing up: %s -> %s\n' "$target_path" "$backup_path"
    mv "$target_path" "$backup_path"
  fi

  ln -s "$source_path" "$target_path"
  printf 'linked: %s -> %s\n' "$target_path" "$source_path"
}

info 'Linking shell + tmux config'
link_file "$repo_dir/zsh/.zshrc" "$HOME/.zshrc"
link_file "$repo_dir/zim/.zimrc" "$HOME/.zimrc"
link_file "$repo_dir/tmux/.tmux.conf" "$HOME/.tmux.conf"

# Install the Ghostty terminfo so this machine renders inbound SSH sessions from
# a Ghostty terminal (TERM=xterm-ghostty) correctly. Without it the remote line
# editor miscomputes the cursor and the display looks doubled/garbled.
install_terminfo() {
  command -v tic >/dev/null 2>&1 || { warn 'tic not found; skipping terminfo (install ncurses)'; return 0; }
  [ -f "$repo_dir/terminfo/ghostty.terminfo" ] || return 0
  if infocmp xterm-ghostty >/dev/null 2>&1; then
    printf 'terminfo present: xterm-ghostty\n'; return 0
  fi
  info 'Installing xterm-ghostty terminfo'
  tic -x -o "$HOME/.terminfo" "$repo_dir/terminfo/ghostty.terminfo" 2>/dev/null \
    || warn 'terminfo install failed'
}
install_terminfo

# Include the dotfiles-managed Ghostty config (theme, ...) from the user's real
# Ghostty config, without overwriting any local settings there. Idempotent.
ensure_ghostty_config() {
  [ -f "$repo_dir/ghostty/config" ] || return 0
  cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
  cfg="$cfg_dir/config"
  include="config-file = $repo_dir/ghostty/config"
  mkdir -p "$cfg_dir"
  if [ -f "$cfg" ] && grep -qF "$include" "$cfg"; then
    printf 'ghostty: dotfiles include already present\n'
    return 0
  fi
  printf '%s\n' "$include" >> "$cfg"
  info 'ghostty: linked dotfiles config (theme applied)'
}
ensure_ghostty_config

# --------------------------------------------------------------------------
# Platform detection
# --------------------------------------------------------------------------
os=$(uname -s)
arch=$(uname -m)
sudo_cmd=""
if [ "$(id -u)" -ne 0 ] && have sudo; then
  sudo_cmd="sudo"
fi

pkg=""
case "$os" in
  Darwin) if have brew; then pkg=brew; else warn 'Homebrew not found; install from https://brew.sh then re-run'; fi ;;
  Linux)  if have apt-get; then pkg=apt; else warn 'no apt-get; install tools manually for your distro'; fi ;;
esac

mkdir -p "$HOME/.local/bin"

case "$arch" in
  x86_64|amd64)  nv_arch=x86_64; gh_arch=x86_64; eza_arch=x86_64 ;;
  aarch64|arm64) nv_arch=arm64;  gh_arch=arm64;  eza_arch=aarch64 ;;
  *)             nv_arch="";     gh_arch="";     eza_arch="" ;;
esac

gh_latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
}

# --------------------------------------------------------------------------
# Modern CLI tools
# --------------------------------------------------------------------------
install_packages() {
  case "$pkg" in
    brew)
      info 'Installing CLI tools via Homebrew'
      brew install git curl tmux zsh ripgrep fd fzf bat eza zoxide lazygit \
        || warn 'some brew formulae failed'
      brew install --cask font-jetbrains-mono-nerd-font 2>/dev/null \
        || warn 'nerd font cask skipped (optional)'
      ;;
    apt)
      info 'Installing CLI tools via apt'
      $sudo_cmd apt-get update -y || warn 'apt-get update failed'
      $sudo_cmd apt-get install -y \
        git curl unzip build-essential ca-certificates \
        tmux zsh ripgrep fd-find bat fzf || warn 'some apt packages failed'
      # Ubuntu ships fd as fdfind and bat as batcat; expose canonical names.
      [ -e /usr/bin/fdfind ] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd" || true
      [ -e /usr/bin/batcat ] && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat" || true
      install_zoxide_linux
      install_eza_linux
      install_lazygit_linux
      install_nerdfont_linux
      ;;
    *) warn 'skipping package install (unknown package manager)' ;;
  esac
}

install_zoxide_linux() {
  have zoxide && { info 'zoxide present'; return 0; }
  info 'Installing zoxide'
  curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
    | sh || warn 'zoxide install failed'
}

install_eza_linux() {
  have eza && { info 'eza present'; return 0; }
  if $sudo_cmd apt-get install -y eza 2>/dev/null; then info 'eza via apt'; return 0; fi
  [ -n "$eza_arch" ] || { warn 'eza: unsupported arch'; return 0; }
  info 'Installing eza (release tarball)'
  url="https://github.com/eza-community/eza/releases/latest/download/eza_${eza_arch}-unknown-linux-gnu.tar.gz"
  tmp=$(mktemp -d)
  if curl -fsSL "$url" -o "$tmp/eza.tar.gz" && tar -xzf "$tmp/eza.tar.gz" -C "$tmp"; then
    install -m 0755 "$tmp/eza" "$HOME/.local/bin/eza" || warn 'eza install failed'
  else
    warn 'eza download failed'
  fi
  rm -rf "$tmp"
}

install_lazygit_linux() {
  have lazygit && { info 'lazygit present'; return 0; }
  [ -n "$gh_arch" ] || { warn 'lazygit: unsupported arch'; return 0; }
  tag=$(gh_latest_tag jesseduffield/lazygit); ver=${tag#v}
  [ -n "$ver" ] || { warn 'lazygit: could not resolve version'; return 0; }
  info "Installing lazygit $ver"
  url="https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${ver}_Linux_${gh_arch}.tar.gz"
  tmp=$(mktemp -d)
  if curl -fsSL "$url" -o "$tmp/lg.tar.gz" && tar -xzf "$tmp/lg.tar.gz" -C "$tmp" lazygit; then
    install -m 0755 "$tmp/lazygit" "$HOME/.local/bin/lazygit" || warn 'lazygit install failed'
  else
    warn 'lazygit download failed'
  fi
  rm -rf "$tmp"
}

install_nerdfont_linux() {
  font_dir="$HOME/.local/share/fonts"
  [ -e "$font_dir/JetBrainsMonoNerdFont-Regular.ttf" ] && return 0
  info 'Installing JetBrainsMono Nerd Font'
  mkdir -p "$font_dir"
  tmp=$(mktemp -d)
  url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  if curl -fsSL "$url" -o "$tmp/font.zip" && unzip -o -q "$tmp/font.zip" -d "$font_dir" '*.ttf'; then
    have fc-cache && fc-cache -f "$font_dir" >/dev/null 2>&1 || true
  else
    warn 'nerd font install skipped'
  fi
  rm -rf "$tmp"
}

# --------------------------------------------------------------------------
# Editors: helix is the default, fresh is available
# --------------------------------------------------------------------------
# Fresh replaces Neovim/AstroNvim here. On Linux it is one static musl binary under
# ~/.local that updates itself; on macOS it is a brew formula. Helix installs beside it
# and is never made the default.
install_fresh() {
  if have fresh; then info "fresh present: $(fresh --version 2>/dev/null || echo unknown)"; return 0; fi

  if [ "$pkg" = brew ]; then
    info 'Installing fresh via Homebrew'
    brew install fresh-editor || warn 'fresh brew install failed'
    return 0
  fi

  have curl || { warn 'curl missing; cannot install fresh'; return 0; }

  info 'Installing fresh (universal build)'
  FRESH_NO_DESKTOP=1 curl -fsSL \
    https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh |
    sh || warn 'fresh install failed'

  hash -r 2>/dev/null || true
  have fresh && info "fresh installed: $(fresh --version 2>/dev/null || echo unknown)"
}

install_helix() {
  if have hx; then info "helix present: $(hx --version 2>/dev/null || echo unknown)"; return 0; fi

  if [ "$pkg" = brew ]; then
    info 'Installing helix via Homebrew'
    brew install helix || warn 'helix brew install failed'
    return 0
  fi

  case $nv_arch in
    x86_64) helix_asset='x86_64-linux' ;;
    arm64) helix_asset='aarch64-linux' ;;
    *) warn 'helix: unsupported arch; install manually'; return 0 ;;
  esac

  have curl || { warn 'curl missing; cannot install helix'; return 0; }

  helix_url=$(
    curl -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest 2>/dev/null |
      sed -n "s/.*\"browser_download_url\": *\"\([^\"]*${helix_asset}\.tar\.xz\)\".*/\1/p" |
      head -1
  )
  [ -n "$helix_url" ] || { warn 'helix: could not resolve a release'; return 0; }

  info 'Installing helix (release tarball)'
  tmp=$(mktemp -d)
  if curl -fsSL "$helix_url" -o "$tmp/helix.tar.xz" && tar -xJf "$tmp/helix.tar.xz" -C "$tmp" 2>/dev/null; then
    helix_root=$(find "$tmp" -maxdepth 1 -type d -name 'helix-*' | head -1)
    if [ -n "$helix_root" ] && [ -x "$helix_root/hx" ]; then
      mkdir -p "$HOME/.local/bin" "$HOME/.config/helix"
      cp "$helix_root/hx" "$HOME/.local/bin/hx"
      chmod 755 "$HOME/.local/bin/hx"
      # The runtime carries grammars and themes; without it every buffer is unhighlighted.
      [ -d "$helix_root/runtime" ] && cp -R "$helix_root/runtime" "$HOME/.config/helix/"
      info "helix installed: $("$HOME/.local/bin/hx" --version 2>/dev/null | head -1)"
    fi
  else
    warn 'helix download failed'
  fi
  rm -rf "$tmp"
}

# --------------------------------------------------------------------------
# omp coding harness + Copilot endpoint
# --------------------------------------------------------------------------
# ONE COMMAND, because `omp/bin/install.sh` already installs both. It provisions
# the pinned runtime, nine language servers, fifteen gate tools, the agents and
# skills, and -- when the `agentic-search` checkout is beside it -- renders the
# Copilot endpoint into the same profile. Reimplementing any part of that here
# would be a second copy to keep in step with the first.
#
# It is FOUND, not cloned. This repository does not own omp and has no business
# deciding where it lives: `$OMP_REPO` answers first for anyone whose layout
# differs, then the standard `god` checkout, then a sibling of this repo. A
# machine with none gets a note saying where to look, not a failure -- the shell
# config this installer exists for works perfectly well without a coding agent.
install_omp() {
  omp_repo=""
  for candidate in \
    "${OMP_REPO:-}" \
    "$HOME/projects/god/repos/omp" \
    "$repo_dir/../omp"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/bin/install.sh" ]; then
      # `CDPATH=` is a prefix assignment, not an empty variable: without it a user's
      # CDPATH can make `cd` land somewhere else and print where it went. Same idiom as
      # `repo_dir` at the top of this file.
      # shellcheck disable=SC1007
      omp_repo=$(CDPATH= cd -- "$candidate" && pwd -P)
      break
    fi
  done

  # ABSENCE IS REPORTED, LOUDLY, AND NAMES THE FIX. It is not a clone: the `god` tree is a
  # submodule layout whose omp remote is not reachable from a bare machine, so `git clone`
  # here would fail at the network with a worse message than this one. It is not fatal
  # either -- the shell and tmux config this script exists for do not depend on a coding
  # agent, and taking the whole install down would be the wrong trade.
  #
  # What it must never be is silent. `install.sh` finishing green while `omp` is missing is
  # the setup someone discovers days later, which is exactly what this section was added to
  # prevent. The summary at the end repeats it for the same reason.
  if [ -z "$omp_repo" ]; then
    OMP_STATUS='missing: no checkout found'
    warn 'omp harness NOT installed: no checkout found'
    printf '   looked in: $OMP_REPO, ~/projects/god/repos/omp, %s/../omp\n' "$repo_dir" >&2
    printf '   fix: clone the god tree to ~/projects/god, or set OMP_REPO=/path/to/omp\n' >&2
    printf '   then re-run: %s\n' "$0" >&2
    return 0
  fi

  # `uv` builds the harness venvs and `node` runs five of the language servers. Both come
  # from the package step above, so naming the missing one here beats a failure forty lines
  # into someone else's script.
  for tool in uv node; do
    if ! have "$tool"; then
      OMP_STATUS="missing: needs $tool"
      warn "omp harness NOT installed: $tool is missing"
      printf '   fix: install %s, then re-run: %s\n' "$tool" "$0" >&2
      return 0
    fi
  done

  info 'Installing omp harness (language servers, gates, agents, skills)'
  if sh "$omp_repo/bin/install.sh"; then
    # The launcher, so `omp` works from any directory. A symlink rather than a copy: it
    # resolves its own location to find the profile, and it refuses to exec itself, so
    # reaching it through `PATH` is safe.
    ln -sfn "$omp_repo/bin/omp" "$HOME/.local/bin/omp"
    OMP_STATUS='installed'
  else
    OMP_STATUS='FAILED: see the harness output above'
    warn 'omp harness install reported a failure'
  fi
}

# --------------------------------------------------------------------------
# Run
# --------------------------------------------------------------------------
[ "$INSTALL_PACKAGES" -eq 1 ] && install_packages
if [ "$INSTALL_EDITORS" -eq 1 ]; then
  install_fresh
  install_helix
fi
# After the packages, which is where `uv` and `node` come from.
OMP_STATUS='skipped by --no-omp'
[ "$INSTALL_OMP" -eq 1 ] && install_omp

printf '\n'
info 'Done.'
printf 'Open a new zsh session or run: exec zsh\n'
printf 'For an existing tmux server, run: tmux source-file ~/.tmux.conf\n'
[ "$INSTALL_EDITORS" -eq 1 ] && printf 'Launch the editor with: hx   (fresh: fresh)\n'
# STATED EVERY TIME, installed or not. A summary that mentions omp only on success is one
# where its absence looks like it was never meant to be there.
case "$OMP_STATUS" in
  installed) printf 'Start a coding session with: omp\n' ;;
  *)         printf 'omp harness: %s\n' "$OMP_STATUS" >&2 ;;
esac
exit 0
