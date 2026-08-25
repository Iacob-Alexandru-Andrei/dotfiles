#!/bin/sh
set -eu

with_dotfiles=0
install_apt=1
install_editors=1
install_omp_harness=1
dotfiles_args=''
omp_repo_url='git@github-personal:Iacob-Alexandru-Andrei/omp.git'
npm_mirror='https://packagefeedproxy.microsoft.io/npm/'

usage() {
  cat <<'EOF' >&2
usage: ubuntu-agent/install.sh [--with-dotfiles] [--install-apt] [--skip-apt] [--skip-editors] [--skip-omp] [--minimal] [--no-packages]

Sets up an Ubuntu host for agent/Copilot work without changing the default
dotfiles installer. Existing tools and config are detected and left in place.
Missing apt packages are installed by default. Use --skip-apt to only report
missing packages.

Editors: helix is installed and made the default (EDITOR/VISUAL) because it is
post-modal and behaves inside omp's Ctrl+G external-editor path; fresh is
installed alongside it and is never made the default. --skip-editors skips both.

The omp harness is installed from its own repository, which is what provisions
the language servers; --skip-omp skips it, and skipping it also skips wiring
those servers into fresh.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-dotfiles)
      with_dotfiles=1
      shift
      ;;
    --install-apt)
      install_apt=1
      shift
      ;;
    --skip-apt)
      install_apt=0
      shift
      ;;
    --skip-editors)
      install_editors=0
      shift
      ;;
    --skip-omp)
      install_omp_harness=0
      shift
      ;;
    --minimal)
      dotfiles_args="$dotfiles_args --minimal"
      install_editors=0
      shift
      ;;
    --no-packages)
      dotfiles_args="$dotfiles_args --no-packages"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

info() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_ubuntu() {
  if [ ! -r /etc/os-release ]; then
    info "warning: cannot identify OS; continuing conservatively"
    return 0
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ]; then
    printf 'ubuntu-agent setup targets Ubuntu; found ID=%s\n' "${ID:-unknown}" >&2
    exit 1
  fi
}

# PATH and the editor defaults, written where a NON-INTERACTIVE ssh command will see them.
# ~/.profile alone is not enough and that is the whole point of this function: `ssh host
# 'command -v uv'` runs no login shell and sources no profile, so every user-space install
# here -- uv, pre-commit, wandb, nvitop, bpytop, copilot, fresh -- was invisible to exactly
# the caller that matters, an agent driving the box over ssh. Verified on the live host:
# `command -v uv` empty, `bash -lc 'command -v uv'` found it.
#
# ~/.bashrc is read by non-interactive ssh commands, and ~/.zshenv is read by zsh on
# EVERY invocation. Writing all three is what makes the PATH true from any entry point.
#
# The block is PREPENDED, not appended, and that is the whole trick. Ubuntu's stock
# ~/.bashrc opens with `case $- in *i*) ;; *) return;; esac` -- a non-interactive shell
# returns at line 8. Appending put this block at line 131, which such a shell never
# reaches: `ssh host 'command -v fresh'` found nothing while the binary sat in
# ~/.local/bin and the healthcheck (running under the installer's own exported PATH)
# reported it present. Prepending puts it ahead of that return.
ensure_path_block() {
  begin='# BEGIN dotfiles ubuntu-agent path'
  end='# END dotfiles ubuntu-agent path'

  export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
  # Helix is the default editor everywhere: EDITOR for anything that reads it, VISUAL for
  # the richer callers, and both are what omp's Ctrl+G external-editor path consults.
  #
  # Helix rather than fresh because of that path specifically. Helix is post-modal: it
  # opens on a file, edits it, writes it and exits, which is the entire contract a
  # `$VISUAL` invocation has. Fresh is a visual editor that does not behave inside omp,
  # so naming it here made Ctrl+G the broken key. Fresh is still installed and `fresh`
  # still runs it -- it is simply not what other programs hand a buffer to.
  if have hx; then
    export EDITOR=hx
    export VISUAL=hx
  elif have fresh; then
    export EDITOR=fresh
    export VISUAL=fresh
  fi

  for profile_file in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshenv"; do
    touch "$profile_file"

    # Strip any previous copy wherever it landed, then put one at the top. This also
    # repairs hosts that already carry an appended, unreachable block.
    next="$profile_file.dotfiles.$$"
    trap 'rm -f "$next"' EXIT INT TERM
    {
      printf '%s\n' "$begin"
      printf 'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"\n'
      # Resolved when the shell starts rather than now. This function runs BEFORE
      # `install_helix`, so a check made here would answer for a machine that does not
      # exist yet; and a bare `EDITOR=hx` would name a program that is not there if that
      # install later fails. Fresh is the fallback, so the worst case is the old default
      # rather than a shell whose $EDITOR cannot run.
      printf 'if command -v hx >/dev/null 2>&1; then\n'
      printf '  export EDITOR=hx\n'
      printf '  export VISUAL=hx\n'
      printf 'elif command -v fresh >/dev/null 2>&1; then\n'
      printf '  export EDITOR=fresh\n'
      printf '  export VISUAL=fresh\n'
      printf 'fi\n'
      printf '%s\n\n' "$end"
      awk -v b="$begin" -v e="$end" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip { print }' "$profile_file"
    } > "$next"
    mv "$next" "$profile_file"
  done
}

apt_install_missing() {
  have apt-get || return 0

  missing=''
  for spec in \
    git:git \
    curl:curl \
    jq:jq \
    rg:ripgrep \
    fdfind:fd-find \
    tmux:tmux \
    zsh:zsh \
    xz:xz-utils \
    unzip:unzip \
    python3:python3 \
    pipx:pipx \
    npm:npm
  do
    cmd=${spec%%:*}
    pkg=${spec#*:}
    if ! have "$cmd"; then
      missing="$missing $pkg"
    fi
  done

  [ -n "$missing" ] || return 0

  if [ "$install_apt" -eq 0 ]; then
    info "missing Ubuntu packages:$missing"
    info "rerun with --install-apt to install missing apt packages"
    return 0
  fi

  have sudo || {
    info "sudo not found; skipping apt package installation"
    return 0
  }

  info "installing missing Ubuntu packages:$missing"
  sudo apt-get update
  # shellcheck disable=SC2086
  sudo apt-get install -y $missing
}

pipx_package_installed() {
  package_name=$1

  have pipx || return 1
  python3 -m pipx list --short 2>/dev/null | grep -Eq "^${package_name}( |$)"
}

install_uv() {
  if have uv || pipx_package_installed uv; then
    return 0
  fi

  info "installing uv in user space"
  if have pipx; then
    python3 -m pipx install 'uv==0.11.2' || python3 -m pip install --user 'uv==0.11.2'
  else
    python3 -m pip install --user 'uv==0.11.2'
  fi
}

install_pre_commit() {
  if have pre-commit || pipx_package_installed pre-commit; then
    return 0
  fi

  info "installing pre-commit in user space"
  if have pipx; then
    python3 -m pipx install pre-commit || python3 -m pip install --user pre-commit
  else
    python3 -m pip install --user pre-commit
  fi
}

install_wandb() {
  if have wandb || pipx_package_installed wandb; then
    return 0
  fi

  info "installing wandb in user space"
  if have pipx; then
    python3 -m pipx install wandb || python3 -m pip install --user wandb
  else
    python3 -m pip install --user wandb
  fi
}

install_nvitop() {
  if have nvitop || pipx_package_installed nvitop; then
    return 0
  fi

  info "installing nvitop in user space"
  if have pipx; then
    python3 -m pipx install nvitop || python3 -m pip install --user nvitop
  else
    python3 -m pip install --user nvitop
  fi
}

install_bpytop() {
  if have bpytop || pipx_package_installed bpytop; then
    return 0
  fi

  info "installing bpytop in user space"
  if have pipx; then
    python3 -m pipx install bpytop || python3 -m pip install --user bpytop
  else
    python3 -m pip install --user bpytop
  fi
}

# Fresh is the editor this setup installs and the one it makes default. The Linux
# "universal build" is a single static musl binary under ~/.local, owned by the user: no
# root, no distro package, and it updates itself with `fresh --cmd update`. That is the
# only Linux install of it that can replace itself, which is what makes it a sane choice
# on a box nobody administers.
install_fresh() {
  if [ "$install_editors" -eq 0 ]; then
    return 0
  fi

  have curl || {
    info "curl not found; cannot install fresh"
    return 1
  }

  if have fresh; then
    info "fresh present: $(fresh --version 2>/dev/null || echo unknown)"
    return 0
  fi

  # FRESH_NO_DESKTOP because this is a server: the desktop entry and icon theme the
  # installer would copy into ~/.local/share have nothing to show them.
  info "installing fresh"
  FRESH_NO_DESKTOP=1 curl -fsSL \
    https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh |
    sh

  hash -r 2>/dev/null || true

  have fresh || {
    info "fresh install did not produce a usable binary"
    return 1
  }
}

# Helix is what EDITOR and VISUAL name, so this is the editor every other program hands a
# buffer to -- git, and omp's Ctrl+G among them. It earns that by being post-modal: it
# opens on a path, writes, and exits, which is the whole contract those callers rely on.
install_helix() {
  if [ "$install_editors" -eq 0 ]; then
    return 0
  fi

  if have hx; then
    info "helix present: $(hx --version 2>/dev/null || echo unknown)"
    return 0
  fi

  # Ubuntu 24.04 has no helix package in the default archive; the PPA is the maintained
  # route and the release tarball is the fallback when adding a PPA is not possible.
  if have add-apt-repository && [ "$install_apt" -eq 1 ] && have sudo; then
    sudo add-apt-repository -y ppa:maveonair/helix-editor >/dev/null 2>&1 || true
    sudo apt-get update -qq >/dev/null 2>&1 || true
    if sudo apt-get install -y -qq helix >/dev/null 2>&1; then
      hash -r 2>/dev/null || true
      have hx && return 0
    fi
  fi

  have curl || {
    info "curl not found; skipping helix"
    return 0
  }

  helix_arch=$(uname -m)
  case $helix_arch in
    x86_64) helix_asset='x86_64-linux' ;;
    aarch64 | arm64) helix_asset='aarch64-linux' ;;
    *)
      info "no helix build for $helix_arch; skipping"
      return 0
      ;;
  esac

  helix_url=$(
    curl -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest 2>/dev/null |
      sed -n "s/.*\"browser_download_url\": *\"\([^\"]*${helix_asset}\.tar\.xz\)\".*/\1/p" |
      head -1
  )

  [ -n "$helix_url" ] || {
    info "could not resolve a helix release for $helix_asset; skipping"
    return 0
  }

  helix_tmp=$(mktemp -d)
  if curl -fsSL "$helix_url" -o "$helix_tmp/helix.tar.xz" &&
    tar -xJf "$helix_tmp/helix.tar.xz" -C "$helix_tmp" 2>/dev/null; then
    helix_root=$(find "$helix_tmp" -maxdepth 1 -type d -name 'helix-*' | head -1)
    if [ -n "$helix_root" ] && [ -x "$helix_root/hx" ]; then
      mkdir -p "$HOME/.local/bin" "$HOME/.config/helix"
      cp "$helix_root/hx" "$HOME/.local/bin/hx"
      chmod 755 "$HOME/.local/bin/hx"
      # hx resolves its grammars and themes relative to this directory, so the runtime
      # has to travel with the binary or every buffer opens unhighlighted.
      [ -d "$helix_root/runtime" ] && cp -R "$helix_root/runtime" "$HOME/.config/helix/"
    fi
  fi
  rm -rf "$helix_tmp"

  hash -r 2>/dev/null || true
  have hx || info "helix install did not produce a usable binary"
}

# Ubuntu ships fd as `fdfind` because the name `fd` was taken. Everything that expects
# ripgrep-adjacent tooling -- including agents -- calls `fd`, and the README promises it,
# so the shim is what makes the promise true. A real `fd` from elsewhere is left alone.
ensure_fd_shim() {
  have fd && return 0
  have fdfind || return 0

  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  hash -r 2>/dev/null || true
}

# Global lint/type defaults, so a directory with no config of its own is still checked
# properly rather than at each tool's quiet built-in floor. Ruff's own default is four
# rule families (E4, E7, E9, F); this raises it to `select = ["ALL"]` with a short,
# argued ignore list, which is the shape rqgm uses.
#
# A project ALWAYS wins. Ruff resolves the nearest `ruff.toml`/`pyproject.toml` by
# walking up from the file and only falls back to the user config when that walk finds
# nothing -- verified both ways: in an isolated temp dir ruff reports
# `Settings path: ~/.config/ruff/ruff.toml`, and with a local `ruff.toml` present it
# reports that one instead.
install_lint_defaults() {
  ruff_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ruff"
  mkdir -p "$ruff_cfg_dir"
  cp "$repo_dir/lint/ruff/ruff.toml" "$ruff_cfg_dir/ruff.toml"
  info "ruff defaults installed at $ruff_cfg_dir/ruff.toml"

  # NO GLOBAL PYRIGHT CONFIG, and the reason is measured rather than cautious.
  #
  # A `pyrightconfig.json` at $HOME does govern projects that carry none -- but it
  # also OUTRANKS `[tool.pyright]` in a project that does, because pyright prefers the
  # standalone file wherever it finds one on the walk up. So it silently replaced the
  # `include`/`exclude` of every repository under home, and pyright then walked trees
  # those configs exist to keep it out of.
  #
  # Measured in repos/omp, whose pre-commit runs pyright with `pass_filenames: false`:
  # with the file at $HOME the hook did not finish in 300s; with it removed, 1s and
  # exit 0. That is the whole case against it.
  #
  # Ruff is different and keeps its global default: `~/.config/ruff/ruff.toml` is a
  # user-level fallback ruff consults only when the walk finds no project config, so it
  # cannot outrank one. Pyright has no equivalent -- `pyright --help` offers only
  # `-p FILE`, and `pyright-langserver` takes no config flag at all -- so pyright is
  # left at its own defaults until OMP answers the server's `workspace/configuration`
  # request. Verified from three sides: a settings block in lsp.json is ignored,
  # `initializationOptions` at initialize is ignored, and the CLI has no user-level
  # config path. `lint/pyright/pyrightconfig.json` is kept as the reference a project
  # can adopt deliberately, NOT as a global fallback.

  # ty (Astral) IS installed with a global config, because it has the exact property
  # pyright lacks: `$XDG_CONFIG_HOME/ty/ty.toml` applies only where the project walk
  # finds nothing. Measured against the file this actually ships, not a scratch one:
  # on an unresolvable import it alone reports `warning` and exits 0, and a project
  # adding `[tool.ty.rules] unresolved-import = "error"` reports `error` and exits 1.
  # The project's answer replaces this one -- a fallback, not an override, which is the
  # whole distinction the pyright paragraph above turns on.
  #
  # The binary itself is pinned in the omp harness manifest and lives at
  # `$PI_CODING_AGENT_DIR/tools/env/bin/ty`, never on PATH: a harness that installs tools
  # globally shadows whatever the user already had and outlives its own uninstall. So it
  # is invoked by that absolute path -- `ty check` as a bare word will not find it, by
  # design, and nothing here puts `tools/env/bin` on PATH.
  #
  # Not registered as an LSP BY DEFAULT. omp's lsp.json carries a ONE SERVER PER JOB
  # rule and pyright already holds the type-intelligence job for Python; enabling both
  # would put two indexers and two sets of type diagnostics on the same file.
  #
  # But the swap is a supported, per-project mechanism rather than a hand-edit of a
  # generated file: `<project>/.omp/lsp.json` outranks the agent directory's
  # (omp://lsp-config.md:29-30). The TEMPLATE below disables pyright and enables ty
  # together, which is the only combination that respects the rule. Verified end to end
  # before it was shipped: with it in place `lsp status` reports `ty (ready)`, pyright
  # never spawns, and diagnostics arrive tagged `[ty]`.
  #
  # It is rendered INTO THE CONFIG DIRECTORY, never into a project. Placing it under
  # some checkout would be this installer choosing a per-project policy it has no
  # business choosing; copying it is the deliberate act that selects ty there.
  #
  # Rendered rather than copied because the command must be absolute: ty is off PATH
  # by design, so a bare `ty` resolves for nobody and the server silently never starts.
  # The tracked file carries a placeholder, so no machine's `$HOME` is committed and the
  # substitution below is what makes it correct on this one.
  ty_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ty"
  mkdir -p "$ty_cfg_dir"
  cp "$repo_dir/lint/ty/ty.toml" "$ty_cfg_dir/ty.toml"
  info "ty defaults installed at $ty_cfg_dir/ty.toml"

  # Rendered with python's json rather than `sed`: the replacement is a filesystem path,
  # and `sed` would take `&` in it as "the whole match" and `#` as the delimiter. A home
  # directory containing either is unusual, not impossible, and the failure would be a
  # silently malformed config -- which presents as "the server just never starts".
  # pydoclint's global fallback. It has no user-level config discovery of its own --
  # `--config` FORCES a file and a bare run discovers the project's. Measured both ways
  # against a project saying `skip-checking-short-docstrings = true`: forced global
  # reports 4 findings, discovered project reports 0. So the omp-side server passes
  # `--config` only where nothing above the file configures pydoclint, and this is the
  # file it passes. The setting that matters is `skip-checking-short-docstrings = false`:
  # left at its default a one-line docstring exempts the whole function, which is how an
  # undocumented `def f(a, b)` passes a documentation gate.
  pydoclint_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pydoclint"
  mkdir -p "$pydoclint_cfg_dir"
  cp "$repo_dir/lint/pydoclint/pyproject.toml" "$pydoclint_cfg_dir/pyproject.toml"
  info "pydoclint defaults installed at $pydoclint_cfg_dir/pyproject.toml"

  ty_lsp_src="$repo_dir/lint/ty/lsp-ty.json"
  ty_bin="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}/tools/env/bin/ty"
  if [ -f "$ty_lsp_src" ] && have python3; then
    python3 - "$ty_lsp_src" "$ty_cfg_dir/lsp-ty.json" "$ty_bin" <<'PY'
import json
import pathlib
import sys

src, dest, ty_bin = (pathlib.Path(a) for a in sys.argv[1:4])
config = json.loads(src.read_text(encoding="utf-8"))
config["servers"]["ty"]["command"] = str(ty_bin)
dest.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY
    info "ty LSP template rendered at $ty_cfg_dir/lsp-ty.json (copy to <project>/.omp/lsp.json to select ty there)"
  fi
}

# The omp harness. This is the layer that actually brings language servers to the box:
# the sandbox had NONE before this ran -- no pyright, ruff, marksman, yaml, bash, docker
# or json server -- because nothing here installed any and nothing checked. omp's own
# bin/install.sh provisions them under ~/.omp/agent/tools, so the correct fix is to run
# it rather than to re-derive its list here and let the two drift.
install_omp() {
  if [ "$install_omp_harness" -eq 0 ]; then
    return 0
  fi

  have git || {
    info "git not found; cannot install omp"
    return 1
  }

  omp_dir="$HOME/.omp/src"

  if [ -d "$omp_dir/.git" ]; then
    git -C "$omp_dir" remote set-url origin "$omp_repo_url"
    git -C "$omp_dir" fetch --quiet origin
    # Matching the dotfiles rule next door: a hand-edit is someone's work, so a dirty
    # checkout is reported and left alone rather than reset out from under them.
    omp_dirty=$(git -C "$omp_dir" status --porcelain)
    if [ -n "$omp_dirty" ]; then
      info "local changes in $omp_dir; skipping update"
    else
      git -C "$omp_dir" pull --ff-only --quiet || info "omp update did not fast-forward"
    fi
  else
    mkdir -p "$(dirname -- "$omp_dir")"
    git clone --quiet "$omp_repo_url" "$omp_dir" || {
      info "omp clone failed; skipping harness install"
      return 0
    }
  fi

  [ -x "$omp_dir/bin/install.sh" ] || {
    info "omp checkout has no bin/install.sh; skipping"
    return 0
  }

  # The launcher is linked BEFORE the harness install and independently of it. It is a
  # checked-out file, not something the installer produces, and gating it on that exit
  # code is what left the live host with every language server present and `omp` not a
  # command -- the installer had returned nonzero after doing its work.
  if [ -x "$omp_dir/bin/omp" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$omp_dir/bin/omp" "$HOME/.local/bin/omp"
  fi

  info "installing omp harness and its language servers"
  ( cd "$omp_dir" && ./bin/install.sh ) || {
    info "omp install.sh failed; language servers may be missing"
    return 0
  }

  hash -r 2>/dev/null || true
}

# Fresh speaks LSP, and omp has just provisioned nine working servers under
# ~/.omp/agent/tools. Pointing fresh at the same binaries means one set of servers rather
# than a second copy that ages differently -- the config is generated FROM omp's
# lsp.json, so adding a server there is enough and this file follows.
#
# Entries whose command does not resolve are skipped rather than written: fresh reports a
# failing server per buffer, and a config full of dead commands is worse than a short one.
wire_fresh_lsp() {
  if [ "$install_editors" -eq 0 ] || [ "$install_omp_harness" -eq 0 ]; then
    return 0
  fi

  omp_lsp="$HOME/.omp/agent/lsp.json"
  [ -f "$omp_lsp" ] || {
    info "no omp lsp.json; skipping fresh LSP wiring"
    return 0
  }
  have python3 || return 0

  mkdir -p "$HOME/.config/fresh"
  python3 - "$omp_lsp" "$HOME/.config/fresh/config.json" <<'PY'
import json
import os
import sys

omp_lsp, fresh_cfg = sys.argv[1], sys.argv[2]

# Which omp server answers for which fresh language id. Servers omp declares but does not
# provision (pylsp, basedpyright: null command) fall out on the resolve check below.
LANGUAGES = {
    "pyright": ("python", ["--stdio"], ["pyproject.toml", "pyrightconfig.json", ".git"]),
    "ruff": ("python", ["server"], ["pyproject.toml", "ruff.toml", ".git"]),
    "marksman": ("markdown", ["server"], [".git"]),
    "yamlls": ("yaml", ["--stdio"], [".git"]),
    "bashls": ("bash", ["start"], [".git"]),
    "dockerls": ("dockerfile", ["--stdio"], [".git"]),
    "vscode-json-language-server": ("json", ["--stdio"], [".git"]),
}

with open(omp_lsp, encoding="utf-8") as fh:
    servers = json.load(fh)
servers = servers.get("servers", servers)

by_language = {}
for name, spec in servers.items():
    if name.startswith("//") or name not in LANGUAGES:
        continue
    command = spec.get("command") if isinstance(spec, dict) else spec
    # A declared-but-unprovisioned server has a null command; a stale one points at a path
    # that no longer exists. Both are skipped, because fresh surfaces a dead server as a
    # per-buffer error rather than silence.
    if not command or not os.path.exists(command):
        continue
    language, args, roots = LANGUAGES[name]
    by_language.setdefault(language, []).append(
        {
            "name": name,
            "command": command,
            "args": args,
            "enabled": True,
            "auto_start": True,
            "root_markers": roots,
        }
    )

if not by_language:
    print("  no resolvable omp language servers; fresh LSP config unchanged")
    raise SystemExit(0)

config = {}
if os.path.exists(fresh_cfg):
    try:
        with open(fresh_cfg, encoding="utf-8") as fh:
            config = json.load(fh)
    except (OSError, ValueError):
        config = {}

# Replace only the languages this script owns. Anything else the user configured in
# fresh -- themes, keymaps, other servers -- is left exactly as it was.
lsp = config.get("lsp")
if not isinstance(lsp, dict):
    lsp = {}
lsp.update(by_language)
config["lsp"] = lsp

tmp = fresh_cfg + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2)
    fh.write("\n")
os.replace(tmp, fresh_cfg)

print("  fresh language servers: " + ", ".join(sorted(
    s["name"] for group in by_language.values() for s in group
)))
PY
}

install_github_cli() {
  if have gh; then
    return 0
  fi

  if [ "$install_apt" -eq 0 ]; then
    info "gh not found; rerun without --skip-apt to install GitHub CLI"
    return 0
  fi

  have sudo || {
    info "sudo not found; skipping GitHub CLI installation"
    return 0
  }

  have curl || {
    info "curl not found; skipping GitHub CLI installation"
    return 0
  }

  info "installing GitHub CLI"
  sudo mkdir -p /usr/share/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

  arch=$(dpkg --print-architecture)
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$arch" |
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  sudo apt-get update
  sudo apt-get install -y gh
}

clone_or_update_repo() {
  repo_url=$1
  target_dir=$2

  if [ ! -d "$target_dir/.git" ]; then
    mkdir -p "$(dirname -- "$target_dir")"
    git clone "$repo_url" "$target_dir"
    return 0
  fi

  git -C "$target_dir" remote set-url origin "$repo_url"
  git -C "$target_dir" pull --ff-only
}

# npm on a corporate network cannot reach registry.npmjs.org: from this machine it
# answers nothing at all while the internal mirror answers. The mirror is machine-local
# configuration rather than a fact about the package, so it is only set when it actually
# responds -- a hardcoded internal URL would break every clone outside the network.
#
# TWO-WAY, and that is the part this used to get wrong. It returned early whenever npm
# already named the mirror, so a machine that later moved off the corporate network kept
# pointing at a proxy it could no longer see, and every `npm install` there failed with
# no explanation. The public registry is checked FIRST and wins whenever it answers,
# which makes leaving the network self-correcting rather than a support call.
#
# A HEAD that returns any status counts as an answer: the mirror replies `405 Method Not
# Allowed` to its own root, which means reachable-and-not-serving-that-verb. `-f` would
# read that as a failure, so it is deliberately absent here.
ensure_npm_registry() {
  have npm || return 0
  have curl || return 0

  npm_current=$(npm config get registry 2>/dev/null)
  case $npm_current in
    *registry.npmjs.org* | '' | undefined | null | *packagefeedproxy.microsoft.io*) ;;
    # Some third feed, deliberately configured. Not ours to override.
    *) return 0 ;;
  esac

  for npm_candidate in 'https://registry.npmjs.org/' "$npm_mirror"; do
    if curl -sS -o /dev/null -I --max-time 5 "$npm_candidate" 2>/dev/null; then
      case $npm_current in
        "$npm_candidate") return 0 ;;
      esac
      info "pointing npm at $npm_candidate (it answered; the other did not)"
      npm config set registry "$npm_candidate" >/dev/null
      return 0
    fi
  done
  # Neither answered. Leave whatever is configured, so the eventual failure names the
  # real network rather than a URL this function chose.
  return 0
}

install_copilot_cli() {
  # The registry is configured before the early return on purpose. It is a property of the
  # machine, not of this one install: with copilot already present the old ordering
  # returned first and left npm pointed at a registry that does not answer here, so every
  # later `npm install`/`npm update` on that box failed. Verified live -- the run logged
  # the mirror while `npm config get registry` still read registry.npmjs.org.
  ensure_npm_registry

  if have copilot; then
    return 0
  fi

  if ! have npm; then
    if [ "$install_apt" -eq 1 ]; then
      apt_install_missing
    fi

    if ! have npm; then
      info "npm not found; skipping Copilot CLI install"
      return 0
    fi
  fi


  info "installing GitHub Copilot CLI with npm user prefix"
  mkdir -p "$HOME/.npm-global"
  npm config set prefix "$HOME/.npm-global" >/dev/null
  npm install -g @github/copilot
}

link_skill_dir() {
  source_dir=$1
  skill_name=$(basename -- "$source_dir")
  target_dir="$HOME/.copilot/skills/$skill_name"

  [ -f "$source_dir/SKILL.md" ] || return 0

  if [ -L "$target_dir" ]; then
    current_link=$(readlink "$target_dir")
    if [ "$current_link" = "$source_dir" ]; then
      return 0
    fi

    rm "$target_dir"
  elif [ -e "$target_dir" ]; then
    info "skipping existing Copilot skill: $target_dir"
    return 0
  fi

  ln -s "$source_dir" "$target_dir"
}

install_skill_links_from_repo() {
  skill_repo_dir=$1
  skills_root=$2

  [ -d "$skills_root" ] || return 0

  find "$skills_root" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | while IFS= read -r skill_file; do
    link_skill_dir "$(dirname -- "$skill_file")"
  done
}

install_copilot_marketplace_plugin() {
  plugin_label=$1
  marketplace_repo=$2
  plugin_ref=$3
  update_name=$4

  if ! have copilot; then
    info "copilot not found; skipping $plugin_label plugin install"
    return 0
  fi

  info "installing $plugin_label from official Copilot plugin marketplace"
  copilot plugin marketplace add "$marketplace_repo" >/dev/null 2>&1 || true
  copilot plugin install "$plugin_ref" >/dev/null 2>&1 ||
    copilot plugin update "$update_name" >/dev/null 2>&1 ||
    info "$plugin_label plugin install/update did not complete; run: copilot plugin install $plugin_ref"
}

install_superpowers_plugin() {
  install_copilot_marketplace_plugin \
    "Superpowers" \
    "obra/superpowers-marketplace" \
    "superpowers@superpowers-marketplace" \
    "superpowers"
}

install_ponytail_plugin() {
  install_copilot_marketplace_plugin \
    "Ponytail" \
    "DietrichGebert/ponytail" \
    "ponytail@ponytail" \
    "ponytail"
}

install_copilot_skills() {
  source_root="$HOME/.local/share/dotfiles-agent"
  custom_skills_repo="$source_root/skills"
  god_skills_repo="$source_root/god-skills"
  academic_skills_repo="$source_root/academic-research-skills"

  mkdir -p "$HOME/.copilot/skills" "$source_root"

  clone_or_update_repo \
    "git@github-personal:Iacob-Alexandru-Andrei/skills.git" \
    "$custom_skills_repo" ||
    info "custom skills repo clone failed; check github-personal SSH auth"

  clone_or_update_repo \
    "git@github-personal:Iacob-Alexandru-Andrei/god-skills.git" \
    "$god_skills_repo" ||
    info "God-specific skills repo clone failed; check github-personal SSH auth"

  clone_or_update_repo \
    "https://github.com/Imbad0202/academic-research-skills.git" \
    "$academic_skills_repo"

  install_skill_links_from_repo "$custom_skills_repo" "$custom_skills_repo/memory/skills"
  install_skill_links_from_repo "$god_skills_repo" "$god_skills_repo/memory/skills"
  install_skill_links_from_repo "$academic_skills_repo" "$academic_skills_repo"
  install_superpowers_plugin
  install_ponytail_plugin

  info "Copilot skills directory: $HOME/.copilot/skills"
}

install_github_hosts() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  config_file="$HOME/.ssh/config"
  begin='# BEGIN dotfiles ubuntu-agent github hosts'
  end='# END dotfiles ubuntu-agent github hosts'

  touch "$config_file"
  chmod 600 "$config_file"

  if grep -q "$begin" "$config_file"; then
    tmp_file=$(mktemp)
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      !skip { print }
    ' "$config_file" > "$tmp_file"
    mv "$tmp_file" "$config_file"
    chmod 600 "$config_file"
  fi

  cat >> "$config_file" <<'EOF'

# BEGIN dotfiles ubuntu-agent github hosts
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host github-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/github-personal
  IdentitiesOnly yes

Host github-company
  HostName github.com
  User git
  IdentityFile ~/.ssh/github-company
  IdentitiesOnly yes
# END dotfiles ubuntu-agent github hosts
EOF
}

ensure_default_identity() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  # Whoever the driver copied wins; this only fills a vacancy. Personal first, matching
  # the driver: personal is always fine, so it is the safe holder of an unqualified
  # git@github.com. Work only takes it on a host where personal was never installed.
  for account in github-personal github-company; do
    [ -f "$HOME/.ssh/$account" ] || continue

    if [ ! -e "$HOME/.ssh/id_ed25519" ] && [ ! -L "$HOME/.ssh/id_ed25519" ]; then
      ln -s "$HOME/.ssh/$account" "$HOME/.ssh/id_ed25519"
    fi

    if [ -f "$HOME/.ssh/$account.pub" ] &&
      [ ! -e "$HOME/.ssh/id_ed25519.pub" ] &&
      [ ! -L "$HOME/.ssh/id_ed25519.pub" ]; then
      ln -s "$HOME/.ssh/$account.pub" "$HOME/.ssh/id_ed25519.pub"
    fi

    return 0
  done
}

ensure_github_known_host() {
  known_hosts="$HOME/.ssh/known_hosts"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$known_hosts"
  chmod 600 "$known_hosts"

  if ssh-keygen -F github.com -f "$known_hosts" >/dev/null 2>&1; then
    return 0
  fi

  if ! have ssh-keyscan; then
    info "ssh-keyscan not found; skipping GitHub known_hosts setup"
    return 0
  fi

  info "adding github.com to known_hosts"
  ssh-keyscan github.com >> "$known_hosts" 2>/dev/null
}

run_dotfiles_install() {
  if [ "$with_dotfiles" -eq 0 ]; then
    return 0
  fi

  "$repo_dir/install.sh" $dotfiles_args
}

install_bash_zsh_handoff() {
  bashrc="$HOME/.bashrc"
  begin='# BEGIN dotfiles ubuntu-agent zsh handoff'
  end='# END dotfiles ubuntu-agent zsh handoff'

  touch "$bashrc"
  if grep -q "$begin" "$bashrc"; then
    return 0
  fi

  cat >> "$bashrc" <<'EOF'

# BEGIN dotfiles ubuntu-agent zsh handoff
case $- in
  *i*) ;;
  *) return ;;
esac

if [ -z "${DOTFILES_ZSH_HANDOFF:-}" ] && command -v zsh >/dev/null 2>&1; then
  export DOTFILES_ZSH_HANDOFF=1
  exec zsh
fi
# END dotfiles ubuntu-agent zsh handoff
EOF
}

healthcheck() {
  info ""
  info "ubuntu-agent healthcheck"
  # `fd` as well as `fdfind`: Ubuntu ships the binary as fd-find and the README promises
  # `fd`, so checking only the packaged name hid a gap the shim now closes.
  for cmd in git curl jq rg fd fdfind tmux zsh python3 uv pre-commit wandb nvitop bpytop npm copilot gh az amlt fresh hx omp; do
    if have "$cmd"; then
      printf '  ok      %s\n' "$cmd"
    else
      printf '  missing %s\n' "$cmd"
    fi
  done

  # The language servers, checked as files rather than as commands: they live under
  # ~/.omp/agent/tools and are launched by path, never from PATH. Nothing verified these
  # before, which is exactly how a box ends up with zero of them and a green healthcheck.
  if [ -f "$HOME/.omp/agent/lsp.json" ] && have python3; then
    python3 - "$HOME/.omp/agent/lsp.json" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    servers = json.load(fh)
servers = servers.get("servers", servers)

for name, spec in sorted(servers.items()):
    if name.startswith("//"):
        continue
    command = spec.get("command") if isinstance(spec, dict) else spec
    if not command:
        # Declared without a command: omp knows the server but does not provision it.
        print(f"  --      lsp {name} (not provisioned)")
    elif os.path.exists(command):
        print(f"  ok      lsp {name}")
    else:
        print(f"  missing lsp {name}")
PY
  else
    printf '  missing language servers (no omp lsp.json)\n'
  fi

  for alias in github.com github-personal github-company; do
    if ssh -G "$alias" >/dev/null 2>&1; then
      printf '  ok      ssh alias %s\n' "$alias"
    else
      printf '  missing ssh alias %s\n' "$alias"
    fi
  done

  for key_name in github-personal github-company id_ed25519; do
    if [ -f "$HOME/.ssh/$key_name" ]; then
      printf '  ok      ~/.ssh/%s exists\n' "$key_name"
    else
      printf '  missing ~/.ssh/%s\n' "$key_name"
    fi
  done

  if [ -n "${WANDB_API_KEY:-}" ]; then
    printf '  ok      WANDB_API_KEY is set\n'
  else
    printf '  missing WANDB_API_KEY\n'
  fi

  info ""
  info "Manual auth still required where needed: gh auth login, copilot login, az login, amlt project checkout."
}

require_ubuntu
ensure_path_block
apt_install_missing
# BEFORE anything that speaks to npm. `install_omp` provisions language servers from the
# registry and used to run four lines above the only caller of this function, so on a
# corporate box the servers were fetched from a registry that answers nothing and the
# mirror was selected afterwards, for the next run. Ordering was the whole bug.
ensure_npm_registry
install_uv
install_pre_commit
install_wandb
install_nvitop
install_bpytop
ensure_fd_shim
install_fresh
install_helix
install_omp
install_lint_defaults
wire_fresh_lsp
install_github_cli
install_copilot_cli
install_github_hosts
ensure_default_identity
ensure_github_known_host
install_copilot_skills
run_dotfiles_install
install_bash_zsh_handoff
healthcheck
