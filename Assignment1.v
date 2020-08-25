module ir_transmitter(
  input wire [31:0] tx_data,
  input wire tx_start,
  input wire clock,
  input wire reset_n,
  output reg tx_port,
  output reg tx_busy
);
endmodule

module ir_receiver(
  input wire clock,
  input wire reset_n,
  input wire rx_enable,
  input wire rx_port,
  output reg rx_receiver,
  output reg [31:0] rx_data
);
endmodule

module ir_transceiver(
  input wire [31:0] tx_data,
  input wire tx_start,
  input wire clock,
  input wire reset_n,
  input wire rx_enable,
  input wire rx_port,
  output wire rx_receiver,
  output wire [31:0] rx_data,
  output wire tx_port,
  output wire tx_busy
);
  ir_transmitter inst1(
    .clock(clock),
    .tx_data(tx_data),
    .tx_start(tx_start),
    .reset_n(reset_n),
    .tx_port(tx_port),
    .tx_busy(tx_busy)
  );
  ir_receiver inst2(
    .clock(clock),
    .reset_n(reset_n),
    .rx_enable(rx_enable),
    .rx_port(rx_port),
    .rx_receiver(rx_receiver),
    .rx_data(rx_data)
  );
endmodule

