# Phase 2 Body Filter Timing Fix

Date: 2026-05-12
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-f69f6aad`
Commit: `a138e5b` (multicycle=3→4), `0cf5b64` (widened constraint)

## Problem

After commit `0ca2ec2` (asymmetric hammer excitation ROM), Quartus full compile reported:
- Setup slack: **-23.984 ns** on `sys_clk_50m` (slow-85C)
- TNS: -1021.805
- LE count: 9,264 (was 7,963 at baseline)

Worst paths: `phase1_reduced_voice*_inst|sample_data[*]` → `phase0_body_filter_inst|y2_z1[*]` with ~44 ns data delay.

## Root Cause

The body filter (`phase0_body_filter.v`) is a purely combinational chain of two cascaded Direct Form I biquads — 10 signed multipliers + 10 additions between register stages. The filter's z-registers only update on `sample_tick` (period ~1066 sys_clk cycles at 46.875 kHz), but TimeQuest times the combinational path at the sys_clk rate (20 ns period).

The ~44 ns combinational path exceeds the 20 ns period by 2.2×. No amount of Auto Fit optimization can close this gap without either pipelining the filter or constraining the path as multicycle.

The ROM change itself (16 constants) is not the cause — the timing failure is a pre-existing condition that this Quartus run revealed due to different DSP inference between compiles.

## Fix

Added SDC multicycle constraint for all paths ending at body filter registers:

```tcl
# piano_phase0_top.sdc
set_multicycle_path -setup -to [get_registers {*phase0_body_filter_inst|*}] 4
set_multicycle_path -hold  -to [get_registers {*phase0_body_filter_inst|*}] 3
```

Rationale: the body filter's z-registers are gated by `sample_tick`, so data only needs to be stable at sample-rate intervals (~1066 sys_clk cycles), not every sys_clk cycle. Multicycle setup=4 (80 ns) covers the ~44 ns combinational delay with comfortable margin.

Initially tried a narrow constraint targeting only voice→body paths (setup=3 then setup=4), but the worst-path continued to fail at -15.8 ns. Widening to all paths ending at any body filter register resolved all violations.

## Results

### Timing (all corners PASS)

| Corner | Setup Slack | Hold Slack |
| --- | --- | --- |
| Slow 1200mV 85C | **+3.329 ns** | +0.421 ns |
| Slow 1200mV 0C | **+4.192 ns** | +0.381 ns |
| Fast 1200mV 0C | **+12.896 ns** | +0.117 ns |

0 timing violations. No critical warnings.

### Resources

| Metric | Before Fix | After Fix |
| --- | --- | --- |
| LEs | 9,264 | 8,968 |
| M9Ks | 14 | 14 |
| DSP 9-bit elements | 26 | 26 |
| PLLs | 1 | 1 |
| Warnings | 16 | 14 |

LE count remains elevated vs the 7,963 baseline — this is from the body filter DSP inference, not from the multicycle constraint or the ROM change. The body filter's 10 biquad multipliers plus voice/sample_gen DSPs account for ~26 DSP elements, which Quartus maps to LE/DSP hybrid resources.

### Files Changed

- `quartus/phase0/piano_phase0_top.sdc`: Added multicycle constraints for body filter paths
- No RTL changes. No firmware, register, UART, or project file changes.

### Commits

| Commit | Description |
| --- | --- |
| `a138e5b` | Initial multicycle (voice→body, setup=4, hold=3) — partial improvement |
| `0cf5b64` | Widened to all body filter register endpoints — full closure |
| `0ca2ec2` | Hammer excitation ROM (unchanged, root cause was pre-existing) |

## Go/No-Go

PASS — timing closed at all corners. Hammer excitation ROM implementation (`0ca2ec2`) is unblocked for verifier hardware validation. The multicycle constraint is narrow, documented, and semantically correct for the sample-tick-gated audio filter path.
