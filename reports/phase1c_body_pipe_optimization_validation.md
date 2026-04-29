# Phase 1C-B Body-Pipe Optimization Validation

Verifier: Codex verifier agent  
Task: `task-0d8a2558`  
Date: 2026-04-28  
Verdict: PASS

## Scope

This validation checked the Phase 1C-B reduced-voice body-pipe/tap-storage optimization against the authorized narrow behavior-preserving hardening slice.

No verifier-side RTL, firmware, constraints, clocking, register-map, or behavior changes were made. Additional verifier evidence files were generated under `reports/` only.

## References

- `reports/phase1c_body_pipe_optimization_authorization_decision.md`
- `reports/phase1c_rom_ram_rightsizing_acceptance_decision.md`
- `reports/phase1c_body_pipe_optimization_impl_report.md`
- `quartus/phase0/output_files/piano_phase0_top.fit.summary`
- `quartus/phase0/output_files/piano_phase0_top.fit.rpt`
- `quartus/phase0/output_files/piano_phase0_top.sta.summary`
- `quartus/phase0/output_files/piano_phase0_top.sta.rpt`

## Result

PASS. The implementation stayed within the authorized body-pipe/tap-storage scope and preserved the accepted two-voice register, UART, ROM/RAM, clock, sample-rate, mixer, delay-line, and multiplier contracts.

I recommend promoting this build as the current accepted baseline. The acceptance should explicitly record the resource tradeoff: it recovers substantial LE/register headroom and spends two additional M9Ks versus the Phase 1C-A baseline.

## Scope Discipline

The implementation is narrow and matches the Phase 1C-B authorization:

- `rtl/audio/phase1_reduced_voice.v` replaces the per-voice 32-entry shifting `body_pipe` with M9K-backed circular tap storage.
- `rtl/audio/phase1_reduced_voice_tb.v` adds the golden-sample comparison path.
- `rtl/audio/phase1_reduced_voice_golden_samples.hex` contains the 4096-sample golden trace.
- Generated build/simulation/Quartus/hardware collateral was refreshed under `reports/`, `phase1c_bodypipe_work/`, `quartus/phase0/`, and firmware build output paths.

No evidence was found of a third voice, scheduler, SDRAM, richer physics, coefficient/default change, sample playback, UI, larger CPU, clock/PLL/sample-rate change, register-map expansion, UART expansion, diagnostic removal, ROM/RAM sizing change, or unrelated cleanup in this slice.

ROM/RAM sizing remains at the accepted Phase 1C-A envelope:

- ROM: `1024 x 32`, `4 KiB`, base `0x0000_0000`
- RAM: `1024 x 32`, `4 KiB`, base `0x0001_0000`
- Control registers: `0x4000_0000`
- UART MMIO: `0x4000_1000`

## RTL Behavior Check

The current voice RTL removes the old shifting body pipe and uses:

- `(* ramstyle = "M9K" *) reg signed [17:0] body_history [0:31]`
- `body_wr_ptr` as a circular write pointer
- pre-write tap addresses:
  - `body_wr_ptr - 5'd7`
  - `body_wr_ptr - 5'd17`
  - `body_wr_ptr - 5'd31`
- the unchanged body mix expression:
  - `(tap6 >>> 2) - (tap16 >>> 3) + (tap30 >>> 4)`, then scaled by `body_mix_q15`

This matches the intended replacement for old `body_pipe[6]`, `body_pipe[16]`, and `body_pipe[30]` timing. The added body wait/tap states remain inside the existing sample interval and do not add a CPU dependency.

The RTL still preserves the existing `body_bypass` and `disp_bypass` branches. The golden regression covers the default active body path; future non-default body/disp bypass combinations should continue to be treated as regression-sensitive if they become product-facing.

## Behavior Evidence

The standalone golden evidence is strong enough for this change:

| Test | Evidence | Result |
| --- | --- | --- |
| Golden trace generation | `reports/phase1c_body_pipe_golden_write.log` | PASS, `4096` samples written from the pre-optimization reference |
| Golden sample count | `rtl/audio/phase1_reduced_voice_golden_samples.hex` | `4096` lines |
| Voice regression | `reports/phase1c_body_pipe_msim_voice.log` | PASS, `4096` golden samples matched |
| Top happy path | `reports/phase1c_body_pipe_msim_happy.log` | PASS, two-voice/mix signature preserved |
| Top NACK path | `reports/phase1c_body_pipe_msim_nack.log` | PASS, NACK/stop behavior preserved |
| Firmware build | `reports/phase1c_body_pipe_fw_build.log` | PASS |

The preserved standalone voice signature is:

```text
VOICE_TB_PASS first_nonzero_sample=106 freq=438.084112 rms_100ms=292.703180 rms_500ms=35.578467 rms_3s=0.000000 peak=2082 golden_samples=4096
```

The preserved top happy-path signature includes:

```text
voice_peak_level=2082 voice1_peak_level=2082 mix_peak_level=4164 voice_trigger_count=1 voice1_trigger_count=1 mix_clip_count=0 uart_capture_count=111
```

## Resource And Timing Comparison

Resource and timing numbers match the current Quartus reports and the implementation report.

| Metric | Phase 1C-A Accepted Baseline | Phase 1C-B Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | 7,382 / 10,320 | 6,474 / 10,320 | -908 |
| Dedicated registers | 3,580 | 2,748 | -832 |
| Memory bits | 74,752 / 423,936 | 75,776 / 423,936 | +1,024 |
| M9Ks | 10 / 46 | 12 / 46 | +2 |
| DSP9 elements | 4 / 46 | 4 / 46 | 0 |
| PLLs | 1 / 2 | 1 / 2 | 0 |
| Slow 85C `sys_clk_50m` setup slack | +3.214 ns | +3.907 ns | +0.693 ns |
| Slow 85C `sys_clk_50m` hold slack | +0.433 ns | +0.432 ns | -0.001 ns |
| Slow 85C `sys_clk_50m` Fmax | 59.57 MHz | 62.14 MHz | +2.57 MHz |

TimeQuest remains fully constrained with all listed TNS values at `0.000`.

The current slow-85C Fmax summary is:

- `sys_clk_50m`: `62.14 MHz`
- `i2c_clk`: `178.48 MHz`
- `audio_bclk`: `28.13 MHz`

## Mapping Check

Preserved mapping:

- Boot ROM remains `1024 x 32`, `32768` bits, `4` M9Ks, initialized from `phase0_fw.mif`.
- Data RAM remains `1024 x 32`, `32768` bits, `4` M9Ks.
- Each voice delay line remains synchronous M9K-backed storage.
- Each voice multiplier remains a signed 18-bit simple multiplier using `2` DSP9 elements.
- Total DSP use remains `4 / 46` DSP9 elements.

Corrected interpretation:

- RTL declares `body_history` as signed `[17:0]`, but the Quartus RAM summary physically packs each body-history memory as `32 x 16`, `512` bits, `1` M9K.
- This is not a functional failure: the 4096-sample golden comparison, top simulations, and hardware smoke all preserve the accepted behavior.
- The resource accounting should use the fitted value: two additional `512`-bit body-history RAMs, one per voice, costing two physical M9Ks total.

Per-voice post-fit resource point:

| Block | Logic cells | Registers | Memory bits | M9Ks | DSP9 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Voice 0 | 864 | 427 | 5,120 | 2 | 2 |
| Voice 1 | 869 | 427 | 5,120 | 2 | 2 |

## Independent Hardware Smoke

Verifier hardware evidence was collected independently after reviewing the submitted implementation evidence.

Build identity:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- SHA-256: `48BAB4ACBAD44899E5FB8E25B89496B4E4A8C1AFEF0CF110178EB8C481849510`
- Programmer checksum: `0x0050ADE7`

JTAG:

- `USB-Blaster [USB-0]` was visible.
- Programming succeeded on `EP4CE10F17@1`.
- JTAG ID code observed: `0x020F10DD`.
- Evidence:
  - `reports/phase1c_body_pipe_optimization_validation_pgm_list.log`
  - `reports/phase1c_body_pipe_optimization_validation_pgm.log`
  - `reports/phase1c_body_pipe_optimization_validation_pgm_during_uart.log`
  - `reports/phase1c_body_pipe_optimization_validation_pgm_during_audio.log`

UART on `COM5`, `115200 8N1`, captured startup and recurring diagnostics. The capture includes one pre-reprogram steady frame followed by the fresh startup sequence and steady body-pipe build frames:

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

Evidence: `reports/phase1c_body_pipe_optimization_validation_uart_capture.txt`.

Audio:

- External Realtek capture succeeded using the DirectShow alternative device ID.
- Evidence:
  - `reports/phase1c_body_pipe_optimization_validation_audio_capture.wav`
  - `reports/phase1c_body_pipe_optimization_validation_audio_ffmpeg.log`
  - `reports/phase1c_body_pipe_optimization_validation_audio_analysis.txt`
- Analysis result:
  - duration `11.987 s`
  - event onset `3.740 s`
  - mono F0 `435.512 Hz`
  - mono early RMS `0.023312`
  - mono early peak `0.081100`
  - mono crest factor `3.479`
  - total clipped samples `0`
  - no square-wave regression indicated

The independent hardware smoke agrees with the implementation report and with the accepted two-voice behavior.

## Residual Risks

- This optimization intentionally trades two M9Ks for LE/register headroom. That is acceptable after Phase 1C-A's ROM/RAM right-sizing, but it should be recorded as a deliberate baseline tradeoff.
- The bit-exact proof is for the 4096-sample default voice trace plus top-level happy/NACK tests. Future coefficient/default changes or broader body/disp bypass use should rerun targeted regressions.
- This acceptance should not authorize third voice, scheduler, SDRAM, richer physics, sample playback, UI, larger CPU, clock/PLL/sample-rate work, register-map expansion, UART expansion, or diagnostic removal.
- Phase 1C-A remains the fallback baseline if the project later decides the two-M9K body-history cost is unacceptable.

## Recommendation

Promote the Phase 1C-B body-pipe/tap-storage optimized build to the current accepted baseline.

The promotion should be narrow: accept the same two-voice behavior with materially lower LE/register use and two additional M9Ks. Keep all feature-expansion gates in place.
