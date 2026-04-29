# Phase 1C UART RX Command-Ingress Contract Revalidation

Verifier: Codex verifier agent `e9722d83-b000-4165-a5a7-36b758c2e8d8`  
Task: `task-a483aafd`  
Revision artifact: `7e6588a5-06d5-4a99-a34f-5f982ee57d4e`  
Revised contract: `reports/phase1c_uart_rx_command_ingress_contract.md`

## Verdict

PASS.

The revised memo resolves the prior blockers from `reports/phase1c_uart_rx_command_ingress_contract_validation.md` and remains documentation-only. It is suitable to use as the gate document for a later, separately authorized UART RX command-ingress implementation.

## Scope Revalidation

PASS for documentation-only scope.

The revised contract still states that it does not implement or authorize RTL, firmware, constraints, MIF/build outputs, Quartus project edits, bitstream changes, or host command tools. A recent file-activity check after 2026-04-28 20:51 found only:

- `reports/phase1c_uart_rx_command_ingress_contract.md`, last written 2026-04-28 20:53:22

No recent RTL, firmware, Quartus, MIF/build-output, register-map, UART-behavior, or generated-bitstream files were observed in this revision window.

## Prior Blockers

### `H=2` restored

PASS.

The accepted `H=2` scheduler telemetry value is now present in the required no-command and commanded profiles/checks:

- current parser/test tooling profile: `T/U/O=2`, `G=6`, `H=2`, `J/L/N=2`, `P=0`, `K=0`
- no-command compatibility: `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`
- six-command cumulative behavior: `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `Q=6`, `P=0`, `K=0`
- simulation no-command health includes `H=2`
- simulation commanded smoke includes `H=2`
- hardware no-command and commanded smokes include `H=2`

### Overlong threshold made exact

PASS.

The revised contract now defines one consistent rule:

- maximum line length is exactly 16 total bytes including terminating CRLF
- at most 14 bytes may appear before CRLF
- the 15th pre-CRLF byte makes the line overlong immediately
- the overlong line is rejected exactly once
- the parser discards until CRLF
- the terminating CRLF does not create a second error

The error-code table and hardware malformed smoke both use the same 15th-pre-CRLF threshold.

### `X` behavior made deterministic

PASS.

The revised partial-command behavior is deterministic:

- hardware reset clears partial command state and clears `Q/X`; no partial-reset error is observable or required after reset
- `FLUSH_RX_FIFO` with a partial line buffered discards the partial line, increments `X` exactly once with error code `4`, and sets `RX_DROPPED_STICKY`
- `FLUSH_RX_FIFO` with no partial line buffered does not change `X`
- the RXCONTROL table repeats the same code-`4` requirement

### `Q` telemetry clarified as ACK

PASS.

The revised transport and telemetry sections now state:

- the device must not echo received command bytes
- there is no byte-level echo and no standalone immediate ACK frame
- `Q` telemetry after `P` is the ACK mechanism
- `Q` increments only after a valid `!N\r\n` command schedules a note event
- hosts confirm acceptance by observing the next `Q` after the regular report sequence reaches `P`

## Baseline Constraints Still Preserved

The revised memo continues to preserve the previously passing baseline constraints:

- UART TX data/status remain at `0x40001000 + 0x00` and `0x40001000 + 0x04`.
- New RX MMIO is defined only at `0x08`, `0x0C`, and `0x10`.
- Control-register offsets through `0x80` remain frozen; future scheduler/control registers still start at `0x84` or later unless separately accepted.
- Existing telemetry order through `I/S/R`, `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`, and `G/H/J/L/N/P` remains unchanged.
- `Q/X` are appended after `P` only.
- The first RX slice remains limited to `!N\r\n` default-note enqueue through firmware-owned round-robin policy.
- Host control of voice index, pitch, velocity, duration, per-note state, per-voice parameter banks, synthesis parameters, diagnostics clear, codec config, sample playback, or content selection remains out of scope.
- CPU polling remains in the low-rate control path and outside the audio sample loop.
- Resource/timing gates remain present: full Quartus compile, constrained setup/hold, TNS `0.000`, LE `<= 8,200 / 10,320`, slow-85C setup slack `>= +1.0 ns`, nonnegative hold slack, ROM `<= 1024` words, DSP9 `6 / 46`, and M9K `14 / 46` unless separately authorized.
- Simulation and hardware plans still cover no-command compatibility, commanded smoke, malformed input, backpressure, parser regression, Quartus evidence, UART capture, and audio capture.

## Residual Risks

- This is still a design contract only. UART RX RTL, firmware parser code, host tooling, bitstream generation, and hardware smoke remain unauthorized until an orchestrator acceptance decision creates an implementation task.
- The future implementation must still prove the specified rates, parser behavior, resource/timing gates, UART captures, and audio captures; none of that evidence exists in this memo.
- Any deviation from the contract should require a separate acceptance decision before implementation.

## Recommendation

Accept the revised UART RX command-ingress contract memo as the implementation gate. The next orchestrator decision can either accept the memo and then create a separately scoped UART RX implementation task, or hold implementation until more protocol detail is desired.
