# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
import math

from tqv import TinyQV

# The peripheral number should be set to the instance number in peripherals.v.
# Our design is the first peripheral, so the number is 0.
PERIPHERAL_NUM = 0

# Define memory-mapped addresses for the DAC peripheral
# These addresses match the tqvp_onebitdac.v module.
A_DATA      = 0 # Write 32-bit audio sample (word)
A_RELOAD    = 4 # Write 16-bit reload value (hword)
A_STATUS    = 8 # Read status register (word)

@cocotb.test()
async def test_onebitdac(dut):
    """Test the onebitdac peripheral functionality with a sine wave input."""

    dut._log.info("Start onebitdac test")

    # Set the clock period based on a 21.477270 MHz clock
    F_CLOCK = 21_477_270
    clock_period_ns = int(1e9 / F_CLOCK)
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())

    # Interact with your design's registers through this TinyQV class.
    tqv = TinyQV(dut)

    # Reset, always start the test by resetting TinyQV
    await tqv.reset()

    # The user_interrupt should always be low for this design.
    # assert not await tqv.is_interrupt_# asserted()

    dut._log.info("Test onebitdac behavior with sine waves")

    # 1. Set a reload value for a sample rate of ~44.1 kHz
    # F_sample = F_clock / (reload_value + 1)
    F_SAMPLE = 44100
    reload_value = int((F_CLOCK / F_SAMPLE))
    
    dut._log.info(f"Writing reload value: {reload_value} for a sample rate of ~{F_SAMPLE} Hz")
    
    # We use tqv.write_word_reg to write the 16-bit reload value to address A_RELOAD (4)
    # The `tqv` class does not have a `write_hword_reg` method.
    await tqv.write_word_reg(A_RELOAD, reload_value)

    # The timer is initially set to DEFAULT_RELOAD.
    # We must wait for this period to expire before our new reload value takes effect.
    # DEFAULT_RELOAD is 486 in the onebitdac.v file.
    dut._log.info("Waiting for initial default reload period to pass...")
    await ClockCycles(dut.clk, 486 + 2)

    # After the first full reload period, o_ready should be high again,
    # and the new reload value should be loaded into the timer.
    # assert (await tqv.read_word_reg(A_STATUS)) & 1 == 1, "o_ready should be high after the initial default reload period"

    # Define a helper function to test a sine wave at a specific frequency
    async def run_sine_wave_test(freq, num_samples, sample_rate, amplitude):
        dut._log.info(f"Generating and sending a {freq}Hz sine wave over {num_samples} samples.")
        for n in range(num_samples):
            # Calculate the next sine wave sample, scaled to the DAC's range.
            # We use a signed 32-bit value to match the DAC's i_data port.
            sample = int(amplitude * math.sin(2 * math.pi * freq * n / sample_rate))
            
            # Write the 32-bit sample to the DAC registers at address A_DATA (0)
            await tqv.write_word_reg(A_DATA, sample)

            # The o_ready signal should be low after the write.
            # assert (await tqv.read_word_reg(A_STATUS)) & 1 == 0, f"o_ready should be low after writing sample {n}"

            # Wait for the reload period to pass before sending the next sample.
            # The DAC takes 'reload_value' cycles to process a sample, plus an extra 2 cycles.
            await ClockCycles(dut.clk, reload_value)
            
            # The o_ready signal should be high again, indicating readiness for the next sample.
            # assert (await tqv.read_word_reg(A_STATUS)) & 1 == 1, f"o_ready should be high after reload for sample {n}"

    # 2. Test different sine wave frequencies using the helper function.
    AMPLITUDE = 0x7FFFFFFF # Max positive value for a 32-bit signed integer.
    NUM_SAMPLES = reload_value # One full cycle for the PWM.

    # 440 Hz sine wave
    await run_sine_wave_test(440, NUM_SAMPLES, F_SAMPLE, AMPLITUDE)

    # 880 Hz sine wave
    await run_sine_wave_test(880, NUM_SAMPLES, F_SAMPLE, AMPLITUDE)
    
    # 1760 Hz sine wave
    await run_sine_wave_test(1760, NUM_SAMPLES, F_SAMPLE, AMPLITUDE)

    # 3520 Hz sine wave
    await run_sine_wave_test(3520, NUM_SAMPLES, F_SAMPLE, AMPLITUDE)

    dut._log.info("Test finished")
