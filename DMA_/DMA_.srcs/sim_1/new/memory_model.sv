`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/05/2026 12:34:59 PM
// Design Name: 
// Module Name: memory_model
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module memory_model(
    input logic clk,
    input logic rst_n,

    // APB Master Interface
    input logic [31:0] m_paddr,
    input logic [31:0] m_pwdata,
    input logic        m_pwrite,
    input logic        m_psel,
    input logic        m_penable,
    output logic [31:0] m_prdata,
    output logic        m_pready,
    output logic        m_pslverr
    );

// 1. Khai báo bộ nhớ (RAM) 8KB (2048 words x 32 bits)
    localparam RAM_SIZE = 2048;
    logic [31:0] ram [0:RAM_SIZE-1];

    // Đếm số chu kì chờ (Wait States)
    int wait_counter;

    // ─────────────────────────────────────────────────────
    // 2. Logic tạo wait states ngẫu nhiên (0..3 chu kỳ)
    //    SETUP  (psel=1, penable=0): lấy số random, reset pready
    //    ACCESS (psel=1, penable=1): đếm lùi, kéo pready khi xong
    //    IDLE   (psel=0)           : xóa pready
    // ─────────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_pready     <= 1'b0;
            wait_counter <= 0;
        end else begin
            if (m_psel && !m_penable) begin
                // SETUP: sample số wait cycle
                wait_counter <= $urandom_range(0, 3);
                m_pready     <= 1'b0;          // Chưa ready ở setup phase
            end else if (m_psel && m_penable) begin
                // ACCESS: đếm lùi
                if (wait_counter > 0) begin
                    wait_counter <= wait_counter - 1;
                    // Kéo pready lên trước 1 cycle để kịp timing
                    m_pready <= (wait_counter == 1) ? 1'b1 : 1'b0;
                end else begin
                    m_pready <= 1'b1;          // wait_counter=0: ready ngay
                end
            end else begin
                // IDLE
                m_pready     <= 1'b0;
                wait_counter <= 0;
            end
        end
    end

    // ─────────────────────────────────────────────────────
    // 3. Logic ghi data (write)
    // ─────────────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (m_psel && m_penable && m_pready && m_pwrite) begin
            ram[m_paddr[12:2]] <= m_pwdata;    // byte addr → word index
        end
    end

    // ─────────────────────────────────────────────────────
    // 4. Logic đọc data (read) — combinational
    //    Dùng blocking assignment (=) trong always_comb
    // ─────────────────────────────────────────────────────
    always_comb begin
        if (m_psel && !m_pwrite)
            m_prdata = ram[m_paddr[12:2]];     // = thay vì <=
        else
            m_prdata = 32'h0;
    end

    // Không báo lỗi truy cập ở memory model
    assign m_pslverr = 1'b0;
    
endmodule
