`default_nettype none
`timescale 1 ns / 1 ps

`define assert(signal, value, detail) \
        if (signal !== value) begin \
            $display("ASSERTION FAILED @ %t: signal should be value, but was %x detail.", $time, signal); \
            $finish; \
        end

// This Testbench is for Assignment 5.

module tb;

    parameter BASE_DELAY = 250;

    reg clock = 0;
    always #10 clock = ~clock;  // 20 ns period for 50 MHz clock

    reg reset_n = 0;
    initial #100 reset_n = 1; // release reset after 100 ns

    reg [31:0] tx_data;
    reg tx_start;
    wire tx_busy;
    
    wire tx_port;
    
    
    // Device Under Test
    ir_transmitter #(
        //.BASE_DELAY(BASE_DELAY)
    ) dut (
        .clock(clock),
        .reset_n(reset_n),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy),

        .tx_port(tx_port)
    );

    reg signed [6:0] i;
    reg [31:0] delay;

    initial begin
        $timeformat(-9, 2, " ns", 1);
        $dumpfile("ir_transmitter.vcd");
        $dumpvars;

        tx_start = 0;
        tx_data = 0;

        #100;
        @(negedge clock);

        // check condition after reset
        `assert(tx_busy, 0, after reset)
        `assert(tx_port, 0, after reset)


        tx_data = 32'hBEEF0001;
        @(negedge clock);
        
        // transmission not yet started
        `assert(tx_busy, 0, after setting tx_data)
        `assert(tx_port, 0, after setting tx_data)

        tx_start = 1;
        @(posedge clock);
        $display("Started a transmission at time %t", $time);
        @(negedge clock);
        tx_start = 0;

        for ( i=63 ; i !== -1 ; i=i-1 ) begin
            `assert(tx_busy, 1, after starting a transmission)

            delay = BASE_DELAY;
            if ( i < 32 ) begin
                if (tx_data[i]) begin 
                    delay = BASE_DELAY / 2;
                    $display("Checking that symbol %d is 1 (expected start time of symbol: %t)", i, $time);
                end else begin
                    delay = BASE_DELAY + BASE_DELAY / 2;
                    $display("Checking that symbol %d is 0 (expected start time of symbol: %t)", i, $time);
                end
            end else begin
                $display("Checking that symbol %d is X (expected start time of symbol: %t)", i, $time);
            end
            #(delay*20);  // delay until the middle of the 1 pulse of the symbol
            `assert(tx_port, 1, at this time in the transmission)
            #(delay*2*20);  // delay until the middle of the 0 phase of the symbol
            `assert(tx_port, 0, at this time in the transmission)
            #(delay*20);  // delay until the end of the symbol
        end
        #(BASE_DELAY*20);
        `assert(tx_port, 1, at this time in the transmission as the stop symbol)
        #(BASE_DELAY*2*20);
        `assert(tx_port, 0, after the transmission)
        `assert(tx_busy, 0, after the transmission)

        @(negedge clock);

        $display("IR transmitter test was successful! ^o^");

        $finish;
    end

endmodule
