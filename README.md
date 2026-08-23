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

It is found, never cloned: this repo does not own omp. The search order is
`$OMP_REPO`, then `~/projects/god/repos/omp`, then a sibling of this checkout. A
machine with none of those gets a note and an otherwise normal install — the
shell config does not depend on it.

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

Open a new zsh session after installing:

```sh
exec zsh
```

## Optional Ubuntu agent setup

Agent/Copilot setup for Ubuntu hosts is separate from the normal dotfiles
installer. From a machine that already has this repo:

```sh
~/.dotfiles/bin/install-ubuntu-agent-on-host \
  --personal-key ~/.ssh/<personal-key> \
  --work-key ~/.ssh/<work-key> \
  <ssh-host>
```

See [`ubuntu-agent/README.md`](ubuntu-agent/README.md) for details. Missing apt
packages are installed by default; pass `--skip-apt` if you only want the script
to report them. Neovim 0.11+/AstroNvim is installed by default; pass
`--skip-neovim` to opt out. `nvitop` and `bpytop` are installed as user-space
monitors. The work key is installed as the standard `~/.ssh/id_ed25519` GitHub key so
ordinary `git@github.com:...` remotes use company GitHub access.
