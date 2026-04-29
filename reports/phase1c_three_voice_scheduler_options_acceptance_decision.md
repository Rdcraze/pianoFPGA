# Phase 1C Three-Voice Scheduler Options Acceptance Decision

Date: 2026-04-28
Agent: Codex orchestrator
Task: `task-3e2bbf31`

## Decision

Accept `reports/phase1c_three_voice_scheduler_options.md` as the current scheduler/control design memo for the accepted Phase 1C three-voice baseline.

The verifier report at `reports/phase1c_three_voice_scheduler_options_validation.md` is also accepted. Verdict: PASS. The memo stayed design-only, fairly compared firmware round-robin, hardware note-event dispatch, and hold/control-hardening options, and its recommendation is consistent with the current resource and timing posture.

## Current Baseline

The current accepted hardware baseline remains the narrow three-voice feasibility build:

| Metric | Accepted Three-Voice Build |
| --- | ---: |
| Logic elements | 7,548 / 10,320 |
| Dedicated registers | 3,275 |
| Memory bits | 80,896 / 423,936 |
| M9Ks | 14 / 46 |
| DSP9 elements | 6 / 46 |
| Slow-85C `sys_clk_50m` setup slack | +3.675 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns |
| Slow-85C `sys_clk_50m` Fmax | 61.26 MHz |

The prior third-voice stop gate was `8,200` LEs. The accepted build has only `652` LEs of margin below that gate, so the project should not spend logic on a hardware scheduler before the control contract is tighter.

## Interpretation

Firmware-triggered round-robin is the preferred first scheduler implementation direction, but it is not authorized yet. It has the lowest FPGA risk because it can use the existing three voice trigger controls and keep the CPU in the low-rate note-event path, outside the audio sample loop.

A small hardware note-event dispatcher remains deferred. It may become appropriate later if external event ingress needs a hardware-owned queue/acceptance contract, but it would consume scarce LE headroom and create a new hardware interface before the ABI is stable.

Holding at three voices for ABI/control hardening is the right immediate next step. The next task should document the current three-voice register/UART ABI, define the post-`0x80` scheduler diagnostic contract, and turn the verifier's go/no-go gates into implementation-ready acceptance criteria.

## Authorized Next Step

Authorize a short design/documentation hardening task only:

- document the current three-voice register map and UART stream as the baseline ABI;
- identify which diagnostics are architectural versus smoke-test-only;
- define prefix-compatibility requirements for UART consumers;
- reserve future scheduler/control additions after the current `0x80` map;
- define required scheduler observability: event count, selected voice, per-voice assignment counts, drop/steal count, clip count, and last error/status;
- produce pass/fail criteria for a later firmware-owned round-robin implementation.

No RTL, firmware, constraints, clocking, register-map behavior, or hardware build changes are authorized by this decision.

## Still Gated

Do not authorize these until a later explicit decision:

- scheduler implementation;
- hardware dispatcher;
- fourth voice or broader polyphony;
- SDRAM;
- richer physical model;
- sample playback;
- UI/TFT/touch work;
- exact-48-kHz clock/PLL work;
- larger CPU or ISA expansion;
- voice stealing, per-note state, or per-voice parameter banks;
- register changes before `0x80`;
- non-prefix-compatible UART changes;
- CPU participation in the audio sample loop.

## Required Gates For Later Firmware Round-Robin

If a later decision authorizes firmware-owned round-robin, that task must require:

- firmware build and ROM-size check within the configured `1024` words;
- current standalone voice regression;
- top simulation with at least six note events showing `0,1,2,0,1,2` assignment;
- per-voice trigger counts matching assignment counts;
- proof that all three voices overlap;
- default smoke case with `mix_clip_count=0`;
- UART prefix through `V,F,T,A,W,Y,U,B,C,M,K` preserved;
- current `Z,O,D,E` voice2 frames preserved;
- any new diagnostics appended after the current frame/register set;
- NACK regression;
- hardware UART smoke, plus audio smoke if event cadence is intended to be audible.

If any RTL changes are proposed, the task also needs full Quartus/TimeQuest evidence, `<= 8,200` LEs, `sys_clk_50m` setup slack `>= +1.0 ns`, fully constrained setup/hold, all listed TNS values at `0.000`, and no M9K/DSP mapping regression without separate authorization.

## Disposition

Proceed to the ABI/control-hardening memo. Hold scheduler implementation and all feature expansion until that memo is complete, validated, and accepted.
