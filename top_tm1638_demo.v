module top_tm1638_demo #(
    parameter TICK_CYCLES = 12_000_000,  // 1 detik pada 12 MHz
    parameter INVERT_SW   = 1'b1         // 1 = switch ON membaca 0 di pin (pull-up)
) (
    input  wire       clk,       // Clock 12 MHz dari iCESugar (Pin 35)
    input  wire [2:0] sw,        // Switch input
    output wire       tm_clk,    // SCLK ke TM1638
    output wire       tm_cs,     // STB / CS ke TM1638
    inout  wire       tm_dio,    // DIO (Data I/O) ke TM1638
    output wire       heartbeat  // Indikator LED onboard (Pin 41)
);

    // =========================================================================
    // 1. Heartbeat LED & Scroll Timer
    // =========================================================================
    reg [23:0] heartbeat_cnt = 0;
    always @(posedge clk) begin
        heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign heartbeat = heartbeat_cnt[23]; // Indikator clock FPGA aktif

    // Mode dari switch (sw[1:0], ON = 1 setelah INVERT_SW):
    //   2'b01 = geser ke kiri tiap 1 detik
    //   2'b10 = geser ke kanan tiap 1 detik
    //   2'b00 = bolak-balik kiri-kanan tiap 1 detik
    //   2'b11 = tidak ditentukan di soal -> diam
    reg [1:0] sw_s1 = 2'b00, sw_s2 = 2'b00;
    always @(posedge clk) begin
        sw_s1 <= sw[1:0];
        sw_s2 <= sw_s1;                      // 2 flip-flop: sinkronisasi input asinkron
    end
    wire [1:0] mode = sw_s2 ^ {2{INVERT_SW}};

    reg [23:0] scroll_timer = 0;
    reg [4:0]  scroll_offset = 0;            // 0..19 (teks 15 karakter + 5 spasi)
    reg        pp_dir = 1'b0;                // mode bolak-balik: 0 = kiri, 1 = kanan
    wire       tick = (scroll_timer == TICK_CYCLES - 1);

    always @(posedge clk) begin
        if (tick) begin
            scroll_timer <= 0;
            case (mode)
                2'b01: scroll_offset <= (scroll_offset >= 5'd19) ? 5'd0  : scroll_offset + 1'b1;
                2'b10: scroll_offset <= (scroll_offset == 5'd0)  ? 5'd19 : scroll_offset - 1'b1;
                2'b00: 
                begin
                    if (!pp_dir) begin
                        if (scroll_offset >= 5'd12) begin
                            pp_dir        <= 1'b1;
                            scroll_offset <= scroll_offset - 1'b1;
                        end else
                            scroll_offset <= scroll_offset + 1'b1;
                    end else begin
                        if (scroll_offset == 5'd0) begin
                            pp_dir        <= 1'b0;
                            scroll_offset <= 5'd1;
                        end else
                            scroll_offset <= scroll_offset - 1'b1;
                    end
                end
                default: ;                   // 2'b11: diam
            endcase
        end else begin
            scroll_timer <= scroll_timer + 1'b1;
        end
    end

    // =========================================================================
    // 2. Decoder 7-Segment NIM ("503627-te-55045     ")
    // =========================================================================
    function [7:0] decode_7seg;
        input [4:0] char_code;
        begin
            case (char_code)
                5'd0:  decode_7seg = 8'h6D; // 5
                5'd1:  decode_7seg = 8'h3F; // 0
                5'd2:  decode_7seg = 8'h4F; // 3
                5'd3:  decode_7seg = 8'h7D; // 6
                5'd4:  decode_7seg = 8'h5B; // 2
                5'd5:  decode_7seg = 8'h07; // 7
                5'd6:  decode_7seg = 8'h40; // - (dash / garis tengah saja)
                5'd7:  decode_7seg = 8'h78; // t
                5'd8:  decode_7seg = 8'h7B; // e
                5'd9:  decode_7seg = 8'h40; // - (dash / garis tengah saja)
                5'd10: decode_7seg = 8'h6D; // 5
                5'd11: decode_7seg = 8'h6D; // 5 (Diperbaiki ke hex code 8'h6D)
                5'd12: decode_7seg = 8'h3F; // 0
                5'd13: decode_7seg = 8'h66; // 4
                5'd14: decode_7seg = 8'h6D; // 5
                default: decode_7seg = 8'h00; // Spasi / Mati
            endcase
        end
    endfunction

    wire [63:0] seg_flat;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : MAP_DIGITS
            assign seg_flat[8*i +: 8] = decode_7seg((scroll_offset + i) % 20);
        end
    endgenerate

    reg        data_latch = 0;
    reg [7:0]  tx_data = 0;
    wire       busy, dio_in, dio_out;
    reg        stb_reg = 1;

    assign tm_dio = dio_out;
    assign dio_in = tm_dio;
    assign tm_cs  = stb_reg;

    tm1638 driver_inst (
        .clk(clk), .rst(1'b0),
        .data_latch(data_latch), .data(tx_data), .rw(1'b0),
        .busy(busy), .sclk(tm_clk),
        .dio_in(dio_in), .dio_out(dio_out)
    );

    reg [4:0] step = 0;
    reg [2:0] ph   = 0;
    reg [5:0] dly  = 0;

    wire [4:0] didx = step - 5'd2;
    wire [7:0] tx_next =
        (step == 0)  ? 8'h40 :
        (step == 1)  ? 8'hC0 :
        (step == 18) ? 8'h8F :
        (didx[0])    ? 8'h00 :
                       seg_flat[{didx[3:1], 3'b000} +: 8];

    wire frame_end = (step == 0) || (step == 17) || (step == 18);

    always @(posedge clk) begin
        data_latch <= 0;
        case (ph)
            0: begin
                if (step == 0 || step == 1 || step == 18) stb_reg <= 0;
                dly <= 0; ph <= 1;
            end
            1: begin
                dly <= dly + 1'b1;
                if (dly == 31) begin
                    tx_data    <= tx_next;
                    data_latch <= 1;
                    ph <= 2;
                end
            end
            2: if (busy)  ph <= 3;
            3: if (!busy) begin dly <= 0; ph <= 4; end
            4: begin
                dly <= dly + 1'b1;
                if (dly == 31) begin
                    if (frame_end) stb_reg <= 1;
                    step <= (step == 18) ? 5'd0 : step + 1'b1;
                    dly <= 0; ph <= 5;
                end
            end
            5: begin
                dly <= dly + 1'b1;
                if (dly == 31) ph <= 0;
            end
            default: ph <= 0;
        endcase
    end

endmodule