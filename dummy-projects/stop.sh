#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
run="$root/.run"
names=("$@")
[[ ${#names[@]} -eq 0 ]] && names=(notes-api shop-web)

for name in "${names[@]}"; do
  pidfile="$run/$name.pid"
  if [[ ! -f "$pidfile" ]]; then
    echo "$name not running"
    continue
  fi
  pgid="$(cat "$pidfile")"
  kill -TERM -- "-$pgid" 2>/dev/null || true
  for _ in $(seq 1 50); do
    kill -0 -- "-$pgid" 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL -- "-$pgid" 2>/dev/null || true
  rm -f "$pidfile"
  echo "$name stopped"
done
