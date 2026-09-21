#!/usr/bin/env python3
"""Forward 127.0.0.1:7860 to the remote Make-It-Animatable service.

Why this exists
---------------
The user-facing address for the auto-rig service is `http://127.0.0.1:7860/`, but that
service does not run on this machine: it lives at `21.6.90.117:7860`, reachable over the
`utun6` VPN. Nothing listens on the local port, so browsing `127.0.0.1:7860` fails with a
connection error until a forward is established.

This is a plain bidirectional TCP relay (no TLS termination, no header rewriting), which is
enough because Gradio's own HTTP API is what both the browser UI and
`tools/art/mia_rig_cultivator_tripo_v9.py` talk to.

Usage
-----
    python3 tools/art/port_forward_mia_7860.py                 # default 127.0.0.1:7860
    python3 tools/art/port_forward_mia_7860.py --listen 7870   # different local port
    python3 tools/art/port_forward_mia_7860.py --target 21.6.90.117:7860

Alternatively skip the forward entirely and point the driver straight at the remote host:

    python3 tools/art/mia_rig_cultivator_tripo_v9.py --base-url http://21.6.90.117:7860/

Leave it running in a background job while driving the rig, then stop it.
"""

from __future__ import annotations

import argparse
import socket
import sys
import threading

DEFAULT_LISTEN = ("127.0.0.1", 7860)
DEFAULT_TARGET = ("21.6.90.117", 7860)
CONNECT_TIMEOUT_S = 30.0
BUFFER = 65536


def pump(src: socket.socket, dst: socket.socket) -> None:
    """Copy src -> dst until either side closes."""
    try:
        while True:
            chunk = src.recv(BUFFER)
            if not chunk:
                break
            dst.sendall(chunk)
    except OSError:
        pass
    finally:
        # Half-close so the peer sees EOF instead of hanging.
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle(client: socket.socket, target: tuple[str, int]) -> None:
    try:
        upstream = socket.create_connection(target, timeout=CONNECT_TIMEOUT_S)
    except OSError as exc:
        print(f"  upstream connect failed: {exc}", file=sys.stderr)
        client.close()
        return
    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pump, args=(upstream, client), daemon=True).start()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen-host", default=DEFAULT_LISTEN[0])
    parser.add_argument("--listen", type=int, default=DEFAULT_LISTEN[1])
    parser.add_argument("--target-host", default=DEFAULT_TARGET[0])
    parser.add_argument("--target", type=int, default=DEFAULT_TARGET[1])
    args = parser.parse_args()

    target = (args.target_host, args.target)
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((args.listen_host, args.listen))
    except OSError as exc:
        print(f"FAIL: cannot bind {args.listen_host}:{args.listen}: {exc}", file=sys.stderr)
        print("hint: another forward is already running (check lsof -nP -iTCP:%d -sTCP:LISTEN)"
              % args.listen, file=sys.stderr)
        return 2
    server.listen(64)

    print(f"forwarding {args.listen_host}:{args.listen} -> {target[0]}:{target[1]}", flush=True)
    try:
        while True:
            client, _addr = server.accept()
            threading.Thread(target=handle, args=(client, target), daemon=True).start()
    except KeyboardInterrupt:
        print("\nstopped", flush=True)
    finally:
        server.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
