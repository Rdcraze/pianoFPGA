# Phase 6 M6.6-DISP Runtime Dispersion Coefficient

Date: 2026-05-28
Task: `task-ee5d03aa`
Parent: `64fe124` (M6.6 scope validation)

## TL;DR

**PASS.** LE +42 (5,279 vs 5,237), under +50 hard gate.
Setup +5.770 ns. All gates met.

Added `!S<vvvv>` runtime dispersion coefficient command.
Full signed 16-bit range valid (no clamping). Reset default
16'sd9952 (0x26E0). Replaces the static
`assign voice_disp_coeff = 16'sd9952` in fixed_control with
a runtime wire from the parser.

## Files changed

- `rtl/control/phase0_uart_command.v` (!S command + port)
- `rtl/control/phase0_uart_command_tb.v` (tests 26-31)
- `rtl/control/phase0_fixed_control.v` (runtime port + assign)
- `rtl/control/phase0_fixed_control_isolation_tb.v` (port wire)
- `rtl/top/piano_phase0_top.v` (wire + routing)
- `reports/phase6_m6_6_quartus_compile.log` (build evidence)
- `reports/phase6_m6_6_disp_runtime_impl.md` (this report)

Host sweep helper deferred to a follow-up commit (same
pattern as M6.5-DAMP raised-cap completion).

## Quartus

| metric | M6.5-DAMP baseline | M6.6-DISP | delta |
| ------ | ------------------:| ---------:| -----:|
| LE     | 5,237              | 5,279     | +42   |
| Setup  | +5.213 ns          | +5.770 ns | +0.557|
| DSP9   | 26/46              | 26/46     | 0     |
| M9K    | 5                  | 5         | 0     |
| PLL    | 1/2                | 1/2       | 0     |
| Errors | 0                  | 0         | 0     |
| Warnings| 16                | 16        | 0     |

## Semantic direction

`disp_coeff` is the allpass coefficient in STATE_AP_FINISH.
Positive values produce forward dispersion (upper partials
sharper); negative values invert. `!S0000` = no dispersion
(purely harmonic). `!S26E0` = current default. `!S7FFF` =
maximum positive dispersion.

## Verifier handoff

Program SOF, run dispersion sweep
`[0x0000, 0x1000, 0x26E0, 0x4000, 0x7FFF]` x A4/C5.
Measure 2nd partial frequency shift. PASS >= +5 Hz on A4.
