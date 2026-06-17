#!/bin/sh
set -eu

with_dotfiles=0
install_apt=1
install_neovim=1

usage() {
  cat <<'EOF' >&2
usage: ubuntu-agent/install.sh [--with-dotfiles] [--install-apt] [--skip-apt] [--skip-neovim]

Sets up an Ubuntu host for agent/Copilot work without changing the default
dotfiles installer. Existing tools and config are detected and left in place.
Missing apt packages are installed by default. Use --skip-apt to only report
missing packages. Use --skip-neovim to skip Neovim/AstroNvim setup.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-dotfiles)
      with_dotfiles=1
      shift
      ;;
    --install-apt)
      install_apt=1
      shift
      ;;
    --skip-apt)
      install_apt=0
      shift
      ;;
    --skip-neovim)
      install_neovim=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

info() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_ubuntu() {
  if [ ! -r /etc/os-release ]; then
    info "warning: cannot identify OS; continuing conservatively"
    return 0
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ]; then
    printf 'ubuntu-agent setup targets Ubuntu; found ID=%s\n' "${ID:-unknown}" >&2
    exit 1
  fi
}

ensure_path_block() {
  profile_file="$HOME/.profile"
  begin='# BEGIN dotfiles ubuntu-agent path'
  end='# END dotfiles ubuntu-agent path'

  export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

  touch "$profile_file"
  if grep -q "$begin" "$profile_file"; then
    return 0
  fi

  cat >> "$profile_file" <<'EOF'

# BEGIN dotfiles ubuntu-agent path
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
# END dotfiles ubuntu-agent path
EOF
}

apt_install_missing() {
  have apt-get || return 0

  missing=''
  for spec in \
    git:git \
    curl:curl \
    jq:jq \
    rg:ripgrep \
    fdfind:fd-find \
    tmux:tmux \
    zsh:zsh \
    nvim:neovim \
    unzip:unzip \
    python3:python3 \
    pipx:pipx \
    npm:npm
  do
    cmd=${spec%%:*}
    pkg=${spec#*:}
    if ! have "$cmd"; then
      missing="$missing $pkg"
    fi
  done

  [ -n "$missing" ] || return 0

  if [ "$install_apt" -eq 0 ]; then
    info "missing Ubuntu packages:$missing"
    info "rerun with --install-apt to install missing apt packages"
    return 0
  fi

  have sudo || {
    info "sudo not found; skipping apt package installation"
    return 0
  }

  info "installing missing Ubuntu packages:$missing"
  sudo apt-get update
  # shellcheck disable=SC2086
  sudo apt-get install -y $missing
}

pipx_package_installed() {
  package_name=$1

  have pipx || return 1
  python3 -m pipx list --short 2>/dev/null | grep -Eq "^${package_name}( |$)"
}

install_uv() {
  if have uv || pipx_package_installed uv; then
    return 0
  fi

  info "installing uv in user space"
  if have pipx; then
    python3 -m pipx install 'uv==0.11.2' || python3 -m pip install --user 'uv==0.11.2'
  else
    python3 -m pip install --user 'uv==0.11.2'
  fi
}

install_pre_commit() {
  if have pre-commit || pipx_package_installed pre-commit; then
    return 0
  fi

  info "installing pre-commit in user space"
  if have pipx; then
    python3 -m pipx install pre-commit || python3 -m pip install --user pre-commit
  else
    python3 -m pip install --user pre-commit
  fi
}

install_wandb() {
  if have wandb || pipx_package_installed wandb; then
    return 0
  fi

  info "installing wandb in user space"
  if have pipx; then
    python3 -m pipx install wandb || python3 -m pip install --user wandb
  else
    python3 -m pip install --user wandb
  fi
}

nvim_is_modern() {
  required_nvim_minor=11

  have nvim || return 1

  nvim_version=$(
    NVIM_APPNAME=dotfiles-agent-version-check nvim --version 2>/dev/null |
      sed -n '1s/^NVIM v//p'
  )
  nvim_major=${nvim_version%%.*}
  nvim_rest=${nvim_version#*.}
  nvim_minor=${nvim_rest%%.*}

  case $nvim_major:$nvim_minor in
    *[!0-9:]* | :* | *:)
      return 1
      ;;
  esac

  if [ "$nvim_major" -gt 0 ]; then
    return 0
  fi

  [ "$nvim_major" -eq 0 ] && [ "$nvim_minor" -ge "$required_nvim_minor" ]
}

ensure_modern_neovim() {
  if [ "$install_neovim" -eq 0 ]; then
    return 0
  fi

  if nvim_is_modern; then
    return 0
  fi

  have curl || {
    info "curl not found; skipping modern Neovim install"
    return 0
  }

  have tar || {
    info "tar not found; skipping modern Neovim install"
    return 0
  }

  info "installing Neovim 0.11+ in user space"
  nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
  nvim_opt_dir="$HOME/.local/opt"
  nvim_install_dir="$nvim_opt_dir/nvim-linux-x86_64"
  nvim_tmp_dir=$(mktemp -d)
  nvim_archive="$nvim_tmp_dir/nvim-linux-x86_64.tar.gz"

  mkdir -p "$nvim_opt_dir" "$HOME/.local/bin"
  curl -fsSL "$nvim_url" -o "$nvim_archive"
  tar -xzf "$nvim_archive" -C "$nvim_tmp_dir"
  rm -rf "$nvim_install_dir"
  mv "$nvim_tmp_dir/nvim-linux-x86_64" "$nvim_install_dir"
  ln -sfn "$nvim_install_dir/bin/nvim" "$HOME/.local/bin/nvim"
  rm -rf "$nvim_tmp_dir"
}

install_astronvim() {
  if [ "$install_neovim" -eq 0 ]; then
    return 0
  fi

  nvim_dir="$HOME/.config/nvim"
  marker="$nvim_dir/.dotfiles-ubuntu-agent-astronvim"

  if [ -e "$nvim_dir" ] && [ ! -f "$marker" ]; then
    info "existing Neovim config found at $nvim_dir; skipping AstroNvim setup"
    return 0
  fi

  if [ ! -d "$nvim_dir/.git" ]; then
    rm -rf "$nvim_dir"
    mkdir -p "$(dirname -- "$nvim_dir")"
    git clone https://github.com/AstroNvim/template "$nvim_dir"
  else
    git -C "$nvim_dir" remote set-url origin https://github.com/AstroNvim/template
    git -C "$nvim_dir" pull --ff-only
  fi

  touch "$marker"
}

install_github_cli() {
  if have gh; then
    return 0
  fi

  if [ "$install_apt" -eq 0 ]; then
    info "gh not found; rerun without --skip-apt to install GitHub CLI"
    return 0
  fi

  have sudo || {
    info "sudo not found; skipping GitHub CLI installation"
    return 0
  }

  have curl || {
    info "curl not found; skipping GitHub CLI installation"
    return 0
  }

  info "installing GitHub CLI"
  sudo mkdir -p /usr/share/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

  arch=$(dpkg --print-architecture)
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$arch" |
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y gh
}

clone_or_update_repo() {
  repo_url=$1
  target_dir=$2

  if [ ! -d "$target_dir/.git" ]; then
    mkdir -p "$(dirname -- "$target_dir")"
    git clone "$repo_url" "$target_dir"
    return 0
  fi

  git -C "$target_dir" remote set-url origin "$repo_url"
  git -C "$target_dir" pull --ff-only
}

install_copilot_cli() {
  if have copilot; then
    return 0
  fi

  if ! have npm; then
    if [ "$install_apt" -eq 1 ]; then
      apt_install_missing
    fi

    if ! have npm; then
      info "npm not found; skipping Copilot CLI install"
      return 0
    fi
  fi

  info "installing GitHub Copilot CLI with npm user prefix"
  mkdir -p "$HOME/.npm-global"
  npm config set prefix "$HOME/.npm-global" >/dev/null
  npm install -g @github/copilot
}

link_skill_dir() {
  source_dir=$1
  skill_name=$(basename -- "$source_dir")
  target_dir="$HOME/.copilot/skills/$skill_name"

  [ -f "$source_dir/SKILL.md" ] || return 0

  if [ -L "$target_dir" ]; then
    current_link=$(readlink "$target_dir")
    if [ "$current_link" = "$source_dir" ]; then
      return 0
    fi

    rm "$target_dir"
  elif [ -e "$target_dir" ]; then
    info "skipping existing Copilot skill: $target_dir"
    return 0
  fi

  ln -s "$source_dir" "$target_dir"
}

install_skill_links_from_repo() {
  skill_repo_dir=$1
  skills_root=$2

  [ -d "$skills_root" ] || return 0

  find "$skills_root" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | while IFS= read -r skill_file; do
    link_skill_dir "$(dirname -- "$skill_file")"
  done
}

install_superpowers_plugin() {
  if ! have copilot; then
    info "copilot not found; skipping Superpowers plugin install"
    return 0
  fi

  info "installing Superpowers from official Copilot plugin marketplace"
  copilot plugin marketplace add obra/superpowers-marketplace >/dev/null 2>&1 || true
  copilot plugin install superpowers@superpowers-marketplace >/dev/null 2>&1 ||
    copilot plugin update superpowers >/dev/null 2>&1 ||
    info "Superpowers plugin install/update did not complete; run: copilot plugin install superpowers@superpowers-marketplace"
}

install_copilot_skills() {
  source_root="$HOME/.local/share/dotfiles-agent"
  custom_skills_repo="$source_root/skills"
  god_skills_repo="$source_root/god-skills"
  academic_skills_repo="$source_root/academic-research-skills"

  mkdir -p "$HOME/.copilot/skills" "$source_root"

  clone_or_update_repo \
    "git@github-personal:Iacob-Alexandru-Andrei/skills.git" \
    "$custom_skills_repo" ||
    info "custom skills repo clone failed; check github-personal SSH auth"

  clone_or_update_repo \
    "git@github-personal:Iacob-Alexandru-Andrei/god-skills.git" \
    "$god_skills_repo" ||
    info "God-specific skills repo clone failed; check github-personal SSH auth"

  clone_or_update_repo \
    "https://github.com/Imbad0202/academic-research-skills.git" \
    "$academic_skills_repo"

  install_skill_links_from_repo "$custom_skills_repo" "$custom_skills_repo/memory/skills"
  install_skill_links_from_repo "$god_skills_repo" "$god_skills_repo/memory/skills"
  install_skill_links_from_repo "$academic_skills_repo" "$academic_skills_repo"
  install_superpowers_plugin

  info "Copilot skills directory: $HOME/.copilot/skills"
}

install_github_hosts() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  config_file="$HOME/.ssh/config"
  begin='# BEGIN dotfiles ubuntu-agent github hosts'
  end='# END dotfiles ubuntu-agent github hosts'

  touch "$config_file"
  chmod 600 "$config_file"

  if grep -q "$begin" "$config_file"; then
    tmp_file=$(mktemp)
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      !skip { print }
    ' "$config_file" > "$tmp_file"
    mv "$tmp_file" "$config_file"
    chmod 600 "$config_file"
  fi

  cat >> "$config_file" <<'EOF'

# BEGIN dotfiles ubuntu-agent github hosts
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/github-personal
  IdentitiesOnly yes

Host github-company
  HostName github.com
  User git
  IdentityFile ~/.ssh/github-company
  IdentitiesOnly yes
# END dotfiles ubuntu-agent github hosts
EOF
}

ensure_default_company_key() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ ! -f "$HOME/.ssh/github-company" ]; then
    return 0
  fi

  if [ ! -e "$HOME/.ssh/id_ed25519" ] && [ ! -L "$HOME/.ssh/id_ed25519" ]; then
    ln -s "$HOME/.ssh/github-company" "$HOME/.ssh/id_ed25519"
  fi

  if [ -f "$HOME/.ssh/github-company.pub" ] &&
    [ ! -e "$HOME/.ssh/id_ed25519.pub" ] &&
    [ ! -L "$HOME/.ssh/id_ed25519.pub" ]; then
    ln -s "$HOME/.ssh/github-company.pub" "$HOME/.ssh/id_ed25519.pub"
  fi
}

ensure_github_known_host() {
  known_hosts="$HOME/.ssh/known_hosts"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$known_hosts"
  chmod 600 "$known_hosts"

  if ssh-keygen -F github.com -f "$known_hosts" >/dev/null 2>&1; then
    return 0
  fi

  if ! have ssh-keyscan; then
    info "ssh-keyscan not found; skipping GitHub known_hosts setup"
    return 0
  fi

  info "adding github.com to known_hosts"
  ssh-keyscan github.com >> "$known_hosts" 2>/dev/null
}

run_dotfiles_install() {
  if [ "$with_dotfiles" -eq 0 ]; then
    return 0
  fi

  "$repo_dir/install.sh"
}

install_bash_zsh_handoff() {
  bashrc="$HOME/.bashrc"
  begin='# BEGIN dotfiles ubuntu-agent zsh handoff'
  end='# END dotfiles ubuntu-agent zsh handoff'

  touch "$bashrc"
  if grep -q "$begin" "$bashrc"; then
    return 0
  fi

  cat >> "$bashrc" <<'EOF'

# BEGIN dotfiles ubuntu-agent zsh handoff
case $- in
  *i*) ;;
  *) return ;;
esac

if [ -z "${DOTFILES_ZSH_HANDOFF:-}" ] && command -v zsh >/dev/null 2>&1; then
  export DOTFILES_ZSH_HANDOFF=1
  exec zsh
fi
# END dotfiles ubuntu-agent zsh handoff
EOF
}

healthcheck() {
  info ""
  info "ubuntu-agent healthcheck"
  for cmd in git curl jq rg fdfind tmux zsh nvim python3 uv pre-commit wandb npm copilot gh az amlt; do
    if have "$cmd"; then
      printf '  ok      %s\n' "$cmd"
    else
      printf '  missing %s\n' "$cmd"
    fi
  done

  for alias in github.com github-personal github-company; do
    if ssh -G "$alias" >/dev/null 2>&1; then
      printf '  ok      ssh alias %s\n' "$alias"
    else
      printf '  missing ssh alias %s\n' "$alias"
    fi
  done

  for key_name in github-personal github-company id_ed25519; do
    if [ -f "$HOME/.ssh/$key_name" ]; then
      printf '  ok      ~/.ssh/%s exists\n' "$key_name"
    else
      printf '  missing ~/.ssh/%s\n' "$key_name"
    fi
  done

  if [ -n "${WANDB_API_KEY:-}" ]; then
    printf '  ok      WANDB_API_KEY is set\n'
  else
    printf '  missing WANDB_API_KEY\n'
  fi

  info ""
  info "Manual auth still required where needed: gh auth login, copilot login, az login, amlt project checkout."
}

require_ubuntu
ensure_path_block
apt_install_missing
install_uv
install_pre_commit
install_wandb
ensure_modern_neovim
install_astronvim
install_github_cli
install_copilot_cli
install_github_hosts
ensure_default_company_key
ensure_github_known_host
install_copilot_skills
run_dotfiles_install
install_bash_zsh_handoff
healthcheck
