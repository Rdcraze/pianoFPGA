# Phase 0 RV32I Timing-Closure Validation

## Findings

- No new verifier finding blocks acceptance of the integrated Phase 0 RV32I timing-closure build. Internal modeled-clock timing is closed after rerunning the Quartus compile on 2026-04-24.
- The exact slow-85C `sys_clk_50m` setup result is now positive: slack `+1.120 ns`, TNS `0.000 ns`. Slow-85C hold is also positive: slack `+0.433 ns`, TNS `0.000 ns`.
- The prior dominant failing family is no longer present as a direct `instr_reg[*] -> regs[*]` writeback path in the current TimeQuest top setup table. The current worst slow-85C `sys_clk_50m` setup path is `phase0_rv32i_core:cpu_inst|regs[26][1] -> phase0_rv32i_core:cpu_inst|wb_writeback_data_q[29]`, with data delay `19.252 ns` and slack `+1.120 ns`.
- Scope caveat: Quartus/TimeQuest still reports the design is not fully constrained for setup/hold because board-level I/O delays remain omitted. This is a board I/O sign-off gap, not an internal RV32I timing-closure failure.
- Clock/audio caveats remain non-blocking for this verdict: `audio_adcdat` is intentionally unused, some pins have incomplete I/O assignments, and the PLL-generated `audio_mclk` output still has the known output-compensation/non-dedicated-routing warnings.
- Audio capture caveat: the built-in microphone capture was not used as proof because it did not isolate the board tone. The external Realtek input capture is the accepted audio evidence and is explicitly labeled as L/R in the generated plot.

## Timing Evidence

Rebuilt image:

- Firmware build: `reports/phase0_rv32i_timing_closure_fw_build.log`, exit `0`.
- Quartus compile: `reports/phase0_rv32i_timing_closure_quartus_compile.log`, full compilation successful with `0 errors, 8 warnings`.
- New SOF timestamp: `quartus/phase0/output_files/piano_phase0_top.sof`, `2026-04-24T08:14:23+08:00`.
- Programmed SOF checksum: `0x003EAD3F`.

Slow 1200 mV 85C setup:

| Clock | Slack | TNS |
| --- | ---: | ---: |
| `sys_clk_50m` | `+1.120 ns` | `0.000 ns` |
| `i2c_clk` | `+17.868 ns` | `0.000 ns` |
| `audio_bclk` | `+328.252 ns` | `0.000 ns` |

Slow 1200 mV 85C hold:

| Clock | Slack | TNS |
| --- | ---: | ---: |
| `sys_clk_50m` | `+0.433 ns` | `0.000 ns` |
| `i2c_clk` | `+0.444 ns` | `0.000 ns` |
| `audio_bclk` | `+0.453 ns` | `0.000 ns` |

Resource snapshot from the successful post-fit flow:

| Resource | Usage |
| --- | ---: |
| Logic elements | `4,809 / 10,320 (47%)` |
| Dedicated logic registers | `1,520 / 10,320 (15%)` |
| Memory bits | `262,144 / 423,936 (62%)` |
| Embedded multiplier 9-bit elements | `2 / 46 (4%)` |
| PLLs | `1 / 2 (50%)` |

## Functional Evidence

Simulation:

- ModelSim RTL compile: `0 errors, 0 warnings`.
- Normal testbench: `TB_PASS fabric_status=8019077f soc_status=037f write_count=18 dac_toggle_count=1668 uart_capture_count=36`.
- NACK testbench: `TB_NACK_PASS fabric_status=6019073f soc_status=033f nack_count=1 stop_count=1`.

Live board smoke:

- Programmer saw `USB-Blaster [USB-0]`, JTAG ID `0x020F10DD`, and configured one `EP4CE10F17` device successfully.
- UART capture on `COM4` after programming the rebuilt SOF:

```text
I=50303031
S=8019073F
R=8019077F
R=8019077F
R=8019077F
R=8019077F
R=8019077F
```

Audio baseline:

- Expected digital waveform is a two-level square wave from `phase0_sample_gen`: `-gain` when `phase_accum[23] == 0`, `+gain` when `phase_accum[23] == 1`, with `phase_step=157482`, `gain=4096`, `decay_step=0`, and square wave select.
- With the board's effective sample tick of about `46.875 kHz`, expected frequency is `157482 * 46875 / 2^24 = 439.9996 Hz`.
- External capture, L channel: `440.001454 Hz`, RMS CV `0.0177%`, f0 window span `1.44 ppm`.
- External capture, R channel: `440.001461 Hz`, RMS CV `0.0335%`, f0 window span `3.40 ppm`.
- Harmonics match a band-limited square-wave signature: odd harmonics dominate and even harmonics are suppressed below about `-40 dBc`.
- L/R amplitude differs by about `9.30 dB` in this capture. This is tracked as the already-proven wiring/capture imbalance, not an RTL defect; both channels carry the same stable tone frequency.

## Artifacts

- `reports/phase0_rv32i_timing_closure_msim_compile.log`
- `reports/phase0_rv32i_timing_closure_msim_happy.log`
- `reports/phase0_rv32i_timing_closure_msim_nack.log`
- `reports/phase0_rv32i_timing_closure_fw_build.log`
- `reports/phase0_rv32i_timing_closure_quartus_compile.log`
- `reports/phase0_rv32i_timing_closure_programmer.log`
- `reports/phase0_rv32i_timing_closure_uart.txt`
- `reports/phase0_rv32i_timing_closure_audio_devices.log`
- `reports/phase0_rv32i_timing_closure_capture_external.wav`
- `reports/phase0_rv32i_timing_closure_audio_analysis_external.json`
- `reports/phase0_rv32i_timing_closure_audio_external.png`
- `reports/phase0_rv32i_timing_closure_capture_builtin.wav`
- `reports/phase0_rv32i_timing_closure_audio_analysis_builtin.json`

Verdict: PASS for integrated Phase 0 RV32I internal timing closure and smoke-level functional validation, with board-level I/O timing constraints and known audio clock-output warnings explicitly outside this internal closure verdict.
