# Phase 1C Firmware Round-Robin Acceptance Decision

Date: 2026-04-28
Agent: Codex orchestrator
Task: `task-36ef6941`

## Decision

Promote the Phase 1C firmware-owned round-robin build as the current narrow three-voice control baseline.

Accepted inputs:

- Implementation report: `reports/phase1c_firmware_round_robin_impl_report.md`
- Verifier report: `reports/phase1c_firmware_round_robin_validation.md`
- Implementation artifact: `5e2b58d6-48bb-437f-8681-4a921a12eafd`
- Validation artifact: `6f989b9c-1326-4b88-aedc-1f64a93a4a96`

Verifier verdict: PASS. The implementation stayed within the authorized firmware-owned scope and passed simulation, build, timing, UART, and hardware audio evidence.

## Promoted Build Identity

| Metric | Firmware Round-Robin Build |
| --- | ---: |
| SOF SHA-256 | `0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0` |
| Programmer checksum | `0x005B95A9` |
| Logic elements | 7,548 / 10,320 |
| Dedicated registers | 3,275 |
| Memory bits | 80,896 / 423,936 |
| M9Ks | 14 / 46 |
| DSP9 elements | 6 / 46 |
| PLLs | 1 / 2 |
| Slow-85C `sys_clk_50m` setup slack | +3.675 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns |
| Listed TNS | 0.000 |
| Firmware ROM image | 318 / 1024 words |

Resource and timing posture is unchanged from the accepted three-voice hardware baseline. The SOF identity changed because the boot ROM/MIF contents changed.

## Accepted Behavior

The promoted build implements a fixed firmware-owned six-event round-robin smoke:

```text
0,1,2,0,1,2
```

Accepted evidence:

- assignment counts are `2,2,2`;
- per-voice trigger counts are `2,2,2`;
- all three voices overlap;
- default mix peak remains `6246`;
- `mix_clip_count=0`;
- UART prefix through `I/S/R` and `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E` is preserved;
- scheduler diagnostics are appended after `E` as `G/H/J/L/N/P`;
- hardware UART smoke reports `G=6`, `H=2`, `J=2`, `L=2`, `N=2`, `P=0`;
- hardware audio smoke is clean, unclipped, and consistent with the prior three-voice capture.

## Scope Boundary

This is not a general scheduler architecture. It does not provide:

- user-input event ingress;
- event queueing;
- voice stealing;
- per-note velocity or pitch state;
- per-voice parameter banks;
- hardware dispatch;
- fourth voice or broader polyphony;
- SDRAM-backed content;
- sample playback;
- richer physics;
- UI/TFT/touch integration.

The CPU remains in the low-rate note-event/control path and outside the audio sample loop.

## Residual Risks

- The behavior is a fixed boot-time six-event smoke, not an interactive instrument input path.
- New UART scheduler tags are useful diagnostics, but consumers must continue parsing by tag and tolerating unknown future tags.
- The implementation report referenced a firmware build log path that was not present in `reports/`; verifier judged this non-blocking because ROM size, generated artifacts, simulations, Quartus, and hardware behavior independently verified the build.
- The project still has only modest LE margin under the `8,200` feasibility gate, so hardware scheduler or dispatcher work remains risky without a separate resource budget.

## Still Gated

Do not proceed without a separate orchestrator decision for:

- hardware note-event dispatcher;
- fourth voice or broader polyphony;
- SDRAM;
- richer physical model;
- sample playback;
- UI/TFT/touch work;
- exact-48-kHz clock or PLL work;
- larger CPU or ISA expansion;
- voice stealing;
- per-note state;
- per-voice parameter banks;
- register changes before `0x84`;
- non-prefix-compatible UART changes;
- CPU participation in the audio sample loop.

## Recommended Next Step

Move to a design-only event-ingress/control options memo. The next decision should compare how real note events enter this firmware-owned control path without implementing anything yet.

At minimum, compare:

- UART RX command ingress;
- board-button or simple GPIO test ingress;
- host-driven debug protocol over existing UART infrastructure;
- holding at fixed boot smoke while adding parser/test tooling.

No event-ingress implementation is authorized by this decision.
