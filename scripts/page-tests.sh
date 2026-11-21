#!/bin/sh
# The phone page script's unit tests (Shared/page-tests, from micro-harness-manager) against
# the page this app serves. They expect the Java repo's layout, so they run from a scratch
# folder that mirrors it. Needs node 20+. Extra args go to node --test.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/microhm-page-tests-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/main/resources" "$TMP/test"
ln -s "$ROOT/Sources/MicrohmCore/Resources/web" "$TMP/main/resources/web"
cp -R "$ROOT/Shared/page-tests" "$TMP/test/web"
node --test "$@" "$TMP/test/web/app.test.mjs"
