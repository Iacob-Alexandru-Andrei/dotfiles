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
