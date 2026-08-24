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

## Reaching the other sandboxes

`--mesh` is orthogonal to the account flags: they decide which GitHub the
remote signs as, `--mesh` decides whether it can `ssh` anywhere itself. An agent
launched on a sandbox could not previously reach its peers -- both the key and
the host aliases live only on your laptop.

```sh
~/.dotfiles/bin/install-ubuntu-agent-on-host --personal --work --mesh <ssh-host>
```

It copies the key the sandboxes accept to `~/.ssh/sandbox-mesh` (discovered as
`~/.ssh/id_rsa`, overridable with `--mesh-key PATH`) and writes every `sandbox*`
block from your `~/.ssh/config` into the remote's, pointed at that key with
`IdentitiesOnly yes`.

Two details are load-bearing:

- **Only `sandbox*` hosts are carried.** Other entries authenticate with keys
  that mean something else on the remote -- `mac-mini-server` uses
  `id_ed25519`, which there is a GitHub key -- so meshing them would break them.
- **The block is written first, not appended.** `ssh` takes the first value it
  sees for `HostName` and `User`, so a hand-added `Host sandbox_2` earlier in
  the file would decide where connections go. Hand-added blocks are left in
  place, outranked rather than deleted.

Re-running replaces the block between its markers rather than stacking copies,
and the file is renamed into place so an interrupted run cannot truncate it.

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
It also installs `nvitop` and `bpytop` as user-space monitoring commands.

### Editors

[Fresh](https://github.com/sinelaw/fresh) is the editor this installs and the
one it makes default: `EDITOR` and `VISUAL` both point at it, which is also what
omp reads for its external-editor binding. On Linux it is a single static musl
binary under `~/.local`, owned by you, needing no root and updating itself with
`fresh --cmd update`.

Helix is installed beside it and is deliberately never made the default -- `hx`
is there when you want it. `--skip-editors` skips both.

Neovim and AstroNvim are no longer installed.

### Language servers

The omp harness is installed from its own repository, and it is what provisions
the language servers: pyright, ruff, marksman, yaml, bash, docker, and json.
They are then wired into fresh automatically, generated from omp's own
`lsp.json` so the two cannot drift -- add a server there and fresh picks it up
on the next run. Servers omp declares but does not provision are skipped rather
than written, because a config naming a missing binary shows up as a per-buffer
error. `--skip-omp` skips the harness and the wiring together.

## On the remote machine

If dotfiles are already cloned on the remote:

```sh
~/.dotfiles/ubuntu-agent/install.sh --with-dotfiles
```

Omit `--with-dotfiles` to skip the normal zsh/tmux symlink setup.

## What it configures

- Ubuntu package checks for common tools such as `git`, `curl`, `jq`, `ripgrep`,
  `fd`, `tmux`, `zsh`, `python3`, `pipx`, and `npm`
- `fd` as a name: Ubuntu ships the binary as `fdfind`, so a shim is linked into
  `~/.local/bin`
- user-space `uv==0.11.2`
- user-space `pre-commit`
- user-space `wandb`
- user-space `nvitop`
- user-space `bpytop`
- fresh as the default editor, and helix alongside it
- the omp harness and its seven language servers, wired into fresh
- `PATH`, `EDITOR`, and `VISUAL` written to `~/.profile`, `~/.bashrc`, and
  `~/.zshenv`, so a non-interactive `ssh host 'command -v uv'` finds what was
  installed. Writing only `~/.profile` left every user-space install invisible
  to exactly the caller that matters -- an agent driving the box over ssh.
- interactive bash sessions hand off to zsh automatically
- GitHub Copilot CLI via npm when `copilot` is missing and `npm` is available
- Copilot skills from source repositories plus Superpowers and Ponytail from
  Copilot plugin marketplaces
- SSH defaults for ordinary `github.com` remotes plus host aliases
  `github-personal` and `github-company`
- a healthcheck for the tools above, every language server, keys, skills, and
  `WANDB_API_KEY`

Authentication remains manual: run `gh auth login`, `copilot login`, `az login`,
and `amlt project checkout ...` as needed.
