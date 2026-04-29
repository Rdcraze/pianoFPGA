# Phase 1C Three-Voice ABI/Control Contract Acceptance Decision

Date: 2026-04-28
Agent: Codex orchestrator
Task: `task-8d500139`

## Decision

Accept `reports/phase1c_three_voice_abi_control_contract.md` as the Phase 1C three-voice ABI/control gate document.

Accepted validation inputs:

- `reports/phase1c_three_voice_abi_control_contract_validation.md`: PASS, with one non-blocking UART-MMIO documentation cleanup requested.
- `reports/phase1c_three_voice_abi_control_contract_cleanup_validation.md`: PASS, cleanup verified.

The contract now documents the accepted three-voice register map, UART stream, diagnostic classifications, parser rules, future post-`0x80` scheduler reservations, and go/no-go gates for a later firmware-owned round-robin implementation. The UART-MMIO row now explicitly lists `0x00` TX data and `0x04` status, resolving the only noted ambiguity.

## Current Accepted Baseline

The hardware baseline remains the accepted Phase 1C three-voice feasibility build:

| Metric | Accepted Three-Voice Build |
| --- | ---: |
| SOF SHA-256 | `91784AE1B85E69F989D4CD09273466E14A6FAB66A557AD8ACDA296F990A07A0E` |
| Programmer checksum | `0x005B2137` |
| Logic elements | 7,548 / 10,320 |
| Dedicated registers | 3,275 |
| Memory bits | 80,896 / 423,936 |
| M9Ks | 14 / 46 |
| DSP9 elements | 6 / 46 |
| Slow-85C `sys_clk_50m` setup slack | +3.675 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns |
| Slow-85C `sys_clk_50m` Fmax | 61.26 MHz |

The current feasibility gate remains `8,200` LEs and `sys_clk_50m` setup slack `>= +1.0 ns` for any bitstream-changing work.

## Accepted ABI Rules

The following rules are now binding for the next scheduler/control work:

- current control-register offsets through `0x80` are preserved;
- future scheduler/control registers, if separately authorized, start at `0x84` or later;
- UART consumers must parse by tag, tolerate unknown tags, and not depend on fixed total frame count;
- existing UART tags and order remain prefix-compatible: `I/S/R`, then `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`;
- exact smoke values are validation signatures, not permanent software ABI constants;
- scheduler observability is defined before implementation: event count, selected voice, per-voice assignment counts, drop/steal count, clip count, and last error/status.

## Authorized Next Slice

Authorize one narrow implementation task: firmware-owned round-robin over the existing three voices.

Allowed scope:

- firmware policy only, using existing voice0/voice1/voice2 trigger controls;
- preserve existing RTL behavior and register offsets through `0x80`;
- keep the CPU out of the audio sample loop;
- prove six-event assignment sequence `0,1,2,0,1,2`;
- preserve existing UART prefix frames through `Z/O/D/E`;
- append any firmware diagnostics only after the current stream;
- keep ROM image within the configured `1024` words;
- rebuild and verify the accepted bitstream if MIF contents change.

This authorization does not require or authorize a hardware dispatcher.

## Required Evidence For The Firmware Round-Robin Slice

The implementation report must include:

- changed files and exact firmware policy behavior;
- firmware build and ROM-size evidence within `1024` words;
- current standalone voice regression;
- top simulation with at least six events proving `0,1,2,0,1,2`;
- per-voice trigger counts matching assignment counts;
- proof all three voices can overlap;
- default smoke case with `mix_clip_count=0`;
- UART prefix compatibility through `V,F,T,A,W,Y,U,B,C,M,K,Z,O,D,E`;
- NACK regression;
- Quartus full compile and TimeQuest if MIF or RTL/project output changes;
- hardware UART smoke, plus audio smoke if event cadence is audible.

If any RTL change is proposed, stop and request a separate authorization before proceeding.

## Still Gated

The following remain explicitly blocked:

- hardware note-event dispatcher;
- fourth voice or broader polyphony;
- SDRAM;
- richer physics;
- sample playback;
- UI/TFT/touch work;
- exact-48-kHz clock or PLL work;
- larger CPU or ISA expansion;
- voice stealing;
- per-note state;
- per-voice parameter banks;
- register changes before `0x84`;
- non-prefix-compatible UART behavior;
- CPU participation in the audio sample loop.

## Disposition

Proceed to the narrow firmware-owned round-robin implementation task and paired verifier validation. Treat the accepted ABI/control contract as the reference for scope and evidence.
