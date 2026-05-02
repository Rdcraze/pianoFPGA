# Phase 1C First Measurement Hook Contract

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-68752505`
Sources: `reports/phase1c_measurement_hooks_options.md`, `reports/phase1c_measurement_hooks_options_validation.md`

## Selected Hook

**Firmware report-service CPU cycle counter** — a firmware-owned 32-bit cycle counter that measures CPU clock cycles consumed by the telemetry report service routine between successive UART telemetry emissions.

This is the single lowest-risk first hook from the options matrix. It is firmware-only, requires no RTL changes, no MMIO register changes, and no new sticky hardware indicators.

## Why Not A Sticky RTL Indicator

A registered sticky RTL indicator (audio-path busy, saturation latch, underrun flag) is the next-lowest-risk hardware option, but it is not justified as the *first* hook for three reasons:

1. No concrete failure mode currently requires a hardware sticky indicator — the baseline passes host smoke, waveform checklist, and resource/timing gates.
2. A firmware-only counter provides immediate observability into the most likely first-order risk (firmware cadence perturbation from future telemetry or service changes) without any RTL or timing impact.
3. A sticky RTL indicator would need fault-injection simulation, clear-semantics design (diagnostic clear RX is blocked), and a hardware re-flash cycle. A firmware counter can be validated entirely in firmware build + host smoke.

## Purpose

Measure whether the firmware telemetry report service routine maintains deterministic timing under the current accepted baseline, and provide a quantitative baseline for detecting firmware cadence drift if future telemetry, command handling, or service work is added.

Concretely: answer "how many CPU cycles does it cost to prepare and emit one telemetry report frame?" and "does that cost stay constant across consecutive reports under no-command and commanded conditions?"

## Precise Data Exposed

| Field | Width | Description |
| --- | --- | --- |
| CPU cycle delta | 32-bit unsigned | Number of CPU clock cycles consumed by the report service routine since the last report emission. Sampled at a deterministic point in the firmware main loop immediately after the previous report is fully transmitted. |
| Counter overflow flag | 1-bit (embedded in value) | Wraps to zero on overflow. A zero value with a prior nonzero history is not an error condition; the 32-bit width makes overflow infrequent at 50 MHz (overflow period > 85 seconds of continuous counting). |

The counter starts at zero on firmware boot and increments only while the report service routine is executing. It is sampled (read and reset) atomically at the point where the report prefix is assembled.

## Ownership Domain

**Firmware only.** The counter lives in firmware data memory (no new RTL registers, no new MMIO addresses, no new bus transactions). It is incremented by the CPU in the existing firmware main loop, using the CPU's own cycle-count capability or a software increment loop in the report service routine.

If the CPU lacks a hardware cycle counter accessible to firmware, a software calibration loop (instruction-counted busy-wait measured against a known timer) is acceptable for the first implementation, provided the calibration constant is documented and the measurement is labeled as software-approximate.

## UART Impact

A new telemetry tag is required to expose the counter value. The tag is appended after the frozen accepted tag order — it must not reorder, remove, or modify any existing tag.

### Tag Selection

All 26 single-letter uppercase tags are already assigned in the frozen order (`I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X`). The proposed new tag is **`CC`** (two-character, uppercase), representing "CPU Cycles."

### Prefix Compatibility

- `CC` is distinguishable from all existing single-letter tags because the parser already expects `=` as the delimiter after a tag identifier. A two-character tag `CC=NNNN` does not collide with any single-character tag.
- The tag is appended after `X` in the frozen order. The new extended order becomes: `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X/CC`
- Existing parsers that stop at the last known tag (`X`) will ignore `CC` without error if they use permissive trailing-content handling. Parsers updated to the new contract will extract `CC`.
- Under no-command smoke the expected profile is `G=6 Q=0 X=0 K=0 CC=<nonzero constant>`.
- Under six-command smoke the expected profile is `G=12 Q=6 X=0 K=0 CC=<nonzero constant>`.

### Non-Prefix Constraint

This contract does **not** add non-prefix UART behavior. The frozen tag order prefix (`I` through `X`) remains unchanged. `CC` is a suffix extension, not a prefix insertion or reordering. No existing tag semantics are altered.

## MMIO Impact

**None.** The counter is firmware-internal. No new MMIO registers are created. No existing register ranges are changed. The counter is not readable or writable by the host except through UART telemetry.

## Clear / Set / Snapshot Semantics

| Operation | Behavior |
| --- | --- |
| Set (increment) | Firmware increments the counter during the report service routine. The increment granularity is one CPU clock cycle (or one software-counted instruction, if using a software loop). |
| Snapshot + clear | At report assembly time, the current counter value is atomically read and the counter is reset to zero. The snapshot value is formatted into the `CC` tag. |
| Overflow | On 32-bit wraparound, the counter wraps to zero. The `CC` value in the overflow report will be near `0xFFFFFFFF`, and the next report will show a small value. This is self-evident. |
| Boot | Counter initializes to zero at firmware start. First report after boot will show the cycle cost of the first report service (not cumulative boot time). |

No explicit diagnostic clear command is required — the counter resets every report. No sticky latching behavior. No host-initiated clear path.

## Resource / Timing / ROM Risk

| Risk category | Estimate | Rationale |
| --- | --- | --- |
| LE / FPGA logic | Zero | No RTL changes. |
| M9K / memory bits | Zero | No new block RAM. |
| DSP | Zero | No DSP use. |
| ROM / firmware code size | Low (< 128 bytes) | One 32-bit counter variable (4 bytes data), increment logic (~20 instructions), snapshot+format logic (~40 instructions), UART formatting (~30 instructions). Approximate ceiling: 128 bytes of additional firmware code. |
| CPU cycle overhead | Low | Increment per service loop iteration (~2-3 instructions). Snapshot and format once per report (~20 instructions). Negligible relative to existing report service cost. |
| UART bandwidth | Low | `CC=NNNNNNNNNN` is at most 15 characters (tag + '=' + up to 10 decimal digits), emitted once per report. At current report cadence this is < 1% of UART bandwidth. |
| Timing slack | Zero impact | No RTL path changes. Firmware-only addition. |
| Report cadence perturbation | Low | The format-and-emit cost is bounded and constant. If the counter itself measurably changes report cadence, that is self-diagnosing (the counter will report the perturbation). |

## Validation Evidence Required

Before this contract is considered accepted:

1. **Firmware build**: ROM delta measured and reported. Must be under 256 bytes.
2. **Host smoke — no-command**: `python scripts\phase1c_uart_rx_baseline_smoke.py check <capture.txt> --mode no-command` passes with `CC` present and nonzero, all existing tags unchanged.
3. **Host smoke — commanded**: Six-command profile passes with `CC` present, all existing tags unchanged (`G=12 Q=6 X=0 K=0`).
4. **Parser update**: `scripts\phase1c_uart_telemetry.py` updated to parse `CC` tag. Existing tag parsing behavior unchanged. Malformed/boundary parser smoke still passes.
5. **CC stability**: Five consecutive no-command reports show `CC` values within ±5% of each other (validates deterministic report service cost).
6. **CC range**: `CC` value is nonzero and within expected bounds for a firmware report service routine at 50 MHz (expected < 100,000 cycles per report).
7. **Waveform checklist**: PASS with the accepted capture setup. No audio change.
8. **Resource/timing**: Quartus compile shows zero resource delta from baseline. No timing slack change.
9. **No echo/ACK regression**: Hardware UART capture shows no spurious echo or ACK behavior.

## Rollback Criteria

The hook is rejected (or must be reworked) if any of:

- Firmware ROM delta exceeds 256 bytes.
- Any existing host smoke check fails (no-command, commanded, malformed/boundary).
- `CC` value is zero in any report (indicates counter not incrementing).
- `CC` values across five consecutive reports vary by more than ±20% (indicates nondeterministic report service timing).
- Any existing UART tag value changes relative to the accepted baseline (indicates firmware perturbation of existing telemetry).
- Quartus resource or timing slack degrades (indicates unintended RTL change — should not happen for firmware-only work, but must be checked).
- Waveform checklist does not pass.

## Go / No-Go Gates

### Go gates (all must be satisfied before implementation begins)

1. This contract is reviewed and accepted by the orchestrator.
2. A distinct implementation task is created (this contract does not authorize implementation).
3. The implementation task explicitly lists `reports/phase1c_first_measurement_hook_contract.md` as its governing contract.
4. Implementation is scoped to firmware changes only (counter variable, increment logic, UART formatting for `CC` tag) plus host parser update for `CC` parsing.
5. No RTL, constraints, build scripts, project files, bitstreams, or register-map files are in scope.

### No-go gates (any one blocks implementation)

1. The orchestrator does not accept this contract.
2. Implementation would require any RTL change, MMIO register change, or non-prefix UART change.
3. Any blocked feature (SDRAM, fourth voice, richer physics, exact-48k PLL, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, host-selected parameters, codec config RX, diagnostic clear RX, sample playback, UI/TFT/touch, CPU audio-loop expansion, non-prefix UART changes, register-map changes outside accepted ranges) would be touched.
4. Firmware ROM headroom is insufficient for a 128-256 byte addition.
5. The `CC` tag cannot be made prefix-compatible with the existing parser (parser update would break existing tag extraction).

## Summary

One hook. Firmware-only. Appended after the frozen prefix. No RTL, no MMIO, no timing risk. Measures what the firmware already does (report service cost), quantifies it, and exposes it as a self-diagnosing constant. If the constant drifts, the hook itself reports the drift. This is the smallest possible first measurement hook that provides actionable observability without touching any blocked domain.
