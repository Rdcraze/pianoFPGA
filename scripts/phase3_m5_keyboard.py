#!/usr/bin/env python3
"""Phase 3 M5 host-side keyboard-to-UART command mapper.

Maps MIDI note numbers (21-108, A0-C8) to !NLLLLVVVV FPGA UART commands.
Zero firmware/RTL changes required. Uses the accepted M4 command set:
  !N\r\n              — bare trigger (default pitch)
  !NLLLLVVVV\r\n       — parameterized note (loop_len, velocity)
  !F\r\n              — release all voices
"""

import sys
import math

# Waveguide sample rate (Hz)
FS = 46875.0

# A4 reference
A4_MIDI = 69
A4_FREQ = 440.0  # Hz
A4_LOOP_LEN = 106  # rounded integer

# Velocity range
VELOCITY_MAX = 0x7FFF
VELOCITY_DEFAULT = VELOCITY_MAX

# Loop length range (from RTL clamp)
LOOP_MIN = 32
LOOP_MAX = 127

# MIDI note range
NOTE_MIN = 21  # A0
NOTE_MAX = 108  # C8


def midi_to_freq(note: int) -> float:
    """Convert MIDI note number to frequency in Hz."""
    return A4_FREQ * (2.0 ** ((note - A4_MIDI) / 12.0))


def freq_to_loop_len(freq: float) -> int:
    """Convert frequency in Hz to waveguide loop length.
    Calibrated so A4 (440 Hz) maps exactly to A4_LOOP_LEN = 106."""
    raw = round(A4_LOOP_LEN * A4_FREQ / freq)
    return max(LOOP_MIN, min(LOOP_MAX, raw))


def midi_to_command(note: int, velocity: int = VELOCITY_DEFAULT) -> str:
    """Generate !NLLLLVVVV command for a MIDI note number."""
    freq = midi_to_freq(note)
    loop_len = freq_to_loop_len(freq)
    vel = max(0, min(VELOCITY_MAX, velocity))
    return f"!N{loop_len:04X}{vel:04X}\r\n"


def note_name(note: int) -> str:
    """Return note name for a MIDI note number (e.g. A4, C#5)."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    octave = (note // 12) - 1
    name = names[note % 12]
    return f"{name}{octave}"


def self_check() -> bool:
    """Verify all 88 keys produce valid command strings."""
    errors = 0
    for note in range(NOTE_MIN, NOTE_MAX + 1):
        cmd = midi_to_command(note)
        if not cmd.startswith("!N"):
            print(f"FAIL {note_name(note)}: missing !N prefix: {cmd.strip()}")
            errors += 1
            continue
        loop_hex = cmd[2:6]
        vel_hex = cmd[6:10]
        try:
            loop_len = int(loop_hex, 16)
            velocity = int(vel_hex, 16)
        except ValueError:
            print(f"FAIL {note_name(note)}: invalid hex in {cmd.strip()}")
            errors += 1
            continue
        if not (LOOP_MIN <= loop_len <= LOOP_MAX):
            print(f"FAIL {note_name(note)}: loop_len={loop_len} out of range")
            errors += 1
        if not (0 <= velocity <= VELOCITY_MAX):
            print(f"FAIL {note_name(note)}: velocity={velocity:#x} out of range")
            errors += 1
    # A4 exact match
    a4_cmd = midi_to_command(69)
    if a4_cmd.strip() != "!N006A7FFF":
        print(f"FAIL A4: expected !N006A7FFF, got {a4_cmd.strip()}")
        errors += 1
    else:
        print("A4=0x6A: PASS")

    # note/name equivalence
    for midi, name in [(21, "A0"), (60, "C4"), (69, "A4"), (108, "C8")]:
        cmd_note = midi_to_command(midi)
        freq = A4_FREQ * (2.0 ** ((midi - A4_MIDI) / 12.0))
        vel = VELOCITY_DEFAULT
        cmd_name = midi_to_command(midi, vel)
        if cmd_note != cmd_name:
            print(f"FAIL {name}/MIDI{midi}: note={cmd_note.strip()} name={cmd_name.strip()}")
            errors += 1
        else:
            print(f"{name}/MIDI{midi} equiv: PASS")

    # Release aliases
    for alias in ["release", "off", "panic"]:
        if cmd_release().strip() != "!F":
            print(f"FAIL {alias}: expected !F, got {cmd_release().strip()}")
            errors += 1
        else:
            print(f"{alias}=!F: PASS")

    if errors:
        print(f"\n{errors} error(s) found")
    else:
        print(f"PASS: all {NOTE_MAX - NOTE_MIN + 1} notes + A4 exact + name equiv + release aliases")
    return errors == 0


def print_mapping():
    """Print note-to-command mapping table."""
    print(f"{'Note':>4} {'MIDI':>4} {'Freq(Hz)':>9} {'LoopLen':>8} {'Command':>16}")
    print("-" * 50)
    for note in range(NOTE_MIN, NOTE_MAX + 1):
        freq = midi_to_freq(note)
        loop_len = freq_to_loop_len(freq)
        name = note_name(note)
        cmd = f"!N{loop_len:04X}7FFF"
        print(f"{name:>4} {note:>4} {freq:>9.2f} {loop_len:>8} {cmd:>16}")


def cmd_release() -> str:
    return "!F\r\n"


def cmd_bare() -> str:
    return "!N\r\n"


def main():
    if len(sys.argv) < 2:
        print("Usage: phase3_m5_keyboard.py <command> [args]")
        print("  self-check          — validate all 88 keys")
        print("  map                 — print note-to-loop mapping table")
        print("  note <MIDI> [vel]   — print command for a MIDI note (21-108)")
        print("  name <name> [vel]   — print command for a note name (e.g. A4)")
        print("  release             — print all-notes-release command")
        print("  bare                — print bare trigger command")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "self-check":
        ok = self_check()
        sys.exit(0 if ok else 1)
    elif cmd == "map":
        print_mapping()
    elif cmd == "note":
        if len(sys.argv) < 3:
            print("Usage: ... note <MIDI_number> [velocity]", file=sys.stderr)
            sys.exit(1)
        note = int(sys.argv[2])
        vel = int(sys.argv[3], 0) if len(sys.argv) > 3 else VELOCITY_DEFAULT
        if not (NOTE_MIN <= note <= NOTE_MAX):
            print(f"ERROR: MIDI note {note} out of range ({NOTE_MIN}-{NOTE_MAX})", file=sys.stderr)
            sys.exit(1)
        print(midi_to_command(note, vel), end="")
    elif cmd == "name":
        if len(sys.argv) < 3:
            print("Usage: ... name <note_name> [velocity]", file=sys.stderr)
            sys.exit(1)
        name = sys.argv[2].upper()
        names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        # Parse note name like "A4" or "C#5"
        for octave in range(10):
            for i, n in enumerate(names):
                full = f"{n}{octave}"
                if name == full:
                    note = (octave + 1) * 12 + i
                    if NOTE_MIN <= note <= NOTE_MAX:
                        vel = int(sys.argv[3], 0) if len(sys.argv) > 3 else VELOCITY_DEFAULT
                        print(midi_to_command(note, vel), end="")
                        sys.exit(0)
        print(f"ERROR: unknown note name '{sys.argv[2]}'", file=sys.stderr)
        sys.exit(1)
    elif cmd in ("release", "off", "panic"):
        print(cmd_release(), end="")
    elif cmd == "bare":
        print(cmd_bare(), end="")
    else:
        print(f"ERROR: unknown command '{cmd}'", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
