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

grep -q -- '--skip-neovim' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must pass through --skip-neovim"

grep -q -- '--minimal' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must pass through --minimal"

grep -q -- '--no-packages' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must pass through --no-packages"

grep -q -- '--no-nvim' "$repo_dir/bin/install-on-host" ||
  fail "normal host installer must pass through --no-nvim"

grep -q -- '--minimal' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must pass through --minimal"

grep -q -- '--no-packages' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must pass through --no-packages"

grep -q -- '--no-nvim' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "ubuntu-agent host installer must pass through --no-nvim"

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
  fail "ordinary github.com SSH remotes must use the standard company key"

grep -q 'ensure_default_company_key' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must default an existing company key to ~/.ssh/id_ed25519"

grep -q 'ln -s "$HOME/.ssh/github-company" "$HOME/.ssh/id_ed25519"' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "company key defaulting must avoid duplicating private-key contents"

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

grep -q 'install_astronvim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install AstroNvim"

grep -q 'ensure_modern_neovim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must ensure Neovim is modern enough for AstroNvim"

grep -q 'required_nvim_minor=11' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "AstroNvim requires Neovim 0.11+"

grep -q 'nvim-linux-x86_64.tar.gz' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "modern Neovim installer must use the upstream Linux x86_64 release tarball"

grep -q 'NVIM_APPNAME' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "Neovim version checks must avoid loading user config"

grep -q 'ln -sfn "$nvim_install_dir/bin/nvim" "$HOME/.local/bin/nvim"' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "modern Neovim installer must put nvim on the user PATH"

grep -q 'hash -r' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "modern Neovim installer must refresh the shell command cache after installing nvim"

grep -q 'Neovim 0.11+ is required for AstroNvim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "AstroNvim setup must fail clearly if Neovim remains too old"

grep -q 'install_neovim=1' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install Neovim/AstroNvim by default"

grep -q -- '--skip-neovim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must offer --skip-neovim"

grep -q 'nvim:neovim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent apt setup must install neovim when nvim is missing"

grep -q 'AstroNvim/template' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "AstroNvim must be installed from the official template repository"

grep -q '.dotfiles-ubuntu-agent-astronvim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "AstroNvim install must write an ownership marker for idempotence"

grep -q 'existing Neovim config' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "AstroNvim install must skip existing non-owned Neovim config"

grep -q 'install_bash_zsh_handoff' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must configure bash-to-zsh handoff"

grep -q 'BEGIN dotfiles ubuntu-agent zsh handoff' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bash-to-zsh handoff must use a marked idempotent block"

grep -q 'DOTFILES_ZSH_HANDOFF' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bash-to-zsh handoff must guard against recursion"

grep -q 'exec zsh' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "bash-to-zsh handoff must exec zsh for interactive bash shells"

grep -q 'git curl jq rg fdfind tmux zsh nvim python3 uv pre-commit wandb nvitop bpytop npm copilot gh az amlt' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent healthcheck must report nvim, wandb, nvitop, and bpytop"

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

grep -q -- '--no-nvim' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must pass through --no-nvim to normal dotfiles installer"

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
