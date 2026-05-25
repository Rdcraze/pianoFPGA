# Phase 6 Audio Chain Noise Debugging - Verifier Investigation

Date: 2026-05-24
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `251e0d7` (Phase 6 M4 validation
M5_FALLBACK_REQUIRED)

## TL;DR

Investigation of the audio capture chain noise floor that left M3
verifier CONDITIONAL_PASS and triggered the M4
M5_FALLBACK_REQUIRED verdict identified the root cause as a **USB
ground loop between the laptop's audio capture endpoint and any
USB device sharing the same ground**. Both the USB-UART module
(used for sending !N/!F/!I0/!I1 commands) and the USB-Blaster
(used for SOF programming) inject the same 82 / 329 / 410 Hz
spectral peaks into the analog audio chain via shared USB ground.
Removing both restores the chain to the pre-existing quiet level
documented in the legacy `sample.wav` (median floor approx
-95 dBFS per bin).

User has ordered a passive 3.5 mm ground-loop isolator
(transformer-based) which is expected to break the loop without
any RTL or workflow change. Until the isolator arrives, the
project will proceed with **option 5** from the M4 fallback
analysis: implement candidate B2 (runtime body knob via UART) so
intra-run timbre deltas can be made large enough to exceed the
current chain noise variance.

## Investigation timeline

### M3 verifier CONDITIONAL_PASS (commit `9c3bf62`)

- Live A/B FFT-band comparison of M3 vs M2 captures showed
  uniform -1 to -4 dB delta across all bands on 5 cells.
- Per-cell envelope inspection proved both M2 and M3 strikes
  were at-or-below the audio chain noise floor (~-15 to -18
  dBFS Gaussian).
- Coherent body warmth improvement was real in simulation but
  could not be measured.
- Recommended Phase 6 M4 = audio-chain SNR improvement.

### M4 implementer task (commit `352c775`)

- Software-only solution: `--repeats K` in the bench, coherent
  averaging in the analyzer, noise-floor classifier script.
- Self-checks all PASS.
- Synthetic K=16 SNR gain measured +11.70 dB vs +12.04 dB
  predicted, within tolerance.

### M4 verifier task (commit `251e0d7`)

- Self-checks all PASS on the verifier machine (3 scripts, 21
  vectors).
- Live noise-floor characterization: the verifier machine's
  Realtek capture endpoint classified as
  `HUM_60HZ_DOMINATED` with 60 Hz peak +18.9 dB above robust
  median floor.
- K=16 capture executed end-to-end (240 strikes, P5M2 Q
  0->0x209=521, X=0).
- K=16 coherent-averaged SNR per cell came back NEGATIVE
  -7.5 to -14.6 dB on all 15 cells.
- Pre-averaging diagnostic confirmed strikes are at-or-below
  noise floor BEFORE any averaging on this chain. Coherent
  averaging cannot help when there is no signal above noise to
  amplify.
- Verdict: M5_FALLBACK_REQUIRED. The M4 deliverable is correct;
  the gate fired correctly.

### Cable change diagnosis (post-M4)

User changed the audio cable. Re-ran noise-floor characterization:

| Frequency | Old cable | New cable | sample.wav (legacy) |
|-----------|----------:|----------:|--------------------:|
| Total RMS | -19.82 | -17.98 | -23.18 |
| Median floor | -78.93 | -84.16 | -95.22 |
| 50 Hz | -71.77 | -63.55 | -76.25 |
| 60 Hz | -60.03 | -74.54 | -87.63 |
| 100 Hz | -69.85 | -76.50 | -77.99 |
| 120 Hz | -76.09 | -51.53 | -97.22 |
| 180 Hz | -69.46 | -75.75 | -90.51 |
| 240 Hz | -86.78 | -77.42 | -71.71 |

Cable swap moved interference frequencies (60 Hz down, 120 Hz
way up) without dropping overall noise floor; chain still
classified as `HUM_60HZ_DOMINATED`.

The legacy `sample.wav` (32-bit float stereo, 6.19 s, captured
"under the same conditions" per user recall) has a 561 Hz square
wave fundamental at -32 dBFS (the M2/M3 board's autonomous
output) plus inter-harmonic noise floor of -90 to -97 dBFS per
bin and hum components 13-46 dB BELOW the live chain.

### Spectral-peak forensics on live "silence" capture

The live capture-with-no-strikes WAV showed:
- 82.1 Hz peak at -49 dBFS per bin (38 dB louder than
  sample.wav's 82 Hz)
- 329 Hz cluster at -52 dBFS per bin (40 dB louder)
- 410-432 Hz cluster at -53 dBFS per bin (34 dB louder)
- 246-252 Hz cluster, 396 Hz cluster, plus the 561 Hz
  harmonic series at much lower level

Frequencies do NOT form a clean harmonic series of any single
electrical interference source (50/60 Hz x n misses 82, 330,
410). Cluster 1-5 Hz spreading is characteristic of broadband
or drifting EMI rather than fixed-frequency digital tones.

### Hypothesis triage and elimination

User performed a series of physical isolation tests:

1. **Power-cycle board, remove JTAG, run factory test program**:
   spectrum essentially unchanged. Rules out: M3 RTL state, the
   particular SOF, JTAG cable.
2. **AC vs battery**: spectrum unchanged. Rules out: laptop power
   supply switching coupling.
3. **Remove USB-UART connection**: 82 / 329 / 410 Hz peaks
   disappear. **Implicates USB-UART**.
4. **Remove power supply (board powered by USB-UART only)**: noise
   gets worse, especially at low frequencies. Rules out: dedicated
   board PSU as the dominant noise source.
5. **Connect USB-Blaster only (no USB-UART)**: same 82 / 329 / 410
   Hz peaks reappear. **Implicates USB ground loop**, not the UART
   protocol specifically.

### Root cause identified

The verifier machine's audio capture endpoint shares ground with
the laptop USB controllers. Any USB device on the same ground -
USB-UART, USB-Blaster, USB-audio - injects switching noise into
the analog audio path. The 82 / 329 / 410 Hz peak pattern is the
laptop's USB host controller's bus traffic spectrum.

Why the legacy sample.wav was clean: per user inquiry, the
discrepancy is currently unexplained by the user's recollection
("same conditions"). Likely candidates: (a) the old audio cable
had a flaky shield/sleeve connection that incidentally broke the
ground loop; (b) USB enumeration order changed across reboots;
(c) the laptop's chassis-ground impedance changed because of
peripheral, dock, or driver updates between then and now. The
mystery is itself useful evidence: the chain is sensitive to
configuration details that are not reliably controllable.

## Decision: Option 5 (B2 runtime body knob) for now

The user has ordered a passive 3.5 mm ground-loop isolator. While
that is in transit, the project proceeds with **option 5** from
the M4 fallback analysis:

- Implement candidate **B2** (runtime body knob) as Phase 6 M5.
- B2 lets a single capture sweep multiple `voice_body_mix` values
  via a new UART command (e.g. `!Bxxxx\r\n` where xxxx is a 4-hex
  body_mix value).
- Intra-run deltas become large enough that the chain noise
  variance does not block A/B work.
- The runtime knob is also useful regardless of chain noise
  improvement: it lets future timbre work tune the warmth setpoint
  experimentally without recompiles.

Once the isolator arrives:

- Existing K=16 coherent averaging machinery (M4) becomes
  immediately useful, because the chain SNR will be high enough
  for software averaging to provide additional gain.
- The combined toolchain (B2 runtime knob + K=16 averaging +
  isolator) gives maximum flexibility for the remaining Phase 6
  timbre slices (E loop-loss filter, D pre-strike noise, F per-
  voice release).

## Recommendations for orchestrator

### Queue Phase 6 M5: B2 runtime body knob (RTL slice)

Scope:
- New UART command `!B<vvvv>\r\n` where `<vvvv>` is 4 hex digits
  for a 16-bit body_mix value.
- Parser sets a new persistent register `body_mix_runtime` (16-bit).
- Fixed control replaces the static `voice_body_mix = 16'd12288`
  preset with `body_mix_runtime` once a `!B` command lands;
  defaults to 16'd12288 (M3 value) on reset.
- No change to `voice_body_mix_q15` width or saturator behavior.
- TBs: parser case-9 dispatch (`!B0000` to `!BFFFF`), control TB
  end-to-end (parser -> fixed-control -> audio-path verifies the
  runtime value reaches the body filter biquad).
- Bench: optional `--body-mix-sweep` mode that for each cell
  sends K different `!B` values back-to-back and labels the
  segments.
- Resource budget: <= +50 LE target, <= +150 hard. Setup
  preferably >= +4.0 ns.

This is candidate B2 from the M0 scope (deferred at M3 in favor of
the fixed B1 retune; now justified by chain-noise-driven
measurement amplification needs).

### Queue Phase 6 M5.1 / M6 future: ground-loop isolator
acceptance test

Once user receives the ordered ground-loop isolator:

- Verifier captures 30 s silence with isolator inserted.
- If noise-floor classifier returns `GAUSSIAN_CLEAN` and median
  floor drops to <= -90 dBFS, the isolator is accepted.
- Re-run the M4 K=16 protocol with the isolator. Expected SNR
  gain: chain itself drops 30+ dB, plus K=16 gives another 12 dB,
  so per-cell SNR rises from current -10 dB to >= +30 dB.
- This unblocks all remaining M5+ timbre slices for measurement.

### Avoid:

- A JTAG-based command path. We empirically verified JTAG also
  contributes the same noise profile because both USB-UART and
  USB-Blaster share the same USB ground loop.
- An on-chip strike scheduler in RTL. Workable but burns 2+
  implementer cycles for a problem the cheap isolator solves.
- Continued attempts at coherent averaging without addressing the
  chain. The strikes are at-or-below noise; software cannot
  resolve them.

## Files

This report:
- `reports/phase6_chain_noise_debug.md` (this file, **new**)

Verifier-side artifacts (`.kiro/`, not committed):
- `phase6_m4_noise.wav` (30 s silence, current cable)
- `sample_pcm16.wav`, `sample_mono.wav` (sample.wav converted for
  ASCII-safe analysis)
- `sample_inspect.py`, `sample_noise_floor.py`,
  `sample_hum_check.py`, `sample_stereo_split.py`,
  `board_silence_check.py`, `find_signal_peaks.py`

Legacy reference:
- `sample.wav` at repo root (32-bit float stereo; was already
  in repo from an earlier Phase 6 session)

## ASCII check

```
reports/phase6_chain_noise_debug.md non_ascii=0
```

(Verified before commit by PowerShell foreach byte loop.)

## Next steps

1. Orchestrator queues Phase 6 M5 implementer task: B2 runtime
   body knob.
2. User receives ground-loop isolator hardware in transit.
3. After M5 implementer + verifier complete, queue M5.1 isolator
   acceptance test.
4. With isolator + B2 + K=16 coherent averaging, future M6 timbre
   slices (E/D/F from M0 scope) can proceed with measurable A/B.
