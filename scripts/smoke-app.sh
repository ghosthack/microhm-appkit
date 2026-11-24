#!/bin/sh
# Starts the built app's phone page with the build folder moved away and fetches every
# page file: the installed app has no build folder, and a resource lookup that only works
# beside it (SwiftPM's Bundle.module) crashes there. Run after build-app.sh or package.sh.
#
#   scripts/smoke-app.sh [path/to/Microhm.app]
set -eu
cd "$(dirname "$0")/.."
APP=${1:-dist/Microhm.app}
HOST="$APP/Contents/MacOS/microhm-host"
[ -x "$HOST" ] || { echo "no $HOST: build the app first" >&2; exit 1; }

TMP=$(mktemp -d)
PID=
restore() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  [ -d .build.smoke-away ] && mv .build.smoke-away .build
  rm -rf "$TMP"
}
trap restore EXIT INT TERM
[ -d .build ] && mv .build .build.smoke-away

PORT=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
MICROHM_HOME="$TMP/home" "$HOST" --phone-only --port="$PORT" --token=smoke-secret \
  --registry="$TMP/sessions.json" --mux-home="$TMP/mux" >"$TMP/host.log" 2>&1 &
PID=$!

i=0
until grep -q 'phone page ready' "$TMP/host.log" 2>/dev/null; do
  i=$((i + 1))
  if [ $i -gt 100 ] || ! kill -0 "$PID" 2>/dev/null; then
    echo "the phone page did not start:" >&2; cat "$TMP/host.log" >&2; exit 1
  fi
  sleep 0.1
done

failed=0
for f in Sources/MicrohmCore/Resources/web/*; do
  name=$(basename "$f")
  url="http://127.0.0.1:$PORT/$name"
  [ "$name" = index.html ] && url="http://127.0.0.1:$PORT/"
  if curl -fsS -o "$TMP/got" "$url" && cmp -s "$TMP/got" "$f"; then
    echo "ok   $name"
  else
    echo "FAIL $name" >&2; failed=1
  fi
  kill -0 "$PID" 2>/dev/null || { echo "microhm-host died:" >&2; cat "$TMP/host.log" >&2; exit 1; }
done
exit $failed
