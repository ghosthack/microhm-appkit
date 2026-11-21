#!/bin/sh
# Copies the files listed in Shared/shared.txt from micro-harness-manager into this repo.
#   scripts/sync-shared.sh            the commit in Shared/shared.lock (restores the copies)
#   scripts/sync-shared.sh --latest   upstream main; updates the lock
#   scripts/sync-shared.sh <commit>   that commit; updates the lock
#   scripts/sync-shared.sh --check    fails if a copy differs from the locked commit (CI)
# MHM_SHARED_REPO overrides the upstream (a URL or a local clone).
set -eu
cd "$(dirname "$0")/.."
LOCK=Shared/shared.lock
LIST=Shared/shared.txt
UPSTREAM=$(awk '$1 == "repo" { print $2 }' "$LOCK")
REPO=${MHM_SHARED_REPO:-$UPSTREAM}
LOCKED=$(awk '$1 == "commit" { print $2 }' "$LOCK")
[ -n "$UPSTREAM" ] && [ -n "$LOCKED" ] || { echo "$LOCK needs a repo and a commit line" >&2; exit 1; }

check=0
case "${1:-}" in
  "") ref=$LOCKED ;;
  --check) ref=$LOCKED; check=1 ;;
  --latest) ref=main ;;
  -*) echo "usage: $0 [--latest | --check | <commit>]" >&2; exit 2 ;;
  *) ref=$1 ;;
esac

paths() { grep -v '^[[:space:]]*\(#\|$\)' "$LIST"; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/microhm-shared-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" sparse-checkout set --no-cone $(paths | awk '{ print "/" $1 }') >/dev/null
git -C "$TMP" fetch -q --depth 1 "$REPO" "$ref"
git -C "$TMP" checkout -q FETCH_HEAD
commit=$(git -C "$TMP" rev-parse HEAD)

# --check copies into a scratch folder and compares, so it never touches the working tree
OUT=.
[ $check = 1 ] && OUT=$TMP/out
paths | while read -r from to; do
  [ -e "$TMP/$from" ] || { echo "not in $commit: $from" >&2; exit 1; }
  case "$from" in
    */) mkdir -p "$OUT/$to"; rsync -a --delete --exclude node_modules "$TMP/$from" "$OUT/$to" ;;
    *) mkdir -p "$(dirname "$OUT/$to")"; cp "$TMP/$from" "$OUT/$to" ;;
  esac
done

if [ $check = 1 ]; then
  paths | while read -r from to; do
    diff -r -x node_modules "$OUT/$to" "$to" >/dev/null 2>&1 || echo "  $to"
  done > "$TMP/differ"
  if [ -s "$TMP/differ" ]; then
    echo "These copies differ from micro-harness-manager at $commit:" >&2
    cat "$TMP/differ" >&2
    echo "Change them there and run scripts/sync-shared.sh, not by hand." >&2
    exit 1
  fi
  echo "shared files match micro-harness-manager at $commit"
else
  printf 'repo %s\ncommit %s\n' "$UPSTREAM" "$commit" > "$LOCK"
  echo "synced from micro-harness-manager at $commit"
fi
