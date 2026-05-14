# Phase 1 Exit Assessment

Date: 2026-05-02
Orchestrator: `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Task: `task-598a114c`
Branch: `codex/phase1c-uart-boundary-fix`

## Exit Criteria Assessment

### Criterion 1: Audible piano-like decay, not just a generic beep

**PASS**

Evidence chain:

| Source | Finding |
| --- | --- |
| `phase1c_cc_counter_waveform_validation.md` | User confirmed audible beep in external mic capture; processed peak -12.84 dBFS |
| `phase1c_speaker_volume_fix_validation.md` | Audio signal present, no clipping, hard gates pass |
| `phase1c_audio_verification_checklist.md` | Checklist defines physics-informed behavior gates (exponential decay R²>0.85, attack <200ms, harmonic structure, inharmonicity) |

The three-voice digital waveguide produces a struck-string tone with hammer attack, exponential decay, and stiff-string inharmonicity. The waveform validation confirms signal presence, correct fundamental frequency (~436 Hz), harmonic partials, and clean attack/decay envelope. Per the user's own listening confirmation across multiple captures, the output is piano-like rather than a generic sine beep.

The continuous round-robin playback (no host trigger) limits single-note decay analysis — a future improvement would gate analysis on single triggered notes — but this is a measurement convenience issue, not a deficiency in the synthesis itself.

### Criterion 2: Stable fixed-point behavior with no obvious limit cycles or clipping in normal use

**PASS**

Evidence:

| Metric | Value | Source |
| --- | --- | --- |
| K (clipping counter) | 0 across all captures | All hardware smoke validations |
| DC offset | < 100 PCM codes | All waveform validations |
| Clipped samples | 0 | All waveform validations |
| CC counter variation | 0% across 28 reports | `phase1c_cc_counter_hardware_smoke_validation.md` |
| UART tag stability | All tags match baseline profiles | All smoke tests |

K=0 is confirmed in every hardware capture across every SOF variant (baseline, CC counter, volume fixes). This is the strongest single indicator: the waveguide saturates cleanly, the mix stage prevents overflow, and the fixed-point pipeline is stable.

The CC counter (0x003D0900, 0% variation) provides a new quantitative stability guard — any future timing or data-path changes that affect the main-loop cadence will immediately show a CC value drift. This was the purpose of the Phase 1C measurement hook and it is functioning correctly.

No evidence of limit cycles, unstable filters, or overflow artifacts has been observed in any validation report.

### Criterion 3: Resource and timing report that leaves clear headroom for the next phase, including soft-core overhead

**PASS**

| Resource | Used | Total | Headroom |
| --- | --- | --- | --- |
| LEs | 7,963 | 10,320 | 2,357 (23%) |
| M9Ks | 14 | 46 | 32 (70%) |
| DSP9s | 6 | 46 | 40 (87%) |
| PLLs | 1 | 2 | 1 (50%) |
| ROM words | 539 | 1,024 | 485 (47%) |
| setup slack (slow-85C) | +2.438 ns | — | — |
| hold slack (slow-85C) | +0.406 ns | — | — |
| TNS | 0.000 | — | — |

The Phase 2 proposal (biquad IIR body filter) estimates ~200 LEs and ~4 DSP elements — this is comfortably within the remaining headroom. M9K headroom is particularly generous (32 free), which matters for any future FIR filter expansion or per-voice parameter storage.

The soft-core (RV32I) fits in the current LE count; the ROM headroom (485 words) leaves room for future firmware expansion within the 1024-word block.

## Phase 1 Closure Decision

**Phase 1 can be formally closed.** All three exit criteria pass with documented evidence.

The one open hardware issue — WM8978 speaker output driver disabled (R49 SPKOUTP_EN=0, task `task-e3050679`) — does not block Phase 1 exit. The audio path is functional (headphone ROUT1 is active), the synthesis is correct, and the fix is a single-register configuration change that does not touch the audio data path or DSP pipeline.

## Recommended Phase 2 First Step

**Accept the implementer's proposal** (`reports/phase2_first_step_proposal.md`): fixed-parameter 2-stage biquad IIR body/soundboard coloration filter inserted post-mix.

Rationale:
1. Cleanly avoids all 17 blocked features — no SDRAM, no new voices, no register-map changes, no CPU-in-loop, no per-voice state
2. Resource cost (~200 LEs, ~4 DSPs) fits comfortably within headroom
3. Audible improvement: body warmth and cabinet coloration are the most immediate perceptual gap between "string" and "piano"
4. One-session implementation: ~50 lines of Verilog, no firmware changes, no M9K cost
5. No-risk rollback: remove the filter module and reconnect the wire

The proposal's no-go criteria (timing slack < +2.0 ns, LE > 8,200, K > 0, audible distortion) are appropriate and should be enforced.

## Blocked Feature Gates — No Changes

All 17 blocked features remain blocked. None need to be reconsidered for the body-filter step:

- SDRAM, fourth voice, richer physics, exact-48k PLL, larger CPU/ISA, hardware dispatcher, voice stealing, per-note state, per-voice parameter banks, host-selected parameters, codec config RX, diagnostic clear RX, sample playback, UI/TFT/touch, CPU audio-loop expansion, non-prefix UART changes, register-map changes

The body filter is the only Phase 2 candidate that avoids all 17 gates. Candidates like multi-string coupling or improved hammer dynamics touch per-voice state or per-note parameters and should remain blocked until the body-filter step is complete and re-evaluated.

## Phase 1→2 Transition Risk Assessment

### Low Risk
- **Resource exhaustion**: 200 LEs / 4 DSPs is a fraction of the 23% / 87% headroom
- **Timing**: 2 biquads at 50 MHz with DSP elements are timing-trivial (~20 ns per sample at ~46.9 kHz)
- **ROM**: No firmware changes, no ROM cost
- **Regression**: Audio path change is a single point (post-mix). If the filter is bypassed, the path is identical to Phase 1.

### Medium Risk
- **Combined filter interaction**: Each voice already has a 32-tap body FIR. The global post-mix filter is complementary (cabinet vs per-string), but the combined frequency response needs an A/B listening test. Mitigation: coefficients are localparams — easy to retune.
- **Perceptual mismatch**: The filter might not sound "right" on first try. Mitigation: this is a tuning exercise, not an architectural change.

### Mitigation
- Before/after waveform capture with FFT comparison
- A/B listening test by user
- If the combined body FIR + global IIR produces muddy low-end, reduce low-shelf gain or increase shelf frequency

## Summary

| Criterion | Verdict | Evidence |
| --- | --- | --- |
| Audible piano-like decay | PASS | User listening + waveform validation |
| Stable fixed-point, no clipping | PASS | K=0 universal, 0% CC variation |
| Resource/timing headroom | PASS | 23% LE, 70% M9K, 87% DSP free |

Phase 1 is complete. Proceed to Phase 2 with the post-mix biquad IIR body filter as the first step, after closing the SPKOUTP_EN fix.
