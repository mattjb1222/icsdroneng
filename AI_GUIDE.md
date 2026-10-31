# AI Agent Reference — icsdroneng

A concise, code-level reference for AI agents working in this repository.
Complements (not replaces) `README` (options man page) and `BUGHOUSE_TEST.md`
(test harness docs). Read those for command-line options and verification
workflow details.

---

## 1. What this project is

`icsdroneng` (binary: **`icsdrone`**) is a C program that bridges a chess
engine (XBoard/WinBoard protocol; UCI engines via polyglot) and an Internet
Chess Server (ICS). Originally a fork of `icsdrone` (Henrik Gram) by Michel
Van den Bergh (GPL2+, since it embeds polyglot book code).

Key features:
- Engine wrapper: starts/stops/kills the engine (child process), sends
  board/clock/moves, parses eval + PV from engine output.
- ICS client: login, seeking, auto-accept/decline offers, tournaments,
  auto-reconnect, ping keep-alive, auto-resign/draw handling.
- ICS proxy (default port 5000): telnet-style second interface so a GUI
  (xboard) can stay attached to the engine without owning it.
- Built-in polyglot opening-book support.
- Console (readline, if compiled in), logging (long log, short log, PGN).
- **This fork's main area of work: Bughouse on FatICS** (a private ICS
  fork at 192.168.7.30:5000), including holding/hand reporting, partner
  coordination, drop moves, and human-partner control via ptells.

Companion project: **`/home/mattjb/code/Sunsetter`** — the XBoard engine
being tested (custom, with bughouse support: `partner`, `holding`,
`parntime`, `ptell` commands).

## 2. Repository layout

### Sources (built into `icsdrone` — see `Makefile.am`)
| File | Responsibility |
|---|---|
| `main.c` | `main()`, `MainLoop()` (the `select()`-based event loop over ICS/engine/proxy fds + timers), signal handling, daemonize, history, login sequence (incl. `iset bugholding 1` for FatICS) |
| `fics.c` | **The core protocol engine** (~90 KB). All ICS-line parsing: `ProcessIcsLine()` dispatches to `ProcessBoard()`, `ProcessGameEnd()`, `ProcessIncomingMatches()`, `ProcessOffers()`, `ProcessTells()`/`ProcessPTell()`, `ProcessBughouseHolding()`, `ProcessIllegalMove()`, `ProcessStandings()` (tournaments), command execution (`ExecCommand`), option handling (`SetOption`), login processing |
| `computer.c` | Engine (XBoard) side: `StartComputer`/`KillComputer`/`ResetComputer`, `SendBoardToComputer` (builds xboard `position` + FEN), `ProcessComputerLine` (parses `Depth/...`, `Kibitz`, `The result is`), PV feedback, `NewGame`, engine variant parsing |
| `polyglot.c` | Opening book (polyglot `.bin` format): `hash_key`, `book_move`, `book_open/close` |
| `board.c` | `ParseBoard()` (ICS board lines), `BoardToString`, `BoardToFen` (note: FEN for bughouse omits hand; holding is sent separately) |
| `proxy.c` | ICS proxy: `StartProxy`, `ProcessProxyLine`, login prompt states (`PROXY_LOGIN_INIT…LOGGED_IN`), telnet negotiation |
| `sched.c` | Tiny event/timer scheduler (`create_timer`, `process_timer_list`, `sched_idle_time`) — everything time-based (ping, flag, abort, idle timeout, tell queue) runs here |
| `argparser.c` | Command-line option table (`argList[]`); `-name` CLI options map to `AppData` fields; runtime `set` uses the same table (case-insensitive, no leading `-`) |
| `marker.c` | Inter-process marker protocol strings (`ENDTELL`, `ASKLASTMOVES`, `PING`, `ENDLOGIN`, …) |
| `net.c` | `OpenTCP`, `SendToIcs`, `SendToComputer` |
| `utils.c` | Move-format conversions (ICS LAN/SAN/CASTLE ↔ xboard), logging (`logme`, `StartLogging`, gz support), colors, misc |
| `icsdrone.h` | **The map**: all shared data structures + nearly all prototypes. Read this file first when orienting. |
| `config.h` / `configure` / `configure.ac` | autoconf (readline, ncurses, zlib are optional) |

### Test harness (bash + python, see `BUGHOUSE_TEST.md`)
| File | Role |
|---|---|
| `launch_bots.sh` | Launch/stop/status N `icsdrone` processes running Sunsetter against the local FatICS; per-bot dirs `/tmp/drone<label>/`, proxy ports 6000+i |
| `mon_verify.sh` | One monitor cycle: prints bug signals (crashes, `TRC BADSTATE`, illegal-move rejections, drop moves), auto-rematches A vs C when all four bots idle. Run in a `while :; do ./mon_verify.sh; sleep 40; done` loop |
| `check_test.sh` | Manual status helper (bots up, game count, last move, crashes, illegal moves) |
| `ics_proxy.py` | Sends one command to a bot via its icsdrone proxy (telnet login `guest`/`blah`); strips telnet IAC bytes |
| `ics_client.py` | Minimal FatICS client (log in as guest, run commands, print replies) |

### Build artifacts (in-tree, gitignore'd-ish)
`Makefile` (generated — already configured), `*.o`, `.deps/`, `icsdrone` binary,
`config.log`, `Guest*.txt` (per-bot logs from tests).

## 3. Build

```sh
cd /home/mattjb/code/icsdroneng
make            # Makefile is already configured; plain gcc, -Wall
```

Regenerating from scratch (only if needed):
```sh
./configure && make    # configure.ac: optional --with-readline, --with-zlib
```

Rebuild the engine too before testing: `cd /home/mattjb/code/Sunsetter && make`
(plus `SUNSETTER_DEBUGSTATE=1` at run time for `TRC APPLY`/`TRC BADSTATE` traces).

## 4. Architecture in 30 seconds

One event loop (`MainLoop` in main.c) multiplexes three file descriptor
groups — ICS socket, engine pipes, proxy — plus a timer list (`sched.c`).
Input lines go through three parallel parsers, one per interface:

- `ProcessIcsLine()` (fics.c) — server → everything
- `ProcessComputerLine()` (computer.c) — engine → everything
- `ProcessProxyLine()` (proxy.c) — proxy → mostly `ExecCommand()`

State lives in three globals declared in `icsdrone.h`:
- **`AppData`** — immutable-ish command-line options (engine cmd, host, book, …).
- **`RunData`** — all mutable runtime state (fd's, `icsBoard`, timers,
  game counter, login state, **bughouse state**).
- **`PersistentData`** — survives soft resets (games played, start time).

`EXIT_RESTART`/`EXIT_SOFTQUIT`/`EXIT_HARDQUIT` flow through `ExitOn()` and
control the top-level loop (restart/reconnect vs quit).

### Key constants (icsdrone.h)
- `RESIGN_SCORE -600` (auto-resign threshold; **eval-based auto-resign is off by default** — commit `d79ab87`), `RESIGN_SCORE_TIMES 3`
- `PINGINTERVAL 60s`, `ABORTTIMEOUT 60s`, `IDLETIMEOUT 600s`, `COURTESYADJOURNINTERVAL 45s`
- `BUF_SIZE 8192`, `NETNEWLINE "\r\n"` (ICS is CRLF; so is the proxy/telnet side)
- `Bool` = enum `{FALSE,TRUE}`; `P()` macro for K&R compat (always use the normal `()` style)

### Logging
`logme(LogType, fmt, ...)` — levels `LOG_ERROR/WARNING/INFO/CHAT/DEBUG`.
`logcomm(source, dest, line)` logs every line crossing the ICS/engine boundary
(what the test scripts grep: `icsdrone->ics:`, `Something bad happened`,
`Bailing out`, `Detected end of game`). Feedback to the visible interfaces
is masked: `OWNER`/`CONSOLE`/`PROXY`/`SHORTLOG` bitmask.

## 5. Game lifecycle (normal chess)

1. Login sequence in `main.c` (server-detects `IcsType` FICS/ICC/generic;
   generic/FatICS path sends `iset bugholding 1`, `iset lock 1`, `td set …`).
   Manual seeks are **required** (see README) so icsdrone can pre-check
   offers (`noplay`, `acceptOnly`).
2. `ProcessIncomingMatches()` accepts → engine `NewGame` + `SetInterface` +
   `SetScoreForWhite` (auto-on for Crafty).
3. `ProcessBoard()` parses each board line; `HandleBoard()` →
   `IsMyBoard()`/`EngineToMove()`; on the engine's turn: optional
   polyglot `book_move()`, else `Go()`; `forceSetBoard` flag forces a full
   `setboard` on the first board of a shuffle/variant game (and after a
   bughouse resync).
4. Move: engine sends `move …` → `ConvCompToIcs` → `SendToIcs`. Opponent
   moves are forwarded to the engine (`SendMoveToComputer`, with trace
   sequence numbers).
5. Clocks: `SendTimeToComputer` (1/100 s units — watch unit conversions;
   there was a clock-units bugfix, commit `b467dcb`).
6. `ProcessGameEnd()` → result, PGN logging, rematch limiting
   (`limitRematches`/`hardLimit`), engine restart if `dontReuseEngine`.

## 6. Bughouse / FatICS extension (the recent focus — read carefully)

Added across commits `a8fd6e9` → `ded6e0f`. All in `fics.c` + `icsdrone.h`
(`RunData` bughouse fields: `isBughouse`, `bughousePartner`,
`holdingWhite/Black`, `holdingKnown`, `holdingReportPending`, `lastSentMove`,
`forceSetBoard`, `illegalMoveCount`).

The protocol pieces, and the *why* of each (comments in code explain more):

- **Partnership**: server ptells are parsed in `ProcessOffers()`/
  `ProcessTells()` → `runData.bughousePartner` set. On game start the partner
  name is sent to the engine: `partner <name>` (fics.c ~line 1845).
  `-acceptPartnership` option controls accepting offers.
- **Holding reports** (`ProcessBughouseHolding`, fics.c:1993): FatICS pushes
  `holding <white> <black>` lines (opt-in via `iset bugholding 1` at login).
  A report that *removes* pieces (a drop, detected with
  `countHoldingPieces()`) is **buffered** (`holdingReportPending`) and
  delivered by `FlushHoldingToEngine()` *after* the move that caused it —
  FatICS can send the post-drop report before the drop move, and
  forwarding it immediately makes the engine reject the drop as illegal.
  White/black mapping uses `computerIsWhite`, not board player names (names
  get clobbered by partner-board lines; see `IsPartnerBoard`).
- **Resync instead of resign** (`ProcessIllegalMove`, fics.c:2577): first
  `Illegal move` → interrupt engine, `forceSetBoard=TRUE`, wait for next
  board (full `setboard` + `go`); only the *second* failure resigns.
  On a resync setboard, the last known holding is re-sent to the engine
  (`BoardToFen` omits the hand list, so the engine would otherwise lose it).
- **Partner board observation** (fics.c:2080 `ProcessBoard`): FatICS re-sends
  the partner's board on every move; icsdrone does **not** apply it to
  `runData.icsBoard` but forwards its clocks as `parntime <pclock> <opp clock>`
  (×100, 1/100 s units) so the engine's `canSitByClock()` works without
  ptell spam.
- **ptell forwarding** (`ProcessPTell`, fics.c:2041): FatICS partner tells
  (`"… (your partner) tells you: …"`) and admin-issued ptells are forwarded
  to the engine as `ptell <msg>` — this drives Sunsetter's human-control
  (sit/go/sitting/flag/abort/<move>). On `"sitting"`, icsdrone also sends
  `board` — FatICS does *not* broadcast the board carrying the partner's
  drop, so without this the engine never learns of it.
- **Bughouse never uses move lists** (`UseMoveList()`, fics.c:848): relies on
  board updates; launch scripts pass `-useMoveList off`.
- **Engine survives across bughouse games** (commit `c816110`): game-end /
  rematch handling must not kill the engine mid-partnership.

### Testing bughouse changes
Use the harness — never test by hand one-move-at-a-time; the failure modes
are rare-state desyncs. Full workflow in `BUGHOUSE_TEST.md`:

```sh
cd /home/mattjb/code/Sunsetter && make && cd /home/mattjb/code/icsdroneng && make
./launch_bots.sh stop
SUNSETTER_DEBUGSTATE=1 ./launch_bots.sh 4     # note Guest names
while :; do ./mon_verify.sh; sleep 40; done    # watch for crashes/rejections/BADSTATE
```

Bug signals to watch: `crashes=N` (non-zero = fail), `!!! REJECTIONS`
(`Tried to play illegal move` / `It is not your move` / `Illegal move`),
`BADSTATE=N`. Counting: `matches = Σ "Detected end of game" ÷ 4`.
Known-harmless noise: `Sorry, I didn't understand …` ptells, partner
intro/protect ptells.

## 7. Conventions & gotchas for contributors

- **Style**: old K&R-era C, `P()` macro on prototypes (function bodies use
  normal modern C). 2-space indent, `Bool` not `bool`. Follow the local style
  of the file you edit; do not reformat.
- **New option**: add to `argList[]` in `argparser.c` (name, ArgType,
  `&appData.field`); add the field to `AppData` in `icsdrone.h`; mark
  `runTime=1` if it can change at runtime via `set` (then also add to
  `SendOptions()` in fics.c if it should appear in `options`).
- **New ICS line to handle**: write a `ProcessX(char *line)` in fics.c using
  `sscanf` patterns, return `TRUE` if consumed, and add it to the dispatch
  chain in `ProcessIcsLine()`. Keep the "parse into scratch copy first"
  pattern for board lines (do not clobber `runData.icsBoard` with lines
  that aren't ours).
- **Engine commands**: send via `SendToComputer("…\n", …)`; remember CRLF is
  used to the ICS (`SendToIcs`), engine side also gets `\n` — check
  existing calls before assuming.
- **Timing**: don't sleep; schedule a timer via `create_timer()` and handle
  it in `process_timer_list`.
- **Time units**: engine clocks are 1/100 second; ICS board clocks in
  seconds (bughouse `parntime` needs ×100). A past bug here — check units
  in any clock code.
- **Move formats**: ICS LAN/SAN/CASTLE vs xboard — always go through
  `Conv*` helpers in utils.c, never hand-convert. Drops are LAN-style
  (`Q@c1`); normalization fixed in `bf302f5`.
- **Do not** commit build artifacts (`.o`, `icsdrone`, `config.log`,
  `Guest*.txt`, `guest.log`, `__pycache__`), test logs, or the generated
  `Makefile`/`config.h`/`configure`/`icsdroneng.spec` (only the `.in`/`.am`/
  `.ac`/`.pod`/`.man` sources are canonical).
- Recent fix history is useful context: `git log --oneline` (18 commits;
  bughouse work is the last ~14). Each commit message states the bug it
  fixes — read them before touching bughouse code.

## 8. Quick orientation map (where to look)

| I want to change/understand | Start here |
|---|---|
| A command-line / `set` option | `argparser.c` → `icsdrone.h` (`AppData`) → `fics.c` `SetOption`/`SendOptions` |
| Server reply parsing | `fics.c` `ProcessIcsLine()` dispatch chain |
| Board / resync / first-board logic | `fics.c` `HandleBoard()`, `ProcessBoard()`; `board.c` `ParseBoard`/`BoardToFen` |
| Engine lifecycle / xboard commands | `computer.c` |
| Bughouse holding / drops / ptells | `fics.c`: `ProcessBughouseHolding`, `FlushHoldingToEngine`, `ProcessPTell`, `ProcessIllegalMove` |
| Login / reconnect / FatICS setup | `main.c` `MainLoop`, `ProcessLogin()` (fics.c:971) |
| Timers / delays | `sched.c` + `event_t` fields in `RunData` |
| Proxy behavior | `proxy.c` |
| Testing a change | `BUGHOUSE_TEST.md` workflow (`launch_bots.sh` + `mon_verify.sh`) |
