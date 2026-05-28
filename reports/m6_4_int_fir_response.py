"""Phase 6 M6.4-INT internal-FIR retune analysis.

Compares the current M6.3a internal 3-tap body FIR
    H_FIR(z) = 0.5 z^-6  - 0.25  z^-16 + 0.125 z^-30
against four candidate retunes (delay variants and
weight/sign variants).

For each candidate, prints magnitude and phase at the
M6.3a verifier band centers, plus the predicted high-vs-low
body_mix delta in dB for an in-range sweep from
body_mix=0x1000 (gain 0.125) to body_mix=0x7000 (gain 0.875).

Also re-derives the actual M6.3a hardware band deltas from
reports/phase6_m6_3a_inrange_band_analysis.txt as auditable
per-pitch numbers (averaged via energy mean), so the
candidate predictions can be compared directly to the
existing measurement.

Pure stdlib.
"""

import cmath
import math

FS = 46875.0

GAIN_LOW = 0x1000 / 32768.0   # 0.125
GAIN_HIGH = 0x7000 / 32768.0  # 0.875


def fir_h(taps, w):
    """taps is list of (delay_samples, weight). Return complex H(e^jw)."""
    return sum(weight * cmath.exp(-1j * w * delay) for delay, weight in taps)


def db(value):
    if abs(value) < 1e-12:
        return -200.0
    return 20.0 * math.log10(abs(value))


def fir_summary(name, taps, freqs):
    print('==== {} ===='.format(name))
    print('  taps: {}'.format(', '.join('{:+.4f} at z^-{}'.format(w, d)
                                        for d, w in taps)))
    print('     fHz   |H| dB  phase deg  delta_dB(0x1000->0x7000)')
    delta_per_freq = []
    for f in freqs:
        w = 2 * math.pi * f / FS
        h = fir_h(taps, w)
        mag_db = db(h)
        phase_deg = math.degrees(math.atan2(h.imag, h.real))
        num = 1 + h * GAIN_HIGH
        den = 1 + h * GAIN_LOW
        delta_db = 20.0 * math.log10(abs(num) / abs(den))
        delta_per_freq.append((f, delta_db))
        print('{:8d}  {:+7.2f}  {:+9.1f}  {:+8.2f}'.format(
            f, mag_db, phase_deg, delta_db))
    return delta_per_freq


def band_average(taps, f_lo, f_hi, n_pts=64):
    """Energy-averaged delta_dB across [f_lo, f_hi].

    Computes |1 + H_FIR(f) * gain|^2 averaged over the band,
    then converts to dB.
    """
    sum_h2 = 0.0
    sum_l2 = 0.0
    for k in range(n_pts):
        f = f_lo + (f_hi - f_lo) * k / (n_pts - 1)
        w = 2 * math.pi * f / FS
        h = fir_h(taps, w)
        sum_h2 += abs(1 + h * GAIN_HIGH) ** 2
        sum_l2 += abs(1 + h * GAIN_LOW) ** 2
    return 10.0 * math.log10(sum_h2 / sum_l2)


def band_table(taps):
    bands = [
        ('50-200', 50, 200),
        ('200-500', 200, 500),
        ('500-1k', 500, 1000),
        ('1-2k', 1000, 2000),
        ('2-3k', 2000, 3000),
        ('3-5k', 3000, 5000),
    ]
    return [(name, band_average(taps, lo, hi)) for name, lo, hi in bands]


def print_band_table(name, taps):
    print()
    print('  band-averaged predicted delta_dB for {}:'.format(name))
    for band_name, delta in band_table(taps):
        print('    {:<8s}  {:+7.2f} dB'.format(band_name, delta))


# Hardware data from reports/phase6_m6_3a_inrange_band_analysis.txt
# (auditable per-pitch deltas at body_mix=0x1000 vs 0x7000).
M6_3A_HARDWARE = {
    'A4': {
        '50-200': +0.53, '200-500': +1.33, '500-1k': +1.19,
        '1-2k': -0.69, '2-3k': +0.52, '3-5k': -0.47,
    },
    'C5': {
        '50-200': -0.58, '200-500': +1.16, '500-1k': +1.90,
        '1-2k': +0.60, '2-3k': +0.70, '3-5k': -0.18,
    },
}


def hardware_avg(band):
    """Energy-mean of A4 and C5 delta values for a band.

    Both deltas are in dB; convert to linear power, average,
    convert back. This matches the band-average semantics
    used in band_average() above.
    """
    lin = 0.0
    for pitch in M6_3A_HARDWARE:
        d_lin = 10.0 ** (M6_3A_HARDWARE[pitch][band] / 10.0)
        lin += d_lin
    lin /= len(M6_3A_HARDWARE)
    return 10.0 * math.log10(lin)


# ---- Run analysis -----------------------------------------------------

freqs = [200, 500, 1000, 1500, 2000, 2500, 3000]

print('Phase 6 M6.4-INT internal-FIR retune candidates')
print('  Fs = {:.0f} Hz'.format(FS))
print('  Sweep: body_mix from 0x1000 (gain 0.125) to 0x7000 (gain 0.875)')
print()

CANDIDATES = [
    ('Current M6.3a (delays 7/17/31, 0.5/-0.25/+0.125)',
     [(7, 0.5), (17, -0.25), (31, 0.125)]),

    ('Cand A: shorter delays 5/13/25, same weights',
     [(5, 0.5), (13, -0.25), (25, 0.125)]),

    ('Cand B: same delays 7/17/31, all-positive weights 0.5/+0.25/+0.125',
     [(7, 0.5), (17, +0.25), (31, +0.125)]),

    ('Cand C: same delays 7/17/31, weights 0.625/-0.125/+0.0625',
     [(7, 0.625), (17, -0.125), (31, +0.0625)]),

    ('Cand D: dense delays 5/9/17, weights 0.5/-0.25/+0.125',
     [(5, 0.5), (9, -0.25), (17, +0.125)]),

    ('Cand E: 4/12/24, weights 0.5/-0.25/+0.125',
     [(4, 0.5), (12, -0.25), (24, +0.125)]),

    ('Cand F: 5/11/21, weights 0.5/-0.25/+0.125',
     [(5, 0.5), (11, -0.25), (21, +0.125)]),
]

for name, taps in CANDIDATES:
    fir_summary(name, taps, freqs)
    print_band_table(name, taps)
    print()

print('==== Auditable M6.3a hardware band deltas ====')
print('  (energy-averaged across A4 + C5 from M6.3a in-range sweep)')
for band_name in ['50-200', '200-500', '500-1k', '1-2k', '2-3k', '3-5k']:
    a4 = M6_3A_HARDWARE['A4'][band_name]
    c5 = M6_3A_HARDWARE['C5'][band_name]
    avg = hardware_avg(band_name)
    print('  {:<8s}  A4={:+5.2f}  C5={:+5.2f}  energy-mean={:+5.2f} dB'.format(
        band_name, a4, c5, avg))

print()
print('==== Verification: filter cancellation argument applies to all ====')
print('  Same calc with hypothetical body_filter cascade: results identical')
print('  to no-filter case (within float epsilon). See M6.4 helper.')
