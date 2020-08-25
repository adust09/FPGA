`default_nettype none
`timescale 1 ns / 1 ps
// Test Bench
module tb;
  reg clock = 0;
  always #10 clock = ~clock;
  reg reset_n = 0;
  initial #40 reset_n = 1;
  initial #10000 reset_n <= 0;
  //declare variables 
  wire tx_port;
  reg rx_port;
  reg tx_start;
  //start Test-Bench
  ir_transceiver DUT(
    .clock(clock),
    .reset_n(reset_n),
    .tx_port(tx_port),
    .rx_port(rx_port),
    .tx_start(tx_start)
  );
  //when tx_port overwrite, substitute it for rx_port
  always @ (tx_port) begin
    rx_port <= tx_port;
  end
  //capture simulation
  initial begin
    $dumpfile("output2.vcd");
    $dumpvars;
    tx_start <= 1;
    #20000;
    @(negedge clock);
    tx_start <= 0;
    @(negedge clock);
    $finish;
  end
endmodule