# Phase 1C-A ROM/RAM Right-Sizing Validation

Verifier: Codex verifier agent  
Task: `task-a03a1741`  
Date: 2026-04-28  
Verdict: PASS

## Scope

This validation checked the Phase 1C-A ROM/RAM right-sized build against the authorized narrow memory-headroom cleanup slice.

No verifier-side RTL, firmware, constraints, clocking, register-map, or behavior changes were made. Additional verifier evidence files were generated under `reports/` only.

## References

- `reports/phase1c_rom_ram_rightsizing_impl_report.md`
- `reports/phase1c_resource_attribution_acceptance_decision.md`
- `reports/phase1c_resource_attribution_validation.md`
- `reports/phase1_two_voice_hardware_acceptance_decision.md`
- `quartus/phase0/output_files/piano_phase0_top.fit.summary`
- `quartus/phase0/output_files/piano_phase0_top.fit.rpt`
- `quartus/phase0/output_files/piano_phase0_top.sta.summary`
- `fw/phase0/build/phase0.map`

## Result

PASS. The implementation stayed within the authorized ROM/RAM right-sizing scope and preserves the accepted two-voice behavior, register/UART contract, clocking, voice M9K/DSP mapping, and hardware smoke behavior.

I recommend promoting the right-sized SOF to the current accepted baseline, with the prior hardware-accepted two-voice SOF retained as the rollback image until the orchestrator publishes the replacement acceptance decision.

## Scope Discipline

The implementation is narrow and matches the Phase 1C authorization:

- `fw/phase0/link.ld` reduces ROM and RAM lengths to `4K`.
- `fw/phase0/phase0_hw.h` updates ROM/RAM size constants to `0x00001000` while preserving base addresses.
- `fw/phase0/build.ps1` emits `DEPTH = 1024` MIF files and fails if the firmware image exceeds the configured ROM depth.
- `rtl/control/phase0_boot_rom.v` and `rtl/control/phase0_data_ram.v` default to `ADDR_WIDTH = 10`, `MEM_WORDS = 1024`.
- `rtl/control/phase0_rv32i_soc.v` decodes the `0x0001_0000..0x0001_0FFF` RAM page through `data_addr[31:12] == 20'h00010`.
- `docs/phase0_impl_notes.md` records the memory-envelope change and explicitly keeps the two-voice audio/register/UART/clock contracts unchanged.

No evidence was found of a third voice, SDRAM, scheduler, body-pipe rewrite, richer physics, UI, sample playback, larger CPU, clock/PLL change, register-map expansion, or unrelated cleanup in this slice.

## Firmware And Memory Consistency

Verifier reran the firmware build:

- Command: `powershell -ExecutionPolicy Bypass -File fw\phase0\build.ps1`
- Result: PASS
- Evidence: `reports/phase1c_rom_ram_rightsizing_validation_fw_build.log`

The generated memory collateral is internally consistent:

| Check | Result |
| --- | --- |
| Linker ROM | `0x0000_0000`, length `0x00001000` |
| Linker RAM | `0x0001_0000`, length `0x00001000` |
| Stack top | `0x00011000` |
| `.text` size | `0x37c` bytes |
| `phase0.bin` size | `892` bytes |
| Root MIF depth | `DEPTH = 1024` |
| Quartus MIF depth | `DEPTH = 1024` |
| MIF fill range | `[0DF..3FF] : 00000000` |
| Boot ROM RTL | `ADDR_WIDTH = 10`, `MEM_WORDS = 1024` |
| Data RAM RTL | `ADDR_WIDTH = 10`, `MEM_WORDS = 1024` |

The current firmware image uses less than one quarter of the 4 KiB ROM. `.data` and `.bss` remain empty, leaving the 4 KiB RAM envelope for stack/control-flow margin in this firmware build.

## Simulation Evidence

The submitted simulation logs support the implementation report:

| Test | Evidence | Result |
| --- | --- | --- |
| ModelSim compile | `reports/phase1c_rom_ram_rightsizing_msim_compile.log` | PASS, `0` errors / `0` warnings |
| Reduced voice TB | `reports/phase1c_rom_ram_rightsizing_msim_voice.log` | PASS, unchanged signature, peak `2082` |
| Top happy path | `reports/phase1c_rom_ram_rightsizing_msim_happy.log` | PASS, voice0 peak `2082`, voice1 peak `2082`, mix peak `4164`, mix clip `0` |
| NACK path | `reports/phase1c_rom_ram_rightsizing_msim_nack.log` | PASS, `nack_count=1`, `stop_count=1` |

The standalone voice result and top-level two-voice status are consistent with the accepted two-voice behavior.

## Resource And Timing Comparison

Resource and timing numbers match the current Quartus reports and the implementation report.

| Metric | Hardware-Accepted Two-Voice | Right-Sized Build | Delta |
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

TimeQuest remains fully constrained with all listed TNS values at `0.000`. The small LE increase and setup/Fmax movement are acceptable fitter movement from the ROM/RAM geometry change.

## Mapping Check

The right-sized build has the intended memory mapping:

- Boot ROM: `1024 x 32`, `32768` bits, `4` M9Ks, initialized from `phase0_fw.mif`.
- Data RAM: `1024 x 32`, `32768` bits, `4` M9Ks.
- Voice 0 delay-line storage: `4608` logical bits, `1` physical M9K.
- Voice 1 delay-line storage: `4608` logical bits, `1` physical M9K.
- Voice multipliers: two signed 18-bit simple multipliers, `4` DSP9 elements total.

The Phase 1 voice delay-line and multiplier mapping did not regress.

## Independent Hardware Smoke

Verifier hardware evidence was collected after reviewing the submitted implementation evidence.

Build identity:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `D5D2A283CCF37795CEED9BD79C754003E184AE6927842F4E0112AE6D866FF3EA`
- Programmer checksum: `0x0055BA0E`

JTAG:

- `USB-Blaster [USB-0]` was visible.
- Programming succeeded on `EP4CE10F17@1`.
- JTAG ID code observed: `0x020F10DD`.
- Evidence:
  - `reports/phase1c_rom_ram_rightsizing_validation_pgm_list.log`
  - `reports/phase1c_rom_ram_rightsizing_validation_pgm.log`
  - `reports/phase1c_rom_ram_rightsizing_validation_pgm_during_uart.log`
  - `reports/phase1c_rom_ram_rightsizing_validation_pgm_during_audio.log`

UART on `COM5`, `115200 8N1`, captured startup and recurring two-voice diagnostics:

```text
I=50303031
S=8018073F
R=8018077F
V=08220010
T=00000001
Y=08220010
U=00000001
M=10440010
K=00000000
```

Evidence: `reports/phase1c_rom_ram_rightsizing_validation_uart_capture.txt`.

Audio:

- External Realtek capture succeeded after using the DirectShow alternative device ID to avoid localized-device-name encoding issues.
- Evidence:
  - `reports/phase1c_rom_ram_rightsizing_validation_audio_capture.wav`
  - `reports/phase1c_rom_ram_rightsizing_validation_audio_ffmpeg.log`
  - `reports/phase1c_rom_ram_rightsizing_validation_audio_analysis.txt`
- Analysis result:
  - duration `11.986 s`
  - event onset `3.520 s`
  - mono F0 `435.510 Hz`
  - mono early RMS `0.023710`
  - mono early peak `0.088638`
  - mono crest factor `3.738`
  - total clipped samples `0`
  - no square-wave regression indicated

The independent hardware smoke agrees with the implementation report and with the earlier accepted two-voice behavior.

## Residual Risks

- The build now has a smaller ROM/RAM envelope by design. Future firmware changes must continue to rely on the ROM bounds check and should re-check `.data`, `.bss`, and stack-margin assumptions.
- This slice recovers M9K headroom only. It does not solve the LE pressure from the RV32I core and duplicated voice engines, and it should not be treated as authorization for third voice, scheduler, SDRAM, richer physics, sample playback, UI, larger CPU, or clock work.
- The old two-voice SOF remains the practical rollback image until the right-sized build is explicitly accepted as the replacement baseline.

## Recommendation

Promote the Phase 1C-A ROM/RAM right-sized build to the current accepted baseline.

The promotion should be framed narrowly: it accepts the same two-voice behavior with reduced on-chip ROM/RAM allocation and recovered M9K headroom. It does not relax the existing gates on voice scaling or feature expansion.
