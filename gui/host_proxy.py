"""Minimal HTTP CONNECT forward proxy for Docker Desktop.

Docker Desktop's VM cannot reach ghcr.io/quay.io directly in this environment
(the system VPN/proxy breaks VM egress). The host CAN reach them, so we run this
proxy on the host and point Docker Desktop's manual proxy at it.
"""
import socket
import sys
import threading
from urllib.parse import urlparse

HOST = "0.0.0.0"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except Exception:
            pass


def relay(a, b):
    a.settimeout(None)
    b.settimeout(None)
    t1 = threading.Thread(target=pipe, args=(a, b), daemon=True)
    t2 = threading.Thread(target=pipe, args=(b, a), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()


def handle(client):
    try:
        client.settimeout(30)
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = client.recv(65536)
            if not chunk:
                return
            data += chunk
        header, _, rest = data.partition(b"\r\n\r\n")
        lines = header.split(b"\r\n")
        parts = lines[0].decode("latin1").split(" ")
        if len(parts) < 2:
            return
        method, target = parts[0], parts[1]

        if method.upper() == "CONNECT":
            host, _, port = target.partition(":")
            remote = socket.create_connection((host, int(port or 443)), timeout=20)
            client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            relay(client, remote)
        else:
            u = urlparse(target)
            path = u.path or "/"
            if u.query:
                path += "?" + u.query
            remote = socket.create_connection(
                (u.hostname, u.port or 80), timeout=20
            )
            req = f"{method} {path} HTTP/1.1\r\n".encode("latin1")
            for ln in lines[1:]:
                if ln.lower().startswith(b"proxy-connection"):
                    continue
                req += ln + b"\r\n"
            req += b"\r\n" + rest
            remote.sendall(req)
            relay(client, remote)
    except Exception:
        pass
    finally:
        try:
            client.close()
        except Exception:
            pass


def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(128)
    print(f"host proxy listening on {HOST}:{PORT}", flush=True)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
