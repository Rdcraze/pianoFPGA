# Phase 1C Event-Ingress Options Acceptance Decision

Date: 2026-04-28
Agent: Codex orchestrator
Task: `task-65394918`

## Decision

Accept `reports/phase1c_event_ingress_options.md` as the current event-ingress design memo.

Accepted validation:

- `reports/phase1c_event_ingress_options_validation.md`
- Artifact `55e7844e-992c-4c4e-a25d-99cdf8b1cb7a`
- Verdict: PASS

The memo stayed design-only, fairly compared UART RX command ingress, GPIO/button ingress, host-driven debug protocol, and hold/parser-test tooling, and aligned with the accepted firmware-owned round-robin baseline and ABI gates.

## Current Control Baseline

The accepted control baseline remains the firmware-owned six-event round-robin build:

- SOF SHA-256: `0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0`
- Programmer checksum: `0x005B95A9`
- firmware ROM: `318 / 1024` words
- fit: `7,548 / 10,320` LEs, `14 / 46` M9Ks, `6 / 46` DSP9s
- timing: `sys_clk_50m` setup slack `+3.675 ns`, hold slack `+0.433 ns`
- UART prefix: `I/S/R` then `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`
- appended scheduler diagnostics: `G/H/J/L/N/P`

This baseline is still a fixed boot-time smoke, not an interactive input path.

## Interpretation

UART RX is the strongest first real ingress candidate, but it is not authorized yet. It requires RX RTL/MMIO, parser firmware, malformed-input policy, resource/timing validation, and hardware serial smoke.

GPIO/button ingress is useful for a board-local demo, but it is weaker for repeatable host-driven regression and still costs pins, debounce/status logic, constraints, and validation.

Host-driven debug protocol is valuable, but the device-side RX implementation should wait until parser/test tooling and command grammar are accepted.

The lowest-risk next step is no-device-change parser/test tooling for existing UART telemetry and synthetic captures.

## Authorized Next Slice

Authorize only a host-side parser/test tooling slice.

Allowed scope:

- parse existing `TAG=XXXXXXXX\\r\\n` telemetry captures;
- tolerate capture starting mid-frame;
- ignore unknown tags;
- handle duplicate/repeated report cycles;
- validate the accepted firmware round-robin health criteria;
- include synthetic tests for corrupt bytes, partial frames, unknown tags, duplicate tags, repeated cycles, and malformed lines;
- run against accepted UART capture artifacts where available;
- produce a report describing behavior, commands, test coverage, and known limitations.

No device RTL, firmware, UART behavior, register map, clocking, constraints, MIF/build output, Quartus project, or hardware behavior changes are authorized by this decision.

## Parser Health Criteria

The parser/tooling slice should at least validate:

- identity/status frames are present when expected;
- existing voice/mix tags through `Z/O/D/E` can be parsed by tag;
- `T=2`, `U=2`, and `O=2` for the accepted round-robin smoke;
- `G=6`, `H=2`, `J=2`, `L=2`, `N=2`, and `P=0`;
- `K=0`;
- voice status and mix status are nonzero where expected;
- unknown future tags do not fail parsing;
- exact active/valid/sample counts are not treated as permanent ABI constants.

## Still Gated

Do not authorize these without a later explicit decision:

- UART RX command ingress;
- GPIO/button ingress;
- hardware note-event dispatcher;
- fourth voice or broader polyphony;
- voice stealing;
- per-note state;
- per-voice parameter banks;
- SDRAM;
- richer physical model;
- sample playback;
- UI/TFT/touch work;
- exact-48-kHz clock or PLL work;
- larger CPU or ISA expansion;
- register changes before `0x84`;
- non-prefix-compatible UART behavior;
- CPU participation in the audio sample loop.

## Later UART RX Decision Requirements

Before any UART RX implementation task is created, a separate decision must fix:

- minimal command grammar;
- whether RX extends the existing UART MMIO page or uses a separate control page;
- exact RX MMIO offsets without disturbing TX `0x00` or status `0x04`;
- parser limits and malformed/partial/overlong input behavior;
- acknowledgement or telemetry tags appended after the current stream;
- LE/timing gates;
- ModelSim, Quartus, UART, and audio-smoke evidence requirements.

## Disposition

Proceed to host-side parser/test tooling only. Hold all device event-ingress implementation.
