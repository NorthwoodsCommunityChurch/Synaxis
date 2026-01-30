#!/usr/bin/env python3
"""
TSL 5.0 Simulator for Touchdrive to Premiere

Connects to the app's TSL listener as a TCP client and sends
simulated TSL UMD 5.0 tally messages, mimicking a Ross Carbonite
switcher. Useful for testing without physical hardware.

Usage:
    python3 tsl_simulator.py [--host HOST] [--port PORT]

The simulator cycles through program cuts on 4 sources every
few seconds, with Carbonite-style labels.
"""

import argparse
import socket
import struct
import time
import sys


def build_tsl5_message(index: int, program: bool, preview: bool, text: str) -> bytes:
    """Build a TSL UMD 5.0 binary message.

    Wire format:
        [0-1]  PBC       (LE u16, payload byte count excluding this field)
        [2]    Version   (0x00)
        [3]    Flags     (0x00)
        [4-5]  Screen    (LE u16, 0x0000)
        [6-7]  Index     (LE u16)
        [8-9]  Control   (LE u16, tally brightness bits)
        [10-11] TextLen  (LE u16)
        [12..] Text      (UTF-8)
    """
    text_bytes = text.encode("utf-8")
    text_len = len(text_bytes)

    # Control byte: bits 0-1 = program brightness (0 or 3), bits 2-3 = preview brightness
    control = 0
    if program:
        control |= 0x03       # tally 1 brightness = 3
    if preview:
        control |= 0x03 << 2  # tally 2 brightness = 3

    # Payload: version(1) + flags(1) + screen(2) + index(2) + control(2) + textlen(2) + text
    pbc = 1 + 1 + 2 + 2 + 2 + 2 + text_len  # = 10 + text_len

    msg = struct.pack("<H", pbc)           # PBC (LE u16)
    msg += struct.pack("<B", 0x00)         # Version
    msg += struct.pack("<B", 0x00)         # Flags
    msg += struct.pack("<H", 0x0000)       # Screen
    msg += struct.pack("<H", index)        # Index
    msg += struct.pack("<H", control)      # Control
    msg += struct.pack("<H", text_len)     # Text length
    msg += text_bytes                      # Text

    return msg


# Simulated sources — Carbonite label format: sourceIndex:busLabel:sourceLabel
SOURCES = [
    (1, "1:ME1PGM:CAM 1"),
    (2, "2:ME1PGM:CAM 2"),
    (3, "3:ME1PGM:CAM 3"),
    (4, "4:ME1PGM:GRAPHICS"),
]


def main():
    parser = argparse.ArgumentParser(description="TSL 5.0 Simulator")
    parser.add_argument("--host", default="127.0.0.1", help="TSL listener host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=5201, help="TSL listener port (default: 5201)")
    parser.add_argument("--interval", type=float, default=3.0, help="Seconds between program cuts (default: 3.0)")
    args = parser.parse_args()

    print(f"Connecting to TSL listener at {args.host}:{args.port}")

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((args.host, args.port))
        print("Connected!")
    except ConnectionRefusedError:
        print(f"Connection refused. Is the app listening on port {args.port}?")
        sys.exit(1)
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

    current_program = 0

    try:
        while True:
            # Send tally state for all sources
            for i, (index, label) in enumerate(SOURCES):
                is_program = i == current_program
                is_preview = i == (current_program + 1) % len(SOURCES)
                msg = build_tsl5_message(index, program=is_program, preview=is_preview, text=label)
                sock.sendall(msg)

                state = []
                if is_program:
                    state.append("PGM")
                if is_preview:
                    state.append("PVW")
                if not state:
                    state.append("---")
                print(f"  Source {index}: {'/'.join(state):>7s}  {label}")

            print(f"--- Program on source {SOURCES[current_program][0]} ---")
            print()

            time.sleep(args.interval)
            current_program = (current_program + 1) % len(SOURCES)

    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
