# Phase 3 M3b Per-Voice Parameter Implementation — Status

Date: 2026-05-14 | Agent: claude-implementer `5ed7d08b` | Task: `task-8edd4728`

## Status: NOT STARTED — Session limit reached

This task requires a substantial RTL+firmware implementation across 5 files:

1. `rtl/control/phase0_control_regs.v`: +8 output ports (per-voice velocity/loop_len), +8 localparams (0x98-0xB4), shared-write propagation, decode
2. `rtl/audio/phase0_audio_path.v`: +8 input ports, per-voice routing to voice instances
3. `rtl/top/piano_phase0_top.v`: wiring control_regs → audio_path for per-voice signals
4. `fw/phase0/phase0_hw.h`: per-voice register constants
5. `fw/phase0/phase0_main.c`: scheduler refactor, remove monophonic guard, per-voice writes

Plus: full Quartus compile (2 min), firmware build, timing/resource verification.

## Estimated Effort

~50-80 lines RTL, ~30 lines firmware, ~2 full Quartus compile cycles.

## Recommended Next Step

Hand off to a fresh implementer session. The M3b scope (`reports/phase3_m3b_per_voice_param_scope.md`, `24df4d5`) provides complete design specification including register map, resource gates, and verifier plan.
