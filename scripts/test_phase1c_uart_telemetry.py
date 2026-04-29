#!/usr/bin/env python3
"""Tests for the Phase 1C UART telemetry parser."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from phase1c_uart_telemetry import (  # noqa: E402
    parse_frames,
    validate_round_robin_health,
)


def frame(tag: str, value: int) -> bytes:
    return f"{tag}={value:08X}\r\n".encode("ascii")


def accepted_capture(**overrides: int) -> bytes:
    values = {
        "I": 0x50303031,
        "S": 0x8018073F,
        "R": 0x8019077F,
        "V": 0x00000011,
        "F": 0x000000E5,
        "T": 0x00000002,
        "A": 0x000000C1,
        "W": 0x00000179,
        "Y": 0x08220011,
        "U": 0x00000002,
        "B": 0x00000186,
        "C": 0x0000023E,
        "M": 0x18660011,
        "K": 0x00000000,
        "Z": 0x08220011,
        "O": 0x00000002,
        "D": 0x000002AE,
        "E": 0x00000365,
        "G": 0x00000006,
        "H": 0x00000002,
        "J": 0x00000002,
        "L": 0x00000002,
        "N": 0x00000002,
        "P": 0x00000000,
    }
    values.update(overrides)
    order = "I S R V F T A W Y U B C M K Z O D E G H J L N P".split()
    return b"".join(frame(tag, values[tag]) for tag in order)


class UartTelemetryParserTests(unittest.TestCase):
    def test_parse_valid_frame(self) -> None:
        frames = parse_frames(frame("T", 2))
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0].tag, "T")
        self.assertEqual(frames[0].value, 2)

    def test_tolerates_capture_starting_mid_frame(self) -> None:
        data = b"00112233\r\njunk" + accepted_capture()
        result = validate_round_robin_health(parse_frames(data), require_startup=True)
        self.assertTrue(result.ok, result.errors)
        self.assertGreater(result.summary["first_offset"], 0)

    def test_ignores_corrupt_bytes_and_malformed_lines(self) -> None:
        data = (
            b"\x00\xffT=0000000Z\r\n"
            b"bad line\r\n"
            b"lower=00000002\r\n"
            + accepted_capture()
        )
        result = validate_round_robin_health(parse_frames(data), require_startup=True)
        self.assertTrue(result.ok, result.errors)

    def test_unknown_tags_do_not_fail_health(self) -> None:
        data = accepted_capture() + frame("Q", 0x12345678)
        result = validate_round_robin_health(parse_frames(data), require_startup=True)
        self.assertTrue(result.ok, result.errors)
        self.assertIn("Q", result.summary["unknown_tags"])

    def test_duplicate_repeated_cycles_use_latest_values(self) -> None:
        stale_cycle = accepted_capture(T=1, U=1, O=1, G=3, J=1, L=1, N=1)
        result = validate_round_robin_health(parse_frames(stale_cycle + accepted_capture()), require_startup=True)
        self.assertTrue(result.ok, result.errors)

    def test_partial_tail_frame_is_ignored(self) -> None:
        data = accepted_capture() + b"T=000"
        result = validate_round_robin_health(parse_frames(data), require_startup=True)
        self.assertTrue(result.ok, result.errors)

    def test_smoke_only_counters_are_not_exact_constants(self) -> None:
        data = accepted_capture(
            F=0xFFFFFFFF,
            A=0x00001234,
            W=0x00005678,
            B=0x00009ABC,
            C=0x0000DEF0,
            D=0x00011111,
            E=0x00022222,
        )
        result = validate_round_robin_health(parse_frames(data), require_startup=True)
        self.assertTrue(result.ok, result.errors)

    def test_detects_clip_count_failure(self) -> None:
        result = validate_round_robin_health(parse_frames(accepted_capture(K=1)), require_startup=True)
        self.assertFalse(result.ok)
        self.assertIn("K expected 0x00000000, got 0x00000001", result.errors)

    def test_detects_scheduler_count_failure(self) -> None:
        result = validate_round_robin_health(parse_frames(accepted_capture(P=1)), require_startup=True)
        self.assertFalse(result.ok)
        self.assertIn("P expected 0x00000000, got 0x00000001", result.errors)

    def test_startup_requirement_is_optional(self) -> None:
        no_startup = b"".join(
            frame(tag, value)
            for tag, value in {
                "V": 0x11,
                "F": 0x01,
                "T": 0x02,
                "A": 0x01,
                "W": 0x01,
                "Y": 0x11,
                "U": 0x02,
                "B": 0x01,
                "C": 0x01,
                "M": 0x11,
                "K": 0x00,
                "Z": 0x11,
                "O": 0x02,
                "D": 0x01,
                "E": 0x01,
                "G": 0x06,
                "H": 0x02,
                "J": 0x02,
                "L": 0x02,
                "N": 0x02,
                "P": 0x00,
            }.items()
        )
        self.assertTrue(validate_round_robin_health(parse_frames(no_startup)).ok)
        self.assertFalse(validate_round_robin_health(parse_frames(no_startup), require_startup=True).ok)


if __name__ == "__main__":
    unittest.main()
