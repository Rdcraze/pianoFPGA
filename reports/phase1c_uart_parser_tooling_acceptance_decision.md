# Phase 1C UART Parser/Test Tooling Acceptance Decision

Date: 2026-04-28
Orchestrator: Codex orchestrator agent `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Task: `task-d085d188`

## Decision

ACCEPTED.

The Phase 1C UART parser/test tooling is accepted as a host-side verification aid for the current accepted three-voice round-robin baseline.

This acceptance does not authorize or imply any device-side behavior change. It does not authorize RTL changes, firmware changes, constraints changes, clock changes, MIF/build-output changes, Quartus project changes, register-map changes, UART behavior changes, hardware behavior changes, or bitstream changes.

## Accepted Scope

Accepted files and evidence:

- `scripts/phase1c_uart_telemetry.py`
- `scripts/test_phase1c_uart_telemetry.py`
- `reports/phase1c_uart_parser_tooling_impl_report.md`
- `reports/phase1c_uart_parser_tooling_selftest.log`
- `reports/phase1c_uart_parser_tooling_round_robin_check.log`
- `reports/phase1c_uart_parser_tooling_validation_capture_check.log`
- `reports/phase1c_uart_parser_tooling_validation.md`

The tooling parses existing UART telemetry frames of the form `TAG=XXXXXXXX\r\n`, recovers from capture-start and mid-frame offsets, ignores malformed or partial frames, tolerates unknown valid uppercase tags as warnings, and validates the latest accepted value per tag across repeated report cycles.

Accepted current Phase 1C health profile:

- Exact checks: `T=2`, `U=2`, `O=2`, `K=0`, `G=6`, `H=2`, `J=2`, `L=2`, `N=2`, `P=0`
- Nonzero checks: `V`, `Y`, `Z`, `M`
- Startup check when requested: `I=0x50303031`, with `I/S/R` required
- Smoke-only counters `F/A/W/B/C/D/E` are parsed but not fixed as permanent ABI constants

## Validation Basis

Verifier artifact `dd1b4ad0-5bc6-4cff-9dd1-f9a220d32339` reported PASS in `reports/phase1c_uart_parser_tooling_validation.md`.

Independent validation confirmed:

- The work was host-side parser/test tooling only.
- No device-facing build or behavior files were changed in the task window.
- `python scripts\test_phase1c_uart_telemetry.py -v` passed 10 tests.
- The parser accepted both the implementer capture and independent verifier capture with `--require-startup --json`.
- The accepted telemetry values matched the current firmware-owned three-voice round-robin criteria.

## Current Baseline Relationship

This tooling supports the already accepted Phase 1C round-robin baseline:

- SOF SHA: `0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0`
- Programmer checksum: `0x005B95A9`
- LEs: `7,548 / 10,320`
- Registers: `3,275`
- Memory bits: `80,896 / 423,936`
- M9Ks: `14 / 46`
- DSP9s: `6 / 46`
- PLLs: `1 / 2`
- `sys_clk_50m` setup slack: `+3.675 ns`
- Hold slack: `+0.433 ns`
- Firmware ROM: `318 / 1024` words

The parser is a measurement and regression aid for this baseline. It is not part of the FPGA image and is not a new hardware feature.

## Residual Risks

- The expected-value table is intentionally tied to the current Phase 1C health profile and must be revised when mandatory telemetry tags or acceptance criteria change.
- Status values are not decoded into named bitfields yet.
- The scanner is intentionally permissive to support capture recovery; it is not a strict protocol validator.
- UART RX command parsing, GPIO event ingress, device-side queues, and host-to-device command behavior remain unimplemented and unauthorized.

## Next Orchestrator Action

Proceed with a design-only UART RX command-ingress contract memo before implementation. That memo must define the minimal command grammar, RX MMIO placement and offsets, malformed/partial/overlong input behavior, acknowledgement telemetry, resource and timing gates, and the ModelSim/Quartus/hardware smoke plan.

No UART RX implementation work should start until that contract is validated and explicitly accepted.
