#!/usr/bin/env python3
"""Phase 1C UART RX baseline smoke checker and optional serial capture tool."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO

from phase1c_uart_telemetry import TelemetryFrame, latest_values, parse_frames, tag_counts


STARTUP_ORDER = ("I", "S")
CYCLE_ORDER = (
    "R",
    "V",
    "F",
    "T",
    "A",
    "W",
    "Y",
    "U",
    "B",
    "C",
    "M",
    "K",
    "Z",
    "O",
    "D",
    "E",
    "G",
    "H",
    "J",
    "L",
    "N",
    "P",
    "Q",
    "X",
)
FROZEN_ORDER = STARTUP_ORDER + CYCLE_ORDER
NONZERO_HEALTH_TAGS = ("V", "Y", "Z", "M")
ACCEPTED_COMMAND = b"!N\r\n"
ACK_LINE_RE = re.compile(rb"(?m)^(?:ACK|OK)\r?\n")

EXPECTED_PROFILES: dict[str, dict[str, int]] = {
    "no-command": {
        "T": 0x00000002,
        "U": 0x00000002,
        "O": 0x00000002,
        "G": 0x00000006,
        "H": 0x00000002,
        "J": 0x00000002,
        "L": 0x00000002,
        "N": 0x00000002,
        "P": 0x00000000,
        "Q": 0x00000000,
        "X": 0x00000000,
        "K": 0x00000000,
    },
    "commanded": {
        "T": 0x00000004,
        "U": 0x00000004,
        "O": 0x00000004,
        "G": 0x0000000C,
        "H": 0x00000002,
        "J": 0x00000004,
        "L": 0x00000004,
        "N": 0x00000004,
        "P": 0x00000000,
        "Q": 0x00000006,
        "X": 0x00000000,
        "K": 0x00000000,
    },
}


@dataclass(frozen=True)
class SmokeResult:
    ok: bool
    mode: str
    errors: tuple[str, ...]
    warnings: tuple[str, ...]
    summary: dict[str, object]


def load_capture(path: Path) -> bytes:
    return path.read_bytes()


def parse_smoke_frames(data: bytes) -> tuple[list[TelemetryFrame], bool]:
    frames = parse_frames(data)
    if frames or b"\n" not in data:
        return frames, False

    normalized = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    return parse_frames(normalized), True


def _find_start_index(frames: list[TelemetryFrame], require_startup: bool) -> int:
    if not require_startup:
        return 0

    tags = [frame.tag for frame in frames]
    for i in range(0, len(tags) - 1):
        if tags[i : i + 2] == list(STARTUP_ORDER):
            return i
    return 0


def _complete_cycle_count(tags: list[str]) -> int:
    count = 0
    width = len(CYCLE_ORDER)
    for i in range(0, len(tags) - width + 1):
        if tuple(tags[i : i + width]) == CYCLE_ORDER:
            count += 1
    return count


def _validate_frozen_order(frames: list[TelemetryFrame], require_startup: bool) -> tuple[list[str], int]:
    errors: list[str] = []
    if not frames:
        return ["no valid telemetry frames found"], 0

    start = _find_start_index(frames, require_startup)
    tags = [frame.tag for frame in frames[start:]]

    if require_startup:
        if tuple(tags[:2]) != STARTUP_ORDER:
            errors.append("missing frozen startup order I,S")
            return errors, _complete_cycle_count(tags)
        cycle_tags = tags[2:]
    else:
        cycle_tags = tags

    cycle_count = 0
    index = 0
    while index < len(cycle_tags):
        if cycle_tags[index] != "R":
            index += 1
            continue
        candidate = tuple(cycle_tags[index : index + len(CYCLE_ORDER)])
        if len(candidate) < len(CYCLE_ORDER):
            break
        if candidate != CYCLE_ORDER:
            errors.append(
                "frozen telemetry order mismatch at parsed frame "
                f"{start + (2 if require_startup else 0) + index}: "
                f"expected {','.join(CYCLE_ORDER)}, got {','.join(candidate)}"
            )
            break
        cycle_count += 1
        index += len(CYCLE_ORDER)

    if cycle_count == 0:
        errors.append("no complete frozen telemetry cycle found")
    return errors, cycle_count


def validate_capture(data: bytes, *, mode: str, require_startup: bool = True) -> SmokeResult:
    frames, normalized_line_endings = parse_smoke_frames(data)
    latest = latest_values(frames)
    counts = tag_counts(frames)
    errors: list[str] = []
    warnings: list[str] = []

    if mode not in EXPECTED_PROFILES:
        raise ValueError(f"unsupported mode: {mode}")

    order_errors, cycle_count = _validate_frozen_order(frames, require_startup)
    errors.extend(order_errors)

    required_tags = set(FROZEN_ORDER if require_startup else CYCLE_ORDER)
    missing = sorted(tag for tag in required_tags if tag not in latest)
    for tag in missing:
        errors.append(f"missing required tag {tag}")

    if "I" in latest and latest["I"] != 0x50303031:
        errors.append(f"I expected 0x50303031, got 0x{latest['I']:08X}")

    for tag, expected in EXPECTED_PROFILES[mode].items():
        if tag in latest and latest[tag] != expected:
            errors.append(f"{tag} expected 0x{expected:08X}, got 0x{latest[tag]:08X}")

    for tag in NONZERO_HEALTH_TAGS:
        if tag in latest and latest[tag] == 0:
            errors.append(f"{tag} should be nonzero in accepted UART RX smoke")

    if ACCEPTED_COMMAND.rstrip() in data:
        errors.append("command echo regression: raw capture contains !N")

    if ACK_LINE_RE.search(data):
        errors.append("standalone ACK/OK regression detected")

    if normalized_line_endings:
        warnings.append("parsed LF-normalized text capture as CRLF telemetry")

    duplicate_tags = sorted(tag for tag, count in counts.items() if count > 1)
    if duplicate_tags:
        warnings.append("using latest values for repeated tags: " + ",".join(duplicate_tags))

    latest_summary = {tag: f"0x{value:08X}" for tag, value in sorted(latest.items())}
    summary: dict[str, object] = {
        "mode": mode,
        "frame_count": len(frames),
        "cycle_count": cycle_count,
        "first_offset": frames[0].offset if frames else None,
        "last_offset": frames[-1].offset if frames else None,
        "require_startup": require_startup,
        "frozen_order": "/".join(FROZEN_ORDER),
        "latest": latest_summary,
        "tag_counts": counts,
    }

    return SmokeResult(
        ok=not errors,
        mode=mode,
        errors=tuple(errors),
        warnings=tuple(warnings),
        summary=summary,
    )


def capture_serial(
    *,
    port_name: str,
    mode: str,
    duration_s: float,
    baud: int,
    output: BinaryIO,
    command_count: int = 6,
    command_interval_s: float = 0.1,
) -> int:
    try:
        import serial  # type: ignore[import-not-found]
    except ImportError:
        print("FAIL pyserial is required for serial capture; use check on an existing capture", file=sys.stderr)
        return 2

    if mode not in EXPECTED_PROFILES:
        raise ValueError(f"unsupported mode: {mode}")

    with serial.Serial(port_name, baudrate=baud, timeout=0.02, write_timeout=1.0) as ser:
        deadline = time.monotonic() + duration_s
        next_command_time = time.monotonic() + command_interval_s
        sent = 0
        while time.monotonic() < deadline:
            now = time.monotonic()
            if mode == "commanded" and sent < command_count and now >= next_command_time:
                ser.write(ACCEPTED_COMMAND)
                sent += 1
                next_command_time = now + command_interval_s

            chunk = ser.read(max(1, ser.in_waiting or 1))
            if chunk:
                output.write(chunk)
            time.sleep(0.005)

        while ser.in_waiting:
            output.write(ser.read(ser.in_waiting))

    return 0


def _result_payload(result: SmokeResult) -> dict[str, object]:
    return {
        "ok": result.ok,
        "mode": result.mode,
        "errors": list(result.errors),
        "warnings": list(result.warnings),
        "summary": result.summary,
    }


def print_result(result: SmokeResult, *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(_result_payload(result), indent=2, sort_keys=True))
        return

    status = "PASS" if result.ok else "FAIL"
    latest = result.summary.get("latest", {})
    if not isinstance(latest, dict):
        latest = {}
    key_fields = " ".join(
        f"{tag}={str(latest.get(tag, 'missing')).replace('0x', '')}"
        for tag in ("G", "Q", "X", "K")
    )
    print(
        f"UART_RX_BASELINE_SMOKE_{status} mode={result.mode} "
        f"frames={result.summary['frame_count']} cycles={result.summary['cycle_count']} {key_fields}"
    )
    for warning in result.warnings:
        print(f"warning: {warning}")
    for error in result.errors:
        print(f"error: {error}")


def cmd_check(args: argparse.Namespace) -> int:
    result = validate_capture(load_capture(args.capture), mode=args.mode, require_startup=args.require_startup)
    print_result(result, as_json=args.json)
    return 0 if result.ok else 1


def cmd_capture(args: argparse.Namespace) -> int:
    with args.output.open("wb") as out:
        rc = capture_serial(
            port_name=args.port,
            mode=args.mode,
            duration_s=args.duration,
            baud=args.baud,
            output=out,
            command_count=args.command_count,
            command_interval_s=args.command_interval,
        )
    if rc != 0:
        return rc
    if args.check:
        result = validate_capture(load_capture(args.output), mode=args.mode, require_startup=args.require_startup)
        print_result(result, as_json=args.json)
        return 0 if result.ok else 1
    print(f"UART_RX_BASELINE_CAPTURE_PASS mode={args.mode} output={args.output}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="validate an existing UART telemetry capture")
    check.add_argument("capture", type=Path)
    check.add_argument("--mode", choices=sorted(EXPECTED_PROFILES), required=True)
    check.add_argument("--require-startup", action="store_true", default=True)
    check.add_argument("--no-require-startup", action="store_false", dest="require_startup")
    check.add_argument("--json", action="store_true")
    check.set_defaults(func=cmd_check)

    capture = subparsers.add_parser("capture", help="capture UART telemetry from a serial port")
    capture.add_argument("--port", required=True)
    capture.add_argument("--output", type=Path, required=True)
    capture.add_argument("--mode", choices=sorted(EXPECTED_PROFILES), required=True)
    capture.add_argument("--duration", type=float, default=12.0)
    capture.add_argument("--baud", type=int, default=115200)
    capture.add_argument("--command-count", type=int, default=6)
    capture.add_argument("--command-interval", type=float, default=0.1)
    capture.add_argument("--check", action="store_true", help="validate the capture after recording")
    capture.add_argument("--require-startup", action="store_true", default=True)
    capture.add_argument("--no-require-startup", action="store_false", dest="require_startup")
    capture.add_argument("--json", action="store_true")
    capture.set_defaults(func=cmd_capture)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
