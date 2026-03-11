module dma_reg_file (
    input  wire        clk,
    input  wire        rst_n,
    
    // Kết nối với apb_slave_if 
    input  wire        reg_write_en,
    input  wire        reg_read_en,
    input  wire [31:0] reg_addr,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,
    output reg         wait_request,  // Báo Slave kéo PREADY=0
    output reg         error_trigger, // Báo Slave kéo PSLVERR=1
    
    // Kết nối với dma_master_engine
    output reg  [31:0] out_src_addr,
    output reg  [31:0] out_dst_addr,
    output reg  [31:0] out_len,
    output wire        dma_start,
    input  wire        dma_busy,
    input  wire        dma_done
);

    reg [1:0] ctrl_reg; // [1]: IE, [0]: START
    reg [1:0] stat_reg; // [1]: DONE, [0]: BUSY
    reg       start_pulse;

    // --- 1. LOGIC PHÁT HIỆN LỖI (ERROR DETECTION) ---
    always @(*) begin
        error_trigger = 1'b0;
        if (reg_write_en || reg_read_en) begin
            // Lỗi 1: Truy cập ngoài vùng địa chỉ 0x00 - 0x10
            if (reg_addr[7:5] != 3'b000 || reg_addr[4:0] > 5'h10)
                error_trigger = 1'b1;
            // Lỗi 2: Cố tình ghi vào vùng không cho phép (ví dụ bit BUSY của STAT)
            if (reg_write_en && (reg_addr[7:0] == 8'h10) && reg_wdata[0])
                error_trigger = 1'b1;
        end
    end

    // --- 2. LOGIC BẮT ĐỢI (WAIT REQUEST) ---
    always @(*) begin
        wait_request = 1'b0;
        // Nếu DMA đang bận mà CPU muốn ghi vào các thanh ghi cấu hình chính
        if (dma_busy && reg_write_en) begin
            if (reg_addr[7:0] == 8'h00 || reg_addr[7:0] == 8'h04 || reg_addr[7:0] == 8'h08)
                wait_request = 1'b1;
        end
    end

    // --- 3 & 4. GHI THANH GHI + CẬP NHẬT TRẠNG THÁI (một always block duy nhất)
    //   Lý do gộp: stat_reg[1] được drive bởi cả ghi W1C lẫn dma_done
    //   → tách thành 2 block sẽ gây "multi-driven net" lỗi synthesis
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_src_addr <= 32'h0;
            out_dst_addr <= 32'h0;
            out_len      <= 32'h0;
            ctrl_reg     <= 2'h0;
            stat_reg     <= 2'h0;
            start_pulse  <= 1'b0;
        end else begin
            start_pulse  <= 1'b0;

            // --- Cập nhật BUSY từ engine (luôn phản ánh thực tế) ---
            stat_reg[0] <= dma_busy;

            // --- Set DONE khi engine báo xong ---
            if (dma_done) stat_reg[1] <= 1'b1;

            // --- Xử lý ghi từ CPU (ưu tiên cao hơn dma_done) ---
            if (reg_write_en && !wait_request && !error_trigger) begin
                case (reg_addr[7:0])
                    8'h00: out_src_addr <= reg_wdata;
                    8'h04: out_dst_addr <= reg_wdata;
                    8'h08: out_len      <= reg_wdata;
                    8'h0C: begin
                        ctrl_reg <= reg_wdata[1:0];
                        if (reg_wdata[0]) start_pulse <= 1'b1;
                    end
                    // W1C: CPU ghi 1 vào bit DONE để xóa nó
                    8'h10: if (reg_wdata[1]) stat_reg[1] <= 1'b0;
                endcase
            end
        end
    end

    assign dma_start = start_pulse;

    // --- 5. LOGIC ĐỌC THANH GHI ---
    always @(*) begin
        case (reg_addr[7:0])
            8'h00:   reg_rdata = out_src_addr;
            8'h04:   reg_rdata = out_dst_addr;
            8'h08:   reg_rdata = out_len;
            8'h0C:   reg_rdata = {30'h0, ctrl_reg};
            8'h10:   reg_rdata = {30'h0, stat_reg};
            default: reg_rdata = 32'hDEADBEEF; // Trả về mã lỗi nhận diện
        endcase
    end

endmodule