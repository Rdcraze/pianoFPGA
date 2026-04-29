#ifndef PHASE0_HW_H
#define PHASE0_HW_H

#include <stdint.h>

/*
 * Provisional Phase 0 memory map for the future RISC-V control subsystem.
 * The current RTL still uses phase0_soc_stub.v, but keeping the firmware
 * contract stable now makes later CPU integration smaller and clearer.
 */
#define PHASE0_ROM_BASE   0x00000000u
#define PHASE0_ROM_SIZE   0x00001000u
#define PHASE0_RAM_BASE   0x00010000u
#define PHASE0_RAM_SIZE   0x00001000u
#define PHASE0_CTRL_BASE  0x40000000u
#define PHASE0_UART_BASE  0x40001000u

#define PHASE0_REG_IDENT       0x00u
#define PHASE0_REG_CONTROL     0x04u
#define PHASE0_REG_PHASE_STEP  0x08u
#define PHASE0_REG_GAIN        0x0Cu
#define PHASE0_REG_DECAY_STEP  0x10u
#define PHASE0_REG_CODEC_CFG   0x14u
#define PHASE0_REG_STATUS      0x18u
#define PHASE0_REG_VOICE_CONTROL    0x20u
#define PHASE0_REG_VOICE_STATUS     0x24u
#define PHASE0_REG_VOICE_VELOCITY   0x28u
#define PHASE0_REG_VOICE_LOOP_LEN   0x2Cu
#define PHASE0_REG_VOICE_LOOP_GAIN  0x30u
#define PHASE0_REG_VOICE_DAMP_MIX   0x34u
#define PHASE0_REG_VOICE_DISP_COEFF 0x38u
#define PHASE0_REG_VOICE_BODY_MIX   0x3Cu
#define PHASE0_REG_VOICE_SAMPLE_COUNT  0x40u
#define PHASE0_REG_VOICE_TRIGGER_COUNT 0x44u
#define PHASE0_REG_VOICE_ACTIVE_COUNT  0x48u
#define PHASE0_REG_VOICE_VALID_COUNT   0x4Cu
#define PHASE0_REG_VOICE_DIAG_CONTROL  0x50u
#define PHASE0_REG_VOICE1_CONTROL       0x54u
#define PHASE0_REG_VOICE1_STATUS        0x58u
#define PHASE0_REG_VOICE1_TRIGGER_COUNT 0x5Cu
#define PHASE0_REG_VOICE1_ACTIVE_COUNT  0x60u
#define PHASE0_REG_VOICE1_VALID_COUNT   0x64u
#define PHASE0_REG_VOICE_MIX_STATUS     0x68u
#define PHASE0_REG_VOICE_MIX_CLIP_COUNT 0x6Cu
#define PHASE0_REG_VOICE2_CONTROL       0x70u
#define PHASE0_REG_VOICE2_STATUS        0x74u
#define PHASE0_REG_VOICE2_TRIGGER_COUNT 0x78u
#define PHASE0_REG_VOICE2_ACTIVE_COUNT  0x7Cu
#define PHASE0_REG_VOICE2_VALID_COUNT   0x80u

#define PHASE0_CONTROL_AUDIO_ENABLE_M      (1u << 0)
#define PHASE0_CONTROL_TONE_ENABLE_M       (1u << 1)
#define PHASE0_CONTROL_WAVE_SEL_SHIFT      4u
#define PHASE0_CONTROL_TRIGGER_STROBE_M    (1u << 8)
#define PHASE0_CONTROL_CODEC_CFG_VALID_M   (1u << 9)

#define PHASE0_CONTROL_WAVE_SQUARE \
    (0u << PHASE0_CONTROL_WAVE_SEL_SHIFT)
#define PHASE0_CONTROL_WAVE_SAW \
    (1u << PHASE0_CONTROL_WAVE_SEL_SHIFT)
/* Selector 2 is the envelope-only pulse waveform from phase0_sample_gen.v. */
#define PHASE0_CONTROL_WAVE_ENV \
    (2u << PHASE0_CONTROL_WAVE_SEL_SHIFT)

#define PHASE0_VOICE_CONTROL_ENABLE_M      (1u << 0)
#define PHASE0_VOICE_CONTROL_TRIGGER_M     (1u << 1)
#define PHASE0_VOICE_CONTROL_RESET_M       (1u << 2)
#define PHASE0_VOICE_CONTROL_BODY_BYPASS_M (1u << 3)
#define PHASE0_VOICE_CONTROL_DISP_BYPASS_M (1u << 4)
#define PHASE0_VOICE_CONTROL_CLIP_CLEAR_M  (1u << 8)

#define PHASE0_VOICE1_CONTROL_ENABLE_M     (1u << 0)
#define PHASE0_VOICE1_CONTROL_TRIGGER_M    (1u << 1)
#define PHASE0_VOICE1_CONTROL_RESET_M      (1u << 2)
#define PHASE0_VOICE1_CONTROL_CLIP_CLEAR_M (1u << 8)

#define PHASE0_VOICE2_CONTROL_ENABLE_M     (1u << 0)
#define PHASE0_VOICE2_CONTROL_TRIGGER_M    (1u << 1)
#define PHASE0_VOICE2_CONTROL_RESET_M      (1u << 2)
#define PHASE0_VOICE2_CONTROL_CLIP_CLEAR_M (1u << 8)

#define PHASE0_VOICE_DIAG_CONTROL_CLEAR_COUNTERS_M (1u << 0)

#define PHASE0_VOICE_STATUS_ACTIVE_M       (1u << 0)
#define PHASE0_VOICE_STATUS_EXCITE_BUSY_M  (1u << 1)
#define PHASE0_VOICE_STATUS_CLIP_SEEN_M    (1u << 2)
#define PHASE0_VOICE_STATUS_SAMPLE_VALID_M (1u << 3)
#define PHASE0_VOICE_STATUS_ENABLED_M      (1u << 4)
#define PHASE0_VOICE_STATUS_PEAK_SHIFT     16u

#define PHASE0_VOICE_DEFAULT_VELOCITY      0x4000u
#define PHASE0_VOICE_DEFAULT_LOOP_LEN      106u
#define PHASE0_VOICE_DEFAULT_LOOP_GAIN     32640u
#define PHASE0_VOICE_DEFAULT_DAMP_MIX      16384u
#define PHASE0_VOICE_DEFAULT_DISP_COEFF    9952u
#define PHASE0_VOICE_DEFAULT_BODY_MIX      8192u

#define PHASE0_STATUS_CODEC_INIT_DONE_M    (1u << 31)
#define PHASE0_STATUS_CODEC_INIT_FAILED_M  (1u << 30)
#define PHASE0_STATUS_CODEC_ERROR_SEEN_M   (1u << 29)
#define PHASE0_STATUS_CODEC_TIMEOUT_SEEN_M (1u << 28)
/* Bit 27 reports a queued CPU-owned codec request awaiting handoff. */
#define PHASE0_STATUS_CODEC_PENDING_M      (1u << 27)
#define PHASE0_STATUS_AUDIO_TX_VALID_M     (1u << 26)
#define PHASE0_STATUS_AUDIO_SAMPLE_TICK_M  (1u << 25)
/* Bit 24 is the completion fence and stays high until the I2C-side transaction finishes. */
#define PHASE0_STATUS_CODEC_BUSY_M         (1u << 24)

#define PHASE0_UART_REG_TXDATA   0x00u
#define PHASE0_UART_REG_STATUS   0x04u
#define PHASE0_UART_REG_RXDATA   0x08u
#define PHASE0_UART_REG_RXSTATUS 0x0Cu
#define PHASE0_UART_REG_RXCONTROL 0x10u
#define PHASE0_UART_STATUS_TX_READY_M (1u << 0)
#define PHASE0_UART_RXSTATUS_VALID_M        (1u << 0)
#define PHASE0_UART_RXSTATUS_FULL_M         (1u << 1)
#define PHASE0_UART_RXSTATUS_OVERRUN_M      (1u << 2)
#define PHASE0_UART_RXSTATUS_FRAME_ERROR_M  (1u << 3)
#define PHASE0_UART_RXSTATUS_DROPPED_M      (1u << 4)
#define PHASE0_UART_RXCONTROL_CLEAR_ERRORS_M (1u << 0)
#define PHASE0_UART_RXCONTROL_FLUSH_FIFO_M   (1u << 1)

#define PHASE0_IDENT_VALUE 0x50303031u

#define PHASE0_CTRL_ADDR(offset) (PHASE0_CTRL_BASE + (offset))
#define PHASE0_UART_ADDR(offset) (PHASE0_UART_BASE + (offset))

#define PHASE0_WM8978_WORD(reg_index, reg_value) \
    ((((uint16_t)(reg_index) & 0x7Fu) << 9) | ((uint16_t)(reg_value) & 0x1FFu))

static inline void phase0_mmio_write32(uint32_t addr, uint32_t value)
{
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t phase0_mmio_read32(uint32_t addr)
{
    return *(volatile uint32_t *)addr;
}

#endif
