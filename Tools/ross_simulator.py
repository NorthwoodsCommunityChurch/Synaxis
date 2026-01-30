#!/usr/bin/env python3
"""
RossTalk Simulator for Touchdrive to Premiere
Simulates a Ross Carbonite/Ultrix switcher sending RossTalk commands.

Usage:
    python3 ross_simulator.py [--port PORT]

The simulator listens for connections and provides an interactive menu
to send various RossTalk commands.
"""

import socket
import threading
import argparse
import time
import sys

class RossTalkSimulator:
    def __init__(self, port=7788):
        self.port = port
        self.server_socket = None
        self.clients = []
        self.running = False

    def start(self):
        """Start the RossTalk server."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind(('0.0.0.0', self.port))
        self.server_socket.listen(5)
        self.running = True

        print(f"\n{'='*60}")
        print(f"RossTalk Simulator running on port {self.port}")
        print(f"{'='*60}")
        print(f"\nWaiting for connections...")
        print(f"Configure Touchdrive to connect to: 127.0.0.1:{self.port}")
        print(f"{'='*60}\n")

        # Accept connections in a separate thread
        accept_thread = threading.Thread(target=self._accept_connections)
        accept_thread.daemon = True
        accept_thread.start()

        # Run interactive menu
        self._interactive_menu()

    def _accept_connections(self):
        """Accept incoming connections."""
        while self.running:
            try:
                client_socket, address = self.server_socket.accept()
                self.clients.append(client_socket)
                print(f"\n[CONNECTED] Client connected from {address}")
                print(f"[INFO] Total clients: {len(self.clients)}")

                # Start a thread to handle incoming data (if any)
                recv_thread = threading.Thread(target=self._receive_data, args=(client_socket,))
                recv_thread.daemon = True
                recv_thread.start()
            except:
                break

    def _receive_data(self, client_socket):
        """Receive data from client (for any bidirectional communication)."""
        while self.running:
            try:
                data = client_socket.recv(1024)
                if not data:
                    break
                print(f"\n[RECV] {data.decode('utf-8', errors='ignore').strip()}")
            except:
                break
        self.clients.remove(client_socket) if client_socket in self.clients else None
        print(f"\n[DISCONNECTED] Client disconnected. Total clients: {len(self.clients)}")

    def send_command(self, command):
        """Send a RossTalk command to all connected clients."""
        if not self.clients:
            print("[WARN] No clients connected!")
            return

        # RossTalk commands are terminated with \r\n
        message = f"{command}\r\n"

        for client in self.clients[:]:  # Copy list to avoid modification during iteration
            try:
                client.send(message.encode('utf-8'))
                print(f"[SENT] {command}")
            except Exception as e:
                print(f"[ERROR] Failed to send to client: {e}")
                self.clients.remove(client)

    def _interactive_menu(self):
        """Display interactive menu for sending commands."""
        while self.running:
            print("\n" + "="*60)
            print("RossTalk Command Menu")
            print("="*60)
            print("\nSWITCHER COMMANDS:")
            print("  1. MECUT (Program Cut)")
            print("  2. MEAUTO (Auto Transition)")
            print("  3. SELECT (Source Select)")
            print("\nKEYER COMMANDS:")
            print("  4. KEYCUT ON  (Keyer Cut On)")
            print("  5. KEYCUT OFF (Keyer Cut Off)")
            print("  6. KEYAUTO ON (Keyer Auto On)")
            print("  7. KEYAUTO OFF (Keyer Auto Off)")
            print("\nULTRIX COMMANDS:")
            print("  8. XPT (Crosspoint Route)")
            print("  9. SALVO (Fire Salvo)")
            print("\nTEST SEQUENCES:")
            print("  10. Full Production Sequence (simulates a show)")
            print("  11. Keyer Toggle Test (on/off every 3 sec)")
            print("\nOTHER:")
            print("  c. Custom command")
            print("  s. Status (show connected clients)")
            print("  q. Quit")
            print("="*60)

            choice = input("\nEnter choice: ").strip().lower()

            if choice == '1':
                me = input("ME number [1]: ").strip() or "1"
                self.send_command(f"MECUT ME:{me}")

            elif choice == '2':
                me = input("ME number [1]: ").strip() or "1"
                self.send_command(f"MEAUTO ME:{me}")

            elif choice == '3':
                source = input("Source input [1]: ").strip() or "1"
                self.send_command(f"SELECT PGM:1:IN:{source}")

            elif choice == '4':
                me = input("ME number [1]: ").strip() or "1"
                keyer = input("Keyer number [1]: ").strip() or "1"
                self.send_command(f"KEYCUT ME:{me}:{keyer}")

            elif choice == '5':
                me = input("ME number [1]: ").strip() or "1"
                keyer = input("Keyer number [1]: ").strip() or "1"
                self.send_command(f"KEYCUT ME:{me}:{keyer}:OFF")

            elif choice == '6':
                me = input("ME number [1]: ").strip() or "1"
                keyer = input("Keyer number [1]: ").strip() or "1"
                self.send_command(f"KEYAUTO ME:{me}:{keyer}")

            elif choice == '7':
                me = input("ME number [1]: ").strip() or "1"
                keyer = input("Keyer number [1]: ").strip() or "1"
                self.send_command(f"KEYAUTO ME:{me}:{keyer}:OFF")

            elif choice == '8':
                level = input("Level [vid]: ").strip() or "vid"
                dest = input("Destination [1]: ").strip() or "1"
                source = input("Source [1]: ").strip() or "1"
                self.send_command(f"XPT {level} {dest} {source}")

            elif choice == '9':
                salvo = input("Salvo number [1]: ").strip() or "1"
                self.send_command(f"SALVO {salvo}")

            elif choice == '10':
                self._run_production_sequence()

            elif choice == '11':
                self._run_keyer_toggle_test()

            elif choice == 'c':
                cmd = input("Enter raw command: ").strip()
                if cmd:
                    self.send_command(cmd)

            elif choice == 's':
                print(f"\n[STATUS] Connected clients: {len(self.clients)}")

            elif choice == 'q':
                print("\nShutting down...")
                self.running = False
                break

    def _run_production_sequence(self):
        """Run a simulated production sequence."""
        print("\n[SEQUENCE] Starting production sequence simulation...")
        print("[INFO] This will send commands every 2-3 seconds")
        print("[INFO] Press Ctrl+C to stop\n")

        try:
            # Start with camera 1
            self.send_command("SELECT PGM:1:IN:1")
            time.sleep(2)

            # Cut to camera 2
            self.send_command("MECUT ME:1")
            self.send_command("SELECT PGM:1:IN:2")
            time.sleep(3)

            # Bring up keyer 1 (lower thirds)
            self.send_command("KEYCUT ME:1:1")
            time.sleep(2)

            # Cut to camera 3
            self.send_command("MECUT ME:1")
            self.send_command("SELECT PGM:1:IN:3")
            time.sleep(2)

            # Take down keyer 1
            self.send_command("KEYCUT ME:1:1:OFF")
            time.sleep(1)

            # Auto transition to camera 1
            self.send_command("MEAUTO ME:1")
            self.send_command("SELECT PGM:1:IN:1")
            time.sleep(3)

            # Bring up keyer 2 (lyrics)
            self.send_command("KEYCUT ME:1:2")
            time.sleep(3)

            # Take down keyer 2
            self.send_command("KEYCUT ME:1:2:OFF")
            time.sleep(1)

            # Final cut to camera 2
            self.send_command("MECUT ME:1")
            self.send_command("SELECT PGM:1:IN:2")

            print("\n[SEQUENCE] Production sequence complete!")

        except KeyboardInterrupt:
            print("\n[SEQUENCE] Stopped by user")

    def _run_keyer_toggle_test(self):
        """Toggle keyer on and off repeatedly for testing."""
        print("\n[TEST] Starting keyer toggle test...")
        print("[INFO] Will toggle keyer 1 every 3 seconds")
        print("[INFO] Press Ctrl+C to stop\n")

        keyer_on = False
        try:
            while True:
                if keyer_on:
                    self.send_command("KEYCUT ME:1:1:OFF")
                    keyer_on = False
                else:
                    self.send_command("KEYCUT ME:1:1")
                    keyer_on = True
                time.sleep(3)
        except KeyboardInterrupt:
            # Make sure keyer is off when stopping
            if keyer_on:
                self.send_command("KEYCUT ME:1:1:OFF")
            print("\n[TEST] Stopped by user")


def main():
    parser = argparse.ArgumentParser(description='RossTalk Simulator for Touchdrive to Premiere')
    parser.add_argument('--port', '-p', type=int, default=7788, help='Port to listen on (default: 7788)')
    args = parser.parse_args()

    simulator = RossTalkSimulator(port=args.port)

    try:
        simulator.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        if simulator.server_socket:
            simulator.server_socket.close()


if __name__ == '__main__':
    main()
