# Phase 1C UART RX Command-Ingress Contract

Date: 2026-04-28
Agent: Codex implementer
Task: `task-8fd3900b`

## Purpose

Define a design-only contract for a later UART RX command-ingress implementation. This memo does not implement or authorize RTL, firmware, constraints, MIF/build outputs, Quartus project edits, bitstream changes, or host command tools.

The contract preserves the accepted Phase 1C firmware-owned three-voice round-robin baseline and defines the exact behavior a later implementation task must meet before it can be accepted.

## Current Baseline To Preserve

Accepted baseline:

- fixed boot-time six-event round-robin smoke: `0,1,2,0,1,2`;
- firmware-owned scheduling over existing voice0/voice1/voice2 trigger controls;
- CPU remains in the low-rate note-event/control path and outside the audio sample loop;
- control-register offsets through `0x80` remain unchanged;
- UART TX MMIO remains `0x40001000 + 0x00` for TX data and `0x40001000 + 0x04` for TX status;
- UART telemetry prefix remains `I/S/R`, then `V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E`;
- scheduler telemetry remains appended after `E` as `G/H/J/L/N/P`;
- current parser/test tooling accepts the no-command health profile `T/U/O=2`, `G=6`, `H=2`, `J/L/N=2`, `P=0`, `K=0`;
- current build identity is SOF SHA-256 `0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0`, programmer checksum `0x005B95A9`, `7,548 / 10,320` LEs, and `318 / 1024` firmware ROM words.

## Command Scope Decision

UART RX commands alter note-event scheduling only.

The first RX slice must not allow host control of:

- voice index;
- pitch or phase step;
- velocity;
- duration/release;
- per-note state;
- per-voice parameter banks;
- synthesis parameters;
- clip/diagnostic clear;
- codec configuration;
- sample playback or content selection.

The only accepted command action is "enqueue one default note event into the existing firmware-owned round-robin policy." The firmware selects the next voice. Hardware remains a three-voice trigger target, not a dispatcher.

## Minimal Command Grammar

Transport:

- 115200 8N1 UART bytes on the existing board UART connection.
- Commands are host-to-device only.
- Device telemetry remains device-to-host only.
- The device must not echo received command bytes.
- The first RX slice has no byte-level echo and no standalone immediate ACK frame; `Q` telemetry after `P` is the ACK mechanism.

Line grammar:

```text
!N\r\n
```

Meaning:

- `!` begins a host command.
- `N` is the only accepted opcode in the first RX slice.
- CRLF terminates the command.
- The command schedules one default note event through the firmware-owned round-robin policy.

Rejected in the first RX slice:

- any arguments, including `!N=XXXXXXXX\r\n`;
- lowercase opcodes;
- whitespace;
- bare LF without CR;
- telemetry-shaped input such as `T=00000002\r\n`;
- unknown opcodes;
- empty lines;
- binary/non-ASCII bytes inside a command line;
- any line longer than the maximum below.

Maximum command line length:

- The limit is exactly 16 total bytes including the terminating CRLF.
- Therefore at most 14 bytes may appear before CRLF.
- If the 15th pre-CRLF byte arrives, the line is overlong immediately, must be rejected exactly once, and the parser discards bytes until the next CRLF before accepting a new command.
- The CRLF that terminates an overlong discarded line must not create a second error.

Partial command behavior:

- A partial line has no side effect until CRLF is received.
- No timeout is required for the first RX slice.
- Hardware reset clears any partial command buffer and clears `Q/X`; no partial-reset error is observable or required after reset.
- A `FLUSH_RX_FIFO` pulse while a partial command is buffered must discard the partial line, increment the `X` error count exactly once with error code `4`, and set `RX_DROPPED_STICKY`.
- A `FLUSH_RX_FIFO` pulse with no partial command buffered must not change `X`.
- If a new `!` arrives while a partial malformed line is buffered, firmware may restart the line buffer at the new `!`, but it must not emit a note event for the discarded bytes.

## UART RX MMIO Placement

UART MMIO base remains:

```text
PHASE0_UART_BASE = 0x40001000
```

Existing offsets remain unchanged:

| Offset | Name | Access | Required behavior |
| ---: | --- | --- | --- |
| `0x00` | `PHASE0_UART_REG_TXDATA` | WO | Existing TX data write behavior unchanged |
| `0x04` | `PHASE0_UART_REG_STATUS` | RO | Existing TX-ready bit behavior unchanged; existing firmware polling of bit 0 must keep working |

New RX offsets for a later implementation:

| Offset | Name | Access | Required behavior |
| ---: | --- | --- | --- |
| `0x08` | `PHASE0_UART_REG_RXDATA` | RO/pop | Bits `7:0` return the oldest received byte; a read pops one byte only when RX valid is set; reads when empty return `0` and have no side effect |
| `0x0C` | `PHASE0_UART_REG_RXSTATUS` | RO | RX status flags defined below |
| `0x10` | `PHASE0_UART_REG_RXCONTROL` | WO/pulse | RX control pulses defined below |

No other UART RX offsets are reserved for the first RX slice.

`PHASE0_UART_REG_RXSTATUS` bits:

| Bit | Meaning |
| ---: | --- |
| `0` | `RX_VALID`: at least one byte is available at `RXDATA` |
| `1` | `RX_FULL`: RX FIFO is full |
| `2` | `RX_OVERRUN_STICKY`: at least one byte was dropped because the FIFO was full |
| `3` | `RX_FRAME_ERROR_STICKY`: UART framing error observed |
| `4` | `RX_DROPPED_STICKY`: firmware or RX logic discarded bytes after an overlong/malformed command |
| `31:5` | reserved, read as zero |

`PHASE0_UART_REG_RXCONTROL` bits:

| Bit | Meaning |
| ---: | --- |
| `0` | `CLEAR_RX_ERRORS`: clears sticky RX error bits |
| `1` | `FLUSH_RX_FIFO`: discards all queued RX bytes and clears any partial command buffer; if a partial command was buffered, firmware must report error code `4` through `X` exactly once |
| `31:2` | reserved, write zero |

RX FIFO requirement:

- Minimum depth: 16 bytes.
- Overflow policy: drop newest byte, preserve existing FIFO contents, set `RX_OVERRUN_STICKY`.
- The implementation must document any larger depth if chosen, but acceptance tests should assume only 16 bytes.

Control register compatibility:

- No control-register offsets through `0x80` may change.
- UART RX uses the UART MMIO page, not the control-register page.
- Any future scheduler/control registers still start at `0x84` or later unless a later accepted contract revises that rule.

## Firmware Parser And Event Semantics

Firmware polling:

- Firmware may poll RX status in the existing low-rate control loop.
- Polling must not enter the audio sample loop.
- TX telemetry emission must remain nonblocking with the existing timeout behavior.

Accepted command handling:

- On valid `!N\r\n`, firmware schedules exactly one default note event.
- The scheduler assigns the event to the next voice in the existing `0,1,2` round-robin sequence.
- The command is acknowledged only after the event is accepted by the firmware scheduler.
- No valid command may directly write voice parameter registers or select a voice.

No-command compatibility:

- With no host commands, reset behavior must remain the accepted six-event boot smoke.
- Expected no-command totals remain `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0`.

Commanded-event cumulative behavior:

- The first RX slice keeps the boot smoke enabled.
- Commanded note events are cumulative after the boot smoke.
- After six valid `!N\r\n` commands following reset, expected totals are `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `Q=6`, `P=0`, and `K=0`.
- The six commanded events after boot must independently follow `0,1,2,0,1,2` because the boot smoke ends on voice2 and wraps to voice0.

## Malformed, Partial, And Overlong Handling

Rejected inputs must not change `G`, `H`, `J`, `L`, `N`, `P`, `T`, `U`, or `O`.

Malformed command classes:

| Code | Class | Examples | Required behavior |
| ---: | --- | --- | --- |
| `0` | none | no error since reset/clear | no error action |
| `1` | malformed | `N\r\n`, `!N\n`, `T=00000002\r\n`, binary bytes | reject, increment error count |
| `2` | unknown opcode | `!X\r\n` | reject, increment error count |
| `3` | overlong | 15th byte before CRLF, exceeding the exact 16-byte complete-line limit including CRLF | reject exactly once, discard until CRLF, increment error count |
| `4` | partial flush | `FLUSH_RX_FIFO` while partial line pending | discard partial line, increment error count exactly once; hardware reset clears `Q/X` and has no observable error |
| `5` | rate/backpressure | command accepted by parser but scheduler intentionally refuses due low-rate gate | reject, increment error count |
| `6` | RX hardware error | overrun or framing error | set RX sticky status and increment error count when firmware observes it |
| `7` | unsupported argument | `!N=00000001\r\n` | reject, increment error count |

The first RX implementation should avoid code `5` in normal smoke by accepting at least the rate below.

## Rate And Backpressure

Required acceptance rate:

- The device must accept six valid `!N\r\n` commands sent at 10 Hz after boot.
- The device should accept up to 20 valid note commands per second without overrun or parser error.

Non-goals:

- No guarantee is made for audio-rate command streams.
- No guarantee is made for continuous UART saturation.
- No event queue beyond the UART RX FIFO and firmware line buffer is required.

Backpressure behavior:

- If the RX FIFO overflows, newest bytes are dropped and `RX_OVERRUN_STICKY` is set.
- If firmware intentionally rate-limits valid commands, it must reject the command, increment the error count, and report error code `5`.
- A rejected command must not partially trigger a voice.

## ACK And ERR Telemetry

Existing telemetry order through `G/H/J/L/N/P` must remain unchanged.

New command telemetry tags, if RX is implemented:

| Tag | Meaning |
| --- | --- |
| `Q` | accepted RX command count since reset |
| `X` | packed RX parser/error status |

Telemetry order with RX enabled:

```text
I/S/R
V/F/T/A/W/Y/U/B/C/M/K/Z/O/D/E/G/H/J/L/N/P/Q/X
```

`Q` value and ACK behavior:

- `Q=00000000` after reset before any host command is accepted.
- Increment by one only after a valid `!N\r\n` command schedules a note event.
- `Q` telemetry is the only ACK mechanism for the first RX slice.
- The device must not emit byte-level echo, command echo, or a standalone immediate ACK frame.
- Hosts confirm command acceptance by observing the next `Q` value after the regular report sequence reaches `P`.

`X` value:

```text
bits 31:16 = last_error_code
bits 15:0  = saturated error_count
```

Rules:

- `X=00000000` means no parser/RX errors observed since reset or clear.
- Error count saturates at `0xFFFF`.
- `Q` and `X` are appended telemetry diagnostics only. They must not appear before `E` or before `P`.
- Existing host parsers must be able to ignore `Q` and `X` as unknown tags until updated.

## Resource And Timing Gates

Hard gates for any later RX implementation:

- Full Quartus compile passes.
- TimeQuest reports setup and hold fully constrained.
- Listed TNS remains `0.000`.
- Total logic elements remain at or below `8,200 / 10,320`.
- Slow-85C `sys_clk_50m` setup slack remains at or above `+1.0 ns`.
- Slow-85C `sys_clk_50m` hold slack remains nonnegative.
- Firmware ROM remains within `1024` words.
- DSP9 usage remains `6 / 46`.
- M9K usage remains `14 / 46` unless a later decision explicitly authorizes one additional memory block for RX buffering.

Reporting requirements:

- Report LE delta versus the accepted `7,548` LE baseline.
- Report firmware ROM word count versus accepted `318` word baseline.
- Report whether RX FIFO inferred registers or memory.
- Report SOF SHA-256 and programmer checksum for the new bitstream.

## Required Simulation Plan

ModelSim compile:

- Existing design plus new RX logic and RX-specific tests compile with 0 errors.

No-command compatibility:

- Boot without host RX data.
- Existing accepted parser health still passes: `T/U/O=2`, `G=6`, `H=2`, `J/L/N=2`, `P=0`, `K=0`.
- `Q=0`, `X=0` when RX telemetry is present.

Commanded smoke:

- Send six valid `!N\r\n` commands after boot.
- Prove commanded assignment sequence `0,1,2,0,1,2` after the boot smoke.
- Expected cumulative totals: `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `Q=6`, `P=0`, `K=0`.
- Prove all three voices overlap and no clipping occurs.

Malformed input:

- Send malformed, unknown-opcode, unsupported-argument, partial, overlong, binary-byte, and telemetry-shaped input cases.
- Confirm no trigger-count or assignment-count increment for rejected input.
- Confirm `X` reports nonzero error status.

Backpressure:

- Exercise RX FIFO full/overrun behavior.
- Confirm no lockup, no audio-loop coupling, and no partial trigger.

Regression:

- Existing standalone reduced-voice regression passes.
- Existing NACK regression passes.
- Existing UART telemetry parser tests pass, with a new RX-aware expected profile if `Q/X` are added.

## Required Quartus And Hardware Plan

Quartus:

- Rebuild full bitstream because RTL/firmware will change.
- Capture resource summary, TimeQuest setup/hold, SOF SHA-256, and programmer checksum.
- Reject the build if any hard gate above fails.

Hardware no-command smoke:

- Program the new SOF.
- Capture UART from reset.
- Confirm the no-command compatibility profile `G=6`, `H=2`, `J/L/N=2`, `T/U/O=2`, `P=0`, `K=0` plus `Q=0`, `X=0`.
- Capture audio and verify no unexpected clipping or silence regression.

Hardware commanded smoke:

- Program the new SOF.
- Send six `!N\r\n` commands from the host at 10 Hz after boot.
- Capture UART and verify cumulative totals `G=12`, `H=2`, `J/L/N=4`, `T/U/O=4`, `Q=6`, `P=0`, `K=0`.
- Capture audio during the command window.

Hardware malformed smoke:

- Send at least `!X\r\n`, `!N=00000001\r\n`, and a line with 15 bytes before CRLF to exercise the exact overlong threshold.
- Confirm `X` changes and note counters do not change because of rejected commands.

## Rollback Criteria

Reject or roll back an RX implementation if any of these occur:

- TX `0x00` or status `0x04` behavior changes incompatibly.
- Control-register offsets through `0x80` change.
- Existing UART telemetry prefix through `G/H/J/L/N/P` changes order or disappears.
- No-command parser health no longer passes.
- Valid command tests do not produce the expected cumulative counts.
- Malformed input can trigger a voice.
- Firmware enters or blocks the audio sample loop.
- `mix_clip_count` is nonzero in the default smoke.
- ROM exceeds `1024` words.
- LE/timing/M9K/DSP gates fail.
- Hardware UART or audio smoke fails.

Rollback anchor:

- Restore the accepted firmware round-robin build with SOF SHA-256 `0541752C47D73CD78EE04C9B99359E55581CD8CAAFD541925526BDDFD41CBCE0` and programmer checksum `0x005B95A9`.

## Acceptance Criteria

A later UART RX implementation can be accepted only if:

- it implements exactly the command grammar and MMIO contract above;
- it keeps command effects limited to default note-event scheduling;
- it preserves boot no-command compatibility;
- it appends only `Q/X` after `P` for command telemetry;
- it passes the required simulation, Quartus, parser, UART, and audio smoke plans;
- it reports all resource, timing, ROM, SOF, checksum, and hardware evidence;
- it documents any deviation before implementation and receives a separate acceptance decision.
