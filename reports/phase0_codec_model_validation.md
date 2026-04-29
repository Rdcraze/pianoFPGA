# Phase 0 Codec Model Validation

Date: 2026-04-21
Task: `task-7f9c0d09`

## Findings

No new findings were discovered in the stronger WM8978 simulation model / Phase 0 harness within this task scope.

## Verified

1. The updated testbench is model-driven rather than state-window-driven.
   - `rtl/top/wm8978_i2c_model.v` detects start/stop from `SDA` edges while `SCL` is high (`lines 96-113`, `115-135`), shifts bytes on `posedge i2c_scl` (`137-152`), and drives ACK/NACK on `negedge i2c_scl` (`154-218`).
   - `rtl/top/piano_phase0_top_tb.v` now instantiates that bus model directly (`72-87`) instead of forcing ACK from DUT-internal state, and the negative-path wrapper uses the same model with `NACK_ENABLE=1` (`164-168`).

2. The success path completes under the stronger model and exercises the intended write sequence.
   - The happy-path testbench requires all of the following before it prints `TB_PASS`: init succeeds, the bring-up agent reaches the CPU-write path, `write_count == 17`, `captured_words[0] == 16'h0000`, `captured_words[15] == 16'h699E`, `captured_words[16] == 16'h6B9E`, and the DAC output toggles after init (`rtl/top/piano_phase0_top_tb.v:115-136`).
   - ModelSim result:

```text
TB_PASS fabric_status=80190758 soc_state=18 codec_write_exercised=1 write_count=17 dac_toggle_count=8911
```

3. The negative path is now targeted and deterministic under the same model.
   - `rtl/top/wm8978_i2c_model.v:174-184` injects a NACK when `NACK_ENABLE != 0` and the transfer high byte matches `NACK_CFG_HIGH_BYTE`.
   - `piano_phase0_top_nack_tb` sets `NACK_CFG_HIGH_BYTE` to `8'h00`, which forces a NACK on the selected Phase 0 write pattern through the model instead of by globally suppressing ACK.
   - ModelSim result:

```text
TB_NACK_PASS fabric_status=60190728 soc_state=18 nack_count=1 stop_count=1
```

4. The current tree also preserves the fixes validated in the earlier verifier pass.
   - `rtl/peripherals/wm8978_i2c_ctrl.v:190-195` now samples ACK while `SCL` is high.
   - `rtl/top/piano_phase0_top.v:73-78` now packs `fabric_status` explicitly from an `8`-bit `codec_status`.
   - `fw/phase0/phase0_hw.h:36-38` now labels waveform selector `2` as `PHASE0_CONTROL_WAVE_ENV`, matching the implemented envelope-only behavior.

## Commands

```powershell
vlib sim_codec_model/work
vlog -work sim_codec_model/work rtl/control/phase0_control_regs.v rtl/control/phase0_soc_stub.v rtl/audio/phase0_audio_path.v rtl/audio/phase0_sample_gen.v rtl/peripherals/phase0_reset_sync.v rtl/peripherals/uart_debug_stub.v rtl/peripherals/uart_tx.v rtl/peripherals/wm8978_boot_seq.v rtl/peripherals/wm8978_codec_stub.v rtl/peripherals/wm8978_dac_tx.v rtl/peripherals/wm8978_i2c_ctrl.v rtl/top/wm8978_i2c_model.v rtl/top/piano_phase0_top.v rtl/top/piano_phase0_top_tb.v
vsim -c -lib sim_codec_model/work piano_phase0_top_tb -do "run -all; quit -f"
vsim -c -lib sim_codec_model/work piano_phase0_top_nack_tb -do "run -all; quit -f"
```

Compile result:

```text
Errors: 0, Warnings: 0
```

## Residual Gaps

- This is still a bounded write-side digital model, not a full WM8978 behavioral replacement.
- The model does not cover analog behavior, ADC paths, internal codec register side effects, or audio-fidelity validation.
- The model validates the current three-byte write transaction shape only; it does not cover read transactions, clock stretching, or broader I2C bus contention cases.
- The negative injection hook is keyed by transfer high-byte pattern, not by an exact transfer index/occurrence counter.
- The DAC-side check only proves non-stuck line activity after init; it does not prove sample correctness or audio-format compliance.

## Likely Next Owner

- `orchestrator` / `implementer` if broader codec modeling or additional failure modes need to be added.
