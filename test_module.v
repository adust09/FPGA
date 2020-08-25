`default_nettype none
`timescale 1 ns / 1 ps

module test_module;

    reg clk = 0;
    always #4 clk = ~clk;

    reg reset = 1;
    initial #10 reset = 0;

    wire [15:0] lfsr_poly = 16'b1000101110110111; // 16 15 11 9 8 7 5 4 2 1 0
    reg [15:0] lfsr_state;
    
    always @(posedge clk) begin
        if (reset == 1) lfsr_state <= -1;
        else lfsr_state <= (lfsr_state << 1) ^ ((lfsr_state[15]) ? lfsr_poly : 0);
    end

    initial begin
        $dumpfile("test_module_output.vcd");
        $dumpvars;

        #104;

        $display("Your magic number is:");
        $display(lfsr_state);
        $finish;
    end

endmodule
