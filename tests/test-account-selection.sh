#!/bin/sh
# The account selector, run rather than described. `ssh` and `scp` are replaced by
# recorders on PATH, so the real argument parser and the real copy path execute and the
# transcript says which key reached which remote name.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
driver="$repo_dir/bin/install-ubuntu-agent-on-host"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

work_root=$(mktemp -d)
trap 'rm -rf "$work_root"' EXIT

bin_dir="$work_root/bin"
key_dir="$work_root/keys"
driver_home="$work_root/driver-home"
mkdir -p "$bin_dir" "$key_dir" "$driver_home/.ssh"

printf 'PERSONAL-PRIVATE\n' > "$key_dir/personal"
printf 'PERSONAL-PUBLIC\n' > "$key_dir/personal.pub"
printf 'WORK-PRIVATE\n' > "$key_dir/work"
printf 'WORK-PUBLIC\n' > "$key_dir/work.pub"

# The names the driver discovers, so the matrix exercises the default path.
printf 'PERSONAL-PRIVATE\n' > "$driver_home/.ssh/id_ed25519_github_personal"
printf 'PERSONAL-PUBLIC\n' > "$driver_home/.ssh/id_ed25519_github_personal.pub"
printf 'WORK-PRIVATE\n' > "$driver_home/.ssh/id_ed25519"
printf 'WORK-PUBLIC\n' > "$driver_home/.ssh/id_ed25519.pub"

# Recorders. `scp` is the one that matters: its two arguments are the local key and the
# remote name, which is the whole question this file asks. `ssh` must succeed silently so
# the driver reaches its own end, and `infocmp` must fail so the terminfo path is skipped
# without a remote.
cat > "$bin_dir/scp" <<'EOF'
#!/bin/sh
src=''
dst=''
for arg in "$@"; do
  case $arg in
    -*) continue ;;
  esac
  if [ -z "$src" ]; then src=$arg; else dst=$arg; fi
done
printf 'scp %s -> %s\n' "$src" "$dst" >> "$RECORD"
exit 0
EOF

cat > "$bin_dir/ssh" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$bin_dir/infocmp" <<'EOF'
#!/bin/sh
exit 1
EOF

chmod +x "$bin_dir/scp" "$bin_dir/ssh" "$bin_dir/infocmp"

# Returns the transcript of one driver run. The keys sit in a scratch HOME rather than
# being named on the command line, because --personal-key/--work-key each imply their own
# account -- passing both would select both and answer a different question than the flags.
#
# A nonzero exit fails the case outright. Asserting against a partial transcript from an
# aborted run is how a suite reports success for a driver that died.
run_driver() {
  RECORD="$work_root/record"
  export RECORD
  : > "$RECORD"

  if [ "$#" -eq 0 ]; then
    flag_label='(no flags)'
  else
    flag_label=$*
  fi

  if ! HOME="$driver_home" PATH="$bin_dir:$PATH" TERM='' \
    sh "$driver" "$@" test-host >"$work_root/out" 2>&1; then
    fail "driver exited nonzero for: $flag_label"
    sed 's/^/    /' "$work_root/out" >&2
  fi

  cat "$RECORD"
}

# The private key that landed on a given remote name, or empty.
copied_to() {
  awk -v want="test-host:.ssh/$2.tmp" '
    $2 != "" && $4 == want { print $2 }
  ' "$1" | head -1
}

assert_copy() {
  transcript=$1
  remote_name=$2
  expected=$3
  label=$4

  actual=$(copied_to "$transcript" "$remote_name")

  if [ -z "$expected" ]; then
    [ -z "$actual" ] ||
      fail "$label: nothing should reach ~/.ssh/$remote_name, got $(basename "$actual")"
    return 0
  fi

  [ -n "$actual" ] || {
    fail "$label: expected $expected at ~/.ssh/$remote_name, nothing was copied"
    return 0
  }
  [ "$(basename "$actual")" = "$expected" ] ||
    fail "$label: expected $expected at ~/.ssh/$remote_name, got $(basename "$actual")"
}

transcript="$work_root/t"

# The names discovery finds, which are what the copies carry when no key flag is given.
PERSONAL=id_ed25519_github_personal
WORK=id_ed25519

# 1. No flags: personal, because personal is the account with nothing to opt into.
run_driver > "$transcript"
assert_copy "$transcript" github-personal "$PERSONAL" 'no flags'
assert_copy "$transcript" github-company '' 'no flags'
assert_copy "$transcript" id_ed25519 "$PERSONAL" 'no flags'

# 2. --personal: the same thing, said out loud.
run_driver --personal > "$transcript"
assert_copy "$transcript" github-personal "$PERSONAL" '--personal'
assert_copy "$transcript" github-company '' '--personal'
assert_copy "$transcript" id_ed25519 "$PERSONAL" '--personal'

# 3. --work: work ONLY. A flag that quietly installed the other account too would make
#    the pair uncomposable, and this is the case that catches it.
run_driver --work > "$transcript"
assert_copy "$transcript" github-personal '' '--work'
assert_copy "$transcript" github-company "$WORK" '--work'
assert_copy "$transcript" id_ed25519 "$WORK" '--work'

# 4. Both flags: both accounts, and personal keeps the unqualified identity.
run_driver --personal --work > "$transcript"
assert_copy "$transcript" github-personal "$PERSONAL" '--personal --work'
assert_copy "$transcript" github-company "$WORK" '--personal --work'
assert_copy "$transcript" id_ed25519 "$PERSONAL" '--personal --work'

# Order must not matter for a pair of selectors.
run_driver --work --personal > "$transcript"
assert_copy "$transcript" github-personal "$PERSONAL" '--work --personal'
assert_copy "$transcript" github-company "$WORK" '--work --personal'
assert_copy "$transcript" id_ed25519 "$PERSONAL" '--work --personal'

# Public halves ride along with the account that was selected.
run_driver --personal --work > "$transcript"
grep -q "$PERSONAL.pub -> test-host:.ssh/github-personal.pub.tmp" "$transcript" ||
  fail 'the personal public key must accompany the personal private key'
grep -q "$WORK.pub -> test-host:.ssh/github-company.pub.tmp" "$transcript" ||
  fail 'the work public key must accompany the work private key'

# An explicit key overrides discovery, and selects its own account.
RECORD="$work_root/record"
export RECORD
: > "$RECORD"
HOME="$driver_home" PATH="$bin_dir:$PATH" TERM='' \
  sh "$driver" --work-key "$key_dir/work" test-host >/dev/null 2>&1 ||
  fail '--work-key alone must run'
cp "$RECORD" "$transcript"
assert_copy "$transcript" github-company work '--work-key'
assert_copy "$transcript" github-personal '' '--work-key'

# A key path that does not exist is refused rather than silently skipped.
RECORD="$work_root/record"
export RECORD
: > "$RECORD"
if PATH="$bin_dir:$PATH" TERM='' sh "$driver" \
  --work-key "$work_root/absent" --work test-host >/dev/null 2>&1; then
  fail 'a --work-key naming a missing file must fail the run'
fi

# Discovery: with no key flags, the driver reads ~/.ssh itself. A HOME holding neither
# key must fail loudly rather than install nothing and report success.
fake_home="$work_root/home"
mkdir -p "$fake_home/.ssh"
if HOME="$fake_home" PATH="$bin_dir:$PATH" TERM='' sh "$driver" test-host >/dev/null 2>&1; then
  fail 'with no discoverable personal key, the run must fail rather than do nothing'
fi

printf 'PERSONAL-PRIVATE\n' > "$fake_home/.ssh/id_ed25519_github_personal"
: > "$RECORD"
HOME="$fake_home" PATH="$bin_dir:$PATH" TERM='' sh "$driver" test-host >/dev/null 2>&1 || true
cp "$RECORD" "$transcript"
assert_copy "$transcript" github-personal id_ed25519_github_personal 'discovery'

if [ "$failures" -ne 0 ]; then
  printf '%s account-selection check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'account selection checks passed\n'
