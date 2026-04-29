# Phase 1C Firmware Round-Robin Implementation Report

## Scope

Implemented the authorized firmware-owned round-robin slice over the existing three hardware voices. No design RTL, hardware dispatcher, register offsets, or pre-`0x84` ABI surface were changed.

Source changes:

- `fw/phase0/phase0_main.c`
  - Replaced the one-shot `voice0, voice1, voice2` boot trigger sequence with six low-rate note events assigned by firmware as `0,1,2,0,1,2`.
  - Added scheduler counters for event count, last selected voice, per-voice assignment counts, and drop/steal count.
  - Preserved the existing UART report prefix and voice diagnostics through `E`.
  - Appended scheduler diagnostics after `E`: `G` event count, `H` last voice, `J/L/N` voice 0/1/2 assignment counts, `P` drop/steal count.
- `phase1c_roundrobin_work/phase1c_round_robin_top_tb.v`
  - Verification-only top testbench. It observes the existing top-level voice trigger strobes hierarchically and checks the firmware assignment sequence without editing RTL.

## Firmware Build

Command:

```powershell
.\fw\phase0\build.ps1
```

Result:

- PASS
- Toolchain: xPack `riscv-none-elf-gcc` 15.2.0-1.1
- ROM image size: 318 words / 1024 words
- Updated generated firmware images:
  - `fw/phase0/build/phase0.bin`
  - `fw/phase0/build/phase0.mem`
  - `fw/phase0/build/phase0.mif`
  - `phase0_fw.mif`
  - `quartus/phase0/phase0_fw.mif`

Evidence: `reports/phase1c_firmware_round_robin_fw_build.log`

## Simulation

ModelSim compile:

- PASS, 0 errors
- Evidence: `reports/phase1c_firmware_round_robin_msim_compile.log`

Standalone voice regression:

- PASS
- `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082 golden_samples=4096`
- Evidence: `reports/phase1c_firmware_round_robin_msim_voice.log`

Round-robin top simulation:

- PASS
- Observed assignment sequence: `0,1,2,0,1,2`
- Observed assignment counts: `2,2,2`
- Trigger counts: `voice_trigger_count=2`, `voice1_trigger_count=2`, `voice2_trigger_count=2`
- Overlap proof: all three voices active, with active counts `1671,1671,1671`
- Valid counts: `1828,1829,1829`
- Mix peak: `6246`
- Default smoke clip count: `mix_clip_count=0`
- UART scheduler diagnostics captured and checked: `G=6,H=2,J=2,L=2,N=2,P=0`
- Evidence: `reports/phase1c_firmware_round_robin_msim_happy.log`

NACK regression:

- PASS
- `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1`
- Evidence: `reports/phase1c_firmware_round_robin_msim_nack.log`

## Quartus Rebuild

Command:

```powershell
quartus_sh --flow compile piano_phase0_top
```

Result:

- PASS, full compilation successful
- Fitter successful: 0 errors, 3 warnings
- TimeQuest successful: 0 errors, 0 warnings
- Full flow: 0 errors, 14 warnings
- Device: EP4CE10F17C8
- Logic elements: 7,548 / 10,320 (73%)
- Registers: 3,275
- Memory bits: 80,896 / 423,936 (19%)
- DSP9 elements: 6 / 46 (13%)
- Slow 85C setup slack: +3.675 ns on `sys_clk_50m`
- Slow 85C worst hold slack: +0.414 ns on `i2c_clk`; `sys_clk_50m` hold slack +0.433 ns
- SOF SHA256: `0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0`

Evidence:

- `reports/phase1c_firmware_round_robin_quartus_compile.log`
- `quartus/phase0/output_files/piano_phase0_top.fit.summary`
- `quartus/phase0/output_files/piano_phase0_top.sof`

## Hardware Smoke

Programmer:

- USB-Blaster detected: `USB-Blaster [USB-0]`
- Programming PASS
- Evidence:
  - `reports/phase1c_firmware_round_robin_quartus_pgm_list.log`
  - `reports/phase1c_firmware_round_robin_quartus_pgm.log`

UART:

- Capture port: `COM5`, 115200 8N1
- Capture size: 1008 bytes
- New boot frames include:
  - `I=50303031`
  - `S=8018073F`
  - `R=8019077F`
  - `T=00000002`
  - `U=00000002`
  - `O=00000002`
  - `K=00000000`
  - `G=00000006`
  - `H=00000002`
  - `J=00000002`
  - `L=00000002`
  - `N=00000002`
  - `P=00000000`
- The capture begins with residual repeated frames from the previously programmed image, then includes the new boot sequence after reprogramming.
- Evidence:
  - `reports/phase1c_firmware_round_robin_uart_capture.bin`
  - `reports/phase1c_firmware_round_robin_uart_capture.txt`

Audio:

- Capture device: `外部麦克风 (Realtek(R) Audio)`
- Duration: 5.99 seconds
- Samples: 287,376 at 48 kHz mono
- Peak level: -13.084021 dBFS
- RMS level: -41.588136 dBFS
- Evidence:
  - `reports/phase1c_firmware_round_robin_audio_devices.log`
  - `reports/phase1c_firmware_round_robin_audio_capture.wav`
  - `reports/phase1c_firmware_round_robin_audio_ffmpeg.log`
  - `reports/phase1c_firmware_round_robin_audio_analysis.txt`

## Acceptance Notes

- Existing register offsets through `0x80` are unchanged.
- Existing UART diagnostics through `I/S/R` and `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E` are preserved in order.
- New diagnostics are appended only after `E`.
- The CPU remains in the low-rate note-event/control path and is not in the audio sample loop.
- No voice stealing, per-note state, per-voice parameter banks, fourth voice, hardware dispatcher, SDRAM, richer physics, sample playback, exact-48k work, CPU/ISA expansion, UI, or unrelated cleanup was added.
