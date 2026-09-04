# Dotfiles

Portable zsh prompt, shell setup, and tmux defaults.

## Local install

```sh
git clone https://github.com/Iacob-Alexandru-Andrei/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

The installer backs up existing `~/.zshrc`, `~/.zimrc`, and `~/.tmux.conf`
files before linking them to this repo.

The tmux config enables mouse/trackpad scrolling, a larger scrollback history,
friendlier pane/window defaults, and a readable status line. New tmux servers
load `~/.tmux.conf` automatically. Existing tmux servers need a reload:

```sh
tmux source-file ~/.tmux.conf
```

## Coding harness

`install.sh` also installs the [omp](https://github.com/Iacob-Alexandru-Andrei/omp)
coding harness and its Copilot endpoint, then links the launcher into
`~/.local/bin/omp` so `omp` starts a session from any directory. One command
brings the pinned runtime, nine language servers, fifteen quality gates, and the
agents and skills.

It is found, never cloned: this repo does not own omp, and the `god` tree's omp
remote is not reachable from a bare machine. The search order is `$OMP_REPO`,
then `~/projects/god/repos/omp`, then a sibling of this checkout.

A machine with none of those does **not** fail the install — the shell config
does not depend on a coding agent — but it says so loudly, names every path it
looked in, and repeats it in the closing summary:

```
!! omp harness NOT installed: no checkout found
   looked in: $OMP_REPO, ~/projects/god/repos/omp, .../dotfiles/../omp
   fix: clone the god tree to ~/projects/god, or set OMP_REPO=/path/to/omp
```

```sh
./install.sh --no-omp        # shell config only, no harness
OMP_REPO=~/src/omp ./install.sh
```

## Install on an SSH host

From a machine that already has this repo:

```sh
~/.dotfiles/bin/install-on-host mac-mini-server
```

Or run directly on the remote machine:

```sh
git clone https://github.com/Iacob-Alexandru-Andrei/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

The full installer runs GitHub's default Copilot CLI installer on every setup,
so an existing installation is updated as well as a missing one being
installed. It also keeps Copilot's startup auto-update enabled and installs the
OMP and Codex launchers. Global Copilot skills and skill plugins are removed;
skills belong to the repository that uses them.

Remote setup securely copies `~/.judge_copilot_token` and exposes it as
`COPILOT_GITHUB_TOKEN`, so headless hosts authenticate as the same corporate
Copilot account without relying on a desktop keychain. The preferred models
are listed in `copilot/models.allowlist`; add one model ID per line and keep
the final `fallback:` entry on an allowed model. The `copilot` launcher places
that native policy into each repository as an ignored symlink before starting
the real CLI. Disallowed session models are refused, and disallowed subagent
overrides are clamped to the fallback. A repository carrying a different
policy fails closed instead of widening the fleet policy.

Open a new zsh session after installing:

```sh
exec zsh
```

## Optional Ubuntu agent setup

Agent/Copilot setup for Ubuntu hosts is separate from the normal dotfiles
installer. From a machine that already has this repo:

```sh
~/.dotfiles/bin/install-ubuntu-agent-on-host <ssh-host>            # personal auth
~/.dotfiles/bin/install-ubuntu-agent-on-host --work <ssh-host>     # work auth
~/.dotfiles/bin/install-ubuntu-agent-on-host --personal --work <ssh-host>
```

Each flag selects one account and nothing else, so typing both is what installs
both. With neither, you get personal, which needs no opting into. The keys are
discovered from `~/.ssh` -- `id_ed25519_github_personal` and `id_ed25519` --
and `--personal-key PATH` / `--work-key PATH` override that discovery and select
the account they name.

Both accounts land on the remote as `~/.ssh/github-personal` and
`~/.ssh/github-company`, matching the host aliases the installer writes, so
`git@github-personal:...` and `git@github-company:...` both work. The
unqualified `git@github.com:...` reads `~/.ssh/id_ed25519`, which personal
claims whenever personal was selected; a work-only install gives it to work.

`--mesh` answers a different question from the account flags: not which GitHub
the remote signs as, but whether it can `ssh` where this machine can. It copies
the key the sandboxes accept to `~/.ssh/sandbox-mesh` and writes the `sandbox*`
host aliases from your `~/.ssh/config` into the remote's, so an agent running
there reaches the other boxes by the same names you use:

```sh
~/.dotfiles/bin/install-ubuntu-agent-on-host --mesh <ssh-host>
```

Only `sandbox*` hosts are carried. Other entries authenticate with keys that
mean something else on the remote -- `mac-mini-server` uses `id_ed25519`, which
there is a GitHub key -- so meshing them would break them. The block is written
between its own markers and the file is replaced by rename, so re-running
updates it in place rather than stacking copies, and the installer's
GitHub-hosts block is left alone. `--mesh-key PATH` overrides the discovered
key.

See [`ubuntu-agent/README.md`](ubuntu-agent/README.md) for details. Missing apt
packages are installed by default; pass `--skip-apt` if you only want the script
to report them. Fresh is installed as the default editor (`EDITOR`/`VISUAL`,
which is also what omp reads) with helix alongside it; pass `--skip-editors` to
opt out of both. The omp harness and its language servers are installed too;
`--skip-omp` opts out. `nvitop` and `bpytop` are installed as user-space
monitors.

## Tests

```sh
sh tests/run-all.sh
```

The account-selection matrix runs the real driver with `ssh` and `scp` replaced
by recorders, so it checks which key reached which remote name rather than
grepping the script for the shape of an answer.
