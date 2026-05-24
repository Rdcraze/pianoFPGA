#!/usr/bin/env python3
"""Phase 5 M3 P5M2 status frame decoder.

Decodes 62-byte CRLF-terminated P5M2 status frames produced by the
live RTL phase0_uart_status_tx block. Frame format:

    P5M2 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX Q=XXXXXXXX X=XXXXXXXX\\r\\n

Three modes:

    --self-check                    Run a fixed test vector through the
                                    decoder, print PASS/FAIL, exit 0/1.

    --capture-file PATH             Decode all P5M2 frames found in the
                                    given file. The file may contain
                                    other text; the decoder finds frames
                                    by scanning for the leading "P5M2 "
                                    tag and reading 62 bytes from there.

    --port COMx [--seconds N]       Open a COM port at 115200 8N1, read
                                    bytes for N seconds (default 5),
                                    decode P5M2 frames inline.

The decoder is pure Python (stdlib only). Live serial mode requires
pyserial; the same dependency the existing scripts/phase3_m{5,6,7,9}
host wrappers already use.

Output: one tab-separated line per decoded frame with timestamp, BOOT,
TICK (hex), VC (decimal), Q (hex), last_error (decimal), error_count
(decimal). A trailing summary prints total frame count and any frames
that had structural problems.
"""

import argparse
import re
import sys
import time
from typing import Dict, Iterable, List, Optional, Tuple

FRAME_RE = re.compile(
    r"^P5M2 BOOT=([0-9A-F]{8}) TICK=([0-9A-F]{8}) VC=([0-9A-F]{2}) "
    r"Q=([0-9A-F]{8}) X=([0-9A-F]{8})\r\n$"
)

# A relaxed regex that matches the same five fields anywhere in a line,
# so we can decode frames from human-readable capture files where each
# frame has been pre-parsed into a row (no CRLF). Used by the
# capture-file mode as a fallback when no raw 62-byte frames are found.
FRAME_RE_LAX = re.compile(
    r"P5M2 BOOT=([0-9A-Fa-f]{8}) TICK=([0-9A-Fa-f]{8}) VC=([0-9A-Fa-f]{2}) "
    r"Q=([0-9A-Fa-f]{8}) X=([0-9A-Fa-f]{8})"
)

FRAME_LEN = 62
TAG = b"P5M2 "


def decode_frame(frame: str) -> Optional[Dict[str, int]]:
    """Decode a single 62-byte ASCII frame string.

    Returns a dict with boot, tick, vc, q, last_error, error_count
    on success, None on structural failure.
    """
    if len(frame) != FRAME_LEN:
        return None
    m = FRAME_RE.match(frame)
    if not m:
        return None
    boot = int(m.group(1), 16)
    tick = int(m.group(2), 16)
    vc = int(m.group(3), 16)
    q = int(m.group(4), 16)
    x = int(m.group(5), 16)
    last_error = (x >> 16) & 0xFFFF
    error_count = x & 0xFFFF
    return {
        "boot": boot,
        "tick": tick,
        "vc": vc,
        "q": q,
        "x": x,
        "last_error": last_error,
        "error_count": error_count,
    }


def find_frames_in_bytes(buf: bytes) -> List[Tuple[int, str]]:
    """Find all P5M2 frames in a byte buffer.

    Returns a list of (offset, frame_string) tuples. Each frame is
    exactly FRAME_LEN ASCII bytes including the CRLF terminator.
    Frames that overrun the buffer are skipped.
    """
    frames: List[Tuple[int, str]] = []
    i = 0
    while True:
        j = buf.find(TAG, i)
        if j < 0:
            break
        end = j + FRAME_LEN
        if end > len(buf):
            break
        candidate = buf[j:end]
        try:
            text = candidate.decode("ascii")
        except UnicodeDecodeError:
            i = j + len(TAG)
            continue
        if text.endswith("\r\n") and decode_frame(text) is not None:
            frames.append((j, text))
            i = end
        else:
            i = j + len(TAG)
    return frames


def print_header(stream) -> None:
    print(
        "timestamp\tboot\ttick_hex\tvc\tq\tlast_error\terror_count",
        file=stream,
    )


def print_frame(stream, ts: float, fields: Dict[str, int]) -> None:
    print(
        "{:.3f}\t{:08X}\t{:08X}\t{:02d}\t{:08X}\t{:d}\t{:d}".format(
            ts,
            fields["boot"],
            fields["tick"],
            fields["vc"],
            fields["q"],
            fields["last_error"],
            fields["error_count"],
        ),
        file=stream,
    )


def cmd_capture_file(path: str) -> int:
    try:
        with open(path, "rb") as fp:
            data = fp.read()
    except OSError as exc:
        print("ERROR: cannot open '{}': {}".format(path, exc), file=sys.stderr)
        return 2

    frames = find_frames_in_bytes(data)
    if frames:
        print_header(sys.stdout)
        for offset, text in frames:
            fields = decode_frame(text)
            if fields is None:
                continue
            ts = offset / (115200.0 / 10.0)
            print_frame(sys.stdout, ts, fields)
        print(
            "\nframes={:d} bytes={:d} mode=raw path={}".format(
                len(frames), len(data), path),
            file=sys.stderr,
        )
        return 0

    # Fallback: treat the file as human-readable text and pull frames
    # out with the lax regex. Useful for capture files the verifier
    # already pre-parsed into rows without CRLF terminators.
    try:
        text = data.decode("utf-8", errors="replace")
    except Exception as exc:
        print("ERROR: cannot decode text: {}".format(exc), file=sys.stderr)
        return 2

    matches = list(FRAME_RE_LAX.finditer(text))
    if not matches:
        print("WARN: no P5M2 frames found in '{}'".format(path), file=sys.stderr)
        return 1

    print_header(sys.stdout)
    for idx, m in enumerate(matches):
        boot = int(m.group(1), 16)
        tick = int(m.group(2), 16)
        vc = int(m.group(3), 16)
        q = int(m.group(4), 16)
        x = int(m.group(5), 16)
        last_error = (x >> 16) & 0xFFFF
        error_count = x & 0xFFFF
        fields = {
            "boot": boot, "tick": tick, "vc": vc, "q": q, "x": x,
            "last_error": last_error, "error_count": error_count,
        }
        # Use the line's leading numeric token as a synthetic timestamp
        # if the file row has one; otherwise use match index.
        line_start = text.rfind("\n", 0, m.start()) + 1
        line = text[line_start:m.start()]
        ts = float(idx)
        toks = line.strip().split()
        for tok in toks:
            try:
                ts = float(tok)
                break
            except ValueError:
                continue
        print_frame(sys.stdout, ts, fields)
    print(
        "\nframes={:d} bytes={:d} mode=text path={}".format(
            len(matches), len(data), path),
        file=sys.stderr,
    )
    return 0


def cmd_live(port: str, seconds: float, baud: int = 115200) -> int:
    try:
        import serial
    except ImportError:
        print(
            "ERROR: pyserial not installed. Install with: pip install pyserial",
            file=sys.stderr,
        )
        return 2

    try:
        ser = serial.Serial(port, baud, timeout=0.1)
    except Exception as exc:
        print("ERROR: cannot open {}: {}".format(port, exc), file=sys.stderr)
        return 2

    print("Connected to {} at {} baud, capturing for {:.2f} s".format(
        port, baud, seconds), file=sys.stderr)
    print_header(sys.stdout)

    deadline = time.monotonic() + seconds
    buf = bytearray()
    frame_count = 0
    err_count = 0
    while time.monotonic() < deadline:
        chunk = ser.read(256)
        if chunk:
            buf.extend(chunk)
        # Try to parse any complete frames we have buffered.
        while True:
            j = buf.find(TAG)
            if j < 0:
                if len(buf) > 4 * FRAME_LEN:
                    # Drop ancient bytes that do not start a frame.
                    del buf[:-FRAME_LEN]
                break
            if j + FRAME_LEN > len(buf):
                break
            text = bytes(buf[j:j + FRAME_LEN]).decode("ascii", errors="replace")
            fields = decode_frame(text)
            if fields is None:
                err_count += 1
                # Skip past this tag occurrence to avoid infinite loop
                del buf[:j + len(TAG)]
            else:
                frame_count += 1
                ts = time.monotonic()
                print_frame(sys.stdout, ts, fields)
                sys.stdout.flush()
                del buf[:j + FRAME_LEN]

    ser.close()
    print("\nframes={:d} parse_errors={:d}".format(frame_count, err_count),
          file=sys.stderr)
    return 0 if frame_count > 0 else 1


def cmd_self_check() -> int:
    fails = 0

    # Vector 1: real frame from the M2 verifier hardware capture
    frame1 = (
        "P5M2 BOOT=0000003F TICK=001687BA VC=03 "
        "Q=00000002 X=00000000\r\n"
    )
    f1 = decode_frame(frame1)
    if f1 is None:
        print("FAIL self_check_v1 decode")
        fails += 1
    elif (f1["boot"] != 0x3F or f1["tick"] != 0x001687BA or f1["vc"] != 3 or
          f1["q"] != 0x00000002 or f1["last_error"] != 0 or
          f1["error_count"] != 0):
        print("FAIL self_check_v1 fields {}".format(f1))
        fails += 1
    else:
        print("PASS self_check_v1 boot=0x3F vc=3 q=2")

    # Vector 2: error fields populated
    frame2 = (
        "P5M2 BOOT=00000040 TICK=0016E348 VC=00 "
        "Q=00000004 X=00020001\r\n"
    )
    f2 = decode_frame(frame2)
    if f2 is None:
        print("FAIL self_check_v2 decode")
        fails += 1
    elif (f2["q"] != 4 or f2["last_error"] != 2 or f2["error_count"] != 1):
        print("FAIL self_check_v2 fields {}".format(f2))
        fails += 1
    else:
        print("PASS self_check_v2 q=4 last_error=2 error_count=1")

    # Vector 3: structural failure should return None
    bad = "GARBAGE not a frame at all\r\n"
    if decode_frame(bad) is not None:
        print("FAIL self_check_v3 garbage decoded")
        fails += 1
    else:
        print("PASS self_check_v3 garbage rejected")

    # Vector 4: short frame should return None
    short = "P5M2 BOOT=DEADBEEF\r\n"
    if decode_frame(short) is not None:
        print("FAIL self_check_v4 short decoded")
        fails += 1
    else:
        print("PASS self_check_v4 short rejected")

    # Vector 5: scan a buffer with mixed content for frame discovery
    junk = b"hello world "
    f5_text = (
        "P5M2 BOOT=00000005 TICK=00000006 VC=01 "
        "Q=00000007 X=00000000\r\n"
    )
    junk2 = b"more junk\n"
    f6_text = (
        "P5M2 BOOT=00000006 TICK=00000007 VC=02 "
        "Q=00000008 X=00000000\r\n"
    )
    buf = junk + f5_text.encode("ascii") + junk2 + f6_text.encode("ascii")
    found = find_frames_in_bytes(buf)
    if len(found) != 2:
        print("FAIL self_check_v5 found={:d}".format(len(found)))
        fails += 1
    elif decode_frame(found[0][1])["boot"] != 5 or decode_frame(found[1][1])["boot"] != 6:
        print("FAIL self_check_v5 boot values")
        fails += 1
    else:
        print("PASS self_check_v5 buffer scan finds 2 frames")

    # Vector 6: lax regex finds frame in pre-parsed text row
    text_row = (
        "POST    2.594 P5M2 BOOT=0000003F TICK=001687BA "
        "VC=03 Q=00000002 X=00000000\n"
    )
    m = FRAME_RE_LAX.search(text_row)
    if m is None:
        print("FAIL self_check_v6 lax regex no match")
        fails += 1
    elif int(m.group(1), 16) != 0x3F or int(m.group(4), 16) != 2:
        print("FAIL self_check_v6 lax regex fields")
        fails += 1
    else:
        print("PASS self_check_v6 lax regex matches text row")

    if fails == 0:
        print("PHASE5_M3_DECODE_PASS vectors=6")
        return 0
    else:
        print("PHASE5_M3_DECODE_FAIL fails={:d}".format(fails))
        return 1

def main() -> int:
    p = argparse.ArgumentParser(description="Phase 5 M3 P5M2 frame decoder")
    g = p.add_mutually_exclusive_group(required=False)
    g.add_argument("--self-check", action="store_true",
                   help="Run fixed-vector self-check and exit")
    g.add_argument("--capture-file", "-f", default=None,
                   help="Decode P5M2 frames from a saved capture file")
    g.add_argument("--port", "-P", default=None,
                   help="Live mode: COM port (e.g. COM5)")
    p.add_argument("--seconds", "-s", type=float, default=5.0,
                   help="Live mode: seconds to capture (default 5)")
    p.add_argument("--baud", "-b", type=int, default=115200)
    args = p.parse_args()

    if args.self_check:
        return cmd_self_check()
    if args.capture_file:
        return cmd_capture_file(args.capture_file)
    if args.port:
        return cmd_live(args.port, args.seconds, args.baud)

    p.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
