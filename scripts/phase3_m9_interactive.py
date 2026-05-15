#!/usr/bin/env python3
"""Phase 3 M9 interactive stdin-to-UART wrapper.

Reads tokens from stdin/pipe/comma, maintains M7a active-note state,
and sends UART commands incrementally per token. Dry-run forces no-
serial and prints repr(). Zero firmware/RTL changes.
"""

import sys
import time
from typing import List, Optional, Set

from phase3_m5_keyboard import (midi_to_command, cmd_release, cmd_bare,
                                NOTE_MIN, NOTE_MAX, VELOCITY_MAX, note_name)

DOWN_ALIASES = {"down", "d"}
UP_ALIASES = {"up", "u"}
RELEASE_ALIASES = {"off", "release", "panic", "!f", "all-off"}
QUIT_ALIASES = {"quit", "q", "exit"}


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


def _parse_note_cmd(tok: str) -> Optional[str]:
    """Parse note name, MIDI number, or down:X[:vel] into command string."""
    core = tok
    vel = None
    if ":" in tok:
        parts = tok.split(":")
        if parts[0].lower() in DOWN_ALIASES and len(parts) >= 2:
            core = parts[1]
            if len(parts) >= 3:
                try:
                    vs = parts[2]
                    vel = int(vs, 16) if vs.lower().startswith("0x") else int(vs)
                    vel = max(0, min(VELOCITY_MAX, vel))
                except ValueError:
                    return None
        else:
            return None  # up: events handled separately

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


def _is_up_event(tok: str) -> Optional[int]:
    """Return MIDI note number if token is an up:X/down:X event, else None."""
    if ":" not in tok:
        return None
    parts = tok.split(":")
    if parts[0].lower() in UP_ALIASES and len(parts) >= 2:
        core = parts[1]
        if core.isdigit():
            note = int(core)
        else:
            note = _name_to_midi(core.upper())
        if note is not None and NOTE_MIN <= note <= NOTE_MAX:
            return note
    return None


def _is_down_event(tok: str) -> bool:
    if ":" in tok and tok.split(":")[0].lower() in DOWN_ALIASES:
        return True
    return False


def _resolve_token(tok: str, state) -> Optional[str]:
    """Resolve a single token to a UART command string (or None if suppressed).

    Returns the command string to send, or None if suppressed (up while others active).
    Updates state in-place. Logs to state.log.
    """
    tl = tok.lower().strip()

    # Quit with release
    if tl in QUIT_ALIASES:
        if state.active:
            state.active.clear()
            state.log.append(f"[{tok}] quit -> !F sent")
            return cmd_release()
        state.log.append(f"[{tok}] quit -> no active notes")
        return None

    # Release/panic: always emit !F for operator safety
    if tl in RELEASE_ALIASES:
        state.active.clear()
        state.log.append(f"[{tok}] release -> active=[] -> !F sent")
        return cmd_release()

    # Bare trigger
    if tl in {"bare", "!n"}:
        state.log.append(f"[{tok}] bare -> {cmd_bare()!r}")
        return cmd_bare()

    # Raw !N passthrough
    if tl.startswith("!n") and len(tl) > 2:
        cmd = tok.upper().strip() + "\r\n"
        state.log.append(f"[{tok}] raw -> {cmd!r}")
        return cmd

    # Raw !F
    if tl == "!f":
        if state.active:
            state.active.clear()
        state.log.append(f"[{tok}] raw !F")
        return cmd_release()

    # Up event
    up_note = _is_up_event(tok)
    if up_note is not None:
        if up_note in state.active:
            state.active.discard(up_note)
            if state.active:
                state.log.append(f"[{tok}] up:{note_name(up_note)}({up_note}) -> active={sorted(state.active)} -> suppressed")
                return None
            else:
                state.log.append(f"[{tok}] up:{note_name(up_note)}({up_note}) -> active empty -> !F sent")
                return cmd_release()
        else:
            state.log.append(f"[{tok}] up:{note_name(up_note)}({up_note}) -> already up, suppressed")
            return None

    # Note or down event
    cmd = _parse_note_cmd(tok)
    if cmd is None:
        state.log.append(f"[{tok}] WARN: invalid/unknown token")
        return None

    # Track note for state
    note = None
    if _is_down_event(tok):
        core = tok.split(":")[1]
    else:
        core = tok
    if core.isdigit():
        note = int(core)
    else:
        note = _name_to_midi(core.upper())

    if note is not None and NOTE_MIN <= note <= NOTE_MAX:
        state.active.add(note)
        state.log.append(f"[{tok}] down:{note_name(note)}({note}) -> active={sorted(state.active)} -> {cmd!r}")
    else:
        state.log.append(f"[{tok}] raw -> {cmd!r}")
    return cmd


class M9State:
    def __init__(self):
        self.active: Set[int] = set()
        self.log: List[str] = []
        self.sent_count = 0

    def reset(self):
        self.active.clear()
        self.log.clear()
        self.sent_count = 0


def process_stream(in_stream, send_fn, transcript, state):
    """Read tokens from stream, process per-token with incremental send."""
    for line in in_stream:
        line = line.strip()
        if not line:
            continue
        # Support comma-separated and space-separated
        tokens = []
        for chunk in line.split(","):
            for tok in chunk.split():
                tok = tok.strip()
                if tok:
                    tokens.append(tok)
        for tok in tokens:
            cmd = _resolve_token(tok, state)
            entry = f"[{tok}] "
            if cmd:
                send_fn(cmd)
                state.sent_count += 1
                entry += f"SENT {cmd!r} active={sorted(state.active)}"
            else:
                entry += f"suppressed active={sorted(state.active)}"
            print(entry)
            if transcript:
                transcript.write(entry + "\n")
            if tok.lower() in QUIT_ALIASES:
                return


def self_check() -> bool:
    """Extended self-check."""
    import io
    errors = 0

    def _run(tokens, desc, expected_sent):
        s = M9State()
        sent = sum(1 for tok in tokens if _resolve_token(tok, s) is not None)
        if sent != expected_sent:
            print(f"  FAIL {desc}: expected {expected_sent} sent, got {sent}")
            return False
        print(f"  {desc}: sent={sent} PASS")
        return True

    print("=== M9 self-check ===")
    ok = True
    ok &= _run(["A4", "C5", "off"], "A4,C5,off", 3)
    ok &= _run(["down:A4", "down:C5", "up:A4", "up:C5"], "down/up overlap", 3)
    ok &= _run(["A4", "panic"], "panic", 2)
    ok &= _run(["A4", "off", "C5", "off"], "off after off", 4)
    ok &= _run(["bare"], "bare", 1)
    ok &= _run(["panic"], "empty panic sends !F", 1)

    # CRLF framing
    s = M9State()
    cmd = _resolve_token("A4", s)
    if cmd and cmd.endswith("\r\n"):
        print(f"  CRLF framing: {cmd!r} PASS")
    else:
        print(f"  FAIL: no CRLF in {cmd!r}")
        ok = False

    # quit with active notes
    s = M9State()
    _resolve_token("A4", s)
    cmd = _resolve_token("quit", s)
    if cmd and cmd.strip() == "!F":
        print("  quit with active: !F sent PASS")
    else:
        print(f"  FAIL: quit {cmd!r}")
        ok = False

    if ok:
        print("PASS: all M9 self-checks")
    return ok


def main():
    import argparse
    p = argparse.ArgumentParser(description="Phase 3 M9 interactive wrapper")
    p.add_argument("--port", "-p", default=None, help="COM port for serial send")
    p.add_argument("--baud", "-b", type=int, default=115200)
    p.add_argument("--delay-ms", "-d", type=int, default=80)
    p.add_argument("--dry-run", "-n", action="store_true",
                   help="Force dry-run (no serial even with --port)")
    p.add_argument("--self-check", action="store_true")
    p.add_argument("--transcript", "-t", default=None, help="Write transcript to PATH")
    args = p.parse_args()

    if args.self_check:
        ok = self_check()
        sys.exit(0 if ok else 1)

    state = M9State()
    transcript = open(args.transcript, "w") if args.transcript else None

    use_serial = args.port and not args.dry_run

    if use_serial:
        try:
            import serial
        except ImportError:
            print("ERROR: pyserial required for --port", file=sys.stderr)
            sys.exit(1)
        ser = serial.Serial(args.port, args.baud, timeout=1)
        print(f"Connected to {args.port}")

        def send_fn(cmd):
            ser.write(cmd.encode("ascii"))
            time.sleep(args.delay_ms / 1000.0)
    else:
        def send_fn(cmd):
            print(f"DRY: {cmd!r}")

    process_stream(sys.stdin, send_fn, transcript, state)

    if transcript:
        transcript.close()
    if use_serial:
        ser.close()
    print(f"\nSent {state.sent_count} commands")


if __name__ == "__main__":
    main()
