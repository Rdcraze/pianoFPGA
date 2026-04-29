# Phase 1C Firmware Round-Robin Validation

Date: 2026-04-28
Agent: Codex verifier
Task: `task-45e77b49`

## Verdict

PASS.

The implementation stays inside the authorized firmware-owned round-robin scope. It uses the existing three hardware voices and existing trigger controls, preserves register behavior through `0x80`, preserves the current UART prefix through `Z/O/D/E`, appends scheduler diagnostics only after `E`, keeps the CPU out of the audio sample loop, and does not add RTL scheduler/dispatcher logic, a fourth voice, voice stealing, per-note state, per-voice parameter banks, SDRAM, richer physics, sample playback, UI, clock work, or CPU/ISA expansion.

Recommendation: promote as a narrow firmware-owned round-robin control baseline. This should not be treated as a general scheduler architecture or broader polyphony authorization.

## References

- `reports/phase1c_three_voice_abi_control_contract.md`
- `reports/phase1c_three_voice_abi_control_contract_acceptance_decision.md`
- `reports/phase1c_firmware_round_robin_impl_report.md`

## Scope Check

Changed source files are limited to:

- `fw/phase0/phase0_main.c`
- `phase1c_roundrobin_work/phase1c_round_robin_top_tb.v` as a verification-only testbench

Generated firmware/Quartus outputs were refreshed because the boot ROM image changed. The `rtl/` source timestamps remain at the accepted three-voice implementation window; no RTL, control-register, audio-path, clock, constraint, or project-source behavior edits were found.

Firmware behavior is a fixed six-event smoke:

```text
0,1,2,0,1,2
```

The policy is simple round-robin over voice0, voice1, and voice2. It does not implement input event ingress, note queues, voice stealing, per-note velocity/pitch, or per-voice parameter banks.

## Firmware And ROM

PASS.

The current generated ROM image is `318 / 1024` words:

- `fw/phase0/build/phase0.mem`: `318` lines
- `fw/phase0/build/phase0.bin`: `1272` bytes

Evidence summary: `reports/phase1c_firmware_round_robin_validation_summary.txt`

Evidence note: the implementation report references `reports/phase1c_firmware_round_robin_fw_build.log`, but that file is not present in `reports/`. This is not blocking because the current ROM artifacts, simulation results, and Quartus rebuild independently verify the built firmware image. Future implementation reports should keep the firmware build log artifact.

## Simulation

PASS.

| Check | Result | Evidence |
| --- | --- | --- |
| ModelSim compile | PASS | `reports/phase1c_firmware_round_robin_msim_compile.log`, 0 errors / 0 warnings |
| Standalone voice regression | PASS | `VOICE_TB_PASS ... peak=2082 golden_samples=4096` |
| Round-robin top simulation | PASS | `TB_RR_PASS sequence=0,1,2,0,1,2 assignments=2,2,2 rr_events=6` |
| Per-voice trigger counts | PASS | `voice_trigger_count=2`, `voice1_trigger_count=2`, `voice2_trigger_count=2` |
| Three-voice overlap | PASS | active counts `1671,1671,1671` |
| Default mix clipping | PASS | `mix_peak_level=6246`, `mix_clip_count=0` |
| UART diagnostics | PASS | scheduler diagnostics `G6,H2,J2,L2,N2,P0` |
| NACK regression | PASS | `TB_NACK_PASS fabric_status=6018053f soc_status=033f nack_count=1 stop_count=1` |

The verification-only round-robin testbench checks the current UART prefix order and appended scheduler tags:

```text
I,S,R,V,F,T,A,W,Y,U,B,C,M,K,Z,O,D,E,G,H,J,L,N,P
```

## Quartus And TimeQuest

PASS.

The bitstream changed because the boot ROM/MIF contents changed, but hardware resources and timing match the accepted three-voice baseline.

SOF SHA-256:

```text
0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0
```

Programmer checksum:

```text
0x005B95A9
```

| Metric | Accepted Three-Voice Baseline | Round-Robin Build | Result |
| --- | ---: | ---: | --- |
| Logic elements | 7,548 / 10,320 | 7,548 / 10,320 | PASS |
| Dedicated registers | 3,275 | 3,275 | PASS |
| Memory bits | 80,896 / 423,936 | 80,896 / 423,936 | PASS |
| M9Ks | 14 / 46 | 14 / 46 | PASS |
| DSP9 elements | 6 / 46 | 6 / 46 | PASS |
| PLLs | 1 / 2 | 1 / 2 | PASS |
| Slow-85C `sys_clk_50m` setup slack | +3.675 ns | +3.675 ns | PASS |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns | +0.433 ns | PASS |
| Listed TNS | 0.000 | 0.000 | PASS |

TimeQuest reports setup and hold fully constrained. M9K and DSP mapping remain consistent with the accepted three-voice baseline.

## Hardware Smoke

PASS.

Independent verifier hardware evidence:

- `reports/phase1c_firmware_round_robin_validation_pgm_list.log`
- `reports/phase1c_firmware_round_robin_validation_pgm.log`
- `reports/phase1c_firmware_round_robin_validation_uart_capture.txt`
- `reports/phase1c_firmware_round_robin_validation_audio_capture.wav`
- `reports/phase1c_firmware_round_robin_validation_audio_analysis.txt`

JTAG/programming:

- USB-Blaster detected.
- Programming passed on `EP4CE10F17@1`.
- JTAG ID: `0x020F10DD`.
- Programmer checksum: `0x005B95A9`.

UART:

Steady verifier capture includes:

```text
V=08220010
T=00000002
Y=08220010
U=00000002
M=18660010
K=00000000
Z=08220010
O=00000002
G=00000006
H=00000002
J=00000002
L=00000002
N=00000002
P=00000000
```

Interpretation:

- Existing prefix through `Z/O/D/E` is preserved.
- Scheduler diagnostics are appended after `E`.
- Six events were accepted.
- Last assigned voice is voice2.
- Voice assignment counts are `2,2,2`.
- Drop/steal count is `0`.
- Per-voice trigger counts are `2,2,2`.
- Mix clip count is `0`.

Audio:

Verifier audio analysis:

- duration `11.987 s`
- early RMS `0.02868047`
- early peak `0.14904785`
- RMS delta versus accepted three-voice verifier capture: `-0.09 dB`
- autocorrelation F0 `435.812 Hz`
- dominant spectral peak about `435.9 Hz`
- crest factor `5.197`
- clipped PCM samples: `0`

This is consistent with a clean three-voice hardware smoke and does not indicate clipping or square-wave regression.

## Residual Risks

- This is a fixed boot-time six-event smoke, not a user-input event system.
- There is still no voice stealing, event queue, per-note parameter state, velocity/pitch assignment, or external event ingress.
- The appended UART scheduler diagnostics are useful for this slice, but future tools must keep parsing by tag and must tolerate unknown future tags.
- The missing firmware build log should be corrected in future artifacts even though current ROM size and behavior are verified independently.

