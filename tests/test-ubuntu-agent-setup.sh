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

grep -q 'BEGIN dotfiles ubuntu-agent github hosts' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must manage SSH host aliases in a marked block"

grep -q 'install_copilot_skills' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must install Copilot skills separately"

grep -q -- '--install-apt' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must make apt installation explicit"

grep -q 'install_apt=0' "$repo_dir/ubuntu-agent/install.sh" ||
  fail "ubuntu-agent installer must not install apt packages by default"

if grep -q 'ubuntu-agent' "$repo_dir/install.sh"; then
  fail "normal install.sh must not invoke ubuntu-agent setup"
fi

printf 'ubuntu-agent setup static checks passed\n'
