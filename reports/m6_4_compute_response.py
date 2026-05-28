"""Phase 6 M6.4 body-path frequency response analysis.

Computes:
1. The external phase0_body_filter cascade response (post-mix biquad pipeline).
2. The internal phase1_reduced_voice 3-tap body FIR response.
3. The relative dB delta in output spectrum between body_mix=0x7000 (gain
   0.875) and body_mix=0x1000 (gain 0.125), which is the M6.3a verifier's
   acceptance metric.

The purpose is to support the M6.4 scope decision: does retuning the
external body filter actually change the body_mix-driven dB delta at any
frequency, or does the body filter response cancel out?

Pure stdlib.
"""

import cmath
import math

FS = 46875.0

# Live phase0_body_filter Q2.14 coefficients at HEAD (M6.3a).
B1 = {'B0': 16493 / 16384, 'B1': -32236 / 16384, 'B2': 15759 / 16384,
      'A1': 32240 / 16384, 'A2': -15864 / 16384}
B2 = {'B0': 16742 / 16384, 'B1': -30410 / 16384, 'B2': 14289 / 16384,
      'A1': 30410 / 16384, 'A2': -14645 / 16384}

# M6.3a internal 3-tap body FIR (post-doubling): 1/2 at delay 6,
# -1/4 at delay 16, +1/8 at delay 30 samples.
FIR_TAPS = [(6, 0.5), (16, -0.25), (30, 0.125)]

# M6.3a sweep gains.
GAIN_LOW = 0x1000 / 32768.0   # 0.125
GAIN_HIGH = 0x7000 / 32768.0  # 0.875


def biquad_h(coeffs, w):
    z = cmath.exp(-1j * w)
    n = coeffs['B0'] + coeffs['B1'] * z + coeffs['B2'] * z * z
    d = 1 - coeffs['A1'] * z - coeffs['A2'] * z * z
    return n / d


def fir_h(taps, w):
    return sum(weight * cmath.exp(-1j * w * delay) for delay, weight in taps)


def db(value):
    if abs(value) < 1e-12:
        return -200.0
    return 20.0 * math.log10(abs(value))


freqs = [50, 100, 200, 300, 500, 700, 1000, 1200, 1500, 1800,
         2000, 2500, 3000, 4000, 6000, 8000]

print('==== Live phase0_body_filter cascade (post-mix) ====')
print('  Biquad 1: low-shelf, +6 dB at DC, fc ~200 Hz')
print('  Biquad 2: peaking, +3 dB at 1500 Hz, Q=1.5')
print('     fHz     B1dB     B2dB    sumdB')
for f in freqs:
    w = 2 * math.pi * f / FS
    h1 = biquad_h(B1, w)
    h2 = biquad_h(B2, w)
    print('{:8d}  {:+7.2f}  {:+7.2f}  {:+7.2f}'.format(f, db(h1), db(h2), db(h1 * h2)))

print()
print('==== Internal phase1_reduced_voice 3-tap body FIR (post-M6.3a doubling) ====')
print('  Taps: 0.5 at delay 6, -0.25 at delay 16, +0.125 at delay 30')
print('  Fed by disp_sample once per audio sample at Fs={:.0f} Hz'.format(FS))
print('     fHz    H_FIR_dB  H_FIR_phase_deg')
for f in freqs:
    w = 2 * math.pi * f / FS
    h = fir_h(FIR_TAPS, w)
    phase_deg = math.degrees(math.atan2(h.imag, h.real))
    print('{:8d}  {:+7.2f}  {:+12.1f}'.format(f, db(h), phase_deg))

print()
print('==== Relative output-spectrum delta between body_mix=0x7000 vs 0x1000 ====')
print('  output(f, body_mix) = H_filter(f) * disp(f) * (1 + H_FIR(f) * gain)')
print('  delta_dB(f) = 20*log10(|1 + H_FIR(f)*gain_high| / |1 + H_FIR(f)*gain_low|)')
print('  KEY: H_filter(f) cancels out. Body filter coefficients do NOT')
print('       change this delta. Only the internal 3-tap FIR does.')
print('     fHz   delta_dB(f)')
for f in freqs:
    w = 2 * math.pi * f / FS
    h_fir = fir_h(FIR_TAPS, w)
    num = 1 + h_fir * GAIN_HIGH
    den = 1 + h_fir * GAIN_LOW
    delta_db = 20.0 * math.log10(abs(num) / abs(den))
    print('{:8d}  {:+7.2f}'.format(f, delta_db))

print()
print('==== Same delta for body filter REMOVED (sanity check, must match) ====')
print('     fHz   delta_dB(f)')
for f in freqs:
    w = 2 * math.pi * f / FS
    h_fir = fir_h(FIR_TAPS, w)
    h_filter = biquad_h(B1, w) * biquad_h(B2, w)
    num = h_filter * (1 + h_fir * GAIN_HIGH)
    den = h_filter * (1 + h_fir * GAIN_LOW)
    delta_db = 20.0 * math.log10(abs(num) / abs(den))
    print('{:8d}  {:+7.2f}'.format(f, delta_db))

print()
print('==== Band-averaged delta_dB (uniform weighting across band) ====')
bands = [
    ('50-200', 50, 200),
    ('200-500', 200, 500),
    ('500-1k', 500, 1000),
    ('1-2k', 1000, 2000),
    ('2-3k', 2000, 3000),
    ('3-5k', 3000, 5000),
    ('5-7k', 5000, 7000),
    ('7-10k', 7000, 10000),
]
for name, f_lo, f_hi in bands:
    samples = []
    n_pts = 64
    for k in range(n_pts):
        f = f_lo + (f_hi - f_lo) * k / (n_pts - 1)
        w = 2 * math.pi * f / FS
        h_fir = fir_h(FIR_TAPS, w)
        num = abs(1 + h_fir * GAIN_HIGH) ** 2
        den = abs(1 + h_fir * GAIN_LOW) ** 2
        samples.append((num, den))
    avg_num = sum(s[0] for s in samples) / n_pts
    avg_den = sum(s[1] for s in samples) / n_pts
    delta_db = 10.0 * math.log10(avg_num / avg_den)
    print('  {:<8s}  {:+7.2f} dB'.format(name, delta_db))
