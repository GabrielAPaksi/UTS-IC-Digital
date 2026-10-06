module tm1638(
    input clk,
    input rst,

    input data_latch,
    input [7:0] data,       // FIX: Diubah dari inout menjadi input biasa
    input rw,

    output busy,

    output reg sclk = 1'b1,
    input  dio_in,
    output reg dio_out
);

    localparam [1:0]
        S_IDLE      = 2'h0,
        S_TRANSFER  = 2'h1;

    reg [1:0] cur_state = S_IDLE;
    reg [7:0] clk_cnt = 0;
    reg [7:0] data_q = 0;
    reg [7:0] data_out_q = 0;
    reg [2:0] bit_cnt = 0;

    assign busy = (cur_state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            cur_state  <= S_IDLE;
            sclk       <= 1'b1;
            dio_out    <= 1'b0;
            bit_cnt    <= 3'b0;
            data_q     <= 8'b0;
            data_out_q <= 8'b0;
            clk_cnt    <= 0;
        end else begin
            case (cur_state)
                S_IDLE: begin
                    sclk    <= 1'b1;
                    bit_cnt <= 3'b0;
                    clk_cnt <= 0;
                    if (data_latch) begin
                        data_q    <= data; // Memuat byte data yang akan dikirim
                        cur_state <= S_TRANSFER;
                    end
                end

                S_TRANSFER: begin
                    clk_cnt <= clk_cnt + 1'b1;
                    
                    if (clk_cnt == 40) begin
                        sclk    <= 1'b0;      // Clock low
                        dio_out <= data_q[0]; // Geser bit LSB lebih dulu
                    end else if (clk_cnt == 90) begin
                        sclk   <= 1'b1;       // Clock high
                        data_q <= {dio_in, data_q[7:1]}; // Sample input / shift
                    end else if (clk_cnt == 140) begin
                        clk_cnt <= 0;
                        bit_cnt <= bit_cnt + 1'b1;

                        if (bit_cnt == 3'd7) begin
                            data_out_q <= {dio_in, data_q[7:1]};
                            cur_state  <= S_IDLE;
                        end
                    end
                end

                default: cur_state <= S_IDLE;
            endcase
        end
    end

endmodule