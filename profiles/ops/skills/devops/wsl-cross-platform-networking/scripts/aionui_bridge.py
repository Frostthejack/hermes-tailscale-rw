#!/usr/bin/env python3
"""AionUI MCP Bridge - WSL-side TCP bridge

Forwards local WSL ports to Windows AionUI services.
Handles bidirectional TCP forwarding for web UI and MCP tools.

Usage:
    python3 aionui_bridge.py
"""

import socket
import threading
import sys
import time

# Configuration
WINDOWS_WS_HOST = "192.168.0.40"  # Windows host IP
WINDOWS_VETH_HOST = "172.25.144.1"  # Windows vEthernet (WSL gateway)

AIONUI_WEB_PORT = 62936
AIONUI_MCP_PORT = 57978

# Local bridge ports (WSL side)
LOCAL_WEB_PORT = 62936
LOCAL_MCP_PORT = 57978

BRIDGE_MODE = "veth"  # "windows" or "veth" or "loopback"
# "windows": forward to Windows host IP (192.168.0.40)
# "veth": forward to Windows vEthernet (172.25.144.1) - requires portproxy
# "loopback": Windows listens on 127.0.0.1, portproxy to WSL


def forward_bidirectional(src_sock, dst_sock, label):
    """Forward data bidirectionally until either socket closes."""
    
    def forward_direction(source, destination, direction_name):
        try:
            while True:
                data = source.recv(8192)
                if not data:
                    break
                destination.sendall(data)
        except (ConnectionError, OSError):
            pass
        finally:
            try:
                source.close()
            except:
                pass
            try:
                destination.close()
            except:
                pass
    
    t1 = threading.Thread(
        target=forward_direction,
        args=(src_sock, dst_sock, f"{label}-out"),
        daemon=True
    )
    t2 = threading.Thread(
        target=forward_direction,
        args=(dst_sock, src_sock, f"{label}-in"),
        daemon=True
    )
    t1.start()
    t2.start()
    return t1, t2


def tcp_bridge(local_host, local_port, dest_host, dest_port, label):
    """TCP forwarding bridge.
    
    Listens on local_host:local_port and forwards all connections to
    dest_host:dest_port.
    """
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        server.bind((local_host, local_port))
    except OSError as e:
        print(f"[{label}] ERROR: Cannot bind to {local_host}:{local_port}")
        print(f"[{label}]        {e}")
        print(f"[{label}]        Port may already be in use.")
        sys.exit(1)
    
    server.listen(10)
    print(f"[{label}] Bridge active: {local_host}:{local_port} -> {dest_host}:{dest_port}")
    
    connections = []
    
    while True:
        try:
            server.settimeout(1.0)
            client_sock, client_addr = server.accept()
            print(f"[{label}] Connection from {client_addr[0]}:{client_addr[1]}")
            
            # Connect to destination
            dest_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            dest_sock.settimeout(5)
            try:
                dest_sock.connect((dest_host, dest_port))
                dest_sock.settimeout(None)
                print(f"[{label}] Forwarding to {dest_host}:{dest_port}")
            except Exception as e:
                print(f"[{label}] ERROR connecting to destination: {e}")
                client_sock.close()
                continue
            
            # Start bidirectional forwarding
            forward_bidirectional(client_sock, dest_sock, label)
            
        except socket.timeout:
            continue
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"[{label}] Unexpected error: {e}")
            import traceback
            traceback.print_exc()
    
    server.close()


def main():
    print("=" * 60)
    print("AionUI MCP Bridge (WSL)")
    print("=" * 60)
    print()
    
    # Determine destination based on mode
    if BRIDGE_MODE == "windows":
        web_dest = (WINDOWS_WS_HOST, AIONUI_WEB_PORT)
        mcp_dest = (WINDOWS_WS_HOST, AIONUI_MCP_PORT)
    elif BRIDGE_MODE == "veth":
        web_dest = (WINDOWS_VETH_HOST, AIONUI_WEB_PORT)
        mcp_dest = (WINDOWS_VETH_HOST, AIONUI_MCP_PORT)
    else:  # loopback
        web_dest = ("127.0.0.1", AIONUI_WEB_PORT)
        mcp_dest = ("127.0.0.1", AIONUI_MCP_PORT)
    
    print(f"Bridge mode: {BRIDGE_MODE}")
    print(f"  Web UI:   localhost:{LOCAL_WEB_PORT} -> {web_dest[0]}:{web_dest[1]}")
    print(f"  MCP:      localhost:{LOCAL_MCP_PORT} -> {mcp_dest[0]}:{mcp_dest[1]}")
    print()
    print("Press Ctrl+C to stop.")
    print()
    
    # Start web UI bridge
    web_thread = threading.Thread(
        target=tcp_bridge,
        args=('0.0.0.0', LOCAL_WEB_PORT, web_dest[0], web_dest[1], "WebUI"),
        daemon=True
    )
    web_thread.start()
    
    # Start MCP bridge
    mcp_thread = threading.Thread(
        target=tcp_bridge,
        args=('0.0.0.0', LOCAL_MCP_PORT, mcp_dest[0], mcp_dest[1], "MCP"),
        daemon=True
    )
    mcp_thread.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n\nShutting down bridges...")
        sys.exit(0)


if __name__ == "__main__":
    main()
