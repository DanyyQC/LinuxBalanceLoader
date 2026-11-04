#!/usr/bin/env python3
"""
Simple TCP Load Balancer
Listens on configured ports and forwards to backend servers using round-robin.
"""

import socket
import threading
import select
import sys


class LoadBalancer:
    def __init__(self, listen_port, backends):
        """
        listen_port: port to listen on
        backends: list of (host, port) tuples
        """
        self.listen_port = listen_port
        self.backends = backends
        self.current = 0
        self.lock = threading.Lock()

    def get_next_backend(self):
        with self.lock:
            backend = self.backends[self.current]
            self.current = (self.current + 1) % len(self.backends)
            return backend

    def handle_client(self, client_sock, client_addr):
        try:
            backend_host, backend_port = self.get_next_backend()
            print(f"[{self.listen_port}] {client_addr} -> {backend_host}:{backend_port}")

            backend_sock = socket.create_connection((backend_host, backend_port), timeout=5)

            # Bidirectional forwarding
            sockets = [client_sock, backend_sock]
            while True:
                readable, _, error = select.select(sockets, [], sockets, 60)
                if error or not readable:
                    break

                for sock in readable:
                    data = sock.recv(65536)
                    if not data:
                        return
                    if sock is client_sock:
                        backend_sock.sendall(data)
                    else:
                        client_sock.sendall(data)
        except Exception as e:
            print(f"[{self.listen_port}] Error: {e}")
        finally:
            try:
                client_sock.close()
            except:
                pass
            try:
                backend_sock.close()
            except:
                pass

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("0.0.0.0", self.listen_port))
        server.listen(100)
        print(f"Listening on port {self.listen_port} -> {self.backends}")

        while True:
            client_sock, client_addr = server.accept()
            threading.Thread(
                target=self.handle_client,
                args=(client_sock, client_addr),
                daemon=True
            ).start()


# Config: port -> list of backends
CONFIG = {
    8080: [("127.0.0.1", 9001), ("127.0.0.1", 9002)],
    8081: [("127.0.0.1", 9003)],
}

if __name__ == "__main__":
    for port, backends in CONFIG.items():
        lb = LoadBalancer(port, backends)
        threading.Thread(target=lb.start, daemon=True).start()

    try:
        print("Load balancer running. Ctrl+C to stop.")
        threading.Event().wait()
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)
