# Phase 2 First Step Proposal

Date: 2026-05-02
Agent: claude-implementer `5ed7d08b-d179-4fdc-ada6-5e1f57099943`
Task: `task-465cee85`

## Selected Improvement

**Fixed-parameter 2-stage biquad IIR body/soundboard coloration filter** inserted after the 3-voice mix in `phase0_audio_path.v`, between `mix_sample_sat` and `tx_sample`.

This is the single lowest-risk Phase 2 entry point. It provides audible warmth and body character to the current plucked-string waveguide voices, directly addressing the Phase 2 "lightweight soundboard/body stage" objective.

## Why This Is The Best First Step

### 1. Completely Unblocked

This proposal touches none of the 17 blocked features:

| Blocked feature | Why not touched |
| --- | --- |
| SDRAM | Filter is on-chip, no external memory |
| Fourth voice | Stays at 3 voices |
| Richer physics | Fixed filter, not physics model change |
| Exact-48k PLL | No clock/PLL changes |
| Larger CPU/ISA | No CPU changes |
| Hardware dispatcher | No scheduling/dispatch logic |
| Voice stealing | No voice allocation changes |
| Per-note state | No per-note data |
| Per-voice parameter banks | No new parameter registers |
| Host-selected parameters | Fixed hardwired coefficients |
| Codec config RX | No codec configuration changes |
| Diagnostic clear RX | No diagnostic path changes |
| Sample playback | No sample playback |
| UI/TFT/touch | No UI work |
| CPU audio-loop expansion | No CPU-in-loop work |
| Non-prefix UART changes | No UART changes at all |
| Register-map changes | No new registers |

### 2. Fits Within Resource Headroom

| Resource | Available | Estimated cost | Remaining |
| --- | --- | --- | --- |
| LEs | 2,357 free (23%) | ~200 LEs | 2,157 free (21%) |
| M9Ks | 32 free (70%) | 0 M9Ks (coefficients hardwired) | 32 free (70%) |
| DSPs | 40 free (87%) | ~4 DSP elements (2 biquads) | 36 free (78%) |
| ROM | 485 words free (47%) | 0 words (no firmware change) | 485 words free (47%) |

The filter is LE-only for control logic; DSP elements handle the multiply-accumulate. Hardwired coefficients avoid M9K cost.

### 3. Audible Perceptual Improvement

The current 3-voice waveguide produces a convincing plucked-string sound, but the raw output is spectrally flat — it sounds like a string in isolation rather than a string heard through a piano body. Two biquad stages tuned to piano soundboard resonance characteristics (one low-shelf for body warmth, one peaking filter for the characteristic 100-300 Hz cabinet resonance) will add:

- Low-end warmth (bass boost below ~200 Hz)
- Midrange body (cabinet resonance around 150-250 Hz)
- Gentle high-frequency roll-off (natural soundboard absorption)

The improvement will be clearly audible in A/B comparison by ear and measurable in FFT before/after captures.

### 4. One-Session Implementation Feasibility

- **RTL**: Add one small module (`phase0_body_filter.v`) with 2 biquad stages, ~50 lines of Verilog. Wire it between `mix_sample_sat` and `tx_sample` in `phase0_audio_path.v`.
- **Firmware**: No changes.
- **Simulation**: Existing ModelSim setup covers the audio path; inject a test tone and verify filter response.
- **Quartus**: ~5 minutes full compile. Resource and timing deltas are minimal.
- **Hardware**: Program SOF, capture audio, compare waveform FFT against baseline. A/B listening test.

## Filter Design

### Topology

Two cascaded Direct Form I biquad sections, 18-bit data path:

1. **Low-shelf** (fc ≈ 200 Hz, +6 dB gain, Q ≈ 0.7): Adds bass warmth.
2. **Peaking** (fc ≈ 200 Hz, +3 dB, Q ≈ 1.0): Piano cabinet body resonance.

Coefficients are Q2.14 fixed-point, hardwired as localparams. No runtime programmability.

### Data Flow

```
mix_sample_sat (16-bit signed)
    → sign-extend to 18-bit
    → Biquad 1 (low-shelf)
    → Biquad 2 (peaking)
    → saturate to 16-bit
    → tx_sample
```

### Saturation

The filter can apply up to ~9 dB cumulative gain. To prevent clipping, the output includes saturation logic identical to the existing mix saturation: clamp to [-32768, +32767].

## Validation Strategy

### Simulation

- ModelSim testbench: inject 440 Hz sine at `mix_sample_sat` point, measure FFT of filter output
- Verify: low-frequency gain matches coefficient design, no instability, no DC offset
- Verify: saturation clamps correctly on full-scale input

### Hardware Capture

- Before: capture existing baseline waveform (no body filter) with existing trigger smoke
- After: capture with body filter, same trigger smoke
- Compare: FFT shows +3 to +6 dB in 100-300 Hz band, unchanged fundamental pitch, no new clipping (K=0), no harmonic distortion beyond expected filter coloration
- A/B listening: programmer can flash baseline vs body-filter SOF and confirm warmer/fuller tone

### Quartus

- Full compile, verify: LEs ≤ 8,200, M9Ks = 14, DSP elements ≤ 10, timing slack ≥ +2.0 ns
- Same warning profile as baseline (14 warnings, all known)

## Risk Assessment

### Low Risks

- **Timing**: 2 biquads at 50 MHz with DSP elements have abundant slack (~20 ns per sample at ~46.9 kHz). Zero timing risk.
- **Clipping**: Saturation logic prevents overflow. K counter unchanged (=0).
- **Resource**: 200 LEs and 4 DSPs are well within headroom.
- **ROM**: No firmware changes, no ROM cost.

### Medium Risks

- **Perceptual**: The filter might not sound "right" on first try. Mitigation: coefficients are localparams, can be adjusted and recompiled. No architectural change needed if tuning is required.
- **Existing per-voice body filter interaction**: Each voice already has a 32-tap body FIR (`body_history_rtl_0`, `body_mix_q15` default 8192). The global post-mix filter is complementary (cabinet/soundboard coloration vs per-string body resonance). They operate at different scales and should not conflict, but the combined effect needs listening test.

### No-Go Criteria

Stop and revert if:
- Any Quartus timing slack drops below +2.0 ns
- LE count exceeds 8,200
- K counter reports clipping (K > 0) in smoke test
- Waveform DC offset exceeds baseline
- Audio becomes audibly distorted or unpleasant
- Any existing tag value changes in UART telemetry

## Why Not Other Phase 2 Candidates

| Candidate | Why deferred |
| --- | --- |
| Multi-string coupling | Touches per-voice state and would require new register parameters; "richer physics" border risk |
| Improved hammer dynamics | Requires per-note velocity state or new excitation ROM; "per-note state" border risk |
| Damper behavior | Requires note-off detection and per-voice damper state; "per-note state" border risk |
| Variable pitch via UART | Requires new UART command; "host-selected parameters" border risk |
| Per-voice body filter length increase | Touches per-voice M9K allocation; 3× M9K cost vs 0 M9K for global filter |

The global body filter is the only Phase 2 improvement that cleanly avoids all blocked features while providing immediate audible benefit.
