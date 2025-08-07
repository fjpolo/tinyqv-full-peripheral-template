////////////////////////////////////////////////////////////////////////////////
//
// Filename:    onebitdac.v
//
// Project: A Standard Interface Controlled PWM (audio) controller
//
// Purpose: This PWM controller was designed with audio in mind, although
//  it should be sufficient for many other purposes.  Specifically,
//  it creates a pulse-width modulated output, where the amount of time
//  the output is 'high' is determined by the pulse width data given to
//  it.  Further, the 'high' time is spread out in bit reversed order.
//  In this fashion, a halfway point will alternate between high and low,
//  rather than the normal fashion of being high for half the time and then
//  low.  This approach was chosen to move the PWM artifacts to higher,
//  inaudible frequencies and hence improve the sound quality.
//
//  The interface supports two types of writes:
//
//  `i_data` is the data input. When `i_data_valid` is high, the 32-bit
//  sample value will be produced by the PWM logic.
//  
//  `i_reload_data` is a timer reload value, used to determine how often the
//  PWM logic needs its next value. This value is written when
//  `i_reload_valid` is high. This number should be set
//  to the number of clock cycles between reload values.
//
//  `o_ready` indicates the device is ready for a new sample.
//
//  The `VARIABLE_RATE` parameter still controls whether the sample
//  rate can be changed dynamically.
//
// Creator: Dan Gisselquist, Ph.D.
//  Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015-2024, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License: GPL, v3, as defined and found on www.gnu.org,
//  http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype none
//
module onebitdac(
                     i_clk, 
                     i_reset,
                     // Standard interface
                     i_data_valid, 
                     i_data,
                     i_reload_valid, 
                     i_reload_data,
                     o_pwm, o_aux, 
                     o_ready
                 );
    parameter  DEFAULT_RELOAD = 16'd486, // about 44.1 kHz sample rate @ 21.477270MHz clock, 32-bit data
               NAUX=2,
               VARIABLE_RATE=0,
               TIMING_BITS=16;
    input wire                      i_clk, i_reset;
    // Standard interface signals
    input wire                      i_data_valid;
    input wire [31:0]               i_data;
    input wire                      i_reload_valid;
    input wire [(TIMING_BITS-1):0]  i_reload_data;
    output reg                      o_pwm;
    output reg [(NAUX-1):0]         o_aux;
    output wire                     o_ready;


    // How often shall we create an interrupt?  Every reload_value clocks!
    // If VARIABLE_RATE==0, this value will never change and will be kept
    // at the default reload rate (defined up top)
    wire [(TIMING_BITS-1):0] w_reload_value;
    generate
    if (VARIABLE_RATE != 0)
    begin : GEN_VARIABLE_RELOAD
          reg [(TIMING_BITS-1):0] r_reload_value;
          initial r_reload_value = DEFAULT_RELOAD;
          always @(posedge i_clk) // Data write
             if (i_reload_valid)
                 r_reload_value <= i_reload_data - 1'b1;
          assign w_reload_value = r_reload_value;
    end else begin : FIXED_RELOAD_VALUE
          assign w_reload_value = DEFAULT_RELOAD;
    end endgenerate

    //
    // The next value timer
    //
    // We'll want a new sample every w_reload_value clocks.  When the
    // timer hits zero, the signal ztimer (zero timer) will also be
    // set--allowing following logic to depend upon it.
    //
    reg             ztimer;
    reg [(TIMING_BITS-1):0] timer;
    initial timer = DEFAULT_RELOAD;
    initial ztimer= 1'b0;
    always @(posedge i_clk)
          if (i_reset)
             ztimer <= 1'b0;
          else
             ztimer <= (timer == { {(TIMING_BITS-1){1'b0}}, 1'b1 });

    always @(posedge i_clk)
          if ((ztimer)||(i_reset))
             timer <= w_reload_value;
          else
             timer <= timer - {{(TIMING_BITS-1){1'b0}},1'b1};

    //
    // Whenever the timer runs out, accept the next value from the single
    // sample buffer.
    //
    reg [31:0] sample_out;
    always @(posedge i_clk)
          if (i_reset)
             sample_out <= 32'h8000_0000; // Added reset condition
          else if (ztimer)
             sample_out <= next_sample;


    //
    // Control what's in the single sample buffer, next_sample, as well as
    // whether or not it's a valid sample.  Specifically, if next_valid is
    // false, then the sample buffer needs a new value.
    reg [31:0] next_sample;
    reg next_valid;
    initial next_valid = 1'b1;
    initial next_sample = 32'h8000_0000;
    always @(posedge i_clk)
          if (i_reset)
          begin
             next_sample <= 32'h8000_0000; // Added reset condition
             next_valid <= 1'b1;
          end
          else if (i_data_valid)
          begin
             // Write with two's complement data, convert it
             // internally to an unsigned binary offset
             // representation
             next_sample <= { !i_data[31], i_data[30:0] };
             next_valid <= 1'b1;
             // o_aux is no longer controlled by a specific bit on the bus,
             // as this would require a separate `i_aux_valid` signal which is
             // not needed for this simplified interface.
             // o_aux <= i_wb_data[(NAUX+20-1):20];
          end else if (ztimer)
             next_valid <= 1'b0;

    // The `o_ready` signal is high when a new sample is needed.
    assign o_ready = (!next_valid);

    //
    // To generate our waveform, we'll compare our sample value against
    // a bit reversed counter.  This counter is kept in pwm_counter.
    // The choice of a 32-bit counter matches the new input data width
    // and provides maximum resolution.
    reg [31:0] pwm_counter;
    initial pwm_counter = 32'h00;
    always @(posedge i_clk)
          if (i_reset)
             pwm_counter <= 32'h0;
          else
             pwm_counter <= pwm_counter + 32'h01;

    // Bit-reverse the counter
    wire [31:0] br_counter;
    genvar k;
    generate for(k=0; k<32; k=k+1)
    begin : bit_reversal_loop
          assign br_counter[k] = pwm_counter[31-k];
    end endgenerate

    // Apply our comparison to determine the next output bit
    always @(posedge i_clk)
          if (i_reset)
             o_pwm <= 1'b0; // Added reset condition
          else
             o_pwm <= (sample_out >= br_counter);

endmodule
