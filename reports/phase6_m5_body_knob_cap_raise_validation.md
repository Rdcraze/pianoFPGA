# Phase 6 M5 B2 Body-Knob Reapply Validation (Revised LE Cap)

Date: 2026-05-25
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-52e7c860`
Implementer commit under review: `2fa70e8`
Implementer task: `task-3beccc57`
Implementer report: `reports/phase6_m5_body_knob_cap_raise_impl.md`
Branch: `codex/phase1c-uart-boundary-fix`

## Verdict: PASS

The B2 runtime body-mix knob is accepted as a runtime tuning /
control surface under the orchestrator's revised +200 LE cap.
All four ModelSim TBs PASS independently from a fresh work
library, Quartus full compile reproduces the implementer's
numbers exactly (LE 5,105 / 10,320 = +173 vs M3/M4 baseline,
slow-85C `sys_clk_50m` setup +4.620 ns), and live hardware
exercising on COM5 confirms valid `!B` commands advance Q
monotonically while a malformed `!BG000` produces exactly
`last_error = 0x0007` (`ERR_UNSUPPORTED_ARG`) without wedging
the parser. Existing `!N`, `!NLLLLVVVV`, `!F`, and `!I0/!I1`
behavior remains intact after `!B` activity. Final audio A/B
characterization remains pending the user-ordered passive
ground-loop transformer isolator per
`reports/phase6_chain_noise_debug.md`; this is a measurement
chain limitation, not a design defect.

| Acceptance gate | Target | Actual | Verdict |
| --- | --- | --- | --- |
| Historical NO-GO report unchanged | yes | `git diff 33e9005..2fa70e8 -- reports/phase6_m5_body_knob_impl.md` empty | PASS |
| Cap-raise follow-up report added | yes | `reports/phase6_m5_body_knob_cap_raise_impl.md` (new in `2fa70e8`) | PASS |
| Static scope: 5 RTL/TB files + 1 new report | exactly | 5 RTL/TB modifications + 1 new report; no QSF/SDC/PLL/firmware/obsolete touched | PASS |
| ASCII-only on touched files | yes | foreach byte loop confirms 0 non-ASCII across 7 checked files | PASS |
| `phase0_uart_command_tb` PASS with !B vectors | PASS | `UART_CMD_TB_PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000` | PASS |
| `phase0_fixed_control_isolation_tb` 11 assertions | PASS | `ISOLATION_TB_PASS` (11 assertions) | PASS |
| `phase0_uart_status_tx_tb` | PASS | `UART_TX_TB_PASS frames=2 collected_count=170` | PASS |
| `phase1_reduced_voice_tb` golden | bit-exact peak=3952 | `VOICE_TB_PASS first_nonzero_sample=106 ... peak=3952 golden_samples=4096` | PASS |
| Default `body_mix_runtime` = 0x3000 at reset | yes | TB vector 13 (`body_mix_default got=3000`) PASS | PASS |
| `!B0000`, `!B3000`, `!B7FFF`, `!BFFFF` update register | yes | TB vectors 14-17 PASS | PASS |
| Malformed `!BG000` -> ERR_UNSUPPORTED_ARG (7), no body_mix update | yes | TB vector 18 PASS; `last_error=7`, `body_mix=0x3000` retained | PASS |
| Quartus errors | 0 | 0 | PASS |
| LE delta vs M3/M4 baseline 4,932 | <= +200 hard | +173 (5,105) | PASS |
| Setup slow-85C `sys_clk_50m` | >= +4.0 ns | +4.620 ns | PASS |
| Hold slow-85C | clean | +0.414 ns | PASS |
| All TNS | 0 | 0 | PASS |
| M9K block count | unchanged | 8 (matches M3/M4 reapply baseline; see Note A) | PASS |
| DSP9 9-bit elements | unchanged | 26 / 46 | PASS |
| PLL | 1 / 2 | 1 / 2 | PASS |
| Quartus warnings | <= 16 | 16 (cosmetic baseline) | PASS |
| Hardware: SOF programs cleanly | yes | EP4CE10F17 configured, programmer checksum 0x00397207 | PASS |
| Hardware: valid !B advance command_count | yes | Q 0 -> 9 across 9 valid commands | PASS |
| Hardware: malformed !B raises ERR=7 without wedging | yes | X = 0x00070001 latched; no further error increments after burst | PASS |
| Hardware: existing !N/!F/!I still work | yes | bare !N, !NLLLLVVVV, !F, !I1, !I0 all counted as accepted commands | PASS |

Note A: the implementer's report says "M9K = 5". That number
matches the memory-bits utilization percentage (20,480 /
423,936 = 5%), not the block count. Quartus fit.rpt line 573
shows actual M9K = 8 across this commit, the M3/M4 baseline,
and the prior NO-GO attempt. The memory-blocks contract
"unchanged across M3/M4/M5" still holds; the documentation
inconsistency is non-blocking.

## Scope check

### Files touched in commit `2fa70e8`

```
A       reports/phase6_m5_body_knob_cap_raise_impl.md
M       rtl/control/phase0_fixed_control.v
M       rtl/control/phase0_fixed_control_isolation_tb.v
M       rtl/control/phase0_uart_command.v
M       rtl/control/phase0_uart_command_tb.v
M       rtl/top/piano_phase0_top.v
```

- No CPU / firmware / MMIO / register-file revival.
- No JTAG command path, no on-chip strike scheduler, no
  polyphony feature work.
- No QSF / SDC / PLL / obsolete archive change.
- No audio path / body filter / waveguide / hammer-ROM change.
- No reduction of physical voice instances; four
  `phase1_reduced_voice` instances preserved.
- The historical NO-GO report
  `reports/phase6_m5_body_knob_impl.md` is byte-identical
  between `33e9005` and `2fa70e8`, as required.

### ASCII check

```
rtl/control/phase0_uart_command.v: non-ascii=0
rtl/control/phase0_uart_command_tb.v: non-ascii=0
rtl/control/phase0_fixed_control.v: non-ascii=0
rtl/control/phase0_fixed_control_isolation_tb.v: non-ascii=0
rtl/top/piano_phase0_top.v: non-ascii=0
reports/phase6_m5_body_knob_cap_raise_impl.md: non-ascii=0
reports/phase6_m5_body_knob_impl.md: non-ascii=0
FILES_BAD=0
```

### Source spot checks

`rtl/control/phase0_uart_command.v`:

- New 16-bit output `body_mix_runtime`, reset to `16'd12288`.
- New combinational helpers `bm_hex_valid`, `parsed_body_mix`.
- New `5'd8` dispatch case for `!Bvvvv\r\n`. Valid hex updates
  `body_mix_runtime` and bumps `command_count`. Invalid hex
  raises `ERR_UNSUPPORTED_ARG` (7) and bumps `error_count`
  without changing `body_mix_runtime`. Other 8-byte forms
  starting with `!B` also raise `ERR_UNSUPPORTED_ARG`. Other
  `!`-led 8-byte forms raise `ERR_UNKNOWN_OPCODE`. Other
  8-byte forms raise `ERR_MALFORMED`.

`rtl/control/phase0_fixed_control.v`:

- New 16-bit input `body_mix_runtime`.
- `assign voice_body_mix = body_mix_runtime;` replaces the
  prior static `assign voice_body_mix = 16'd12288;`.

`rtl/top/piano_phase0_top.v`:

- New 16-bit wire `cmd_body_mix_runtime` between
  `phase0_uart_command_inst` and `phase0_fixed_control_inst`.
- Both port maps reference `cmd_body_mix_runtime`.

`rtl/control/phase0_fixed_control_isolation_tb.v`:

- DUT instantiation gains `body_mix_runtime <= 16'd12288`
  constant wiring; routing-only TB unchanged otherwise.

`rtl/control/phase0_uart_command_tb.v`:

- 7 new test vectors (default 0x3000; `!B0000`, `!B7FFF`,
  `!BFFFF`, `!B3000`; malformed `!BG000` -> ERR=7, no
  body_mix update; post-`!B` regression `!N`).
- Final pass line reports body_mix.

## ModelSim regression evidence (independent rerun)

Compiled and ran from a fresh work library at
`.kiro/msim_phase6_m5_v/` using ModelSim SE-64 10.5
(`D:\modelsim\win64\vsim.exe`).

`phase0_uart_command_tb`:
```
UART_CMD_TB_INFO body_mix_default=0x3000
UART_CMD_TB_PASS notes=6 releases=1 errors=4 isolation=1 body_mix=3000
Errors: 0, Warnings: 0
```

`phase0_uart_status_tx_tb`:
```
UART_TX_TB_INFO boot0=00000001 boot1=00000002
UART_TX_TB_INFO q0=12345678
UART_TX_TB_INFO x0=00030007
UART_TX_TB_PASS frames=2 collected_count=170
Errors: 0, Warnings: 0
```

`phase0_fixed_control_isolation_tb` (11 assertions):
```
ISO_TB_PASS normal_mode_roundrobin v0=1 v1=1 v2=1 v3=1
ISO_TB_PASS isolation_mode v0=4 v1=0 v2=0 v3=0
ISO_TB_PASS voice_index_after_isolation=0
ISO_TB_PASS voice0_params loop_len=32 vel=0x6000
ISO_TB_PASS release_in_isolation_resets_voice0 reset_count=1
ISO_TB_PASS release_in_isolation_damp=0x7FFF
ISO_TB_PASS release_in_isolation_no_trigger
ISO_TB_PASS isolated_note_after_reset
ISO_TB_PASS post_isolation_roundrobin v0=1 v1=1 v2=1 v3=1
ISO_TB_PASS release_in_normal_no_reset
ISO_TB_PASS release_in_normal_damp=0x7FFF
ISOLATION_TB_PASS
Errors: 0, Warnings: 0
```

`phase1_reduced_voice_tb` (golden bit-exact):
```
VOICE_TB_PASS first_nonzero_sample=106 freq=434.027778
  rms_100ms=272.800735 rms_500ms=27.713698 rms_3s=0.000000
  peak=3952 golden_samples=4096
Errors: 0, Warnings: 0
```

Per-TB ModelSim transcripts saved at
`.kiro/msim_phase6_m5_v/*.log` (local-only).

## Quartus full compile evidence (independent rerun)

`quartus\phase0\build.ps1 -Stage compile`:

```
Info: Quartus II 64-Bit Analysis & Synthesis was successful. 0 errors, 13 warnings
Info: Quartus II 64-Bit Fitter was successful. 0 errors, 3 warnings
Info: Quartus II 64-Bit Assembler was successful. 0 errors, 0 warnings
Info: Quartus II 64-Bit TimeQuest Timing Analyzer was successful. 0 errors, 0 warnings
Info: Quartus II 64-Bit EDA Netlist Writer was successful. 0 errors, 0 warnings
Info (293000): Quartus II Full Compilation was successful. 0 errors, 16 warnings
```

Resource and timing summary versus M3/M4 baseline:

| Metric | M3/M4 (4,932 baseline) | M5 (this commit) | Delta |
| --- | ---: | ---: | ---: |
| Total logic elements | 4,932 / 10,320 | 5,105 / 10,320 (49%) | +173 |
| Combinational | 4,707 | 4,843 | +136 |
| Registers | 2,285 | 2,305 | +20 |
| Memory bits | 20,480 / 423,936 | 20,480 / 423,936 (5%) | 0 |
| M9K block count | 8 | 8 | 0 |
| Embedded Multiplier 9-bit | 26 / 46 | 26 / 46 (57%) | 0 |
| PLL | 1 / 2 | 1 / 2 (50%) | 0 |
| Total pins | 11 / 180 | 11 / 180 (6%) | 0 |
| Slow-85C setup `sys_clk_50m` | +4.515 ns | **+4.620 ns** | +0.105 ns |
| Hold slow-85C | +0.413 ns | +0.414 ns | +0.001 ns |
| All TNS | 0 | 0 | 0 |
| Errors | 0 | 0 | 0 |
| Warnings | 16 | 16 | 0 |

Setup slack at +4.620 ns is +0.620 ns above the +4.0 ns hard
gate. Setup numbers reproduce the implementer's exactly. The
+173 LE delta is within the orchestrator's revised +200 hard
cap by 27 LE; the +120-130 LE per-voice body multiplier
unfolding cost is intrinsic to removing constant folding from
four physical voice instances.

Compile log: `.kiro/quartus_phase6_m5_verifier.log` (local-only).

## Hardware UART evidence

Quartus programmer reaches the board:

```
1) USB-Blaster [USB-0]
Info (213045): Using programming cable "USB-Blaster [USB-0]"
```

SOF identity:

- Path: `quartus/phase0/output_files/piano_phase0_top.sof`
- Length: 358,681 bytes
- Programmer checksum: `0x00397207`
- SHA-256: `1E59C516502B8E603ED66DB50A4CDEA0ED466F093351C89AF80D2E9EF2BC6F09`

Programmed cleanly:

```
Info (213011): Using programming file ... checksum 0x00397207 for device EP4CE10F17@1
Info (209016): Configuring device index 1
Info (209017): Device 1 contains JTAG ID code 0x020F10DD
Info (209007): Configuration succeeded -- 1 device(s) configured
Info: Quartus II 64-Bit Programmer was successful. 0 errors, 0 warnings
```

UART smoke (`COM5`, 115200 8N1) using
`.kiro/phase6_m5_uart.ps1`. Captured frames pre/post a 10-command
burst (full transcript at `reports/phase6_m5_hardware_uart.txt`):

Before any host command (steady state):

```
P5M2 BOOT=000000D7 TICK=004CE3BE VC=03 Q=00000000 X=00000000
P5M2 BOOT=000000D8 TICK=004D3F4C VC=00 Q=00000000 X=00000000
P5M2 BOOT=000000D9 TICK=004D9AD9 VC=02 Q=00000000 X=00000000
P5M2 BOOT=000000DA TICK=004DF667 VC=03 Q=00000000 X=00000000
```

Burst sequence (250 ms inter-command spacing):

1. `!N\r\n` (bare note)
2. `!B0000\r\n`
3. `!B3000\r\n`
4. `!B7FFF\r\n`
5. `!BFFFF\r\n`
6. `!BG000\r\n` (malformed)
7. `!F\r\n`
8. `!N006A4000\r\n` (parameterized note)
9. `!I1\r\n`
10. `!I0\r\n`

After burst (settled):

```
P5M2 BOOT=000000DB TICK=004E51F4 VC=01 Q=00000000 X=00000000
P5M2 BOOT=000000DC TICK=004EAD82 VC=02 Q=00000002 X=00000000
P5M2 BOOT=000000DD TICK=004F090F VC=02 Q=00000004 X=00000000
P5M2 BOOT=000000DE TICK=004F649D VC=02 Q=00000005 X=00070001
P5M2 BOOT=000000DF TICK=004FC02A VC=03 Q=00000007 X=00070001
P5M2 BOOT=000000E0 TICK=00501BB8 VC=03 Q=00000009 X=00070001
P5M2 BOOT=000000E1 TICK=00507745 VC=03 Q=00000009 X=00070001
... (repeats Q=00000009 X=00070001 for 7 more frames)
```

Interpretation:

- 9 valid commands (`!N`, `!B0000`, `!B3000`, `!B7FFF`,
  `!BFFFF`, `!F`, `!N006A4000`, `!I1`, `!I0`) each advance
  `Q` exactly once. Final `Q = 0x00000009` matches the count.
- The 1 malformed command (`!BG000`) raises `last_error = 7`
  (`ERR_UNSUPPORTED_ARG`) and increments `error_count` by 1,
  giving `X = 0x00070001`. `Q` does NOT advance for the
  malformed command.
- The malformed-command latch is correct: `last_error` is
  sticky-latched at 7, and `error_count` does not increment
  again because no further malformed input is sent.
- BOOT and TICK advance monotonically across the burst; VC
  cycles 00..03; the parser does not wedge after the
  malformed command (commands 7-10 keep advancing Q).
- Steady-state P5M2 frames continue at the documented ~500 ms
  cadence in the trailing 7 frames at unchanging
  `Q=0x00000009 X=0x00070001`.

This is end-to-end hardware proof that valid `!B` commands
update the runtime `body_mix_q15` register (advance Q only),
malformed `!B` is rejected through the existing error path
without wedging, and pre-existing `!N`, `!NLLLLVVVV`, `!F`,
`!I1`, `!I0` semantics are preserved after `!B` activity.

## Audio validation status

Per `reports/phase6_chain_noise_debug.md` and orchestrator
direction, final audio A/B comparison between contrasting
body_mix values is deliberately deferred to the period after
the user-ordered passive 3.5 mm transformer ground-loop
isolator arrives. The current Realtek capture path is
USB-ground-loop limited (HUM_60HZ_DOMINATED, ~-15 to -18 dBFS
floor) and cannot resolve sub-3 dB body_mix-driven warmth
deltas. M5 is therefore accepted as a **runtime tuning /
control surface** today, not as a final timbre PASS. Once the
isolator is installed, the suggested verifier protocol in the
implementer report's section 7 (K=16 coherent-averaging A/B
between `!B3000` and `!B6000`) can produce the audio gate
without touching this RTL.

## Source spot-check vs implementer report

I confirmed the implementer's section 5 file scope claims
exactly:

- `phase0_uart_command.v`: header comment for `!Bvvvv\r\n`,
  `body_mix_runtime` output port resetting to 16'd12288,
  `bm_hex_valid` and `parsed_body_mix` combinational helpers,
  5'd8 dispatch case structure, default fall-through
  recognising `!B*` as unsupported. All present and ASCII.
- `phase0_fixed_control.v`: new `body_mix_runtime` 16-bit
  input, runtime assign replacing 16'd12288 constant. Present.
- `piano_phase0_top.v`: `cmd_body_mix_runtime` wire and both
  port maps. Present at lines 105, 125, 140 (verified).
- `phase0_fixed_control_isolation_tb.v`: routing-only constant
  wiring `body_mix_runtime <= 16'd12288`. Present.
- `phase0_uart_command_tb.v`: 7 new vectors covering default,
  !B0000/7FFF/FFFF/3000, malformed !BG000, and post-!B !N
  regression; pass line reports body_mix. Verified.

## Final verdict

**PASS** under the orchestrator's revised +200 LE cap.

- Static scope clean and ASCII clean.
- Historical NO-GO report preserved unchanged.
- Four ModelSim TBs PASS independently from a fresh work
  library; reduced-voice golden TB stays bit-exact at peak=3952.
- Quartus full compile reproduces implementer numbers exactly
  (LE 5,105 = +173 vs M3/M4 baseline 4,932; setup +4.620 ns;
  hold +0.414 ns; M9K/DSP9/PLL unchanged; 0 errors; 16
  warnings).
- Live hardware on COM5 confirms valid `!B` commands advance
  command_count, malformed `!BG000` raises
  `ERR_UNSUPPORTED_ARG` (7) without wedging the parser, and
  existing `!N`/`!NLLLLVVVV`/`!F`/`!I0/!I1` behaviour remains
  intact after `!B` activity.
- Default `body_mix_runtime = 0x3000` at reset means the audio
  path comes up at the M3-accepted body warmth preset before
  any host command arrives, so prior accepted captures and
  audible behaviour are unchanged at boot.

The B2 runtime body-mix knob is therefore accepted as a
runtime tuning / control surface. Final audio A/B
characterization remains gated behind the in-transit
ground-loop isolator and is explicitly deferred per chain-noise
debug history; this is a measurement chain limit, not a design
defect.

## Artifacts

Committed:

- `reports/phase6_m5_body_knob_cap_raise_validation.md` (this
  file).
- `reports/phase6_m5_hardware_uart.txt` (concise UART smoke
  transcript: pre/post burst frames + sent command list).

Local-only (not committed, large/derived):

- `.kiro/msim_phase6_m5_v/` (ModelSim work + per-TB logs).
- `.kiro/quartus_phase6_m5_verifier.log` (Quartus compile log).
- `.kiro/phase6_m5_uart.ps1` (UART smoke runner).

ASCII-only on all committed files. No RTL, firmware, host
tool, QSF, SDC, PLL, or obsolete-archive change in the
verifier diff.
