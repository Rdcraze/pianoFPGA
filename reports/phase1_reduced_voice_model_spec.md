# Phase 1 Reduced Piano Voice Model Spec

Date: `2026-04-24`
Task: `task-8baad913`
Role: `manual-reader`

## Purpose

This is the implementation-facing Phase 1 voice target. It intentionally stops short of a full piano engine: one fixed note, one reduced digital-waveguide string, a lightweight hammer/excitation model, simple damping/dispersion, optional tiny body coloration, and CPU-visible control/status registers.

No RTL or firmware changes are made by this report.

## Source Basis

Local sources reviewed:

- `docs/project_brief.md`
- `docs/platform_decisions.md`
- `docs/phase0_impl_notes.md`
- `reports/phase0_board_io_timing_requirements.md`
- `reports/phase0_board_io_timing_model_report.md`
- `reports/phase0_audio_path_hardware_validation.md`
- `rtl/audio/phase0_sample_gen.v`
- `rtl/audio/phase0_audio_path.v`
- `rtl/control/phase0_control_regs.v`
- `fw/phase0/phase0_hw.h`

No local piano-modeling paper PDFs were found. The modeling direction therefore follows the project brief's summarized literature conclusion: a reduced digital-waveguide string is the right first hardware model on EP4CE10, while full modal banks and finite-difference/PDE methods are later work.

## Algorithm Choice

The Phase 1 algorithm should be a reduced implementation of the Bensa et al. (2003) string-model direction as summarized in `docs/project_brief.md`: a physical string model mapped to a digital-waveguide realization.

This is not a verbatim implementation of a full paper model. It is the smallest hardware-owned subset that preserves the useful part for this board:

- delay-line string state
- feedback loss filter for damping
- first-order allpass for fractional delay and a placeholder dispersion effect
- deterministic short hammer/excitation burst
- optional tiny post-string body coloration

Reason for choosing this path:

- It maps directly to one small circular RAM plus a few filters, which fits EP4CE10 far better than a modal resonator bank or finite-difference mesh.
- It is physically motivated enough to produce a struck-string decay rather than another oscillator test tone.
- It keeps the CPU out of the per-sample loop, matching the project split in `docs/project_brief.md`.
- It gives a clean upgrade path: later phases can add multi-string coupling, better hammer nonlinearity, and modal/body stages without discarding the Phase 1 loop.

The Bank et al. (2003) work is used as the architectural tradeoff justification: choose a reduced hammer/string/body split that is efficient enough for the board. The Bank/Zambon/Fontana (2010) modal direction is intentionally deferred because its resonator-bank arithmetic is a worse first fit for the current resource/timing budget.

Current platform constraints that matter for Phase 1:

- FPGA: `EP4CE10F17C8`, about `10320` logic elements, `423936` memory bits, `46` embedded 9-bit multipliers, `2` PLLs.
- Current Phase 0 fit after board-I/O timing work: `4796` logic elements, `1520` registers, `262144` memory bits, `1` PLL, `2` embedded 9-bit multipliers.
- Current codec contract: `audio_mclk = 12.000 MHz`, codec direct-MCLK mode, `audio_bclk = 1.500 MHz`, nominal `audio_lrc = 46.875 kHz`.
- The CPU is present for control/status only. The audio-rate voice loop must be custom RTL and must continue producing samples if the CPU is idle after a trigger.

## Phase 1 Target

Implement a single A4 reduced piano-like voice:

- Fixed pitch: `A4`, target `440 Hz`.
- Sample rate: use the current nominal `46.875 kHz`; do not change the codec clocking contract in Phase 1.
- Output: signed 16-bit mono sample, sent to both left and right codec channels by the existing audio path.
- Voice type: one-loop reduced digital waveguide / Karplus-Strong-family struck string, not a software oscillator.
- Trigger: one register write arms a hammer strike; the RTL owns the per-sample excitation and decay.
- Default behavior after reset: Phase 1 voice enabled and silent until triggered. Do not restore the old continuous square tone as the default user-facing sound.

## String Model

Use one circular delay line plus a small feedback loop. This is a reduced implementation of a two-rail waveguide: for Phase 1 the round-trip behavior is what matters, so a single loop is enough.

Default tuning:

- `Fs = 46875 Hz`
- `f0 = 440 Hz`
- ideal period: `Fs / f0 = 106.5340909 samples`
- integer delay: `106` samples
- fractional correction: `0.5340909 samples`
- backing storage: `128` entries, power-of-two addressing

The loop should run once per `sample_tick`:

```text
dl       = delay[rd_addr]
disp     = allpass(dl)
lp       = lowpass(disp)
fb       = loop_gain * lp
write    = saturate_q18(fb + excitation)
delay[wr_addr] = write
voice    = body_filter(disp)
```

Delay addressing:

- Use a `7-bit` write pointer for the `128` entry RAM.
- Read address is `write_ptr - loop_len`.
- Default `loop_len = 106`.
- Legal register range: `32..127`; clamp or ignore out-of-range writes.
- For this first fixed note, `loop_len` may be implemented as a register-backed constant rather than a general note scheduler.

## Fixed-Point Format

Use saturating fixed-point arithmetic. Do not allow wraparound in the audio feedback path.

Recommended formats:

- Delay/state samples: signed `Q1.17`, `18-bit`.
- Internal multiply inputs: signed `18-bit` sample by signed/unsigned `Q1.15` coefficient.
- Internal multiply result: keep at least `34-bit`, round back to `Q1.17`.
- Intermediate adder/accumulator: at least signed `24-bit`; `32-bit` is acceptable if simpler.
- Codec output: signed `Q1.15`, `16-bit`, saturated from the post-body `Q1.17` sample.
- Control coefficients: `Q1.15`, where `0x7FFF` is just under `1.0`.

Default coefficients:

- `loop_gain_q15 = 32640` (`0.9960828`), approximately a 4 second T60 at A4 when applied once per loop.
- `damp_mix_q15 = 16384` (`0.5`), a simple two-point average/one-pole damping default.
- `disp_coeff_q15 = 9952` (`0.3037037`), first-order allpass coefficient for the `0.5340909` sample fractional correction.
- `body_mix_q15 = 8192` (`0.25`), used only if the tiny body coloration block is enabled.

Saturation policy:

- Saturate delay writes to signed `Q1.17`.
- Saturate final output to signed `Q1.15`.
- Maintain a sticky `clip_seen` status bit when either saturation occurs.
- Provide a write-one-to-clear bit for `clip_seen`.
- Default trigger velocity and excitation scale must not clip with the default coefficients.

## Loop Filters

### Fractional/Dispersion Allpass

Use a first-order allpass:

```text
y[n] = x[n-1] + a * (x[n] - y[n-1])
```

Default:

- `a = 0.3037037`
- `disp_coeff_q15 = 9952`

This gives the first implementation two useful properties:

- It corrects the A4 loop length from integer `106` samples toward the current `46.875 kHz` rate.
- It introduces a small phase-dependent effect that is acceptable as a placeholder for real piano-string stiffness/dispersion.

If resource pressure is unexpectedly high, the allpass may be bypassed for first bring-up, but then the acceptance pitch window must use the actual integer-delay pitch. The expected integer alternatives are:

- `106` samples: `442.217 Hz`
- `107` samples: `438.084 Hz`

### Damping Lowpass

Use a stable lowpass in the feedback path:

```text
lp[n] = (1 - damp_mix) * disp[n] + damp_mix * lp[n-1]
```

Default `damp_mix = 0.5` may be implemented as a shift-friendly average:

```text
lp[n] = (disp[n] + lp[n-1]) >>> 1
```

This damps high frequencies faster than the fundamental and is the main difference between a struck/plucked string decay and the Phase 0 square/saw tone.

## Hammer/Excitation

Do not implement nonlinear hammer contact solving in Phase 1. Use a deterministic short force burst that is cheap, repeatable, and testable.

On trigger:

- Clear the delay line and filter state unless `legato_restrike` is explicitly enabled later.
- Start a `16` sample excitation burst.
- Scale the burst by `velocity_q15`.
- Add the burst at the delay-line write point before saturation.
- Set `active` when the trigger is accepted.

Default velocity:

- `velocity_q15 = 0x4000` (`0.5`)

Default excitation ROM, normalized `Q1.15` half-sine:

```text
6021, 11837, 17250, 22075,
26149, 29332, 31516, 32627,
32627, 31516, 29332, 26149,
22075, 17250, 11837, 6021
```

Apply a fixed `excite_shift = 2` after velocity scaling for the default build. That keeps the initial injected energy below full scale and gives the loop room for filter transients:

```text
excitation_q18 = (rom_q15 * velocity_q15) >>> (15 + excite_shift - 2)
```

The exact bit slicing may differ in RTL, but the default trigger must produce a fast attack without clipping.

## Optional Tiny Body Coloration

A full soundboard/body model is out of scope. If Phase 1 has resource headroom after the string loop, add a tiny post-string coloration block:

```text
body[n] = x[n] + (x[n-7] >>> 2) - (x[n-17] >>> 3) + (x[n-31] >>> 4)
```

Implementation notes:

- Use a `32` sample shift register or small RAM.
- Saturate the body output before the final 16-bit codec conversion.
- Provide a `body_bypass` control bit.
- If timing/resource pressure appears, bypass the body block and keep the rest of the model intact.

## Control Register Contract

Preserve the existing Phase 0 register offsets through `0x18` so current firmware/debug tools do not break:

- `0x00 IDENT`
- `0x04 CONTROL`
- `0x08 PHASE_STEP`
- `0x0C GAIN`
- `0x10 DECAY_STEP`
- `0x14 CODEC_CFG`
- `0x18 STATUS`

Add Phase 1 voice registers starting at `0x20`:

| Offset | Name | Reset | Description |
|---:|---|---:|---|
| `0x20` | `VOICE_CONTROL` | `0x00000001` | bit 0 `voice_enable`; bit 1 write-one `trigger`; bit 2 write-one `reset_voice`; bit 3 `body_bypass`; bit 4 `disp_bypass`; bit 8 write-one `clip_clear` |
| `0x24` | `VOICE_STATUS` | status | bit 0 `active`; bit 1 `excite_busy`; bit 2 `clip_seen`; bit 3 `sample_valid`; bit 4 `voice_enabled`; bits `31:16` optional peak meter |
| `0x28` | `VOICE_VELOCITY` | `0x00004000` | unsigned `Q1.15`; legal `0..0x7FFF` |
| `0x2C` | `VOICE_LOOP_LEN` | `106` | active integer loop delay; legal `32..127` |
| `0x30` | `VOICE_LOOP_GAIN` | `32640` | unsigned `Q1.15` |
| `0x34` | `VOICE_DAMP_MIX` | `16384` | unsigned `Q1.15` |
| `0x38` | `VOICE_DISP_COEFF` | `9952` | signed `Q1.15`; first-order allpass coefficient |
| `0x3C` | `VOICE_BODY_MIX` | `8192` | optional body amount; may be ignored if body block is bypassed |

Firmware behavior:

- Firmware may trigger the voice by writing `VOICE_CONTROL.trigger = 1`.
- Firmware must not service the audio sample loop.
- Firmware may poll `VOICE_STATUS.active` and `VOICE_STATUS.clip_seen`.
- Existing UART/status reporting should include enough information to confirm voice active/clip state during board tests.

## Integration Direction

Recommended RTL decomposition:

- Replace or bypass `phase0_sample_gen` with a new `phase1_reduced_voice` module.
- Keep `phase0_audio_path` as the codec-facing shell if that minimizes churn.
- Keep the current `sample_tick` contract; the voice advances only on `sample_tick`.
- Keep the existing codec/I2C/audio timing model unchanged.
- Extend `phase0_control_regs` rather than replacing the control bus.

Resource budget for acceptance:

- Total fitted design should remain below `7000 / 10320` logic elements.
- Total embedded multipliers should remain at or below `12 / 46` 9-bit multipliers.
- Total memory bits should remain below `300000 / 423936`.
- PLL count should remain `1 / 2`.
- TimeQuest should remain fully constrained with nonnegative setup and hold slack on `sys_clk_50m`, `i2c_clk`, and `audio_bclk`.

These are budgets, not predictions. They leave headroom above the current Phase 0 fit while preventing the first voice from consuming the whole device.

## Objective Simulation Acceptance

A Phase 1 RTL/testbench pass should demonstrate:

- Reset leaves the voice silent, with delay/filter state cleared.
- A trigger write produces nonzero samples within `5 ms`.
- With default velocity and coefficients, `clip_seen` remains clear.
- Output is bounded for at least `5 seconds` of simulated audio.
- The dominant frequency after the attack is within `440 Hz +/- 15 Hz` when the fractional allpass is enabled.
- If the allpass is bypassed for bring-up, the measured frequency is within `+/- 5 Hz` of the selected integer-delay pitch (`442.217 Hz` for `106`, or `438.084 Hz` for `107`).
- RMS envelope measured in `20 ms` windows decays after the first `100 ms`; small ripple is acceptable, sustained growth is not.
- RMS level drops by at least `20 dB` by `3 seconds` after trigger with default coefficients.
- CPU idling after the trigger does not stop sample generation.
- Existing Phase 0 codec-init, UART, happy-path, and NACK-path simulations still pass or have documented intentional updates.

## Hardware Acceptance

Board validation should verify:

- Existing codec bring-up still reports success over UART.
- `audio_mclk`, `audio_bclk`, `audio_lrc`, and `audio_dacdat` retain the Phase 0 clocking contract.
- A single trigger produces a decaying tone, not a continuous square wave.
- External audio capture estimates the fundamental near `440 Hz +/- 15 Hz` with the fractional allpass enabled.
- Attack is audible/visible within `50 ms` of trigger.
- Envelope decays by at least `12 dB` over the first `2 seconds`.
- No obvious flat-topped clipping in the analog capture; target clipped sample fraction below `1%`.
- Left and right output remain matched because the Phase 1 voice is mono-to-dual-mono.

## Explicit Deferrals

Do not include these in Phase 1:

- Polyphony.
- Pedal or damper resonance.
- Multi-string unison/coupled strings.
- SDRAM use.
- Exact `48 kHz` codec rework.
- Full modal body/soundboard bank.
- Finite-difference/PDE mesh.
- Nonlinear hammer contact solver.
- MIDI, keyboard scanning, TFT/touch UI, or sample playback.

The point of Phase 1 is to replace the Phase 0 test tone with one stable, hardware-owned, physically motivated piano-like decay while keeping the board timing and SoC base under control.
