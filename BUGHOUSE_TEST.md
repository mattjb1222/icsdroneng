# 4-Bot Bughouse Self-Play Test Harness

A small set of scripts for **stress-testing the Sunsetter engine (via icsdrone)**
by running four bots on the private FatICS server in continuous 3-minute
**bughouse** matches: **(droneA + droneB) vs (droneC + droneD)**.

Bughouse is the ideal stress test for the engine: huge branching, frequent deep
mates, constant piece drops, and the partner/tellics protocol all get exercised
every game. Running many games back-to-back makes rare bugs (board/holding
desyncs, illegal-move rejections, internal-state corruption) show up quickly.

This harness was used to **verify the `partMatesMe` drop-suppression fix**
(Sunsetter commit `3f58f00`) — see the "Verification history" section.

---

## The scripts

| Script | Role |
|---|---|
| `launch_bots.sh` | **Launch / stop / status** N bots (labels A, B, C, D, …). Each bot is an `icsdrone` wrapper running the `sunsetter` engine, with an ICS proxy. `stop` kills them; `status` prints the guest names. |
| `ics_proxy.py` | Send a **single command** to a bot through its ICS proxy: `python3 ics_proxy.py <port> "<cmd>"`. Used to send `partner …` / `match …`. |
| `ics_client.py` | Minimal **FatICS client** — log in as a guest and run a list of commands, printing the server's replies. Used to explore the server's command set (partnership / match / …) and to drive bots directly. |
| `mon_verify.sh` | **Monitor + auto-rematch** — one cycle: prints the bug signals (crashes, `TRC BADSTATE`, illegal-move rejections, drop moves) and, when all four bots are idle, re-asserts the partnerships and starts a fresh A-vs-C match. Wrap it in a sleep loop to run continuously. |
| `check_test.sh` | **Manual status check** — which bots are up, game count, last move per bot, any crashes, any illegal moves. A quick eyeball helper (no auto-rematch). |

---

## Running a verification set

```sh
# 1. Build the engine (with diagnostics on if you want TRC APPLY / BADSTATE)
#    and icsdrone.
cd /home/mattjb/code/Sunsetter && make
cd /home/mattjb/code/icsdroneng && make

# 2. Stop any old bots, launch four fresh ones.
#    SUNSETTER_DEBUGSTATE=1 turns on the engine's trace/consistency checks
#    (TRC APPLY#N, TRC BADSTATE, state dumps). Leave it off for a plain run.
./launch_bots.sh stop
SUNSETTER_DEBUGSTATE=1 ./launch_bots.sh 4
./launch_bots.sh status          # -> note the four Guest… names

# 3. Keep matches running and watch for bug signals.
#    mon_verify.sh auto-rematches A vs C when all four go idle, so this loop
#    runs the test continuously:
while :; do ./mon_verify.sh; sleep 40; done
```

`mon_verify.sh` is self-contained about the guest names (it reads them from the
per-bot logs), so it works for any freshly-launched set. Override the layout with
`PROXY_BASE`, `LOGDIR`, `MATCH_SPEC` if needed.

### What to watch for

- **`crashes=N`** — `Something bad happened` / `Bailing out`. Any non-zero value
  means icsdrone bailed on a move it thought was legal (usually the engine
  rejected a legal drop, or a board/holding desync).
- **`rejections: …`** — `Tried to play illegal move` / `It is not your move` /
  `Illegal move`. This is the **`partMatesMe`-class bug** signal: the engine
  rejected a legal move.
- **`BADSTATE=N`** — the engine's own consistency check
  (`debugCheckConsistency`, position[] vs bitboards vs king-count) failed. Only
  present when the engine has the diagnostics and `SUNSETTER_DEBUGSTATE=1`.
- **`drop-moves~N`** — how many drop moves were exercised (higher = more of the
  bughouse drop/holding path tested).
- **`matches=N`** — completed matches. **Counting convention:** the monitor sums
  `Detected end of game` lines across all four bots, so **matches = total ÷ 4**
  (each match produces one end event per bot).

> The ptells `Sorry, I didn't understand …` and the partner intro/protect
> ptells are **normal and harmless** — they do **not** indicate a bug.

---

## Verification history

### `partMatesMe` drop-suppression fix (engine commit `3f58f00`)

**The bug:** a partner "protect queen/rook" directive (`+q` / `+r` → "Mates Me")
set `partMatesMe[X]`, which also drove a drop-suppression gate in `aiMoves()`
(*"keep the protected hand piece off the board"*). Because `moves()` calls
`aiMoves()`, that gate leaked into legal-move validation: with `partMatesMe` set
and no matching piece on the board, the opponent's **legal drop** (e.g. `Q@c1`)
was suppressed from the legal list → `isLegal()` rejected it → icsdrone bailed →
the game crashed.

**The fix:** gate the suppression on `suppressMatesMeDrops` — off (all drops
generated) for `moves()` / `isLegal()` / `isCheckmate()` / partner mate-checks,
and on **only** around the search's own move generation (so the engine still
keeps the protected hand piece out of harm's way when choosing its own moves).

**How it was verified with this harness:**
- The **buggy build** crashed at **match 10** (legal `Q@c1` drop rejected).
- The **fixed build** was launched fresh (SUNSETTER_DEBUGSTATE=1) and run
  continuously: **34 matches / ~571 drop moves / 3083 applied moves** with
  **0 crashes, 0 `TRC BADSTATE`, 0 illegal-move rejections**.
- The `partMatesMe` scenario was actively exercised the whole time (protect
  queen/rook directives were constantly being sent), which is exactly the
  condition that triggered the bug — and it never recurred.

---

## Caveats

- **Guest names are random** per login. `mon_verify.sh` and `check_test.sh`
  read them from the logs; if you hardcode a command (e.g. a one-off
  `python3 ics_proxy.py 6001 "match <Name> 3 0 bug"`), get the current name
  from `./launch_bots.sh status` first.
- **Baseline resets on fresh logs.** `launch_bots.sh` truncates each bot's
  `guest.log`, so `matches=N` starts at 0 for a fresh set (the old `mon_set.sh`
  used a `BASELINE` offset — superseded by `mon_verify.sh`, which assumes a
  fresh set).
- `launch_bots.sh`'s `wait_login` can hang up to ~60 s per bot if a login fails;
  the bots are detached via `setsid` so they survive the script exiting.
- The "in progress" idle check compares `HH:MM:SS` strings, which is fine within a
  single run (no clock wrap). Very long overnight runs could mis-detect; just
  re-issue a match manually if the count stalls while bots are clearly moving.
