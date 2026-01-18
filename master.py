#!/usr/bin/env python3
"""
P2P Chat for Raspberry Pi over Ad-Hoc WiFi
Device A acts as server, Device B connects as client.
"""

import socket
import threading
import json
import sys
import os

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

def receive_messages(sock, peer_name):
    """Thread to continuously receive messages from peer."""
    while True:
        try:
            data = sock.recv(4096)
            if not data:
                print(f"\n[{peer_name} disconnected]")
                break
            message = data.decode("utf-8")
            print(f"\n[{peer_name}]: {message}")
            print("You: ", end="", flush=True)
        except ConnectionResetError:
            print(f"\n[{peer_name} disconnected]")
            break
        except Exception as e:
            print(f"\n[Connection error: {e}]")
            break

def send_messages(sock):
    """Main thread sends messages."""
    while True:
        try:
            message = input("You: ")
            if message.lower() == "/quit":
                print("[Closing connection...]")
                break
            sock.sendall(message.encode("utf-8"))
        except (BrokenPipeError, ConnectionResetError):
            print("[Connection lost]")
            break
        except KeyboardInterrupt:
            print("\n[Closing connection...]")
            break

def run_server(config):
    """Device A runs as server."""
    my_ip = config["network"]["A"]
    port = config["port"]

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        server.bind((my_ip, port))
    except OSError:
        # Fallback to bind on all interfaces if specific IP fails
        server.bind(("0.0.0.0", port))

    server.listen(1)
    print(f"[Device A - Server]")
    print(f"[Listening on {my_ip}:{port}]")
    print("[Waiting for Device B to connect...]")

    conn, addr = server.accept()
    print(f"[Device B connected from {addr[0]}]")
    print("[Type messages and press Enter. Type /quit to exit]\n")

    # Start receive thread
    recv_thread = threading.Thread(target=receive_messages, args=(conn, "B"), daemon=True)
    recv_thread.start()

    # Send messages in main thread
    send_messages(conn)

    conn.close()
    server.close()

def run_client(config):
    """Device B runs as client."""
    server_ip = config["network"]["A"]
    port = config["port"]

    print(f"[Device B - Client]")
    print(f"[Connecting to Device A at {server_ip}:{port}...]")

    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Retry connection until successful
    connected = False
    while not connected:
        try:
            client.connect((server_ip, port))
            connected = True
        except ConnectionRefusedError:
            print("[Device A not ready, retrying in 2s...]")
            import time
            time.sleep(2)
        except KeyboardInterrupt:
            print("\n[Cancelled]")
            sys.exit(0)

    print("[Connected to Device A]")
    print("[Type messages and press Enter. Type /quit to exit]\n")

    # Start receive thread
    recv_thread = threading.Thread(target=receive_messages, args=(client, "A"), daemon=True)
    recv_thread.start()

    # Send messages in main thread
    send_messages(client)

    client.close()

def main():
    config = load_config()
    device = config["device"].upper()

    print("=" * 40)
    print("  P2P Chat - Raspberry Pi Ad-Hoc WiFi")
    print("=" * 40)

    if device == "A":
        run_server(config)
    elif device == "B":
        run_client(config)
    else:
        print(f"Error: Invalid device '{device}' in config. Must be 'A' or 'B'.")
        sys.exit(1)

if __name__ == "__main__":
    main()
