#!/usr/bin/env python3
"""Phase 6 M6.5 damp_mix sweep host harness.

Drives the live M5 RTL UART command path through a hardware serial
port to sweep the runtime damp_mix knob across a configurable grid
and capture an isolated single-voice strike at each (damp_mix, pitch)
cell.

The damp_mix parameter controls the damping feedback coefficient in
the Karplus-Strong loop. Higher damp_mix values (closer to 0x7FFF)
mean less damping per sample, resulting in longer sustain. Lower
damp_mix values (closer to 0x0000) mean more damping per sample,
resulting in shorter sustain (faster decay).

Commands emitted (all accepted by the M2/M5 parser):

    !I1\\r\\n             enable single-voice isolation mode
    !I0\\r\\n             disable single-voice isolation mode
    !D<vvvv>\\r\\n        set runtime damp_mix to a 4-hex-digit value
                         (range 0x0000..0x7FFF)
    !F\\r\\n              release/silence (in isolation mode also
                         hard-resets voice0)
    !NLLLLVVVV\\r\\n      parameterized note (loop_len 32..127,
                         velocity 0..0x7FFF)

Per-cell pacing within a damp_mix row:

    1. Send !D<vvvv> once per damp_mix value, wait 100 ms for
       register update to propagate.
    2. For each pitch in the row:
       a. Send !F to silence prior ringing (and reset voice0
          under isolation).
       b. Wait SETTLE_S (1.0 s).
       c. Record send timestamp.
       d. Send !NLLLLVVVV.
       e. Wait CAPTURE_S (4.0 s) for the strike to be captured.
       f. Wait PAUSE_S (1.0 s) before the next cell.

Sidecar JSON format written by --run mode:

    {
        "schema": "phase6_m6_5_damp_sweep.v1",
        "port": "COM5",
        "baud": 115200,
        "settle_s": 1.0,
        "capture_s": 4.0,
        "pause_s": 1.0,
        "damp_settle_s": 0.1,
        "session_start_unix": 1234567890.123,
        "single_voice_isolate": true,
        "pre_commands": [
            {"command": "!I1", "send_t_session_s": 0.005},
            ...
        ],
        "cells": [
            {"index": 0,
             "damp_mix": 0, "damp_mix_hex": "0x0000",
             "loop_len": 106, "velocity": 32767,
             "pitch_name": "A4",
             "command": "!N006A7FFF",
             "send_t_session_s": [3.234]},
            ...
        ],
        "post_commands": [
            {"command": "!F",  "send_t_session_s": 87.10},
            {"command": "!I0", "send_t_session_s": 87.15}
        ]
    }

Each cell's `send_t_session_s` is a list (length 1 today) of
relative session times at which the bench called serial.write() for
the !N strike command. Verifier uses these timestamps plus the
audio capture start unix time to align segments.

Modes:
    --self-check         Run fixed-vector validation, exit 0 on PASS.
                         Does not require pyserial.
    --plan               Print the grid and per-cell command bytes
                         without opening hardware. Does not require
                         pyserial.
    --run --port COM5    Drive hardware. Writes a sidecar JSON next
                         to the optional --sidecar path (default
                         reports/phase6_m6_5_damp_sweep_session.json).

No --analyze mode is provided; the verifier will use custom
tail-slope analysis for damp_mix characterization.
"""

import argparse
import json
import sys
import time
from typing import Dict, List

# -- Grid definition --
# damp_mix range: 0x0000..0x7FFF (Q15 unsigned fraction).
# Higher = longer sustain, lower = shorter sustain.
DEFAULT_DAMP_MIX_GRID = [0x0000, 0x0800, 0x1000, 0x2000, 0x4000, 0x6000, 0x7FFF]

DEFAULT_PITCH_GRID = [
    {"loop_len": 106, "pitch_name": "A4"},
    {"loop_len": 89,  "pitch_name": "C5"},
]

DEFAULT_VELOCITY = 0x7FFF

# Per-cell pacing.
SETTLE_S = 1.0
CAPTURE_S = 4.0
PAUSE_S = 1.0

# Time after !D before the first per-cell !F.
DAMP_SETTLE_S = 0.1

# Pre/post pacing (small).
PRE_AFTER_I1_S = 0.1
POST_BEFORE_I0_S = 0.05

DEFAULT_PORT = "COM5"
DEFAULT_BAUD = 115200
DEFAULT_SIDECAR = "reports/phase6_m6_5_damp_sweep_session.json"

# UART command bytes (constants, no new syntax).
ISOLATE_ENABLE = b"!I1\r\n"
ISOLATE_DISABLE = b"!I0\r\n"


# ---- Builders ----------------------------------------------------------


def parse_hex_list(spec: str) -> List[int]:
    """Parse a comma-separated list of hex or decimal integers.

    Values must be in range 0x0000..0x7FFF for damp_mix.
    """
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        v = int(tok, 16) if tok.lower().startswith("0x") else int(tok, 0)
        if not (0 <= v <= 0x7FFF):
            raise ValueError(
                "damp_mix value out of range 0..0x7FFF: {}".format(tok))
        out.append(v)
    if not out:
        raise ValueError("empty damp_mix grid")
    return out


def parse_pitch_list(spec: str) -> List[Dict]:
    """Parse a comma-separated list of pitch tokens.

    Each token is either NAME:LOOPLEN (e.g. A4:106) or a bare
    loop_len integer.
    """
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if ":" in tok:
            name, ll = tok.split(":", 1)
            loop_len = int(ll, 0)
        else:
            name = "loop{}".format(tok)
            loop_len = int(tok, 0)
        if not (32 <= loop_len <= 127):
            raise ValueError(
                "loop_len out of range 32..127: {}".format(loop_len))
        out.append({"loop_len": loop_len, "pitch_name": name})
    if not out:
        raise ValueError("empty pitch grid")
    return out


def build_damp_mix_command(damp_mix: int) -> bytes:
    """Build the !D<vvvv>\\r\\n command bytes for a damp_mix value.

    damp_mix must be in range 0x0000..0x7FFF.
    """
    if not (0 <= damp_mix <= 0x7FFF):
        raise ValueError("damp_mix out of range 0..0x7FFF")
    return ("!D{:04X}\r\n".format(damp_mix)).encode("ascii")


def build_note_command(loop_len: int, velocity: int) -> bytes:
    """Build the !NLLLLVVVV\\r\\n command bytes."""
    if not (32 <= loop_len <= 127):
        raise ValueError("loop_len out of range 32..127")
    if not (0 <= velocity <= 0x7FFF):
        raise ValueError("velocity out of range 0..0x7FFF")
    return ("!N{:04X}{:04X}\r\n".format(loop_len, velocity)).encode("ascii")


def build_grid(damp_mix_values: List[int],
               pitches: List[Dict],
               velocity: int) -> List[Dict]:
    """Build the full cell grid for the sweep."""
    cells = []
    idx = 0
    for dm in damp_mix_values:
        for p in pitches:
            ll = p["loop_len"]
            cmd_ascii = "!N{:04X}{:04X}".format(ll, velocity)
            cells.append({
                "index": idx,
                "damp_mix": dm,
                "damp_mix_hex": "0x{:04X}".format(dm),
                "loop_len": ll,
                "velocity": velocity,
                "pitch_name": p["pitch_name"],
                "command_ascii": cmd_ascii,
                "command_bytes": (cmd_ascii + "\r\n").encode("ascii"),
                "damp_mix_command_bytes": build_damp_mix_command(dm),
            })
            idx += 1
    return cells


def cmd_release_bytes() -> bytes:
    """Return the !F\\r\\n release command bytes."""
    return b"!F\r\n"


def session_duration_s(damp_mix_values: List[int],
                       pitches: List[Dict],
                       single_voice_isolate: bool) -> float:
    """Estimate total session duration in seconds."""
    n_dm = len(damp_mix_values)
    n_pitch = len(pitches)
    per_cell = SETTLE_S + CAPTURE_S + PAUSE_S
    per_dm = DAMP_SETTLE_S + n_pitch * per_cell
    total = n_dm * per_dm
    if single_voice_isolate:
        total += PRE_AFTER_I1_S + POST_BEFORE_I0_S
    return total


def expected_command_counts(damp_mix_values: List[int],
                            pitches: List[Dict],
                            single_voice_isolate: bool) -> Dict[str, int]:
    """Return a per-command and total count breakdown.

    Every emitted command is a valid M2/M5 accepted command and is
    expected to increment the device's command counter Q by exactly
    one. The harness emits no malformed commands, so the device's
    error counter X should remain 0 for the whole session.
    """
    n_dm = len(damp_mix_values)
    n_pitch = len(pitches)
    n_d = n_dm                        # one !D per damp_mix value
    n_f = n_dm * n_pitch + 1          # per-cell !F + one trailing !F
    n_n = n_dm * n_pitch              # one !N per cell
    n_i1 = 1 if single_voice_isolate else 0
    n_i0 = 1 if single_voice_isolate else 0
    total = n_d + n_f + n_n + n_i1 + n_i0
    return {
        "I1": n_i1,
        "D":  n_d,
        "F":  n_f,
        "N":  n_n,
        "I0": n_i0,
        "total": total,
    }


# ---- Bench run ----------------------------------------------------------


def run_bench(port: str, baud: int, sidecar_path: str,
              damp_mix_values: List[int],
              pitches: List[Dict],
              velocity: int,
              settle_s: float, capture_s: float, pause_s: float,
              damp_settle_s: float,
              single_voice_isolate: bool) -> int:
    """Drive hardware via serial port and write sidecar JSON."""
    try:
        import serial  # type: ignore
    except ImportError:
        print(
            "ERROR: pyserial is required for --run. "
            "Install with: pip install pyserial",
            file=sys.stderr,
        )
        return 2

    try:
        ser = serial.Serial(port, baud, timeout=1.0)
    except Exception as exc:
        print("ERROR: cannot open {} at {} baud: {}".format(port, baud, exc),
              file=sys.stderr)
        return 2

    cells = build_grid(damp_mix_values, pitches, velocity)
    session_start = time.monotonic()
    session_unix = time.time()

    sidecar = {
        "schema": "phase6_m6_5_damp_sweep.v1",
        "port": port,
        "baud": baud,
        "settle_s": settle_s,
        "capture_s": capture_s,
        "pause_s": pause_s,
        "damp_settle_s": damp_settle_s,
        "single_voice_isolate": single_voice_isolate,
        "session_start_unix": session_unix,
        "damp_mix_grid": ["0x{:04X}".format(v) for v in damp_mix_values],
        "pitch_grid": [
            {"loop_len": p["loop_len"], "pitch_name": p["pitch_name"]}
            for p in pitches
        ],
        "velocity_hex": "0x{:04X}".format(velocity),
        "pre_commands": [],
        "cells": [],
        "post_commands": [],
    }

    counts = expected_command_counts(damp_mix_values, pitches,
                                     single_voice_isolate)
    duration = session_duration_s(damp_mix_values, pitches,
                                  single_voice_isolate)
    print(
        "Phase 6 M6.5 damp_mix sweep: {} damp_mix x {} pitch = {} cells, "
        "total {:.1f} s + setup".format(
            len(damp_mix_values), len(pitches), len(cells), duration),
        file=sys.stderr,
    )
    print(
        "Expected device command counts: !I1={} !D={} !F={} !N={} !I0={} "
        "(total {} valid commands; X expected 0)".format(
            counts["I1"], counts["D"], counts["F"], counts["N"],
            counts["I0"], counts["total"]),
        file=sys.stderr,
    )
    print(
        "Start audio capture now and record the audio start unix time. "
        "Sidecar session_start_unix={:.3f}".format(session_unix),
        file=sys.stderr,
    )
    # Give the operator 3 s to start audio capture if needed.
    time.sleep(3.0)

    if single_voice_isolate:
        ser.write(ISOLATE_ENABLE)
        sidecar["pre_commands"].append({
            "command": "!I1",
            "send_t_session_s": round(time.monotonic() - session_start, 3),
        })
        time.sleep(PRE_AFTER_I1_S)

    # Track current damp_mix to avoid redundant !D writes if the
    # caller groups multiple pitches under the same damp_mix.
    current_damp_mix = None
    for cell in cells:
        if cell["damp_mix"] != current_damp_mix:
            ser.write(cell["damp_mix_command_bytes"])
            sidecar["pre_commands"].append({
                "command": "!D{:04X}".format(cell["damp_mix"]),
                "send_t_session_s": round(
                    time.monotonic() - session_start, 3),
            })
            current_damp_mix = cell["damp_mix"]
            time.sleep(damp_settle_s)

        # Per-cell !F (silence + voice0 reset under isolation).
        ser.write(cmd_release_bytes())
        time.sleep(settle_s)

        # Strike.
        send_t = time.monotonic() - session_start
        ser.write(cell["command_bytes"])
        send_times = [round(send_t, 3)]

        print(
            "[{:02d}] t={:7.3f}s damp_mix={} {} {}".format(
                cell["index"], send_t, cell["damp_mix_hex"],
                cell["pitch_name"], cell["command_ascii"]),
            file=sys.stderr,
        )

        # Capture window.
        time.sleep(capture_s)

        # Pause.
        time.sleep(pause_s)

        sidecar["cells"].append({
            "index": cell["index"],
            "damp_mix": cell["damp_mix"],
            "damp_mix_hex": cell["damp_mix_hex"],
            "loop_len": cell["loop_len"],
            "velocity": cell["velocity"],
            "pitch_name": cell["pitch_name"],
            "command": cell["command_ascii"],
            "send_t_session_s": send_times,
        })

    # Trailing !F to silence the last ring.
    ser.write(cmd_release_bytes())
    sidecar["post_commands"].append({
        "command": "!F",
        "send_t_session_s": round(time.monotonic() - session_start, 3),
    })

    if single_voice_isolate:
        time.sleep(POST_BEFORE_I0_S)
        ser.write(ISOLATE_DISABLE)
        sidecar["post_commands"].append({
            "command": "!I0",
            "send_t_session_s": round(time.monotonic() - session_start, 3),
        })

    ser.close()

    with open(sidecar_path, "w", encoding="ascii") as fp:
        json.dump(sidecar, fp, indent=2, sort_keys=True)
        fp.write("\n")

    print("Sidecar written: {}".format(sidecar_path), file=sys.stderr)
    return 0


# ---- Plan mode ---------------------------------------------------------


def cmd_plan(damp_mix_values: List[int],
             pitches: List[Dict],
             velocity: int,
             single_voice_isolate: bool) -> int:
    """Print the full byte sequence with visible \\r\\n framing."""
    cells = build_grid(damp_mix_values, pitches, velocity)
    duration = session_duration_s(damp_mix_values, pitches,
                                  single_voice_isolate)
    counts = expected_command_counts(damp_mix_values, pitches,
                                     single_voice_isolate)
    print(
        "Phase 6 M6.5 damp_mix sweep: {:d} damp_mix x {:d} pitch = {:d} cells"
        ", total ~{:.1f} s{}".format(
            len(damp_mix_values), len(pitches), len(cells), duration,
            " (isolation_mode=ON)" if single_voice_isolate else ""))
    print(
        "  pacing: damp_settle {:.2f}s, per-cell settle {:.1f}s, "
        "capture {:.1f}s, pause {:.1f}s".format(
            DAMP_SETTLE_S, SETTLE_S, CAPTURE_S, PAUSE_S))
    print(
        "  expected device command counts: !I1={} !D={} !F={} !N={} !I0={} "
        "(total {} valid; X expected 0)".format(
            counts["I1"], counts["D"], counts["F"], counts["N"],
            counts["I0"], counts["total"]))
    print()
    print("  Higher damp_mix = longer sustain; lower damp_mix = shorter "
          "sustain.")
    print()

    if single_voice_isolate:
        print("pre:  !I1\\r\\n  (enable single-voice isolation mode)")

    print()
    print("idx  damp_mix  pitch    loop_len  velocity  byte_sequence")
    print("---  --------  -------  --------  --------  -------------------")

    current_damp_mix = None
    for c in cells:
        if c["damp_mix"] != current_damp_mix:
            current_damp_mix = c["damp_mix"]
            print(
                "        {:s}                                {:s}".format(
                    c["damp_mix_hex"],
                    c["damp_mix_command_bytes"].decode("ascii")
                    .replace("\r", "\\r").replace("\n", "\\n")))
        print(
            "{:3d}  {:8s}  {:7s}  {:>8d}  {:#06x}    {:s}".format(
                c["index"], c["damp_mix_hex"], c["pitch_name"],
                c["loop_len"], c["velocity"],
                "!F\\r\\n then " +
                c["command_bytes"].decode("ascii")
                .replace("\r", "\\r").replace("\n", "\\n")))

    if single_voice_isolate:
        print()
        print("post: !F\\r\\n  (final release)")
        print("post: !I0\\r\\n  (disable isolation mode)")
    return 0


# ---- Self-check --------------------------------------------------------


def cmd_self_check() -> int:
    """Run fixed-vector validation, exit 0 on PASS."""
    fails = 0

    # 1. Default grid shape: 7 damp_mix x 2 pitches = 14 cells.
    cells = build_grid(DEFAULT_DAMP_MIX_GRID, DEFAULT_PITCH_GRID,
                       DEFAULT_VELOCITY)
    expected_n = len(DEFAULT_DAMP_MIX_GRID) * len(DEFAULT_PITCH_GRID)
    if len(cells) != expected_n:
        print("FAIL grid_size got={} want={}".format(len(cells), expected_n))
        fails += 1
    elif expected_n != 14:
        print("FAIL grid_size expected 14 got={}".format(expected_n))
        fails += 1
    else:
        print("PASS grid_size {} cells (7 damp_mix x 2 pitch)".format(
            len(cells)))

    # 2. Cell 0: damp_mix=0x0000, A4 loop_len=106, velocity=0x7FFF
    c0 = cells[0]
    if c0["damp_mix"] != 0x0000 or c0["loop_len"] != 106 or \
       c0["velocity"] != 0x7FFF:
        print("FAIL c0 fields {}".format(c0))
        fails += 1
    elif c0["command_ascii"] != "!N006A7FFF":
        print("FAIL c0 command {}".format(c0["command_ascii"]))
        fails += 1
    elif c0["command_bytes"] != b"!N006A7FFF\r\n":
        print("FAIL c0 bytes {!r}".format(c0["command_bytes"]))
        fails += 1
    elif c0["damp_mix_command_bytes"] != b"!D0000\r\n":
        print("FAIL c0 damp_mix bytes {!r}".format(
            c0["damp_mix_command_bytes"]))
        fails += 1
    else:
        print("PASS c0 !D0000\\r\\n then !F\\r\\n then !N006A7FFF\\r\\n")

    # 3. Cell 1: same damp_mix=0x0000, C5 loop_len=89
    c1 = cells[1]
    if c1["damp_mix"] != 0x0000 or c1["loop_len"] != 89:
        print("FAIL c1 fields {}".format(c1))
        fails += 1
    elif c1["command_ascii"] != "!N00597FFF":
        print("FAIL c1 command {}".format(c1["command_ascii"]))
        fails += 1
    else:
        print("PASS c1 !N00597FFF (C5 loop_len 89, same damp_mix row)")

    # 4. Cell 2 starts a new damp_mix row (0x0800).
    c2 = cells[2]
    if c2["damp_mix"] != 0x0800:
        print("FAIL c2 damp_mix {}".format(c2["damp_mix"]))
        fails += 1
    elif c2["damp_mix_command_bytes"] != b"!D0800\r\n":
        print("FAIL c2 damp_mix bytes {!r}".format(
            c2["damp_mix_command_bytes"]))
        fails += 1
    else:
        print("PASS c2 next damp_mix row !D0800\\r\\n")

    # 5. Last cell: damp_mix=0x7FFF, C5
    last = cells[-1]
    if last["damp_mix"] != 0x7FFF or last["loop_len"] != 89:
        print("FAIL last_cell fields {}".format(last))
        fails += 1
    elif last["damp_mix_command_bytes"] != b"!D7FFF\r\n":
        print("FAIL last_cell damp_mix bytes {!r}".format(
            last["damp_mix_command_bytes"]))
        fails += 1
    elif last["command_ascii"] != "!N00597FFF":
        print("FAIL last_cell command {}".format(last["command_ascii"]))
        fails += 1
    else:
        print("PASS last_cell damp_mix=0x7FFF C5 !D7FFF+!N00597FFF")

    # 6. !D byte-format checks (4 hex digits, uppercase, CRLF framing).
    for v, want in [
            (0x0000, b"!D0000\r\n"),
            (0x0001, b"!D0001\r\n"),
            (0x3000, b"!D3000\r\n"),
            (0x5BCD, b"!D5BCD\r\n"),
            (0x7FFF, b"!D7FFF\r\n")]:
        got = build_damp_mix_command(v)
        if got != want:
            print("FAIL !D format v={:#06x} got={!r} want={!r}".format(
                v, got, want))
            fails += 1
        else:
            print("PASS !D v={:#06x} -> {!r}".format(v, got))

    # 7. !D out-of-range rejected (only 0x0000..0x7FFF valid).
    for bad in [-1, 0x8000, 0xFFFF]:
        try:
            build_damp_mix_command(bad)
            print("FAIL !D accepted out-of-range {}".format(bad))
            fails += 1
        except ValueError:
            pass
    print("PASS !D out-of-range rejection (0x0000..0x7FFF only)")

    # 8. !N range/format checks.
    if build_note_command(106, 0x7FFF) != b"!N006A7FFF\r\n":
        print("FAIL !N format")
        fails += 1
    else:
        print("PASS !N format !N006A7FFF\\r\\n")
    for bad_ll in [31, 128]:
        try:
            build_note_command(bad_ll, 0x7FFF)
            print("FAIL !N accepted bad loop_len {}".format(bad_ll))
            fails += 1
        except ValueError:
            pass
    for bad_vel in [-1, 0x8000]:
        try:
            build_note_command(106, bad_vel)
            print("FAIL !N accepted bad velocity {}".format(bad_vel))
            fails += 1
        except ValueError:
            pass
    print("PASS !N range rejection")

    # 9. Release bytes (CRLF framing).
    if cmd_release_bytes() != b"!F\r\n":
        print("FAIL release_bytes {!r}".format(cmd_release_bytes()))
        fails += 1
    else:
        print("PASS release_bytes !F\\r\\n")

    # 10. Isolation bytes (CRLF framing).
    if ISOLATE_ENABLE != b"!I1\r\n":
        print("FAIL isolate_enable {!r}".format(ISOLATE_ENABLE))
        fails += 1
    else:
        print("PASS isolate_enable !I1\\r\\n")
    if ISOLATE_DISABLE != b"!I0\r\n":
        print("FAIL isolate_disable {!r}".format(ISOLATE_DISABLE))
        fails += 1
    else:
        print("PASS isolate_disable !I0\\r\\n")

    # 11. Pacing constants are sane.
    if SETTLE_S <= 0.0 or CAPTURE_S <= 0.0 or PAUSE_S <= 0.0 or \
       DAMP_SETTLE_S <= 0.0:
        print("FAIL pacing constants")
        fails += 1
    elif CAPTURE_S < 2.0:
        print("FAIL capture window too short {:.2f}s".format(CAPTURE_S))
        fails += 1
    else:
        print(
            "PASS pacing damp_settle={:.2f}s settle={:.1f}s "
            "capture={:.1f}s pause={:.1f}s".format(
                DAMP_SETTLE_S, SETTLE_S, CAPTURE_S, PAUSE_S))

    # 12. Expected command counts: with 7 damp_mix x 2 pitches and
    # isolation enabled, the total valid command count is:
    #   !I1 = 1
    #   !D  = 7
    #   !F  = 7*2 + 1 (trailing) = 15
    #   !N  = 7*2 = 14
    #   !I0 = 1
    #   total = 38
    counts = expected_command_counts(
        DEFAULT_DAMP_MIX_GRID, DEFAULT_PITCH_GRID, single_voice_isolate=True)
    expected_counts = {
        "I1": 1, "D": 7, "F": 15, "N": 14, "I0": 1, "total": 38}
    if counts != expected_counts:
        print("FAIL command_counts default got={} want={}".format(
            counts, expected_counts))
        fails += 1
    else:
        print(
            "PASS command_counts default: !I1=1 !D=7 !F=15 !N=14 !I0=1 "
            "(total 38 valid; X expected 0)")

    # 13. Expected command counts without isolation:
    #   no !I1 / !I0; same !D/!F/!N counts but no enable/disable.
    counts2 = expected_command_counts(
        DEFAULT_DAMP_MIX_GRID, DEFAULT_PITCH_GRID, single_voice_isolate=False)
    expected_counts2 = {
        "I1": 0, "D": 7, "F": 15, "N": 14, "I0": 0, "total": 36}
    if counts2 != expected_counts2:
        print("FAIL command_counts no_isolate got={} want={}".format(
            counts2, expected_counts2))
        fails += 1
    else:
        print(
            "PASS command_counts no-isolate: !D=7 !F=15 !N=14 (total 36)")

    # 14. Session duration math: damp_settle 0.1s + 2*(1+4+1)=12s
    # per damp_mix row, x 7 rows = 84.7s plus 0.1+0.05 if isolation.
    duration = session_duration_s(
        DEFAULT_DAMP_MIX_GRID, DEFAULT_PITCH_GRID, single_voice_isolate=True)
    expected_duration = 7 * (DAMP_SETTLE_S +
                             len(DEFAULT_PITCH_GRID) *
                             (SETTLE_S + CAPTURE_S + PAUSE_S))
    expected_duration += PRE_AFTER_I1_S + POST_BEFORE_I0_S
    if abs(duration - expected_duration) > 1e-6:
        print("FAIL session_duration got={:.3f} want={:.3f}".format(
            duration, expected_duration))
        fails += 1
    else:
        print("PASS session_duration {:.2f}s (default + isolation)".format(
            duration))

    # 15. Sidecar JSON round-trip.
    fake = {
        "schema": "phase6_m6_5_damp_sweep.v1",
        "port": "COM_TEST",
        "baud": 115200,
        "settle_s": SETTLE_S,
        "capture_s": CAPTURE_S,
        "pause_s": PAUSE_S,
        "damp_settle_s": DAMP_SETTLE_S,
        "single_voice_isolate": True,
        "session_start_unix": 1700000000.0,
        "damp_mix_grid": ["0x{:04X}".format(v) for v in DEFAULT_DAMP_MIX_GRID],
        "pitch_grid": [
            {"loop_len": p["loop_len"], "pitch_name": p["pitch_name"]}
            for p in DEFAULT_PITCH_GRID],
        "velocity_hex": "0x7FFF",
        "pre_commands": [
            {"command": "!I1", "send_t_session_s": 0.005},
            {"command": "!D0000", "send_t_session_s": 0.110},
        ],
        "cells": [
            {
                "index": 0,
                "damp_mix": 0x0000,
                "damp_mix_hex": "0x0000",
                "loop_len": 106,
                "velocity": 0x7FFF,
                "pitch_name": "A4",
                "command": "!N006A7FFF",
                "send_t_session_s": [3.234],
            },
        ],
        "post_commands": [
            {"command": "!F",  "send_t_session_s": 87.10},
            {"command": "!I0", "send_t_session_s": 87.15},
        ],
    }
    s = json.dumps(fake, sort_keys=True)
    fake2 = json.loads(s)
    if fake2 != fake:
        print("FAIL sidecar round-trip not idempotent")
        fails += 1
    elif fake2["cells"][0]["command"] != "!N006A7FFF":
        print("FAIL sidecar cell command")
        fails += 1
    elif fake2["cells"][0]["damp_mix_hex"] != "0x0000":
        print("FAIL sidecar damp_mix_hex")
        fails += 1
    elif fake2["pre_commands"][1]["command"] != "!D0000":
        print("FAIL sidecar pre_command !D0000")
        fails += 1
    elif fake2["post_commands"][1]["command"] != "!I0":
        print("FAIL sidecar post_command")
        fails += 1
    elif fake2["schema"] != "phase6_m6_5_damp_sweep.v1":
        print("FAIL sidecar schema")
        fails += 1
    elif not isinstance(fake2["cells"][0]["send_t_session_s"], list):
        print("FAIL sidecar send_t_session_s should be list")
        fails += 1
    else:
        print("PASS sidecar v1 JSON round-trip")

    # 16. parse_hex_list helper (respects 0x0000..0x7FFF range).
    parsed = parse_hex_list("0x0000, 0x2000, 0x7FFF")
    if parsed != [0x0000, 0x2000, 0x7FFF]:
        print("FAIL parse_hex_list got={}".format(parsed))
        fails += 1
    else:
        print("PASS parse_hex_list")

    # 16b. parse_hex_list rejects values above 0x7FFF.
    for bad in ["0x8000", "0xFFFF"]:
        try:
            parse_hex_list(bad)
            print("FAIL parse_hex_list accepted {}".format(bad))
            fails += 1
        except ValueError:
            pass
    print("PASS parse_hex_list range rejection (0x0000..0x7FFF)")

    # 17. parse_pitch_list helper accepts both "name:loop_len" and
    # bare "loop_len" tokens.
    parsed_p = parse_pitch_list("A4:106,C5:89,127")
    if (len(parsed_p) != 3 or parsed_p[0]["loop_len"] != 106 or
            parsed_p[0]["pitch_name"] != "A4" or
            parsed_p[2]["loop_len"] != 127 or
            parsed_p[2]["pitch_name"] != "loop127"):
        print("FAIL parse_pitch_list got={}".format(parsed_p))
        fails += 1
    else:
        print("PASS parse_pitch_list (named and bare tokens)")

    # 18. parse_pitch_list rejects out-of-range loop_len.
    for bad in ["A4:31", "A4:128"]:
        try:
            parse_pitch_list(bad)
            print("FAIL parse_pitch_list accepted {}".format(bad))
            fails += 1
        except ValueError:
            pass
    print("PASS parse_pitch_list range rejection")

    # 19. CRLF framing: every command must end with \r\n exactly.
    for cmd_bytes in [ISOLATE_ENABLE, ISOLATE_DISABLE, cmd_release_bytes(),
                      build_damp_mix_command(0x4000),
                      build_note_command(106, 0x7FFF)]:
        if not cmd_bytes.endswith(b"\r\n"):
            print("FAIL CRLF framing: {!r} missing \\r\\n".format(cmd_bytes))
            fails += 1
            break
        if b"\r\n" != cmd_bytes[-2:]:
            print("FAIL CRLF framing: trailing bytes wrong")
            fails += 1
            break
        # Ensure no embedded \r\n before the final one.
        inner = cmd_bytes[:-2]
        if b"\r" in inner or b"\n" in inner:
            print("FAIL CRLF framing: embedded CR/LF in {!r}".format(
                cmd_bytes))
            fails += 1
            break
    else:
        print("PASS CRLF framing on all command types")

    # 20. Command format: !D must use exactly 4 uppercase hex digits.
    for v in [0x0000, 0x0ABC, 0x7FFF]:
        cmd = build_damp_mix_command(v)
        # Strip CRLF, check prefix and length.
        body = cmd[:-2].decode("ascii")
        if not body.startswith("!D"):
            print("FAIL !D prefix missing in {!r}".format(body))
            fails += 1
            break
        hex_part = body[2:]
        if len(hex_part) != 4:
            print("FAIL !D hex not 4 digits: {!r}".format(hex_part))
            fails += 1
            break
        if hex_part != hex_part.upper():
            print("FAIL !D hex not uppercase: {!r}".format(hex_part))
            fails += 1
            break
    else:
        print("PASS !D command format (4 uppercase hex digits)")

    if fails == 0:
        print("PHASE6_M6_5_DAMP_SWEEP_PASS cells={:d}".format(len(cells)))
        return 0
    print("PHASE6_M6_5_DAMP_SWEEP_FAIL fails={:d}".format(fails))
    return 1


# ---- Main --------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(
        description="Phase 6 M6.5 damp_mix sweep host harness. "
                    "Higher damp_mix = longer sustain, "
                    "lower damp_mix = shorter sustain.")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--self-check", action="store_true",
                   help="Run fixed-vector validation, exit 0 on PASS.")
    g.add_argument("--plan", action="store_true",
                   help="Print the grid and per-cell command bytes "
                        "with visible CRLF framing.")
    g.add_argument("--run", action="store_true",
                   help="Drive hardware via serial port.")

    p.add_argument("--port", default=DEFAULT_PORT)
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--sidecar", default=DEFAULT_SIDECAR)
    p.add_argument("--settle-s", type=float, default=SETTLE_S)
    p.add_argument("--capture-s", type=float, default=CAPTURE_S)
    p.add_argument("--pause-s", type=float, default=PAUSE_S)
    p.add_argument("--damp-settle-s", type=float,
                   default=DAMP_SETTLE_S)
    p.add_argument("--damp-mix-grid", default=None,
                   help="Comma-separated hex values (0x0000..0x7FFF), e.g. "
                        "0x0000,0x2000,0x4000,0x7FFF. Default is "
                        "0x0000,0x0800,0x1000,0x2000,0x4000,0x6000,0x7FFF.")
    p.add_argument("--pitch-grid", default=None,
                   help="Comma-separated pitch tokens. Each token is "
                        "either NAME:LOOPLEN (e.g. A4:106) or a bare "
                        "loop_len. Default is A4:106,C5:89.")
    p.add_argument("--velocity", type=lambda v: int(v, 0),
                   default=DEFAULT_VELOCITY,
                   help="Velocity as decimal or hex (default 0x7FFF).")
    p.add_argument("--no-isolate", action="store_true",
                   help="Skip !I1/!I0 framing. The default sweep "
                        "enables isolation mode so voice0 is the "
                        "only audible voice.")

    args = p.parse_args()

    try:
        damp_mix_values = (parse_hex_list(args.damp_mix_grid)
                           if args.damp_mix_grid else
                           list(DEFAULT_DAMP_MIX_GRID))
        pitches = (parse_pitch_list(args.pitch_grid)
                   if args.pitch_grid else list(DEFAULT_PITCH_GRID))
    except ValueError as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 2

    single_voice_isolate = not args.no_isolate

    if args.self_check:
        return cmd_self_check()
    if args.plan:
        return cmd_plan(damp_mix_values, pitches, args.velocity,
                        single_voice_isolate)
    if args.run:
        return run_bench(args.port, args.baud, args.sidecar,
                         damp_mix_values, pitches, args.velocity,
                         args.settle_s, args.capture_s, args.pause_s,
                         args.damp_settle_s,
                         single_voice_isolate)
    return 1


if __name__ == "__main__":
    sys.exit(main())
