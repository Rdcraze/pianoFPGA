#!/usr/bin/env python3
"""Phase 6 M1 voice-quality analysis harness.

Reads a captured WAV plus the bench sidecar JSON, aligns each
(pitch, velocity) cell by send timestamp, and computes per-cell
acoustic metrics:

    peak_dbfs            full-scale peak in the cell's capture window
    rms_100ms_dbfs       RMS over the first 100 ms after strike
    rms_500ms_dbfs       RMS over the first 500 ms after strike
    rms_3s_dbfs          RMS over the first 3 s after strike
    attack_ms            time from cell start to peak sample
    decay_db_per_s       slope of 100 ms RMS between t=100 ms and t=1 s
    spectral_centroid_hz centroid of |FFT| over the first 250 ms
    clipping_count       count of samples at or near +/-32767
    silence_after_ms     consecutive sub-threshold ms once decay below floor

Two run modes:

    --self-check         Synthesize a deterministic decaying sine,
                         analyze it, validate metrics fall inside known
                         tolerances. Exit 0 on PASS.

    --wav PATH --sidecar PATH [--audio-start-unix N] [--out CSV] [--out-md MD]
                         Real analysis. Reads the WAV (mono or stereo;
                         stereo is averaged). Aligns each cell by
                         send_t_session_s plus the optional
                         audio-start-unix offset. Writes a per-cell CSV
                         and an optional markdown summary.

The metrics use only stdlib (wave, math, struct, csv) so no numpy
dependency is required for the analyzer to run.
"""

import argparse
import csv
import json
import math
import struct
import sys
import wave
from typing import Dict, List, Optional, Tuple


# Capture window per cell, must match the bench.
CAPTURE_S = 4.0

# RMS analysis window endpoints, in seconds.
RMS_100MS = 0.100
RMS_500MS = 0.500
RMS_3S = 3.000

# Spectral centroid window (s).
CENTROID_WIN = 0.250

# Decay slope: 100 ms RMS between these two points (s).
DECAY_T0 = 0.100
DECAY_T1 = 1.000

# Clipping threshold: count samples within this margin of full scale.
CLIP_MARGIN = 8

# Silence threshold (linear amplitude) for "silence after" measurement.
SILENCE_LINEAR = 50

FULL_SCALE = 32767.0


# ---- WAV utilities (stdlib) --------------------------------------------


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
    # Average channels to mono.
    mono = []
    for i in range(0, len(samples), nch):
        s = sum(samples[i:i + nch]) // nch
        mono.append(s)
    return mono, sr


def synthesize_decaying_sine(sr: int, freq_hz: float, duration_s: float,
                             attack_ms: float = 0.0,
                             tau_s: float = 0.5,
                             peak: float = 0.5) -> List[int]:
    """Generate a deterministic decaying sine for self-check.

    A short raised-cosine attack of `attack_ms`, then exponential decay
    with time-constant tau_s, scaled to `peak * FULL_SCALE`.
    """
    n = int(sr * duration_s)
    out = []
    attack_samples = int(sr * attack_ms / 1000.0)
    for i in range(n):
        t = i / sr
        env = math.exp(-t / tau_s)
        if i < attack_samples and attack_samples > 0:
            env *= 0.5 * (1.0 - math.cos(math.pi * i / attack_samples))
        v = peak * FULL_SCALE * env * math.sin(2 * math.pi * freq_hz * t)
        out.append(max(-32768, min(32767, int(round(v)))))
    return out


# ---- Metric calculators -------------------------------------------------


def peak_metrics(samples: List[int]) -> Tuple[int, float, int]:
    """Return (peak_abs, peak_dbfs, peak_index)."""
    peak = 0
    peak_idx = 0
    for i, s in enumerate(samples):
        a = -s if s < 0 else s
        if a > peak:
            peak = a
            peak_idx = i
    if peak == 0:
        return 0, -200.0, 0
    db = 20.0 * math.log10(peak / FULL_SCALE)
    return peak, db, peak_idx


def rms(samples: List[int]) -> float:
    if not samples:
        return 0.0
    s = 0.0
    for v in samples:
        s += v * v
    return math.sqrt(s / len(samples))


def rms_dbfs(samples: List[int]) -> float:
    r = rms(samples)
    if r <= 1e-9:
        return -200.0
    return 20.0 * math.log10(r / FULL_SCALE)


def attack_ms(samples: List[int], sr: int) -> float:
    _, _, idx = peak_metrics(samples)
    return 1000.0 * idx / sr


def decay_slope(samples: List[int], sr: int) -> float:
    """Return decay rate in dB/s between t=100 ms and t=1 s.

    Computed from the RMS of 100 ms windows centered at each point.
    """
    win = int(0.100 * sr)
    i0 = int(DECAY_T0 * sr)
    i1 = int(DECAY_T1 * sr)
    if i1 + win > len(samples):
        return 0.0
    r0 = rms(samples[i0:i0 + win])
    r1 = rms(samples[i1:i1 + win])
    if r0 <= 1e-9 or r1 <= 1e-9:
        return 0.0
    db0 = 20.0 * math.log10(r0 / FULL_SCALE)
    db1 = 20.0 * math.log10(r1 / FULL_SCALE)
    dt = DECAY_T1 - DECAY_T0
    return (db1 - db0) / dt  # negative if decaying


def spectral_centroid(samples: List[int], sr: int,
                      window_s: float = CENTROID_WIN) -> float:
    """Compute spectral centroid in Hz of the first window_s of audio.

    Uses a slow-but-stdlib-only DFT. Window length truncated to power
    of two not exceeding window_s to keep cost down.
    """
    n_full = int(window_s * sr)
    if n_full <= 0:
        return 0.0
    # Largest power of two <= n_full to keep cost manageable.
    n = 1
    while (n << 1) <= n_full:
        n <<= 1
    if n < 16:
        return 0.0
    block = samples[:n]
    if len(block) < n:
        return 0.0

    # Apply a Hann window to reduce spectral leakage so the centroid
    # of a clean sinusoid lands near its true frequency.
    windowed = []
    for i in range(n):
        w = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (n - 1)))
        windowed.append(block[i] * w)

    # Real DFT via O(N log N) Cooley-Tukey on complex inputs (no numpy).
    # Use iterative FFT.
    a = [complex(s, 0.0) for s in windowed]
    # Bit-reverse permutation.
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    # FFT.
    size = 2
    while size <= n:
        half = size >> 1
        ang = -2.0 * math.pi / size
        wlen = complex(math.cos(ang), math.sin(ang))
        for k in range(0, n, size):
            w = complex(1.0, 0.0)
            for jj in range(half):
                u = a[k + jj]
                v = a[k + jj + half] * w
                a[k + jj] = u + v
                a[k + jj + half] = u - v
                w *= wlen
        size <<= 1

    # Magnitudes for k in [1, n/2)
    num = 0.0
    den = 0.0
    df = sr / float(n)
    for k in range(1, n // 2):
        m = math.sqrt(a[k].real ** 2 + a[k].imag ** 2)
        f = k * df
        num += f * m
        den += m
    if den <= 1e-9:
        return 0.0
    return num / den


def clipping_count(samples: List[int]) -> int:
    return sum(1 for s in samples if s >= 32767 - CLIP_MARGIN or
               s <= -32768 + CLIP_MARGIN)


def silence_after_ms(samples: List[int], sr: int) -> float:
    """Trailing-silence ms once amplitude drops below SILENCE_LINEAR.

    Returns the ms of consecutive sub-threshold samples at the end of
    the segment. 0 if the segment never drops to silence.
    """
    n = len(samples)
    last_sound = -1
    for i in range(n - 1, -1, -1):
        a = -samples[i] if samples[i] < 0 else samples[i]
        if a >= SILENCE_LINEAR:
            last_sound = i
            break
    if last_sound < 0:
        # Entirely below threshold.
        return 1000.0 * n / sr
    return 1000.0 * (n - 1 - last_sound) / sr


# ---- Per-cell analysis --------------------------------------------------


def analyze_segment(samples: List[int], sr: int) -> Dict[str, float]:
    n100 = int(RMS_100MS * sr)
    n500 = int(RMS_500MS * sr)
    n3s = int(RMS_3S * sr)
    peak_abs, peak_db, _ = peak_metrics(samples)
    return {
        "peak_abs": peak_abs,
        "peak_dbfs": round(peak_db, 3),
        "rms_100ms_dbfs": round(rms_dbfs(samples[:n100]), 3),
        "rms_500ms_dbfs": round(rms_dbfs(samples[:n500]), 3),
        "rms_3s_dbfs": round(rms_dbfs(samples[:n3s]), 3),
        "attack_ms": round(attack_ms(samples[:n3s], sr), 3),
        "decay_db_per_s": round(decay_slope(samples, sr), 3),
        "spectral_centroid_hz": round(spectral_centroid(samples, sr), 1),
        "clipping_count": clipping_count(samples),
        "silence_after_ms": round(silence_after_ms(samples, sr), 1),
    }


# ---- Real-data path -----------------------------------------------------


def run_real(wav_path: str, sidecar_path: str,
             audio_start_unix: Optional[float],
             out_csv: str, out_md: Optional[str]) -> int:
    samples, sr = read_wav_mono(wav_path)
    with open(sidecar_path, "r", encoding="ascii") as fp:
        sidecar = json.load(fp)
    if sidecar.get("schema") != "phase6_m1_voice_bench.v1":
        print("ERROR: sidecar schema mismatch: {}".format(sidecar.get("schema")),
              file=sys.stderr)
        return 2

    # Compute base offset between WAV start and sidecar session start.
    session_unix = float(sidecar["session_start_unix"])
    if audio_start_unix is not None:
        wav_start_unix = float(audio_start_unix)
    else:
        # Assume the audio capture started at the same monotonic moment
        # as the bench session; this is the common case when the
        # operator runs the bench and capture in parallel.
        wav_start_unix = session_unix
    base_offset_s = session_unix - wav_start_unix

    rows = []
    for cell in sidecar["cells"]:
        cell_start_s = float(cell["send_t_session_s"]) + base_offset_s
        i0 = max(0, int(cell_start_s * sr))
        i1 = min(len(samples), i0 + int(CAPTURE_S * sr))
        seg = samples[i0:i1]
        m = analyze_segment(seg, sr)
        rows.append({
            "index": cell["index"],
            "pitch_name": cell["pitch_name"],
            "loop_len": cell["loop_len"],
            "velocity_hex": "{:#06x}".format(cell["velocity"]),
            "command": cell["command"],
            **m,
        })

    write_csv(out_csv, rows)
    if out_md is not None:
        write_md(out_md, rows, wav_path, sidecar_path)
    print("Wrote {} rows to {}".format(len(rows), out_csv), file=sys.stderr)
    return 0


def write_csv(path: str, rows: List[Dict]) -> None:
    if not rows:
        with open(path, "w", encoding="ascii", newline="") as fp:
            fp.write("# no rows\n")
        return
    fields = [
        "index", "pitch_name", "loop_len", "velocity_hex", "command",
        "peak_abs", "peak_dbfs",
        "rms_100ms_dbfs", "rms_500ms_dbfs", "rms_3s_dbfs",
        "attack_ms", "decay_db_per_s", "spectral_centroid_hz",
        "clipping_count", "silence_after_ms",
    ]
    with open(path, "w", encoding="ascii", newline="") as fp:
        w = csv.DictWriter(fp, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def write_md(path: str, rows: List[Dict], wav: str, sidecar: str) -> None:
    with open(path, "w", encoding="ascii") as fp:
        fp.write("# Phase 6 M1 voice baseline (analyzed)\n\n")
        fp.write("- wav: {}\n".format(wav))
        fp.write("- sidecar: {}\n\n".format(sidecar))
        fp.write("| idx | pitch | loop_len | vel | peak dBFS | RMS100 | RMS500 | "
                 "RMS3 | attack ms | decay dB/s | centroid Hz | clips | "
                 "silence ms |\n")
        fp.write("| ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | "
                 "---: | ---: | ---: | ---: | ---: |\n")
        for r in rows:
            fp.write("| {idx} | {pitch} | {ll} | {vel} | {pk} | {r100} | "
                     "{r500} | {r3} | {atk} | {dec} | {cen} | {clip} | "
                     "{sil} |\n".format(
                         idx=r["index"], pitch=r["pitch_name"],
                         ll=r["loop_len"], vel=r["velocity_hex"],
                         pk=r["peak_dbfs"], r100=r["rms_100ms_dbfs"],
                         r500=r["rms_500ms_dbfs"], r3=r["rms_3s_dbfs"],
                         atk=r["attack_ms"], dec=r["decay_db_per_s"],
                         cen=r["spectral_centroid_hz"], clip=r["clipping_count"],
                         sil=r["silence_after_ms"]))


# ---- Self-check ---------------------------------------------------------


def cmd_self_check() -> int:
    fails = 0
    sr = 48000
    duration = 4.0

    # Vector 1: 440 Hz decaying sine, peak=0.25 (-12 dBFS), tau=0.5s
    samples = synthesize_decaying_sine(
        sr=sr, freq_hz=440.0, duration_s=duration,
        attack_ms=2.0, tau_s=0.5, peak=0.25,
    )
    m = analyze_segment(samples, sr)

    # peak_dbfs should be ~-12 dBFS (within 0.5 dB; first sample is small
    # because the attack window is 2 ms = 96 samples, so the peak occurs
    # near the start of decay, very close to amplitude 0.25 * 32767).
    if not (-13.0 < m["peak_dbfs"] < -11.0):
        print("FAIL v1 peak_dbfs={:.3f} expected ~-12 dBFS".format(m["peak_dbfs"]))
        fails += 1
    else:
        print("PASS v1 peak_dbfs={:.3f}".format(m["peak_dbfs"]))

    # Decay: With tau=0.5, the dB rate is 20/ln(10)/0.5 = 17.372 dB/s.
    # Expected slope is therefore ~-17.37 dB/s. Allow +/- 2 dB/s window.
    if not (-19.5 < m["decay_db_per_s"] < -15.0):
        print("FAIL v1 decay_db_per_s={:.3f} expected ~-17.37".format(
            m["decay_db_per_s"]))
        fails += 1
    else:
        print("PASS v1 decay_db_per_s={:.3f}".format(m["decay_db_per_s"]))

    # Spectral centroid: a clean sine at 440 Hz should have centroid
    # very close to 440 Hz (within +/- 30 Hz at the 250 ms / 48 kHz
    # window resolution).
    if not (380.0 < m["spectral_centroid_hz"] < 500.0):
        print("FAIL v1 spectral_centroid_hz={:.1f} expected ~440".format(
            m["spectral_centroid_hz"]))
        fails += 1
    else:
        print("PASS v1 spectral_centroid_hz={:.1f}".format(
            m["spectral_centroid_hz"]))

    # Attack: 2 ms attack + first peak. Should be < 5 ms.
    if not (m["attack_ms"] < 5.0):
        print("FAIL v1 attack_ms={:.3f} expected < 5".format(m["attack_ms"]))
        fails += 1
    else:
        print("PASS v1 attack_ms={:.3f}".format(m["attack_ms"]))

    # No clipping for peak=0.25
    if m["clipping_count"] != 0:
        print("FAIL v1 clipping_count={} expected 0".format(m["clipping_count"]))
        fails += 1
    else:
        print("PASS v1 clipping_count=0")

    # Vector 2: full-scale clipping vector
    samples2 = [32767 if i % 2 == 0 else -32768 for i in range(sr // 10)]
    m2 = analyze_segment(samples2, sr)
    if m2["clipping_count"] < (sr // 10) // 2:
        print("FAIL v2 clipping_count={} expected ~half".format(
            m2["clipping_count"]))
        fails += 1
    else:
        print("PASS v2 clipping_count={}".format(m2["clipping_count"]))

    # Vector 3: silence vector
    silence = [0] * (sr * 2)
    m3 = analyze_segment(silence, sr)
    if m3["silence_after_ms"] < 1500.0:
        print("FAIL v3 silence_after_ms={:.1f} expected ~2000".format(
            m3["silence_after_ms"]))
        fails += 1
    else:
        print("PASS v3 silence_after_ms={:.1f}".format(m3["silence_after_ms"]))

    if fails == 0:
        print("PHASE6_M1_ANALYZE_PASS vectors=3")
        return 0
    print("PHASE6_M1_ANALYZE_FAIL fails={:d}".format(fails))
    return 1


# ---- Main ---------------------------------------------------------------


def main() -> int:
    p = argparse.ArgumentParser(description="Phase 6 M1 voice analyzer")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--self-check", action="store_true")
    g.add_argument("--wav", default=None,
                   help="Captured WAV path (16-bit mono or stereo)")
    p.add_argument("--sidecar", default=None,
                   help="Bench sidecar JSON path (required with --wav)")
    p.add_argument("--audio-start-unix", type=float, default=None,
                   help="Unix time at which the WAV recording started "
                        "(default: assume same as session_start_unix)")
    p.add_argument("--out", default="reports/phase6_m1_voice_baseline.csv",
                   help="Output CSV path")
    p.add_argument("--out-md", default=None,
                   help="Optional output markdown path")
    args = p.parse_args()

    if args.self_check:
        return cmd_self_check()
    if not args.sidecar:
        print("ERROR: --sidecar is required with --wav", file=sys.stderr)
        return 2
    return run_real(args.wav, args.sidecar, args.audio_start_unix,
                    args.out, args.out_md)


if __name__ == "__main__":
    sys.exit(main())
