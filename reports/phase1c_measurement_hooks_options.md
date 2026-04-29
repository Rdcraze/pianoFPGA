# Phase 1C Measurement Hook Options

Date: 2026-04-29
Agent: Codex implementer
Task: `task-33c8a281`

## Scope

This is a design-only options memo for the accepted Phase 1C UART RX command-ingress baseline.

No implementation is authorized here. Do not edit RTL, firmware, constraints, build scripts, project files, generated bitstreams, host tools, register behavior, UART behavior, or resource-affecting files based on this memo alone.

Accepted baseline anchors:

- SOF SHA-256: `CAB259BC697ABB5F76AD48120AE4CD65AB1FD4311FC9AEA59F620868E3F3D7F5`
- Programmer checksum: `0x005F102E`
- Resource/timing reference: `7,963 / 10,320` LEs, `14 / 46` M9Ks, `80,896 / 423,936` memory bits, `6 / 46` DSP9s, slow-85C `sys_clk_50m` setup slack `+2.438 ns`, hold slack `+0.406 ns`
- Frozen UART order: `I/S/R/V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X`
- Host smoke profile: no-command `G=6 Q=0 X=0 K=0`; six-command `G=12 Q=6 X=0 K=0`

## Non-Goals

This memo does not authorize SDRAM, fourth voice, richer physics, exact-48k PLL, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, host-selected parameters, codec config RX, diagnostic clear RX, sample playback, UI/TFT/touch, CPU audio-loop expansion, non-prefix UART changes, or register-map changes before current accepted ranges.

Any future hook must preserve the current audio/UART baseline unless a new explicit implementation task updates the contract and re-runs the full evidence bundle.

## Option Matrix

| Hook | Preferred location | Qualitative risk | Verification needed before implementation |
| --- | --- | --- | --- |
| Audio-frame cycle counter | RTL counter sampled at existing audio frame/sample boundary; expose through firmware telemetry only after an explicit contract update | Low to medium LE risk for a 32-bit counter and snapshot register; low memory risk; timing risk low if counter stays in `sys_clk_50m` domain and only snapshots at existing boundaries | ModelSim proves monotonic counter and stable snapshot timing; Quartus resource/timing delta; UART no-command/commanded profiles unchanged or contract-updated; waveform checklist still PASS |
| CPU cycles per report/sample service | Firmware-owned counter using existing timer-like loop points, emitted in UART telemetry only if a new prefix-compatible tag is accepted | Low resource risk if firmware-only; ROM risk low to medium; no RTL timing risk; can perturb firmware report timing if sampled too often | Firmware build ROM delta; host parser/tool update; UART cadence comparison; no change to audio waveform gates; no RX overrun while reporting |
| Voice busy-cycle counters | RTL or firmware snapshot around each existing voice trigger/decay activity window | Medium LE risk for per-voice counters; memory risk low; timing risk medium if placed in voice hot path; avoid adding combinational depth to audio sample path | Voice regression simulation; per-voice trigger counts unchanged; TimeQuest audio/sys clock slack comparison; waveform event bins and no dropout/clipping evidence |
| Accelerator or audio-path busy indicator | RTL sticky/level indicator sampled at existing frame boundary, not a dispatcher or scheduler | Low LE risk for sticky bits; low memory risk; timing risk low if registered; conceptual risk medium because it can drift toward hardware-dispatcher scope | Simulation with busy asserted/deasserted around known sample/frame windows; no scheduler behavior change; host smoke no-command/commanded PASS; resource/timing delta |
| UART/audio underrun and overrun indicators | Existing UART RX status already has overrun semantics; future audio underrun indicators should be sticky RTL bits cleared only by an explicit future diagnostic contract | Low to medium LE risk; no memory risk; timing risk low if sticky bits are registered; register/UART behavior risk high unless exposure is contract-controlled | Fault-injection simulation; hardware capture showing normal baseline zero; parser/host checks reject unexpected nonzero; explicit clear behavior validation if a clear mechanism is later approved |
| Saturation and overflow counters | Existing `K` mix-clip telemetry should remain the first-line hook; future expansion can count saturated samples per report window | Low LE risk for one shared saturating counter; medium LE risk per voice; no M9K need; timing risk medium if saturation detection is inserted in audio combinational path | Audio-path simulation with forced saturation; accepted waveform captures keep `K=0`; Quartus timing delta; host smoke and waveform checklist PASS |
| Note-event counters | Firmware is preferred because accepted `G/J/L/N/Q` already expose event totals and command count | Low ROM/data risk; no RTL timing risk; low UART risk if values reuse existing telemetry semantics; avoid new tags unless explicit | Existing host smoke expected profiles remain valid; commanded six `!N` still gives `G=12 Q=6`; malformed profile still `X=00030004`; parser selftests |
| Minimal current voice state debug | Existing UART telemetry can expose coarse, snapshot-only state if a future prefix-compatible telemetry extension is approved; avoid per-note state or per-voice parameter banks | Medium UART contract risk; low to medium firmware/ROM risk; low memory if state is coarse; high scope risk if it becomes per-note/per-parameter introspection | New contract doc; parser/host tooling update; no change to current frozen prefix; waveform checklist; simulation proving snapshots do not alter scheduling |

## Hook Details

### Audio-Frame Cycle Counter

Goal: measure real-time stability by counting `sys_clk_50m` cycles between audio frame or sample service boundaries.

Preferred design is a single registered counter plus a snapshot register at an existing audio boundary. Avoid feeding the counter into audio combinational logic. If exposed, telemetry should be appended only under a new explicit contract and must not reorder the frozen baseline tags.

Risk: modest LE cost, no M9K expected, low timing risk if kept as a registered sideband. The main risk is turning a passive measure into a new register-map or UART contract change.

Evidence before implementation: simulation of boundary snapshots, TimeQuest slack delta, host smoke unchanged or intentionally updated, and waveform checklist PASS.

### Accelerator / Voice Busy Cycles

Goal: quantify how much time each existing voice or audio block is active without creating a hardware dispatcher or voice scheduler.

Preferred design is a sticky or counted busy sideband around already-existing trigger/active windows. Avoid any feedback from busy measurement into voice operation.

Risk: per-voice counters add LE/register use and can touch timing-sensitive audio path boundaries. A single aggregate counter is lower risk than three independent full-width counters.

Evidence before implementation: voice trigger simulation, no change to `T/U/O` and `J/L/N` semantics unless explicitly contracted, TimeQuest comparison, and waveform continuity.

### Underrun / Overrun Indicators

Goal: detect missed service or lost input without widening behavior.

UART RX already has accepted overrun/error behavior and `X` reports parser errors. Future measurement should prefer sticky status visible only in controlled telemetry. Audio underrun should be defined precisely before implementation, because the current audio path is not stream-buffer driven.

Risk: sticky bits are cheap, but clear semantics are not. Diagnostic clear RX is explicitly blocked, so any clear mechanism must be a separate approved contract.

Evidence before implementation: fault injection for set behavior, normal hardware smoke proves zero under accepted use, and no new host command semantics.

### Saturation / Overflow Counters

Goal: quantify clipping or arithmetic overflow beyond the existing `K=0` pass/fail signal.

Preferred first step is a saturating report-window counter for mix clipping only. Avoid per-voice arithmetic counters until there is a specific failure mode to diagnose.

Risk: low if counting an already-existing clip condition; medium if new comparators enter the sample path. Memory risk should remain zero.

Evidence before implementation: forced-clipping simulation, normal audio smoke with `K=0` and counter zero, accepted peak/DC/dropout gates, and timing delta.

### Note-Event Counters

Goal: make operator checks more diagnosable without changing note behavior.

The baseline already exposes useful counters: `G` for scheduler/event total, `J/L/N` and `T/U/O` for per-voice trigger totals, and `Q` for accepted UART command count. Future work should treat these as the primary hook. Additional firmware-only derived counters should be considered before any RTL counter.

Risk: low if firmware-only and if current values remain stable. The main risk is expanding UART semantics or creating host-selected parameter behavior, which remains blocked.

Evidence before implementation: host smoke expected profiles, parser boundary malformed profile, firmware ROM delta, and no echo/ACK regressions.

### Minimal Current Voice State Debug

Goal: provide enough state to diagnose whether each existing voice is idle/active/releasing during a smoke run.

Preferred shape is a coarse snapshot bitfield, not per-note state, not per-voice parameter banks, and not host-readable register expansion. If exposed in UART, it should be appended after the frozen accepted prefix only with an explicit contract update.

Risk: low data width, medium firmware/telemetry contract risk, high scope-creep risk. This hook can easily become a backdoor to blocked voice-stealing or per-note-state work.

Evidence before implementation: explicit contract doc, parser and host smoke updates, simulation showing debug state has no scheduling feedback, and waveform checklist PASS.

## Recommended Sequence

1. Keep the current baseline frozen and rely on host smoke plus waveform checklist for promotion decisions.
2. If more observability is needed, start with firmware-derived note-event/report counters because they have the lowest resource and timing risk.
3. Add one RTL sticky indicator at a time only when there is a concrete failure mode and a fault-injection test.
4. Prefer aggregate counters over per-voice full-width counters until a verifier needs per-voice attribution.
5. Do not add new MMIO registers or non-prefix UART tags without a contract task that updates parser, host smoke, simulation, hardware, and waveform evidence together.

## Verification Bundle For Any Future Hook

Before implementation acceptance, require:

- source review confirming no blocked feature expansion;
- focused ModelSim test for the hook set/clear/snapshot behavior;
- existing UART no-command and six-command host smoke PASS;
- malformed/boundary parser smoke still PASS when parser behavior is in scope;
- firmware ROM delta if firmware telemetry changes;
- Quartus resource and TimeQuest timing delta;
- hardware UART capture with no echo/ACK regression;
- waveform checklist PASS with the accepted capture setup;
- report stating whether the hook changes telemetry contract, MMIO contract, or neither.

## Conclusion

The safest future measurement hooks are passive, registered, aggregate, and contract-controlled. The first candidates should be firmware-derived event/report counters and a small number of RTL sticky indicators with clear fault-injection evidence. Anything that changes UART prefix behavior, MMIO register ranges, audio scheduling, voice architecture, or resource footprint beyond the accepted baseline needs a separate explicit implementation task and full revalidation.
