# Phase 0 Sample-Rate Fix Validation

Date: `2026-04-23`

## Findings

### [P2] The sample-rate/pitch mismatch improved on hardware, but it is not fully fixed

I validated the updated bitstream on the live board using a fresh analog capture from the external Realtek audio-input endpoint, not the built-in microphone:

- capture device used: external Realtek audio-input endpoint
- built-in Realtek microphone remained separately enumerated and was not used
- fresh capture artifact: [phase0_sample_rate_fix_capture.wav](</E:/projects/piano-agents/reports/phase0_sample_rate_fix_capture.wav>)

The new capture shows a stable dominant tone around `538.75 Hz`.

That is materially better than the earlier pre-fix hardware result of about `561.25 Hz`, but it is still well above the intended nominal tone. Under the new interim clock contract:

- `phase_step = 157482`
- intended sample rate = `46.875 kHz`
- expected default tone = `157482 * 46875 / 2^24 = 439.9996 Hz`

Observed result:

- dominant tone: `~538.75 Hz`
- ratio vs target: `538.75 / 440 ~= 1.224`
- implied effective playback rate if `phase_step` is correct: `~57.4 kHz`

So the fix reduced the error, but the live board is still running materially fast from the audio-rate point of view.

### [Info] Control/debug baseline for this updated image was already healthy

This same updated image had already shown a good control/debug baseline on hardware in the immediately preceding validation pass for the same `.sof` checksum family:

- `I=50303031`
- `S=8019030A`
- recurring `R=8019035A`

In this audio-capture pass, the CH340 UART path was not simultaneously available, but JTAG programming of the same updated bitstream still succeeded cleanly, so there is no new evidence of a control-plane regression.

## Exact Actions And Results

1. Confirmed the updated packaged image:
   - `E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof`
2. Programmed the board over JTAG:
   - cable: `USB-Blaster [USB-0]`
   - command:
     `D:\quartus\quartus\bin64\quartus_pgm.exe -c "USB-Blaster [USB-0]" -m JTAG -o "P;E:\projects\piano-agents\quartus\phase0\output_files\piano_phase0_top.sof@1"`
   - result:
     - checksum `0x00103BA5`
     - `Configuration succeeded -- 1 device(s) configured`
3. Identified a valid external audio-input endpoint on the PC:
   - external Realtek audio-input endpoint
4. Recorded a fresh `8 s` analog capture from that external endpoint while reprogramming the board:
   - output file:
     [phase0_sample_rate_fix_capture.wav](</E:/projects/piano-agents/reports/phase0_sample_rate_fix_capture.wav>)
5. Analyzed the new capture locally.

## Capture Analysis

File characteristics:

- WAV / PCM `16-bit`
- `48 kHz`
- stereo
- duration `7.988 s`

Measured signal characteristics:

- dominant spectral peak: `~538.75 Hz`
- strong harmonics near `~1077.5 Hz`, `~1616.5 Hz`, `~2155.25 Hz`
- channel RMS:
  - left: `0.0438`
  - right: `0.0452`
- stereo correlation: `~0.946`
- no obvious silence or one-shot-only behavior

Comparison against the previous pre-fix hardware capture:

- old dominant tone: `~561.25 Hz`
- new dominant tone: `~538.75 Hz`
- improvement in the frequency error magnitude: about `18.6%`

## Interpretation

The updated hardware image clearly changed the live audio rate in the right direction, so the implementer's clock/sample-rate fix is not a no-op.

But the remaining mismatch is still too large to call the clock/sample-rate contract coherent. Since:

- analog audio output is definitely present
- the pitch moved but did not land near the intended nominal value
- the new RTL explicitly changed the clocking path to a PLL-backed `12.000 MHz` `audio_mclk`
- the new RTL explicitly writes `R7 = 0`

the narrowest remaining suspect is still the codec/master-clock/sample-rate boundary on real hardware, not mute/routing and not the UART/control plane.

Without direct digital-rate measurements in this pass, I cannot narrow that further than:

- actual live `audio_mclk` on the board is not the intended `12.000 MHz`, or
- the WM8978 is not deriving the intended `audio_lrc` / effective sample rate from the written register set the way this interim contract assumes

## Next Actions

1. Measure the live digital clocks directly:
   - `audio_mclk`
   - `audio_bclk`
   - `audio_lrc`
2. Compare measured `audio_lrc` against the intended `~46.875 kHz`.
3. If `audio_mclk` is correct but `audio_lrc` is still fast, keep the diagnosis focused on the WM8978 rate/divider contract rather than the FPGA tone generator.

Bottom line: the new fix improved the pitch on real hardware, but did not finish the job. The end-to-end audio path still plays too fast, with the narrowest remaining suspect still at the codec clock/sample-rate boundary.
