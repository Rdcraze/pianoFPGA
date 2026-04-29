# Phase 1C UART RX Command-Ingress Contract Validation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-68fcfc07`  
Implementation artifact: `4a4fdb67-e699-4588-9167-9280cb5d09d4`  
Submitted contract: `reports/phase1c_uart_rx_command_ingress_contract.md`

## Verdict

FAIL. Revision required before acceptance.

The memo is correctly scoped as design-only and mostly preserves the accepted Phase 1C baseline, but it contains contract ambiguities that would make the later UART RX implementation and acceptance tests less exact than requested.

## Scope Validation

PASS for design-only scope.

The submitted memo states that it does not implement or authorize RTL, firmware, constraints, MIF/build outputs, Quartus project edits, bitstream changes, or host command tools. A recent file-activity check after 2026-04-28 20:42 found only:

- `reports/phase1c_uart_rx_command_ingress_contract.md`, last written 2026-04-28 20:46:26
- `reports/phase1c_uart_parser_tooling_acceptance_decision.md`, last written 2026-04-28 20:42:07

No recent RTL, firmware, Quartus, MIF/build-output, register-map, UART-behavior, or generated-bitstream files were observed in this task window.

## Passing Checks

The memo preserves the key accepted baseline constraints:

- Existing UART TX data/status offsets remain `0x40001000 + 0x00` and `0x40001000 + 0x04`.
- Control-register offsets through `0x80` remain frozen.
- New UART RX MMIO is placed after the TX/status words at `0x08`, `0x0C`, and `0x10`.
- Existing telemetry order through `I/S/R`, `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`, and appended `G/H/J/L/N/P` is preserved.
- UART RX remains unimplemented until a later explicit implementation and acceptance decision.
- The only first-slice command action is default note-event enqueue through the firmware-owned round-robin policy.
- Host-selected voice, pitch, velocity, duration, per-note state, per-voice banks, synthesis parameters, clip/diagnostic clear, codec config, sample playback, and content selection remain out of scope.
- The memo blocks scope creep into SDRAM, a fourth voice/polyphony, richer physics, exact-48 kHz PLL work, larger CPU/ISA, and CPU work in the audio sample loop.
- Resource/timing gates are present: full Quartus compile, constrained setup/hold, TNS `0.000`, LE gate `<= 8,200`, setup slack `>= +1.0 ns`, nonnegative hold slack, ROM `<= 1024` words, DSP9 unchanged, M9K unchanged unless separately authorized.
- Simulation and hardware smoke plans cover no-command compatibility, commanded smoke, malformed input, backpressure, parser regression, Quartus evidence, UART capture, and audio capture.

## Blocking Findings

### 1. Accepted health profile drops `H=2`

The accepted parser/tooling decision defines the current Phase 1C health profile as:

```text
T=2, U=2, O=2, K=0, G=6, H=2, J=2, L=2, N=2, P=0
```

The submitted RX contract repeatedly omits `H=2` from no-command and commanded acceptance checks:

- line 24: current parser/test tooling profile omits `H=2`
- line 167: expected no-command totals omit `H=2`
- line 173: commanded cumulative totals omit `H=2`
- line 281: required simulation no-command health omits `H=2`
- line 288: commanded simulation totals omit `H=2`
- line 327: hardware commanded smoke totals omit `H=2`

This is not just a formatting issue. `H` is part of the accepted `G/H/J/L/N/P` scheduler telemetry prefix and currently proves the last selected voice/status value. A later RX implementation could regress `H` while still satisfying the memo's listed checks.

Required correction: include `H=2` in the no-command profile and the commanded cumulative smoke expectations unless the contract explicitly redefines `H` and receives separate acceptance for that ABI change.

### 2. Overlong command threshold is internally inconsistent

The memo states:

- line 82: maximum command line length is `16 bytes, including CRLF`
- line 83: overlong is any line that exceeds `16 bytes before CRLF`
- line 187: error code `3` covers `more than 16 bytes before CRLF`

These two thresholds are not equivalent. If the maximum is 16 bytes including CRLF, then the maximum pre-CRLF payload is 14 bytes. If overlong means more than 16 bytes before CRLF, then up to 18 total bytes including CRLF could be accepted before overlong handling triggers.

Required correction: define one exact threshold, including whether the CR and LF bytes count toward it, and update the error-code table and smoke tests to match.

## Non-Blocking Cleanup

Line 188 leaves partial reset/flush error-count increment optional. That may be acceptable if tests explicitly allow either behavior, but it weakens the requested exact `X` error contract. Prefer making this deterministic, or state exactly how acceptance tests will evaluate `X` after reset/flush while a partial command is buffered.

Line 161 says a command is acknowledged only after scheduler acceptance, and the `Q` telemetry definition makes that usable as an ACK count. A revision should explicitly state that there is no immediate byte-level echo or standalone ACK response in the first RX slice; `Q` in appended telemetry is the acknowledgement mechanism.

## Recommendation

Do not accept this memo yet and do not start UART RX implementation from it.

Request a narrow documentation revision that:

1. Adds `H=2` to all no-command and six-command cumulative acceptance profiles.
2. Resolves the 16-byte overlong threshold into one exact rule.
3. Tightens `X` behavior for partial reset/flush and clarifies that `Q` telemetry is the ACK mechanism.

After those changes, the memo should be ready for a focused re-validation. No device-side implementation should begin until the revised contract is accepted.
