# Phase 1C Measurement Hook Options Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-d7d85833`  
Implementation task: `task-33c8a281`  
Implementation artifact: `865bcee1-cb7f-4a1a-a7ab-00bdf3e005a0`  
Implementation commit: `54d3904`  
Reviewed memo: `reports/phase1c_measurement_hooks_options.md`

## Verdict

PASS.

The memo is design-only, is grounded in the accepted Phase 1C UART RX baseline, keeps future measurement hooks narrow and passive, and does not authorize blocked feature expansion. I found no required corrections.

## Scope Validation

PASS.

Commit `54d3904` adds one file only:

- `reports/phase1c_measurement_hooks_options.md`

No RTL, firmware, constraints, build scripts, project files, generated bitstreams, host tools, register behavior, UART behavior, implementation reports, or resource-affecting files were changed. `git status --short --untracked-files=normal` was clean before this validation report was written.

The memo explicitly states that no implementation is authorized and warns not to edit design, firmware, build, host, register, UART, or resource-affecting files based on the memo alone.

## Baseline Grounding

PASS.

The memo anchors itself to the accepted UART RX command-ingress baseline:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`
- Resource/timing reference: `7,963 / 10,320` LEs, `14 / 46` M9Ks, `80,896 / 423,936` memory bits, `6 / 46` DSP9s, setup slack `+2.438 ns`, hold slack `+0.406 ns`
- Frozen UART order: `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X`
- Host smoke profiles: no-command `G=6 Q=0 X=0 K=0`, six-command `G=12 Q=6 X=0 K=0`

These values match the accepted boundary-fix validation and command-ingress acceptance decision.

## Hook Discipline

PASS.

The proposed hooks are appropriate as future options:

- audio-frame cycle counter as a registered sideband at an existing boundary;
- firmware-owned CPU/report counter with ROM and cadence risk called out;
- voice busy-cycle counters with timing-path caution;
- aggregate audio-path busy or sticky indicators rather than a scheduler/dispatcher;
- underrun/overrun indicators with explicit clear-semantics risk;
- saturation/overflow counters that keep `K` as the first-line signal;
- note-event counters grounded in existing `G/J/L/N/T/U/O/Q` telemetry;
- coarse current voice state only as a snapshot extension under a future contract.

The memo consistently requires explicit future contract updates for UART/MMIO exposure and keeps new hooks passive, registered, aggregate-first, and verification-driven.

## Blocked Feature Discipline

PASS.

The memo does not authorize SDRAM, fourth voice, richer physics, exact-48k PLL work, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, host-selected parameters, codec config RX, diagnostic clear RX, sample playback, UI/TFT/touch, CPU audio-loop expansion, non-prefix UART changes, or current-range register-map changes.

It also calls out several scope-creep traps directly: hardware-dispatcher drift for busy indicators, diagnostic clear semantics for sticky bits, host-selected parameter drift for note counters, and per-note/per-parameter introspection risk for current voice state debug.

## Resource And Timing Risk

PASS with residual risk.

The qualitative risk ratings are realistic for a design-only memo:

- Firmware-derived counters are correctly treated as the lowest timing-risk path, with ROM and UART cadence as the main risks.
- A single aggregate RTL counter or sticky indicator is correctly lower risk than per-voice full-width counters.
- Hooks near the audio combinational path are correctly marked medium timing risk and require TimeQuest deltas.
- The memo avoids assuming free telemetry bandwidth or free register-map expansion.
- The future verification bundle includes ModelSim, ROM delta when firmware changes, Quartus resource and timing deltas, host smoke, hardware UART, and waveform checklist evidence.

Residual risk: the memo does not estimate numeric LE/ROM deltas for each hook. That is acceptable at this options stage, but any implementation slice should include a pre/post resource table and explicit timing slack comparison.

## Corrections

None.

## Residual Risks

- Any UART-exposed hook could accidentally disturb the frozen prefix or host parser expectations unless a contract task controls the change.
- Sticky status hooks require clear/set semantics; diagnostic clear RX remains blocked until separately authorized.
- Per-voice counters and state snapshots have the highest scope-creep risk and should be deferred unless a verifier needs per-voice attribution.
- Audio-path counters can become timing-sensitive if inserted into combinational sample logic instead of registered sideband paths.
- Additional telemetry can perturb firmware cadence, so UART timing and RX overrun evidence must be part of any future implementation.

## Recommendation

Accept the memo as design guidance only.

Go for a later implementation slice only if it is one narrow, separately authorized hook with an explicit contract and evidence bundle. The lowest-risk first slice would be a firmware-derived event/report measurement or one aggregate registered sticky indicator with fault-injection simulation, resource/timing deltas, existing host smoke PASS, waveform checklist PASS, and no UART prefix/register-map drift.

No-go for any implementation that combines multiple hooks, adds non-prefix UART tags without a contract, changes MMIO ranges, alters audio scheduling, introduces per-note/per-voice parameter state, or uses this memo as authorization for blocked features.
