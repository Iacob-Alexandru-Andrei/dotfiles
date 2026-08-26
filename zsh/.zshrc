# Start configuration added by Zim Framework install {{{
#
# User configuration sourced by interactive shells
#

# -----------------
# Zsh configuration
# -----------------

#
# History
#

# Remove older command from the history if a duplicate is to be added.
setopt HIST_IGNORE_ALL_DUPS

#
# Input/output
#

# Set editor default keymap to emacs (`-e`) or vi (`-v`)
bindkey -e

# Prompt for spelling correction of commands.
#setopt CORRECT

# Customize spelling correction prompt.
#SPROMPT='zsh: correct %F{red}%R%f to %F{green}%r%f [nyae]? '

# Remove path separator from WORDCHARS.
WORDCHARS=${WORDCHARS//[\/]}

# --------------------
# Module configuration
# --------------------

#
# git
#

# Set a custom prefix for the generated aliases. The default prefix is 'G'.
#zstyle ':zim:git' aliases-prefix 'g'

#
# input
#

# Append `../` to your input for each `.` you type after an initial `..`
#zstyle ':zim:input' double-dot-expand yes

#
# termtitle
#

# Set a custom terminal title format using prompt expansion escape sequences.
# See http://zsh.sourceforge.net/Doc/Release/Prompt-Expansion.html#Simple-Prompt-Escapes
# If none is provided, the default '%n@%m: %~' is used.
#zstyle ':zim:termtitle' format '%1~'

#
# zsh-autosuggestions
#

# Disable automatic widget re-binding on each precmd. This can be set when
# zsh-users/zsh-autosuggestions is the last module in your ~/.zimrc.
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

# Customize the style that the suggestions are shown with.
# See https://github.com/zsh-users/zsh-autosuggestions/blob/master/README.md#suggestion-highlight-style
#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'

#
# zsh-syntax-highlighting
#

# Set what highlighters will be used.
# See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters.md
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# Customize the main highlighter styles.
# See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters/main.md#how-to-tweak-it
#typeset -A ZSH_HIGHLIGHT_STYLES
#ZSH_HIGHLIGHT_STYLES[comment]='fg=242'

# Start shell polish added by Copilot {{{
if (( ${+commands[brew]} )); then
  fpath=(
    "$(brew --prefix)/share/zsh/site-functions"
    "$(brew --prefix)/share/zsh-completions"
    $fpath
  )
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# }}} End shell polish added by Copilot

# ------------------
# Initialize modules
# ------------------

ZIM_HOME=${ZDOTDIR:-${HOME}}/.zim
# Download zimfw plugin manager if missing.
if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
  if (( ${+commands[curl]} )); then
    curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  else
    mkdir -p ${ZIM_HOME} && wget -nv -O ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  fi
fi
# Install missing modules, and update ${ZIM_HOME}/init.zsh if missing or outdated.
if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]]; then
  source ${ZIM_HOME}/zimfw.zsh init
fi
# Initialize modules.
source ${ZIM_HOME}/init.zsh

# Start modern shell tools added by Copilot {{{
if (( ${+commands[zoxide]} )); then
  eval "$(zoxide init zsh)"
fi

if (( ${+commands[fzf]} )) && [[ -o interactive && -t 0 && -t 1 ]]; then
  source <(fzf --zsh)
fi

if (( ${+commands[eza]} )); then
  alias ls='eza --icons=auto'
  alias ll='eza -lah --icons=auto --git'
  alias la='eza -la --icons=auto'
fi

if (( ${+commands[bat]} )); then
  alias cat='bat'
fi
# }}} End modern shell tools added by Copilot
# }}} End configuration added by Zim Framework install

export PATH="$HOME/.local/bin:$PATH"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# Add the global npm bin to PATH, but only if npm actually works. Guarded so a
# broken/absent node install doesn't spew dyld/npm errors on every shell start.
#
# `npm prefix -g` is the obvious way to ask and costs a measured 75 ms of every
# interactive shell -- it boots node to print a path that is already implied by
# where npm itself lives. `${commands[npm]}` is the path zsh already resolved
# for the guard above, and `:h:h` walks it up past `bin/` to the same prefix.
# Verified equal to `npm prefix -g` on both a Homebrew node (/opt/homebrew) and
# an unpacked tarball under ~/.local/opt, which are the two shapes this repo
# installs. A node whose npm is NOT at <prefix>/bin/npm would disagree, and the
# `-d` test below is what keeps that case harmless rather than wrong.
if (( ${+commands[npm]} )); then
  npm_global_bin="${commands[npm]:h:h}/bin"
  [[ -d "$npm_global_bin" ]] && export PATH="$npm_global_bin:$PATH"
  unset npm_global_bin
fi
# Load W&B API key from private local file.
if [ -r "$HOME/.ssh/wandb_api_key" ]; then
  export WANDB_API_KEY="$(tr -d '\r\n' < "$HOME/.ssh/wandb_api_key")"
fi

# Editor for anything that shells out to one: git commit messages, and omp's
# Ctrl+G, which opens the current draft in $VISUAL and waits for it to exit.
# Helix is the default here and on every host this repo sets up, because that
# Ctrl+G contract is the demanding one: the editor must own the terminal, edit,
# write, and give it back on exit. Helix is post-modal and does exactly that.
# Fresh does not behave inside omp, which is why it no longer takes this seat.
#
# Fresh stays installed and is deliberately not named first; `fresh` when you
# want it. It remains the fallback, so a host with fresh and no helix is still
# left with a working $EDITOR rather than none.
if command -v hx >/dev/null 2>&1; then
  export EDITOR=hx
  export VISUAL=hx
elif command -v fresh >/dev/null 2>&1; then
  export EDITOR=fresh
  export VISUAL=fresh
fi
