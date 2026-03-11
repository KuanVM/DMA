`timescale 1ns / 1ps
//=============================================================
// Testbench: tb_top
// DUT: apb_dma_top
// Điều kiện: Lý tưởng — Memory luôn pready=1 ngay lập tức
// Test cases:
//   TC1 — Đọc thanh ghi sau reset (config rỗng)
//   TC2 — Cấu hình SRC/DST/LEN, kích START, chờ DONE
//   TC3 — Kiểm tra dữ liệu đã được copy đúng
//   TC4 — W1C: xóa bit DONE bằng cách ghi 1
//=============================================================

module tb_top;

    // ─────────────────────────────────────────────
    // Tham số & Clock
    // ─────────────────────────────────────────────
    localparam CLK_PERIOD = 10; // 100 MHz
    localparam SRC_BASE   = 32'h0000_0000;
    localparam DST_BASE   = 32'h0000_0100; // Cách src 256 bytes
    localparam XFER_LEN   = 4;             // Copy 4 words (16 bytes)

    logic clk, rst_n;

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ─────────────────────────────────────────────
    // Tín hiệu APB Slave (CPU → DUT)
    // ─────────────────────────────────────────────
    logic [31:0] paddr;
    logic [31:0] pwdata;
    logic        pwrite;
    logic        psel;
    logic        penable;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // ─────────────────────────────────────────────
    // Tín hiệu APB Master (DUT → Memory)
    // ─────────────────────────────────────────────
    logic [31:0] m_paddr;
    logic [31:0] m_pwdata;
    logic        m_pwrite;
    logic        m_psel;
    logic        m_penable;
    logic [31:0] m_prdata;
    logic        m_pready;

    // ─────────────────────────────────────────────
    // DUT: apb_dma_top
    // ─────────────────────────────────────────────
    apb_dma_top dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .paddr    (paddr),
        .pwdata   (pwdata),
        .pwrite   (pwrite),
        .psel     (psel),
        .penable  (penable),
        .prdata   (prdata),
        .pready   (pready),
        .pslverr  (pslverr),
        .m_paddr  (m_paddr),
        .m_pwdata (m_pwdata),
        .m_pwrite (m_pwrite),
        .m_psel   (m_psel),
        .m_penable(m_penable),
        .m_prdata (m_prdata),
        .m_pready (m_pready)
    );

    // ─────────────────────────────────────────────
    // Memory Model lý tưởng: pready=1 ngay lập tức
    // RAM 512 words x 32-bit (địa chỉ byte 0x000..0x7FF)
    // ─────────────────────────────────────────────
    logic [31:0] ram [0:511];

    assign m_pready = m_psel & m_penable; // Ideal: sẵn sàng ngay ACCESS phase

    always_ff @(posedge clk) begin
        if (m_psel && m_penable && m_pready && m_pwrite)
            ram[m_paddr[10:2]] <= m_pwdata;            // Byte addr → word index
    end

    assign m_prdata = (m_psel && !m_pwrite)
                      ? ram[m_paddr[10:2]]
                      : 32'h0;

    // ─────────────────────────────────────────────
    // TASK: APB Write (1 transaction)
    // ─────────────────────────────────────────────
    task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk); #1;
        paddr   = addr;
        pwdata  = data;
        pwrite  = 1'b1;
        psel    = 1'b1;
        penable = 1'b0;

        @(posedge clk); #1;       // SETUP → ACCESS
        penable = 1'b1;

        // Đợi slave assert pready
        do @(posedge clk); while (!pready);
        #1;

        // Deassert bus
        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;
    endtask

    // ─────────────────────────────────────────────
    // TASK: APB Read (1 transaction)
    // ─────────────────────────────────────────────
    task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk); #1;
        paddr   = addr;
        pwrite  = 1'b0;
        psel    = 1'b1;
        penable = 1'b0;

        @(posedge clk); #1;       // SETUP → ACCESS
        penable = 1'b1;

        do @(posedge clk); while (!pready);
        #1;
        data    = prdata;

        psel    = 1'b0;
        penable = 1'b0;
    endtask

    // ─────────────────────────────────────────────
    // TASK: Chờ DMA hoàn thành (polling STAT[1]=DONE)
    // ─────────────────────────────────────────────
    task automatic wait_dma_done(input int timeout_cycles);
        logic [31:0] stat;
        int cnt = 0;
        do begin
            apb_read(32'h10, stat);
            cnt++;
            if (cnt > timeout_cycles) begin
                $display("[ERROR] Timeout: DMA không hoàn thành sau %0d cycles!", timeout_cycles);
                $finish;
            end
        end while (!stat[1]); // bit DONE
        $display("[INFO]  DMA DONE sau ~%0d check cycles.", cnt);
    endtask

    // ─────────────────────────────────────────────
    // Biến tạm & counters
    // ─────────────────────────────────────────────
    logic [31:0] rd_data;
    int          err_count = 0;

    // ─────────────────────────────────────────────
    // MAIN TEST
    // ─────────────────────────────────────────────
    initial begin
        // Khởi tạo bus
        paddr   = 0; pwdata  = 0;
        pwrite  = 0; psel    = 0; penable = 0;
        rst_n   = 0;

        // Khởi tạo RAM nguồn với dữ liệu cố định
        for (int i = 0; i < 512; i++)
            ram[i] = 32'hA000_0000 + i;

        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("==============================================");
        $display(" TC1: Đọc thanh ghi sau reset");
        $display("==============================================");
        apb_read(32'h00, rd_data); check("SRC_ADDR reset", rd_data, 32'h0);
        apb_read(32'h04, rd_data); check("DST_ADDR reset", rd_data, 32'h0);
        apb_read(32'h08, rd_data); check("LEN reset",      rd_data, 32'h0);
        apb_read(32'h0C, rd_data); check("CTRL reset",     rd_data, 32'h0);
        apb_read(32'h10, rd_data); check("STAT reset",     rd_data, 32'h0);

        $display("==============================================");
        $display(" TC2: Cấu hình DMA và kích START");
        $display("==============================================");
        apb_write(32'h00, SRC_BASE);          // SRC_ADDR
        apb_write(32'h04, DST_BASE);          // DST_ADDR
        apb_write(32'h08, XFER_LEN);          // LEN = 4 words
        apb_write(32'h0C, 32'h1);             // CTRL[0]=START

        // BUSY nên lên ngay
        apb_read(32'h10, rd_data);
        if (rd_data[0]) $display("[PASS]  BUSY = 1 ngay sau START");
        else begin $display("[WARN]  BUSY chưa lên (có thể DMA đã quá nhanh)"); end

        // Chờ hoàn thành
        wait_dma_done(1000);

        // BUSY phải về 0, DONE phải lên 1
        apb_read(32'h10, rd_data);
        check("STAT.DONE=1 sau khi xong", rd_data[1], 1'b1);
        check("STAT.BUSY=0 sau khi xong", rd_data[0], 1'b0);

        $display("==============================================");
        $display(" TC3: Kiểm tra dữ liệu đã copy đúng");
        $display("==============================================");
        for (int i = 0; i < XFER_LEN; i++) begin
            logic [31:0] src_word, dst_word;
            src_word = ram[SRC_BASE[10:2] + i];
            dst_word = ram[DST_BASE[10:2] + i];
            if (src_word === dst_word)
                $display("[PASS]  Word[%0d]: 0x%08X → OK", i, dst_word);
            else begin
                $display("[FAIL]  Word[%0d]: Expected 0x%08X, Got 0x%08X",
                          i, src_word, dst_word);
                err_count++;
            end
        end

        $display("==============================================");
        $display(" TC4: W1C — Xóa bit DONE");
        $display("==============================================");
        apb_write(32'h10, 32'h2);             // Ghi 1 vào bit[1] DONE để xóa
        apb_read (32'h10, rd_data);
        check("STAT.DONE=0 sau W1C", rd_data[1], 1'b0);

        // ── Kết quả tổng hợp ──
        $display("==============================================");
        if (err_count == 0)
            $display(" ALL TESTS PASSED!");
        else
            $display(" %0d TEST(S) FAILED!", err_count);
        $display("==============================================");

        repeat(5) @(posedge clk);
        $finish;
    end

    // ─────────────────────────────────────────────
    // HELPER: check giá trị và in pass/fail
    // ─────────────────────────────────────────────
    task automatic check(input string name,
                          input logic [31:0] actual,
                          input logic [31:0] expected);
        if (actual === expected)
            $display("[PASS]  %s = 0x%08X", name, actual);
        else begin
            $display("[FAIL]  %s: Expected 0x%08X, Got 0x%08X",
                      name, expected, actual);
            err_count++;
        end
    endtask

    // Waveform dump (cho Vivado / ModelSim)
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
