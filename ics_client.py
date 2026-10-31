#!/usr/bin/env python3
"""Minimal FatICS client: log in as a guest, then run a list of commands and
print the server's responses.  Used to explore the server's command set
(partnership / match / me) and to drive the test bots.

Usage:
  ./ics_client.py "cmd1" "cmd2" ...
  (each cmd is sent to the server after login; the server's replies are printed)
"""
import socket, sys, time, os

HOST = os.environ.get("BOT_HOST", "192.168.7.30")
PORT = int(os.environ.get("BOT_PORT", "5000"))
HANDLE = "guest"
PASSWORD = "blah"

def main():
    cmds = sys.argv[1:]
    s = socket.create_connection((HOST, PORT), timeout=30)
    s.settimeout(5)
    def recv(t=5):
        buf = b""
        try:
            s.settimeout(t)
            while True:
                chunk = s.recv(4096)
                if not chunk: break
                buf += chunk
                if len(buf) > 8192: break
        except socket.timeout:
            pass
        return buf.decode("latin-1", "replace")
    def send(x):
        s.sendall((x + "\n").encode("latin-1"))
    # read banner + login prompt
    print("=== banner ===")
    print(recv(3)[:2000])
    # login
    send(HANDLE + "\n" + PASSWORD + "\n")
    time.sleep(1.0)
    print("=== after login ===")
    print(recv(3)[:1500])
    # confirm (press enter)
    send("")
    time.sleep(0.5)
    print("=== after confirm ===")
    print(recv(2)[:800])
    for c in cmds:
        print("\n>>> %s" % c)
        send(c)
        time.sleep(1.2)
        print(recv(3)[:2500])
    s.close()

if __name__ == "__main__":
    main()
