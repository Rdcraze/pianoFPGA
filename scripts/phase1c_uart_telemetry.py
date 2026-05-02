#!/usr/bin/env python3
"""Host-side parser and health checks for Phase 1C UART telemetry captures."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


FRAME_RE = re.compile(rb"([A-Z]+)=([0-9A-F]{8})\r\n")

VOICE_DIAG_TAGS = ("V", "F", "T", "A", "W", "Y", "U", "B", "C", "M", "K", "Z", "O", "D", "E")
SCHEDULER_TAGS = ("G", "H", "J", "L", "N", "P")
STARTUP_TAGS = ("I", "S", "R")
MEASUREMENT_TAGS = ("CC",)
KNOWN_TAGS = set(STARTUP_TAGS + VOICE_DIAG_TAGS + SCHEDULER_TAGS + MEASUREMENT_TAGS)

ROUND_ROBIN_EXPECTED_VALUES = {
    "T": 0x00000002,
    "U": 0x00000002,
    "O": 0x00000002,
    "K": 0x00000000,
    "G": 0x00000006,
    "H": 0x00000002,
    "J": 0x00000002,
    "L": 0x00000002,
    "N": 0x00000002,
    "P": 0x00000000,
}

NONZERO_HEALTH_TAGS = ("V", "Y", "Z", "M")


@dataclass(frozen=True)
class TelemetryFrame:
    tag: str
    value: int
    offset: int
    raw: str


@dataclass(frozen=True)
class HealthResult:
    ok: bool
    errors: tuple[str, ...]
    warnings: tuple[str, ...]
    summary: dict[str, object]


def parse_frames(data: bytes) -> list[TelemetryFrame]:
    """Return valid TAG=XXXXXXXX CRLF frames found anywhere in the capture."""
    frames: list[TelemetryFrame] = []
    for match in FRAME_RE.finditer(data):
        tag = match.group(1).decode("ascii")
        value_text = match.group(2).decode("ascii")
        frames.append(
            TelemetryFrame(
                tag=tag,
                value=int(value_text, 16),
                offset=match.start(),
                raw=match.group(0).decode("ascii"),
            )
        )
    return frames


def latest_values(frames: Iterable[TelemetryFrame]) -> dict[str, int]:
    latest: dict[str, int] = {}
    for frame in frames:
        latest[frame.tag] = frame.value
    return latest


def tag_counts(frames: Iterable[TelemetryFrame]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for frame in frames:
        counts[frame.tag] = counts.get(frame.tag, 0) + 1
    return counts


def summarize(frames: list[TelemetryFrame]) -> dict[str, object]:
    counts = tag_counts(frames)
    latest = latest_values(frames)
    return {
        "frame_count": len(frames),
        "first_offset": frames[0].offset if frames else None,
        "last_offset": frames[-1].offset if frames else None,
        "tags_seen": sorted(counts),
        "tag_counts": counts,
        "unknown_tags": sorted(tag for tag in counts if tag not in KNOWN_TAGS),
        "latest": {tag: f"0x{value:08X}" for tag, value in sorted(latest.items())},
    }


def validate_round_robin_health(
    frames: list[TelemetryFrame],
    *,
    require_startup: bool = False,
) -> HealthResult:
    """Validate accepted Phase 1C round-robin telemetry without fixing smoke-only counters."""
    errors: list[str] = []
    warnings: list[str] = []
    latest = latest_values(frames)
    counts = tag_counts(frames)

    if not frames:
        errors.append("no valid telemetry frames found")

    required_tags = list(VOICE_DIAG_TAGS + SCHEDULER_TAGS)
    if require_startup:
        required_tags = list(STARTUP_TAGS) + required_tags

    for tag in required_tags:
        if tag not in latest:
            errors.append(f"missing required tag {tag}")

    if "I" in latest and latest["I"] != 0x50303031:
        errors.append(f"I expected 0x50303031, got 0x{latest['I']:08X}")

    for tag, expected in ROUND_ROBIN_EXPECTED_VALUES.items():
        if tag in latest and latest[tag] != expected:
            errors.append(f"{tag} expected 0x{expected:08X}, got 0x{latest[tag]:08X}")

    for tag in NONZERO_HEALTH_TAGS:
        if tag in latest and latest[tag] == 0:
            errors.append(f"{tag} should be nonzero in accepted round-robin smoke")

    unknown_tags = sorted(tag for tag in counts if tag not in KNOWN_TAGS)
    if unknown_tags:
        warnings.append("ignored unknown tags: " + ",".join(unknown_tags))

    duplicate_tags = sorted(tag for tag, count in counts.items() if count > 1)
    if duplicate_tags:
        warnings.append("using latest values for repeated tags: " + ",".join(duplicate_tags))

    summary = summarize(frames)
    summary["require_startup"] = require_startup
    summary["checked_exact_tags"] = sorted(ROUND_ROBIN_EXPECTED_VALUES)
    summary["checked_nonzero_tags"] = list(NONZERO_HEALTH_TAGS)
    summary["smoke_only_not_fixed"] = ["F", "A", "W", "B", "C", "D", "E"]

    return HealthResult(ok=not errors, errors=tuple(errors), warnings=tuple(warnings), summary=summary)


def load_capture(path: Path) -> bytes:
    return path.read_bytes()


def _print_result(result: HealthResult, *, as_json: bool) -> None:
    payload = {
        "ok": result.ok,
        "errors": list(result.errors),
        "warnings": list(result.warnings),
        "summary": result.summary,
    }
    if as_json:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return

    print("PASS" if result.ok else "FAIL")
    print(f"frames={result.summary['frame_count']} tags={','.join(result.summary['tags_seen'])}")
    if result.warnings:
        for warning in result.warnings:
            print(f"warning: {warning}")
    if result.errors:
        for error in result.errors:
            print(f"error: {error}")


def cmd_parse(args: argparse.Namespace) -> int:
    frames = parse_frames(load_capture(args.capture))
    payload = summarize(frames)
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for frame in frames:
            print(f"{frame.offset:08d} {frame.tag}=0x{frame.value:08X}")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    frames = parse_frames(load_capture(args.capture))
    result = validate_round_robin_health(frames, require_startup=args.require_startup)
    _print_result(result, as_json=args.json)
    return 0 if result.ok else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    parse_cmd = subparsers.add_parser("parse", help="print valid telemetry frames")
    parse_cmd.add_argument("capture", type=Path)
    parse_cmd.add_argument("--json", action="store_true")
    parse_cmd.set_defaults(func=cmd_parse)

    check_cmd = subparsers.add_parser("check", help="validate accepted round-robin health")
    check_cmd.add_argument("capture", type=Path)
    check_cmd.add_argument("--require-startup", action="store_true")
    check_cmd.add_argument("--json", action="store_true")
    check_cmd.set_defaults(func=cmd_check)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
