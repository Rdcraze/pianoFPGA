# Phase 1C Event Ingress And Control Options

Date: 2026-04-28
Agent: Codex implementer
Task: `task-364f6aa4`

## Purpose

Compare design options for how real note events should enter the accepted firmware-owned three-voice control path.

This memo is design-only. It does not edit or authorize RTL, firmware, constraints, clocks, register maps, UART behavior, build scripts, event ingress, UART RX, hardware dispatch, a fourth voice, SDRAM, richer physics, UI, sample playback, CPU/ISA expansion, voice stealing, per-note state, per-voice parameter banks, exact-48-kHz work, or broad cleanup.

## Current Accepted Baseline

The promoted Phase 1C control baseline is the firmware-owned six-event round-robin smoke:

```text
0,1,2,0,1,2
```

Accepted baseline facts:

- CPU owns low-rate note-event/control policy and stays out of the audio sample loop.
- Existing three hardware voices are triggered through the current voice0/voice1/voice2 trigger controls.
- Register offsets through `0x80` remain frozen.
- UART telemetry keeps the prefix `I/S/R` and `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`.
- Scheduler diagnostics are appended after `E` as `G/H/J/L/N/P`.
- Current ROM image is `318 / 1024` words.
- Current fit is `7,548 / 10,320` LEs, with only `652` LEs under the prior `8,200` feasibility gate.
- Current slow-85C `sys_clk_50m` setup/hold slacks are `+3.675 ns` / `+0.433 ns`.

The current build is not interactive. It has no user-input ingress, queue, voice stealing, per-note pitch/velocity state, or host command parser.

## Option 1: UART RX Command Ingress

Concept:

- Add a receive path on the existing board UART connection.
- Host sends low-rate note-event commands.
- Firmware parses commands and feeds the already accepted round-robin policy.
- The first authorized command should be a default note event only. Pitch, velocity, duration, release, voice selection, and per-note parameter changes should remain gated until separately accepted.

Resource and timing risk:

- Medium risk because current UART MMIO is effectively TX/status oriented; RX requires RTL, buffering/status, firmware polling, and simulation coverage.
- A minimal RX byte register plus status can be small, but the design has limited LE margin below the `8,200` gate.
- Timing risk is manageable if RX logic stays in the system clock domain and the CPU polls at low rate, but it still changes hardware and must receive full Quartus/TimeQuest validation.

Firmware/software impact:

- Requires a nonblocking parser so malformed or partial input cannot stall telemetry or note triggering.
- Requires explicit bounds: no audio-rate processing, no host-selected voice, no voice stealing, no per-note state in the first slice.
- ROM impact should be measured early because parser code can grow faster than the current fixed smoke.

Register/UART impact:

- Must preserve TX offsets and behavior at UART MMIO `0x00` and `0x04`.
- If RX registers are added, prefer extending the UART MMIO page after the existing TX/status words rather than touching control-register offsets through `0x80`.
- Telemetry must remain prefix-compatible. Any acknowledgements or parser diagnostics should be appended after the current stream, and parsers must continue to ignore unknown tags.

Test and hardware-smoke plan:

- Unit-test the parser against valid, partial, malformed, and overlong command streams.
- ModelSim top test sends at least six host note commands and proves assignment `0,1,2,0,1,2`.
- Verify per-voice trigger counts, overlap, `mix_clip_count=0`, and unchanged telemetry prefix.
- Run NACK regression.
- Rebuild Quartus and check LE gate, M9K/DSP mapping, and TimeQuest.
- Hardware smoke sends serial commands from the host, captures UART telemetry, and records audio.

Fit:

- Best real event ingress candidate after tooling is stable, because it supports repeatable host-driven tests and later MIDI-like evolution without board-specific button limits.
- Not a low-risk immediate implementation without a separate RX/register/resource decision.

## Option 2: GPIO Or Board-Button Test Ingress

Concept:

- Add one or more debounced GPIO/button event inputs.
- Firmware or hardware presents a button edge as a low-rate note event into the existing round-robin policy.
- First version would trigger the default note only.

Resource and timing risk:

- Low-to-medium logic cost for synchronizers, debounce, edge detect, and a readable status/clear path.
- Constraint and board-integration risk is higher than it looks: pins must be assigned, electrical behavior confirmed, and bounce behavior validated.
- Still spends FPGA resources and changes the project/constraints, so it is not free under the current margin.

Firmware/software impact:

- Simple firmware polling or interrupt-like status handling is possible, but the current CPU/software stack has no interrupt infrastructure.
- Polling must remain low-rate and cannot enter the audio sample loop.
- Without multiple buttons or encoders, this does not scale beyond smoke/demo triggering.

Register/UART impact:

- Needs either post-`0x80` control registers or a separate GPIO MMIO page for button status, edge count, and clear.
- No UART behavior needs to change except optional appended diagnostics.
- Existing `G/H/J/L/N/P` counters can still prove assignment counts.

Test and hardware-smoke plan:

- Simulate clean pulses and bounced pulses; prove one accepted event per intended press.
- Confirm trigger sequence across at least six accepted events.
- Check no event occurs during reset and no double-trigger occurs from bounce.
- Hardware smoke presses the button manually or with a fixture, captures UART counters, and records audio.

Fit:

- Useful as a physical bring-up/demo input.
- Weak as the main control path because it is board-specific, low-bandwidth, and does not naturally support scripted regression.

## Option 3: Host-Driven Debug Protocol Over UART Infrastructure

Concept:

- Define a host-side debug protocol and tooling around the UART link.
- The host sends low-rate note-event commands once RX exists, and always parses returned `TAG=XXXXXXXX` telemetry.
- Keep the firmware-owned scheduler as the only voice assignment authority.

Resource and timing risk:

- The protocol definition itself has no FPGA resource cost.
- If paired with UART RX implementation, it inherits the RX hardware risk from Option 1.
- The main risk is protocol creep: adding pitch, velocity, note-off, per-note state, or voice selection would exceed the current accepted control model.

Firmware/software impact:

- Firmware parser should initially accept only a minimal note-event command and a limited diagnostic/status command.
- Host tooling should own higher-level scripting, retries, capture normalization, and report generation.
- Device firmware should not become a general command shell in this phase.

Register/UART impact:

- Telemetry must keep current frame format and prefix order.
- Host commands should use a distinct syntax or direction-specific framing so telemetry parsers do not confuse command echo with device output.
- Any new response/ack tags should be appended after existing diagnostics and documented before implementation.

Test and hardware-smoke plan:

- Host parser tests with synthetic captures, mid-frame starts, repeated report cycles, and unknown future tags.
- Command-protocol tests with malformed commands and rate limiting.
- End-to-end serial smoke after RX exists: send six note commands, verify `G=6`, `J/L/N=2`, `P=0`, `T/U/O=2`, and `K=0`.
- Audio smoke should be scripted so command cadence is repeatable.

Fit:

- Strongest long-term validation and lab-control path.
- Should be specified before implementing UART RX so the hardware/software boundary stays narrow.

## Option 4: Hold Fixed Boot Smoke And Add Parser/Test Tooling

Concept:

- Keep the accepted boot-time six-event smoke unchanged.
- Add host-side capture parsing, synthetic-frame tests, and report tooling before any event-ingress implementation.
- Use current telemetry, especially `G/H/J/L/N/P`, as the stable test oracle.

Resource and timing risk:

- No FPGA resource or timing risk.
- No register, UART, clock, constraint, firmware, or bitstream risk.
- Improves confidence before spending limited LE margin.

Firmware/software impact:

- No device firmware changes.
- Host tooling can normalize UART captures that start mid-frame, tolerate unknown tags, and assert accepted health criteria.
- This can also define the golden behavior that later UART RX or GPIO ingress must preserve.

Register/UART impact:

- None.
- Reinforces existing parser rules: parse by tag, ignore unknown tags, tolerate repeated report cycles, and avoid exact active/valid/sample count constants.

Test and hardware-smoke plan:

- Synthetic parser tests for valid frames, corrupt bytes, partial captures, duplicate tags, unknown tags, and repeated cycles.
- Regression parser checks over accepted captures:
  - identity/status presence;
  - `T/U/O=2` for the round-robin smoke;
  - `G=6`, `H=2`, `J/L/N=2`, `P=0`;
  - `K=0`;
  - nonzero mix/voice status where applicable.
- Hardware smoke remains program, UART capture, audio capture, and parser report generation.

Fit:

- Best immediate next step.
- Does not deliver real event ingress, but it lowers risk for any later ingress choice by making pass/fail criteria mechanical and repeatable.

## Comparison Matrix

| Option | Real event input | FPGA change | Firmware change | Register/UART risk | Regression value | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| UART RX command ingress | Yes | Yes | Yes | Medium | High | Best first real ingress after separate RX authorization |
| GPIO/button ingress | Limited | Yes | Likely | Medium | Medium | Useful demo/bring-up path, not primary control |
| Host-driven debug protocol | Yes, once RX exists | No for spec; yes for RX-backed implementation | Eventually | Medium if implemented | High | Specify before RX implementation |
| Hold/parser-test tooling | No | No | No | None | High | Do next immediately |

## Recommended Next Decision

Authorize a no-device-change parser/test tooling slice first.

That slice should produce a host parser and validation harness for the current UART telemetry, using accepted round-robin captures and synthetic malformed captures. It should not alter RTL, firmware, registers, UART behavior, constraints, clocks, or build/project files unless separately scoped.

After that tooling is accepted, choose UART RX command ingress as the first real event-ingress implementation candidate, gated by a separate design decision that fixes:

- the minimal command grammar;
- RX MMIO placement without disturbing UART TX `0x00`/status `0x04`;
- parser limits and malformed-input behavior;
- appended telemetry/ack tags;
- LE/timing gates;
- required ModelSim, Quartus, UART, and audio smoke evidence.

GPIO/button ingress should remain optional for a later physical-demo slice. It should not be used as the primary path for host-repeatable regression unless the project explicitly prioritizes board-local demo controls over scripted validation.
