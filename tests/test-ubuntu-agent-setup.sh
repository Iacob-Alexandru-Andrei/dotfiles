#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -x "$repo_dir/bin/install-ubuntu-agent-on-host" ] ||
  fail "missing executable bin/install-ubuntu-agent-on-host"

[ -x "$repo_dir/ubuntu-agent/install.sh" ] ||
  fail "missing executable ubuntu-agent/install.sh"

[ -f "$repo_dir/ubuntu-agent/README.md" ] ||
  fail "missing ubuntu-agent/README.md"

grep -q 'ubuntu-agent/install.sh' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must invoke the separate ubuntu-agent installer"

grep -q 'copy_key_if_requested' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must keep SSH key copying explicit"

grep -q 'copy_key_if_requested "work GitHub default" "$work_key" "id_ed25519"' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must copy the work GitHub key to the standard ~/.ssh/id_ed25519 name"

grep -q 'setup_ref=' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must detect the current local ref that contains ubuntu-agent files"

grep -q 'setup_ref=' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must detect the current local ref that contains dotfiles files"

grep -q -- '--skip-editors' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must pass through --skip-editors"

grep -q -- '--skip-omp' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must pass through --skip-omp"

grep -q -- '--minimal' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must pass through --minimal"

grep -q -- '--no-packages' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must pass through --no-packages"

grep -q -- '--no-editors' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must pass through --no-editors"

grep -q -- '--minimal' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must pass through --minimal"

grep -q -- '--no-packages' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must pass through --no-packages"

grep -q 'install_omp_harness' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must track the omp harness selection"

grep -q 'git clone --branch' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must clone the selected setup ref on new remotes"

grep -q 'git clone --branch' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must clone the selected setup ref on new remotes"

grep -q 'git -C.*checkout' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must switch existing remote checkouts to the selected setup ref"

grep -q 'git -C.*checkout' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must switch existing remote checkouts to the selected setup ref"

if grep -q 'alex/ubuntu-agent-setup' "$repo_dir/bin/install-ubuntu-agent-on-host"; then
  fail "host installer must not hard-code the feature branch"
fi

if grep -q 'copy_tree_if_present\\|skills-source\\|plugins-source\\|installed-plugins' "$repo_dir/bin/install-ubuntu-agent-on-host"; then
  fail "host installer must not copy local Copilot skills/plugins"
fi

grep -q 'BEGIN dotfiles ubuntu-agent github hosts' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must manage SSH host aliases in a marked block"

grep -q 'Host github.com' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must configure github.com for ordinary Git SSH remotes"

grep -q 'IdentityFile ~/.ssh/id_ed25519' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ordinary github.com SSH remotes must read the default identity"

# Behaviour, not source text. The old assertions grepped for a function name and a single
# `ln -s` line, which a version that linked nothing at all would still have passed.
identity_home=$(mktemp -d)

extract_function() {
  awk -v name="$1" '
    $0 == name "() {" { inside = 1 }
    inside { print }
    inside && $0 == "}" { exit }
  ' "$repo_dir/ubuntu-agent/install.sh"
}

run_default_identity() {
  extract_function ensure_default_identity > "$identity_home/fn.sh"
  [ -s "$identity_home/fn.sh" ] ||
    fail "could not extract ensure_default_identity from the installer"
  HOME="$identity_home" sh -c '. "$1"; ensure_default_identity' _ "$identity_home/fn.sh"
}

for present in github-personal github-company; do
  rm -rf "${identity_home:?}/.ssh"
  mkdir -p "$identity_home/.ssh"
  printf 'KEY-%s\n' "$present" > "$identity_home/.ssh/$present"
  printf 'PUB-%s\n' "$present" > "$identity_home/.ssh/$present.pub"

  run_default_identity

  [ -L "$identity_home/.ssh/id_ed25519" ] ||
    fail "default identity must be a symlink when only $present is installed"
  [ "$(cat "$identity_home/.ssh/id_ed25519")" = "KEY-$present" ] ||
    fail "default identity must resolve to $present when it is the only key"
  [ "$(cat "$identity_home/.ssh/id_ed25519.pub")" = "PUB-$present" ] ||
    fail "default public identity must resolve to $present"
done

# Both installed: personal holds the unqualified identity, matching the driver's rule
# that personal is always fine and work is the thing you opt into.
rm -rf "${identity_home:?}/.ssh"
mkdir -p "$identity_home/.ssh"
printf 'KEY-personal\n' > "$identity_home/.ssh/github-personal"
printf 'KEY-work\n' > "$identity_home/.ssh/github-company"
run_default_identity
[ "$(cat "$identity_home/.ssh/id_ed25519")" = 'KEY-personal' ] ||
  fail "with both accounts installed, personal must hold the default identity"

# An identity the operator already placed is never replaced.
rm -rf "${identity_home:?}/.ssh"
mkdir -p "$identity_home/.ssh"
printf 'KEY-personal\n' > "$identity_home/.ssh/github-personal"
printf 'PRE-EXISTING\n' > "$identity_home/.ssh/id_ed25519"
run_default_identity
[ "$(cat "$identity_home/.ssh/id_ed25519")" = 'PRE-EXISTING' ] ||
  fail "an existing ~/.ssh/id_ed25519 must not be overwritten"

rm -rf "$identity_home"

grep -q 'ensure_github_known_host' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must idempotently add GitHub to known_hosts"

grep -q 'ssh-keyscan github.com' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must fetch the GitHub SSH host key before private clones"

grep -q 'install_copilot_skills' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install Copilot skills separately"

grep -q 'Imbad0202/academic-research-skills.git' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install academic skills from the official source repository"

grep -q 'Iacob-Alexandru-Andrei/skills.git' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install custom skills from the source repository"

grep -q 'Iacob-Alexandru-Andrei/god-skills.git' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install God-specific skills from the source repository"

grep -q 'superpowers@superpowers-marketplace' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install Superpowers from the official Copilot plugin marketplace"

grep -q 'DietrichGebert/ponytail' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must add the Ponytail Copilot plugin marketplace"

grep -q 'ponytail@ponytail' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install Ponytail from the Copilot plugin marketplace"

grep -q 'install_skill_links_from_repo' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must link skill directories from cloned source repos"

grep -q 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must update PATH for the current run"

grep -q 'pipx_package_installed' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must detect pipx-installed packages idempotently"

grep -q 'pipx_package_installed uv' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "uv install must skip existing pipx uv package even before PATH refresh"

grep -q 'pipx_package_installed pre-commit' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "pre-commit install must skip existing pipx pre-commit package even before PATH refresh"

grep -q 'install_wandb' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install wandb"

grep -q 'pipx_package_installed wandb' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "wandb install must skip existing pipx wandb package even before PATH refresh"

grep -q 'python3 -m pipx install wandb' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "wandb should be installed with pipx when available"

grep -q 'install_nvitop' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install nvitop"

grep -q 'pipx_package_installed nvitop' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "nvitop install must skip existing pipx nvitop package even before PATH refresh"

grep -q 'python3 -m pipx install nvitop' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "nvitop should be installed with pipx when available"

grep -q 'install_bpytop' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install bpytop"

grep -q 'pipx_package_installed bpytop' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bpytop install must skip existing pipx bpytop package even before PATH refresh"

grep -q 'python3 -m pipx install bpytop' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bpytop should be installed with pipx when available"

# --- editors -----------------------------------------------------------------------
#
# Behaviour, not source text: the previous block grepped for `install_astronvim` and a
# hardcoded tarball name, which asserted that particular lines existed rather than that
# the installer worked. These run the real functions against a fake HOME and a stubbed
# PATH, and read what lands on disk.

editor_home=$(mktemp -d)
editor_bin=$(mktemp -d)

# `have` must find these, and they must not do anything real.
for stub in curl git python3 sudo; do
  printf '#!/bin/sh\nexit 0\n' > "$editor_bin/$stub"
  chmod +x "$editor_bin/$stub"
done

# ensure_path_block is the fix for the live gap: user installs were invisible to
# non-interactive ssh because only ~/.profile carried the PATH.
run_installer_fn() {
  fn=$1
  shift
  HOME="$editor_home" PATH="$editor_bin:$PATH" sh -c '
    set -eu
    HOME=$1; fn=$2; script=$3
    have() { command -v "$1" >/dev/null 2>&1; }
    info() { printf "%s\n" "$*"; }
    install_editors=1
    install_omp_harness=1
    install_apt=0
    eval "$(sed -n "/^'"$fn"'()/,/^}/p" "$script")"
    "$fn"
  ' _ "$editor_home" "$fn" "$repo_dir/ubuntu-agent/install.sh" "$@"
}

run_installer_fn ensure_path_block >/dev/null 2>&1 || true

for profile in .profile .bashrc .zshenv; do
  [ -f "$editor_home/$profile" ] ||
    fail "ensure_path_block must write $profile so non-interactive ssh sees the PATH"
  grep -q '.local/bin' "$editor_home/$profile" ||
    fail "$profile must put .local/bin on PATH"
  grep -q 'EDITOR=fresh' "$editor_home/$profile" ||
    fail "$profile must make fresh the default editor"
  grep -q 'VISUAL=fresh' "$editor_home/$profile" ||
    fail "$profile must set VISUAL so omp external editor uses fresh"
done

# Helix is installed but must never be made the default.
if grep -qE 'EDITOR=(hx|helix)|VISUAL=(hx|helix)' "$repo_dir/ubuntu-agent/install.sh"; then
  fail 'helix must not be set as the default editor'
fi

# Idempotent: a second run must not stack a second block.
run_installer_fn ensure_path_block >/dev/null 2>&1 || true
blocks=$(grep -c 'BEGIN dotfiles ubuntu-agent path' "$editor_home/.profile")
[ "$blocks" -eq 1 ] ||
  fail "two runs must leave one PATH block in ~/.profile, got $blocks"

rm -rf "$editor_home" "$editor_bin"

# Neovim is gone, not merely unreferenced by name.
if grep -qiE 'neovim|astronvim|nvim' "$repo_dir/ubuntu-agent/install.sh"; then
  fail 'the ubuntu-agent installer must no longer reference Neovim or AstroNvim'
fi

grep -q 'install_bash_zsh_handoff' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must configure bash-to-zsh handoff"

grep -q 'BEGIN dotfiles ubuntu-agent zsh handoff' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bash-to-zsh handoff must use a marked idempotent block"

grep -q 'DOTFILES_ZSH_HANDOFF' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bash-to-zsh handoff must guard against recursion"

grep -q 'exec zsh' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bash-to-zsh handoff must exec zsh for interactive bash shells"

# The healthcheck must name what the installer now installs. It previously verified
# `nvim` and no language server at all, which is how the live box reported green with
# zero servers on it.
for expected in fresh hx omp fd uv pre-commit wandb nvitop bpytop copilot; do
  grep -qE "for cmd in .*\b${expected}\b" "$repo_dir/ubuntu-agent/install.sh" ||
    fail "ubuntu-agent healthcheck must report $expected"
done

grep -q 'lsp.json' "$repo_dir/ubuntu-agent/install.sh" ||
  fail 'ubuntu-agent healthcheck must verify the language servers omp provisions'

grep -q 'install_github_cli' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install GitHub CLI"

grep -q 'cli.github.com/packages' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "GitHub CLI installer must use the official GitHub CLI apt repository"

if grep -q 'pipx install amlt\\|pip install amlt\\|uv tool install amlt' "$repo_dir/ubuntu-agent/install.sh"; then
  fail "ubuntu-agent installer must not install AMLT yet"
fi

grep -q 'find "$skills_root" -mindepth 2 -maxdepth 2 -name SKILL.md' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "skill installer must only discover SKILL.md files, not run repo install scripts"

if grep -q '"$academic_skills_repo"/install.sh' "$repo_dir/ubuntu-agent/install.sh"; then
  fail "ubuntu-agent installer must not run academic repo install.sh"
fi

if grep -q '^  repo_dir=' "$repo_dir/ubuntu-agent/install.sh"; then
  fail "functions must not overwrite the global repo_dir used by run_dotfiles_install"
fi

if ! awk '
  /^install_github_hosts$/ { github_line = NR }
  /^install_copilot_skills$/ { skills_line = NR }
  END { exit !(github_line && skills_line && github_line < skills_line) }
' "$repo_dir/ubuntu-agent/install.sh"; then
  fail "GitHub SSH aliases must be configured before cloning private skill repos"
fi

grep -q -- '--install-apt' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must keep --install-apt for compatibility"

grep -q -- '--minimal' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must pass through --minimal to normal dotfiles installer"

grep -q -- '--no-packages' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must pass through --no-packages to normal dotfiles installer"

grep -q 'install_omp' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install the omp harness"

grep -q 'wire_fresh_lsp' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must wire omp's language servers into fresh"

grep -q -- '--skip-apt' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must offer --skip-apt for base-image-safe runs"

grep -q -- '--skip-apt' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must pass through --skip-apt"

grep -q 'install_apt=1' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install missing apt packages by default"

grep -q 'install_apt=1' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must request apt installation by default"

grep -q 'dotfiles_args=' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must accumulate normal dotfiles installer args"

grep -q '"$repo_dir/install.sh" $dotfiles_args' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must pass accumulated dotfiles args to install.sh"

grep -q 'remote_dotfiles_args=' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must forward normal dotfiles args"

if grep -q 'ubuntu-agent' "$repo_dir/install.sh"; then
  fail "normal install.sh must not invoke ubuntu-agent setup"
fi

printf 'ubuntu-agent setup static checks passed\n'
