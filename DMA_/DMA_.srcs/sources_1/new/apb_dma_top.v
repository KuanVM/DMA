module apb_dma_top (
    input  wire        clk,
    input  wire        rst_n,

    // ──────────────────────────────────────────────────────
    // Giao diện APB Slave (phía CPU kết nối vào)
    // ──────────────────────────────────────────────────────
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,
    input  wire        pwrite,
    input  wire        psel,
    input  wire        penable,
    output wire [31:0] prdata,   // Dữ liệu đọc trả về CPU
    output wire        pready,   // Slave sẵn sàng
    output wire        pslverr,  // Báo lỗi bus

    // ──────────────────────────────────────────────────────
    // Giao diện APB Master (phía RAM/Peripheral)
    // ──────────────────────────────────────────────────────
    output wire [31:0] m_paddr,
    output wire [31:0] m_pwdata,
    output wire        m_pwrite,
    output wire        m_psel,
    output wire        m_penable,
    input  wire [31:0] m_prdata,
    input  wire        m_pready
);

    // ──────────────────────────────────────────────────────
    // Tín hiệu nội bộ: apb_slave_if <-> dma_reg_file
    // ──────────────────────────────────────────────────────
    wire        reg_write_en;
    wire        reg_read_en;
    wire [31:0] reg_rdata;     // Dữ liệu đọc từ RegFile → Slave IF → CPU
    wire        wait_request;  // RegFile yêu cầu giãn chu kỳ
    wire        error_trigger; // RegFile báo lỗi địa chỉ

    // ──────────────────────────────────────────────────────
    // Tín hiệu nội bộ: dma_reg_file <-> dma_master_engine
    // ──────────────────────────────────────────────────────
    wire [31:0] src_addr;
    wire [31:0] dst_addr;
    wire [31:0] xfer_len;
    wire        dma_start;
    wire        dma_busy;
    wire        dma_done;

    // ══════════════════════════════════════════════════════
    // Module 1: APB Slave Interface
    //   - Xử lý FSM APB (IDLE → SETUP → ACCESS)
    //   - Sinh pready, pslverr đúng timing chuẩn APB3
    //   - Sinh reg_write_en / reg_read_en cho RegFile
    // ══════════════════════════════════════════════════════
    apb_slave_if u_slave (
        .clk         (clk),
        .rst_n      (rst_n),
        // APB bus từ CPU
        .paddr        (paddr),
        .psel         (psel),
        .penable      (penable),
        .pwrite       (pwrite),
        .pwdata       (pwdata),
        // Phản hồi về CPU
        .pready       (pready),
        .prdata       (prdata),   // Lấy dữ liệu từ reg_rdata (qua port mới)
        .pslverr      (pslverr),
        // Từ RegFile
        .wait_request (wait_request),
        .error_trigger(error_trigger),
        .reg_rdata    (reg_rdata),
        // Đến RegFile
        .reg_write_en (reg_write_en),
        .reg_read_en  (reg_read_en)
    );

    // ══════════════════════════════════════════════════════
    // Module 2: DMA Register File
    //   - Lưu cấu hình: SRC_ADDR, DST_ADDR, LEN, CTRL, STAT
    //   - Sinh dma_start pulse khi CPU ghi bit START
    //   - Báo wait_request / error_trigger cho Slave IF
    // ══════════════════════════════════════════════════════
    dma_reg_file u_regfile (
        .clk          (clk),
        .rst_n        (rst_n),
        // Từ Slave IF
        .reg_write_en (reg_write_en),
        .reg_read_en  (reg_read_en),
        .reg_addr     (paddr),       // 32-bit; RegFile tự decode [7:0]
        .reg_wdata    (pwdata),
        // Đến Slave IF
        .reg_rdata    (reg_rdata),
        .wait_request (wait_request),
        .error_trigger(error_trigger),
        // Đến Master Engine
        .out_src_addr (src_addr),
        .out_dst_addr (dst_addr),
        .out_len      (xfer_len),
        .dma_start    (dma_start),
        // Từ Master Engine
        .dma_busy     (dma_busy),
        .dma_done     (dma_done)
    );

    // ══════════════════════════════════════════════════════
    // Module 3: DMA Master Engine
    //   - Thực hiện truyền dữ liệu: đọc từ src, ghi vào dst
    //   - FSM: IDLE→RD_SETUP→RD_ACCESS→WR_SETUP→WR_ACCESS→UPDATE→DONE
    //   - Hoạt động như APB Master trên bus m_p*
    // ══════════════════════════════════════════════════════
    dma_master_engine u_engine (
        .clk          (clk),
        .rst_n        (rst_n),
        // Từ RegFile
        .dma_start    (dma_start),
        .cfg_src_addr (src_addr),
        .cfg_dst_addr (dst_addr),
        .cfg_len      (xfer_len),
        // Đến RegFile
        .dma_busy     (dma_busy),
        .dma_done     (dma_done),
        // APB Master bus ra ngoài
        .m_paddr      (m_paddr),
        .m_psel       (m_psel),
        .m_penable    (m_penable),
        .m_pwrite     (m_pwrite),
        .m_pwdata     (m_pwdata),
        .m_prdata     (m_prdata),
        .m_pready     (m_pready)
    );

endmodule