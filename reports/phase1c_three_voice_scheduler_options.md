# Phase 1C Three-Voice Scheduler/Control Options

Date: 2026-04-28
Agent: Codex implementer
Task: `task-fe9baed6`

## Purpose

Compare narrow scheduler/control directions for the accepted Phase 1C three-voice baseline. This is a design memo only: no RTL, firmware, constraints, scripts, register maps, or diagnostics are changed here.

## Baseline Facts

The current accepted build demonstrates three simultaneous optimized reduced voices with:

- three fixed hardware voice instances;
- firmware-issued one-shot triggers after codec initialization;
- no scheduler, allocator, voice stealing, or note-event architecture;
- shared default voice coefficients and controls;
- three-way signed saturated mix;
- existing register map preserved through `0x6C`;
- voice2 diagnostics appended at `0x70` through `0x80`;
- UART prefix compatibility through `V,F,T,A,W,Y,U,B,C,M,K`, with `Z,O,D,E` appended.

Accepted resource/timing point:

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

The previous third-voice stop gate was `8,200` LEs. The accepted build leaves `652` LEs below that gate, so the next control step must avoid broad hardware churn.

## Decision Criteria

The next step should:

- preserve the current three voices, coefficients, sample rate, clocking, ROM/RAM sizing, CPU, and codec path;
- keep the CPU out of the audio sample loop;
- preserve existing registers and UART frames as a prefix-compatible interface;
- avoid expanding into fourth voice, SDRAM, richer physics, exact-48-kHz work, larger CPU, UI, or sample playback;
- improve control usefulness without consuming the remaining FPGA headroom prematurely;
- add enough observability to verify assignment behavior, missed events, and clipping behavior.

## Option 1: Firmware Round-Robin Over Current Voices

Design:

- Keep the current three voice instances and per-voice trigger strobes.
- Add a firmware-side `next_voice` policy that assigns incoming note events to voice0, voice1, then voice2, wrapping in order.
- Use existing control registers for the first prototype:
  - voice0 trigger via `PHASE0_REG_VOICE_CONTROL`;
  - voice1 trigger via `PHASE0_REG_VOICE1_CONTROL`;
  - voice2 trigger via `PHASE0_REG_VOICE2_CONTROL`.
- Leave the hardware sample path unchanged; firmware only handles low-rate note-event assignment.
- Treat any richer policy, stealing, per-note envelopes, or per-voice parameter banks as out of scope for the first slice.

Resource and timing risk:

- Lowest FPGA risk if implemented without new RTL.
- ROM growth is the main implementation cost; current firmware image is `241 / 1024` words, so there is room for a narrow policy.
- If no new RTL is added, M9K/DSP mapping and TimeQuest closure should remain unchanged.

Expected register/UART impact:

- Can be zero register-map impact for a minimal firmware-owned demonstration.
- Optional diagnostics should be appended after `0x80`, not inserted before existing offsets.
- UART can remain prefix-compatible by appending assignment frames after existing `Z/O/D/E`, for example:
  - event count;
  - selected voice id;
  - per-voice assignment counts;
  - dropped-event count.

Observability needs:

- Per-voice trigger counts already exist and can prove distribution.
- A scheduler/event counter would help distinguish assignment failure from voice-engine failure.
- A last-assigned voice id and drop count would be useful if events can arrive while firmware is busy.

Test plan:

- Firmware build and ROM-size check.
- Existing standalone voice regression.
- Top-level sim with at least six note events proving assignment sequence `0,1,2,0,1,2`.
- Verify all three voices can overlap and that trigger counts match assignment counts.
- Verify existing UART prefix frames through `K` and appended voice2 frames remain unchanged.
- NACK regression.
- Quartus/TimeQuest only if any RTL changes are made; otherwise still rebuild the accepted bitstream after firmware MIF refresh.
- Hardware UART smoke showing round-robin counts; audio smoke if the trigger cadence is audible.

Main advantages:

- Fastest path to a playable three-voice control demonstration.
- Does not spend the remaining FPGA LE headroom.
- Keeps scheduler policy easy to inspect and revise.

Main risks:

- The current control interface uses shared voice parameters, so true independent per-note velocity/pitch/control is limited.
- Firmware event latency is acceptable for sparse note events but should not become an audio-rate loop.
- Voice stealing policy can grow quickly if not explicitly deferred.

## Option 2: Small Hardware Note-Event Dispatcher

Design:

- Add post-`0x80` note-event command/status registers.
- Firmware writes a compact event command; hardware selects a target voice and generates the appropriate per-voice trigger strobe.
- Initial policy could be simple round-robin or prefer-idle-else-round-robin.
- Dispatcher owns assignment counters, busy/drop status, and last-assigned voice id.

Resource and timing risk:

- Moderate risk because the accepted build has only `652` LEs below the prior stop gate.
- A carefully scoped dispatcher may fit, but the required control, counters, arbitration, status, and tests could consume meaningful headroom.
- Timing risk is probably manageable if the dispatcher stays off the audio datapath, but it still touches the control register path and trigger fanout.
- This option must not grow into per-voice parameter banks or richer note state in the same slice.

Expected register/UART impact:

- Requires new registers after `0x80`, likely including:
  - note event command;
  - dispatcher status;
  - event count;
  - assigned voice counts;
  - dropped/overflow count;
  - last assigned voice.
- UART should append dispatcher frames after current voice2 diagnostics.
- Existing register and UART prefixes must remain stable.

Observability needs:

- Dispatcher event accepted/rejected count.
- Last assigned voice id.
- Per-voice assignment counts.
- Drop/overflow count.
- Optional reason bits for busy/no-idle/disabled voice.
- Existing per-voice trigger/active/valid counters remain the voice-engine proof.

Test plan:

- Unit/top simulation for command writes and assignment order.
- Back-to-back command stress with expected accepted/drop behavior.
- Disabled-voice behavior if voice enables remain software-visible.
- Existing three-voice happy path and NACK regression.
- UART prefix compatibility check.
- Quartus full compile and TimeQuest.
- Mapping check to confirm no voice RAM/DSP regression.
- Hardware UART smoke proving event assignment and no unexpected mix clipping.

Main advantages:

- Better abstraction for future non-firmware event sources.
- More deterministic event acceptance and assignment than firmware sequencing.
- Gives one central place to report scheduling state.

Main risks:

- Consumes scarce LE headroom before the control architecture is fully specified.
- Adds a new hardware contract and failure modes.
- Can easily expand into note state, voice stealing, per-voice parameters, and broader polyphony architecture unless tightly gated.

## Option 3: Hold At Three Voices For Control Hardening

Design:

- Do not add scheduler or dispatcher yet.
- Treat the accepted three-voice build as the current feasibility baseline.
- Spend the next pass on control-contract hardening and test coverage only.
- Produce a precise ABI/control note for the three-voice map and UART stream.
- Add or plan tests for saturation edge cases, diagnostic parsing, and register compatibility before scheduler implementation.

Resource and timing risk:

- Lowest immediate implementation risk.
- No FPGA resource or timing pressure if this remains documentation and test planning.
- Creates room to identify small optimizations before spending headroom on control hardware.

Expected register/UART impact:

- None for the memo/test-plan phase.
- Future additions should be explicitly assigned after `0x80`.
- Existing UART consumers should be documented as prefix parsers, not fixed-frame-count parsers.

Observability needs:

- Clarify which counters are architectural diagnostics and which are smoke-test aids.
- Define required scheduler observability before implementation:
  - event count;
  - selected voice;
  - per-voice assignment count;
  - drop/steal count;
  - clip count;
  - last error/status.

Test plan:

- Document current register and UART ABI.
- Add a compatibility checklist for any future scheduler slice.
- Define exact pass/fail criteria for round-robin assignment before writing RTL or firmware.
- Preserve current firmware, voice, top happy, NACK, Quartus, TimeQuest, UART, and audio smoke evidence as the baseline acceptance set.

Main advantages:

- Protects the newly accepted baseline from immediate scope creep.
- Reduces ambiguity before adding a note-event contract.
- Gives the project a chance to recover more LE headroom or simplify diagnostics before any hardware dispatcher.

Main risks:

- Does not make the instrument more playable by itself.
- May feel like a pause if the immediate product goal is user-driven note events.

## Comparison

| Criterion | Firmware Round-Robin | Hardware Dispatcher | Hold/Hardening |
| --- | --- | --- | --- |
| FPGA resource risk | Very low | Medium | None |
| Timing risk | Very low | Low to medium | None |
| Register impact | None to small | Medium | None |
| UART impact | Optional appended frames | Appended dispatcher frames needed | None |
| Implementation speed | Fast | Moderate | Fast documentation/test planning |
| Future event-source fit | Moderate | Best | Deferred |
| Scope-creep risk | Medium | High | Low |
| Best use | First playable assignment demo | Later centralized event ingress | Stabilize baseline and ABI |

## Recommendation

Do not authorize a hardware dispatcher or fourth voice next.

Recommended next decision:

1. Hold the accepted three-voice baseline for a short control-hardening pass.
2. Define the exact scheduler ABI and UART observability requirements after `0x80`.
3. Then authorize firmware-triggered round-robin as the first scheduler/control implementation slice, provided it avoids RTL changes unless a small post-map diagnostic register is explicitly approved.

Rationale:

- The accepted build is close enough to the `8,200` LE feasibility gate that spending FPGA logic on a dispatcher before the event contract is mature is premature.
- Firmware round-robin can prove useful three-voice assignment without risking M9K/DSP mapping or timing closure.
- A hardware dispatcher should wait until there is a clear need for non-firmware event ingress, deterministic event acceptance, or a richer external control source.

## Non-Goals To Keep Gated

- scheduler implementation in this memo;
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
