# Phase 1C CC Counter Implementation Report

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-b391edf5`
Commit: `72e83d3`
Governing contract: `reports/phase1c_first_measurement_hook_contract.md`

## Scope

Implement firmware CPU cycle counter (CC tag) measurement hook and parser regex update per the accepted measurement-hook contract.

## Files Changed

- `fw/phase0/phase0_main.c` (+10 lines): Added `phase0_cc_counter` static variable, increment in `phase0_delay()`, CC tag emission in `phase0_report_voice_debug()` (8-digit hex, appended after X), counter initialization in `phase0_program_defaults()`.
- `scripts/phase1c_uart_telemetry.py` (+3/-2 lines): Updated `FRAME_RE` regex from `([A-Z])=` to `([A-Z]+)=` (greedy multi-char match). Added `MEASUREMENT_TAGS = ("CC",)` to `KNOWN_TAGS`.

## Commands Run

- Firmware build: `.\fw\phase0\build.ps1` — exit 0, produced `build/phase0.elf`, `build/phase0.bin`, `build/phase0.mem`
- Parser tests: `python scripts/test_phase1c_uart_telemetry.py` — 10/10 PASS
- Parser regression: parsed `reports/phase1c_uart_rx_command_ingress_boundary_uart_capture.txt` — same output with old and new regex
- Parser CC collision test: verified `([A-Z]+)` correctly distinguishes `C` from `CC`, no spurious `C` from `CC=`
- Quartus full compile: `quartus_sh --flow compile piano_phase0_top` — 0 errors, 14 warnings (same warnings as baseline)

## Validation Evidence

| Check | Result | Path |
| --- | --- | --- |
| Firmware build | PASS | `reports/phase1c_cc_counter_fw_build.log` |
| Parser unit tests (10) | PASS | Console output |
| Parser regression (existing captures) | PASS | Console output |
| CC/C collision fixed (new regex) | PASS | Console output |
| Quartus full compile | PASS (0 errors) | `reports/phase1c_cc_counter_quartus_compile.log` |
| Smoke validation (UART capture) | Not yet run — needs hardware | — |
| Waveform checklist | Not yet run — needs hardware | — |

## Resource / Timing Delta

| Metric | Baseline | This Build | Delta |
| --- | --- | --- | --- |
| LEs | 7,963 | 7,963 | 0 |
| M9Ks | 14 | 14 | 0 |
| DSPs | 6 | 6 | 0 |
| PLLs | 1 | 1 | 0 |
| sys_clk_50m setup slack (slow-85C) | +2.438 ns | +2.438 ns | 0 |
| sys_clk_50m hold slack (slow-85C) | +0.406 ns | +0.406 ns | 0 |
| Firmware ROM words | 507 | 539 | +32 (+128 bytes) |

ROM delta: +32 words (128 bytes), under the 256-byte contract limit. ROM headroom: 1024 - 539 = 485 words free.

## Hardware Identity

Not yet programmed. SOF generated at `quartus/phase0/output_files/piano_phase0_top.sof` with updated firmware MIF. Baseline anchor SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`.

## Residual Risks

- **Hardware smoke not run**: UART capture under no-command and six-command profiles needs to be captured and validated with `scripts/phase1c_uart_rx_baseline_smoke.py`. CC presence, nonzero value, stability (±5%), and range (<100k cycles) all need hardware confirmation.
- **Waveform checklist not run**: Audio path should be unchanged (firmware-only change), but waveform capture is needed to confirm no regression.
- **SOF checksum will differ**: The MIF change produces a different SOF. A new programmer checksum must be recorded.
- **CC value accuracy**: Without a hardware cycle counter, the CC value is an approximate cycle count based on `phase0_delay()` NOP accumulation. It should be deterministic across reports but is not a precise cycle count. This matches the contract's software-approximate allowance.

## Recommendation

Promote with caveat. The implementation is correct: zero resource delta, zero timing delta, parser regression tests pass, JSON compliance checks pass. The remaining validation (hardware UART capture, waveform) requires hardware access. If hardware smoke can be run and the CC value is stable across reports, this is ready for acceptance.
