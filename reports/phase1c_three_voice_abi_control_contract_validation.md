# Phase 1C Three-Voice ABI/Control Contract Validation

Date: 2026-04-28
Agent: Codex verifier
Task: `task-e7e236c7`

## Verdict

PASS.

The ABI/control contract memo at `reports/phase1c_three_voice_abi_control_contract.md` stayed documentation-only, accurately captures the accepted three-voice register and UART ABI, preserves prefix-compatible parsing assumptions, reserves future scheduler/control additions after the current map, and keeps scheduler implementation, hardware dispatcher work, fourth voice, and broader feature expansion gated.

Recommendation: accept the ABI/control contract as the gate document for future scheduler work, with one non-blocking editorial correction noted below.

## Inputs Checked

- Implementer artifact: `df79c32c-dd5d-47a7-a089-78bf932c70c2`
- ABI/control memo: `reports/phase1c_three_voice_abi_control_contract.md`
- Accepted three-voice decision: `reports/phase1c_third_voice_acceptance_decision.md`
- Scheduler/options validation: `reports/phase1c_three_voice_scheduler_options_validation.md`
- Source cross-checks:
  - `fw/phase0/phase0_hw.h`
  - `fw/phase0/phase0_main.c`
  - `rtl/control/phase0_control_regs.v`
  - `rtl/audio/phase0_audio_path.v`

## Documentation-Only Scope

PASS.

The memo explicitly says it does not authorize or implement RTL, firmware, constraints, clocks, MIF/build scripts, register behavior, UART behavior, scheduler logic, dispatcher logic, fourth voice, SDRAM, richer physics, sample playback, UI, CPU/ISA expansion, exact-48-kHz clock work, voice stealing, per-note state, or per-voice parameter banks.

A timestamp review of `rtl/` and `fw/` showed no implementation edits associated with this memo task; the relevant source/build files remain from the earlier accepted three-voice implementation window. The new task artifact is the documentation memo itself.

## ABI Accuracy

PASS.

The memo correctly records the accepted three-voice baseline identity:

| Metric | Memo Value | Accepted Value |
| --- | ---: | ---: |
| SOF SHA-256 | `91784AE1...A07A0E` | matches |
| Programmer checksum | `0x005B2137` | matches |
| Logic elements | `7,548 / 10,320` | matches |
| Dedicated registers | `3,275` | matches |
| Memory bits | `80,896 / 423,936` | matches |
| M9Ks | `14 / 46` | matches |
| DSP9 elements | `6 / 46` | matches |
| Slow-85C `sys_clk_50m` setup slack | `+3.675 ns` | matches |
| Slow-85C `sys_clk_50m` hold slack | `+0.433 ns` | matches |
| Slow-85C `sys_clk_50m` Fmax | `61.26 MHz` | matches |

The register map matches the firmware header and control-register RTL:

- ROM `0x00000000`, size `0x00001000`.
- RAM `0x00010000`, size `0x00001000`.
- Control base `0x40000000`.
- UART MMIO base `0x40001000`.
- Existing control offsets are frozen through `0x6C`.
- Accepted voice2 offsets occupy `0x70` through `0x80`.
- Future scheduler/control additions are reserved for `0x84` and above.

The documented control and status bitfields match the RTL:

- `PHASE0_REG_CONTROL` bits `0`, `1`, `5:4`, `8`, and `9`.
- Voice0 control bits `0`, `1`, `2`, `3`, `4`, and `8`.
- Voice1/voice2 control bits `0`, `1`, `2`, and `8`.
- Voice status bits `0`, `1`, `2`, `3`, `4`, and `31:16`.
- Mix status bits `0`, `1`, `2`, `3`, `4`, and `31:16`, including the preserved legacy voice1-enable field at bit `4`.

## UART And Parser Contract

PASS.

The memo correctly documents the firmware frame format as `TAG=XXXXXXXX\r\n`, requires tag-based parsing, requires unknown-tag tolerance, and warns consumers not to assume fixed byte counts or fixed total frame counts.

The current frame order matches firmware:

```text
I, S, R
V, F, T, A, W, Y, U, B, C, M, K, Z, O, D, E
```

The memo correctly classifies exact active/valid/sample counts, audio metrics, and most smoke values as validation observations rather than permanent ABI constants. It also identifies the important current smoke assertions: identity, per-voice trigger counts, enabled/nonzero voice status, nonzero mix peak, and default `K == 0`.

## Future Scheduler Gates

PASS.

The memo gives clear gates for a later firmware-owned round-robin task:

- no RTL changes unless explicitly authorized;
- no register behavior changes before `0x84`;
- no UART behavior changes except appended frames after `Z/O/D/E`;
- no hardware dispatcher;
- no fourth voice;
- no voice stealing, per-note state, or per-voice parameter banks;
- no CPU participation in the audio sample loop;
- no SDRAM, richer physics, sample playback, UI, larger CPU/ISA, or exact-48-kHz work.

It also gives concrete evidence requirements: clean firmware build, ROM within `1024` words, six-event `0,1,2,0,1,2` simulation, matching assignment/trigger counts, three-voice overlap, unchanged UART prefixes, current voice2 frames preserved, NACK regression, hardware UART smoke, audio smoke when audible, and Quartus/TimeQuest gates if any RTL changes.

The resource/timing gates remain consistent with the accepted baseline:

- LE use `<= 8,200 / 10,320`;
- slow-85C `sys_clk_50m` setup slack `>= +1.0 ns`;
- setup and hold fully constrained;
- all listed TNS values `0.000`;
- voice M9K/DSP mapping must not regress unless explicitly authorized.

## Corrections

No blocking corrections.

Non-blocking editorial correction: the memory-map table says UART MMIO has page-local offsets below, but the memo primarily documents the ASCII UART stream and does not list the UART MMIO register offsets. If this is promoted as a complete ABI reference, add `PHASE0_UART_REG_TXDATA = 0x00` and `PHASE0_UART_REG_STATUS = 0x04`, or reword that line to say UART stream framing is documented separately.

## Residual Risks

- The proposed post-`0x80` scheduler register block and future UART tags are reservations only; they must not be treated as implemented behavior.
- The current `652` LE margin below the prior feasibility gate remains tight, so any hardware dispatcher or register-heavy diagnostics need separate authorization and full timing/resource proof.
- Parser guidance must be enforced in tests; otherwise future tools may accidentally depend on fixed frame counts or smoke-only counter values.
- This contract supports a firmware-owned round-robin slice, not broader polyphony, voice stealing, per-note velocity/pitch banks, or external event-ingress architecture.

## Recommendation

Accept `reports/phase1c_three_voice_abi_control_contract.md` as the Phase 1C three-voice ABI/control contract after the non-blocking UART-MMIO documentation cleanup is either made or explicitly deferred.

The next implementation task, if authorized, should be firmware-owned round-robin only and should carry the memo's acceptance gates verbatim.

