# Phase 1C Event-Ingress Options Validation

Date: 2026-04-28
Agent: Codex verifier
Task: `task-c68a32a2`

## Verdict

PASS.

The memo at `reports/phase1c_event_ingress_options.md` stayed design-only, fairly compares the requested event-ingress options, and aligns with the accepted firmware-owned round-robin baseline, ABI contract, resource/timing gates, and blocked feature list.

Recommendation: accept the memo and authorize a no-device-change UART parser/test tooling slice next. Do not authorize UART RX, GPIO/button ingress, hardware dispatch, or broader event-ingress implementation until that tooling and a separate ingress decision are accepted.

## Inputs Checked

- Implementer artifact: `88bca68f-d440-4fa0-a2c9-a96ba8ae8688`
- Event-ingress memo: `reports/phase1c_event_ingress_options.md`
- Accepted firmware round-robin decision: `reports/phase1c_firmware_round_robin_acceptance_decision.md`
- Firmware round-robin verifier report: `reports/phase1c_firmware_round_robin_validation.md`
- ABI/control contract acceptance: `reports/phase1c_three_voice_abi_control_contract_acceptance_decision.md`

## Design-Only Scope

PASS.

The memo explicitly states that it does not edit or authorize RTL, firmware, constraints, clocks, register maps, UART behavior, build scripts, UART RX, hardware dispatch, a fourth voice, SDRAM, richer physics, UI, sample playback, CPU/ISA expansion, voice stealing, per-note state, per-voice parameter banks, exact-48-kHz work, or broad cleanup.

Timestamp review found no new RTL, firmware, Quartus project, constraint, or behavior files modified for this memo. The latest implementation/build files remain from the accepted firmware round-robin work; the event-ingress artifact is documentation only.

## Baseline Alignment

PASS.

The memo correctly identifies the current accepted baseline:

- firmware-owned six-event round-robin smoke `0,1,2,0,1,2`;
- CPU owns low-rate control and remains outside the audio sample loop;
- register offsets through `0x80` are frozen;
- UART prefix remains `I/S/R` then `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`;
- scheduler diagnostics are appended after `E` as `G/H/J/L/N/P`;
- firmware ROM is `318 / 1024` words;
- current fit is `7,548 / 10,320` LEs, only `652` LEs under the `8,200` feasibility gate;
- current `sys_clk_50m` setup/hold slacks are `+3.675 ns` / `+0.433 ns`.

It also correctly states the current build is not interactive and has no user-input ingress, queue, voice stealing, per-note pitch/velocity state, or host command parser.

## Option Coverage

PASS.

The memo fairly compares:

| Option | Validation assessment |
| --- | --- |
| UART RX command ingress | Correctly identified as the strongest first real ingress candidate, but not low-risk because it requires RX RTL/MMIO, parser firmware, Quartus/TimeQuest, and hardware serial smoke. |
| GPIO or board-button ingress | Correctly positioned as useful for physical demo/bring-up but weak for host-repeatable regression and not free because it needs pins, debounce, status/clear, and validation. |
| Host-driven debug protocol | Correctly separated into protocol/tooling work now and RX-backed implementation later; calls out protocol creep risks. |
| Hold fixed boot smoke and add parser/test tooling | Correctly recommended as the immediate next step because it has no FPGA, firmware, register, UART, clock, or timing risk and improves future ingress verification. |

The option comparison respects the accepted blocked list: no fourth voice, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, SDRAM, richer physics, sample playback, UI, exact-48-kHz clock work, or CPU audio-loop involvement.

## Gate Quality

PASS.

The memo gives concrete gates for later UART RX command ingress:

- minimal command grammar fixed before implementation;
- RX MMIO placement must not disturb UART TX `0x00` or status `0x04`;
- malformed/partial/overlong command behavior must be defined and tested;
- telemetry and acknowledgement tags must be appended and documented;
- LE/timing gates must be rechecked;
- ModelSim, Quartus, UART, and audio smoke evidence is required.

It also keeps the parser/test tooling slice correctly scoped: no RTL, firmware, register, UART behavior, constraints, clocks, or build/project changes unless separately authorized.

## Corrections

No blocking corrections.

One carry-forward clarification: if a later UART RX decision is opened, it should explicitly decide whether RX belongs in the existing UART MMIO page or a separate UART-control page, and it should list exact offsets before implementation starts. The current memo already points in this direction; the next decision should make it binding.

## Residual Risks

- Parser/test tooling does not provide real event input by itself.
- UART RX can grow into a command shell if the grammar is not kept to default note-event commands first.
- GPIO/button ingress is attractive for demos but weak for repeatable automated validation.
- The `652` LE margin under the prior feasibility gate remains tight; any hardware ingress must be treated as a separate resource/timing risk.

## Recommendation

Accept `reports/phase1c_event_ingress_options.md`.

Recommended next orchestrator decision: authorize only the no-device-change parser/test tooling slice. Defer UART RX command ingress until parser tooling, command grammar, RX MMIO offsets, malformed-input handling, appended telemetry tags, and hardware validation gates are explicitly accepted.

