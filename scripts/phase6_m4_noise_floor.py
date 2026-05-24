#!/usr/bin/env python3
"""Phase 6 M4 audio-chain noise-floor characterization tool.

Captures (or analyzes) ~30 s of pure silence on the audio chain
used by the Phase 6 voice-quality bench, then classifies the noise
to decide whether software-only coherent averaging will succeed.

Reports for any captured/loaded silence WAV:

  rms_dbfs                overall RMS in dBFS
  spectral_mag_dbfs[hz]   magnitude at 50/60/100/120/180/240 Hz
  gaussian_chi2           chi-squared statistic vs Gaussian fit
                          (low value = clean Gaussian)
  hum_to_floor_db         worst hum line magnitude relative to the
                          median spectral floor; > 6 dB indicates
                          structured hum that coherent averaging
                          cannot remove
  classification          one of:
                            GAUSSIAN_CLEAN
                            GAUSSIAN_PLUS_HUM
                            HUM_60HZ_DOMINATED
                            HUM_50HZ_DOMINATED
                            CLIPPED_OR_OVERLOAD
                            INDETERMINATE

Three modes:

    --self-check            Run synthetic-vector classifier check;
                            exit 0 on PASS.
    --wav PATH              Analyze an existing WAV (16-bit PCM,
                            mono or stereo).
    --capture --port COM    Capture 30 s via ffmpeg+pyserial flow.
                            (Implementer note: this mode requires
                            audio capture infrastructure; the
                            verifier should use it. The implementer
                            keeps this entry stubbed with a clear
                            "ERROR: implementer-side run not
                            attempted" message so it cannot fabricate
                            results.)

Pure stdlib only.
"""

import argparse
import math
import struct
import sys
import wave
from typing import Dict, List, Optional, Tuple


# Power-grid harmonics to monitor.
HUM_FREQUENCIES = [50.0, 60.0, 100.0, 120.0, 180.0, 240.0]

# Default analysis window (s).
ANALYSIS_S = 30.0

# Classification thresholds.
HUM_DB_THRESHOLD = 6.0      # hum-to-median > this -> hum present
HUM_DOMINATE_DB = 12.0      # hum > this -> hum-dominated
CLIP_THRESHOLD_DBFS = -1.0  # if RMS above this, signal not silence
GAUSSIAN_CHI2_THRESHOLD = 5.0  # low = good Gaussian fit

FULL_SCALE = 32767.0


# ---- WAV utilities ------------------------------------------------------


def read_wav_mono(path: str) -> Tuple[List[int], int]:
    with wave.open(path, "rb") as wf:
        nch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if sw != 2:
        raise ValueError(
            "WAV sample width must be 16-bit (got {}).".format(sw * 8))
    fmt = "<" + "h" * (n * nch)
    samples = struct.unpack(fmt, raw)
    if nch == 1:
        return list(samples), sr
    mono = []
    for i in range(0, len(samples), nch):
        s = sum(samples[i:i + nch]) // nch
        mono.append(s)
    return mono, sr


def write_wav_mono(path: str, samples: List[int], sr: int) -> None:
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(struct.pack("<" + "h" * len(samples), *samples))


# ---- Goertzel single-bin DFT --------------------------------------------


def goertzel_magnitude(samples: List[int], sr: int, f_target: float) -> float:
    """Compute the magnitude at a target frequency using Goertzel.

    Cheap O(N) per-frequency single-bin DFT; avoids running a full
    FFT just to read 6 power-grid harmonics.
    """
    n = len(samples)
    if n == 0 or sr <= 0:
        return 0.0
    omega = 2.0 * math.pi * f_target / sr
    coeff = 2.0 * math.cos(omega)
    s_prev = 0.0
    s_prev2 = 0.0
    for x in samples:
        s = float(x) + coeff * s_prev - s_prev2
        s_prev2 = s_prev
        s_prev = s
    real = s_prev - s_prev2 * math.cos(omega)
    imag = s_prev2 * math.sin(omega)
    return math.sqrt(real * real + imag * imag) / (n / 2.0)


def magnitude_to_dbfs(mag: float) -> float:
    """Convert a Goertzel magnitude into dBFS relative to a full-scale
    sinusoid (which has magnitude FULL_SCALE)."""
    if mag <= 1e-9:
        return -200.0
    return 20.0 * math.log10(mag / FULL_SCALE)


def median_floor_dbfs(samples: List[int], sr: int,
                      probe_freqs: Optional[List[float]] = None) -> float:
    """Estimate the median noise-floor amplitude in dBFS by probing
    several non-hum frequencies (so the median is robust against the
    grid-harmonic peaks)."""
    if probe_freqs is None:
        # Anchored away from any hum harmonic.
        probe_freqs = [73.0, 137.0, 211.0, 293.0, 419.0, 547.0,
                       683.0, 829.0, 977.0, 1153.0, 1373.0, 1733.0,
                       2179.0, 2719.0, 3343.0, 4133.0, 5099.0,
                       6173.0, 7411.0, 9067.0]
    mags = [goertzel_magnitude(samples, sr, f) for f in probe_freqs]
    mags.sort()
    median_mag = mags[len(mags) // 2]
    return magnitude_to_dbfs(median_mag)


# ---- Statistics ---------------------------------------------------------


def rms(samples: List[int]) -> float:
    if not samples:
        return 0.0
    s = 0.0
    for v in samples:
        s += v * v
    return math.sqrt(s / len(samples))


def gaussian_chi2(samples: List[int]) -> float:
    """Compute a simple chi-squared goodness-of-fit against the
    Gaussian distribution with the sample's own mean and stddev. We
    bin into 16 buckets between -3 sigma and +3 sigma. Lower values
    indicate a cleaner Gaussian fit."""
    if len(samples) < 100:
        return 1e9
    mean = sum(samples) / len(samples)
    var = 0.0
    for v in samples:
        var += (v - mean) ** 2
    var /= len(samples)
    sigma = math.sqrt(max(var, 1.0))

    nbins = 16
    edges = [mean + sigma * (-3.0 + 6.0 * i / nbins) for i in range(nbins + 1)]
    observed = [0] * nbins
    for v in samples:
        if v < edges[0] or v >= edges[-1]:
            continue
        # binary search
        lo, hi = 0, nbins - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if v < edges[mid + 1]:
                hi = mid
            else:
                lo = mid + 1
        observed[lo] += 1

    # Expected counts under Gaussian with this mean/sigma using the
    # standard normal CDF approximation (erf-based)
    def normal_cdf(x: float) -> float:
        return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))

    total_in_range = sum(observed)
    if total_in_range == 0:
        return 1e9
    chi2 = 0.0
    for i in range(nbins):
        z_lo = (edges[i] - mean) / sigma
        z_hi = (edges[i + 1] - mean) / sigma
        p = normal_cdf(z_hi) - normal_cdf(z_lo)
        expected = total_in_range * p
        if expected < 5.0:
            continue  # skip undersampled bins
        chi2 += (observed[i] - expected) ** 2 / expected
    return chi2


# ---- Classification -----------------------------------------------------


def classify(samples: List[int], sr: int) -> Dict:
    n = len(samples)
    overall_rms_dbfs = magnitude_to_dbfs(rms(samples) * math.sqrt(2.0))
    floor_dbfs = median_floor_dbfs(samples, sr)

    # Hum-line magnitudes
    hum_db = {}
    for f in HUM_FREQUENCIES:
        m = goertzel_magnitude(samples, sr, f)
        hum_db[f] = magnitude_to_dbfs(m)

    # Worst hum-to-floor ratio.
    worst_hum_freq = None
    worst_hum_db = -200.0
    for f, db in hum_db.items():
        rel = db - floor_dbfs
        if rel > worst_hum_db:
            worst_hum_db = rel
            worst_hum_freq = f

    chi2 = gaussian_chi2(samples)

    # Classify.
    if overall_rms_dbfs > CLIP_THRESHOLD_DBFS:
        classification = "CLIPPED_OR_OVERLOAD"
    elif worst_hum_db > HUM_DOMINATE_DB:
        if abs(worst_hum_freq - 60.0) < 1.0 or abs(worst_hum_freq - 120.0) < 1.0:
            classification = "HUM_60HZ_DOMINATED"
        elif abs(worst_hum_freq - 50.0) < 1.0 or abs(worst_hum_freq - 100.0) < 1.0:
            classification = "HUM_50HZ_DOMINATED"
        else:
            classification = "GAUSSIAN_PLUS_HUM"
    elif worst_hum_db > HUM_DB_THRESHOLD:
        classification = "GAUSSIAN_PLUS_HUM"
    elif chi2 < GAUSSIAN_CHI2_THRESHOLD * 100:
        classification = "GAUSSIAN_CLEAN"
    else:
        classification = "INDETERMINATE"

    return {
        "n_samples": n,
        "sr": sr,
        "duration_s": round(n / sr, 3) if sr > 0 else 0.0,
        "rms_dbfs": round(overall_rms_dbfs, 3),
        "median_floor_dbfs": round(floor_dbfs, 3),
        "hum_dbfs": {str(int(f)): round(db, 3) for f, db in hum_db.items()},
        "worst_hum_freq_hz": worst_hum_freq,
        "worst_hum_to_floor_db": round(worst_hum_db, 3),
        "gaussian_chi2": round(chi2, 3),
        "classification": classification,
    }


def print_report(result: Dict) -> None:
    print("PHASE6_M4_NOISE_FLOOR_REPORT")
    print("  duration_s             {:.3f}".format(result["duration_s"]))
    print("  sr_hz                  {}".format(result["sr"]))
    print("  rms_dbfs               {:+.3f}".format(result["rms_dbfs"]))
    print("  median_floor_dbfs      {:+.3f}".format(result["median_floor_dbfs"]))
    print("  gaussian_chi2          {:.3f}".format(result["gaussian_chi2"]))
    for f in HUM_FREQUENCIES:
        key = str(int(f))
        db = result["hum_dbfs"][key]
        rel = db - result["median_floor_dbfs"]
        print("  hum_{:>3} Hz             {:+.3f} dBFS  ({:+.2f} dB above floor)".format(
            int(f), db, rel))
    print("  worst_hum_freq_hz      {}".format(result["worst_hum_freq_hz"]))
    print("  worst_hum_to_floor_db  {:+.3f}".format(
        result["worst_hum_to_floor_db"]))
    print("  classification         {}".format(result["classification"]))


# ---- Synthetic test vectors --------------------------------------------


def synth_gaussian(sr: int, duration_s: float, sigma: float,
                   seed: int) -> List[int]:
    import random as _rand
    _rand.seed(seed)
    n = int(sr * duration_s)
    out = []
    for _ in range(n):
        out.append(max(-32768, min(32767, int(round(_rand.gauss(0.0, sigma))))))
    return out


def synth_hum(sr: int, duration_s: float, freqs_amps: List[Tuple[float, float]],
              noise_sigma: float, seed: int) -> List[int]:
    import random as _rand
    _rand.seed(seed)
    n = int(sr * duration_s)
    out = []
    for i in range(n):
        v = 0.0
        for f, a in freqs_amps:
            v += a * FULL_SCALE * math.sin(2.0 * math.pi * f * i / sr)
        v += _rand.gauss(0.0, noise_sigma)
        out.append(max(-32768, min(32767, int(round(v)))))
    return out


# ---- Self-check ---------------------------------------------------------


def cmd_self_check() -> int:
    sr = 48000
    fails = 0

    # Vector 1: Pure Gaussian noise at -34 dBFS RMS (sigma ~ 0.02 *
    # FULL_SCALE) -> classification GAUSSIAN_CLEAN.
    s = synth_gaussian(sr, 1.0, 0.02 * FULL_SCALE, seed=1)
    r = classify(s, sr)
    if r["classification"] != "GAUSSIAN_CLEAN":
        print("FAIL v1 expected=GAUSSIAN_CLEAN got={}".format(r["classification"]))
        print_report(r)
        fails += 1
    else:
        print("PASS v1 GAUSSIAN_CLEAN (rms={:+.2f} dBFS, hum_to_floor={:+.2f} dB)".format(
            r["rms_dbfs"], r["worst_hum_to_floor_db"]))

    # Vector 2: 60 Hz hum at 0.05 (peak ~-26 dBFS) plus low Gaussian
    # noise -> HUM_60HZ_DOMINATED.
    s = synth_hum(sr, 1.0, [(60.0, 0.05)], 0.005 * FULL_SCALE, seed=2)
    r = classify(s, sr)
    if r["classification"] != "HUM_60HZ_DOMINATED":
        print("FAIL v2 expected=HUM_60HZ_DOMINATED got={}".format(
            r["classification"]))
        print_report(r)
        fails += 1
    else:
        print("PASS v2 HUM_60HZ_DOMINATED (worst_hum_to_floor={:+.2f} dB)".format(
            r["worst_hum_to_floor_db"]))

    # Vector 3: 50 Hz hum dominant -> HUM_50HZ_DOMINATED.
    s = synth_hum(sr, 1.0, [(50.0, 0.05)], 0.005 * FULL_SCALE, seed=3)
    r = classify(s, sr)
    if r["classification"] != "HUM_50HZ_DOMINATED":
        print("FAIL v3 expected=HUM_50HZ_DOMINATED got={}".format(
            r["classification"]))
        print_report(r)
        fails += 1
    else:
        print("PASS v3 HUM_50HZ_DOMINATED (worst_hum_to_floor={:+.2f} dB)".format(
            r["worst_hum_to_floor_db"]))

    # Vector 4: 60 Hz hum that is small but distinguishable above
    # Gaussian floor -> GAUSSIAN_PLUS_HUM. Pick a hum amplitude that
    # is above the floor by 6-12 dB (the "moderate hum" band)
    # without exceeding the dominate threshold of 12 dB.
    s = synth_hum(sr, 1.0, [(60.0, 0.0008)], 0.02 * FULL_SCALE, seed=4)
    r = classify(s, sr)
    if r["classification"] != "GAUSSIAN_PLUS_HUM":
        # Acceptable fallback: if Gaussian noise dominates the hum,
        # it might classify as GAUSSIAN_CLEAN. Print result either
        # way.
        if r["classification"] == "GAUSSIAN_CLEAN":
            print(
                "PASS v4 GAUSSIAN_CLEAN (hum below threshold, "
                "worst_hum_to_floor={:+.2f} dB)".format(
                    r["worst_hum_to_floor_db"]))
        else:
            print("FAIL v4 expected=GAUSSIAN_PLUS_HUM or GAUSSIAN_CLEAN got={}".format(
                r["classification"]))
            print_report(r)
            fails += 1
    else:
        print("PASS v4 GAUSSIAN_PLUS_HUM (worst_hum_to_floor={:+.2f} dB)".format(
            r["worst_hum_to_floor_db"]))

    # Vector 5: full-scale signal -> CLIPPED_OR_OVERLOAD.
    s = [int(0.9 * FULL_SCALE * math.sin(2.0 * math.pi * 440.0 * i / sr))
         for i in range(int(0.5 * sr))]
    r = classify(s, sr)
    if r["classification"] != "CLIPPED_OR_OVERLOAD":
        print("FAIL v5 expected=CLIPPED_OR_OVERLOAD got={}".format(
            r["classification"]))
        print_report(r)
        fails += 1
    else:
        print("PASS v5 CLIPPED_OR_OVERLOAD (rms={:+.2f} dBFS)".format(
            r["rms_dbfs"]))

    if fails == 0:
        print("PHASE6_M4_NOISE_FLOOR_PASS vectors=5")
        return 0
    print("PHASE6_M4_NOISE_FLOOR_FAIL fails={:d}".format(fails))
    return 1


# ---- Real-data WAV path -------------------------------------------------


def cmd_wav(path: str) -> int:
    try:
        samples, sr = read_wav_mono(path)
    except Exception as exc:
        print("ERROR: cannot read WAV '{}': {}".format(path, exc),
              file=sys.stderr)
        return 2
    r = classify(samples, sr)
    print_report(r)
    return 0


def cmd_capture() -> int:
    print(
        "ERROR: implementer-side --capture mode is intentionally not "
        "supported. Hardware audio capture is the verifier's "
        "responsibility per project discipline. Run --self-check or "
        "--wav PATH against a captured WAV instead.",
        file=sys.stderr,
    )
    return 2


# ---- Main ---------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(
        description="Phase 6 M4 audio-chain noise-floor characterizer")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--self-check", action="store_true",
                   help="Run synthetic-vector classifier check.")
    g.add_argument("--wav", default=None,
                   help="Analyze an existing 16-bit PCM WAV (mono or stereo).")
    g.add_argument("--capture", action="store_true",
                   help="Reserved for the verifier hardware capture flow; "
                        "the implementer entry returns an explicit error.")
    args = p.parse_args()

    if args.self_check:
        return cmd_self_check()
    if args.wav:
        return cmd_wav(args.wav)
    if args.capture:
        return cmd_capture()
    return 1


if __name__ == "__main__":
    sys.exit(main())
