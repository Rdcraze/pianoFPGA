# Phase 0 Implementation Notes

Status: integrated RV32I board-I/O-modeled Phase 0 baseline plus Phase 1 two-voice feasibility slice and Phase 1C-A ROM/RAM right-sizing cleanup

Update for `task-9c9f5bd4`:

- this update is memory-headroom cleanup only; it does not change the two-voice audio model, register/MMIO behavior, UART frame contract, clocking, or CPU-out-of-sample-loop split
- the firmware ROM and RAM envelopes are right-sized from `4096 x 32` each to `1024 x 32` each:
  - ROM remains based at `0x0000_0000` and is now `4 KiB`
  - RAM remains based at `0x0001_0000` and is now `4 KiB`
  - control registers remain at `0x4000_0000`
  - UART MMIO remains at `0x4000_1000`
- `fw/phase0/build.ps1` now emits `DEPTH = 1024` MIF files and fails the build if the firmware image exceeds the configured ROM depth
- the current firmware image is still small relative to the right-sized envelope: the linked `.text` is under `1 KiB`, `.data` and `.bss` are empty, and the remaining RAM is reserved for stack/control-flow margin
- validation for this right-sized build passed firmware/linker/MIF consistency checks, ModelSim reduced-voice/happy/NACK tests, Quartus full compile, TimeQuest, USB-Blaster programming, COM5 UART capture, and external Realtek audio capture
- post-fit resources now use `74,752` memory bits and `10` M9Ks, down from the accepted two-voice baseline's `271,360` memory bits and `34` M9Ks; each reduced voice still maps to `1` M9K and `2` DSP9 elements
- this update intentionally does not add a third voice, SDRAM, scheduler, body-pipe rewrite, richer physics, sample playback, UI, larger CPU, clock/PLL change, or broad cleanup

Update for `task-e4ded029`:

- this update is the authorized narrow two-voice feasibility slice from `reports/phase1_timing_margin_acceptance_decision.md`; it does not add richer physics, SDRAM, sample playback, UI, exact-48-kHz clocking, a larger CPU, or a new bus fabric
- existing registers through `0x50` remain compatible:
  - `0x20..0x3C` still control the original reduced voice parameters
  - `0x40..0x50` still expose the original sample, trigger, active, valid, and clear-counter diagnostics for voice0
- `rtl/audio/phase0_audio_path.v` now instantiates a second `phase1_reduced_voice` as `phase1_reduced_voice1_inst`:
  - both voices use the same accepted reduced model, coefficients, sample-rate contract, and synchronous M9K delay-line implementation
  - firmware triggers voice0 and voice1 as two simultaneous hardware-owned note events after codec bring-up
  - the CPU still only writes controls/status/UART and is not in the per-sample synthesis loop
- the audio path mixes voice0 and voice1 with signed saturating addition before the existing mono-to-dual-mono codec path:
  - `VOICE_STATUS` at `0x24` remains voice0 status
  - `VOICE1_STATUS` at `0x58` reports voice1 status with the same bit layout
  - `VOICE_MIX_STATUS` at `0x68` reports mix peak in bits `31:16`, voice1 enabled at bit `4`, mix-valid at bit `3`, mix clip at bit `2`, any excite busy at bit `1`, and any active at bit `0`
  - `VOICE_MIX_CLIP_COUNT` at `0x6C` increments on output saturation events
- new post-`0x50` two-voice registers:
  - `0x54 VOICE1_CONTROL`: bit `0` enable, bit `1` write-one trigger, bit `2` write-one reset, bit `8` write-one clip clear
  - `0x58 VOICE1_STATUS`
  - `0x5C VOICE1_TRIGGER_COUNT`
  - `0x60 VOICE1_ACTIVE_COUNT`
  - `0x64 VOICE1_VALID_COUNT`
  - `0x68 VOICE_MIX_STATUS`
  - `0x6C VOICE_MIX_CLIP_COUNT`
- UART keeps the accepted `I/S/R/V/F/T/A/W` frames and appends two-voice diagnostics:
  - `Y=` reads `VOICE1_STATUS`
  - `U=` reads `VOICE1_TRIGGER_COUNT`
  - `B=` reads `VOICE1_ACTIVE_COUNT`
  - `C=` reads `VOICE1_VALID_COUNT`
  - `M=` reads `VOICE_MIX_STATUS`
  - `K=` reads `VOICE_MIX_CLIP_COUNT`
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded
  - full ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -c work.phase1_reduced_voice_tb -do "run -all; quit -f"` passed with the unchanged single-voice signature `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019057f soc_status=037f write_count=18 dac_toggle_count=1304 voice_peak_level=2082 voice1_peak_level=2082 mix_peak_level=4164 voice_sample_count=517 voice_trigger_count=1 voice1_trigger_count=1 voice_active_count=358 voice1_active_count=358 voice_valid_count=516 voice1_valid_count=516 mix_clip_count=0 uart_capture_count=111`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded with `0` errors and `12` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `7366` logic elements, `3580` registers, `271360` memory bits, `34` M9Ks, `4` DSP9s, and `1` PLL
- TimeQuest remains fully constrained for setup and hold:
  - slow-`85C` `sys_clk_50m` setup slack is `3.957 ns`, above the `+1.0 ns` review trigger and above the timing-margin baseline `3.170 ns`
  - slow-`85C` `sys_clk_50m` Fmax is `62.33 MHz`
  - slow-`85C` hold slack remains positive at `0.432 ns` on `sys_clk_50m`, `0.452 ns` on `audio_bclk`, and `0.453 ns` on `i2c_clk`
- mapping/resource constraints remain acceptable for this experiment:
  - each reduced voice retains synchronous M9K-backed `128 x 18` delay-line RAMs
  - each reduced voice retains one signed embedded 18-bit DSP multiplier, for `4` DSP9 elements total
  - total LE use remains below the `8000 / 10320` experiment limit
- hardware smoke was unavailable in this session:
  - `quartus_pgm --list` reported `No JTAG hardware available`
  - Windows reported no serial COM ports
  - the external Realtek microphone path was visible to ffmpeg, but without JTAG/UART the board could not be programmed or observed

Update for `task-e3bb63b1`:

- this update is margin hardening only; it does not change the Phase 1 sound engine, voice parameters, sample-rate contract, UART `I/S/R/V/F/T/A/W` observability, or register compatibility through `0x50`
- `rtl/control/phase0_rv32i_core.v` now includes a `STATE_DECODE` operand-capture stage:
  - `rs1_value_q` and `rs2_value_q` latch the register-file read operands before `STATE_EXEC`
  - the previous worst path from `instr_reg[*]` through the register-file read mux into `wb_writeback_data_q[*]` no longer carries the full decode plus ALU/writeback delay in one cycle
  - this adds one control-plane decode cycle per instruction, but the CPU remains outside the per-sample audio loop and firmware still only handles codec/control/status/UART work
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded
  - ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -c work.phase1_reduced_voice_tb -do "run -all; quit -f"` passed with the unchanged signature `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1236 voice_peak_level=2082 voice_sample_count=517 voice_trigger_count=1 voice_active_count=358 voice_valid_count=516 uart_capture_count=96`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded with `0` errors and `10` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `5683` logic elements, `2588` registers, `266752` memory bits, `1` PLL, and `2` DSP9s
- TimeQuest remains fully constrained for setup and hold:
  - slow-`85C` `sys_clk_50m` setup slack improved from the observability baseline `0.889 ns` to `3.170 ns`
  - slow-`85C` `sys_clk_50m` Fmax improved from `52.33 MHz` to `59.42 MHz`
  - slow-`85C` hold slack remains positive at `0.432 ns` on `sys_clk_50m`, `0.453 ns` on `audio_bclk`, and `0.453 ns` on `i2c_clk`
- mapping/resource constraints remain intact:
  - the Phase 1 delay line remains two simple-dual-port M9K RAMs
  - the voice multiplier remains one signed embedded 18-bit DSP multiplier (`2` DSP9 elements)
  - memory/M9K/DSP/PLL counts did not increase
- hardware smoke on this host:
  - `quartus_pgm` configured `USB-Blaster [USB-0]` successfully with SOF checksum `0x0047FF19`
  - COM4 at `115200` baud emitted recurring `R/V/F/T/A/W` frames with `T=00000001`, advancing `F/W`, and late `V=08220010`
  - external Realtek microphone capture produced a decaying non-clipped stereo tone; analysis reported mono `f0=435.955 Hz`, 0 clipped samples on both channels, early crest factor `2.948`, and decay of about `-12.42 dB` by `0.50 s`

Update for `task-7c2e4ebf`:

- Phase 1 is still frozen as the single-voice reference baseline; this update adds only runtime observability:
  - the voice sound engine and `rtl/audio/phase1_reduced_voice.v` are unchanged
  - the `128 x 18` delay line remains synchronous M9K-backed
  - the sample-rate, codec, board-I/O timing model, and existing voice register offsets through `0x3C` are unchanged
- `rtl/audio/phase0_audio_path.v` now maintains four lightweight 32-bit diagnostic counters:
  - `VOICE_SAMPLE_COUNT` at `0x40`: increments on every `sample_tick`
  - `VOICE_TRIGGER_COUNT` at `0x44`: increments on an accepted voice trigger
  - `VOICE_ACTIVE_COUNT` at `0x48`: increments when the voice emits a sample while active
  - `VOICE_VALID_COUNT` at `0x4C`: increments on every voice `sample_valid`
  - `VOICE_DIAG_CONTROL` at `0x50`: bit `0` write-one clears those counters
- `fw/phase0/phase0_main.c` now clears the diagnostic counters before the default trigger and appends UART diagnostic frames after each `R=` status frame:
  - `V=` reads `VOICE_STATUS`
  - `F=` reads `VOICE_SAMPLE_COUNT`
  - `T=` reads `VOICE_TRIGGER_COUNT`
  - `A=` reads `VOICE_ACTIVE_COUNT`
  - `W=` reads `VOICE_VALID_COUNT`
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded
  - `vsim -c work.phase1_reduced_voice_tb -do "run -all; quit -f"` passed with `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`
  - ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1243 voice_peak_level=2082 voice_sample_count=517 voice_trigger_count=1 voice_active_count=359 voice_valid_count=517 uart_capture_count=96`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded with `0` errors and `10` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `6515` logic elements, `2523` registers, `266752` memory bits, `1` PLL, and `2` DSP9s
- TimeQuest remains fully constrained for setup and hold:
  - slow-`85C` setup slack is `0.889 ns` on `sys_clk_50m`, `17.615 ns` on `i2c_clk`, and `314.022 ns` on `audio_bclk`, all with `0.000` TNS
  - slow-`85C` hold slack is `0.432 ns` on `sys_clk_50m`, `0.453 ns` on `i2c_clk`, and `0.452 ns` on `audio_bclk`
- hardware UART smoke on this host:
  - `quartus_pgm` configured `USB-Blaster [USB-0]` successfully with SOF checksum `0x004DD5CF`
  - COM4 at `115200` baud emitted recurring frames such as `R=8018077F`, `V=08220010`, `F=00089BD4`, `T=00000001`, `A=000172B3`, and `W=00089C66`
  - an automated external audio capture was not available in this session, so hardware audio was not remeasured here

Update for `task-9fb09496`:

- the hardware-owned sample source is now a single fixed-pitch reduced piano/string voice rather than the old continuous Phase 0 oscillator:
  - `rtl/audio/phase1_reduced_voice.v` implements a `128` entry synchronous M9K-backed Q1.17 delay line, first-order allpass, damping lowpass, loop gain, 16-sample half-sine hammer burst, optional tiny body coloration, saturation, `clip_seen`, and peak metering
  - the CPU remains out of the per-sample loop; firmware only programs parameters and writes a one-shot `VOICE_CONTROL.trigger`
  - the codec clocking contract stays unchanged at the current nominal `46.875 kHz` frame rate (`12.000 MHz / 256` direct-MCLK baseline)
- `rtl/control/phase0_control_regs.v` preserves the Phase 0 register map through `0x18` and adds Phase 1 voice registers at `0x20` through `0x3C`
- `fw/phase0/phase0_main.c` now writes the Phase 1 voice defaults, clears the voice clip flag, and triggers the voice after codec init and the two CPU-owned WM8978 writes
- `rtl/top/piano_phase0_top_tb.v` keeps the existing happy-path and targeted-NACK checks and now also requires the happy path to produce a nonzero voice peak with `clip_seen` clear
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded and regenerated the firmware plus `phase0_fw.mif`
  - ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -c work.phase1_reduced_voice_tb -do "run -all; quit -f"` passed with `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1243 voice_peak_level=2082 uart_capture_count=36`
  - `vsim -voptargs=+acc -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6018073f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded with `0` errors and `10` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `6308` logic elements, `2394` registers, `266752` memory bits, `1` PLL, and `2` DSP9s
- TimeQuest remains fully constrained for setup and hold:
  - slow-`85C` setup slack is `1.234 ns` on `sys_clk_50m`, `18.044 ns` on `i2c_clk`, and `315.774 ns` on `audio_bclk`, all with `0.000` TNS
  - slow-`85C` hold slack is `0.429 ns` on `sys_clk_50m`, `0.452 ns` on `i2c_clk`, and `0.451 ns` on `audio_bclk`
- remaining warnings are understood:
  - the intentionally unused playback-only `audio_adcdat` input
  - existing PLL forwarded-clock/jitter caveats for `audio_mclk`
  - Quartus RAM-inference pass-through warnings for the small voice delay RAMs, which still map to M9K and keep the final fit under the Phase 1 budget

Update for `task-241de457`:

- `quartus/phase0/piano_phase0_top.sdc` now models the defensible Phase 0 board-facing timing at the WM8978 audio boundary instead of leaving all off-chip timing unmodeled:
  - `audio_lrc` and `audio_adcdat` are constrained as codec-driven inputs with `10 ns` max delay from `audio_bclk` falling edge and an explicit `0 ns` min-arrival assumption because local collateral does not provide a min propagation delay or board skew number
  - `audio_dacdat` is constrained against the codec requirement of `10 ns` setup and `10 ns` hold around `audio_bclk` rising edge
  - `audio_bclk` remains the explicit external `1.500 MHz` codec-master timing island for the current direct-`MCLK` Phase 0 contract
- the remaining off-chip interfaces are no longer accidental gaps; they are explicit exclusions with a stated reason:
  - `audio_mclk` is a forwarded codec clock output, not a data pin with a defensible output-delay aperture from the local manuals
  - `i2c_scl` and `i2c_sda` remain an explicit open-drain 2-wire protocol exclusion because local collateral does not provide board-level bus capacitance or skew numbers for point-to-point setup/hold signoff
  - `uart1_rx` / `uart1_tx` remain explicit asynchronous serial exclusions
  - `sys_rst_n` remains an explicit asynchronous reset exclusion into `phase0_reset_sync`
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded and regenerated the firmware plus `phase0_fw.mif`
  - ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - `vsim -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded with `0` errors and `8` warnings, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `4796` logic elements, `1520` registers, `262144` memory bits, `1` PLL, and `2` DSP9s
- TimeQuest now reports the package fully constrained for setup and hold after those explicit constraints/exclusions:
  - slow-`85C` setup slack is `0.357 ns` on `sys_clk_50m`, `17.508 ns` on `i2c_clk`, and `316.385 ns` on `audio_bclk`, all with `0.000` TNS
  - slow-`85C` hold slack is `0.433 ns` on `sys_clk_50m`, `0.403 ns` on `i2c_clk`, and `0.453 ns` on `audio_bclk`
- the remaining signoff caveat is now narrow and explicit rather than generic:
  - source-synchronous WM8978 audio data timing is modeled
  - forwarded-clock, asynchronous-serial, asynchronous-reset, and open-drain I2C board interfaces are excluded on purpose because the local collateral does not provide a defensible point-to-point setup/hold model for them

Update for `task-f925ff80`:

- the integrated RV32I control plane now closes the internal `50 MHz` fabric timing target without changing the Phase 0 firmware-visible contract
- `rtl/control/phase0_rv32i_core.v` now uses an explicit staged writeback boundary for both load and non-load instructions:
  - ALU/branch/jump results are captured into `wb_*` registers in `STATE_EXEC`
  - load data is captured into the same `wb_*` registers in `STATE_LOAD`
  - the architectural register file is only written from `STATE_WRITEBACK`, so the old mixed execute/load tree no longer feeds the register-file write edge directly
- the asynchronous-reset register-file clear is now written explicitly instead of using a procedural loop variable, which removes the Quartus latch warning that briefly appeared during timing-closure work
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded and regenerated the firmware plus `phase0_fw.mif`
  - ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - `vsim -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `4809` logic elements, `1520` registers, `262144` memory bits, `1` PLL, and `2` DSP9s
- TimeQuest timing is now closed for the modeled internal clocks:
  - slow-`85C` setup slack is `1.120 ns` on `sys_clk_50m` with `0.000` TNS
  - `i2c_clk` and `audio_bclk` remain positive at `17.868 ns` and `328.252 ns`
  - the old `instr_reg[*] -> regs[*]` register-file writeback path is no longer the limiting edge; the new worst internal path is the staged writeback datapath into `wb_writeback_data_q[*]`
- the remaining implementation caveat at that handoff point was no longer RV32I core timing closure:
  - TimeQuest still reported the design not fully constrained because board I/O timing had not yet been modeled or explicitly excluded coherently
  - that board-I/O timing gap was later tightened by `task-241de457`
  - the remaining Quartus warnings were already the known playback-only / PLL-output caveats rather than live functional or timing failures

Update for `task-9d00cc2f`:

- `rtl/control/phase0_soc_stub.v` has been replaced in the live top-level path by a real minimal RV32I subsystem:
  - `rtl/control/phase0_rv32i_core.v`
  - `rtl/control/phase0_boot_rom.v`
  - `rtl/control/phase0_data_ram.v`
  - `rtl/control/phase0_rv32i_soc.v`
  - `rtl/peripherals/phase0_uart_mmio.v`
- `rtl/top/piano_phase0_top.v` now boots and executes `fw/phase0` instead of relying on the earlier deterministic stub agent, while preserving the documented ROM/RAM/MMIO map:
  - ROM at `0x0000_0000`
  - RAM at `0x0001_0000`
  - control block at `0x4000_0000`
  - polling UART aperture at `0x4000_1000`
- the firmware build flow now emits `phase0_fw.mif` alongside the earlier ELF/bin/disassembly artifacts and copies that MIF to both the repo root and `quartus/phase0/`, which is the current ROM-init contract for ModelSim and Quartus
- the current in-repo RV32I core is intentionally tiny and multi-cycle rather than throughput-oriented:
  - explicit fetch request/capture stages so the synchronous boot ROM is sampled correctly
  - explicit load stage so the synchronous data RAM can serve stack/data traffic reliably
  - explicit commit staging for non-load instructions to keep the firmware-visible behavior stable while shortening the longest register-file writeback path
- current validation on this host is concrete:
  - `powershell -ExecutionPolicy Bypass -File fw/phase0/build.ps1` succeeded and regenerated the firmware plus `phase0_fw.mif`
  - ModelSim `vlog` with Quartus simulation libraries passed with `0` errors and `0` warnings
  - `vsim -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - `vsim -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded, regenerated `quartus/phase0/output_files/piano_phase0_top.sof`, and fit the design with `4696` logic elements, `1520` registers, `262144` memory bits, `1` PLL, and `2` DSP9s
- at the `task-9d00cc2f` handoff point, the remaining implementation risk was timing closure rather than functional correctness:
  - TimeQuest then reported slow-`85C` setup slack of `-0.881 ns` on `sys_clk_50m`
  - `i2c_clk` and `audio_bclk` were already positive at `17.766 ns` and `328.040 ns`
  - that integrated RV32I timing gap was later closed by `task-f925ff80`, and the later board-I/O timing treatment was tightened by `task-241de457`

## Intent

This scaffold fixes the Phase 0 module boundaries before any real codec, clocking, or firmware work starts. It follows the locked project decisions:

- `50 MHz` board clock as the only Phase 0 fabric clock input
- `WM8978` as the first audio path
- `UART1` as the first debug path
- small soft-core control plane
- hardware-owned sample path
- no SDRAM, TFT, SD, camera, or external touchscreen in this phase

The top-level shell is deliberately small. It is meant to be timing-oriented and easy to replace incrementally, not to be feature-complete yet.

Update for `task-d43bbf83`:

- the codec-side stub now includes a deterministic Phase 0 baseline:
  - dedicated PLL-backed `audio_mclk` generation from the `50 MHz` board clock (`12.000 MHz`)
  - automatic WM8978 register initialization over I2C on power-up
  - CPU-triggerable follow-on WM8978 register writes through the existing control register path
  - a dedicated DAC serializer that keeps the sample stream in hardware rather than software
- the sample generator now auto-starts from control-register defaults, so the hardware path can emit a tone baseline without waiting for firmware
- this is still a bring-up baseline, not final audio-rate sign-off; the current direct-`MCLK` contract is explicit enough for Phase 0, but exact `48 kHz` remains a later step if the project chooses explicit codec-PLL programming or a different exact audio-clock plan

Update for `task-c4c69cf4`:

- CPU-triggered WM8978 writes now cross from the `sys_clk` register domain into the `i2c_clk` sequencer through a held-request handshake in `wm8978_codec_stub.v`, so firmware-visible codec writes are no longer dependent on catching a one-cycle pulse across domains
- the WM8978 I2C controller now exits cleanly on NACK and also exposes a transaction timeout path; those failures clear the sequencer busy state instead of wedging it forever
- startup failures are now latched explicitly, and the combined status word exposes whether init completed, failed, or saw an error/timeout
- the sawtooth path in `phase0_sample_gen.v` now obeys the same gain/decay envelope contract as the square and impulse-style paths, so firmware does not have to special-case waveform semantics

Update for `task-8ee45684`:

- `rtl/control/phase0_soc_stub.v` is no longer a dead placeholder; it now acts as a very small deterministic bring-up agent that writes a known control baseline, reads `IDENT`, waits for codec init completion or failure, exercises the CPU-owned WM8978 write path, starts the default tone deterministically once, and emits compact ASCII hex status frames on `UART1`
- `rtl/peripherals/uart_tx.v` now provides a real `115200`-baud transmit path from the `50 MHz` system clock, so the board can self-report bring-up status before full soft-core integration exists
- the top-level ownership split is intentionally unchanged: this is still not a general CPU, bus fabric, or firmware-executing subsystem, but the old dead-end between the documented control contract and the board-visible outputs is closed for early bring-up

Update for `task-d80ba15e`:

- the codec block now exports the full STATUS upper byte directly, so the documented/software-visible bit mapping is no longer vulnerable to truncation or shifting between `wm8978_codec_stub.v` and `piano_phase0_top.v`
- STATUS bit `24` is now a true completion fence for CPU-owned codec writes: it stays asserted from the sys-domain request through I2C-side activity and only drops after transaction completion is observed back in `sys_clk`
- STATUS bit `27` remains the narrower "request queued for handoff" indicator, which is intentionally different from bit `24`

Update for dynamic ModelSim debug on 2026-04-21:

- `wm8978_i2c_ctrl.v` now treats anything other than a driven-low ACK bit as a deterministic NACK during the ACK states, so an undriven or unknown `i2c_sda` simulation value can no longer poison the I2C FSM with `X` control flow and wedge the boot sequencer forever
- this means a bare top-level smoke sim with no external codec model now fails cleanly with `init_failed` and the expected codec-error bits instead of hanging in `cfg_busy`
- `rtl/top/piano_phase0_top_tb.v` now provides a tiny simulation harness that ACKs the WM8978 transactions, allowing ModelSim to verify the success path end-to-end: codec init completes, the deterministic bring-up agent performs the two CPU-owned codec writes, and the design reaches the steady runtime/reporting loop

Update for `task-93682477`:

- ACK/NACK sampling in `wm8978_i2c_ctrl.v` now occurs during the `SCL`-high subphase instead of the low subphase, while preserving the deterministic X/Z-to-NACK behavior used to keep open-bus simulation states from wedging the controller
- the codec-status path is now width-clean: `wm8978_codec_stub.v` exposes an `8`-bit codec status payload, and `piano_phase0_top.v` packs `STATUS[31:24]` explicitly instead of relying on `40`-bit-to-`32`-bit concat truncation side effects
- waveform selector `2` is now documented on the firmware side as an envelope-only pulse (`PHASE0_CONTROL_WAVE_ENV`) to match the implemented RTL behavior rather than calling it a ramp
- `rtl/top/piano_phase0_top_tb.v` now drives ACK only during the ACK-state `SCL`-high window, so the passing ModelSim harness validates the corrected ACK sample point instead of asserting ACK for the entire state
- `reports/phase0_wm8978_validation.md` remains a historical verifier memo; its selector-2 waveform-label finding was resolved later by `task-93682477`, so that specific documentation mismatch is no longer live in the current tree

Update for `task-b8196a99`:

- `rtl/top/wm8978_i2c_model.v` now provides a bounded simulation-only WM8978-like I2C slave for the Phase 0 write path: it ACKs with protocol-correct timing, recognizes the current three-byte write transaction shape, captures completed `16`-bit codec words, and can inject a targeted NACK for a selected high-byte pattern
- `rtl/top/piano_phase0_top_tb.v` now uses that model for the happy-path check instead of a blanket ACK window, and also exposes a second top-level wrapper (`piano_phase0_top_nack_tb`) that exercises a targeted NACK failure path through the same model
- the happy-path simulation now proves more than codec init completion alone: it requires the model to observe all `18` expected writes (`16` init writes plus `2` CPU-owned writes), checks the two CPU-owned follow-on words, and confirms the DAC serial output is not stuck after init by observing line toggles across the run
- this is still intentionally a bounded digital model, not a full WM8978 behavioral replacement: it does not model analog behavior, ADC capture, register side effects inside the codec, or deep audio-format validation beyond basic non-stuck DAC-side activity

Update for `task-4ad912d3`:

- `rtl/control/phase0_soc_stub.v` now treats UART transmission as a held request rather than a pulse: it loads one byte, keeps `tx_valid` asserted until `uart_tx.v` is actually ready to consume it, and advances `frame_index` only on that acceptance event
- `rtl/top/piano_phase0_top_tb.v` now includes a UART monitor that checks the exact `I=50303031` ident frame plus complete framed `S=` and `R=` records with `8` hex digits and `CRLF`, which is the right regression target for the hardware-proven byte-drop bug without hard-coding incidental live status words
- live hardware retest on `2026-04-22` confirmed the fix on `COM3`: the board now emits full framed records such as `I=50303031`, `S=8019030A`, `R=80190314`, and recurring `R=8019035A`; the earlier `R8105`/`I5333`/`S8100` truncation pattern only appeared in buffered pre-program traffic from the previously loaded broken image

Update for `task-09810cec`:

- the accidental `12.5 MHz` fabric-divider MCLK is gone; `rtl/peripherals/phase0_audio_mclk_pll.v` now generates an explicit `12.000 MHz` codec master clock from the board `50 MHz` source, and `wm8978_boot_seq.v` waits for PLL lock before issuing the WM8978 bring-up sequence
- the WM8978 init image now writes `R7 = 0` explicitly instead of inheriting the sample-rate register by omission, so the current Phase 0 rate contract is visible in RTL even though it still uses the direct-`MCLK` path
- the Phase 0 default tone contract now matches that interim direct-`MCLK` plan: `phase0_control_regs.v`, `phase0_soc_stub.v`, and `fw/phase0/phase0_main.c` all use `phase_step = 157482`, which yields approximately `440 Hz` at the current nominal `46.875 kHz` sample framing (`12.000 MHz / 256`)
- `rtl/top/piano_phase0_top_tb.v` and `quartus/phase0/piano_phase0_top.sdc` now model the same clocking story instead of the old accidental one:
  - happy-path simulation uses `audio_bclk = 1.500 MHz` and `audio_lrc = 46.875 kHz`
  - Quartus treats `audio_bclk` as a `1.500 MHz` external clock island and derives the new internal PLL clock automatically
- exact `48 kHz` is still deferred; if the project needs that instead of the current explicit interim contract, the next step is to program the codec PLL intentionally or adopt another exact audio-clock plan

Update for `task-e5e0096b`:

- verifier follow-up on real hardware showed the then-current shipped default was a short decaying burst that retriggered into an approximately `538.79 Hz` pattern, which matched the RTL but did not match the intended continuous baseline-tone contract
- `rtl/control/phase0_soc_stub.v` and `fw/phase0/phase0_main.c` now align with that intended contract: `DECAY_STEP` defaults to `0`, one deterministic trigger is still issued after codec init for a phase-clean start, and the runtime loop now only reports status instead of periodically retriggering the tone path
- the current shipped Phase 0 default is therefore a continuous square-wave baseline at the existing explicit direct-`MCLK` rate contract (`phase_step = 157482` at nominal `46.875 kHz`, approximately `440 Hz`) rather than an auto-decaying burst pattern
- post-fix validation is clean on the current host:
  - `fw/phase0/build.ps1` rebuilt the bare-metal image successfully
  - ModelSim `vlog` passed with `0` errors and `0` warnings
  - `vsim -c work.piano_phase0_top_tb -do "run 12 ms; quit -f"` passed with `TB_PASS fabric_status=80190758 soc_state=18 codec_write_exercised=1 write_count=18 dac_toggle_count=1668 uart_capture_count=36`
  - `vsim -c work.piano_phase0_top_nack_tb -do "run 12 ms; quit -f"` passed with `TB_NACK_PASS fabric_status=60190728 soc_state=18 nack_count=1 stop_count=1`
  - `quartus/phase0/build.ps1 -Stage compile` succeeded and regenerated `quartus/phase0/output_files/piano_phase0_top.sof`; latest slow-`85C` setup slack is `7.325 ns` on `sys_clk_50m`, `18.225 ns` on `i2c_clk`, and `328.130 ns` on `audio_bclk`

Update for Phase 4 M2 (`task-0692867c`, commit `5db0378`):

- `rtl/control/phase0_soc_stub.v` has been removed from the source tree. The deterministic bring-up agent it described was already superseded by the live RV32I subsystem in `task-9d00cc2f`; M2 deleted the dead file because it was no longer referenced by the QSF, top-level RTL, simulation testbenches, build scripts, or firmware. The current Phase 0 control plane is the RV32I subsystem (`phase0_rv32i_core.v`, `phase0_boot_rom.v`, `phase0_data_ram.v`, `phase0_rv32i_soc.v`, plus `phase0_uart_mmio.v`) executing `fw/phase0` against the documented ROM/RAM/MMIO map.
- All earlier update sections in this document that mention `rtl/control/phase0_soc_stub.v` describe historical Phase 0 milestones (`task-8ee45684`, `task-4ad912d3`, `task-09810cec`, `task-e5e0096b`, etc.). They are kept as accurate records of how the design got here, but the file itself no longer exists in the live tree, and any behavior they attribute to the stub is now provided by the RV32I subsystem and firmware.
- Source/script references repaired for this rename: `fw/phase0/phase0_hw.h` no longer claims the RTL "still uses" the stub. Verifier-side report `reports/phase4_m2_reclamation_validation.md` is preserved as historical evidence; `reports/phase4_m2_stale_reference_repair.md` records this follow-up cleanup explicitly.

## Update for Phase 5 M0 (2026-05-24)

Architecture pivot: the RISC-V SoC + firmware C + MMIO bus + register-file control stack has been retired. A new single-file RTL controller `rtl/control/phase0_fixed_control.v` replaces the entire prior control plane. Live top-level (`rtl/top/piano_phase0_top.v`) now instantiates only `phase0_reset_sync`, `phase0_fixed_control`, `phase0_audio_path`, and `wm8978_codec_stub`.

All legacy CPU/firmware/MMIO code is preserved (not deleted) under `obsolete/riscv_control/`:
- `obsolete/riscv_control/rtl/control/phase0_boot_rom.v`
- `obsolete/riscv_control/rtl/control/phase0_data_ram.v`
- `obsolete/riscv_control/rtl/control/phase0_rv32i_core.v`
- `obsolete/riscv_control/rtl/control/phase0_rv32i_soc.v`
- `obsolete/riscv_control/rtl/control/phase0_control_regs.v`
- `obsolete/riscv_control/rtl/peripherals/phase0_uart_mmio.v`
- `obsolete/riscv_control/fw/phase0/`

Resource impact: LE 10,099 -> 3,614 (-6,485, ~64% reduction); setup slow-85C `sys_clk_50m` +2.846 ns -> +5.539 ns; all TNS 0; M9K bits 86,016 -> 20,480; ROM gate retired (firmware archived). Quartus full compile passes with 0 errors and 20 warnings.

Sections of this document above this update describe the obsolete architecture (RV32I core, MMIO map, firmware boot, UART command/telemetry contract, ROM/data RAM sizing) and remain useful as historical context for the archived files. They no longer describe the live design. See `reports/phase5_m0_fixed_control_flattening.md` for the new live architecture, the deferred UART functionality, and the recommended Phase 5 M1+ milestones.

## Update for Phase 5 M1 (2026-05-24)

UART TX status frames restored under the fixed-function architecture. New module `rtl/peripherals/phase0_uart_status_tx.v` instantiates the existing `rtl/peripherals/uart_tx.v` (8N1, 115200) and emits a 40-byte ASCII frame on `uart1_tx` every ~500 ms (25,000,000 sys_clk cycles). Frame format: `P5M1 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX\r\n`, where BOOT is a monotonic frame counter, TICK is a sample-tick snapshot at frame start, and VC is the round-robin voice index 00..03. The status block is sys_clk-domain only with no CDC. `phase0_fixed_control.v` now exposes `voice_index_status` instead of owning `uart1_tx` directly.

UART RX command parsing is still deferred to Phase 5 M2. `uart1_rx` remains unconsumed in the top-level. Phase 3 host wrappers in `scripts/phase3_*` continue to be useful only as legacy host-side regression tools until M2 reintroduces a small RTL command parser.

Quartus impact vs accepted M0 baseline: LE 3,614 -> 3,976 (+362), setup slack slow-85C `sys_clk_50m` +5.539 ns -> +5.885 ns, hold/TNS clean, M9K and DSP9 unchanged, warnings 20 -> 18 (idle uart1_tx and unused-signal sinks consumed). See `reports/phase5_m1_uart_status_tx_impl.md`.

## Update for Phase 5 M2 (2026-05-24)

UART RX command parser restored. Three new files land alongside the M1 status TX block:

- `rtl/peripherals/uart_rx.v`: standalone 8N1 115200 receiver lifted (semantics unchanged) from the obsolete `phase0_uart_mmio.v` archive. Double-flop synchronizer, mid-bit sample, frame-error pulse. sys_clk-domain only.
- `rtl/control/phase0_uart_command.v`: small parser FSM that consumes `rx_valid`/`rx_data`/`frame_error`, accumulates bytes into a 16-byte line buffer, and dispatches CRLF-terminated commands. Recognizes `!N\r\n` (bare note: loop_len=106, velocity=0x7FFF), `!NLLLLVVVV\r\n` (parameterized hex, case-insensitive, loop_len clamp 32..127, velocity clamp 0..0x7FFF), and `!F\r\n` (release). Emits single-cycle `note_strobe`/`release_strobe` with stable `cmd_loop_len[6:0]`/`cmd_velocity[15:0]` parameter wires. Records `command_count[31:0]` (32-bit), `error_count[15:0]` (saturating), and `last_error[15:0]` with codes 0=none, 1=malformed, 2=unknown opcode, 3=overlong, 4=frame error, 7=unsupported argument.
- `rtl/control/phase0_uart_command_tb.v`: focused testbench that drives bytes through the full `uart_rx` primitive (no bypass) and validates each command path.

`rtl/control/phase0_fixed_control.v` is extended:
- Adds `note_strobe`, `release_strobe`, `cmd_loop_len[6:0]`, `cmd_velocity[15:0]` inputs.
- Per-voice `loop_len`/`velocity` are now registers initialized to the M1 baseline 7'd106/16'h4000, written only on the cycle a note_strobe lands for the next voice in the round-robin order.
- A new `command_mode` flag latches on the first valid command and suppresses the autonomous round-robin sequencer so host control is exclusive after the first command.
- `voice_damp_mix` is now a register: default 16'd16384, raised to 16'd32767 on `release_strobe`, and reset to default on the next `note_strobe`. Static voice parameters `loop_gain` (16'd32640), `disp_coeff` (16'sd9952), `body_mix` (16'd8192) are unchanged.

`rtl/peripherals/phase0_uart_status_tx.v` extends the status frame from 40 bytes to 62 bytes. New tag `P5M2` and two new fields: `Q=XXXXXXXX` (32-bit `command_count` snapshot at frame start) and `X=XXXXXXXX` ({last_error[15:0], error_count[15:0]} snapshot). Frame format is now `P5M2 BOOT=XXXXXXXX TICK=XXXXXXXX VC=XX Q=XXXXXXXX X=XXXXXXXX\r\n`. Cadence remains ~500 ms.

`rtl/top/piano_phase0_top.v` removes the `_unused_uart1_rx` sink and instantiates `phase0_uart_command` driving the controller and feeding command_count/error_count/last_error to the status TX.

`quartus/phase0/piano_phase0_top.qsf` adds `uart_rx.v` and `phase0_uart_command.v` to the source list.

Quartus impact vs accepted M1 baseline: LE 3,976 -> 4,729 (+753, between +600 paper target and +800 hard limit), combinational 3,754 -> 4,492 (+738), registers 1,908 -> 2,349 (+441), setup slack slow-85C `sys_clk_50m` +5.885 ns -> +5.928 ns, hold +0.444 ns -> +0.432 ns, all TNS 0, M9K 5 (unchanged), DSP9 26 (unchanged), PLL 1 (unchanged), warnings 18 -> 16. See `reports/phase5_m2_uart_rx_command_impl.md`.

ModelSim: `phase0_uart_command_tb` PASS (4 notes, 1 release, 2 errors). `phase0_uart_status_tx_tb` PASS (2 frames decoded with Q=12345678 and X=00030007). `phase1_reduced_voice_tb` PASS golden bit-exact (`peak=3952`).

## File Map

- `rtl/top/piano_phase0_top.v`
  - board-facing shell for `sys_clk_50m`, reset, `WM8978`, and `UART1`
- `rtl/top/piano_phase0_top_tb.v`
  - simulation-only Phase 0 testbench environment plus happy-path and targeted-NACK top-level wrappers for ModelSim bring-up checks
- `rtl/top/wm8978_i2c_model.v`
  - bounded simulation-only WM8978-like I2C slave that ACKs valid writes, records captured codec words, and supports targeted NACK injection
- `rtl/control/phase0_rv32i_core.v`
  - minimal in-repo RV32I CPU for the Phase 0 firmware-owned control plane
- `rtl/control/phase0_boot_rom.v`
  - synchronous on-chip boot ROM wrapper fed from `phase0_fw.mif`
- `rtl/control/phase0_data_ram.v`
  - synchronous on-chip data RAM for stack and firmware state
- `rtl/control/phase0_rv32i_soc.v`
  - small ROM/RAM/MMIO wrapper that ties the RV32I core to the existing control-register block and UART aperture
- `rtl/control/phase0_control_regs.v`
  - CPU-visible register bank for audio and codec control
- `rtl/audio/phase0_audio_path.v`
  - hardware audio-path wrapper between control registers, the Phase 1 voice, and the codec transmit path
- `rtl/audio/phase1_reduced_voice.v`
  - Phase 1 fixed-pitch reduced piano/string voice with delay-line state, loop filtering, hammer excitation, body coloration, saturation, and status metering
- `rtl/audio/phase1_reduced_voice_tb.v`
  - standalone ModelSim voice regression for trigger latency, bounded output, default no-clip behavior, frequency, and decay
- `rtl/audio/phase0_sample_gen.v`
  - historical Phase 0 deterministic sample source; kept in the tree but no longer instantiated by the live audio path
- `rtl/peripherals/phase0_reset_sync.v`
  - synchronous reset release for the `50 MHz` fabric domain
- `rtl/peripherals/wm8978_codec_stub.v`
  - promoted into the first functional WM8978 baseline block
- `rtl/peripherals/wm8978_i2c_ctrl.v`
  - write-focused I2C controller for WM8978 register programming
- `rtl/peripherals/wm8978_boot_seq.v`
  - power-up WM8978 init sequence plus CPU-passthrough config writes
- `rtl/peripherals/wm8978_dac_tx.v`
  - codec-facing serial DAC transmitter with frame-tick generation
- `rtl/peripherals/phase0_uart_mmio.v`
  - minimal polling UART MMIO block that wraps `uart_tx.v` at `0x4000_1000`
- `rtl/peripherals/uart_tx.v`
  - minimal `8N1` UART transmitter used by the RV32I control plane for compact status frames on `UART1`
- `fw/phase0/phase0_hw.h`
  - provisional Phase 0 CPU memory map, control-register offsets, and UART/MMIO contract
- `fw/phase0/start.S`
  - RV32I reset entry, `.data` copy, and `.bss` clear
- `fw/phase0/phase0_main.c`
  - smallest useful firmware flow for codec status polling, CPU-owned codec writes, UART debug, and tone triggering
- `fw/phase0/link.ld`
  - small on-chip ROM/RAM layout for early firmware bring-up
- `fw/phase0/build.ps1`
  - PowerShell build entry that emits ELF, binary, disassembly, and a simple memory-init file, with Windows-side auto-detection for a user-space xPack RISC-V GCC install

## Provisional Phase 0 CPU Map

These addresses are now the live CPU-side contract used by the integrated Phase 0 RV32I subsystem:

- `0x0000_0000` - `0x0000_0FFF`
  - on-chip firmware ROM (`4 KiB`)
- `0x0001_0000` - `0x0001_0FFF`
  - on-chip firmware RAM (`4 KiB`)
- `0x4000_0000`
  - control-register block currently described by `phase0_control_regs.v`
- `0x4000_1000`
  - minimal polling UART aperture for firmware debug:
    - `+0x00`: TX data
    - `+0x04`: status, with bit `0` meaning TX ready

The current `fw/phase0/build.ps1` flow is verified against an installed xPack GNU RISC-V Embedded GCC toolchain on Windows (`15.2.0-1.1` under `%APPDATA%\xPacks`). The script still accepts an explicit `-ToolPrefix`, but it no longer requires manual PATH edits for the common xPack case.

The current RTL now executes the `fw/phase0` image through `phase0_rv32i_soc.v`.

- the boot ROM consumes `phase0_fw.mif`, which `fw/phase0/build.ps1` emits to both the repo root and `quartus/phase0/`
- ModelSim runs should use the repo root as the working directory, or otherwise make `phase0_fw.mif` visible from the simulator's current working directory
- the current firmware behavior is the documented Phase 0 baseline:
  - read `IDENT`
  - emit compact `I=`, `S=`, and `R=` ASCII hex frames on `UART1`
  - program `PHASE_STEP`, `GAIN`, `DECAY_STEP`, and `CONTROL`
  - poll `STATUS` until codec init completes or fails
  - issue the two CPU-owned codec writes through `CODEC_CFG` plus `CONTROL[9]`
  - pulse `CONTROL[8]` once after codec init to start the hardware-owned tone path with a deterministic phase reset

## Control Register Contract

Current register map in `phase0_control_regs.v`:

- `0x00` `IDENT`
  - read-only marker `0x50303031`
- `0x04` `CONTROL`
  - bit `0`: `audio_enable`
  - bit `1`: `tone_enable`
  - bits `5:4`: `wave_sel`
  - selector `0`: square
  - selector `1`: saw
  - selector `2`: envelope-only pulse
  - bit `8`: one-cycle `trigger_strobe`
  - bit `9`: one-cycle `codec_cfg_valid`
- `0x08` `PHASE_STEP`
  - low `24` bits for the sample generator phase increment
- `0x0C` `GAIN`
  - low `16` bits for amplitude
- `0x10` `DECAY_STEP`
  - low `16` bits for a simple envelope step
- `0x14` `CODEC_CFG`
  - low `16` bits reserved for CPU-driven codec writes
- `0x18` `STATUS`
  - read-only combined audio and codec status word
  - upper byte currently exposes:
    - bit `31`: codec init completed
    - bit `30`: codec init failed
    - bit `29`: codec transaction error seen
    - bit `28`: codec timeout seen
    - bit `27`: CPU codec write pending handoff into the codec domain
    - bit `26`: audio transmit sample valid
    - bit `25`: audio sample tick observed
    - bit `24`: codec path busy/completion fence
- `0x20` `VOICE_CONTROL`
  - bit `0`: `voice_enable`
  - bit `1`: write-one `trigger`
  - bit `2`: write-one `reset_voice`
  - bit `3`: `body_bypass`
  - bit `4`: `disp_bypass`
  - bit `8`: write-one `clip_clear`
- `0x24` `VOICE_STATUS`
  - bit `0`: voice active
  - bit `1`: excitation burst busy
  - bit `2`: sticky clip seen
  - bit `3`: voice sample valid
  - bit `4`: voice enabled
  - bits `31:16`: peak meter
- `0x28` `VOICE_VELOCITY`
  - unsigned Q1.15 trigger velocity, reset `0x4000`, clamped to `0x7FFF`
- `0x2C` `VOICE_LOOP_LEN`
  - integer delay length, reset `106`, clamped to `32..127`
- `0x30` `VOICE_LOOP_GAIN`
  - unsigned Q1.15 loop gain, reset `32640`, clamped to `0x7FFF`
- `0x34` `VOICE_DAMP_MIX`
  - unsigned Q1.15 damping mix, reset `16384`, clamped to `0x7FFF`
- `0x38` `VOICE_DISP_COEFF`
  - signed Q1.15 first-order allpass coefficient, reset `9952`
- `0x3C` `VOICE_BODY_MIX`
  - unsigned Q1.15 tiny-body mix amount, reset `8192`, clamped to `0x7FFF`
- `0x40` `VOICE_SAMPLE_COUNT`
  - read-only 32-bit diagnostic counter incremented on every audio `sample_tick`
- `0x44` `VOICE_TRIGGER_COUNT`
  - read-only 32-bit diagnostic counter incremented when the voice accepts a trigger while enabled
- `0x48` `VOICE_ACTIVE_COUNT`
  - read-only 32-bit diagnostic counter incremented when `sample_valid` is asserted while the voice is active
- `0x4C` `VOICE_VALID_COUNT`
  - read-only 32-bit diagnostic counter incremented on every voice `sample_valid`
- `0x50` `VOICE_DIAG_CONTROL`
  - bit `0`: write-one clear for the four diagnostic counters

This is intentionally a narrow Phase 0 interface. It is enough for the follow-on firmware task to exercise the hardware path without inventing a large SoC fabric early.

The `fw/phase0` package assumes the firmware-visible control block is rooted at `0x4000_0000` and keeps the control pulse semantics explicit:

- firmware writes `CODEC_CFG`, then writes `CONTROL` with bit `9` set for a CPU-owned codec transaction
- firmware writes `CONTROL` with bit `8` set to trigger a note/event in the hardware sample path
- Phase 1 firmware writes `VOICE_CONTROL` with bit `1` set to trigger the reduced voice; the legacy `CONTROL[8]` trigger is still accepted by the audio shell for compatibility
- firmware is expected to poll `STATUS` bit `24` (`codec busy`) as the transaction-completion fence and use the init/error bits in the upper byte rather than assume every codec write completed

## Important Non-Features

This baseline still does **not** provide a finished board product:

- the board now has a real UART transmit path for bring-up, but there is still no receive-side command parser, interrupt support, or fuller UART peripheral block
- the soft core is now present, but it is still intentionally narrow:
  - no interrupts
  - no CSR/privileged support
  - no caches
  - no external bus fabric
  - no attempt at general-purpose performance beyond the current Phase 0 firmware flow
- the WM8978 baseline now uses a dedicated PLL-derived `12.000 MHz` `audio_mclk`, but it still relies on the simpler direct-`MCLK` codec path rather than a fully explicit codec-PLL / exact-`48 kHz` contract
- Quartus packaging and synthesis now exist under `quartus/phase0/`; the initial CLI license failure was traced to the `32-bit` `bin` executables, the GUI `64-bit` flow succeeds, and the patched `build.ps1` now reproduces that success from the command line
- the current Quartus package now models `sys_clk_50m`, generated `i2c_clk`, the external `audio_bclk` island, and the defendable source-synchronous WM8978 audio data timing; the remaining board interfaces are now explicit exclusions rather than accidental unconstrained gaps
- codec-status reporting is still intentionally small; it surfaces the hard failure states needed for bring-up, not a complete debug/trace interface
- the stronger ModelSim harness now validates the write-side digital codec control path and basic DAC-line activity, but it is still not a full WM8978 behavioral model and should not be treated as sign-off for codec-internal behavior or audio fidelity

That split is still deliberate. The stub has now been replaced by the minimum firmware-owned RV32I path, and later follow-on work should focus on timing closure plus any decision to keep or replace the current direct-`MCLK` Phase 0 audio-rate contract.

## Follow-On Expectations

### For `task-d43bbf83`

- keep the same top-level ports and module ownership split
- keep the codec block CPU-configurable and hardware-driven at the sample level
- replace the temporary divided MCLK with a cleaner audio clock source when Quartus collateral is added
- preserve the mono-to-stereo frame behavior unless there is a reason to separate channels

### After `task-9d00cc2f`

- preserve the documented Phase 0 CPU memory map unless there is a compelling reason to change it
- keep the firmware image freestanding and on-chip:
  - no RTOS
  - no file system
  - no SDRAM dependency
- keep the current UART framing and STATUS contract stable unless the follow-on work updates both firmware and regression collateral together
- treat the remaining slow-`85C` `sys_clk_50m` timing miss as the main hardware follow-up, not as a reason to revert to the earlier stub architecture

### After `task-224a897d`

- the repo now includes a real Quartus project package at `quartus/phase0/` for `piano_phase0_top`
- the package binds only the current board-facing interface set:
  - `sys_clk_50m`
  - `sys_rst_n`
  - WM8978 pins
  - `UART1`
- `reports/phase0_quartus_bringup_report.md` now records the corrected build finding:
  - the initial scripted failure came from invoking the `32-bit` `D:\quartus\quartus\bin` executables
  - the Quartus GUI uses the working `64-bit` flow and successfully compiled the same packaged revision
  - the patched `quartus/phase0/build.ps1` now also drives the working `64-bit` flow and has been verified with a successful scripted full compile
  - the successful GUI run produced `output_files/piano_phase0_top.sof`
  - `quartus/phase0/build.ps1` now prefers `bin64` executables when available so scripted runs follow the GUI path
- `task-aaca35f6` tightens the timing collateral further:
  - `quartus/phase0/piano_phase0_top.sdc` now models:
    - `sys_clk_50m`
    - derived PLL `audio_mclk` at `12.000 MHz`
    - generated `i2c_clk` at `1 MHz`
    - external `audio_bclk` at a deliberate Phase 0 bring-up assumption of `1.500 MHz`
  - the SDC now treats the codec-driven audio bit-clock island as asynchronous to the sys/i2c fabric clocks, which matches the current off-chip codec boundary and CDC usage better than leaving `audio_bclk` accidentally unconstrained
  - the updated full compile removes the previous unconstrained-clock and clock-uncertainty warnings
  - the remaining Quartus warnings are now narrower and more honest:
    - the intentionally unused `audio_adcdat` input in current playback-only RTL
    - at that `task-aaca35f6` stage, board I/O timing was still intentionally unmodeled; later `task-241de457` added WM8978 audio-pin delays and converted the remaining off-chip interfaces into explicit exclusions
- the only synthesis warning left in the packaged design is expected: `audio_adcdat` is pinned for interface completeness but is not yet consumed by the current playback-only RTL

## Why The Split Looks Like This

The scaffold keeps the CPU boundary, control-register boundary, hardware sample boundary, and codec-facing boundary separate from the start. That reduces the chance that the next two tasks collapse into a vendor-example copy with SD-era assumptions still baked into the design.
