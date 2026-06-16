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

grep -q 'setup_ref=' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must detect the current local ref that contains ubuntu-agent files"

grep -q 'git clone --branch' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must clone the selected setup ref on new remotes"

grep -q 'git -C.*checkout' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must switch existing remote checkouts to the selected setup ref"

if grep -q 'alex/ubuntu-agent-setup' "$repo_dir/bin/install-ubuntu-agent-on-host"; then
  fail "host installer must not hard-code the feature branch"
fi

if grep -q 'copy_tree_if_present\\|skills-source\\|plugins-source\\|installed-plugins' "$repo_dir/bin/install-ubuntu-agent-on-host"; then
  fail "host installer must not copy local Copilot skills/plugins"
fi

grep -q 'BEGIN dotfiles ubuntu-agent github hosts' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must manage SSH host aliases in a marked block"

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

grep -q -- '--skip-apt' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must offer --skip-apt for base-image-safe runs"

grep -q -- '--skip-apt' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must pass through --skip-apt"

grep -q 'install_apt=1' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install missing apt packages by default"

grep -q 'install_apt=1' "$repo_dir/bin/install-ubuntu-agent-on-host" ||
  fail "host installer must request apt installation by default"

if grep -q 'ubuntu-agent' "$repo_dir/install.sh"; then
  fail "normal install.sh must not invoke ubuntu-agent setup"
fi

printf 'ubuntu-agent setup static checks passed\n'
