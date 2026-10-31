#!/usr/bin/env python3
"""Connect to an icsdrone proxy (telnet-style) and issue ICS commands AS the bot.

Proxy protocol (see proxy.c ProcessProxyLine):
  1. icsdrone sends "login: " ; client sends the handle (e.g. "guest").
  2. icsdrone sends "password: " (with a TELNET WILL ECHO); client sends the
     password (e.g. "blah").
  3. On success the proxy is "logged in" and sends the current board (if in a
     game) plus a prompt marker.  Commands sent now are forwarded to the ICS
     server via ExecCommand(line, PROXY, FALSE).

TELNET negotiation bytes (IAC=0xff and following) are stripped for display.

Usage:
  ./ics_proxy.py <port> "cmd1" "cmd2" ...
"""
import socket, sys, time

IAC = 0xff
WILL, WONT, DO, DONT = 251, 252, 253, 254

def strip_telnet(buf):
    out = []
    i = 0
    n = len(buf)
    while i < n:
        b = buf[i]
        if b == IAC:
            if i + 1 < n:
                if buf[i+1] in (WILL, WONT, DO, DONT):
                    i += 3
                    continue
                if buf[i+1] == IAC:
                    out.append(IAC); i += 2; continue
                # IAC + other (e.g. a Telnet option byte) -> skip the pair
                i += 2
                continue
            i += 1
        else:
            out.append(b); i += 1
    return bytes(out).decode("latin-1", "replace")

def main():
    port = int(sys.argv[1])
    cmds = sys.argv[2:]
    handle = sys.argv[0 + 0]  # placeholder, not used
    s = socket.create_connection(("127.0.0.1", port), timeout=30)
    s.settimeout(6)

    def read(t=6):
        buf = b""
        try:
            s.settimeout(t)
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                buf += chunk
                if len(buf) > 16384:
                    break
        except socket.timeout:
            pass
        return strip_telnet(buf)

    def send(x):
        s.sendall((x if isinstance(x, bytes) else x.encode("latin-1")))

    print("=== connect (port %d) ===" % port)
    print(read(3))
    send("guest\n")
    time.sleep(1.0)
    print("=== after handle ===")
    print(read(3))
    send("blah\n")
    time.sleep(1.0)
    print("=== after password (should be logged in) ===")
    print(read(3))
    for c in cmds:
        print("\n>>> %s" % c)
        send(c + "\n")
        time.sleep(1.5)
        print(read(3))
    # clean disconnect (proxy "quit" just disconnects, does not kill icsdrone)
    send("quit\n")
    time.sleep(0.5)
    read(1)
    s.close()

if __name__ == "__main__":
    main()
