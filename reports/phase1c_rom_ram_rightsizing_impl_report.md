# Phase 1C-A ROM/RAM Right-Sizing Implementation Report

Date: 2026-04-28
Agent: Codex implementer
Task: `task-9c9f5bd4`

## Verdict

PASS.

The authorized Phase 1C-A slice is implemented and validated. Firmware ROM and RAM are right-sized from `4096 x 32` each to `1024 x 32` each, recovering `24` M9Ks versus the hardware-accepted two-voice baseline while preserving the accepted two-voice behavior, UART frames, register/MMIO map, clocking, audio model, and CPU-out-of-sample-loop split.

No third voice, SDRAM, scheduler, body-pipe rewrite, richer physics, sample playback, UI, larger CPU, PLL/clock change, or unrelated cleanup was added.

## Implementation

Changed files:

- `fw/phase0/link.ld`: ROM and RAM lengths are now `4K`.
- `fw/phase0/phase0_hw.h`: ROM/RAM size constants are now `0x00001000`; base addresses are unchanged.
- `fw/phase0/build.ps1`: MIF generation now uses `DEPTH = 1024`, fills only through address `0x3FF`, and fails the build if the firmware image exceeds the configured ROM depth.
- `rtl/control/phase0_boot_rom.v`: boot ROM now defaults to `ADDR_WIDTH = 10`, `MEM_WORDS = 1024`.
- `rtl/control/phase0_data_ram.v`: data RAM now defaults to `ADDR_WIDTH = 10`, `MEM_WORDS = 1024`.
- `rtl/control/phase0_rv32i_soc.v`: data RAM decode now selects the `0x0001_0000..0x0001_0FFF` 4 KiB page.
- `docs/phase0_impl_notes.md`: documents the right-sized memory envelope and validation result.

Unchanged architectural contracts:

- ROM base: `0x0000_0000`
- RAM base: `0x0001_0000`
- control registers: `0x4000_0000`
- UART MMIO: `0x4000_1000`
- two reduced voices and their register/UART diagnostics
- codec/audio clocking and mono-to-dual-mono output behavior

## Size Rationale

The generated firmware remains well below the new ROM limit:

- linked `.text`: `0x37c` bytes
- `phase0.bin`: `892` bytes
- MIF content ends at word `0x0DE`, then fills `[0DF..3FF]`
- ROM capacity: `1024` words / `4096` bytes
- RAM capacity: `4096` bytes, with `_stack_top = 0x00011000`
- `.data` and `.bss` remain empty in the current build

Consistency evidence is in `reports/phase1c_rom_ram_rightsizing_consistency.log`.

## Validation

Firmware and consistency:

- Firmware build: PASS (`reports/phase1c_rom_ram_rightsizing_fw_build.log`).
- Linker/MIF/depth consistency: PASS, `depth=1024`, `.text=0x37c`, `bin_bytes=892` (`reports/phase1c_rom_ram_rightsizing_consistency.log`).

ModelSim:

- Fresh compile into `phase1c_romram_work`: PASS, `0` errors / `0` warnings (`reports/phase1c_rom_ram_rightsizing_msim_compile.log`).
- Reduced voice TB: PASS, unchanged signature: `VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082` (`reports/phase1c_rom_ram_rightsizing_msim_voice.log`).
- Top happy path: PASS, `voice_peak_level=2082`, `voice1_peak_level=2082`, `mix_peak_level=4164`, `mix_clip_count=0`, `uart_capture_count=111` (`reports/phase1c_rom_ram_rightsizing_msim_happy.log`).
- NACK path: PASS, `nack_count=1`, `stop_count=1` (`reports/phase1c_rom_ram_rightsizing_msim_nack.log`).

Quartus and TimeQuest:

- Full compile: PASS, `0` errors / `12` warnings (`reports/phase1c_rom_ram_rightsizing_quartus_compile.log`).
- SOF SHA-256: `D5D2A283CCF37795CEED9BD79C754003E184AE6927842F4E0112AE6D866FF3EA`.
- Programmer checksum: `0x0055BA0E`.
- Slow 85C setup slack: `sys_clk_50m +3.214 ns`, `i2c_clk +17.825 ns`, `audio_bclk +315.985 ns`.
- Slow 85C hold slack: `sys_clk_50m +0.433 ns`, `audio_bclk +0.453 ns`, `i2c_clk +0.454 ns`.
- Slow 85C Fmax: `sys_clk_50m 59.57 MHz`, `i2c_clk 179.73 MHz`, `audio_bclk 28.82 MHz`.

Hardware smoke:

- USB-Blaster detected and the right-sized SOF programmed successfully twice, including during audio capture (`reports/phase1c_rom_ram_rightsizing_quartus_pgm.log`).
- UART on `COM5`, `115200 8N1`, captured recurring two-voice diagnostics (`reports/phase1c_rom_ram_rightsizing_uart_capture.txt`):

```text
R=8018077F
V=08220010
T=00000001
Y=08220010
U=00000001
M=10440010
K=00000000
```

- External Realtek audio capture: PASS (`reports/phase1c_rom_ram_rightsizing_audio_capture.wav`, `reports/phase1c_rom_ram_rightsizing_audio_analysis.txt`).
- Audio analysis: event onset `3.100 s`, mono F0 `436.363636 Hz`, mono early crest factor `4.010922`, total clipped samples `0`, and decay `-17.27 dB` by `0.50 s`.

## Resource Delta

Delta is versus the hardware-accepted two-voice baseline in `reports/phase1c_resource_attribution_acceptance_decision.md`.

| Metric | Accepted two-voice | Right-sized | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 7,366 / 10,320 | 7,382 / 10,320 | +16 |
| Dedicated registers | 3,580 | 3,580 | 0 |
| Memory bits | 271,360 / 423,936 | 74,752 / 423,936 | -196,608 |
| M9Ks | 34 / 46 | 10 / 46 | -24 |
| DSP9 elements | 4 / 46 | 4 / 46 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow 85C `sys_clk_50m` setup slack | +3.957 ns | +3.214 ns | -0.743 ns |
| Slow 85C `sys_clk_50m` hold slack | +0.432 ns | +0.433 ns | +0.001 ns |
| Slow 85C `sys_clk_50m` Fmax | 62.33 MHz | 59.57 MHz | -2.76 MHz |

The small LE/timing movement is a fitter result from changing ROM/RAM geometry. Timing remains comfortably positive and fully constrained.

## Mapping Check

Right-sized memory mapping:

- Boot ROM: `1024 x 32`, `32,768` bits, `4` M9Ks.
- Data RAM: `1024 x 32`, `32,768` bits, `4` M9Ks.

Voice mapping is preserved:

- `phase1_reduced_voice_inst`: `4,608` memory bits, `1` M9K, `2` DSP elements.
- `phase1_reduced_voice1_inst`: `4,608` memory bits, `1` M9K, `2` DSP elements.
- The two-voice audio path still uses `4` DSP9 elements total.

## Residual Notes

The accepted two-voice SOF remains the rollback baseline until verifier/orchestrator acceptance promotes this right-sized build. This task only recovers ROM/RAM M9K headroom; it does not address LE pressure from the RV32I core or duplicated voice engines, and it should not be treated as authorization for the still-gated scaling items.
