#!/bin/sh
set -eu
umask 077

fail() {
  printf 'FileBrowser health: %s\n' "$*" >&2
  exit 1
}

probe_dir=
cleanup() {
  if [ -n "$probe_dir" ]; then
    rm -f "$probe_dir/probe"
    rmdir "$probe_dir"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

check_readable() {
  [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ] ||
    fail "directory is not readable/searchable: $1"
  ls -A "$1" >/dev/null || fail "cannot list directory: $1"
}

check_writable() {
  [ -w "$1" ] || fail "directory is not writable: $1"
  probe_dir=$(mktemp -d "$1/.wonton-health.XXXXXX") ||
    fail "cannot create probe directory in: $1"
  printf 'wonton-health\n' >"$probe_dir/probe" || fail "cannot write probe in: $1"
  IFS= read -r result <"$probe_dir/probe" || fail "cannot read probe in: $1"
  [ "$result" = wonton-health ] || fail "probe content mismatch in: $1"
  rm "$probe_dir/probe" && rmdir "$probe_dir" || fail "cannot remove probe in: $1"
  probe_dir=
}

# /health only reports HTTP liveness in v2.0.2-stable. Check storage as the same UID
# as the app; probe roots only, not an expensive recursive scan of every file.
for dir in /data/documents /data/photos /data/music /data/videos /data/downloads /data/transfers \
  /home/filebrowser/data /home/filebrowser/data/cache; do
  check_readable "$dir"
done

# Only touch uniquely named private probes, never existing user files or read-only shares.
for dir in /data/documents /data/downloads /data/transfers \
  /home/filebrowser/data /home/filebrowser/data/cache; do
  check_writable "$dir"
done

curl --fail --silent --show-error --max-time 3 --output /dev/null \
  http://127.0.0.1:80/health || fail 'HTTP liveness request failed'
