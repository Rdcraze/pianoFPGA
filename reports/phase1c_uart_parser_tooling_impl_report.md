# Phase 1C UART Parser Tooling Implementation Report

Date: 2026-04-28
Agent: Codex implementer
Task: `task-51d7666e`

## Scope

Implemented host-side UART telemetry parser/test tooling only. No RTL, firmware, constraints, clocks, MIF/build outputs, Quartus project files, register maps, UART behavior, hardware behavior, or bitstream outputs were changed.

Changed files:

- `scripts/phase1c_uart_telemetry.py`
- `scripts/test_phase1c_uart_telemetry.py`
- `reports/phase1c_uart_parser_tooling_impl_report.md`
- Generated evidence logs listed below.

## Tool Behavior

`scripts/phase1c_uart_telemetry.py` parses existing device telemetry frames:

```text
TAG=XXXXXXXX\r\n
```

Parser behavior:

- scans a capture for valid uppercase `TAG=XXXXXXXX` CRLF frames at any byte offset;
- tolerates capture starting mid-frame or with leading corrupt bytes;
- ignores malformed lines and partial tail frames;
- preserves unknown valid uppercase tags in the parsed summary but does not fail health checks because of them;
- handles duplicate and repeated report cycles by validating the latest value per tag;
- validates current accepted firmware round-robin health by tag, not by fixed byte count.

Round-robin health criteria:

- required voice/mix tags through `Z/O/D/E` are present;
- optional startup requirement checks `I/S/R` when requested;
- if `I` is present, it must be `0x50303031`;
- exact accepted values are checked for `T=2`, `U=2`, `O=2`, `K=0`, `G=6`, `H=2`, `J=2`, `L=2`, `N=2`, `P=0`;
- `V`, `Y`, `Z`, and `M` must be nonzero;
- smoke-only active/valid/sample values `F/A/W/B/C/D/E` are parsed but are not treated as permanent ABI constants.

## Usage

Print valid frames from a capture:

```powershell
python scripts\phase1c_uart_telemetry.py parse reports\phase1c_firmware_round_robin_validation_uart_capture.txt
```

Validate accepted round-robin health:

```powershell
python scripts\phase1c_uart_telemetry.py check reports\phase1c_firmware_round_robin_validation_uart_capture.txt --require-startup
```

Emit machine-readable JSON:

```powershell
python scripts\phase1c_uart_telemetry.py check reports\phase1c_firmware_round_robin_validation_uart_capture.txt --require-startup --json
```

Run synthetic tests:

```powershell
python scripts\test_phase1c_uart_telemetry.py -v
```

## Tests Run

Synthetic unit tests:

- Command: `python scripts\test_phase1c_uart_telemetry.py -v`
- Result: PASS, 10 tests
- Evidence: `reports/phase1c_uart_parser_tooling_selftest.log`

Covered cases:

- valid frame parsing;
- capture starting mid-frame;
- corrupt bytes and malformed lines;
- unknown valid tags;
- duplicate/repeated report cycles;
- partial tail frames;
- smoke-only counters not pinned to exact constants;
- clip-count failure detection;
- scheduler drop/steal count failure detection;
- optional startup-frame requirement.

Implementation capture check:

- Command: `python scripts\phase1c_uart_telemetry.py check reports\phase1c_firmware_round_robin_uart_capture.txt --require-startup --json`
- Result: PASS
- Frames parsed: 84
- Latest accepted values include `I=0x50303031`, `T/U/O=2`, `K=0`, `G=6`, `H=2`, `J/L/N=2`, `P=0`
- Evidence: `reports/phase1c_uart_parser_tooling_round_robin_check.log`

Independent validation capture check:

- Command: `python scripts\phase1c_uart_telemetry.py check reports\phase1c_firmware_round_robin_validation_uart_capture.txt --require-startup --json`
- Result: PASS
- Frames parsed: 68
- Latest accepted values include `I=0x50303031`, `T/U/O=2`, `K=0`, `G=6`, `H=2`, `J/L/N=2`, `P=0`
- Evidence: `reports/phase1c_uart_parser_tooling_validation_capture_check.log`

## Limitations

- The tooling validates existing UART telemetry only; it does not implement or assume UART RX, GPIO ingress, event queues, or host-to-device commands.
- It validates the current accepted round-robin health profile and should be extended by a later decision if the telemetry ABI gains new mandatory tags.
- It intentionally does not assert exact active/valid/sample counters because those are smoke-only observations, not permanent ABI constants.
- It does not decode status bitfields into named fields yet; it only checks identity, exact health counters, nonzero voice/mix status, required tag presence, and parser robustness.
