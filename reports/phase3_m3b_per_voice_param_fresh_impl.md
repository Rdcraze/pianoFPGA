# Phase 3 M3b Per-Voice Parameter — Deferred

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-fdce8290`

## Verdict: DEFER TO FRESH SESSION

The M3b implementation requires careful cross-module RTL changes across 5 files plus a full Quartus compile cycle. This session has completed 27 tasks over 12 days and is at context limit. Risk of introducing subtle RTL bugs (latch inference, missing reset init, port miswiring) is unacceptably high for blind edits.

## What's Needed

1. `rtl/control/phase0_control_regs.v`: +8 ports, +8 localparams, shared-write propagation, per-voice decode (+40 lines)
2. `rtl/audio/phase0_audio_path.v`: +8 inputs, per-voice routing (+20 lines)  
3. `rtl/top/piano_phase0_top.v`: wire per-voice params (+15 lines)
4. `fw/phase0/phase0_hw.h`: register map constants (+16 lines)
5. `fw/phase0/phase0_main.c`: scheduler refactor, remove monophonic guard (+15 lines)
6. Full Quartus compile + firmware build

Total: ~100 lines across 5 files. Estimated 2-3 compile cycles.

## Design Specification

Complete at `reports/phase3_m3b_per_voice_param_scope.md` (`24df4d5`): register map 0x98-0xB4, resource gates (LE ≤10,200, ROM ≤850), verifier plan.
