# Phase 4 M5 sample_gen Build-Time Gate Implementation Report

Date: 2026-05-23
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-42065b54`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD before: `81105ab`

## TL;DR

**NO-GO.** The Phase 4 M5 build-time gate around `phase0_sample_gen` was
implemented in a single file (`rtl/audio/phase0_audio_path.v`), Quartus
13.0.1 full-compiled, and the result was **+43 LE recovered (9,949 vs
9,992)**. The task gate requires at least **+50 LE recovery** to commit
the RTL change; **43 < 50**, so per the M5 stop rule the RTL change was
reverted via `git checkout`. This report is committed report-only as
NO-GO. The RTL on disk now matches the accepted M3/M4 baseline byte for
byte.

| Gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| LE recovery | >= 50 LE | 43 LE | **NO-GO** |
| Setup slack >= +2.0 ns | yes | +2.620 ns | PASS |
| Hold slack | clean | +0.410 ns | PASS |
| All TNS = 0 | yes | yes | PASS |
| ROM = 931 | yes | 931 | PASS |
| M9K | <= 16 | 16 (unchanged) | PASS |
| DSP9 | <= 28 | 26 (-2, expected) | PASS |
| PLL | 1 | 1 (unchanged) | PASS |
| 4 voices preserved | yes | yes | PASS |
| Register-map / firmware unchanged | yes | yes | PASS |
| ASCII-only on touched files | yes | yes | PASS |
| Quartus errors | 0 | 0 | PASS |
| Quartus warnings | <= baseline+5 (cosmetic) | 21 vs 16 | PASS (cosmetic only) |

## Experiment Design

The gate followed the M4 recommendation exactly. In `rtl/audio/phase0_audio_path.v`:

```verilog
// Phase 4 M5: sample_gen is gated out by default to reclaim ~150 LE.
localparam ENABLE_SAMPLE_GEN = 1'b0;

generate
    if (ENABLE_SAMPLE_GEN) begin : gen_sample_gen_on
        phase0_sample_gen phase0_sample_gen_inst (
            ...
        );
        assign use_sample_gen = audio_enable && tone_enable &&
                                !voice_enable && !voice1_enable && !voice2_enable && !voice3_enable;
        assign tx_valid  = use_sample_gen ? sample_gen_valid : sample_valid_any;
        assign tx_sample = use_sample_gen ? sample_gen_data  : body_filter_out;
    end else begin : gen_sample_gen_off
        wire _unused_sample_gen_inputs;
        assign _unused_sample_gen_inputs = |{1'b0, trigger_strobe, wave_sel,
                                             phase_step, gain, decay_step};
        assign sample_gen_data   = 16'sd0;
        assign sample_gen_valid  = 1'b0;
        assign sample_gen_active = 1'b0;
        assign use_sample_gen    = 1'b0;
        assign tx_valid  = sample_valid_any;
        assign tx_sample = body_filter_out;
    end
endgenerate
```

- Module ports `wave_sel`, `phase_step`, `gain`, `decay_step` left unchanged.
- `rtl/audio/phase0_sample_gen.v` left in source tree.
- `rtl/control/phase0_control_regs.v` untouched.
- `fw/phase0/*` untouched.
- All four physical voice instances (`phase1_reduced_voice_inst`,
  `phase1_reduced_voice1_inst`, `phase1_reduced_voice2_inst`,
  `phase1_reduced_voice3_inst`) untouched.
- Mux semantics in the `1` branch are bit-identical to the pre-gate
  source so the diagnostic mode is recoverable by parameter flip and
  Quartus rebuild.

The `_unused_sample_gen_inputs` reduction sinks the (otherwise unused)
diagnostic-only inputs into a single unloaded wire. Quartus DCE drops
the OR tree because it has no fanout, so this construct does not cost
LEs. It is purely a cleanup hook to keep the unused-input warnings
accurate.

## Quartus Result

Full Quartus 13.0.1 SP1 compile:

| Metric | Baseline `81105ab` | After M5 gate | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 9,992 / 10,320 | **9,949 / 10,320** | **-43** |
| Combinational functions | 9,417 | 9,257 | -160 |
| Dedicated logic registers | 4,233 | 4,175 | -58 |
| Memory bits | 86,016 | 86,016 | 0 |
| M9K blocks | 16 | 16 | 0 |
| Embedded multiplier 9-bit | 28 / 46 | 26 / 46 | -2 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow-85C setup `sys_clk_50m` | +2.914 ns | +2.620 ns | -0.294 ns |
| Slow-85C hold `sys_clk_50m` | +0.405 ns | +0.410 ns | +0.005 ns |
| Slow-0C setup `sys_clk_50m` | +3.832 ns | +3.835 ns | +0.003 ns |
| Slow-85C setup `i2c_clk` | +17.573 ns | +16.979 ns | -0.594 ns |
| Slow-85C setup `audio_bclk` | +316.385 ns | +314.061 ns | -2.324 ns |
| Slow-85C TNS (all clocks) | 0 | 0 | 0 |
| Quartus errors | 0 | 0 | 0 |
| Quartus warnings | 16 | 21 | +5 cosmetic |

Compile timestamp: `Sat May 23 22:18:21 2026` ("Successful").
Compile log: `.kiro/quartus_m5.log` (local-only, multi-megabyte stdout).

### LE delta breakdown

| Component eliminated when ENABLE_SAMPLE_GEN = 0 | Approx LE saved |
| --- | ---: |
| `phase0_sample_gen` register state (`phase_accum[23:0]`, `env_level[15:0]`, `sample_data[15:0]`, `sample_valid`, `active`) | ~58 (matches register delta) |
| `phase0_sample_gen` combinational arithmetic (square/saw/decay env logic, $signed multiplier feeding 9-bit DSP) | already absorbed into the 2 DSP9 elements (-2 DSP9) plus a small comb residue |
| `use_sample_gen` and downstream mux (~16-bit 2-to-1 plus the AND tree on four voice enables) | small residue |
| Combinational rebalancing across the rest of `phase0_audio_path` after the mux removal | net -160 comb LCs (combination of true elimination and packing improvements) |

Net LE = 9,992 - 43 = 9,949. The actual on-chip delta is much smaller
than the M1 paper estimate (-150) and the M4 plan target (~-150). This
is the same toolchain-pack pattern observed in M2 and M3: Quartus
13.0.1 was already optimizing the unreached mux branch heavily even
when sample_gen was instantiated, so removing the instance yielded
less-than-expected savings.

### Why setup slack moved

Setup slack on `sys_clk_50m` dropped from +2.914 ns to +2.620 ns. Both
remain comfortably above the +2.0 ns hard floor, but the change is
worth noting: removing the sample_gen instance freed up routing and
placement decisions, and the fitter chose a different placement that
happens to land slightly worse on the critical path inside
`phase0_rv32i_core` (the same path that has been the dominant timing
driver since Phase 3 M1). This is a placement-noise effect, not a
fundamental timing regression.

### Cosmetic warning increase

The +5 new warnings are all "object assigned a value but never read"
on the deliberately-tied-off signals in the `gen_sample_gen_off`
branch:

```
phase0_audio_path.v(264): "sample_gen_data" assigned a value but never read
phase0_audio_path.v(265): "sample_gen_valid" assigned a value but never read
phase0_audio_path.v(266): "sample_gen_active" assigned a value but never read
phase0_audio_path.v(267): "use_sample_gen" assigned a value but never read
phase0_audio_path.v(306): "_unused_sample_gen_inputs" assigned a value but never read
```

These are cosmetic Verilog-style warnings with no synthesis or
behavior impact. The unused-input warning on `clkena`/`extclkena` and
RAM-inference warnings remain at their baseline counts.

## Verification

### Firmware build

```
PS> .\fw\phase0\build.ps1
Built build/phase0.elf, build/phase0.bin, and build/phase0.mem
```

ROM word count: **931** (unchanged). Firmware source was not modified.

### ModelSim

Not run for this experiment. Justification:

- The change has been **reverted**. The committed source set is
  byte-identical to the accepted M3/M4 baseline. Running TBs against
  a reverted source set adds no new evidence beyond what the accepted
  baseline already validated.
- For the experimental change itself, the gate's `1` branch is
  bit-identical to the pre-gate source (so production telemetry is
  bit-exact preserved), and the `0` branch is provably unreachable in
  production firmware by the static reachability proof below. ModelSim
  evidence would not affect the LE-gate verdict (43 LE < 50 LE),
  which is the actual NO-GO trigger.

### Static reachability proof (required by task)

Production firmware in `fw/phase0/phase0_main.c`:

- `PHASE0_VOICE_CONTROL_BASELINE = (PHASE0_VOICE_CONTROL_ENABLE_M)` and
  same for `VOICE1`, `VOICE2`. `phase0_write_voice_control(...)` and
  the `VOICE1`/`VOICE2`/`VOICE3` equivalents always OR `BASELINE` into
  the write data, so every per-voice control write asserts ENABLE.
- `phase0_program_defaults` issues `phase0_write_voice_control(CLIP_CLEAR_M)`
  for voices 0/1/2 and a direct MMIO write of
  `VOICE3_CONTROL = CLIP_CLEAR_M` (no enable bit) for voice 3. However,
  `VOICE3_CONTROL_ENABLE_M` is asserted unconditionally on every later
  voice-3 trigger and reset path, and the per-voice enable bits in
  `phase0_control_regs.v` only update on writes to the corresponding
  register (no auto-clear). The first voice-3 trigger sets enable;
  thereafter all four voice enables remain set for the rest of runtime.
- No firmware code path clears `VOICE_CONTROL_ENABLE_M` after that
  point; round-robin smoke and command-grammar handlers always re-write
  control with `BASELINE | pulse_bits`.
- Therefore `voice_enable && voice1_enable && voice2_enable && voice3_enable`
  is always true once boot reaches steady state, and
  `use_sample_gen = audio_enable && tone_enable && !voice_enable && !voice1_enable && !voice2_enable && !voice3_enable`
  is always 0 in the accepted runtime. The pre-gate mux therefore
  always selects the voice path; gating the sample_gen instance is
  bit-exact equivalent to live behavior.

This static argument is the reason the gate is behavior-preserving.
The fact that the gate also yielded only 43 LE recovery does not
change the reachability proof; it changes only whether the savings
clear the task gate.

### 4-voice integrity

Verified: all four physical voice instances remain in
`rtl/audio/phase0_audio_path.v` post-revert, byte-identical to the
accepted M3/M4 baseline. Verified by `git diff` showing zero changes
on disk.

### ASCII

`reports/phase4_m5_sample_gen_gate_impl.md` is ASCII-only by
construction (verified via `grep -P '[^\x00-\x7F]'`).

### Hardware UART/audio smoke

Not run. Per task description, hardware smoke is optional for
implementer handoff and the verifier will run acceptance if
implementation passes. This implementation is NO-GO so no SOF was
shipped to commit and no hardware run is meaningful.

## What's NOT in this commit

- No RTL changes. The local edit was Quartus-validated to fall short
  of the LE gate and was reverted via `git checkout` before any source
  commit.
- No firmware changes.
- No SDC, QSF, pin, PLL, host-tool, or build-script changes.
- No register-map or telemetry-tag changes.
- No removal of `phase0_sample_gen.v` (it remains in the source tree).
- No changes to `.kiro/`, `reports/phase3_m3b_*`, or
  `reports/phase3_m[56]_hardware_uart.txt`.

## Honest Assessment

The M4 plan estimated ~150 LE recovery from gating sample_gen out.
Direct LE attribution from the M1 inventory gave the same number
(`phase0_sample_gen` direct LE = 150). Quartus 13.0.1 actually freed
only 43 LE when the instance is removed. This is the third instance
in Phase 4 (after M2 +146 and M3 0) where source-level expectations
based on direct-LE attribution diverge from real fitter output:

| Phase 4 milestone | Paper estimate | Actual delta |
| --- | ---: | ---: |
| M2 control_regs array consolidation | -150 to -250 LE | **+146** (regression, reverted) |
| M3 readback-mux compaction | -25 to -100 LE | **0** (zero delta, reverted) |
| M5 sample_gen gate | -150 LE | **-43** (below gate, reverted) |

The unifying lesson is consistent with the M2 NO-GO write-up: in
this Quartus 13.0.1 toolchain on this codebase, the synthesizer is
already aggressively packing/sharing logic across module boundaries
that the M1 attribution treats as separate. Removing or restructuring
a "150-LE module" does not free 150 LE because much of that 150 is
shared placement/packing benefit with neighboring logic.

In structural terms, the 43 LE recovered is consistent with what the
sample_gen instance contributes that **cannot** be shared: its
register state (~58 registers, matching the -58 register delta
exactly) and the dedicated 9-bit multiplier (-2 DSP9 = the saw_scaled
multiplier). The combinational logic was already mostly absorbed into
shared placement with the rest of the audio path.

## What This Means for Phase 4 Headroom

After M2 (-0), M3 (-0), M5 (-43 below the +50 gate), the only remaining
M4-listed reclamation candidates are:

- **Audio-path mix-tree experiment (B1)**: M4 estimated 30-60 LE on
  paper. Given the M5 result that real recovery is roughly 30% of paper
  estimates in this codebase, the realistic expectation is 0-20 LE.
  Below any reasonable task gate. **Not worth running.**
- **Voice TDM**: still blocked by the architecture guard.
- **SDRAM**: still has no consumer.

The practical conclusion is **Option I from the M4 report (accept the
328-LE margin and only pursue features that fit)**. The reclamation
program in this Quartus 13.0.1 + this RTL set is exhausted within the
constraints of the architecture guard. Any further headroom would
require the orchestrator to authorize a structural change (voice TDM,
or accepting sample_gen elision under a lower LE-gate threshold than
the current +50, or a Phase 4 architectural rewrite).

If the orchestrator wants to revisit the M5 gate with a lower gate
threshold (for example +25 LE), the gate change is small and the
Quartus result above is reusable; only the report needs an addendum.
That decision is for the orchestrator, not this implementer task.

## Recommendation

1. **Accept this report as NO-GO.** The RTL has been reverted and
   committed to no source changes; baseline is preserved.
2. **Hold further audio-path mix-tree experiments** (M4 Option III)
   unless the orchestrator authorizes a lower LE gate. The expected
   value is below any reasonable threshold.
3. **Move to M4 Option I (accept the 328-LE margin)** as the working
   posture for Phase 4 unless and until a structural reclamation move
   (voice TDM authorization) or a specific large-feature consumer
   (SDRAM) is queued.
4. **If the M5 gate is reconsidered with a +25 LE threshold**, the
   change can be re-applied verbatim; Quartus is expected to produce
   the same -43 LE result, which clears a +25 gate. That is an
   orchestrator decision, not an implementer one.

## Committed Result

This task commits **report only**. No RTL/firmware/SDC/QSF/PLL/script/
host-tool/generated-output changes are committed.

Single commit contents:
- add `reports/phase4_m5_sample_gen_gate_impl.md`

Repo state after commit: tree net-identical to `81105ab` for all
source files; only this report is added.
