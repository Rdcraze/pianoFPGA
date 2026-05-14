#!/usr/bin/env python3
"""Phase 3 M9 interactive stdin-to-UART wrapper.

Reads tokens from stdin (or file/pipe), maintains M7a active-note state,
and sends UART commands. Dry-run mode prints repr() commands. Serial
mode sends via pyserial. Zero firmware/RTL changes.
"""

import sys
import time
from typing import List, Optional, Set

from phase3_m5_keyboard import (midi_to_command, cmd_release, cmd_bare,
                                NOTE_MIN, NOTE_MAX, VELOCITY_MAX, note_name)

DOWN_ALIASES = {"down", "d"}
UP_ALIASES = {"up", "u"}
RELEASE_ALIASES = {"off", "release", "panic", "!f", "all-off", "quit", "q", "exit"}


def _parse_token(tok: str) -> Optional[str]:
    """Parse a single token and return the UART command string or None.

    Supports: note names (A4), MIDI numbers (69), down/up events,
    velocity overrides (A4:4000), release/bare aliases, raw !N/!F.
    """
    tl = tok.lower().strip()

    if tl in RELEASE_ALIASES:
        return cmd_release()
    if tl in {"bare", "!n"}:
        return cmd_bare()

    # Raw passthrough
    if tl.startswith("!n") and len(tl) > 2:
        return (tok.upper().strip() + "\r\n")
    if tl == "!f":
        return cmd_release()

    # Parse event or note
    is_down = True
    core = tok
    vel = None

    if ":" in tok:
        parts = tok.split(":")
        if parts[0].lower() in DOWN_ALIASES:
            is_down = True
            core = parts[1]
            if len(parts) >= 3:
                try:
                    vs = parts[2]
                    vel = int(vs, 16) if vs.lower().startswith("0x") else int(vs)
                    vel = max(0, min(VELOCITY_MAX, vel))
                except ValueError:
                    return None
        elif parts[0].lower() in UP_ALIASES:
            return None  # handled by M7a state machine, not here

    # Note name or MIDI number
    note = None
    if core.isdigit():
        note = int(core)
    else:
        note = _name_to_midi(core.upper())
    if note is None or not (NOTE_MIN <= note <= NOTE_MAX):
        return None

    if vel is not None:
        return midi_to_command(note, vel)
    return midi_to_command(note)


def _name_to_midi(name: str) -> Optional[int]:
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    for octave in range(10):
        for i, n in enumerate(names):
            if name == f"{n}{octave}":
                midi = (octave + 1) * 12 + i
                if NOTE_MIN <= midi <= NOTE_MAX:
                    return midi
                return None
    return None


class M9State:
    """Tracks active notes per M7a semantics."""
    def __init__(self):
        self.active: Set[int] = set()
        self.actions: List[str] = []
        self.log: List[str] = []

    def down(self, note: int, cmd: str):
        self.active.add(note)
        self.actions.append(cmd)
        self.log.append(f"down:{note_name(note)}({note}) -> active={sorted(self.active)} -> {cmd!r}")

    def up(self, note: int):
        if note in self.active:
            self.active.discard(note)
            if self.active:
                self.log.append(f"up:{note_name(note)}({note}) -> active={sorted(self.active)} -> suppressed")
            else:
                self.actions.append(cmd_release())
                self.log.append(f"up:{note_name(note)}({note}) -> active empty -> !F sent")
        else:
            self.log.append(f"up:{note_name(note)}({note}) -> already up, suppressed")

    def release(self):
        if self.active:
            self.active.clear()
            self.actions.append(cmd_release())
            self.log.append("release -> !F sent")
        else:
            self.log.append("release -> no active notes")


def process_tokens(tokens: List[str], state: M9State):
    """Process tokens one at a time, updating state."""
    for tok in tokens:
        tok = tok.strip()
        if not tok:
            continue
        tl = tok.lower()

        # Release
        if tl in RELEASE_ALIASES:
            state.release()
            if tl in {"quit", "q", "exit"}:
                break
            continue

        # Up event
        if ":" in tok:
            parts = tok.split(":")
            if parts[0].lower() in UP_ALIASES:
                core = parts[1]
                note = None
                if core.isdigit():
                    note = int(core)
                else:
                    note = _name_to_midi(core.upper())
                if note is not None and NOTE_MIN <= note <= NOTE_MAX:
                    state.up(note)
                else:
                    state.log.append(f"WARN: invalid up token '{tok}'")
                continue

        # Down or simple note: resolve to command
        cmd = _parse_token(tok)
        if cmd is None:
            state.log.append(f"WARN: unknown token '{tok}'")
            continue

        # Find note number for tracking
        note = None
        if ":" in tok:
            core = tok.split(":")[1]
        else:
            core = tok
        if core.isdigit():
            note = int(core)
        else:
            note = _name_to_midi(core.upper())

        if note is not None and NOTE_MIN <= note <= NOTE_MAX:
            state.down(note, cmd)
        else:
            # Bare !N or raw passthrough: no note tracking
            state.actions.append(cmd)
            state.log.append(f"bare/raw -> {cmd!r}")


def interactive_loop(state: M9State, send_fn, transcript=None):
    """Read tokens from stdin, process, send/suppress."""
    print("M9 interactive (tokens: A4, C5, off, panic, quit)")
    tokens_buf = []
    for line in sys.stdin:
        tokens = line.strip().split()
        if not tokens:
            continue
        if tokens[0].lower() in {"quit", "q", "exit"}:
            state.release()
            break
        process_tokens(tokens, state)
    # Send accumulated actions
    for cmd in state.actions:
        send_fn(cmd)
        if transcript:
            transcript.write(f"SEND: {cmd!r}\n")
    # Write log
    for entry in state.log:
        print(entry)
        if transcript:
            transcript.write(entry + "\n")


def self_check() -> bool:
    """Quick self-check."""
    print("=== M9 self-check ===")
    s = M9State()
    process_tokens(["A4", "C5", "off"], s)
    assert len(s.actions) == 3, f"Expected 3 actions, got {len(s.actions)}"
    assert "006A" in s.actions[0], f"A4: {s.actions[0]!r}"
    assert s.actions[-1].strip() == "!F", f"off: {s.actions[-1]!r}"
    print("  actions:", [a for a in s.actions])
    print("  PASS")
    return True


def main():
    import argparse
    p = argparse.ArgumentParser(description="Phase 3 M9 interactive wrapper")
    p.add_argument("--port", "-p", default=None, help="COM port for serial send")
    p.add_argument("--baud", "-b", type=int, default=115200)
    p.add_argument("--delay-ms", "-d", type=int, default=80)
    p.add_argument("--dry-run", "-n", action="store_true", help="Print commands, no serial")
    p.add_argument("--self-check", action="store_true", help="Run self-check")
    p.add_argument("--transcript", "-t", default=None, help="Write transcript to PATH")
    args = p.parse_args()

    if args.self_check:
        ok = self_check()
        sys.exit(0 if ok else 1)

    state = M9State()
    transcript = open(args.transcript, "w") if args.transcript else None

    if args.port:
        try:
            import serial
        except ImportError:
            print("ERROR: pyserial required for --port", file=sys.stderr)
            sys.exit(1)
        ser = serial.Serial(args.port, args.baud, timeout=1)

        def send_fn(cmd):
            ser.write(cmd.encode("ascii"))
            print(f"SENT: {cmd!r}")
            time.sleep(args.delay_ms / 1000.0)
    else:

        def send_fn(cmd):
            print(f"DRY: {cmd!r}")

    interactive_loop(state, send_fn, transcript)

    if transcript:
        transcript.close()
    if args.port:
        ser.close()


if __name__ == "__main__":
    main()
