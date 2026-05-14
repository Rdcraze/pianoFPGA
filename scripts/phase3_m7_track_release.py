#!/usr/bin/env python3
"""Phase 3 M7a host track-and-release wrapper.

Tracks active notes on the host side. Sends !N commands on note-down,
suppresses UART on note-up while other notes remain active, and sends
!F only when the active set becomes empty or on all-off/panic/release.
Zero firmware/RTL changes.
"""

import sys
import time
from typing import List, Optional, Set, Tuple

from phase3_m5_keyboard import (midi_to_command, cmd_release,
                                NOTE_MIN, NOTE_MAX, VELOCITY_MAX, note_name)

RELEASE_ALIASES = {"off", "release", "panic", "!f", "all-off"}
DOWN_ALIASES = {"down", "d"}
UP_ALIASES = {"up", "u"}


class Action:
    """A structured UART command with metadata."""
    def __init__(self, cmd: str, reason: str):
        self.cmd = cmd          # raw UART bytes (includes \r\n)
        self.reason = reason    # human-readable description

    def __repr__(self):
        return f"Action({self.cmd!r}, reason={self.reason!r})"


def _parse_note_event(tok: str) -> Optional[Tuple[bool, int, Optional[int]]]:
    """Parse 'down:A4', 'up:69', 'down:A4:4000' etc.

    Returns (is_down, note_midi, velocity_or_None) or None on failure.
    """
    if ":" not in tok:
        return None
    parts = tok.split(":")
    if parts[0].lower() not in (DOWN_ALIASES | UP_ALIASES):
        return None
    is_down = parts[0].lower() in DOWN_ALIASES
    vel = None

    if len(parts) >= 3 and is_down:
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


def process_events(events: List[str]) -> Tuple[List[Action], List[str]]:
    """Process event list. Returns (actions, log_lines)."""
    active: Set[int] = set()
    actions: List[Action] = []
    log: List[str] = []
    error = False

    for evt in events:
        evt = evt.strip()
        tl = evt.lower()

        # Release/panic/all-off
        if tl in RELEASE_ALIASES:
            if active:
                active.clear()
                actions.append(Action(cmd_release(), f"{evt}: active cleared"))
                log.append(f"  [{evt}] cleared, !F sent")
            else:
                log.append(f"  [{evt}] no active notes, !F suppressed")
            continue

        # Note event
        parsed = _parse_note_event(evt)
        if parsed is None:
            print(f"ERROR: invalid event '{evt}'", file=sys.stderr)
            error = True
            continue

        is_down, note, vel = parsed
        nname = note_name(note)

        if is_down:
            active.add(note)
            cmd = midi_to_command(note, vel) if vel else midi_to_command(note)
            actions.append(Action(cmd, f"down:{nname}({note})"))
            log.append(f"  [{evt}] {nname}({note}) down -> active={sorted(active)} -> {cmd!r}")
        else:
            if note in active:
                active.discard(note)
                if active:
                    log.append(f"  [{evt}] {nname}({note}) up -> active={sorted(active)} -> suppressed")
                else:
                    actions.append(Action(cmd_release(), f"up:{nname}({note}): active empty"))
                    log.append(f"  [{evt}] {nname}({note}) up -> active empty -> !F sent")
            else:
                log.append(f"  [{evt}] {nname}({note}) up -> already up, suppressed")

    if error:
        sys.exit(1)
    return actions, log


def dry_run(events: List[str]):
    """Print events with active-set tracking and repr() command framing."""
    print(f"Events: {events}")
    print()
    actions, log = process_events(events)
    for line in log:
        print(line)
    print(f"\nCommands sent: {len(actions)}")
    for i, a in enumerate(actions):
        print(f"  [{i}] {a.cmd!r} ({a.reason})")


def serial_send(events: List[str], port: str, baud: int = 115200, delay_ms: int = 80):
    """Process events and send structured commands via serial port."""
    try:
        import serial
    except ImportError:
        print("ERROR: pyserial not installed.", file=sys.stderr)
        sys.exit(1)

    actions, _ = process_events(events)

    ser = serial.Serial(port, baud, timeout=1)
    print(f"Connected to {port} at {baud} baud")
    for i, a in enumerate(actions):
        ser.write(a.cmd.encode("ascii"))
        print(f"  [{i}] SENT: {a.cmd!r} ({a.reason})")
        time.sleep(delay_ms / 1000.0)
    ser.close()
    print(f"Sent {len(actions)} commands")


def self_check() -> bool:
    """Extended self-check."""
    import io

    def _get_cmds(events):
        actions, _ = process_events(events)
        return actions

    errors = 0

    # Two-note overlap: 3 commands (down:A4, down:C5, up:C4->!F)
    print("=== Two-note overlap ===")
    actions = _get_cmds(["down:A4", "down:C5", "up:A4", "up:C5"])
    assert len(actions) == 3, f"Expected 3, got {len(actions)}"
    assert "006A" in actions[0].cmd, f"A4 missing: {actions[0].cmd}"
    assert actions[-1].cmd.strip() == "!F", f"Final !F missing: {actions[-1].cmd}"
    cmds_repr = [a.cmd for a in actions]
    print(f"  commands={len(actions)}: {cmds_repr}")
    print("  PASS")

    # Command count: 5 for down:A4,down:C5,up:A4,up:C5,down:C4,panic
    print("=== Command count ===")
    actions = _get_cmds(["down:A4", "down:C5", "up:A4", "up:C5", "down:C4", "panic"])
    assert len(actions) == 5, f"Expected 5 commands, got {len(actions)}"
    cmds_repr = [a.cmd for a in actions]
    print(f"  count={len(actions)}: {cmds_repr}")
    print("  PASS")

    # Panic
    print("=== Panic/all-off ===")
    actions = _get_cmds(["down:A4", "panic"])
    assert len(actions) == 2
    assert actions[-1].cmd.strip() == "!F"
    print("  PASS")

    # Repeated up (stale)
    print("=== Repeated up ===")
    actions = _get_cmds(["down:A4", "up:A4", "up:A4"])
    assert len(actions) == 2
    print("  PASS")

    # Velocity override
    print("=== Velocity override ===")
    actions = _get_cmds(["down:A4:4000", "up:A4"])
    assert "0FA0" in actions[0].cmd
    print(f"  {actions[0].cmd!r}")
    print("  PASS")

    # CRLF framing
    print("=== CRLF framing ===")
    actions = _get_cmds(["down:A4"])
    assert actions[0].cmd.endswith("\r\n")
    print(f"  {actions[0].cmd!r}")
    print("  PASS")

    # Note number input
    print("=== Note number ===")
    actions = _get_cmds(["down:69", "up:69"])
    assert "006A" in actions[0].cmd
    assert actions[-1].cmd.strip() == "!F"
    print("  PASS")

    # Invalid event rejection
    print("=== Invalid event ===")
    try:
        process_events(["invalid"])
        print("  FAIL: no error")
        errors += 1
    except SystemExit:
        print("  correctly rejected")
        print("  PASS")

    if errors:
        print(f"\n{errors} error(s)")
        return False
    print("\nPASS: all M7a extended self-checks")
    return True


def main():
    import argparse
    p = argparse.ArgumentParser(description="Phase 3 M7a track-and-release wrapper")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--events", "-e", default=None,
                   help="Comma-separated events: down:X, up:X, panic, all-off")
    g.add_argument("--sequence", "-s", default=None,
                   help="Alias for --events")
    p.add_argument("--port", "-p", default=None, help="COM port for serial send")
    p.add_argument("--baud", "-b", type=int, default=115200)
    p.add_argument("--delay-ms", "-d", type=int, default=80)
    p.add_argument("--dry-run", "-n", action="store_true", help="Verbose dry-run")
    p.add_argument("--self-check", action="store_true", help="Run self-check")
    args = p.parse_args()

    if args.self_check:
        ok = self_check()
        sys.exit(0 if ok else 1)

    seq = args.events or args.sequence or "down:A4,down:C5,up:A4,up:C5,down:C4,panic"
    events = [e.strip() for e in seq.split(",") if e.strip()]

    if args.port:
        serial_send(events, args.port, args.baud, args.delay_ms)
    else:
        dry_run(events)
        if not args.dry_run:
            print("\nAdd --port COMx for hardware send.")


if __name__ == "__main__":
    main()
