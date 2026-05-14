#!/usr/bin/env python3
"""Phase 3 M7a host track-and-release wrapper.

Tracks active notes on the host side. Sends !N commands on note-down,
suppresses UART on note-up while other notes remain active, and sends
!F only when the active set becomes empty or on all-off/panic/release.
Zero firmware/RTL changes.
"""

import sys
import time
from typing import List, Optional, Set

from phase3_m5_keyboard import (midi_to_command, cmd_release, cmd_bare,
                                NOTE_MIN, NOTE_MAX, VELOCITY_MAX, note_name)

RELEASE_ALIASES = {"off", "release", "panic", "!f", "all-off"}


def _parse_note_event(tok: str) -> Optional[tuple]:
    """Parse 'down:A4', 'up:69', 'down:A4:4000' etc.

    Returns (is_down, note_midi, velocity_or_None) or None on failure.
    """
    if ":" not in tok:
        return None
    parts = tok.split(":")
    if parts[0].lower() not in ("down", "up"):
        return None
    is_down = parts[0].lower() == "down"
    vel = None

    if len(parts) >= 3 and is_down:
        # down:A4:4000 or down:69:0x0FA0
        note_str = parts[1]
        try:
            if parts[2].lower().startswith("0x"):
                vel = int(parts[2], 16)
            else:
                vel = int(parts[2])
            vel = max(0, min(VELOCITY_MAX, vel))
        except ValueError:
            return None
    else:
        # down:A4 or up:A4
        note_str = parts[1]

    if note_str.isdigit():
        note = int(note_str)
    else:
        note = _name_to_midi(note_str)
    if note is None or not (NOTE_MIN <= note <= NOTE_MAX):
        return None
    return (is_down, note, vel)


def _name_to_midi(name: str) -> Optional[int]:
    """Convert note name to MIDI number."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    name = name.upper()
    for octave in range(10):
        for i, n in enumerate(names):
            if name == f"{n}{octave}":
                midi = (octave + 1) * 12 + i
                if NOTE_MIN <= midi <= NOTE_MAX:
                    return midi
                return None
    return None


def process_events(events: List[str], quiet: bool = False) -> int:
    """Process event list. Returns number of UART commands sent."""
    active: Set[int] = set()
    sent = 0

    for evt in events:
        evt = evt.strip()
        tl = evt.lower()

        # Release/panic/all-off
        if tl in RELEASE_ALIASES:
            if active:
                active.clear()
                if not quiet:
                    print(f"  [{evt}] active cleared, sending !F")
                print(cmd_release(), end="")
                sent += 1
            else:
                if not quiet:
                    print(f"  [{evt}] no active notes, !F suppressed")
            continue

        # Note event
        parsed = _parse_note_event(evt)
        if parsed is None:
            print(f"ERROR: invalid event '{evt}'", file=sys.stderr)
            sys.exit(1)

        is_down, note, vel = parsed
        nname = note_name(note)

        if is_down:
            active.add(note)
            cmd = midi_to_command(note, vel) if vel else midi_to_command(note)
            if not quiet:
                print(f"  [{evt}] note {nname}({note}) down -> active={sorted(active)} -> {cmd!r}")
            print(cmd, end="")
            sent += 1
        else:
            if note in active:
                active.discard(note)
                if active:
                    if not quiet:
                        print(f"  [{evt}] note {nname}({note}) up -> active={sorted(active)} -> suppressed")
                else:
                    if not quiet:
                        print(f"  [{evt}] note {nname}({note}) up -> active empty, sending !F")
                    print(cmd_release(), end="")
                    sent += 1
            else:
                if not quiet:
                    print(f"  [{evt}] note {nname}({note}) up -> already up, suppressed")

    return sent


def dry_run(events: List[str]):
    """Print events and commands with active-set tracking."""
    print(f"Events: {events}")
    print()
    process_events(events, quiet=False)


def serial_send(events: List[str], port: str, baud: int = 115200, delay_ms: int = 80):
    """Process events and send commands via serial port."""
    try:
        import serial
    except ImportError:
        print("ERROR: pyserial not installed.", file=sys.stderr)
        sys.exit(1)

    ser = serial.Serial(port, baud, timeout=1)
    print(f"Connected to {port} at {baud} baud")

    # Capture commands by overriding stdout temporarily
    import io
    buf = io.StringIO()
    old_stdout = sys.stdout
    sys.stdout = buf
    process_events(events, quiet=True)
    sys.stdout = old_stdout
    cmds = buf.getvalue()

    for cmd in cmds.split("!N")[1:] if "!N" in cmds else []:
        full = "!N" + cmd
        ser.write(full.encode("ascii"))
        time.sleep(delay_ms / 1000.0)


def self_check() -> bool:
    """Self-check: two-note overlap, partial release, final release, panic."""
    import io

    print("=== Two-note overlap ===")
    events = ["down:A4", "down:C5", "up:A4", "up:C5"]
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    n = process_events(events, quiet=True)
    sys.stdout = old
    cmds = buf.getvalue()
    lines = [l for l in cmds.splitlines() if l and l.startswith("!")]
    # down:A4 -> !N, down:C5 -> !N, up:A4 -> suppressed, up:C5 -> !F = 3 total
    assert len(lines) == 3, f"Expected 3 commands, got {len(lines)}: {lines}"
    assert "006A" in lines[0], f"A4 missing: {lines[0]}"  # A4
    assert "!F" in lines[-1], f"Final !F missing: {lines[-1]}"
    print(f"  commands: {lines}")
    print("  two-note overlap: PASS")

    print("=== Panic/all-off ===")
    events = ["down:A4", "panic"]
    buf = io.StringIO()
    sys.stdout = buf
    process_events(events, quiet=True)
    sys.stdout = old
    cmds = buf.getvalue()
    lines = [l for l in cmds.splitlines() if l and l.startswith("!")]
    assert len(lines) == 2, f"Expected 2: {lines}"
    assert "!F" in lines[-1], f"panic !F missing: {lines[-1]}"
    print(f"  commands: {lines}")
    print("  panic: PASS")

    print("=== Repeated up ===")
    events = ["down:A4", "up:A4", "up:A4"]
    buf = io.StringIO()
    sys.stdout = buf
    process_events(events, quiet=True)
    sys.stdout = old
    cmds = buf.getvalue()
    lines = [l for l in cmds.splitlines() if l and l.startswith("!")]
    assert len(lines) == 2, f"Repeated up: expected 2, got {len(lines)}"
    print(f"  commands: {lines}")
    print("  repeated up: PASS")

    print("=== Velocity override ===")
    events = ["down:A4:4000", "up:A4"]
    buf = io.StringIO()
    sys.stdout = buf
    process_events(events, quiet=True)
    sys.stdout = old
    cmds = buf.getvalue()
    lines = [l for l in cmds.splitlines() if l and l.startswith("!")]
    assert "0FA0" in lines[0], f"vel 4000=0x0FA0 not in: {lines[0]}"
    print(f"  commands: {lines}")
    print("  velocity: PASS")

    print("=== CRLF framing ===")
    events = ["down:A4"]
    buf = io.StringIO()
    sys.stdout = buf
    process_events(events, quiet=True)
    sys.stdout = old
    cmds = buf.getvalue()
    assert "\r\n" in cmds, f"No CRLF in: {cmds!r}"
    print(f"  {cmds!r}")
    print("  CRLF: PASS")

    print("\nPASS: all M7a self-checks")
    return True


def main():
    import argparse
    p = argparse.ArgumentParser(description="Phase 3 M7a track-and-release wrapper")
    p.add_argument("--events", "-e", default="down:A4,down:C5,up:A4,up:C5,down:C4,panic",
                   help="Comma-separated events: down:X, up:X, panic, all-off")
    p.add_argument("--port", "-p", default=None, help="COM port for serial send")
    p.add_argument("--baud", "-b", type=int, default=115200)
    p.add_argument("--delay-ms", "-d", type=int, default=80)
    p.add_argument("--dry-run", "-n", action="store_true", help="Verbose dry-run")
    p.add_argument("--self-check", action="store_true", help="Run self-check")
    args = p.parse_args()

    if args.self_check:
        ok = self_check()
        sys.exit(0 if ok else 1)

    events = [e.strip() for e in args.events.split(",") if e.strip()]

    if args.port:
        serial_send(events, args.port, args.baud, args.delay_ms)
    else:
        dry_run(events)
        if not args.dry_run:
            print("\nAdd --port COMx for hardware send.")


if __name__ == "__main__":
    main()
