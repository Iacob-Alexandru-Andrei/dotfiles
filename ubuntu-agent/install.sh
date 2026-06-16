#!/bin/sh
set -eu

with_dotfiles=0
install_apt=0

usage() {
  cat <<'EOF' >&2
usage: ubuntu-agent/install.sh [--with-dotfiles] [--install-apt]

Sets up an Ubuntu host for agent/Copilot work without changing the default
dotfiles installer. Existing tools and config are detected and left in place.
Missing apt packages are reported by default and installed only with
--install-apt.
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

install_uv() {
  if have uv; then
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
  if have pre-commit; then
    return 0
  fi

  info "installing pre-commit in user space"
  if have pipx; then
    python3 -m pipx install pre-commit || python3 -m pip install --user pre-commit
  else
    python3 -m pip install --user pre-commit
  fi
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
    info "npm not found; skipping Copilot CLI install"
    return 0
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
  repo_dir=$1
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
    info "GitHub SSH host aliases already configured"
    return 0
  fi

  cat >> "$config_file" <<'EOF'

# BEGIN dotfiles ubuntu-agent github hosts
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

run_dotfiles_install() {
  if [ "$with_dotfiles" -eq 0 ]; then
    return 0
  fi

  "$repo_dir/install.sh"
}

healthcheck() {
  info ""
  info "ubuntu-agent healthcheck"
  for cmd in git curl jq rg fdfind tmux zsh python3 uv pre-commit npm copilot gh az amlt; do
    if have "$cmd"; then
      printf '  ok      %s\n' "$cmd"
    else
      printf '  missing %s\n' "$cmd"
    fi
  done

  for alias in github-personal github-company; do
    if ssh -G "$alias" >/dev/null 2>&1; then
      printf '  ok      ssh alias %s\n' "$alias"
    else
      printf '  missing ssh alias %s\n' "$alias"
    fi
  done

  for key_name in github-personal github-company; do
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
install_copilot_cli
install_github_hosts
install_copilot_skills
run_dotfiles_install
healthcheck
