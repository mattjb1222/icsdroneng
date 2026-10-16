#!/usr/bin/env bash
#
# launch_bots.sh — launch/stop/status icsdrone processes running the Sunsetter engine.
#
# Usage:
#   ./launch_bots.sh <N>       Launch N bots (labels A, B, C, ... Z, then numbers).
#   ./launch_bots.sh stop      Stop all running bots.
#   ./launch_bots.sh status    Show running bots and their guest names.
#
# Configuration (override via environment variables):
#   BOT_HOST      ICS server host               (default: 192.168.7.30)
#   BOT_PORT      ICS server port              (default: 5000)
#   BOT_HANDLE    login handle                (default: guest)
#   BOT_PASSWORD  login password              (default: blah)
#   BOT_ENGINE    engine binary path          (default: /home/mattjb/code/Sunsetter/sunsetter)
#   BOT_ICSDRONE  icsdrone binary path        (default: /home/mattjb/code/icsdroneng/icsdrone)
#   BOT_ROOT      base dir for per-bot logs   (default: /tmp)  -> <BOT_ROOT>/drone<label>/
#   BOT_PROXY     enable icsdrone proxy       (default: on)   [on|off]
#   BOT_PROXY_BASE base proxy port           (default: 6000) -> bot i uses port (BOT_PROXY_BASE + i)
#   BOT_LOGIN_CMD command sent at login       (default: set bugopen 1)
#
set -u

HOST="${BOT_HOST:-192.168.7.30}"
PORT="${BOT_PORT:-5000}"
HANDLE="${BOT_HANDLE:-guest}"
PASSWORD="${BOT_PASSWORD:-blah}"
ENGINE="${BOT_ENGINE:-/home/mattjb/code/Sunsetter/sunsetter}"
ICSDRONE="${BOT_ICSDRONE:-/home/mattjb/code/icsdroneng/icsdrone}"
BOTROOT="${BOT_ROOT:-/tmp}"
LOGIN_CMD="${BOT_LOGIN_CMD:-set bugopen 1}"
PROXY="${BOT_PROXY:-on}"
PROXY_BASE="${BOT_PROXY_BASE:-6000}"

label_for() { # $1 = 1-based index -> A..Z then 27,28,...
    local i="$1" letters="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if [ "$i" -le 26 ]; then echo "${letters:$((i-1)):1}"; else echo "$i"; fi
}
dir_for() { echo "$BOTROOT/drone$1"; }

real_drone_pids() { # PIDs of real icsdrone processes (comm=icsdrone)
    local out="" p
    for p in $(pgrep -f "icsdrone -icsHost" 2>/dev/null); do
        [ "$(cat /proc/$p/comm 2>/dev/null)" = "icsdrone" ] && out="$out $p"
    done
    echo "$out"
}

check_binaries() {
    [ -x "$ICSDRONE" ] || { echo "ERROR: icsdrone binary not found: $ICSDRONE" >&2; exit 1; }
    [ -x "$ENGINE" ]   || { echo "ERROR: engine binary not found: $ENGINE" >&2; exit 1; }
}

proxy_port() { echo $((PROXY_BASE + $1)); } # $1 = 1-based index

launch_one() { # $1 = index (1-based), $2 = label ; detached via setsid so it survives this script
    local i="$1" label="$2" dir proxy_args=""
    dir="$(dir_for "$label")"
    [ "$PROXY" = "on" ] && proxy_args="-proxy on -proxyPort $(proxy_port "$i")"
    mkdir -p "$dir"
    rm -f "$dir/guest.log"
    ( cd "$dir" && setsid "$ICSDRONE" \
        -icsHost "$HOST" -icsPort "$PORT" \
        -handle "$HANDLE" -password "$PASSWORD" \
        -program "$ENGINE" \
        -console off -useMoveList off \
        $proxy_args \
        -sendLogin "$LOGIN_CMD" </dev/null >"$dir/out.log" 2>&1 & disown )
}

wait_login() { # $1 = label ; 0 once logged in (<=60s)
    local label="$1" dir i=0
    dir="$(dir_for "$label")"
    while [ "$i" -lt 60 ]; do
        grep -q "Logging you in as" "$dir/guest.log" 2>/dev/null && return 0
        sleep 1; i=$((i+1))
    done
    return 1
}

guest_name() { grep -a "Logging you in as" "$(dir_for "$1")/guest.log" 2>/dev/null | tail -1 | grep -aoE 'Guest[A-Z0-9]+'; }

do_launch() { # $1 = count
    local n="$1" i label
    check_binaries
    echo "Launching $n bot(s): engine=$ENGINE"
    echo "  ics=$HOST:$PORT handle=$HANDLE login_cmd='$LOGIN_CMD'"
    if [ "$PROXY" = "on" ]; then
        echo "  proxy=on base_port=$PROXY_BASE (bot i -> port $(proxy_port 1)+)"
    else
        echo "  proxy=off"
    fi
    for i in $(seq 1 "$n"); do
        label="$(label_for "$i")"
        if [ "$PROXY" = "on" ]; then
            echo "  starting drone $label ($(dir_for "$label")) proxy:$(proxy_port "$i") ..."
        else
            echo "  starting drone $label ($(dir_for "$label")) ..."
        fi
        launch_one "$i" "$label"
    done
    echo "Waiting for logins ..."
    for i in $(seq 1 "$n"); do
        label="$(label_for "$i")"
        if wait_login "$label"; then
            echo "  drone $label => $(guest_name "$label")"
        else
            echo "  drone $label => FAILED to log in (see $(dir_for "$label")/out.log)"
        fi
    done
    echo "Done."
}

do_stop() {
    local pids p left
    pids="$(real_drone_pids)"
    if [ -z "$pids" ]; then echo "No bots running."; return 0; fi
    for p in $pids; do kill "$p" 2>/dev/null && echo "  stopped bot pid $p"; done
    sleep 3
    left="$(real_drone_pids)"
    if [ -n "$left" ]; then echo "WARNING still running:$left (try: kill -9)"; else echo "All bots stopped."; fi
}

do_status() {
    local pids
    pids="$(real_drone_pids)"
    if [ -z "$pids" ]; then echo "No bots running."; return 0; fi
    echo "Running icsdrone PIDs:$pids"
    local d
    for d in "$BOTROOT"/drone*/; do
        [ -f "$d/guest.log" ] || continue
        local name
        name="$(grep -a 'Logging you in as' "$d/guest.log" | tail -1 | grep -aoE 'Guest[A-Z0-9]+')"
        echo "  $(basename "$d") => ${name:-<no login yet>}"
    done
}

case "${1:-}" in
    stop)  do_stop ;;
    status) do_status ;;
    "")    echo "Usage: $0 <N|stop|status>" >&2; exit 1 ;;
    *)     [ "$1" -ge 1 ] 2>/dev/null || { echo "ERROR: N must be a positive integer" >&2; exit 1; }
          do_launch "$1" ;;
esac
