#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
run="$root/.run"
mkdir -p "$run"
set -m

for name in notes-api shop-web; do
  pidfile="$run/$name.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "$name already running (pid $(cat "$pidfile"))"
    continue
  fi
  (cd "$root/$name" && exec nohup npm run dev </dev/null >"$run/$name.log" 2>&1) &
  echo $! >"$pidfile"
  url="$(cd "$root/$name" && portless get "$name")"
  for _ in $(seq 1 50); do
    curl -sfk -o /dev/null "$url" && break
    sleep 0.2
  done
  echo "$name started (pid $(cat "$pidfile")) at $url"
done
