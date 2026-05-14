#!/usr/bin/env python3
"""Phase 3 M6 live-play wrapper — sends note sequences to FPGA via UART.

Uses the M5 mapper to convert note names to !N commands. Dry-run prints
commands; serial mode sends via COM port. No firmware/RTL changes.
"""

import sys
import time
from typing import List, Optional

# Import M5 mapper from sibling script
from phase3_m5_keyboard import midi_to_command, cmd_release, cmd_bare, note_name

RELEASE_ALIASES = {"off", "release", "panic", "!F"}
BARE_ALIASES = {"bare", "!N"}


def parse_sequence(seq: str) -> List[str]:
    """Parse comma-separated sequence into command strings."""
    tokens = [t.strip() for t in seq.split(",") if t.strip()]
    commands = []
    for tok in tokens:
        tl = tok.lower()
        if tl in RELEASE_ALIASES:
            commands.append(cmd_release())
        elif tl in BARE_ALIASES:
            commands.append(cmd_bare())
        else:
            note = None
            if tok.upper().startswith("!N"):
                commands.append(tok.upper().strip() + "\r\n")
                continue
            if tok.isdigit():
                note = int(tok)
            else:
                note = note_name_to_midi(tok)
            if note is None:
                print(f"WARNING: unknown token '{tok}', skipping", file=sys.stderr)
                continue
            commands.append(midi_to_command(note))
    return commands


def note_name_to_midi(name: str) -> Optional[int]:
    """Convert note name like 'A4' to MIDI number."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    name = name.upper()
    for octave in range(10):
        for i, n in enumerate(names):
            full = f"{n}{octave}"
            if name == full:
                return (octave + 1) * 12 + i
    return None


def dry_run(commands: List[str]):
    """Print commands that would be sent."""
    for i, cmd in enumerate(commands):
        display = cmd.strip()
        print(f"[{i:03d}] {display}")


def serial_send(commands: List[str], port: str, baud: int = 115200, delay_ms: int = 80):
    """Send commands via serial port."""
    try:
        import serial
    except ImportError:
        print("ERROR: pyserial not installed. Install with: pip install pyserial", file=sys.stderr)
        print("Dry-run mode available without pyserial.", file=sys.stderr)
        sys.exit(1)

    ser = serial.Serial(port, baud, timeout=1)
    print(f"Connected to {port} at {baud} baud")
    for i, cmd in enumerate(commands):
        ser.write(cmd.encode("ascii"))
        print(f"[{i:03d}] SENT: {cmd.strip()}")
        time.sleep(delay_ms / 1000.0)
    ser.close()
    print(f"Sent {len(commands)} commands")


def main():
    import argparse
    p = argparse.ArgumentParser(description="Phase 3 M6 live-play wrapper")
    p.add_argument("--sequence", "-s", default="A4,off,C5,off,C4,off",
                   help="Comma-separated note names/numbers + release aliases")
    p.add_argument("--port", "-p", default=None,
                   help="COM port for serial send (e.g. COM3)")
    p.add_argument("--baud", "-b", type=int, default=115200,
                   help="Serial baud rate (default 115200)")
    p.add_argument("--delay-ms", "-d", type=int, default=80,
                   help="Delay between commands in ms (default 80)")
    p.add_argument("--dry-run", "-n", action="store_true",
                   help="Print commands without sending")
    p.add_argument("--self-check", action="store_true",
                   help="Run self-check with example sequence")
    args = p.parse_args()

    if args.self_check:
        seq = "A4,off,C5,off,C4,off,panic,bare"
        print(f"Self-check sequence: {seq}")
        cmds = parse_sequence(seq)
        dry_run(cmds)
        assert len(cmds) == 8, f"Expected 8 commands, got {len(cmds)}"
        assert cmds[0].startswith("!N006A"), f"A4 not found: {cmds[0]}"
        assert cmds[1].strip() == "!F", f"off not !F: {cmds[1]}"
        assert cmds[2].startswith("!N"), f"C5 not !N: {cmds[2]}"
        assert cmds[5].strip() == "!F", f"panic not !F: {cmds[5]}"
        assert cmds[6].strip() == "!F", f"panic not !F: {cmds[6]}"
        assert cmds[7].strip() == "!N", f"bare not !N: {cmds[7]}"
        print("PASS: self-check")
        return

    commands = parse_sequence(args.sequence)

    if args.port:
        serial_send(commands, args.port, args.baud, args.delay_ms)
    else:
        print(f"DRY RUN ({len(commands)} commands):")
        dry_run(commands)
        if not args.dry_run:
            print("\nAdd --port COMx for hardware send, or --dry-run to suppress this message.")


if __name__ == "__main__":
    main()
