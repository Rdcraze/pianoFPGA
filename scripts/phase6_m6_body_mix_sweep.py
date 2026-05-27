#!/usr/bin/env python3
"""Phase 6 M6 body_mix sweep host harness.

Drives the live M5 RTL UART command path through a hardware serial
port to sweep the runtime body_mix knob across a configurable grid
and capture an isolated single-voice strike at each (body_mix, pitch)
cell. The harness only emits commands the M2/M5 parser already
accepts:

    !I1\\r\\n             enable single-voice isolation mode
    !I0\\r\\n             disable single-voice isolation mode
    !B<vvvv>\\r\\n        set runtime body_mix to a 4-hex-digit Q15 value
    !F\\r\\n              release/silence (in isolation mode also
                         hard-resets voice0)
    !NLLLLVVVV\\r\\n      parameterized note (loop_len 32..127,
                         velocity 0..0x7FFF)

Per-cell pacing within a body_mix row:

    1. Send !B<vvvv> once per body_mix value, wait 100 ms for
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
        "schema": "phase6_m6_body_mix_sweep.v1",
        "port": "COM5",
        "baud": 115200,
        "settle_s": 1.0,
        "capture_s": 4.0,
        "pause_s": 1.0,
        "body_mix_settle_s": 0.1,
        "session_start_unix": 1234567890.123,
        "single_voice_isolate": true,
        "pre_commands": [
            {"command": "!I1", "send_t_session_s": 0.005},
            ...
        ],
        "cells": [
            {"index": 0,
             "body_mix": 4096, "body_mix_hex": "0x1000",
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
                         reports/phase6_m6_body_mix_sweep_session.json).
    --analyze --wav PATH --sidecar PATH [--out CSV] [--out-md MD]
                         Optional convenience wrapper: invoke
                         scripts/phase6_m1_voice_analyze.py over the
                         resulting WAV. The analyzer accepts
                         body_mix-labelled cells transparently
                         because the v1 sweep sidecar carries the
                         same shape as the M4 v2 bench sidecar (a
                         per-cell send_t_session_s list).
"""

import argparse
import json
import os
import subprocess
import sys
import time
from typing import Dict, List

# -- Grid definition (matches Phase 6 M6 scope section 6) --
DEFAULT_BODY_MIX_GRID = [0x1000, 0x2000, 0x3000, 0x4000, 0x6000, 0x8000, 0xC000]

DEFAULT_PITCH_GRID = [
    {"loop_len": 106, "pitch_name": "A4"},
    {"loop_len": 89,  "pitch_name": "C5"},
]
DEFAULT_VELOCITY = 0x7FFF

# Per-cell pacing.
SETTLE_S = 1.0
CAPTURE_S = 4.0
PAUSE_S = 1.0

# Time after !B before the first per-cell !F.
BODY_MIX_SETTLE_S = 0.1

# Pre/post pacing (small).
PRE_AFTER_I1_S = 0.1
POST_BEFORE_I0_S = 0.05

DEFAULT_PORT = "COM5"
DEFAULT_BAUD = 115200
DEFAULT_SIDECAR = "reports/phase6_m6_body_mix_sweep_session.json"

# UART command bytes (constants, no new syntax).
ISOLATE_ENABLE = b"!I1\r\n"
ISOLATE_DISABLE = b"!I0\r\n"


# ---- Builders ----------------------------------------------------------


def parse_hex_list(spec: str) -> List[int]:
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        v = int(tok, 16) if tok.lower().startswith("0x") else int(tok, 0)
        if not (0 <= v <= 0xFFFF):
            raise ValueError(
                "body_mix value out of range 0..0xFFFF: {}".format(tok))
        out.append(v)
    if not out:
        raise ValueError("empty body_mix grid")
    return out


def parse_pitch_list(spec: str) -> List[Dict]:
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


def build_body_mix_command(body_mix: int) -> bytes:
    if not (0 <= body_mix <= 0xFFFF):
        raise ValueError("body_mix out of range")
    return ("!B{:04X}\r\n".format(body_mix)).encode("ascii")


def build_note_command(loop_len: int, velocity: int) -> bytes:
    if not (32 <= loop_len <= 127):
        raise ValueError("loop_len out of range 32..127")
    if not (0 <= velocity <= 0x7FFF):
        raise ValueError("velocity out of range 0..0x7FFF")
    return ("!N{:04X}{:04X}\r\n".format(loop_len, velocity)).encode("ascii")


def build_grid(body_mix_values: List[int],
               pitches: List[Dict],
               velocity: int) -> List[Dict]:
    cells = []
    idx = 0
    for bm in body_mix_values:
        for p in pitches:
            ll = p["loop_len"]
            cmd_ascii = "!N{:04X}{:04X}".format(ll, velocity)
            cells.append({
                "index": idx,
                "body_mix": bm,
                "body_mix_hex": "0x{:04X}".format(bm),
                "loop_len": ll,
                "velocity": velocity,
                "pitch_name": p["pitch_name"],
                "command_ascii": cmd_ascii,
                "command_bytes": (cmd_ascii + "\r\n").encode("ascii"),
                "body_mix_command_bytes": build_body_mix_command(bm),
            })
            idx += 1
    return cells


def cmd_release_bytes() -> bytes:
    return b"!F\r\n"


def session_duration_s(body_mix_values: List[int],
                       pitches: List[Dict],
                       single_voice_isolate: bool) -> float:
    n_bm = len(body_mix_values)
    n_pitch = len(pitches)
    per_cell = SETTLE_S + CAPTURE_S + PAUSE_S
    per_bm = BODY_MIX_SETTLE_S + n_pitch * per_cell
    total = n_bm * per_bm
    if single_voice_isolate:
        total += PRE_AFTER_I1_S + POST_BEFORE_I0_S
    return total


def expected_command_counts(body_mix_values: List[int],
                            pitches: List[Dict],
                            single_voice_isolate: bool) -> Dict[str, int]:
    """Return a per-command and total count breakdown.

    Every emitted command is a valid M2/M5 accepted command and is
    expected to increment the device's command counter Q by exactly
    one. The harness emits no malformed commands, so the device's
    error counter X should remain 0 for the whole session.
    """
    n_bm = len(body_mix_values)
    n_pitch = len(pitches)
    n_b = n_bm                        # one !B per body_mix value
    n_f = n_bm * n_pitch + 1          # per-cell !F + one trailing !F
    n_n = n_bm * n_pitch              # one !N per cell
    n_i1 = 1 if single_voice_isolate else 0
    n_i0 = 1 if single_voice_isolate else 0
    total = n_b + n_f + n_n + n_i1 + n_i0
    return {
        "I1": n_i1,
        "B":  n_b,
        "F":  n_f,
        "N":  n_n,
        "I0": n_i0,
        "total": total,
    }


# ---- Bench run ----------------------------------------------------------


def run_bench(port: str, baud: int, sidecar_path: str,
              body_mix_values: List[int],
              pitches: List[Dict],
              velocity: int,
              settle_s: float, capture_s: float, pause_s: float,
              body_mix_settle_s: float,
              single_voice_isolate: bool) -> int:
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

    cells = build_grid(body_mix_values, pitches, velocity)
    session_start = time.monotonic()
    session_unix = time.time()

    sidecar = {
        "schema": "phase6_m6_body_mix_sweep.v1",
        "port": port,
        "baud": baud,
        "settle_s": settle_s,
        "capture_s": capture_s,
        "pause_s": pause_s,
        "body_mix_settle_s": body_mix_settle_s,
        "single_voice_isolate": single_voice_isolate,
        "session_start_unix": session_unix,
        "body_mix_grid": ["0x{:04X}".format(v) for v in body_mix_values],
        "pitch_grid": [
            {"loop_len": p["loop_len"], "pitch_name": p["pitch_name"]}
            for p in pitches
        ],
        "velocity_hex": "0x{:04X}".format(velocity),
        "pre_commands": [],
        "cells": [],
        "post_commands": [],
    }

    counts = expected_command_counts(body_mix_values, pitches,
                                     single_voice_isolate)
    duration = session_duration_s(body_mix_values, pitches,
                                  single_voice_isolate)
    print(
        "Phase 6 M6 body_mix sweep: {} body_mix x {} pitch = {} cells, "
        "total {:.1f} s + setup".format(
            len(body_mix_values), len(pitches), len(cells), duration),
        file=sys.stderr,
    )
    print(
        "Expected device command counts: !I1={} !B={} !F={} !N={} !I0={} "
        "(total {} valid commands; X expected 0)".format(
            counts["I1"], counts["B"], counts["F"], counts["N"],
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

    # Track current body_mix to avoid redundant !B writes if the
    # caller groups multiple pitches under the same body_mix.
    current_body_mix = None
    for cell in cells:
        if cell["body_mix"] != current_body_mix:
            ser.write(cell["body_mix_command_bytes"])
            sidecar["pre_commands"].append({
                "command": "!B{:04X}".format(cell["body_mix"]),
                "send_t_session_s": round(
                    time.monotonic() - session_start, 3),
            })
            current_body_mix = cell["body_mix"]
            time.sleep(body_mix_settle_s)

        # Per-cell !F (silence + voice0 reset under isolation).
        ser.write(cmd_release_bytes())
        time.sleep(settle_s)

        # Strike.
        send_t = time.monotonic() - session_start
        ser.write(cell["command_bytes"])
        send_times = [round(send_t, 3)]

        print(
            "[{:02d}] t={:7.3f}s body_mix={} {} {}".format(
                cell["index"], send_t, cell["body_mix_hex"],
                cell["pitch_name"], cell["command_ascii"]),
            file=sys.stderr,
        )

        # Capture window.
        time.sleep(capture_s)

        # Pause.
        time.sleep(pause_s)

        sidecar["cells"].append({
            "index": cell["index"],
            "body_mix": cell["body_mix"],
            "body_mix_hex": cell["body_mix_hex"],
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


def cmd_plan(body_mix_values: List[int],
             pitches: List[Dict],
             velocity: int,
             single_voice_isolate: bool) -> int:
    cells = build_grid(body_mix_values, pitches, velocity)
    duration = session_duration_s(body_mix_values, pitches,
                                  single_voice_isolate)
    counts = expected_command_counts(body_mix_values, pitches,
                                     single_voice_isolate)
    print(
        "Phase 6 M6 body_mix sweep: {:d} body_mix x {:d} pitch = {:d} cells, "
        "total ~{:.1f} s{}".format(
            len(body_mix_values), len(pitches), len(cells), duration,
            " (isolation_mode=ON)" if single_voice_isolate else ""))
    print(
        "  pacing: body_mix_settle {:.2f}s, per-cell settle {:.1f}s, "
        "capture {:.1f}s, pause {:.1f}s".format(
            BODY_MIX_SETTLE_S, SETTLE_S, CAPTURE_S, PAUSE_S))
    print(
        "  expected device command counts: !I1={} !B={} !F={} !N={} !I0={} "
        "(total {} valid; X expected 0)".format(
            counts["I1"], counts["B"], counts["F"], counts["N"],
            counts["I0"], counts["total"]))
    print()

    if single_voice_isolate:
        print("pre:  !I1\\r\\n  (enable single-voice isolation mode)")

    print()
    print("idx  body_mix  pitch    loop_len  velocity  byte_sequence")
    print("---  --------  -------  --------  --------  -------------------")

    current_body_mix = None
    for c in cells:
        if c["body_mix"] != current_body_mix:
            current_body_mix = c["body_mix"]
            print(
                "        {:s}                                {:s}".format(
                    c["body_mix_hex"],
                    c["body_mix_command_bytes"].decode("ascii")
                    .replace("\r", "\\r").replace("\n", "\\n")))
        print(
            "{:3d}  {:8s}  {:7s}  {:>8d}  {:#06x}    {:s}".format(
                c["index"], c["body_mix_hex"], c["pitch_name"],
                c["loop_len"], c["velocity"],
                "!F\\r\\n then " +
                c["command_bytes"].decode("ascii")
                .replace("\r", "\\r").replace("\n", "\\n")))

    if single_voice_isolate:
        print()
        print("post: !F\\r\\n  (final release)")
        print("post: !I0\\r\\n  (disable isolation mode)")
    return 0


# ---- Analyze (delegate) ------------------------------------------------


def cmd_analyze(wav_path: str, sidecar_path: str,
                out_csv: str, out_md: str,
                audio_start_unix: float,
                coherent_average: bool) -> int:
    """Convenience wrapper that invokes scripts/phase6_m1_voice_analyze.py
    over the resulting WAV. The M6 sweep sidecar v1 carries the same
    per-cell shape as the M4-era M1 bench sidecar v2 (a list of
    send_t_session_s timestamps), which the analyzer accepts.

    The analyzer's CSV does not natively include a body_mix column.
    We post-process the analyzer output here to splice body_mix_hex
    in as the second column so the resulting CSV matches the row
    format spelled out in section 6 of
    reports/phase6_m6_next_voice_quality_scope.md.
    """
    if not os.path.isfile(wav_path):
        print("ERROR: --wav not found: {}".format(wav_path), file=sys.stderr)
        return 2
    if not os.path.isfile(sidecar_path):
        print("ERROR: --sidecar not found: {}".format(sidecar_path),
              file=sys.stderr)
        return 2

    # Load sidecar to read body_mix labels and to reshape it into the
    # v2 schema the analyzer expects (the analyzer accepts schema
    # values "phase6_m1_voice_bench.v1" or "phase6_m1_voice_bench.v2";
    # our v1 sweep sidecar has a compatible per-cell shape but a
    # different schema string, so we stage a temporary copy).
    with open(sidecar_path, "r", encoding="ascii") as fp:
        sidecar = json.load(fp)
    if sidecar.get("schema") != "phase6_m6_body_mix_sweep.v1":
        print(
            "ERROR: --sidecar schema is not phase6_m6_body_mix_sweep.v1: "
            "{}".format(sidecar.get("schema")),
            file=sys.stderr)
        return 2
    staged = dict(sidecar)
    staged["schema"] = "phase6_m1_voice_bench.v2"
    staged["repeats"] = 1
    staged_path = sidecar_path + ".staged.json"
    with open(staged_path, "w", encoding="ascii") as fp:
        json.dump(staged, fp, indent=2, sort_keys=True)
        fp.write("\n")

    here = os.path.dirname(os.path.abspath(__file__))
    analyzer = os.path.join(here, "phase6_m1_voice_analyze.py")
    if not os.path.isfile(analyzer):
        print("ERROR: analyzer not found at {}".format(analyzer),
              file=sys.stderr)
        return 2

    cmd = [sys.executable, analyzer,
           "--wav", wav_path,
           "--sidecar", staged_path,
           "--out", out_csv]
    if out_md:
        cmd += ["--out-md", out_md]
    if audio_start_unix is not None:
        cmd += ["--audio-start-unix", "{:.6f}".format(audio_start_unix)]
    if coherent_average:
        cmd += ["--coherent-average"]
    print("Invoking analyzer: {}".format(" ".join(cmd)), file=sys.stderr)
    rc = subprocess.call(cmd)
    if rc != 0:
        print("ERROR: analyzer exited with code {}".format(rc),
              file=sys.stderr)
        return rc

    # Splice body_mix_hex into the analyzer CSV so the row format
    # matches the M6 scope.
    try:
        rewrite_csv_with_body_mix(out_csv, sidecar)
    except Exception as exc:
        print("ERROR: failed to splice body_mix into CSV: {}".format(exc),
              file=sys.stderr)
        return 2

    try:
        os.remove(staged_path)
    except OSError:
        pass
    return 0


def rewrite_csv_with_body_mix(csv_path: str, sidecar: Dict) -> None:
    import csv
    body_mix_by_index = {c["index"]: c["body_mix_hex"]
                         for c in sidecar["cells"]}
    with open(csv_path, "r", encoding="ascii", newline="") as fp:
        rdr = csv.DictReader(fp)
        rows = list(rdr)
        fieldnames = list(rdr.fieldnames or [])
    if "body_mix_hex" not in fieldnames:
        # Insert body_mix_hex right after index, before pitch_name.
        new_fields = []
        for f in fieldnames:
            if f == "pitch_name":
                new_fields.append("body_mix_hex")
            new_fields.append(f)
        fieldnames = new_fields
    for r in rows:
        idx = int(r["index"])
        r["body_mix_hex"] = body_mix_by_index.get(idx, "")
    with open(csv_path, "w", encoding="ascii", newline="") as fp:
        w = csv.DictWriter(fp, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)


# ---- Self-check --------------------------------------------------------


def cmd_self_check() -> int:
    fails = 0

    # 1. Default grid shape.
    cells = build_grid(DEFAULT_BODY_MIX_GRID, DEFAULT_PITCH_GRID,
                       DEFAULT_VELOCITY)
    expected_n = len(DEFAULT_BODY_MIX_GRID) * len(DEFAULT_PITCH_GRID)
    if len(cells) != expected_n:
        print("FAIL grid_size got={} want={}".format(len(cells), expected_n))
        fails += 1
    else:
        print("PASS grid_size {} cells (7 body_mix x 2 pitch)".format(
            len(cells)))

    # 2. Cell 0: body_mix=0x1000, A4 loop_len=106, velocity=0x7FFF
    c0 = cells[0]
    if c0["body_mix"] != 0x1000 or c0["loop_len"] != 106 or \
       c0["velocity"] != 0x7FFF:
        print("FAIL c0 fields {}".format(c0))
        fails += 1
    elif c0["command_ascii"] != "!N006A7FFF":
        print("FAIL c0 command {}".format(c0["command_ascii"]))
        fails += 1
    elif c0["command_bytes"] != b"!N006A7FFF\r\n":
        print("FAIL c0 bytes {!r}".format(c0["command_bytes"]))
        fails += 1
    elif c0["body_mix_command_bytes"] != b"!B1000\r\n":
        print("FAIL c0 body_mix bytes {!r}".format(c0["body_mix_command_bytes"]))
        fails += 1
    else:
        print("PASS c0 !B1000\\r\\n then !F\\r\\n then !N006A7FFF\\r\\n")

    # 3. Cell 1: same body_mix=0x1000, C5 loop_len=89
    c1 = cells[1]
    if c1["body_mix"] != 0x1000 or c1["loop_len"] != 89:
        print("FAIL c1 fields {}".format(c1))
        fails += 1
    elif c1["command_ascii"] != "!N00597FFF":
        print("FAIL c1 command {}".format(c1["command_ascii"]))
        fails += 1
    else:
        print("PASS c1 !N00597FFF (C5 loop_len 89, same body_mix row)")

    # 4. Cell 2 starts a new body_mix row (0x2000).
    c2 = cells[2]
    if c2["body_mix"] != 0x2000:
        print("FAIL c2 body_mix {}".format(c2["body_mix"]))
        fails += 1
    elif c2["body_mix_command_bytes"] != b"!B2000\r\n":
        print("FAIL c2 body_mix bytes {!r}".format(c2["body_mix_command_bytes"]))
        fails += 1
    else:
        print("PASS c2 next body_mix row !B2000\\r\\n")

    # 5. Last cell: body_mix=0xC000, C5
    last = cells[-1]
    if last["body_mix"] != 0xC000 or last["loop_len"] != 89:
        print("FAIL last_cell fields {}".format(last))
        fails += 1
    elif last["body_mix_command_bytes"] != b"!BC000\r\n":
        print("FAIL last_cell body_mix bytes {!r}".format(
            last["body_mix_command_bytes"]))
        fails += 1
    elif last["command_ascii"] != "!N00597FFF":
        print("FAIL last_cell command {}".format(last["command_ascii"]))
        fails += 1
    else:
        print("PASS last_cell body_mix=0xC000 C5 !BC000+!N00597FFF")

    # 6. !B byte-format checks (4 hex digits, uppercase).
    for v, want in [
            (0x0000, b"!B0000\r\n"),
            (0x0001, b"!B0001\r\n"),
            (0x3000, b"!B3000\r\n"),
            (0xABCD, b"!BABCD\r\n"),
            (0xFFFF, b"!BFFFF\r\n")]:
        got = build_body_mix_command(v)
        if got != want:
            print("FAIL !B format v={:#06x} got={!r} want={!r}".format(
                v, got, want))
            fails += 1
        else:
            print("PASS !B v={:#06x} -> {!r}".format(v, got))

    # 7. !B out-of-range rejected.
    for bad in [-1, 0x10000]:
        try:
            build_body_mix_command(bad)
            print("FAIL !B accepted out-of-range {}".format(bad))
            fails += 1
        except ValueError:
            pass
    print("PASS !B out-of-range rejection")

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

    # 9. Release bytes.
    if cmd_release_bytes() != b"!F\r\n":
        print("FAIL release_bytes {!r}".format(cmd_release_bytes()))
        fails += 1
    else:
        print("PASS release_bytes !F\\r\\n")

    # 10. Isolation bytes.
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
       BODY_MIX_SETTLE_S <= 0.0:
        print("FAIL pacing constants")
        fails += 1
    elif CAPTURE_S < 2.0:
        print("FAIL capture window too short {:.2f}s".format(CAPTURE_S))
        fails += 1
    else:
        print(
            "PASS pacing body_mix_settle={:.2f}s settle={:.1f}s "
            "capture={:.1f}s pause={:.1f}s".format(
                BODY_MIX_SETTLE_S, SETTLE_S, CAPTURE_S, PAUSE_S))

    # 12. Expected command counts: with 7 body_mix x 2 pitches and
    # isolation enabled, the total valid command count is:
    #   !I1 = 1
    #   !B  = 7
    #   !F  = 7*2 + 1 (trailing) = 15
    #   !N  = 7*2 = 14
    #   !I0 = 1
    #   total = 38
    counts = expected_command_counts(
        DEFAULT_BODY_MIX_GRID, DEFAULT_PITCH_GRID, single_voice_isolate=True)
    expected_counts = {
        "I1": 1, "B": 7, "F": 15, "N": 14, "I0": 1, "total": 38}
    if counts != expected_counts:
        print("FAIL command_counts default got={} want={}".format(
            counts, expected_counts))
        fails += 1
    else:
        print(
            "PASS command_counts default: !I1=1 !B=7 !F=15 !N=14 !I0=1 "
            "(total 38 valid; X expected 0)")

    # 13. Expected command counts without isolation:
    #   no !I1 / !I0; same !B/!F/!N counts but no enable/disable.
    counts2 = expected_command_counts(
        DEFAULT_BODY_MIX_GRID, DEFAULT_PITCH_GRID, single_voice_isolate=False)
    expected_counts2 = {
        "I1": 0, "B": 7, "F": 15, "N": 14, "I0": 0, "total": 36}
    if counts2 != expected_counts2:
        print("FAIL command_counts no_isolate got={} want={}".format(
            counts2, expected_counts2))
        fails += 1
    else:
        print(
            "PASS command_counts no-isolate: !B=7 !F=15 !N=14 (total 36)")

    # 14. Session duration math: body_mix_settle 0.1s + 2*(1+4+1)=12s
    # per body_mix row, x 7 rows = 84.7s plus 0.1+0.05 if isolation.
    duration = session_duration_s(
        DEFAULT_BODY_MIX_GRID, DEFAULT_PITCH_GRID, single_voice_isolate=True)
    expected_duration = 7 * (BODY_MIX_SETTLE_S +
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
        "schema": "phase6_m6_body_mix_sweep.v1",
        "port": "COM_TEST",
        "baud": 115200,
        "settle_s": SETTLE_S,
        "capture_s": CAPTURE_S,
        "pause_s": PAUSE_S,
        "body_mix_settle_s": BODY_MIX_SETTLE_S,
        "single_voice_isolate": True,
        "session_start_unix": 1700000000.0,
        "body_mix_grid": ["0x{:04X}".format(v) for v in DEFAULT_BODY_MIX_GRID],
        "pitch_grid": [
            {"loop_len": p["loop_len"], "pitch_name": p["pitch_name"]}
            for p in DEFAULT_PITCH_GRID],
        "velocity_hex": "0x7FFF",
        "pre_commands": [
            {"command": "!I1", "send_t_session_s": 0.005},
            {"command": "!B1000", "send_t_session_s": 0.110},
        ],
        "cells": [
            {
                "index": 0,
                "body_mix": 0x1000,
                "body_mix_hex": "0x1000",
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
    elif fake2["cells"][0]["body_mix_hex"] != "0x1000":
        print("FAIL sidecar body_mix_hex")
        fails += 1
    elif fake2["pre_commands"][1]["command"] != "!B1000":
        print("FAIL sidecar pre_command !B1000")
        fails += 1
    elif fake2["post_commands"][1]["command"] != "!I0":
        print("FAIL sidecar post_command")
        fails += 1
    elif fake2["schema"] != "phase6_m6_body_mix_sweep.v1":
        print("FAIL sidecar schema")
        fails += 1
    elif not isinstance(fake2["cells"][0]["send_t_session_s"], list):
        print("FAIL sidecar send_t_session_s should be list")
        fails += 1
    else:
        print("PASS sidecar v1 JSON round-trip")

    # 16. parse_hex_list helper.
    parsed = parse_hex_list("0x1000, 0x2000, 0x3000")
    if parsed != [0x1000, 0x2000, 0x3000]:
        print("FAIL parse_hex_list got={}".format(parsed))
        fails += 1
    else:
        print("PASS parse_hex_list")

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

    if fails == 0:
        print("PHASE6_M6_BODY_MIX_SWEEP_PASS cells={:d}".format(len(cells)))
        return 0
    print("PHASE6_M6_BODY_MIX_SWEEP_FAIL fails={:d}".format(fails))
    return 1


# ---- Main --------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(
        description="Phase 6 M6 body_mix sweep host harness")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--self-check", action="store_true",
                   help="Run fixed-vector validation, exit 0 on PASS.")
    g.add_argument("--plan", action="store_true",
                   help="Print the grid and per-cell command bytes.")
    g.add_argument("--run", action="store_true",
                   help="Drive hardware via serial port.")
    g.add_argument("--analyze", action="store_true",
                   help="Invoke phase6_m1_voice_analyze.py over a captured "
                        "WAV; the resulting CSV is rewritten to include "
                        "body_mix_hex.")

    p.add_argument("--port", default=DEFAULT_PORT)
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--sidecar", default=DEFAULT_SIDECAR)
    p.add_argument("--settle-s", type=float, default=SETTLE_S)
    p.add_argument("--capture-s", type=float, default=CAPTURE_S)
    p.add_argument("--pause-s", type=float, default=PAUSE_S)
    p.add_argument("--body-mix-settle-s", type=float,
                   default=BODY_MIX_SETTLE_S)
    p.add_argument("--body-mix-grid", default=None,
                   help="Comma-separated 16-bit hex values, e.g. "
                        "0x1000,0x2000,0x3000. Default is "
                        "0x1000,0x2000,0x3000,0x4000,0x6000,0x8000,0xC000.")
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

    # --analyze options.
    p.add_argument("--wav", default=None,
                   help="Captured WAV path (with --analyze).")
    p.add_argument("--out", default="reports/phase6_m6_body_mix_sweep.csv",
                   help="Analyzer output CSV path (with --analyze).")
    p.add_argument("--out-md", default=None,
                   help="Optional analyzer output markdown path "
                        "(with --analyze).")
    p.add_argument("--audio-start-unix", type=float, default=None,
                   help="Unix time at which the WAV recording started "
                        "(with --analyze; default: assume same as "
                        "session_start_unix).")
    p.add_argument("--coherent-average", action="store_true",
                   help="Pass --coherent-average to the analyzer (only "
                        "useful if a future M6.x sidecar carries K>1 "
                        "repeats; the current v1 sweep emits K=1).")

    args = p.parse_args()

    try:
        body_mix_values = (parse_hex_list(args.body_mix_grid)
                           if args.body_mix_grid else
                           list(DEFAULT_BODY_MIX_GRID))
        pitches = (parse_pitch_list(args.pitch_grid)
                   if args.pitch_grid else list(DEFAULT_PITCH_GRID))
    except ValueError as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 2

    single_voice_isolate = not args.no_isolate

    if args.self_check:
        return cmd_self_check()
    if args.plan:
        return cmd_plan(body_mix_values, pitches, args.velocity,
                        single_voice_isolate)
    if args.run:
        return run_bench(args.port, args.baud, args.sidecar,
                         body_mix_values, pitches, args.velocity,
                         args.settle_s, args.capture_s, args.pause_s,
                         args.body_mix_settle_s,
                         single_voice_isolate)
    if args.analyze:
        if not args.wav:
            print("ERROR: --wav is required with --analyze", file=sys.stderr)
            return 2
        return cmd_analyze(args.wav, args.sidecar, args.out, args.out_md,
                           args.audio_start_unix, args.coherent_average)
    return 1


if __name__ == "__main__":
    sys.exit(main())
