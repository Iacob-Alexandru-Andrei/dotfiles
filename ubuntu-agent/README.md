# Ubuntu Agent Setup

This is an opt-in setup path for Ubuntu machines used for agent and Copilot
work. It is intentionally separate from the normal dotfiles installer:

- normal shell/tmux setup: `install.sh`
- Ubuntu agent setup: `ubuntu-agent/install.sh`
- remote driver: `bin/install-ubuntu-agent-on-host`

The setup is conservative and idempotent. It detects existing tools, installs
missing low-conflict user-space tools where possible, and leaves authentication
manual.

## From your local machine

```sh
~/.dotfiles/bin/install-ubuntu-agent-on-host <ssh-host>            # personal auth
~/.dotfiles/bin/install-ubuntu-agent-on-host --work <ssh-host>     # work auth
~/.dotfiles/bin/install-ubuntu-agent-on-host --personal --work <ssh-host>
```

Each flag selects one account and nothing else; typing both installs both, and
neither means personal. Keys are discovered from `~/.ssh`
(`id_ed25519_github_personal` and `id_ed25519`), and `--personal-key PATH` /
`--work-key PATH` override that discovery and select the account they name.

The script copies the selected private keys to the remote as
`~/.ssh/github-personal` and `~/.ssh/github-company` with strict file
permissions. `~/.ssh/id_ed25519` goes to personal whenever personal was
selected, so an ordinary `git@github.com:...` remote works without a custom host
alias; a work-only install gives that name to the work key instead. It never
stores keys in this repository and does not print key contents.

The remote installer installs Copilot skills from source repositories instead of
copying your local `~/.copilot` directories:

- universal custom skills from `git@github-personal:Iacob-Alexandru-Andrei/skills.git`
- God-specific skills from `git@github-personal:Iacob-Alexandru-Andrei/god-skills.git`
- academic skills from `https://github.com/Imbad0202/academic-research-skills.git`
- Superpowers from the official Copilot plugin marketplace:
  `superpowers@superpowers-marketplace`
- Ponytail from the Copilot plugin marketplace:
  `ponytail@ponytail`

The remote installer installs missing apt packages by default using
`sudo apt-get`. Add `--skip-apt` when you want to only report missing packages.
It installs Neovim 0.11+ with AstroNvim by default; add `--skip-neovim` to opt
out. It also installs `nvitop` and `bpytop` as user-space monitoring commands.

## On the remote machine

If dotfiles are already cloned on the remote:

```sh
~/.dotfiles/ubuntu-agent/install.sh --with-dotfiles
```

Omit `--with-dotfiles` to skip the normal zsh/tmux symlink setup.

## What it configures

- Ubuntu package checks for common tools such as `git`, `curl`, `jq`, `ripgrep`,
  `fd`, `tmux`, `zsh`, `nvim`, `python3`, `pipx`, and `npm`
- user-space `uv==0.11.2`
- user-space `pre-commit`
- user-space `wandb`
- user-space `nvitop`
- user-space `bpytop`
- Neovim 0.11+ with AstroNvim, unless an existing non-owned `~/.config/nvim` is present
- interactive bash sessions hand off to zsh automatically
- GitHub Copilot CLI via npm when `copilot` is missing and `npm` is available
- Copilot skills from source repositories plus Superpowers and Ponytail from
  Copilot plugin marketplaces
- SSH defaults for ordinary `github.com` remotes plus host aliases
  `github-personal` and `github-company`
- a healthcheck for `gh`, `az`, `amlt`, `nvitop`, `bpytop`, keys, skills, and `WANDB_API_KEY`

Authentication remains manual: run `gh auth login`, `copilot login`, `az login`,
and `amlt project checkout ...` as needed.
