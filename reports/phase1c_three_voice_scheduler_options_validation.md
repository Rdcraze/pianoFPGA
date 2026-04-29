# Phase 1C Scheduler/Control Options Memo Validation

Date: 2026-04-28
Agent: Codex verifier
Task: `task-ce6bfae9`

## Verdict

PASS.

The implementer memo at `reports/phase1c_three_voice_scheduler_options.md` stayed design-only and did not authorize or perform scheduler implementation. It fairly compares firmware-triggered round-robin, a small hardware note-event dispatcher, and a hold/control-hardening option. Its recommendation is aligned with the accepted three-voice baseline: do not proceed to a hardware dispatcher or fourth voice next; first stabilize the three-voice control contract, then consider a narrow firmware-owned round-robin slice.

## Inputs Checked

- Design memo artifact: `5b9d1112-af9b-4c79-a9d6-4b3e7bcea703`
- Memo path: `reports/phase1c_three_voice_scheduler_options.md`
- Accepted three-voice decision: `reports/phase1c_third_voice_acceptance_decision.md`
- Verifier baseline evidence: `reports/phase1c_third_voice_validation.md`

## Design-Only Scope

PASS.

The memo explicitly states that it changes no RTL, firmware, constraints, scripts, register maps, or diagnostics. A timestamp review of implementation directories found no RTL, firmware, or constraint edits associated with the memo task; the new item after the third-voice acceptance decision is the memo report itself.

The memo keeps these items gated:

- scheduler implementation;
- fourth voice;
- SDRAM;
- richer physical model;
- sample playback;
- exact-48-kHz clock/PLL work;
- larger CPU or ISA expansion;
- UI/TFT/touch;
- broad register-map churn;
- diagnostic removal;
- non-prefix-compatible UART changes.

## Baseline Alignment

PASS.

The memo uses the accepted three-voice build identity and resource/timing posture correctly:

| Metric | Accepted Three-Voice Baseline |
| --- | ---: |
| Logic elements | 7,548 / 10,320 |
| Dedicated registers | 3,275 |
| Memory bits | 80,896 / 423,936 |
| M9Ks | 14 / 46 |
| DSP9 elements | 6 / 46 |
| Slow-85C `sys_clk_50m` setup slack | +3.675 ns |
| Slow-85C `sys_clk_50m` hold slack | +0.433 ns |
| Slow-85C `sys_clk_50m` Fmax | 61.26 MHz |

The memo correctly notes the remaining `652` LE margin below the prior `8,200` LE stop gate. That point is central to its recommendation to avoid spending FPGA headroom on a hardware dispatcher before the event/control contract is mature.

## Option Review

PASS.

Firmware round-robin is treated as the lowest FPGA-risk implementation path. The memo keeps it low-rate and firmware-owned, uses existing voice trigger controls, and defers stealing, per-note envelopes, per-voice parameter banks, and richer policy.

Hardware dispatcher is treated as a later option with medium resource risk. The memo correctly identifies the control-path, register, counter, arbitration, and scope-creep costs, and does not recommend authorizing it next.

Hold/control-hardening is presented as the safest immediate next step. This is consistent with the accepted baseline's limited LE headroom and the need to define ABI/UART observability before implementation.

## Required Go/No-Go Criteria

Any subsequent scheduler/control implementation task should carry these gates explicitly.

Go only if the task is limited to one of these approved scopes:

- documentation/ABI hardening only; or
- a firmware-owned round-robin prototype over the existing three voices; or
- a separately authorized, tightly bounded post-`0x80` diagnostic addition.

No-go if the implementation requires any of the following:

- fourth voice, extra voice RAM/DSP, SDRAM, richer model, sample playback, UI, exact-48-kHz clock work, larger CPU/ISA, or broad cleanup;
- non-prefix-compatible UART changes;
- register changes before `0x80` or removal of existing diagnostics;
- CPU participation in the audio sample loop;
- voice stealing, per-note state, per-voice parameter banks, or hardware dispatcher logic unless separately authorized.

Required evidence for a firmware round-robin slice:

- firmware build and ROM-size check, still within `1024` configured words;
- current standalone voice regression;
- top simulation with at least six note events proving assignment sequence `0,1,2,0,1,2`;
- per-voice trigger counts matching assignment counts;
- proof that all three voices can overlap;
- expected mix behavior with `mix_clip_count=0` for the default smoke case;
- existing UART prefix through `V,F,T,A,W,Y,U,B,C,M,K` preserved;
- appended `Z,O,D,E` voice2 frames preserved;
- any new diagnostics appended only after the current frame/register set;
- NACK regression;
- hardware UART smoke, and audio smoke if the event cadence is intended to be audible.

Required evidence if any RTL is changed:

- Quartus full compile and TimeQuest;
- LE use remains `<= 8,200 / 10,320`;
- Slow-85C `sys_clk_50m` setup slack remains `>= +1.0 ns`;
- setup and hold remain fully constrained;
- all listed TNS values remain `0.000`;
- M9K mapping does not regress from `14 / 46` unless explicitly authorized;
- DSP9 mapping does not regress from `6 / 46` unless explicitly authorized;
- existing three-voice hardware UART/audio smoke still passes.

## Recommendation

Accept the memo as a valid design-only decision memo.

Recommended next action: authorize a short three-voice ABI/control-hardening task before any scheduler implementation. After that, a narrow firmware-triggered round-robin prototype is the preferred first implementation slice. Hold hardware dispatcher work until the project has a concrete external event-ingress need and a separately approved resource budget.

