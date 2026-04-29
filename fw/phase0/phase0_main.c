#include <stdint.h>

#include "phase0_hw.h"

#define PHASE0_CODEC_WAIT_LIMIT  2000000u
#define PHASE0_UART_WAIT_LIMIT    250000u
#define PHASE0_REPORT_DELAY     4000000u
#define PHASE0_RX_DELAY_SERVICE_CHUNK 8192u
#define PHASE0_CONTROL_BASELINE \
    (PHASE0_CONTROL_AUDIO_ENABLE_M | \
     PHASE0_CONTROL_TONE_ENABLE_M | \
     PHASE0_CONTROL_WAVE_SQUARE)
#define PHASE0_VOICE_CONTROL_BASELINE \
    (PHASE0_VOICE_CONTROL_ENABLE_M)
#define PHASE0_VOICE1_CONTROL_BASELINE \
    (PHASE0_VOICE1_CONTROL_ENABLE_M)
#define PHASE0_VOICE2_CONTROL_BASELINE \
    (PHASE0_VOICE2_CONTROL_ENABLE_M)
#define PHASE0_RR_EVENT_COUNT 6u
#define PHASE0_RX_MAX_LINE_BYTES 16u
#define PHASE0_RX_ERROR_NONE 0u
#define PHASE0_RX_ERROR_MALFORMED 1u
#define PHASE0_RX_ERROR_UNKNOWN_OPCODE 2u
#define PHASE0_RX_ERROR_OVERLONG 3u
#define PHASE0_RX_ERROR_PARTIAL_FLUSH 4u
#define PHASE0_RX_ERROR_RATE_LIMIT 5u
#define PHASE0_RX_ERROR_HARDWARE 6u
#define PHASE0_RX_ERROR_UNSUPPORTED_ARG 7u

static uint32_t phase0_rr_next_voice;
static uint32_t phase0_rr_event_count;
static uint32_t phase0_rr_assign_count[3];
static uint32_t phase0_rr_last_voice;
static uint32_t phase0_rr_drop_steal_count;
static uint32_t phase0_rx_command_count;
static uint32_t phase0_rx_error_count;
static uint32_t phase0_rx_last_error;
static uint32_t phase0_rx_line_len;
static uint32_t phase0_rx_discarding;
static uint32_t phase0_rx_discard_prev_cr;
static char phase0_rx_line[PHASE0_RX_MAX_LINE_BYTES];

static void phase0_service_uart_rx(void);

static void phase0_delay(uint32_t cycles)
{
    while (cycles != 0u) {
        uint32_t chunk = (cycles > PHASE0_RX_DELAY_SERVICE_CHUNK) ?
                         PHASE0_RX_DELAY_SERVICE_CHUNK :
                         cycles;

        cycles -= chunk;
        while (chunk != 0u) {
            __asm__ volatile ("nop");
            chunk--;
        }
        phase0_service_uart_rx();
    }
}

static uint32_t phase0_status(void)
{
    return phase0_mmio_read32(PHASE0_CTRL_ADDR(PHASE0_REG_STATUS));
}

static char phase0_hex_ascii(uint32_t nibble)
{
    if (nibble < 10u) {
        return (char)('0' + nibble);
    }

    return (char)('A' + (nibble - 10u));
}

static void phase0_uart_putc(char c)
{
    uint32_t timeout = PHASE0_UART_WAIT_LIMIT;

    while ((timeout != 0u) &&
           ((phase0_mmio_read32(PHASE0_UART_ADDR(PHASE0_UART_REG_STATUS)) &
             PHASE0_UART_STATUS_TX_READY_M) == 0u)) {
        phase0_service_uart_rx();
        timeout--;
    }

    if (timeout != 0u) {
        phase0_mmio_write32(PHASE0_UART_ADDR(PHASE0_UART_REG_TXDATA),
                            (uint32_t)(uint8_t)c);
    }
}

static void phase0_uart_put_hex32(uint32_t value)
{
    int nibble;

    for (nibble = 7; nibble >= 0; --nibble) {
        uint32_t shift = (uint32_t)nibble * 4u;
        phase0_uart_putc(phase0_hex_ascii((value >> shift) & 0xFu));
    }
}

static void phase0_uart_put_frame(char tag, uint32_t value)
{
    phase0_uart_putc(tag);
    phase0_uart_putc('=');
    phase0_uart_put_hex32(value);
    phase0_uart_putc('\r');
    phase0_uart_putc('\n');
}

static void phase0_write_control(uint32_t pulse_bits)
{
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_CONTROL),
                        PHASE0_CONTROL_BASELINE | pulse_bits);
}

static void phase0_write_voice_control(uint32_t pulse_bits)
{
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_CONTROL),
                        PHASE0_VOICE_CONTROL_BASELINE | pulse_bits);
}

static void phase0_write_voice1_control(uint32_t pulse_bits)
{
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE1_CONTROL),
                        PHASE0_VOICE1_CONTROL_BASELINE | pulse_bits);
}

static void phase0_write_voice2_control(uint32_t pulse_bits)
{
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE2_CONTROL),
                        PHASE0_VOICE2_CONTROL_BASELINE | pulse_bits);
}

static uint32_t phase0_voice_read(uint32_t reg_offset)
{
    return phase0_mmio_read32(PHASE0_CTRL_ADDR(reg_offset));
}

static void phase0_voice_clear_counters(void)
{
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_DIAG_CONTROL),
                        PHASE0_VOICE_DIAG_CONTROL_CLEAR_COUNTERS_M);
}

static void phase0_report_voice_debug(void)
{
    phase0_uart_put_frame('V', phase0_voice_read(PHASE0_REG_VOICE_STATUS));
    phase0_uart_put_frame('F', phase0_voice_read(PHASE0_REG_VOICE_SAMPLE_COUNT));
    phase0_uart_put_frame('T', phase0_voice_read(PHASE0_REG_VOICE_TRIGGER_COUNT));
    phase0_uart_put_frame('A', phase0_voice_read(PHASE0_REG_VOICE_ACTIVE_COUNT));
    phase0_uart_put_frame('W', phase0_voice_read(PHASE0_REG_VOICE_VALID_COUNT));
    phase0_uart_put_frame('Y', phase0_voice_read(PHASE0_REG_VOICE1_STATUS));
    phase0_uart_put_frame('U', phase0_voice_read(PHASE0_REG_VOICE1_TRIGGER_COUNT));
    phase0_uart_put_frame('B', phase0_voice_read(PHASE0_REG_VOICE1_ACTIVE_COUNT));
    phase0_uart_put_frame('C', phase0_voice_read(PHASE0_REG_VOICE1_VALID_COUNT));
    phase0_uart_put_frame('M', phase0_voice_read(PHASE0_REG_VOICE_MIX_STATUS));
    phase0_uart_put_frame('K', phase0_voice_read(PHASE0_REG_VOICE_MIX_CLIP_COUNT));
    phase0_uart_put_frame('Z', phase0_voice_read(PHASE0_REG_VOICE2_STATUS));
    phase0_uart_put_frame('O', phase0_voice_read(PHASE0_REG_VOICE2_TRIGGER_COUNT));
    phase0_uart_put_frame('D', phase0_voice_read(PHASE0_REG_VOICE2_ACTIVE_COUNT));
    phase0_uart_put_frame('E', phase0_voice_read(PHASE0_REG_VOICE2_VALID_COUNT));
    phase0_uart_put_frame('G', phase0_rr_event_count);
    phase0_uart_put_frame('H', phase0_rr_last_voice);
    phase0_uart_put_frame('J', phase0_rr_assign_count[0]);
    phase0_uart_put_frame('L', phase0_rr_assign_count[1]);
    phase0_uart_put_frame('N', phase0_rr_assign_count[2]);
    phase0_uart_put_frame('P', phase0_rr_drop_steal_count);
    phase0_uart_put_frame('Q', phase0_rx_command_count);
    phase0_uart_put_frame('X', ((phase0_rx_last_error & 0xFFFFu) << 16) |
                                (phase0_rx_error_count & 0xFFFFu));
}

static uint32_t phase0_wait_for_mask(uint32_t mask, uint32_t expected)
{
    uint32_t timeout = PHASE0_CODEC_WAIT_LIMIT;
    uint32_t status = phase0_status();

    while ((timeout != 0u) && ((status & mask) != expected)) {
        phase0_service_uart_rx();
        timeout--;
        status = phase0_status();
    }

    return status;
}

static uint32_t phase0_wait_for_any(uint32_t mask)
{
    uint32_t timeout = PHASE0_CODEC_WAIT_LIMIT;
    uint32_t status = phase0_status();

    while ((timeout != 0u) && ((status & mask) == 0u)) {
        phase0_service_uart_rx();
        timeout--;
        status = phase0_status();
    }

    return status;
}

static void phase0_program_defaults(void)
{
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_PHASE_STEP), 157482u);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_GAIN), 4096u);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_DECAY_STEP), 0u);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_VELOCITY),
                        PHASE0_VOICE_DEFAULT_VELOCITY);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_LOOP_LEN),
                        PHASE0_VOICE_DEFAULT_LOOP_LEN);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_LOOP_GAIN),
                        PHASE0_VOICE_DEFAULT_LOOP_GAIN);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_DAMP_MIX),
                        PHASE0_VOICE_DEFAULT_DAMP_MIX);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_DISP_COEFF),
                        PHASE0_VOICE_DEFAULT_DISP_COEFF);
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_VOICE_BODY_MIX),
                        PHASE0_VOICE_DEFAULT_BODY_MIX);
    phase0_write_control(0u);
    phase0_write_voice_control(PHASE0_VOICE_CONTROL_CLIP_CLEAR_M);
    phase0_write_voice1_control(PHASE0_VOICE1_CONTROL_CLIP_CLEAR_M);
    phase0_write_voice2_control(PHASE0_VOICE2_CONTROL_CLIP_CLEAR_M);
    phase0_voice_clear_counters();
    phase0_rr_next_voice = 0u;
    phase0_rr_event_count = 0u;
    phase0_rr_assign_count[0] = 0u;
    phase0_rr_assign_count[1] = 0u;
    phase0_rr_assign_count[2] = 0u;
    phase0_rr_last_voice = 0xFFFFFFFFu;
    phase0_rr_drop_steal_count = 0u;
    phase0_rx_command_count = 0u;
    phase0_rx_error_count = 0u;
    phase0_rx_last_error = PHASE0_RX_ERROR_NONE;
    phase0_rx_line_len = 0u;
    phase0_rx_discarding = 0u;
    phase0_rx_discard_prev_cr = 0u;
    phase0_mmio_write32(PHASE0_UART_ADDR(PHASE0_UART_REG_RXCONTROL),
                        PHASE0_UART_RXCONTROL_CLEAR_ERRORS_M);
}

static uint32_t phase0_wait_codec_ready(void)
{
    return phase0_wait_for_any(PHASE0_STATUS_CODEC_INIT_DONE_M |
                               PHASE0_STATUS_CODEC_INIT_FAILED_M);
}

static uint32_t phase0_wait_codec_idle(void)
{
    return phase0_wait_for_mask(PHASE0_STATUS_CODEC_BUSY_M, 0u);
}

static void phase0_codec_write(uint16_t codec_word)
{
    phase0_wait_codec_idle();
    phase0_mmio_write32(PHASE0_CTRL_ADDR(PHASE0_REG_CODEC_CFG),
                        (uint32_t)codec_word);
    phase0_write_control(PHASE0_CONTROL_CODEC_CFG_VALID_M);
    phase0_wait_codec_idle();
}

static void phase0_trigger_note(void)
{
    phase0_write_voice_control(PHASE0_VOICE_CONTROL_TRIGGER_M);
}

static void phase0_trigger_voice1_note(void)
{
    phase0_write_voice1_control(PHASE0_VOICE1_CONTROL_TRIGGER_M);
}

static void phase0_trigger_voice2_note(void)
{
    phase0_write_voice2_control(PHASE0_VOICE2_CONTROL_TRIGGER_M);
}

static uint32_t phase0_trigger_voice_index(uint32_t voice_index)
{
    switch (voice_index) {
    case 0u:
        phase0_trigger_note();
        return 1u;
    case 1u:
        phase0_trigger_voice1_note();
        return 1u;
    case 2u:
        phase0_trigger_voice2_note();
        return 1u;
    default:
        return 0u;
    }
}

static void phase0_round_robin_note_event(void)
{
    uint32_t voice_index = phase0_rr_next_voice;

    if (phase0_trigger_voice_index(voice_index) != 0u) {
        phase0_rr_assign_count[voice_index]++;
        phase0_rr_event_count++;
        phase0_rr_last_voice = voice_index;

        phase0_rr_next_voice = voice_index + 1u;
        if (phase0_rr_next_voice >= 3u) {
            phase0_rr_next_voice = 0u;
        }
    } else {
        phase0_rr_drop_steal_count++;
        phase0_rr_next_voice = 0u;
    }
}

static void phase0_run_round_robin_smoke(void)
{
    uint32_t event_index;

    for (event_index = 0u; event_index < PHASE0_RR_EVENT_COUNT; event_index++) {
        phase0_round_robin_note_event();
    }
}

static void phase0_rx_record_error(uint32_t error_code)
{
    phase0_rx_last_error = error_code;
    if (phase0_rx_error_count < 0xFFFFu) {
        phase0_rx_error_count++;
    }
}

static void phase0_rx_enter_discard(uint32_t error_code)
{
    phase0_rx_record_error(error_code);
    phase0_rx_line_len = 0u;
    phase0_rx_discarding = 1u;
    phase0_rx_discard_prev_cr = 0u;
}

static void phase0_rx_process_line(void)
{
    if ((phase0_rx_line_len == 4u) &&
        (phase0_rx_line[0] == '!') &&
        (phase0_rx_line[1] == 'N') &&
        (phase0_rx_line[2] == '\r') &&
        (phase0_rx_line[3] == '\n')) {
        phase0_round_robin_note_event();
        phase0_rx_command_count++;
    } else if ((phase0_rx_line_len >= 2u) &&
               (phase0_rx_line[0] == '!') &&
               (phase0_rx_line[1] == 'N')) {
        phase0_rx_record_error(PHASE0_RX_ERROR_UNSUPPORTED_ARG);
    } else if ((phase0_rx_line_len >= 2u) &&
               (phase0_rx_line[0] == '!')) {
        phase0_rx_record_error(PHASE0_RX_ERROR_UNKNOWN_OPCODE);
    } else {
        phase0_rx_record_error(PHASE0_RX_ERROR_MALFORMED);
    }

    phase0_rx_line_len = 0u;
}

static void phase0_rx_process_byte(uint32_t rx_byte)
{
    char c = (char)(uint8_t)rx_byte;
    uint32_t lf_after_cr;

    if (phase0_rx_discarding != 0u) {
        if ((phase0_rx_discard_prev_cr != 0u) && (c == '\n')) {
            phase0_rx_discarding = 0u;
            phase0_rx_discard_prev_cr = 0u;
        } else {
            phase0_rx_discard_prev_cr = (c == '\r') ? 1u : 0u;
        }
        return;
    }

    lf_after_cr = ((c == '\n') &&
                   (phase0_rx_line_len != 0u) &&
                   (phase0_rx_line[phase0_rx_line_len - 1u] == '\r')) ? 1u : 0u;

    if ((phase0_rx_line_len >= (PHASE0_RX_MAX_LINE_BYTES - 2u)) &&
        (c != '\r') &&
        (lf_after_cr == 0u)) {
        phase0_rx_enter_discard(PHASE0_RX_ERROR_OVERLONG);
        return;
    }
    if ((phase0_rx_line_len >= (PHASE0_RX_MAX_LINE_BYTES - 1u)) &&
        (c != '\n')) {
        phase0_rx_enter_discard(PHASE0_RX_ERROR_OVERLONG);
        return;
    }

    phase0_rx_line[phase0_rx_line_len] = c;
    phase0_rx_line_len++;

    if ((phase0_rx_line_len >= 2u) &&
        (phase0_rx_line[phase0_rx_line_len - 2u] == '\r') &&
        (c == '\n')) {
        phase0_rx_process_line();
    }
}

static void phase0_service_uart_rx(void)
{
    uint32_t status = phase0_mmio_read32(PHASE0_UART_ADDR(PHASE0_UART_REG_RXSTATUS));
    uint32_t service_limit = 64u;

    if ((status & (PHASE0_UART_RXSTATUS_OVERRUN_M |
                   PHASE0_UART_RXSTATUS_FRAME_ERROR_M)) != 0u) {
        phase0_rx_record_error(PHASE0_RX_ERROR_HARDWARE);
        phase0_mmio_write32(PHASE0_UART_ADDR(PHASE0_UART_REG_RXCONTROL),
                            PHASE0_UART_RXCONTROL_CLEAR_ERRORS_M);
    }

    while (((status & PHASE0_UART_RXSTATUS_VALID_M) != 0u) &&
           (service_limit != 0u)) {
        phase0_rx_process_byte(
            phase0_mmio_read32(PHASE0_UART_ADDR(PHASE0_UART_REG_RXDATA)) & 0xFFu);
        service_limit--;
        status = phase0_mmio_read32(PHASE0_UART_ADDR(PHASE0_UART_REG_RXSTATUS));
    }
}

void phase0_main(void)
{
    uint32_t ident = phase0_mmio_read32(PHASE0_CTRL_ADDR(PHASE0_REG_IDENT));
    uint32_t status;

    phase0_uart_put_frame('I', ident);

    phase0_program_defaults();
    status = phase0_wait_codec_ready();
    phase0_uart_put_frame('S', status);

    if ((ident == PHASE0_IDENT_VALUE) &&
        ((status & PHASE0_STATUS_CODEC_INIT_DONE_M) != 0u)) {
        phase0_codec_write(PHASE0_WM8978_WORD(52u, 0x019Eu));
        phase0_codec_write(PHASE0_WM8978_WORD(53u, 0x019Eu));
        phase0_run_round_robin_smoke();
    }

    phase0_service_uart_rx();
    status = phase0_status();
    phase0_uart_put_frame('R', status);
    phase0_report_voice_debug();

    for (;;) {
        phase0_delay(PHASE0_REPORT_DELAY);
        phase0_service_uart_rx();
        status = phase0_status();
        phase0_uart_put_frame('R', status);
        phase0_report_voice_debug();
    }
}
