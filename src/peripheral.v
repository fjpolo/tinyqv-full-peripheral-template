/*
* Copyright (c) 2025 Your Name
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

// This module is a memory-mapped peripheral for the onebitdac.v module.
// It provides an interface for a CPU to write 32-bit audio data and a 
// reload value, and to read the 'ready' status of the DAC.
module tqvp_fjpolo_onebitdac_full (
    input          clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input          rst_n,        // Reset_n - low to reset.

    input  [7:0]   ui_in,        // The input PMOD, not used in this peripheral.
    output [7:0]   uo_out,       // The output PMOD. uo_out[0] is the PWM output.

    input [5:0]    address,      // Address within this peripheral's address space
    input [31:0]   data_in,      // Data in to the peripheral.

    // Data read and write requests from the TinyQV core.
    input [1:0]    data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]    data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0]  data_out,     // Data out from the peripheral.
    output         data_ready,

    output         user_interrupt  // Dedicated interrupt request for this peripheral
);

    // Define addresses for the onebitdac module
    localparam A_DATA      = 6'h00; // Write 32-bit audio sample
    localparam A_RELOAD    = 6'h04; // Write 16-bit reload value
    localparam A_STATUS    = 6'h08; // Read status register

    // Internal registers to hold data and pulse valid signals
    reg [31:0] r_i_data;
    reg [15:0] r_i_reload_data;

    // Registers for the valid signals, which are pulsed for one clock cycle
    reg          r_data_valid;
    reg          r_reload_valid;

    // Wires for the onebitdac instance
    wire w_o_pwm;
    wire w_o_ready;

    // Instantiate the onebitdac module
    onebitdac #(
        .DEFAULT_RELOAD(16'd486),
        .NAUX(2),
        .VARIABLE_RATE(1),
        .TIMING_BITS(16)
    ) onebitdac_inst (
        .i_clk             (clk),
        .i_reset           (!rst_n),
        .i_data_valid      (r_data_valid),
        .i_data            (r_i_data),
        .i_reload_valid    (r_reload_valid),
        .i_reload_data     (r_i_reload_data),
        .o_pwm             (w_o_pwm),
        .o_ready           (w_o_ready)
    );

    // Logic for memory-mapped writes and pulsing valid signals
    always @(posedge clk) begin
        // Reset logic
        if (!rst_n) begin
            r_data_valid   <= 1'b0;
            r_reload_valid <= 1'b0;
            r_i_data       <= 32'h0;
            r_i_reload_data <= 16'h0;
        end else begin
            r_data_valid   <= 1'b0;
            r_reload_valid <= 1'b0;

            if (data_write_n != 2'b11) begin
                case(address)
                    A_DATA: begin
                        // Writing 32-bit data to the DAC
                        r_i_data <= data_in;
                        r_data_valid <= 1'b1;
                    end
                    A_RELOAD: begin
                        // Writing 16-bit reload value to the DAC
                        r_i_reload_data <= data_in[15:0];
                        r_reload_valid <= 1'b1;
                    end
                    default: begin
                        // Do nothing
                    end
                endcase
            end
        end
    end

    // Connect the DAC outputs to the PMOD output pins
    assign uo_out[0] = w_o_pwm;
    assign uo_out[1] = w_o_aux[0];
    assign uo_out[2] = w_o_aux[1];
    assign uo_out[7:3] = 5'h0;

    // Read logic for memory-mapped registers
    assign data_out = (address == A_STATUS) ? {31'h0, w_o_ready} : 32'h0;

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // The DAC does not generate an interrupt
    assign user_interrupt = 1'b0;

    // List all unused inputs to prevent warnings
    wire _unused = &{ui_in, data_read_n, 1'b0};

endmodule
