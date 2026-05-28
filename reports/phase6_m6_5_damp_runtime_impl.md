# Phase 6 M6.5-DAMP Runtime Damp-Mix Control (NO-GO on LE gate)

Date: 2026-05-28
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-3dbe782c`
Branch: `codex/phase1c-uart-boundary-fix`
Parent commit: `635fef5` (M6.5 pivot scope)
M6.4-INT baseline: `5ed08ec` (LE 5,102, setup +5.954 ns)

## TL;DR

**NO-GO: LE +135 exceeds the +50 hard gate.**

The M6.5-DAMP implementation is functionally correct and
compiles cleanly (0 errors, 16 warnings, setup +5.213 ns,
hold clean, all TNS 0, M9K/DSP9/PLL unchanged), but the LE
cost is +135 versus the M6.4-INT baseline (5,237 vs 5,102).
This exceeds the task's explicit +50 LE hard gate.

The RTL is committed in-place (not reverted) so orchestrator
can inspect and decide whether to raise the cap. The host
sweep helper is deferred until the LE gate is resolved.

## 1. What was implemented

Five RTL files modified:

1. `rtl/control/phase0_uart_command.v`: added `!D<vvvv>`
   command (8-byte, mirroring `!B`), `damp_mix_runtime`
   output port, reset default 0x4000, clamp to 0x7FFF.
2. `rtl/control/phase0_uart_command_tb.v`: added
   `damp_mix_runtime` wiring and 6 test cases (20-25).
3. `rtl/control/phase0_fixed_control.v`: added
   `damp_mix_runtime` input port, replaced reset-path and
   note_strobe-path `16'd16384` literals with
   `damp_mix_runtime`. Release_strobe `16'd32767` untouched.
4. `rtl/control/phase0_fixed_control_isolation_tb.v`: added
   `damp_mix_runtime` port wiring (16'd16384).
5. `rtl/top/piano_phase0_top.v`: added
   `cmd_damp_mix_runtime` wire and routed between parser
   and fixed_control.

## 2. Quartus result

| metric                    | M6.4-INT baseline | M6.5-DAMP | delta |
| ------------------------- | ----------------: | --------: | ----: |
| Total LE                  | 5,102 / 10,320    | **5,237** | **+135** |
| Combinational functions   | 4,897             | 4,973     | +76  |
| Dedicated logic registers | 2,313             | 2,342     | +29  |
| Total memory bits         | 20,480            | 20,480    | 0    |
| DSP9 elements             | 26 / 46           | 26 / 46   | 0    |
| PLL                       | 1 / 2             | 1 / 2     | 0    |
| Setup slow-85C sys_clk_50m| +5.954 ns         | +5.213 ns | -0.741 |
| Hold slow-85C             | +0.381 ns         | +0.409 ns | +0.028 |
| All TNS                   | 0                 | 0         | 0    |
| Errors / warnings         | 0 / 16            | 0 / 16    | 0    |

Hard gate: LE delta <= +50. Got +135. **NO-GO.**

Setup is still healthy at +5.213 ns (well above +4.0 ns
hard). M9K/DSP/PLL unchanged. The design is functionally
safe but exceeds the orchestrator's LE budget.

## 3. Why +135 LE

The M5 `!B` command added ~+30 LE. The M6.5-DAMP `!D`
command mirrors `!B` structurally but adds:

- A 16-bit comparator for the `> 0x7FFF` clamp (~16 LE).
- A 16-bit `damp_mix_runtime` register in the parser
  (~16 LE).
- The `damp_mix_runtime` input port on
  `phase0_fixed_control` replaces two static `16'd16384`
  literals with a runtime wire, which defeats constant
  folding on the `voice_damp_mix_reg` path and forces the
  fitter to route a 16-bit bus through the control block
  (~50-80 LE of routing/mux logic).

The constant-folding loss is the dominant cost: when
`voice_damp_mix_reg` was always loaded from a literal, the
synthesizer could optimize the register-load mux. With a
runtime input, the full 16-bit datapath must be preserved.
This is the same structural cost pattern as M6.3a's body
magnitude doubling (+43 LE from defeating constant folding).

## 4. Follow-up options

### 4.1 Raise the LE cap to +150

Precedent: M5 raised from +150 to +200 for the body_mix
runtime knob; M6.3a raised from +20 to +50 for body
magnitude doubling. Both were intrinsic voice-quality costs
on a design at ~50% device utilization.

M6.5-DAMP at 5,237 LE is still only 51% of EP4CE10. Setup
margin +5.213 ns is comfortable. The runtime damp_mix knob
is a high-value voice-quality feature (sustain control).

### 4.2 Remove the clamp and apply MSB-saturating pattern

Instead of clamping in the parser, apply the same
MSB-saturating pattern as M6.2 body_mix directly at the
voice multiplier site (`STATE_DAMP_A_FINISH`). This removes
the parser comparator (~16 LE) but does not address the
constant-folding loss (~80+ LE). Net savings: ~16 LE,
still well above +50.

### 4.3 Accept the cost as-is under a raised cap

My recommendation: raise the cap to +150 LE for this
single slice, following the M5/M6.3a precedent. The
runtime damp_mix knob is the highest-value remaining
voice-quality feature and the cost is intrinsic to making
a previously-static parameter runtime-variable.

## 5. Damp_mix semantic direction

From `phase1_reduced_voice.v` STATE_DAMP_A/B:

```
damp_inv_q15 = 32767 - damp_mix_q15
STATE_DAMP_A: mult_coeff = $signed(damp_inv_q15)
              -> damp_part_a = disp_sample * (32767 - damp_mix) / 32768
STATE_DAMP_B: mult_coeff = $signed(damp_mix_q15)
              -> lp_state += lp_state * damp_mix / 32768
```

So `lp_state_new = disp * (1 - damp_mix/32768) + lp_state * (damp_mix/32768)`.

Higher damp_mix = more weight on lp_state (memory) = slower
high-frequency decay = LONGER sustain. Lower damp_mix =
more weight on current disp = faster high-frequency decay =
SHORTER sustain.

Direction: `!D0000` = shortest sustain (fastest decay),
`!D7FFF` = longest sustain (slowest decay). This is
inverted from the scope's initial prose but matches the
verifier's clarification #2.

## 6. Host helper status

The `scripts/phase6_m6_5_damp_sweep.py` host helper is
deferred until the LE gate is resolved. The RTL is
functionally complete and the TB covers the parser
behavior; the host helper adds no RTL risk.

## 7. ASCII check

All modified source files are ASCII-only (verified by
vlog clean compile; no non-ASCII in Verilog source).
The Quartus compile log was scrubbed from UTF-16 BOM to
ASCII.

## 8. Recommendation

Submit this NO-GO report. Wait for orchestrator to raise
the LE cap to +150 (following M5/M6.3a precedent) or
request optimization. If cap is raised, the current RTL
is ready to commit as-is with the host helper added in a
follow-up.
