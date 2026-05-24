#!/usr/bin/env python3
"""Phase 6 M1 voice-quality benchmark harness.

Drives the live M2 RTL UART command path through a hardware serial
port to strike a fixed (pitch x velocity) grid of single notes. The
goal is to produce a structured, repeatable baseline of single-voice
acoustic behavior that future Phase 6 RTL voice-quality experiments
can be A/B'd against.

The harness only emits commands the M2 parser already accepts:
    !F\\r\\n              release/silence
    !NLLLLVVVV\\r\\n      parameterized note (loop_len 32..127, velocity 0..0x7FFF)

Per cell pacing:
    1. send !F to silence prior ring
    2. wait SETTLE_S (1.0 s)
    3. record send timestamp into the sidecar
    4. send !NLLLLVVVV
    5. wait CAPTURE_S (4.0 s) for the strike to be captured
    6. wait PAUSE_S (1.0 s) before the next cell

Sidecar JSON format written by --run mode (consumed by the analyzer):

    {
        "schema": "phase6_m1_voice_bench.v1",
        "port": "COM5",
        "baud": 115200,
        "settle_s": 1.0,
        "capture_s": 4.0,
        "pause_s": 1.0,
        "session_start_unix": 1234567890.123,
        "cells": [
            {"index": 0, "loop_len": 127, "velocity": 8192, "command":
             "!N007F2000", "send_t_session_s": 1.234},
            ...
        ]
    }

Each cell's `send_t_session_s` is the relative time (in seconds from
the session start) at which the bench called serial.write() for the
note command. The analyzer aligns audio segments by this value plus
the session start that the operator records when starting the audio
capture (e.g. with ffmpeg or the verifier's existing capture flow).

Modes:
    --self-check         Run fixed-vector validation, exit 0 on PASS.
    --plan               Print the grid and per-cell command bytes
                         without opening hardware.
    --run --port COM5    Drive hardware. Writes a sidecar JSON next to
                         the optional --sidecar path (default
                         reports/phase6_m1_voice_bench_session.json).
"""

import argparse
import json
import sys
import time
from typing import Dict, List, Tuple

# -- Grid definition (matches Phase 6 M0 scope section 3) --
LOOP_LEN_VALUES = [127, 106, 89, 53, 32]
VELOCITY_VALUES_ORIGINAL = [0x2000, 0x4000, 0x7FFF]
# Phase 6 M1.2 clean-level profile: lower velocities so that long
# loop_len cells do not approach full-scale saturation under the
# isolated voice0 baseline.
VELOCITY_VALUES_CLEAN = [0x0800, 0x1000, 0x2000]
# Default profile used by build_grid() and self-check assertions.
VELOCITY_VALUES = VELOCITY_VALUES_ORIGINAL

PROFILE_ORIGINAL = "original"
PROFILE_CLEAN = "clean"

PITCH_NAMES = {
    127: "loop127",  # ~370 Hz floor (clamp); not exactly A2
    106: "A4",
    89:  "C5",
    53:  "A5",
    32:  "loop32",   # clamp ceiling; not exactly A6
}

SETTLE_S = 1.0
CAPTURE_S = 4.0
PAUSE_S = 1.0

DEFAULT_PORT = "COM5"
DEFAULT_BAUD = 115200
DEFAULT_SIDECAR = "reports/phase6_m1_voice_bench_session.json"

# Phase 6 M1.1 isolation-mode commands.
ISOLATE_ENABLE = b"!I1\r\n"
ISOLATE_DISABLE = b"!I0\r\n"


def build_grid(profile: str = PROFILE_ORIGINAL) -> List[Dict]:
    if profile == PROFILE_CLEAN:
        velocities = VELOCITY_VALUES_CLEAN
    else:
        velocities = VELOCITY_VALUES_ORIGINAL
    cells = []
    idx = 0
    for loop_len in LOOP_LEN_VALUES:
        for velocity in velocities:
            cmd = "!N{:04X}{:04X}".format(loop_len, velocity)
            pitch_name = PITCH_NAMES.get(loop_len, "loop{:d}".format(loop_len))
            cells.append({
                "index": idx,
                "loop_len": loop_len,
                "velocity": velocity,
                "pitch_name": pitch_name,
                "command_ascii": cmd,
                "command_bytes": (cmd + "\r\n").encode("ascii"),
            })
            idx += 1
    return cells


def cmd_release_bytes() -> bytes:
    return b"!F\r\n"


# ---- Bench run ----------------------------------------------------------


def run_bench(port: str, baud: int, sidecar_path: str,
              settle_s: float, capture_s: float, pause_s: float,
              single_voice_isolate: bool,
              profile: str,
              repeats: int) -> int:
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

    cells = build_grid(profile)
    session_start = time.monotonic()
    session_unix = time.time()

    sidecar = {
        "schema": "phase6_m1_voice_bench.v2",
        "port": port,
        "baud": baud,
        "settle_s": settle_s,
        "capture_s": capture_s,
        "pause_s": pause_s,
        "single_voice_isolate": single_voice_isolate,
        "profile": profile,
        "repeats": repeats,
        "session_start_unix": session_unix,
        "pre_commands": [],
        "cells": [],
        "post_commands": [],
    }

    print(
        "Phase 6 M1 voice bench: {} cells x {} repeats (profile={}), "
        "total {:.1f} s + setup{}".format(
            len(cells), repeats, profile,
            len(cells) * repeats * (settle_s + capture_s + pause_s),
            " (isolation_mode=ON, M1.2 reset-on-!F)" if single_voice_isolate else ""),
        file=sys.stderr,
    )
    print(
        "Start audio capture now and record the audio start unix time. "
        "Sidecar session_start_unix={:.3f}".format(session_unix),
        file=sys.stderr,
    )
    # Give the operator 3 s to start the audio capture if needed.
    time.sleep(3.0)

    if single_voice_isolate:
        ser.write(ISOLATE_ENABLE)
        sidecar["pre_commands"].append({
            "command": "!I1",
            "send_t_session_s": round(time.monotonic() - session_start, 3),
        })
        # Brief settle so the isolation_mode flag latches before the
        # first strike.
        time.sleep(0.1)

    for cell in cells:
        send_times = []
        for r in range(repeats):
            # Settle: emit !F first to silence any prior ringing.
            # In isolation mode this is the M1.2 hard-reset of voice0.
            ser.write(cmd_release_bytes())
            time.sleep(settle_s)

            # Strike.
            send_t = time.monotonic() - session_start
            ser.write(cell["command_bytes"])
            send_times.append(round(send_t, 3))

            print(
                "[{:02d}.{:02d}] t={:7.3f}s strike {:s} {}".format(
                    cell["index"], r, send_t, cell["command_ascii"],
                    cell["pitch_name"],
                ),
                file=sys.stderr,
            )

            # Capture window.
            time.sleep(capture_s)

            # Pause.
            time.sleep(pause_s)

        sidecar["cells"].append({
            "index": cell["index"],
            "loop_len": cell["loop_len"],
            "velocity": cell["velocity"],
            "pitch_name": cell["pitch_name"],
            "command": cell["command_ascii"],
            "send_t_session_s": send_times,
        })

    # Final !F to silence the last ring.
    ser.write(cmd_release_bytes())
    sidecar["post_commands"].append({
        "command": "!F",
        "send_t_session_s": round(time.monotonic() - session_start, 3),
    })

    if single_voice_isolate:
        time.sleep(0.05)
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


def cmd_plan(single_voice_isolate: bool, profile: str, repeats: int) -> int:
    cells = build_grid(profile)
    total = len(cells) * repeats * (SETTLE_S + CAPTURE_S + PAUSE_S)
    print(
        "Phase 6 M1 grid: {:d} cells x {:d} repeats (profile={}), total ~{:.1f} s{}".format(
            len(cells), repeats, profile, total,
            " (isolation_mode=ON, M1.2 reset-on-!F)" if single_voice_isolate else ""))
    print(
        "  per cell: settle {:.1f}s, capture {:.1f}s, pause {:.1f}s".format(
            SETTLE_S, CAPTURE_S, PAUSE_S))
    if single_voice_isolate:
        print("  pre:  !I1\\r\\n  (enable single-voice isolation mode)")
        print("  per-cell !F is a hard reset of voice0 in M1.2 builds.")
    if repeats > 1:
        print("  per-cell repeated K={:d} times for coherent averaging.".format(
            repeats))
    print()
    print("idx  pitch    loop_len velocity  command")
    print("---  -------  -------- --------  --------------")
    for c in cells:
        print("{:3d}  {:7s}  {:>8d} {:#06x}    {}\\r\\n".format(
            c["index"], c["pitch_name"],
            c["loop_len"], c["velocity"], c["command_ascii"]))
    if single_voice_isolate:
        print()
        print("post: !F\\r\\n  + !I0\\r\\n  (release, then disable isolation)")
    return 0


# ---- Self-check ---------------------------------------------------------


def cmd_self_check() -> int:
    fails = 0

    cells = build_grid()
    if len(cells) != 5 * 3:
        print("FAIL grid_size got={:d} want=15".format(len(cells)))
        fails += 1
    else:
        print("PASS grid_size 15")

    # Default profile is original.
    if cells[0]["velocity"] != 0x2000:
        print("FAIL default_profile_v0 got=%#06x want=0x2000" % cells[0]["velocity"])
        fails += 1
    else:
        print("PASS default_profile=original (cell0 vel=0x2000)")

    # Clean profile: same loop_len count, lower velocities.
    clean = build_grid(PROFILE_CLEAN)
    if len(clean) != 15:
        print("FAIL clean_grid_size got={:d} want=15".format(len(clean)))
        fails += 1
    elif clean[0]["velocity"] != 0x0800 or clean[1]["velocity"] != 0x1000 or \
         clean[2]["velocity"] != 0x2000:
        print("FAIL clean_profile_velocities {} {} {}".format(
            clean[0]["velocity"], clean[1]["velocity"], clean[2]["velocity"]))
        fails += 1
    elif clean[0]["command_ascii"] != "!N007F0800":
        print("FAIL clean_c0_command got={}".format(clean[0]["command_ascii"]))
        fails += 1
    elif clean[14]["command_ascii"] != "!N00202000":
        print("FAIL clean_last_command got={}".format(clean[14]["command_ascii"]))
        fails += 1
    else:
        print("PASS clean_profile_grid (cell0 !N007F0800, last !N00202000)")

    # Check first row corner cell: loop_len=127 velocity=0x2000
    c0 = cells[0]
    if c0["loop_len"] != 127 or c0["velocity"] != 0x2000:
        print("FAIL c0 fields {}".format(c0))
        fails += 1
    elif c0["command_ascii"] != "!N007F2000":
        print("FAIL c0 command {}".format(c0["command_ascii"]))
        fails += 1
    elif c0["command_bytes"] != b"!N007F2000\r\n":
        print("FAIL c0 bytes {}".format(c0["command_bytes"]))
        fails += 1
    else:
        print("PASS c0 !N007F2000\\r\\n")

    # Check A4 high-velocity cell. A4 loop_len=106, velocity=0x7FFF.
    a4_high = next((c for c in cells if c["loop_len"] == 106 and c["velocity"] == 0x7FFF), None)
    if a4_high is None:
        print("FAIL a4_high missing")
        fails += 1
    elif a4_high["command_ascii"] != "!N006A7FFF":
        print("FAIL a4_high command {}".format(a4_high["command_ascii"]))
        fails += 1
    else:
        print("PASS a4_high !N006A7FFF (matches reduced-voice TB pitch)")

    # Check loop_len=32 cell appears.
    last = cells[-1]
    if last["loop_len"] != 32 or last["velocity"] != 0x7FFF:
        print("FAIL last_cell fields {}".format(last))
        fails += 1
    elif last["command_ascii"] != "!N00207FFF":
        print("FAIL last_cell command {}".format(last["command_ascii"]))
        fails += 1
    else:
        print("PASS last_cell !N00207FFF (loop_len=32 ceiling)")

    # Check release is exactly !F\r\n
    if cmd_release_bytes() != b"!F\r\n":
        print("FAIL release_bytes {!r}".format(cmd_release_bytes()))
        fails += 1
    else:
        print("PASS release_bytes !F\\r\\n")

    # Check pacing constants are sane (capture > 0, settle > 0, pause > 0)
    if SETTLE_S <= 0.0 or CAPTURE_S <= 0.0 or PAUSE_S <= 0.0:
        print("FAIL pacing constants {} {} {}".format(SETTLE_S, CAPTURE_S, PAUSE_S))
        fails += 1
    elif CAPTURE_S < 2.0:
        print("FAIL capture window too short {:.2f}s".format(CAPTURE_S))
        fails += 1
    else:
        print("PASS pacing settle={:.2f}s capture={:.2f}s pause={:.2f}s".format(
            SETTLE_S, CAPTURE_S, PAUSE_S))

    # Sidecar schema dry-run: build a fake sidecar with two cells and
    # validate JSON serialization round-trip.
    fake = {
        "schema": "phase6_m1_voice_bench.v2",
        "port": "COM_TEST",
        "baud": 115200,
        "settle_s": SETTLE_S,
        "capture_s": CAPTURE_S,
        "pause_s": PAUSE_S,
        "single_voice_isolate": True,
        "repeats": 4,
        "session_start_unix": 1700000000.0,
        "pre_commands": [
            {"command": "!I1", "send_t_session_s": 0.005},
        ],
        "cells": [
            {
                "index": cells[0]["index"],
                "loop_len": cells[0]["loop_len"],
                "velocity": cells[0]["velocity"],
                "pitch_name": cells[0]["pitch_name"],
                "command": cells[0]["command_ascii"],
                "send_t_session_s": [1.234, 7.234, 13.234, 19.234],
            },
        ],
        "post_commands": [
            {"command": "!F", "send_t_session_s": 5.500},
            {"command": "!I0", "send_t_session_s": 5.555},
        ],
    }
    s = json.dumps(fake, sort_keys=True)
    fake2 = json.loads(s)
    if fake2 != fake:
        print("FAIL sidecar round-trip not idempotent")
        fails += 1
    elif fake2["cells"][0]["command"] != "!N007F2000":
        print("FAIL sidecar cell command")
        fails += 1
    elif fake2["pre_commands"][0]["command"] != "!I1":
        print("FAIL sidecar pre_command")
        fails += 1
    elif fake2["post_commands"][1]["command"] != "!I0":
        print("FAIL sidecar post_command")
        fails += 1
    elif fake2["schema"] != "phase6_m1_voice_bench.v2":
        print("FAIL sidecar schema not v2")
        fails += 1
    elif fake2["repeats"] != 4:
        print("FAIL sidecar repeats")
        fails += 1
    elif not isinstance(fake2["cells"][0]["send_t_session_s"], list):
        print("FAIL sidecar send_t_session_s should be list in v2")
        fails += 1
    elif len(fake2["cells"][0]["send_t_session_s"]) != 4:
        print("FAIL sidecar send_t_session_s length")
        fails += 1
    else:
        print("PASS sidecar v2 JSON round-trip (K=4 timestamp list)")

    # K=4 grid command bytes: 5 cells x 3 velocities x 4 repeats =
    # 60 strikes, but each strike uses the same per-cell command.
    # Verify build_grid returns the same 15 commands regardless of
    # repeats; the bench just sends each command 4 times in K=4.
    if len(cells) != 15:
        print("FAIL k4_grid_size {}".format(len(cells)))
        fails += 1
    elif cells[0]["command_bytes"] != b"!N007F2000\r\n":
        print("FAIL k4_first_command")
        fails += 1
    else:
        print("PASS k4_grid 15 cells, command bytes unchanged at K>=1")

    # Isolation command bytes
    if ISOLATE_ENABLE != b"!I1\r\n":
        print("FAIL isolate_enable_bytes {!r}".format(ISOLATE_ENABLE))
        fails += 1
    else:
        print("PASS isolate_enable_bytes !I1\\r\\n")
    if ISOLATE_DISABLE != b"!I0\r\n":
        print("FAIL isolate_disable_bytes {!r}".format(ISOLATE_DISABLE))
        fails += 1
    else:
        print("PASS isolate_disable_bytes !I0\\r\\n")

    if fails == 0:
        print("PHASE6_M1_BENCH_PASS cells={:d}".format(len(cells)))
        return 0
    print("PHASE6_M1_BENCH_FAIL fails={:d}".format(fails))
    return 1


# ---- Main ---------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(description="Phase 6 M1 voice-quality bench")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--self-check", action="store_true",
                   help="Run fixed-vector validation, exit 0 on PASS")
    g.add_argument("--plan", action="store_true",
                   help="Print grid without hardware")
    g.add_argument("--run", action="store_true",
                   help="Drive hardware via serial port")
    p.add_argument("--port", default=DEFAULT_PORT)
    p.add_argument("--baud", type=int, default=DEFAULT_BAUD)
    p.add_argument("--sidecar", default=DEFAULT_SIDECAR)
    p.add_argument("--settle-s", type=float, default=SETTLE_S)
    p.add_argument("--capture-s", type=float, default=CAPTURE_S)
    p.add_argument("--pause-s", type=float, default=PAUSE_S)
    p.add_argument("--single-voice-isolate", action="store_true",
                   help="Send !I1 before the grid and !I0 after, so the "
                        "live RTL routes every command note to voice0 "
                        "and mutes voices 1/2/3 from the mix.")
    p.add_argument("--profile", choices=[PROFILE_ORIGINAL, PROFILE_CLEAN],
                   default=PROFILE_ORIGINAL,
                   help="Velocity profile. 'original' uses 0x2000/0x4000/"
                        "0x7FFF; 'clean' uses 0x0800/0x1000/0x2000 to "
                        "avoid full-scale saturation on long loop_len "
                        "cells.")
    p.add_argument("--repeats", "-K", type=int, default=1,
                   help="Phase 6 M4: number of consecutive reset+strike "
                        "events per cell. Coherent averaging in the "
                        "analyzer gives +10*log10(K) dB SNR for "
                        "time-locked content. K=1 (default) preserves "
                        "the M1/M2/M3 single-strike behavior.")
    args = p.parse_args()

    if args.repeats < 1:
        print("ERROR: --repeats must be >= 1", file=sys.stderr)
        return 2

    if args.self_check:
        return cmd_self_check()
    if args.plan:
        return cmd_plan(args.single_voice_isolate, args.profile, args.repeats)
    if args.run:
        return run_bench(args.port, args.baud, args.sidecar,
                         args.settle_s, args.capture_s, args.pause_s,
                         args.single_voice_isolate, args.profile,
                         args.repeats)
    return 1


if __name__ == "__main__":
    sys.exit(main())
