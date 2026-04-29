# Phase 1C Three-Voice ABI And Control Contract

Date: 2026-04-28
Agent: Codex implementer
Task: `task-77f70773`

## Purpose

Document the accepted three-voice register and UART ABI, classify current diagnostics, define prefix-compatible parsing rules, reserve the future scheduler/control extension area, and provide implementation-ready acceptance criteria for a later firmware-owned round-robin slice.

This memo is documentation only. It does not authorize or implement RTL, firmware, constraints, clocks, MIF/build scripts, register behavior, UART behavior, scheduler logic, dispatcher logic, a fourth voice, SDRAM, richer physics, sample playback, UI, CPU/ISA expansion, exact-48-kHz clock work, voice stealing, per-note state, or per-voice parameter banks.

## Accepted Baseline Identity

The current accepted hardware baseline is the Phase 1C three-voice feasibility build:

- SOF SHA-256: `91784AE1B85E69F989D4CD09273466E14A6FAB66A557AD8ACDA296F990A07A0E`
- Programmer checksum: `0x005B2137`
- Logic elements: `7,548 / 10,320`
- Dedicated registers: `3,275`
- Memory bits: `80,896 / 423,936`
- M9Ks: `14 / 46`
- DSP9 elements: `6 / 46`
- Slow-85C `sys_clk_50m` setup slack: `+3.675 ns`
- Slow-85C `sys_clk_50m` hold slack: `+0.433 ns`
- Slow-85C `sys_clk_50m` Fmax: `61.26 MHz`

The previous feasibility stop gate was `8,200` LEs, leaving `652` LEs of margin below that gate. Future control work should avoid spending FPGA logic until explicitly authorized.

## Memory Map

Current architectural base addresses:

| Region | Base | Size | Notes |
| --- | ---: | ---: | --- |
| ROM | `0x00000000` | `0x00001000` | `1024 x 32` boot ROM |
| RAM | `0x00010000` | `0x00001000` | `1024 x 32` data RAM |
| Control registers | `0x40000000` | page-local offsets below | 32-bit MMIO |
| UART MMIO | `0x40001000` | `0x00` TX data, `0x04` status | 32-bit MMIO |

## Control Register ABI

All current control registers are 32-bit word accesses at `PHASE0_CTRL_BASE + offset`.

Existing offsets through `0x6C` are frozen for prefix compatibility. The accepted voice2 additions occupy `0x70` through `0x80`. Future scheduler/control additions must start at `0x84` or later unless a later acceptance decision explicitly revises this contract.

| Offset | Name | Access | Architectural role |
| --- | --- | --- | --- |
| `0x00` | `PHASE0_REG_IDENT` | RO | identity value `0x50303031` |
| `0x04` | `PHASE0_REG_CONTROL` | RW/pulse bits | audio/tone/wave and legacy trigger/config pulses |
| `0x08` | `PHASE0_REG_PHASE_STEP` | RW | legacy phase-step control |
| `0x0C` | `PHASE0_REG_GAIN` | RW | legacy gain control |
| `0x10` | `PHASE0_REG_DECAY_STEP` | RW | legacy decay control |
| `0x14` | `PHASE0_REG_CODEC_CFG` | RW | codec configuration word |
| `0x18` | `PHASE0_REG_STATUS` | RO | fabric status aggregate |
| `0x20` | `PHASE0_REG_VOICE_CONTROL` | RW/pulse bits | voice0 enable, trigger, reset, bypass, clip clear |
| `0x24` | `PHASE0_REG_VOICE_STATUS` | RO | voice0 status word |
| `0x28` | `PHASE0_REG_VOICE_VELOCITY` | RW | shared reduced-voice velocity |
| `0x2C` | `PHASE0_REG_VOICE_LOOP_LEN` | RW | shared reduced-voice loop length |
| `0x30` | `PHASE0_REG_VOICE_LOOP_GAIN` | RW | shared reduced-voice loop gain |
| `0x34` | `PHASE0_REG_VOICE_DAMP_MIX` | RW | shared reduced-voice damping mix |
| `0x38` | `PHASE0_REG_VOICE_DISP_COEFF` | RW | shared reduced-voice dispersion coefficient |
| `0x3C` | `PHASE0_REG_VOICE_BODY_MIX` | RW | shared reduced-voice body mix |
| `0x40` | `PHASE0_REG_VOICE_SAMPLE_COUNT` | RO | shared audio sample tick count |
| `0x44` | `PHASE0_REG_VOICE_TRIGGER_COUNT` | RO | voice0 trigger count |
| `0x48` | `PHASE0_REG_VOICE_ACTIVE_COUNT` | RO | voice0 active sample count |
| `0x4C` | `PHASE0_REG_VOICE_VALID_COUNT` | RO | voice0 valid sample count |
| `0x50` | `PHASE0_REG_VOICE_DIAG_CONTROL` | WO/pulse | diagnostic counter clear |
| `0x54` | `PHASE0_REG_VOICE1_CONTROL` | RW/pulse bits | voice1 enable, trigger, reset, clip clear |
| `0x58` | `PHASE0_REG_VOICE1_STATUS` | RO | voice1 status word |
| `0x5C` | `PHASE0_REG_VOICE1_TRIGGER_COUNT` | RO | voice1 trigger count |
| `0x60` | `PHASE0_REG_VOICE1_ACTIVE_COUNT` | RO | voice1 active sample count |
| `0x64` | `PHASE0_REG_VOICE1_VALID_COUNT` | RO | voice1 valid sample count |
| `0x68` | `PHASE0_REG_VOICE_MIX_STATUS` | RO | final mix status word |
| `0x6C` | `PHASE0_REG_VOICE_MIX_CLIP_COUNT` | RO | final mix clip count |
| `0x70` | `PHASE0_REG_VOICE2_CONTROL` | RW/pulse bits | voice2 enable, trigger, reset, clip clear |
| `0x74` | `PHASE0_REG_VOICE2_STATUS` | RO | voice2 status word |
| `0x78` | `PHASE0_REG_VOICE2_TRIGGER_COUNT` | RO | voice2 trigger count |
| `0x7C` | `PHASE0_REG_VOICE2_ACTIVE_COUNT` | RO | voice2 active sample count |
| `0x80` | `PHASE0_REG_VOICE2_VALID_COUNT` | RO | voice2 valid sample count |

## Bit-Level Control Contract

`PHASE0_REG_CONTROL`:

| Bit(s) | Meaning |
| --- | --- |
| `0` | audio enable |
| `1` | tone enable |
| `5:4` | legacy waveform selector |
| `8` | legacy trigger strobe |
| `9` | codec config valid pulse |

`PHASE0_REG_VOICE_CONTROL`:

| Bit | Meaning |
| --- | --- |
| `0` | voice0 enable |
| `1` | voice0 trigger strobe |
| `2` | voice0 reset strobe |
| `3` | body bypass |
| `4` | dispersion bypass |
| `8` | voice0 clip clear strobe |

`PHASE0_REG_VOICE1_CONTROL` and `PHASE0_REG_VOICE2_CONTROL`:

| Bit | Meaning |
| --- | --- |
| `0` | voice enable |
| `1` | voice trigger strobe |
| `2` | voice reset strobe |
| `8` | voice clip clear strobe |

`PHASE0_REG_VOICE_DIAG_CONTROL`:

| Bit | Meaning |
| --- | --- |
| `0` | clear current voice/mix diagnostic counters |

Voice status words at `0x24`, `0x58`, and `0x74`:

| Bit(s) | Meaning |
| --- | --- |
| `0` | active |
| `1` | excite busy |
| `2` | clip seen |
| `3` | sample valid |
| `4` | voice enabled |
| `31:16` | peak level |

Mix status word at `0x68`:

| Bit(s) | Meaning |
| --- | --- |
| `0` | any voice active |
| `1` | any voice excite busy |
| `2` | mix clip seen |
| `3` | any voice sample valid |
| `4` | preserved legacy voice1-enable field |
| `31:16` | final saturated mix peak level |

The low bits of `0x68` are intentionally preserved from the accepted build. Future consumers should treat the word as the accepted final-mix status, not as a general scheduler status field.

## UART ABI

The firmware emits ASCII frames:

```text
TAG=XXXXXXXX\r\n
```

Rules:

- `TAG` is a single uppercase ASCII letter.
- `XXXXXXXX` is exactly eight uppercase hexadecimal digits.
- Frames end with CRLF.
- Consumers must parse by tag, not by byte count.
- Consumers must ignore unknown tags.
- Existing tags must remain prefix-compatible and in order.
- New tags must be appended after the current sequence unless a later acceptance decision explicitly revises the ABI.
- Consumers must tolerate capture starting mid-frame and recover at the next valid CRLF-terminated frame.

Current startup/control stream:

| Tag | Meaning | Contract status |
| --- | --- | --- |
| `I` | identity register | architectural |
| `S` | status after codec-init wait | architectural startup diagnostic |
| `R` | fabric status snapshot | architectural status diagnostic |

Current repeated voice/mix diagnostic sequence:

| Tag | Register source | Meaning | Contract status |
| --- | --- | --- | --- |
| `V` | `0x24` | voice0 status | architectural diagnostic |
| `F` | `0x40` | sample count | architectural diagnostic, exact value is smoke-only |
| `T` | `0x44` | voice0 trigger count | architectural diagnostic |
| `A` | `0x48` | voice0 active count | architectural diagnostic, exact value is smoke-only |
| `W` | `0x4C` | voice0 valid count | architectural diagnostic, exact value is smoke-only |
| `Y` | `0x58` | voice1 status | architectural diagnostic |
| `U` | `0x5C` | voice1 trigger count | architectural diagnostic |
| `B` | `0x60` | voice1 active count | architectural diagnostic, exact value is smoke-only |
| `C` | `0x64` | voice1 valid count | architectural diagnostic, exact value is smoke-only |
| `M` | `0x68` | final mix status | architectural diagnostic |
| `K` | `0x6C` | final mix clip count | architectural diagnostic |
| `Z` | `0x74` | voice2 status | architectural diagnostic |
| `O` | `0x78` | voice2 trigger count | architectural diagnostic |
| `D` | `0x7C` | voice2 active count | architectural diagnostic, exact value is smoke-only |
| `E` | `0x80` | voice2 valid count | architectural diagnostic, exact value is smoke-only |

Default-smoke values such as `V=08220010`, `M=18660010`, or `K=00000000` are validation signatures, not permanent ABI constants. Parsers should decode status fields and counters rather than hard-coding those values.

## Diagnostic Classification

Architectural diagnostics:

- register offsets and access class;
- bit layouts for current control/status words;
- UART tag names and prefix order;
- per-voice trigger counts;
- per-voice status words;
- final mix status and mix clip count;
- diagnostic clear behavior;
- future additions must be post-`0x80` and prefix-compatible.

Smoke-test-only observations:

- exact active/valid/sample count values after a wall-clock capture interval;
- exact UART capture byte count;
- exact audio onset, RMS, crest factor, and F0 values;
- exact SOF hash as a software ABI dependency;
- exact default peak values except where a test explicitly validates the default smoke signature;
- current resource/timing numbers as parser behavior.

Baseline build identity:

- SOF SHA, checksum, resources, and timing are acceptance evidence and rollback anchors.
- They are not software ABI fields, but they are go/no-go evidence for any bitstream-changing task.

## Future Scheduler/Control Reservation

The current accepted register map ends at `0x80`. Reserve `0x84` and above for future scheduler/control diagnostics.

Recommended future scheduler observability block, if later authorized:

| Proposed offset | Proposed field | Purpose |
| --- | --- | --- |
| `0x84` | scheduler status | enable/idle/busy flags, last selected voice, last error/status |
| `0x88` | scheduler event count | total note events accepted by firmware policy or hardware front-end |
| `0x8C` | voice0 assignment count | events assigned to voice0 |
| `0x90` | voice1 assignment count | events assigned to voice1 |
| `0x94` | voice2 assignment count | events assigned to voice2 |
| `0x98` | drop count | events dropped because they were invalid, too fast, or unsupported |
| `0x9C` | steal count | reserved; must remain zero for a no-stealing first slice |
| `0xA0` | scheduler clip snapshot/count | either mirrors `0x6C` at event checkpoints or remains reserved if `0x6C` is sufficient |
| `0xA4` | last error detail | optional extended error code |

For the later firmware-owned round-robin slice, prefer no new RTL registers. If diagnostics are needed, append UART frames first. If registers are explicitly authorized, use the post-`0x80` block and keep all old offsets unchanged.

Recommended future UART tags, if later authorized:

| Tag | Meaning |
| --- | --- |
| `G` | scheduler event count |
| `H` | last selected voice / scheduler status |
| `J` | voice0 assignment count |
| `L` | voice1 assignment count |
| `N` | voice2 assignment count |
| `P` | drop/steal count or packed policy error count |

These tags are only reservations. They do not exist in the current accepted firmware stream.

## Later Firmware Round-Robin Acceptance Criteria

A later firmware-owned round-robin task should be accepted only if all applicable criteria pass.

Scope criteria:

- no RTL changes unless explicitly authorized;
- no register behavior changes before `0x84`;
- no UART behavior changes except appended frames after the current `Z/O/D/E` sequence;
- no hardware dispatcher;
- no fourth voice;
- no voice stealing;
- no per-note state;
- no per-voice parameter banks;
- no CPU participation in the audio sample loop;
- no SDRAM, richer physics, sample playback, UI, larger CPU/ISA, or exact-48-kHz work.

Firmware criteria:

- firmware builds cleanly;
- ROM image remains within `1024` words;
- firmware assignment policy is simple round-robin over voice0, voice1, voice2;
- firmware event handling remains low-rate note-event control, not audio-rate processing;
- any new UART scheduler frames are appended and documented.

Simulation criteria:

- standalone reduced-voice regression passes;
- top simulation drives at least six note events;
- assignment sequence is proven as `0,1,2,0,1,2`;
- per-voice trigger counts match assignment counts;
- all three voices overlap in the default overlap test;
- final mix uses the existing saturated path;
- default smoke case has `mix_clip_count=0`;
- existing UART prefix through `V,F,T,A,W,Y,U,B,C,M,K` is unchanged;
- current voice2 frames `Z,O,D,E` remain present and ordered;
- NACK regression passes.

Hardware criteria:

- USB-Blaster programming succeeds if a new bitstream/MIF is generated;
- UART capture proves assignment counts and current prefix compatibility;
- audio smoke is required if the event cadence is intended to be audible;
- hardware smoke must show no unexpected clipping in the default case.

Quartus/TimeQuest criteria if any RTL or hardware project output changes are made:

- full Quartus compile passes;
- LE use remains at or below `8,200 / 10,320` unless a later decision revises the gate;
- slow-85C `sys_clk_50m` setup slack remains at or above `+1.0 ns`;
- setup and hold are fully constrained;
- all listed TNS values remain `0.000`;
- voice delay-line M9K mapping does not regress;
- voice multiplier DSP mapping does not regress;
- any new M9K/DSP use is explicitly explained.

## Parser Guidance

Recommended UART parser behavior for tools and tests:

- scan for valid `TAG=XXXXXXXX` frames;
- ignore bytes before the first valid frame;
- keep the latest value per tag;
- allow repeated report cycles;
- treat unknown tags as future extensions;
- assert required tags are present for a given test mode;
- do not assume a fixed byte count or fixed total frame count;
- do not treat exact active/valid/sample counts as ABI constants.

Minimum required tags for current three-voice health:

- `I`, `S`, `R`;
- `V`, `T`;
- `Y`, `U`;
- `Z`, `O`;
- `M`, `K`.

Recommended current smoke assertions:

- `I == 0x50303031`;
- trigger counts `T`, `U`, and `O` are `1` in the fixed-trigger smoke;
- voice status tags `V`, `Y`, and `Z` report enabled and nonzero peak after the note;
- `M` reports a nonzero mix peak;
- `K == 0` for the default no-clipping smoke;
- active/valid/sample counters are nonzero or monotonic, not exact constants.

## Recommendation

Use this ABI/control contract as the gate document before any scheduler implementation.

Recommended next implementation direction, after this memo is validated and accepted:

1. Authorize a firmware-owned round-robin slice only.
2. Prefer using existing registers and appended UART diagnostics.
3. Keep hardware dispatcher, fourth voice, voice stealing, per-note state, and per-voice parameter banks gated.
4. Re-run the acceptance criteria above before promoting any scheduler-capable build.
