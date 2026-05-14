# Phase 3 M5 Keyboard Mapper Implementation

Date: 2026-05-14 | Agent: claude-implementer | Task: `task-394c8d95` | Commit: `d3d6a03`

## Verdict: PASS — 88 keys, zero firmware/RTL cost

`scripts/phase3_m5_keyboard.py` maps all 88 piano keys (A0/MIDI21 → C8/MIDI108) to valid `!NLLLLVVVV\r\n` commands. Self-check confirms all loop_len values in 32-127 range. Frequency-to-loop formula: `loop_len = round(46875 / freq)`.

## Usage

```
python scripts/phase3_m5_keyboard.py self-check   # validate all 88 keys
python scripts/phase3_m5_keyboard.py map           # print mapping table
python scripts/phase3_m5_keyboard.py note 69       # A4 → !N006A7FFF
python scripts/phase3_m5_keyboard.py name A4        # same
python scripts/phase3_m5_keyboard.py release        # !F
python scripts/phase3_m5_keyboard.py bare           # !N
```

## Verifier

Pipe output to FPGA serial port or capture to file for UART smoke tool validation. All commands use accepted M4 format with zero firmware/RTL changes.
