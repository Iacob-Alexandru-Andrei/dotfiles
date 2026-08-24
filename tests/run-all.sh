#!/bin/sh
# Every test in this directory, so a change is checked by one command rather than by
# remembering which files exist. New tests are picked up by being named test-*.sh.
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

failed=''

for test_file in "$tests_dir"/test-*.sh; do
  [ -f "$test_file" ] || continue

  name=$(basename "$test_file")
  printf '==> %s\n' "$name"

  if sh "$test_file"; then
    continue
  fi

  failed="$failed $name"
done

if [ -n "$failed" ]; then
  printf '\nFAILED:%s\n' "$failed" >&2
  exit 1
fi

printf '\nall dotfiles tests passed\n'
