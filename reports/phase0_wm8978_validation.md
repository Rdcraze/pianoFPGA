# Phase 0 WM8978 Validation

Date: 2026-04-21

Scope:

- Validate the current Phase 0 RTL baseline after the revisions in `task-c4c69cf4`, `task-28eb953c`, `task-8ee45684`, and `task-d80ba15e`
- Re-check the original three suspected risk areas:
  - `sys_clk` to `i2c_clk` control CDC for CPU-triggered codec writes
  - lack of a NACK/error/timeout escape in the I2C controller
  - mismatch between exposed waveform controls and actual sample-generator behavior

Validation basis:

- Source inspection of the current RTL, firmware collateral, and implementation notes in this repository
- The verifier task history reports ModelSim happy-path and forced-NACK runs, but those tool runs were not independently rerun from this workspace

## Findings

1. Medium: the I2C controller still samples ACK while `SCL` is low, so the new ACK/NACK cleanup is deterministic in simulation but still not protocol-timed correctly.

Evidence:

- [rtl/peripherals/wm8978_i2c_ctrl.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_i2c_ctrl.v:190) samples `ack` when `cnt_i2c_clk == 2'd0`
- In the same ACK states, [rtl/peripherals/wm8978_i2c_ctrl.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_i2c_ctrl.v:236) drives `i2c_scl` high only for `cnt_i2c_clk == 2'd1` or `2'd2`

Impact:

- The controller now fails cleanly on X/Z/open-bus simulation states, which is better than wedging
- It still relies on the slave presenting ACK early enough during the low phase to be observed before the controller raises `SCL`
- The minimal ACKing harness in [rtl/top/piano_phase0_top_tb.v](/mnt/e/projects/piano-agents/rtl/top/piano_phase0_top_tb.v:65) drives ACK for the whole ACK state, so it does not validate correct ACK sampling timing

Recommended fix:

- Sample ACK/NACK during the `SCL` high window, not before it

2. Medium: the top-level STATUS upper byte still depends on truncation side effects instead of explicit packing.

Evidence:

- [rtl/peripherals/wm8978_codec_stub.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_codec_stub.v:190) builds only an 8-bit meaningful codec status payload and assigns it to a 16-bit `status_word`
- [rtl/top/piano_phase0_top.v](/mnt/e/projects/piano-agents/rtl/top/piano_phase0_top.v:73) concatenates `codec_status` with three more bytes, producing a 40-bit RHS assigned into a 32-bit `fabric_status`

Impact:

- The current layout works only because `codec_status[15:8]` are zero, so truncating the top 8 bits happens to land `codec_status[7:0]` in `STATUS[31:24]`
- The contract is fragile: any future non-zero use of `codec_status[15:8]`, or a width change in the top-level packing, silently breaks the documented STATUS map

Recommended fix:

- Pack `STATUS[31:24]` explicitly from `codec_status[7:0]`, or narrow the codec-side status bus to the width that is actually used

3. Low: waveform selector `2` is still named as a ramp in firmware collateral, but the RTL implementation is an envelope-only pulse/impulse-style waveform.

Evidence:

- [fw/phase0/phase0_hw.h](/mnt/e/projects/piano-agents/fw/phase0/phase0_hw.h:36) exports selector `2` as `PHASE0_CONTROL_WAVE_RAMP`
- [rtl/audio/phase0_sample_gen.v](/mnt/e/projects/piano-agents/rtl/audio/phase0_sample_gen.v:69) drives `wave_sel == 2'b10` as `env_signed`, not a ramp
- [docs/phase0_impl_notes.md](/mnt/e/projects/piano-agents/docs/phase0_impl_notes.md:33) already describes the non-saw alternatives as "square and impulse-style paths"

Impact:

- Current `phase0_main.c` does not use selector `2`, so this is not a live runtime blocker for the present bring-up flow
- The mismatch can still mislead later firmware or tests that treat selector `2` as a ramp waveform

Recommended fix:

- Rename selector `2` in firmware/docs to something like `WAVE_ENV` or `WAVE_IMPULSE`, or change the RTL so the selector actually produces a ramp

## Assessment Of The Original Risk Areas

### 1. CPU Codec-Write CDC

No remaining blocking finding on the original pulse-crossing CDC concern.

Evidence:

- [rtl/peripherals/wm8978_codec_stub.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_codec_stub.v:89) now holds each CPU request in the `sys_clk` domain and transfers it with a toggle handshake into `i2c_clk`
- [rtl/peripherals/wm8978_codec_stub.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_codec_stub.v:97) keeps an explicit outstanding/completion tracker so bit `24` can behave as a real completion fence
- [rtl/control/phase0_soc_stub.v](/mnt/e/projects/piano-agents/rtl/control/phase0_soc_stub.v:291) now waits for busy-high and then busy-low rather than assuming immediate completion after request handoff

Assessment:

- The old one-cycle pulse hazard is addressed
- The remaining STATUS issue is top-level packing fragility, not a reappearance of the original CDC bug

### 2. NACK / Error / Timeout Escape

Partially addressed, with one remaining protocol-timing issue.

Evidence:

- [rtl/peripherals/wm8978_i2c_ctrl.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_i2c_ctrl.v:194) now treats anything other than a driven-low ACK as a deterministic NACK, which prevents X/Z-driven FSM poisoning
- [rtl/peripherals/wm8978_i2c_ctrl.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_i2c_ctrl.v:335) still exposes explicit `i2c_error`, `i2c_nack_error`, and `i2c_timeout_error`
- [rtl/peripherals/wm8978_boot_seq.v](/mnt/e/projects/piano-agents/rtl/peripherals/wm8978_boot_seq.v:70) clears `cfg_busy` on `cfg_end`, latches init failure/error/timeout outcomes, and no longer wedges forever on failure

Assessment:

- The previous “hang forever on missing or NACKing codec” mode is addressed
- The ACK sample point is still not aligned with the `SCL` high phase, so the controller is cleaner but not yet fully robust

### 3. Waveform Contract Coherence

Still not fully clean.

Evidence:

- [rtl/audio/phase0_sample_gen.v](/mnt/e/projects/piano-agents/rtl/audio/phase0_sample_gen.v:66) now applies the same gain/decay envelope handling to the sawtooth path, which resolves the original envelope-behavior mismatch
- The remaining selector-name mismatch for waveform `2` is documented above as a surviving low-severity finding

## Testing Gaps

- Independent `vlog` / `vsim` rerun was not performed from this workspace
- [rtl/top/piano_phase0_top_tb.v](/mnt/e/projects/piano-agents/rtl/top/piano_phase0_top_tb.v:65) is a minimal ACKing harness, not a protocol-accurate WM8978 model

## Conclusion

The current Phase 0 tree is materially better than the earlier baseline: the original CDC hazard and permanent I2C-wedge failure mode are addressed, and the bring-up path is now coherent enough to exercise codec init plus CPU-owned codec writes. Three validation findings remain:

- ACK is still sampled during the low portion of the I2C clock
- the STATUS upper byte still depends on truncation side effects instead of explicit packing
- waveform selector `2` is still mislabeled as a ramp in firmware collateral
