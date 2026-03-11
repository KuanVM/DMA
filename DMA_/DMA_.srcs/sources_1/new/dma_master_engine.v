module dma_master_engine (
    input  wire        clk,
    input  wire        rst_n,
    
    // Giao diện nội bộ với Reg File
    input  wire        dma_start,
    input  wire [31:0] cfg_src_addr,
    input  wire [31:0] cfg_dst_addr,
    input  wire [31:0] cfg_len,
    output reg         dma_busy,
    output reg         dma_done,
    
    // Giao diện Master APB3 (Nối với RAM/Peripheral)
    output reg  [31:0] m_paddr,
    output reg         m_psel,
    output reg         m_penable,
    output reg         m_pwrite,
    output reg  [31:0] m_pwdata,
    input  wire [31:0] m_prdata,
    input  wire        m_pready
);

    // Định nghĩa các trạng thái
    localparam IDLE      = 3'd0;
    localparam RD_SETUP  = 3'd1;
    localparam RD_ACCESS = 3'd2;
    localparam WR_SETUP  = 3'd3;
    localparam WR_ACCESS = 3'd4;
    localparam UPDATE    = 3'd5;
    localparam DONE      = 3'd6;

    reg [2:0]  state;
    reg [31:0] curr_src, curr_dst, curr_len;
    reg [31:0] data_buffer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            dma_busy  <= 1'b0;
            dma_done  <= 1'b0;
            m_psel    <= 1'b0;
            m_penable <= 1'b0;
            m_paddr   <= 32'h0;   // Fix X trong waveform
            m_pwrite  <= 1'b0;
            m_pwdata  <= 32'h0;
        end else begin
            case (state)
                IDLE: begin
                    dma_done <= 1'b0;
                    if (dma_start) begin
                        state     <= RD_SETUP;
                        curr_src  <= cfg_src_addr;
                        curr_dst  <= cfg_dst_addr;
                        curr_len  <= cfg_len;
                        dma_busy  <= 1'b1;
                    end
                end

                RD_SETUP: begin
                    m_paddr   <= curr_src;
                    m_pwrite  <= 1'b0; // Đọc
                    m_psel    <= 1'b1;
                    m_penable <= 1'b0;
                    state     <= RD_ACCESS;
                end

                RD_ACCESS: begin
                    m_penable <= 1'b1;
                    if (m_pready) begin // Đợi bộ nhớ trả dữ liệu 
                        data_buffer <= m_prdata;
                        m_psel      <= 1'b0;
                        m_penable   <= 1'b0;
                        state       <= WR_SETUP;
                    end
                end

                WR_SETUP: begin
                    m_paddr   <= curr_dst;
                    m_pwdata  <= data_buffer;
                    m_pwrite  <= 1'b1; // Ghi
                    m_psel    <= 1'b1;
                    m_penable <= 1'b0;
                    state     <= WR_ACCESS;
                end

                WR_ACCESS: begin
                    m_penable <= 1'b1;
                    if (m_pready) begin // Đợi bộ nhớ nhận dữ liệu 
                        m_psel    <= 1'b0;
                        m_penable <= 1'b0;
                        state     <= UPDATE;
                    end
                end

                UPDATE: begin
                    if (curr_len <= 1) begin
                        state <= DONE;
                    end else begin
                        curr_src <= curr_src + 4; // Tăng địa chỉ word 
                        curr_dst <= curr_dst + 4;
                        curr_len <= curr_len - 1;
                        state    <= RD_SETUP;
                    end
                end

                DONE: begin
                    dma_busy <= 1'b0;
                    dma_done <= 1'b1;
                    state    <= IDLE;
                end
            endcase
        end
    end
endmodule
