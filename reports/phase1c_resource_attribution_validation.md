# Phase 1C Resource Attribution Proposal Validation

Verifier: Codex verifier agent  
Task: `task-4b1885eb`  
Date: 2026-04-28  
Verdict: PASS

## Scope

This is a review-only validation of `reports/phase1c_resource_attribution_and_hardening_proposal.md` against the hardware-accepted two-voice Phase 1 baseline and the Quartus resource/timing evidence in the repository.

No RTL, firmware, constraints, clocking, project, register map, or SOF changes were made for this validation.

## Evidence Reviewed

- `reports/phase1c_resource_attribution_and_hardening_proposal.md`
- `reports/phase1_next_scaling_architecture_options.md`
- `reports/phase1_two_voice_hardware_acceptance_decision.md`
- `reports/phase1_two_voice_hardware_smoke.md`
- `reports/phase1_two_voice_validation.md`
- `reports/phase1_two_voice_impl_report.md`
- `quartus/phase0/output_files/piano_phase0_top.fit.summary`
- `quartus/phase0/output_files/piano_phase0_top.sta.summary`
- `reports/phase1_timing_margin_impl_report.md`
- `reports/phase1_timing_margin_acceptance_decision.md`
- `fw/phase0/build/phase0.map`
- `fw/phase0/build.ps1`
- `fw/phase0/link.ld`
- `rtl/audio/phase0_audio_path.v`
- `rtl/audio/phase1_reduced_voice.v`
- `rtl/control/phase0_control_regs.v`
- `rtl/control/phase0_boot_rom.v`
- `rtl/control/phase0_data_ram.v`

## Baseline Cross-Check

The proposal correctly anchors on the hardware-accepted two-voice SOF and does not reinterpret an exploratory or stale build as the baseline.

| Metric | Proposal | Quartus / accepted baseline | Result |
| --- | ---: | ---: | --- |
| Logic elements | 7366 / 10320 | 7366 / 10320 | Match |
| Dedicated registers | 3580 | 3580 | Match |
| Memory bits | 271360 / 423936 | 271360 / 423936 | Match |
| M9Ks | 34 / 46 | 34 / 46 | Match |
| DSP9 elements | 4 / 46 | 4 / 46 | Match |
| PLLs | 1 / 2 | 1 / 2 | Match |
| `sys_clk_50m` setup slack | +3.957 ns | +3.957 ns | Match |
| `sys_clk_50m` hold slack | +0.432 ns | +0.432 ns | Match |
| Fmax | 62.33 MHz | 62.33 MHz | Match |
| SOF checksum | `0x00553670` | `0x00553670` | Match |

The SOF SHA-256 referenced by the proposal also matches the accepted two-voice smoke evidence: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`.

## Resource Attribution Validation

The hierarchy attribution in the proposal is consistent with the accepted Quartus fit summary:

| Block | Logic cells | Registers | Memory bits | M9Ks | DSP9 | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Top design | 7366 | 3580 | 271360 | 34 | 4 | Match |
| RV32I SoC | 3586 | 1278 | 262144 | 32 | 0 | Match |
| RV32I core | 3423 | 1242 | 0 | 0 | 0 | Match |
| Boot ROM | 0 | 0 | 131072 | 16 | 0 | Match |
| Data RAM | 1 | 0 | 131072 | 16 | 0 | Match |
| Audio path | 3019 | 1959 | 9216 | 2 | 4 | Match |
| Voice 0 | 1316 | 843 | 4608 | 1 | 2 | Match |
| Voice 1 | 1316 | 843 | 4608 | 1 | 2 | Match |
| Control registers | 542 | 172 | 0 | 0 | 0 | Match |
| Codec stub subtree | 266 | 169 | 0 | 0 | 0 | Match |

The proposal's interpretation of the memory use is also correct. The accepted build contains a 4096 x 32 boot ROM and a 4096 x 32 data RAM, each consuming 131072 bits and 16 M9Ks. Each reduced voice contains two logical 128 x 18 delay-line memories, but Quartus packs those into one physical M9K per voice. Therefore, the current M9K pressure is dominated by firmware ROM/RAM sizing rather than by the two audio voices.

The DSP interpretation is correct. Each `phase1_reduced_voice` instance contains one signed 18-bit multiplier that maps to two DSP9 elements, for four DSP9 elements total across two voices.

## Proposal Assessment

The proposal is scope disciplined. It explicitly avoids RTL, firmware, constraints, clock, register-map, project, and SOF changes in the attribution report itself. It also does not authorize a third voice, a scheduler, SDRAM, sample playback, richer physics, a larger CPU, or clock changes as part of the next step.

Candidate Slice 1, ROM/RAM right-sizing, is a valid low-risk next implementation slice if the goal is to recover M9K headroom and reduce avoidable memory pressure. The repository evidence supports the proposal's premise: the firmware image is under 1 KiB while both ROM and RAM are currently provisioned as 16 KiB memories. The proposal correctly requires linker, MIF, boot ROM, data RAM, simulation, Quartus, TimeQuest, and hardware UART/audio smoke coverage for that slice.

Candidate Slice 2, replacing the per-voice 32-sample body shift register with bit-exact tap storage, is a plausible later LE/register reduction slice. The source confirms that the reduced voice keeps a 32-entry signed body pipe while only taps 6, 16, and 30 are consumed. The proposal correctly treats this as medium risk and requires bit-exact validation before relying on it.

The "not recommended next" list is appropriate. The accepted baseline is already high on logic utilization, and a third voice or broader feature work would spend timing and routing margin before the avoidable memory and per-voice storage costs have been addressed.

## Risk Notes

- ROM/RAM right-sizing should not be interpreted as sufficient authorization for a third voice. It reduces M9K use but does not materially reduce the LE pressure that currently dominates the third-voice risk.
- Any memory-size implementation must keep firmware image bounds, stack placement, linker lengths, MIF depth, address decode behavior, and reset behavior aligned.
- Body-pipe optimization must be isolated from ROM/RAM right-sizing. It changes sequential audio state and needs golden signature or bit-exact waveform checks before hardware acceptance.
- The currently accepted hardware baseline remains the two-voice SOF with checksum `0x00553670`. No newer build should replace that baseline without a full hardware acceptance pass.

## Recommendation

PASS the Phase 1C resource attribution proposal.

Proceed with Candidate Slice 1 only as a narrow memory-hardening implementation if the orchestrator wants immediate low-risk headroom cleanup. Keep Candidate Slice 2 as a separate follow-up if LE/register headroom is required before any third-voice work. Continue to hold third voice, scheduler, SDRAM, richer synthesis features, and clock changes until those narrower slices have been implemented and revalidated on hardware.
