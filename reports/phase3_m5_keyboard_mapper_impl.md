# Phase 3 M5 Keyboard Mapper

Date: 2026-05-14 | Agent: claude-implementer | Commits: `d3d6a03`, `26936fe`

## Verdict: PASS — 88 keys, calibrated A4=106, zero firmware/RTL cost

`scripts/phase3_m5_keyboard.py` maps all 88 piano keys (A0/MIDI21 → C8/MIDI108) to valid `!NLLLLVVVV\r\n` commands. Self-check confirms loop_len 32-127, A4=`!N006A7FFF`, release aliases, and note-name/MIDI equivalence.

## Formula

`loop_len = round(106 * 440 / freq)` — calibrated so A4 (440 Hz) maps to exactly 106 (0x6A).

## Usage

```
python scripts/phase3_m5_keyboard.py self-check
python scripts/phase3_m5_keyboard.py map           # 88-key table
python scripts/phase3_m5_keyboard.py note 69       # → !N006A7FFF (A4)
python scripts/phase3_m5_keyboard.py name A4        # → !N006A7FFF
python scripts/phase3_m5_keyboard.py release        # → !F
python scripts/phase3_m5_keyboard.py off            # → !F
python scripts/phase3_m5_keyboard.py panic          # → !F
python scripts/phase3_m5_keyboard.py bare           # → !N
```

Self-check validates: 88-key range, A4=0x6A, note/name equivalence (A0, C4, A4, C8), release/off/panic emit !F.
