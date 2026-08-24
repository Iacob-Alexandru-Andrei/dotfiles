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

# The block must sit at the TOP of every file. Ubuntu's stock ~/.bashrc returns at line 8
# for non-interactive shells, so an appended block is never reached: `ssh host 'command -v
# fresh'` found nothing while the binary was installed and the healthcheck said ok.
printf '# stock rc\ncase $- in\n    *i*) ;;\n      *) return;;\nesac\nexisting_line=1\n' \
  > "$editor_home/.bashrc"
run_installer_fn ensure_path_block >/dev/null 2>&1 || true

for profile in .profile .bashrc .zshenv; do
  first=$(grep -n 'BEGIN dotfiles ubuntu-agent path' "$editor_home/$profile" | head -1 | cut -d: -f1)
  [ "$first" = "1" ] ||
    fail "the PATH block must be the first line of $profile, found at line $first"
done

# Prepending must not discard what was already in the file.
grep -q 'existing_line=1' "$editor_home/.bashrc" ||
  fail 'prepending the PATH block must preserve the existing rc contents'

# And still exactly one block after the repair pass.
blocks=$(grep -c 'BEGIN dotfiles ubuntu-agent path' "$editor_home/.bashrc")
[ "$blocks" -eq 1 ] || fail "repairing must leave one block in .bashrc, got $blocks"

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

# The launcher link must come BEFORE the harness install. Gating it on that exit code
# left the live host with all nine language servers and no `omp` command, because the
# installer returned nonzero after doing its work.
omp_body=$(sed -n '/^install_omp()/,/^}/p' "$repo_dir/ubuntu-agent/install.sh")
link_at=$(printf '%s\n' "$omp_body" | grep -n 'local/bin/omp' | head -1 | cut -d: -f1)
run_at=$(printf '%s\n' "$omp_body" | grep -n 'bin/install.sh )' | head -1 | cut -d: -f1)
[ -n "$link_at" ] || fail 'install_omp must link the omp launcher onto PATH'
[ -n "$run_at" ] || fail 'install_omp must run the omp installer'
[ "$link_at" -lt "$run_at" ] ||
  fail "the omp launcher must be linked before the harness install, so a failing install still leaves a usable omp"

# The npm registry must be configured BEFORE the `have copilot` early return. With
# copilot already installed the old ordering returned first, leaving npm pointed at a
# registry that does not answer on this network -- the run logged the mirror while the
# box still read registry.npmjs.org.
copilot_body=$(sed -n '/^install_copilot_cli()/,/^}/p' "$repo_dir/ubuntu-agent/install.sh")
reg_at=$(printf '%s\n' "$copilot_body" | grep -n 'ensure_npm_registry' | head -1 | cut -d: -f1)
guard_at=$(printf '%s\n' "$copilot_body" | grep -n 'have copilot' | head -1 | cut -d: -f1)
[ -n "$reg_at" ] || fail 'install_copilot_cli must configure the npm registry'
[ -n "$guard_at" ] || fail 'install_copilot_cli must keep its have-copilot guard'
[ "$reg_at" -lt "$guard_at" ] ||
  fail "the npm registry must be set before the have-copilot early return"

grep -q 'packagefeedproxy.microsoft.io' "$repo_dir/ubuntu-agent/install.sh" ||
  fail 'the internal npm mirror must be configured'

# The PROPERTY, not the spelling: every candidate registry is probed before it is
# configured, so a clone outside this network still works. The old assertion pinned one
# curl invocation and failed the moment the probe learned to try both directions.
grep -q 'curl -sS -o /dev/null -I --max-time 5 "$npm_candidate"' "$repo_dir/ubuntu-agent/install.sh" ||
  fail 'each registry must be probed before it is configured'

# --- lint defaults ------------------------------------------------------------------
#
# Behaviour: run the real function against a fake HOME and read what lands.
lint_home=$(mktemp -d)
lint_out=$(HOME="$lint_home" XDG_CONFIG_HOME="$lint_home/.config" sh -c '
  set -eu
  repo_dir=$1
  have() { command -v "$1" >/dev/null 2>&1; }
  info() { printf "%s\n" "$*"; }
  eval "$(sed -n "/^install_lint_defaults()/,/^}/p" "$repo_dir/ubuntu-agent/install.sh")"
  install_lint_defaults
' _ "$repo_dir" 2>&1) || fail "install_lint_defaults must succeed: $lint_out"

[ -f "$lint_home/.config/ruff/ruff.toml" ] ||
  fail 'install_lint_defaults must place a global ruff config'
grep -q 'select = \["ALL"\]' "$lint_home/.config/ruff/ruff.toml" ||
  fail 'the global ruff config must select ALL, not ruff default four families'
grep -q 'TRY003' "$lint_home/.config/ruff/ruff.toml" ||
  fail 'the global ruff config must carry the argued ignore list'

# Pyright must NOT get a global config. A pyrightconfig.json at $HOME outranks
# `[tool.pyright]` in every project that has one, replacing its include/exclude --
# measured in repos/omp, where the pyright hook went from 1s to not finishing in 300s.
# The defaults still ship in lint/pyright/ for a project to copy into its own root.
[ -f "$lint_home/pyrightconfig.json" ] &&
  fail 'install_lint_defaults must not place a pyrightconfig.json at $HOME'
[ -f "$repo_dir/lint/pyright/pyrightconfig.json" ] ||
  fail 'the pyright defaults must still ship for a project to copy'

# ty gets the global config pyright cannot have: $XDG_CONFIG_HOME/ty/ty.toml applies only
# where the project walk finds nothing, so it cannot outrank a repository's own config.
[ -f "$lint_home/.config/ty/ty.toml" ] ||
  fail 'install_lint_defaults must place a global ty.toml'
grep -q 'error-on-warning' "$repo_dir/lint/ty/ty.toml" ||
  fail 'the shipped ty.toml must keep warnings out of the exit code'

# The ty LSP template is rendered into the CONFIG dir, never into a project: placing it
# under a checkout would be the installer choosing a per-project policy. Its command must
# be absolute, since ty is deliberately off PATH and a bare name starts no server.
[ -f "$lint_home/.config/ty/lsp-ty.json" ] ||
  fail 'install_lint_defaults must render the ty LSP template'
grep -q '"REPLACE_WITH_ABSOLUTE_TY_PATH"' "$lint_home/.config/ty/lsp-ty.json" &&
  fail 'the rendered template still carries the placeholder command'
grep -q '"disabled": true' "$lint_home/.config/ty/lsp-ty.json" ||
  fail 'the ty template must disable pyright; two type servers break ONE SERVER PER JOB'
grep -q 'REPLACE_WITH_ABSOLUTE_TY_PATH' "$repo_dir/lint/ty/lsp-ty.json" ||
  fail 'the TRACKED template must keep the placeholder, not a machine-specific path'

# pydoclint's global fallback, and the one setting that makes it worth having: with
# skip-checking-short-docstrings at its default, a one-line docstring exempts the whole
# function, so `def f(a, b)` documented as """Do a thing.""" passes a documentation gate.
[ -f "$lint_home/.config/pydoclint/pyproject.toml" ] ||
  fail 'install_lint_defaults must place the pydoclint defaults'
grep -q 'skip-checking-short-docstrings = false' "$repo_dir/lint/pydoclint/pyproject.toml" ||
  fail 'the shipped pydoclint config must close the short-docstring hole'

# ty reports at error severity, because a warning rendered as advisory grey is one an
# agent reads past and no LSP diagnostic can fail a call whatever it says.
grep -q 'all = "error"' "$repo_dir/lint/ty/ty.toml" ||
  fail 'the shipped ty.toml must default every rule to error'

# The npm registry is chosen by REACHABILITY and both directions must work. The old
# version returned early whenever npm already named the mirror, so a machine that moved
# off the corporate network kept pointing at a proxy it could no longer see and every
# npm install there failed with no explanation.
grep -q "for npm_candidate in 'https://registry.npmjs.org/'" "$repo_dir/ubuntu-agent/install.sh" ||
  fail 'ensure_npm_registry must try the public registry before the mirror'
grep -q 'curl -sS -o /dev/null -I' "$repo_dir/ubuntu-agent/install.sh" ||
  fail 'the probe must accept any HTTP status; the mirror answers 405 to HEAD /'
# Scoped to the registry probe: `-f` is correct for the downloads elsewhere in this
# file, and wrong here, where a 405 means reachable.
sed -n '/^ensure_npm_registry()/,/^}/p' "$repo_dir/ubuntu-agent/install.sh" | grep -q 'curl -f' &&
  fail '-f reads the mirror 405 as a failure and would report it unreachable'

rm -rf "$lint_home"

grep -q 'install_lint_defaults' "$repo_dir/ubuntu-agent/install.sh" ||
  fail 'the installer must place the global lint defaults'

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
