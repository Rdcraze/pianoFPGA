#!/usr/bin/env python3
"""Phase 3 M6 live-play wrapper - sends note sequences to FPGA via UART.

Uses the M5 mapper to convert note names to !N commands. Dry-run prints
commands; serial mode sends via COM port. No firmware/RTL changes.
"""

import sys
import time
from typing import List, Optional

# Import M5 mapper from sibling script
from phase3_m5_keyboard import (midi_to_command, cmd_release, cmd_bare,
                                note_name, NOTE_MIN, NOTE_MAX, VELOCITY_MAX)

RELEASE_ALIASES = {"off", "release", "panic", "!f"}
BARE_ALIASES = {"bare", "!n"}


def _parse_velocity(tok: str) -> Optional[int]:
    """Parse velocity from token suffix like A4:4000 or 69:0x0FA0."""
    if ":" not in tok:
        return None
    _, vs = tok.rsplit(":", 1)
    try:
        if vs.lower().startswith("0x"):
            v = int(vs, 16)
        else:
            v = int(vs)
        return max(0, min(VELOCITY_MAX, v))
    except ValueError:
        return None


def _strip_vel(tok: str) -> str:
    """Remove velocity suffix from token."""
    return tok.rsplit(":", 1)[0] if ":" in tok else tok


def note_name_to_midi(name: str) -> Optional[int]:
    """Convert note name like 'A4' to MIDI number."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    name = name.upper()
    for octave in range(10):
        for i, n in enumerate(names):
            full = f"{n}{octave}"
            if name == full:
                midi = (octave + 1) * 12 + i
                if NOTE_MIN <= midi <= NOTE_MAX:
                    return midi
                return None  # out of range
    return None


def parse_sequence(seq: str) -> List[str]:
    """Parse comma-separated sequence into command strings.

    Supports: note names (A4), MIDI numbers (69), velocity overrides
    (A4:4000, 69:0x0FA0), release aliases (off, release, panic, !F),
    bare trigger (bare, !N), and raw !N passthrough (!N006A7FFF).
    """
    tokens = [t.strip() for t in seq.split(",") if t.strip()]
    commands = []
    errors = 0
    for tok in tokens:
        vel = _parse_velocity(tok)
        core = _strip_vel(tok)
        tl = core.lower()

        if tl in RELEASE_ALIASES:
            commands.append(cmd_release())
            continue
        if tl in BARE_ALIASES:
            commands.append(cmd_bare())
            continue

        # Raw !N passthrough
        if core.upper().startswith("!N") and len(core) > 2:
            cmd = core.upper().strip()
            if not cmd.endswith("\r\n"):
                cmd += "\r\n"
            commands.append(cmd)
            continue

        # Numeric MIDI
        note = None
        if core.isdigit():
            note = int(core)
        else:
            note = note_name_to_midi(core)

        if note is None:
            print(f"ERROR: out-of-range or unknown token '{tok}'", file=sys.stderr)
            errors += 1
            continue

        if not (NOTE_MIN <= note <= NOTE_MAX):
            print(f"ERROR: MIDI {note} out of range ({NOTE_MIN}-{NOTE_MAX})", file=sys.stderr)
            errors += 1
            continue

        if vel is not None:
            commands.append(midi_to_command(note, vel))
        else:
            commands.append(midi_to_command(note))

    if errors:
        print(f"ERROR: {errors} invalid token(s)", file=sys.stderr)
        sys.exit(1)
    return commands


def dry_run(commands: List[str]):
    """Print commands with inspectable CRLF framing."""
    for i, cmd in enumerate(commands):
        print(f"[{i:03d}] {cmd!r}")


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
        print(f"[{i:03d}] SENT: {cmd!r}")
        time.sleep(delay_ms / 1000.0)
    ser.close()
    print(f"Sent {len(commands)} commands")


def self_check() -> bool:
    """Extended self-check."""
    errors = 0
    print("=== Note names ===")
    for name in ["A0", "C4", "A4", "C8"]:
        cmds = parse_sequence(name)
        assert len(cmds) == 1, f"{name}: expected 1 cmd"
        print(f"  {name}: {cmds[0]!r}")
    print("  note names: PASS")

    print("=== Velocity override ===")
    cmds = parse_sequence("A4:4000")
    assert len(cmds) == 1
    assert "0FA0" in cmds[0], f"vel 4000=0x0FA0 not found: {cmds[0]!r}"
    print(f"  A4:4000 -> {cmds[0]!r}")
    cmds = parse_sequence("69:0x7FFF")
    assert "7FFF" in cmds[0], f"vel 7FFF not found: {cmds[0]!r}"
    print(f"  69:0x7FFF -> {cmds[0]!r}")
    print("  velocity override: PASS")

    print("=== Release/bare aliases ===")
    for alias in ["off", "release", "panic", "!F"]:
        cmds = parse_sequence(alias)
        assert cmds[0].strip() == "!F", f"{alias}: {cmds[0]!r}"
        print(f"  {alias}: {cmds[0]!r}")
    for alias in ["bare", "!N"]:
        cmds = parse_sequence(alias)
        assert cmds[0].strip() == "!N", f"{alias}: {cmds[0]!r}"
        print(f"  {alias}: {cmds[0]!r}")
    print("  release/bare: PASS")

    print("=== Raw !N passthrough ===")
    cmds = parse_sequence("!N006A7FFF")
    assert "!N006A7FFF" in cmds[0], f"raw passthrough: {cmds[0]!r}"
    print(f"  !N006A7FFF -> {cmds[0]!r}")
    print("  raw passthrough: PASS")

    print("=== Out-of-range rejection ===")
    try:
        parse_sequence("999")
        print("  FAIL: no error for MIDI 999")
        errors += 1
    except SystemExit:
        print("  MIDI 999: correctly rejected")
    try:
        parse_sequence("Z9")
        print("  FAIL: no error for Z9")
        errors += 1
    except SystemExit:
        print("  Z9: correctly rejected")
    print("  out-of-range: PASS")

    print("=== CRLF framing ===")
    cmds = parse_sequence("A4")
    assert cmds[0].endswith("\r\n"), f"no CRLF: {cmds[0]!r}"
    print(f"  A4 framed: {cmds[0]!r}")
    print("  CRLF: PASS")

    if errors:
        print(f"\n{errors} error(s)")
        return False
    print("\nPASS: all extended self-checks")
    return True


def main():
    import argparse
    p = argparse.ArgumentParser(description="Phase 3 M6 live-play wrapper")
    p.add_argument("--sequence", "-s", default="A4,off,C5,off,C4,off",
                   help="Comma-separated notes + release/bare tokens")
    p.add_argument("--port", "-p", default=None,
                   help="COM port for serial send (e.g. COM3)")
    p.add_argument("--baud", "-b", type=int, default=115200)
    p.add_argument("--delay-ms", "-d", type=int, default=80,
                   help="Delay between commands in ms (default 80)")
    p.add_argument("--dry-run", "-n", action="store_true",
                   help="Print commands without sending")
    p.add_argument("--self-check", action="store_true",
                   help="Run extended self-check")
    args = p.parse_args()

    if args.self_check:
        ok = self_check()
        sys.exit(0 if ok else 1)

    commands = parse_sequence(args.sequence)

    if args.port:
        serial_send(commands, args.port, args.baud, args.delay_ms)
    else:
        print(f"DRY RUN ({len(commands)} commands):")
        dry_run(commands)
        if not args.dry_run:
            print("\nAdd --port COMx for hardware send, or --dry-run to suppress.")


if __name__ == "__main__":
    main()
