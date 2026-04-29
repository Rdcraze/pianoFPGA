#!/usr/bin/env python3
"""Tests for the Phase 1C UART RX baseline smoke harness."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from phase1c_uart_rx_baseline_smoke import (  # noqa: E402
    CYCLE_ORDER,
    STARTUP_ORDER,
    validate_capture,
)


def frame(tag: str, value: int) -> bytes:
    return f"{tag}={value:08X}\r\n".encode("ascii")


def cycle(**overrides: int) -> bytes:
    values = {
        "R": 0x8018077F,
        "V": 0x08220010,
        "F": 0x0007E7BF,
        "T": 0x00000002,
        "A": 0x0001EACB,
        "W": 0x0007E856,
        "Y": 0x08220010,
        "U": 0x00000002,
        "B": 0x00020154,
        "C": 0x0007E920,
        "M": 0x18660010,
        "K": 0x00000000,
        "Z": 0x08220010,
        "O": 0x00000002,
        "D": 0x00021850,
        "E": 0x0007EA4D,
        "G": 0x00000006,
        "H": 0x00000002,
        "J": 0x00000002,
        "L": 0x00000002,
        "N": 0x00000002,
        "P": 0x00000000,
        "Q": 0x00000000,
        "X": 0x00000000,
    }
    values.update(overrides)
    return b"".join(frame(tag, values[tag]) for tag in CYCLE_ORDER)


def capture(*cycles: bytes) -> bytes:
    startup = b"".join(
        (
            frame("I", 0x50303031),
            frame("S", 0x8018073F),
        )
    )
    return startup + b"".join(cycles)


class UartRxBaselineSmokeTests(unittest.TestCase):
    def test_no_command_profile_passes(self) -> None:
        result = validate_capture(capture(cycle()), mode="no-command")
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.summary["cycle_count"], 1)

    def test_commanded_profile_passes_with_latest_values(self) -> None:
        stale = cycle()
        commanded = cycle(T=4, U=4, O=4, G=12, J=4, L=4, N=4, Q=6)
        result = validate_capture(capture(stale, commanded), mode="commanded")
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.summary["cycle_count"], 2)

    def test_detects_command_echo_regression(self) -> None:
        result = validate_capture(capture(cycle(T=4, U=4, O=4, G=12, J=4, L=4, N=4, Q=6)) + b"!N\r\n", mode="commanded")
        self.assertFalse(result.ok)
        self.assertIn("command echo regression: raw capture contains !N", result.errors)

    def test_detects_standalone_ack_regression(self) -> None:
        result = validate_capture(capture(cycle()) + b"ACK\r\n", mode="no-command")
        self.assertFalse(result.ok)
        self.assertIn("standalone ACK/OK regression detected", result.errors)

    def test_detects_frozen_order_regression(self) -> None:
        bad_cycle = cycle().replace(frame("Q", 0), b"").replace(frame("X", 0), b"") + frame("X", 0) + frame("Q", 0)
        result = validate_capture(capture(bad_cycle), mode="no-command")
        self.assertFalse(result.ok)
        self.assertTrue(any("frozen telemetry order mismatch" in error for error in result.errors))

    def test_detects_missing_startup_when_required(self) -> None:
        result = validate_capture(cycle(), mode="no-command")
        self.assertFalse(result.ok)
        self.assertIn("missing frozen startup order I,S", result.errors)

    def test_allows_missing_startup_when_requested(self) -> None:
        result = validate_capture(cycle(), mode="no-command", require_startup=False)
        self.assertTrue(result.ok, result.errors)

    def test_accepts_lf_normalized_capture_text(self) -> None:
        lf_capture = capture(cycle()).replace(b"\r\n", b"\n")
        result = validate_capture(lf_capture, mode="no-command")
        self.assertTrue(result.ok, result.errors)
        self.assertIn("parsed LF-normalized text capture as CRLF telemetry", result.warnings)

    def test_startup_order_constant_is_frozen_prefix(self) -> None:
        self.assertEqual(STARTUP_ORDER, ("I", "S"))
        self.assertEqual(CYCLE_ORDER[-2:], ("Q", "X"))


if __name__ == "__main__":
    unittest.main()
