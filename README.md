# Dotfiles

Portable zsh prompt and shell setup.

## Local install

```sh
git clone git@github.com:Iacob-Alexandru-Andrei/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

The installer backs up existing `~/.zshrc` and `~/.zimrc` files before linking them to this repo.

## Install on an SSH host

From a machine that already has this repo:

```sh
~/.dotfiles/bin/install-on-host mac-mini-server
```

Or run directly on the remote machine:

```sh
git clone git@github.com:Iacob-Alexandru-Andrei/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

Open a new zsh session after installing:

```sh
exec zsh
```
