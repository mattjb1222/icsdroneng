#!/usr/bin/env bash
#
# mon_verify.sh — one monitoring / verification cycle for a 4-bot bughouse test.
#
# Assumed layout (set up by launch_bots.sh, see BUGHOUSE_TEST.md):
#   droneA, droneB, droneC, droneD  (proxies PROXY_BASE+0..3)
#   teams: (A + B)  vs  (C + D)     (partnership asserted below on each rematch)
#
# Each invocation prints the bug signals we care about:
#   - crashes / bail-outs   : "Something bad happened" | "Bailing out"
#   - TRC BADSTATE          : engine position[]/bitboard inconsistency
#                            (only present if the engine was built with the
#                             diagnostics and run with SUNSETTER_DEBUGSTATE=1)
#   - illegal-move rejections: "Tried to play illegal move" | "It is not your
#                            move" | "Illegal move"   <- the partMatesMe-class bug
#   - drop moves exercised  : TRC APPLY lines containing a drop ("...@...")
#
# It auto-rematches A vs C when all four bots are idle, so wrapping it in a
# small sleep loop keeps the test running continuously:
#   while :; do ./mon_verify.sh; sleep 40; done
#
# Configuration (env vars, default to the standard layout):
#   PROXY_BASE  base proxy port (default 6000) -> bot i uses PROXY_BASE+i
#   LOGDIR      per-bot log dir base (default /tmp) -> <LOGDIR>/drone<label>/
#   MATCH_SPEC  the "match <name> <time> <inc> bug" spec (default "3 0 bug")
set -u
PROXY_BASE="${PROXY_BASE:-6000}"
LOGDIR="${LOGDIR:-/tmp}"
MATCH_SPEC="${MATCH_SPEC:-3 0 bug}"
GLOB="$LOGDIR"/drone?/guest.log

E=$(grep -ahc 'Detected end of game' $GLOB 2>/dev/null | paste -sd+ | bc); E=${E:-0}
CR=$(grep -alE 'Something bad happened|Bailing out' $GLOB 2>/dev/null | wc -l)
BS=$(grep -ahc 'TRC BADSTATE' $GLOB 2>/dev/null | paste -sd+ | bc); BS=${BS:-0}
DROPS=$(grep -ahE 'TRC APPLY' $GLOB 2>/dev/null | grep -ac '@' 2>/dev/null); DROPS=${DROPS:-0}
echo "matches=$((E / 4))  crashes=$CR  BADSTATE=$BS  drop-moves~$DROPS"

REJ=$(grep -ahE 'Tried to play illegal move|It is not your move|Illegal move' $GLOB 2>/dev/null | grep -avE '^$')
if [ -n "$REJ" ]; then echo "!!! REJECTIONS:"; echo "$REJ" | tail -8; else echo "rejections: none"; fi
CB=$(grep -ahE 'Something bad happened|Bailing out' $GLOB 2>/dev/null | grep -avE '^$')
if [ -n "$CB" ]; then echo "!!! CRASH/BAILOUT:"; echo "$CB" | tail -8; fi

# --- auto-rematch A vs C when all four bots are idle -----------------------
# A bot is "in progress" if its most recent match-start marker is more recent
# than its most recent match-end marker (HH:MM:SS does not wrap within one run).
ALLIDLE=1
for l in A B C D; do
  L="$LOGDIR/drone$l/guest.log"
  le=$(grep -aE 'Detected end of game' "$L" 2>/dev/null | tail -1 | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1)
  ls=$(grep -aE "bughouse ${MATCH_SPEC%% *} started|observing game" "$L" 2>/dev/null | tail -1 | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1)
  [ -n "$ls" ] && [[ "$ls" > "$le" ]] && ALLIDLE=0
done
if [ "$ALLIDLE" = "1" ]; then
  name_of() { grep -a 'Logging you in as' "$LOGDIR/drone$1/guest.log" 2>/dev/null | tail -1 | grep -aoE 'Guest[A-Z0-9]+'; }
  NA=$(name_of A); NB=$(name_of B); NC=$(name_of C); ND=$(name_of D)
  if [ -n "$NA" ] && [ -n "$NC" ]; then
    # (re)assert partnerships (A+B, C+D), then start A vs C
    python3 ics_proxy.py "$PROXY_BASE" "partner $NB" >/dev/null 2>&1
    python3 ics_proxy.py "$((PROXY_BASE + 2))" "partner $ND" >/dev/null 2>&1
    python3 ics_proxy.py "$PROXY_BASE" "match $NC $MATCH_SPEC" 2>&1 | grep -aiE 'started|accept|match' | head -1 | sed 's/^/  -> re-matching A vs C (all idle): /'
  else
    echo "  -> all idle but no guest names found yet (waiting for login)"
  fi
else
  echo "  -> board in progress (no rematch)"
fi
