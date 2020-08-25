`default_nettype none
module ir_transmitter #(

    // Minimum number of clock cycles between tx_port transitions.
    // Must be greater than 0.
    // Set according to hardware bandwidth limitation.
    // Required_HW_bandwidth = clock_Frequency / BASE_DELAY / 2
    // E.g.:
    //   50 MHz / 10 / 2 = 2.5 MHz (can be used in simulation)
    //   50 MHz / 250 / 2 = 100 kHz (used on real hardware)
    parameter BASE_DELAY = 250
    //parameter BASE_DELAY = 10
)(

    input wire clock,
    input wire reset_n,
    
    input wire [31:0] tx_data,
    input wire tx_start,
    output reg tx_busy,

    output reg tx_port

);

    localparam 
        IDLE     = 2'b00,
        TX_WAIT0 = 2'b01,
        TX_WAIT1 = 2'b10,
        TX_STOP  = 2'b11;

    reg [1:0] state;
    
    reg [5:0] symbol_count;  // 6 bits to store values 0...63

    reg [$clog2(BASE_DELAY*3)-1:0] clock_count;  // enough bits to store values 0...(BASE_DELAY*3)-1

    always @ (posedge clock) begin
        if (~reset_n) begin
            state <= IDLE;
            clock_count <= 0;
            symbol_count <= 0;
            tx_port <= 0;
            tx_busy <= 0;
        end
        else begin
            case(state)
                IDLE: begin
                    if (tx_start) begin
                        symbol_count <= ~0;  // set to maximum value (63)
                        clock_count <= (BASE_DELAY * 2) - 1;
                        tx_busy <= 1;
                        tx_port <= 1;
                        state <= TX_WAIT0;
                    end 
                    else begin
                        tx_busy <= 0;
                        tx_port <= 0;
                    end
                end
                TX_WAIT0: begin
                    if (clock_count > 0) clock_count <= clock_count - 1;
                    else begin
                        if (symbol_count > 31) clock_count <= (BASE_DELAY * 2) - 1;  // set delay for current symbol
                        else if (tx_data[symbol_count]) clock_count <= (BASE_DELAY * 1) - 1;
                        else clock_count <= (BASE_DELAY * 3) - 1;
                        tx_port <= 0;
                        state <= TX_WAIT1;
                    end
                end
                TX_WAIT1: begin
                    if (clock_count > 0) clock_count <= clock_count - 1;
                    else begin
                        if (symbol_count > 0) begin
                            if ((symbol_count-1) > 31) clock_count <= (BASE_DELAY * 2) - 1;  // set delay for next symbol
                            else if (tx_data[symbol_count-1]) clock_count <= (BASE_DELAY * 1) - 1;
                            else clock_count <= (BASE_DELAY * 3) - 1;
                            symbol_count <= symbol_count - 1;
                            tx_port <= 1;
                            state <= TX_WAIT0;
                        end
                        else begin
                            clock_count <= (BASE_DELAY * 2) - 1;  // stop pulse
                            tx_port <= 1;
                            state <= TX_STOP;
                        end
                    end
                end
                TX_STOP: begin
                    if (clock_count > 0) clock_count <= clock_count - 1;
                    else begin
                        tx_port <= 0;
                        state <= IDLE;
                    end 
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


module ir_receiver #(
    // The number of bits in the delay measurement registers.
    // Determines the maximum number of clock cycles between rising transitions on rx_port.
    // 2**CLOCK_COUNT_WIDTH must be bigger than 6*BASE_DELAY of the transmitter.
    // E.g.:
    //   BASE_DELAY = 250, 6*250=1500, 2**11 = 2048 -> CLOCK_COUNT_WIDTH=11
    parameter CLOCK_COUNT_WIDTH = 11
) (
    input wire clock,
    input wire reset_n,
    
    input wire rx_enable,
    output reg [31:0] rx_data,
    output reg rx_received,

    input wire rx_port
);

    // rx_port is coming from outside the FPGA and is not synchronized to its internal
    // clock. We need to synchronize this signal with a flip-flop. Otherwise the state-machine
    // would not work properly on the FPGA.

    reg rx_port_synced;
    always @ (posedge clock) begin
       rx_port_synced <= rx_port;
    end

    localparam 
        IDLE              = 3'b000,
        RX_TRAIN_WAIT1    = 3'b001,
        RX_TRAIN_WAIT0    = 3'b010,
        RX_VALIDATE_WAIT1 = 3'b011,
        RX_VALIDATE_WAIT0 = 3'b100,
        RX_LOCKED_WAIT1   = 3'b101,
        RX_LOCKED_WAIT0   = 3'b110,
        RX_RECEIVED       = 3'b111;

    reg [2:0] state;

    reg [5:0] symbol_count;

    reg [CLOCK_COUNT_WIDTH-1:0] clock_count;

    reg [CLOCK_COUNT_WIDTH-1:0] learned_delay;

    always @ (posedge clock) begin
        if (reset_n == 1'b0) begin
            state <= IDLE;
            symbol_count <= 0;
            clock_count <= 0;
            learned_delay <= 0;
            rx_data <= 0;
            rx_received <= 0;
        end
        else begin
            case(state)
                IDLE: begin // 0
                    if (rx_enable) begin
                        symbol_count <= 16; // use 16 measurements for training
                        clock_count <= 0;
                        rx_data <= 0;
                        state <= RX_TRAIN_WAIT0;
                    end
                end
                RX_TRAIN_WAIT1: begin // 1
                    if (&clock_count) state <= IDLE; // if clock_count is all-1, we were waiting for too long.
                    else begin
                        if (rx_port_synced) begin
                            learned_delay <= ((learned_delay+1) / 2) + (clock_count / 2);
                            clock_count <= 1;
                            symbol_count <= symbol_count - 1;
                            state <= RX_TRAIN_WAIT0;
                        end else clock_count <= clock_count + 1;
                    end
                end
                RX_TRAIN_WAIT0: begin // 2
                    if (&clock_count) state <= IDLE;
                    else begin
                        clock_count <= clock_count + 1;
                        if (~rx_port_synced) begin
                            if (symbol_count) state <= RX_TRAIN_WAIT1;
                            else begin
                                symbol_count <= 8;  // use 8 measurements for validation
                                state <= RX_VALIDATE_WAIT1;
                            end
                        end
                    end
                end
                RX_VALIDATE_WAIT1: begin // 3
                    if (&clock_count) state <= IDLE;
                    else begin
                        if (rx_port_synced) begin
                            if (clock_count >= (learned_delay + (learned_delay/4))) state <= IDLE;
                            else if (clock_count <= (learned_delay - (learned_delay/4))) state <= IDLE;
                            else state <= RX_VALIDATE_WAIT0;  // go to IDLE whenever measured delay is too high or too low.
                            clock_count <= 1;
                            symbol_count <= symbol_count - 1;
                        end else clock_count <= clock_count + 1;
                    end
                end
                RX_VALIDATE_WAIT0: begin // 4
                    if (&clock_count) state <= IDLE;
                    else begin
                        clock_count <= clock_count + 1;
                        if (~rx_port_synced) begin
                            if (symbol_count) state <= RX_VALIDATE_WAIT1;
                            else begin
                                symbol_count <= 31;
                                state <= RX_LOCKED_WAIT1;
                            end
                        end
                    end
                end
                RX_LOCKED_WAIT1: begin // 5
                    if (&clock_count) state <= IDLE;
                    else begin
                        if (rx_port_synced) begin
                            if (clock_count >= (learned_delay + (learned_delay/4))) begin
                                rx_data[symbol_count] <= 1'b0; // received a 0
                                symbol_count <= symbol_count - 1;
                            end
                            else if (clock_count <= (learned_delay - (learned_delay/4))) begin
                                rx_data[symbol_count] <= 1'b1; // received a 1
                                symbol_count <= symbol_count - 1;
                            end // else we have an X. We ignore X's, they may come from preamble.
                            clock_count <= 1;
                            state <= RX_LOCKED_WAIT0;
                        end else clock_count <= clock_count + 1;
                    end
                end
                RX_LOCKED_WAIT0: begin // 6
                    if (&clock_count) state <= IDLE;
                    else begin
                        clock_count <= clock_count + 1;
                        if (~rx_port_synced) begin
                            if (&symbol_count) begin
                                rx_received <= 1;
                                state <= RX_RECEIVED;
                            end
                            else begin
                                state <= RX_LOCKED_WAIT1;
                            end
                        end
                    end
                end
                RX_RECEIVED: begin // 7
                    if (~rx_enable) begin  // wait until rx_enable is low
                        rx_received <= 0;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule

module ir_transceiver(
  input wire [31:0] tx_data,
  input wire tx_start,
  input wire clock,
  input wire reset_n,
  input wire rx_enable,
  input wire rx_port,
  output wire rx_received,
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
    .rx_received(rx_received),
    .rx_data(rx_data)
  );
endmodule