#!/bin/sh
# Prove `detect_platform` answers correctly on Darwin without reaching a Linux-only command.
#
# The installer is sourced rather than copied: `DOTFILES_AGENT_LIB` suppresses its `main`, so
# the function under test is the maintained one. `apt-get` is present on the fixture PATH and
# records any invocation, which distinguishes "the branch was not taken" from "the command
# happened to be missing".
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
script="$repo_dir/ubuntu-agent/install.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -q 'DOTFILES_AGENT_LIB' "$script" ||
  fail "installer must be sourceable so a function can be tested without running main"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home"
calls="$work/calls.log"
: >"$calls"

for forbidden in apt-get add-apt-repository systemctl snap dpkg; do
  printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 0\n' "$forbidden" "$calls" \
    >"$work/bin/$forbidden"
  chmod +x "$work/bin/$forbidden"
done

printf '#!/bin/sh\nexit 0\n' >"$work/bin/brew"
chmod +x "$work/bin/brew"

fake_uname() {
  printf '#!/bin/sh\ncase "${1:-}" in\n  -m) echo %s ;;\n  *) echo %s ;;\nesac\n' "$2" "$1" \
    >"$work/bin/uname"
  chmod +x "$work/bin/uname"
}

# `status` is kept beside the output rather than swallowed: a guard that CRASHES prints no
# `PLATFORM=` line, and a bare `|| true` would let the refusal cases below read that crash
# as a correct refusal. The two success cases assert on it; the refusal cases assert on the
# absent line, which is why they may still ignore it.
platform_of() {
  status=0
  out=$(env PATH="$work/bin:/usr/bin:/bin" HOME="$work/home" DOTFILES_AGENT_LIB=1 \
    DOTFILES_AGENT_SCRIPT="$script" \
    sh -c '. "$1"; detect_platform; printf "PLATFORM=%s\n" "$PLATFORM"' sh "$script" 2>&1) ||
    status=$?
  printf '%s\n' "$out"
  return "$status"
}

fake_uname Darwin arm64
darwin=$(platform_of) || fail "Darwin guard exited non-zero: $darwin"
case $darwin in
  *PLATFORM=macos*) ;;
  *) fail "Darwin must select PLATFORM=macos, got: $darwin" ;;
esac
[ ! -s "$calls" ] || fail "detect_platform reached a Linux-only command: $(cat "$calls")"

fake_uname Linux x86_64
linux=$(platform_of) || fail "Linux guard exited non-zero: $linux"
case $linux in
  *PLATFORM=linux*) ;;
  *) fail "Linux must keep PLATFORM=linux, got: $linux" ;;
esac

# A Mac without Homebrew is refused rather than half-provisioned: nothing below the guard
# knows how to install a package without it, so continuing would fail somewhere less clear.
# The exact status and message are asserted, so an unrelated crash cannot pass as a refusal.
fake_uname Darwin arm64
rm -f "$work/bin/brew"
status=0
no_brew=$(platform_of) || status=$?
[ "$status" -eq 1 ] ||
  fail "a Mac without Homebrew must exit 1, got $status: $no_brew"
case $no_brew in
  *Homebrew*) ;;
  *) fail "the refusal must name Homebrew, got: $no_brew" ;;
esac

fake_uname OpenBSD amd64
status=0
other=$(platform_of) || status=$?
[ "$status" -eq 1 ] ||
  fail "an unsupported platform must exit 1, got $status: $other"
case $other in
  *OpenBSD*) ;;
  *) fail "the refusal must name the platform it found, got: $other" ;;
esac

printf 'ok: detect_platform is Darwin-safe and Linux-unchanged\n'
