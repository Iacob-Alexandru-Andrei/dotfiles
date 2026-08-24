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

# `ssh` records too, so the transcript shows key copies and the checkout update in the
# order they happened. SSH_STUB_FAIL makes the remote-git step fail on demand, which is
# what a dirty checkout looks like from here.
cat > "$bin_dir/ssh" <<'EOF'
#!/bin/sh
for arg in "$@"; do
  case $arg in
    *.dotfiles*)
      printf 'ssh checkout-update\n' >> "$RECORD"
      [ -z "${SSH_STUB_FAIL:-}" ] || exit 1
      exit 0
      ;;
    # The mesh writes the host block over stdin, so the payload is only observable here.
    # When REMOTE_HOME is set the command body is *executed* against it rather than
    # recorded -- recording proves the driver sent something, running it proves the thing
    # it sent does what it claims to the file it claims.
    *ssh/config*)
      printf 'ssh mesh-config\n' >> "$RECORD"
      if [ -n "${REMOTE_HOME:-}" ]; then
        HOME="$REMOTE_HOME" sh -c "$arg"
        exit $?
      fi
      cat >> "$MESH_PAYLOAD"
      exit 0
      ;;
  esac
done
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

# Keys are copied BEFORE the checkout update. Ordering is the whole fix: a remote whose
# ~/.dotfiles has a local edit used to abort the run before any key was installed.
run_driver --personal --work > "$transcript"
first_event=$(grep -nE 'scp|checkout-update' "$transcript" | head -1)
case $first_event in
  *scp*) ;;
  *) fail "keys must be copied before the checkout update, got: $first_event" ;;
esac

# ... and when that update fails, the keys are already on the host. This is the sandbox_2
# failure as a test: exit nonzero, but with both accounts installed.
: > "$RECORD"
if SSH_STUB_FAIL=1 HOME="$driver_home" PATH="$bin_dir:$PATH" TERM='' \
  sh "$driver" --personal --work test-host >/dev/null 2>&1; then
  fail 'a failing checkout update must still fail the run'
fi
cp "$RECORD" "$transcript"
assert_copy "$transcript" github-personal "$PERSONAL" 'checkout failure'
assert_copy "$transcript" github-company "$WORK" 'checkout failure'
assert_copy "$transcript" id_ed25519 "$PERSONAL" 'checkout failure'

# --- mesh -------------------------------------------------------------------------
#
# The mesh answers a different question from the account flags: not "which GitHub am I",
# but "can this host ssh where I can". So it is asserted separately, and asserted to be
# independent of the account selection.
MESH_PAYLOAD="$work_root/mesh"
export MESH_PAYLOAD

mesh_home="$work_root/mesh-home"
mkdir -p "$mesh_home/.ssh"
printf 'PERSONAL-PRIVATE\n' > "$mesh_home/.ssh/id_ed25519_github_personal"
printf 'WORK-PRIVATE\n' > "$mesh_home/.ssh/id_ed25519"
printf 'MESH-PRIVATE\n' > "$mesh_home/.ssh/id_rsa"
cat > "$mesh_home/.ssh/config" <<'CFG'
Host sandbox
      HostName BOX444.example.com
      User someone@example.com

Host mac-mini-server
      HostName 100.125.241.22
      User iacobalexandru
      IdentityFile ~/.ssh/id_ed25519

Host sandbox_2
      HostName BOX443.example.com
      User someone@example.com

# One block naming two aliases, which is legal ssh config and easy to half-read: taking
# only the first field carries sandbox_gpu and silently loses sandbox_gpu2.
Host sandbox_gpu sandbox_gpu2
      HostName BOXGPU.example.com
      User someone@example.com
CFG

run_mesh() {
  : > "$RECORD"
  : > "$MESH_PAYLOAD"
  HOME="$mesh_home" PATH="$bin_dir:$PATH" TERM='' sh "$driver" "$@" test-host \
    > "$work_root/mesh.out" 2>&1
}

# Off by default: an ordinary install must not copy a sandbox key or touch the config.
run_mesh --personal || fail 'plain --personal run must succeed'
cp "$RECORD" "$transcript"
if grep -q 'sandbox-mesh' "$transcript"; then
  fail 'without --mesh, no sandbox key may be copied'
fi
if grep -q 'mesh-config' "$transcript"; then
  fail 'without --mesh, the remote ssh config must not be written'
fi

# With --mesh: the key lands under its own name, and the block carries both sandboxes.
run_mesh --personal --mesh || fail '--mesh run must succeed'
cp "$RECORD" "$transcript"
assert_copy "$transcript" sandbox-mesh id_rsa '--mesh'
grep -q 'ssh mesh-config' "$transcript" || fail '--mesh must write the remote ssh config'

for expected in 'Host sandbox' 'Host sandbox_2' 'BOX444.example.com' 'BOX443.example.com' \
  'IdentityFile ~/.ssh/sandbox-mesh' 'IdentitiesOnly yes'; do
  grep -q "$expected" "$MESH_PAYLOAD" || fail "mesh block must contain: $expected"
done

# A `Host a b` block names both aliases, and both must survive: dropping the second is a
# silent loss -- the name simply stops resolving on the remote, with nothing to read.
grep -q 'Host sandbox_gpu sandbox_gpu2' "$MESH_PAYLOAD" ||
  fail 'mesh block must carry every alias of a multi-pattern Host line'

# Scope: only sandboxes. mac-mini-server authenticates with a key that means something
# else on the remote, so pulling it into the mesh would break it.
if grep -q 'mac-mini-server' "$MESH_PAYLOAD"; then
  fail 'mesh block must not claim non-sandbox hosts'
fi
if grep -q '100.125.241.22' "$MESH_PAYLOAD"; then
  fail 'mesh block must not carry non-sandbox hostnames'
fi

# Independent of account selection: --work --mesh installs the work account and the mesh,
# and the mesh key is not confused for a GitHub one.
run_mesh --work --mesh || fail '--work --mesh run must succeed'
cp "$RECORD" "$transcript"
assert_copy "$transcript" sandbox-mesh id_rsa '--work --mesh'
assert_copy "$transcript" github-personal '' '--work --mesh'

# The mesh is part of the keys-first phase: a checkout that fails afterwards must leave
# the host meshed, or an agent there cannot reach anything.
: > "$RECORD"
: > "$MESH_PAYLOAD"
if SSH_STUB_FAIL=1 HOME="$mesh_home" PATH="$bin_dir:$PATH" TERM='' \
  sh "$driver" --personal --mesh test-host >/dev/null 2>&1; then
  fail 'a failing checkout update must still fail the run'
fi
cp "$RECORD" "$transcript"
assert_copy "$transcript" sandbox-mesh id_rsa 'checkout failure'
grep -q 'ssh mesh-config' "$transcript" || fail 'mesh config must survive a failed checkout'

# A missing mesh key is refused, not silently skipped.
bare_home="$work_root/bare-home"
mkdir -p "$bare_home/.ssh"
printf 'PERSONAL-PRIVATE\n' > "$bare_home/.ssh/id_ed25519_github_personal"
cp "$mesh_home/.ssh/config" "$bare_home/.ssh/config"
if HOME="$bare_home" PATH="$bin_dir:$PATH" TERM='' sh "$driver" --mesh test-host \
  >/dev/null 2>&1; then
  fail 'a --mesh run with no discoverable sandbox key must fail'
fi

# A config with no sandbox hosts is refused too: silently meshing nothing looks identical
# to success from the caller's side.
nohost_home="$work_root/nohost-home"
mkdir -p "$nohost_home/.ssh"
printf 'PERSONAL-PRIVATE\n' > "$nohost_home/.ssh/id_ed25519_github_personal"
printf 'MESH-PRIVATE\n' > "$nohost_home/.ssh/id_rsa"
printf 'Host mac-mini-server\n  HostName 100.125.241.22\n' > "$nohost_home/.ssh/config"
if HOME="$nohost_home" PATH="$bin_dir:$PATH" TERM='' sh "$driver" --mesh test-host \
  >/dev/null 2>&1; then
  fail 'a --mesh run with no sandbox hosts must fail rather than mesh nothing'
fi

# The remote command body, actually run. Everything above proves the driver *sent* the
# right text; this proves the text does the right thing to a real file -- and that a
# second run replaces the block rather than stacking another copy.
remote_home="$work_root/remote-home"
mkdir -p "$remote_home/.ssh"
# The pre-existing config carries a hand-added `Host sandbox_2` pointing somewhere else,
# because that is what the sandboxes actually had. ssh takes the FIRST value it sees, so
# this is the case that decides whether the mesh block is real config or decoration.
cat > "$remote_home/.ssh/config" <<'CFG'
Host sandbox_2
  HostName 10.0.0.253
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host preexisting
  HostName keep.example.com
CFG
chmod 600 "$remote_home/.ssh/config"

for run in 1 2; do
  REMOTE_HOME="$remote_home" HOME="$mesh_home" PATH="$bin_dir:$PATH" TERM='' \
    sh "$driver" --personal --mesh test-host >/dev/null 2>&1 ||
    fail "executed mesh run $run must succeed"
done

remote_config="$remote_home/.ssh/config"
begins=$(grep -c 'BEGIN dotfiles sandbox mesh' "$remote_config")
ends=$(grep -c 'END dotfiles sandbox mesh' "$remote_config")
[ "$begins" -eq 1 ] || fail "two runs must leave one BEGIN marker, got $begins"
[ "$ends" -eq 1 ] || fail "two runs must leave one END marker, got $ends"

# Three Host lines from the mesh block -- sandbox, sandbox_2, and the paired
# `sandbox_gpu sandbox_gpu2` -- plus the hand-added one that is deliberately left alone.
hosts=$(grep -c '^Host sandbox' "$remote_config")
[ "$hosts" -eq 4 ] || fail "two runs must leave four sandbox host lines, got $hosts"

# Precedence, asked of ssh rather than of line numbers. ssh takes the FIRST value it sees
# for HostName and ignores later ones, so a mesh block sitting below a hand-added
# `Host sandbox_2` is decoration. `ssh -G -F` resolves the file exactly as a connection
# would, which is the only thing that settles this; ordering is the implementation.
if command -v ssh >/dev/null 2>&1; then
  resolved=$(command ssh -G -F "$remote_config" sandbox_2 2>/dev/null |
    awk 'tolower($1) == "hostname" { print $2; exit }')
  # ssh lowercases what it reports, so the comparison is made in one case.
  [ "$(printf '%s' "$resolved" | tr 'A-Z' 'a-z')" = 'box443.example.com' ] ||
    fail "ssh must resolve sandbox_2 through the mesh block, got '$resolved'"

  identity=$(command ssh -G -F "$remote_config" sandbox_2 2>/dev/null |
    awk 'tolower($1) == "identityfile" { print $2; exit }')
  case $identity in
    *sandbox-mesh) ;;
    *) fail "ssh must offer the mesh key first for sandbox_2, got '$identity'" ;;
  esac
fi

# The block is additive: what was in the config before it must still be there.
grep -q 'Host preexisting' "$remote_config" ||
  fail 'the mesh block must not discard pre-existing config'
grep -q 'keep.example.com' "$remote_config" ||
  fail 'the mesh block must not discard pre-existing host settings'
grep -q '10.0.0.253' "$remote_config" ||
  fail 'the mesh block must not delete a hand-added host, only outrank it'

mode=$(ls -l "$remote_config" | cut -c1-10)
case $mode in
  -rw-------) ;;
  *) fail "remote ssh config must end 0600, got $mode" ;;
esac

if [ "$failures" -ne 0 ]; then
  printf '%s account-selection check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'account selection checks passed\n'
