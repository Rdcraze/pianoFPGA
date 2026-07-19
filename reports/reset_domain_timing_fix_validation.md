# Reset-Domain Timing Fix Validation

Date: 2026-07-19
Branch: `codex/phase1c-uart-boundary-fix`
Baseline commit: `17dfe77`

## Result

PASS for the reset-domain timing correction. The previous I2C-domain removal
failure is eliminated. All reported setup, hold, recovery, removal, and minimum
pulse-width checks now have positive slack and zero TNS at all three timing
corners.

The broader project audit found pre-existing verification debt described below;
none of those findings is caused by the reset change.

## Implementation

- `rtl/peripherals/wm8978_codec_stub.v`
  - adds local asynchronous-assert/synchronous-deassert reset synchronizers for
    `i2c_clk` and `audio_bclk`;
  - uses the synchronized resets in codec-domain logic, the boot sequencer, and
    the DAC transmitter;
  - retains the system-domain reset on the I2C clock divider so the divider can
    start and release the I2C-domain synchronizer.
- `rtl/peripherals/wm8978_i2c_ctrl.v`
  - separates the system-domain divider reset from the local I2C-domain reset.
- `rtl/control/phase0_fixed_control.v`
  - resets `voice_damp_mix_reg` to the parser's constant `16'h4000` default;
  - avoids unsupported variable asynchronous initialization and removes the 15
    latch-equivalent circuits previously inferred by Quartus.
- `quartus/phase0/piano_phase0_top.sdc`
  - limits the false-path exception to the first stage of the I2C/audio reset
    synchronizers, which are the intentional asynchronous boundaries;
  - system-domain and downstream local recovery/removal paths remain timed.

## Timing and resources

| Metric | Before | After | Result |
| --- | ---: | ---: | --- |
| LE | 5,279 | 5,248 | -31 |
| Registers | 2,422 | 2,426 | +4 fitted registers |
| Memory bits | 20,480 | 20,480 | unchanged |
| DSP9 | 26 | 26 | unchanged |
| PLL | 1 | 1 | unchanged |
| Slow 85C setup | +5.770 ns | +5.303 ns | pass, above +4.0 ns gate |
| Worst hold | +0.155 ns | +0.140 ns | pass |
| Slow 85C removal | -0.942 ns | +1.184 ns | fixed |
| Worst-corner removal | -0.509 ns | +0.500 ns | fixed |
| Removal TNS | -63.692 ns | 0 ns | fixed |

Full Quartus compile: 0 errors, 16 warnings. TimeQuest: 0 errors, 0 warnings,
zero TNS, and fully constrained setup/hold requirements. Explicit
`check_timing` result: 0 loops, 0 latches, and one no-clock node belonging only
to Quartus's generated internal PLL-lock primitive.

Generated SOF SHA-256:
`A6B15439145B38F1DC03172D92F2E7116DEC75A02E6BDA9E0C147ECF654D3FE6`.

## Functional verification

- ModelSim compile/lint of the live RTL: 0 errors, 0 warnings.
- Dedicated codec/reset simulation:
  - two reset and reinitialization cycles;
  - local reset assertion is asynchronous and release occurs on each local
    clock edge;
  - 16 valid WM8978 boot writes after each reset;
  - no malformed transactions or NACKs;
  - DAC output active;
  - `TB_RESET_PASS`.
- UART command parser: PASS.
- UART status transmitter: PASS.
- Fixed-control reset default (`voice_damp_mix == 16'h4000`), isolation, and
  four-voice round robin: PASS.
- Body-mix unsigned saturation: PASS at `0xC000` and `0xFFFF`.
- All Python files under `scripts/`: `py_compile` PASS.
- Eleven Python UART, telemetry, capture, analyzer, and sweep test groups: PASS.
- Keyboard mapping: all 88 notes and release aliases PASS.
- Quartus source audit: all QSF source paths exist; no archived RISC-V source is
  present in the live synthesis list.

## Pre-existing findings

1. `rtl/top/piano_phase0_top_tb.v` cannot elaborate against the current design
   because it still references the retired `phase0_soc_inst` RISC-V hierarchy.
2. The reduced-voice golden test reports sample 110 as `0x0F78` while the golden
   file expects `0x0F70`. The velocity test reports the corresponding peak as
   3,960 instead of 3,952. The reset patch does not touch the voice datapath.
3. ModelSim reports existing out-of-range expression warnings in
   `phase0_uart_command.v:291` and `wm8978_i2c_ctrl.v:260`. Tests still pass, but
   the expressions should be rewritten to avoid invalid array indexing.
4. Hardware programming, analog capture, and the pending M6.6 dispersion
   spectral grid were not performed in this software verification run.

## Verdict

Promote the reset-domain correction for continued development. Do not describe
the overall repository as regression-clean until the stale top-level testbench
and reduced-voice golden drift are resolved. The latch and reset pseudo-clock
findings are closed and do not require an architectural reset redesign.
