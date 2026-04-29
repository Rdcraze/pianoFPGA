# Phase 1C UART Parser/Test Tooling Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-bdea980a`  
Implementation artifact: `93afcd41-3b3c-4ce7-91f8-62db5f02e8b8`  
Implementation report: `reports/phase1c_uart_parser_tooling_impl_report.md`

## Verdict

PASS.

The submitted work is host-side parser/test tooling only. I found no evidence of new RTL, firmware, constraints, clock, MIF/build-output, Quartus project, register-map, UART-behavior, hardware-behavior, or bitstream changes in this task window. The parser and tests satisfy the requested Phase 1C round-robin telemetry checks against both the implementer capture and the independent verifier capture.

## Scope Evidence

Observed parser-tooling files:

- `scripts/phase1c_uart_telemetry.py`, last written 2026-04-28 20:32:33
- `scripts/test_phase1c_uart_telemetry.py`, last written 2026-04-28 20:33:09
- `reports/phase1c_uart_parser_tooling_selftest.log`, last written 2026-04-28 20:33:21
- `reports/phase1c_uart_parser_tooling_round_robin_check.log`, last written 2026-04-28 20:33:29
- `reports/phase1c_uart_parser_tooling_validation_capture_check.log`, last written 2026-04-28 20:33:37
- `reports/phase1c_uart_parser_tooling_impl_report.md`, last written 2026-04-28 20:34:12

Device-facing paths remained at earlier timestamps:

- Latest RTL file observed: `rtl/top/piano_phase0_top_tb.v`, 2026-04-28 18:11:53
- Latest firmware build file observed: `fw/phase0/build/phase0.mif`, 2026-04-28 20:00:17
- Latest SOF observed: `quartus/phase0/output_files/piano_phase0_top.sof`, 2026-04-28 20:08:12
- `quartus/phase0/piano_phase0_top.qsf` remained 2026-04-24 10:29:13
- `quartus/phase0/piano_phase0_top.sdc` remained 2026-04-24 08:40:41

This supports the claim that the artifact did not change the device build or hardware behavior after the accepted round-robin bitstream.

## Parser Behavior Review

`scripts/phase1c_uart_telemetry.py` implements byte-stream scanning for uppercase one-character `TAG=XXXXXXXX` frames terminated by CRLF. Valid frames can be found at any byte offset, which supports capture-start and mid-frame recovery. Malformed lines, lowercase/non-matching tags, corrupt bytes, and partial tails are ignored by the regex scanner.

Health validation uses the latest value per tag, so repeated report cycles are accepted and stale earlier values do not fail the capture once a later accepted cycle appears. Unknown valid uppercase tags are preserved in the summary and reported as warnings, but they do not fail health checks.

The accepted Phase 1C round-robin criteria are checked by tag, not by a fixed byte count or fixed report-cycle count:

- Exact checks: `T=2`, `U=2`, `O=2`, `K=0`, `G=6`, `H=2`, `J=2`, `L=2`, `N=2`, `P=0`
- Nonzero checks: `V`, `Y`, `Z`, `M`
- Startup check when requested: `I=0x50303031`, with `I/S/R` required
- Smoke-only counters `F/A/W/B/C/D/E` are required as tags but are not fixed to exact constants

## Independent Verification Commands

```powershell
python scripts\test_phase1c_uart_telemetry.py -v
```

Result: PASS, 10 tests.

Covered synthetic behavior:

- valid frame parsing
- capture starting mid-frame
- corrupt bytes and malformed lines
- unknown tag tolerance
- duplicate/repeated cycles using latest values
- partial tail frame ignored
- smoke-only counters not fixed to constants
- clip-count failure detection
- scheduler-count failure detection
- optional startup requirement

```powershell
python scripts\phase1c_uart_telemetry.py check reports\phase1c_firmware_round_robin_uart_capture.txt --require-startup --json
```

Result: PASS.

Key evidence:

- `frame_count`: 84
- `I`: `0x50303031`
- `T/U/O`: `0x00000002`
- `G`: `0x00000006`
- `H/J/L/N`: `0x00000002`
- `P`: `0x00000000`
- `K`: `0x00000000`
- `V/Y/Z`: `0x08220010`
- `M`: `0x18660010`
- Warning only for repeated tags, with latest values used

```powershell
python scripts\phase1c_uart_telemetry.py check reports\phase1c_firmware_round_robin_validation_uart_capture.txt --require-startup --json
```

Result: PASS.

Key evidence:

- `frame_count`: 68
- `I`: `0x50303031`
- `T/U/O`: `0x00000002`
- `G`: `0x00000006`
- `H/J/L/N`: `0x00000002`
- `P`: `0x00000000`
- `K`: `0x00000000`
- `V/Y/Z`: `0x08220010`
- `M`: `0x18660010`
- Warning only for repeated tags, with latest values used

```powershell
python scripts\phase1c_uart_telemetry.py parse reports\phase1c_firmware_round_robin_validation_uart_capture.txt --json
```

Result: parsed 68 frames with the expected `A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/R/S/T/U/V/W/Y/Z` tag set and no unknown tags.

## Residual Risks

- The tool validates the current Phase 1C round-robin health profile only; future telemetry tags or changed acceptance criteria must update the expected-value table.
- Status fields are checked for nonzero health where requested, but the tool does not decode status bitfields.
- The scanner is intentionally aggressive for mid-frame recovery and will accept any valid-looking single-letter frame at any byte offset. This matches the current UART capture use case, but it is not a strict line-oriented protocol validator.
- This artifact does not implement UART RX command parsing, GPIO event ingress, or device-side behavior.

## Recommendation

Accept the Phase 1C UART parser/test tooling as a host-side verification aid. It is suitable for checking current accepted round-robin captures and for catching the requested scheduler/trigger/clip regressions without changing the FPGA or firmware behavior.
