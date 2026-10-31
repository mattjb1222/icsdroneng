#!/usr/bin/env bash
# Check the 4-bot bughouse test status (manual tracking helper).
declare -A PORT=( [A]=6001 [B]=6002 [C]=6003 [D]=6004 )

echo "=== running bots (by proxyPort) ==="
for L in A B C D; do
  pgrep -f "proxyPort ${PORT[$L]}" >/dev/null 2>&1 && echo "drone$L: UP" || echo "drone$L: DOWN"
done

echo "=== game count (A vs C 'Detected end of game') ==="
grep -c "Detected end of game" /tmp/droneA/guest.log 2>/dev/null

echo "=== last real move per bot (timestamp) ==="
for L in A B C D; do
  LA=$(grep -a "icsdrone->ics: " /tmp/drone$L/guest.log 2>/dev/null | grep -avE "ping|Command not found" | tail -1 | grep -aoE "^[A-Z][a-z]{2} [A-Z][a-z]{2} [0-9]+ [0-9:]{8}")
  echo "drone$L: ${LA:-none}"
done

echo "=== crashes / bail-outs ==="
found=0
for L in A B C D; do
  R=$(grep -aE "Something bad happened|Bailing out" /tmp/drone$L/guest.log 2>/dev/null | tail -1)
  [ -n "$R" ] && { echo "drone$L: $R"; found=1; }
done
[ "$found" = 0 ] && echo "none"

echo "=== illegal moves (engine rejected a sent move) ==="
IL=$(grep -a "Illegal move" /tmp/drone*/guest.log 2>/dev/null | tail -4)
[ -n "$IL" ] && echo "$IL" | sed 's#/tmp/##' || echo "none"
