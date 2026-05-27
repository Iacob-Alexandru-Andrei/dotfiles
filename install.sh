#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
timestamp=$(date +%Y%m%d%H%M%S)

link_file() {
  source_path=$1
  target_path=$2

  if [ ! -e "$source_path" ]; then
    printf 'missing source: %s\n' "$source_path" >&2
    exit 1
  fi

  target_dir=$(dirname -- "$target_path")
  mkdir -p "$target_dir"

  if [ -L "$target_path" ]; then
    current_link=$(readlink "$target_path")
    if [ "$current_link" = "$source_path" ]; then
      printf 'already linked: %s -> %s\n' "$target_path" "$source_path"
      return
    fi

    printf 'removing stale symlink: %s -> %s\n' "$target_path" "$current_link"
    rm "$target_path"
  elif [ -e "$target_path" ]; then
    backup_path="${target_path}.backup.${timestamp}"
    printf 'backing up: %s -> %s\n' "$target_path" "$backup_path"
    mv "$target_path" "$backup_path"
  fi

  ln -s "$source_path" "$target_path"
  printf 'linked: %s -> %s\n' "$target_path" "$source_path"
}

link_file "$repo_dir/zsh/.zshrc" "$HOME/.zshrc"
link_file "$repo_dir/zim/.zimrc" "$HOME/.zimrc"

printf '\nDone. Open a new zsh session or run: exec zsh\n'
