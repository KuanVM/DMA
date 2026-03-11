`timescale 1ns / 1ps
// Module: tb_simple_dma
// Mô phỏng DMA cơ bản: CPU cấu hình → DMA copy → kiểm tra dữ liệu

module tb_simple_dma();

    // --- 1. Khai báo tín hiệu ---
    logic clk;
    logic rst_n;

    // Bus Slave (CPU → DMA) — biến s_* để phân biệt trong TB
    logic [31:0] s_paddr;
    logic        s_psel;
    logic        s_penable;
    logic        s_pwrite;
    logic [31:0] s_pwdata;
    logic        s_pready;
    logic [31:0] s_prdata;
    logic        s_pslverr;

    // Bus Master (DMA → RAM) — KHÔNG có m_pslverr trong apb_dma_top
    logic [31:0] m_paddr;
    logic        m_psel;
    logic        m_penable;
    logic        m_pwrite;
    logic [31:0] m_pwdata;
    logic        m_pready;
    logic [31:0] m_prdata;

    // --- 2. Clock & Reset ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    initial begin
        rst_n = 0;
        #25 rst_n = 1;
    end

    // --- 3. Instantiate DUT ---
    // FIX 1: apb_dma_top slave ports không có tiền tố s_
    //         → .paddr(s_paddr), .psel(s_psel), ...
    // FIX 2: apb_dma_top KHÔNG có port m_pslverr → xóa
    apb_dma_top dut (
        .clk      (clk),      .rst_n    (rst_n),
        // Slave side
        .paddr    (s_paddr),  .psel     (s_psel),    .penable  (s_penable),
        .pwrite   (s_pwrite), .pwdata   (s_pwdata),
        .prdata   (s_prdata), .pready   (s_pready),  .pslverr  (s_pslverr),
        // Master side
        .m_paddr  (m_paddr),  .m_psel   (m_psel),    .m_penable(m_penable),
        .m_pwrite (m_pwrite), .m_pwdata (m_pwdata),
        .m_pready (m_pready), .m_prdata (m_prdata)
    );

    // --- 4. Instantiate Memory Model ---
    // FIX 3: memory_model port names là clk/rst_n (không phải pclk/presetn)
    // FIX 4: memory_model port names có tiền tố m_ (m_paddr, m_psel, ...)
    memory_model ram (
        .clk      (clk),
        .rst_n    (rst_n),
        .m_paddr  (m_paddr),  .m_psel   (m_psel),    .m_penable(m_penable),
        .m_pwrite (m_pwrite), .m_pwdata (m_pwdata),
        .m_pready (m_pready), .m_prdata (m_prdata),
        .m_pslverr()          // Float — TB không dùng
    );

    // --- 5. Task ghi APB (CPU write) ---
    task automatic cpu_write(input [31:0] addr, input [31:0] data);
        @(posedge clk); #1;
        s_paddr   <= addr; s_pwrite  <= 1;
        s_psel    <= 1;    s_penable <= 0;
        s_pwdata  <= data;

        @(posedge clk); #1;   // SETUP → ACCESS
        s_penable <= 1;

        wait(s_pready);       // Đợi slave assert pready (combinational)

        // QUAN TRỌNG: Giữ thêm 1 posedge để reg_file kịp latch write
        // Lý do: pready là combinational, xuất hiện trong delta cycle sau posedge.
        // Tại posedge đó, dma_reg_file sequential block thấy state=SETUP (chưa ACCESS)
        // → reg_write_en=0 → dữ liệu không được ghi.
        // Phải chờ đến posedge KẾ TIẾP (khi current_state đã ổn định = ACCESS)
        // thì reg_write_en=1 và dữ liệu mới được latch đúng.
        @(posedge clk); #1;
        s_psel    <= 0;
        s_penable <= 0;
        s_pwrite  <= 0;
    endtask

    // --- 6. Kịch bản mô phỏng ---
    initial begin
        s_psel = 0; s_penable = 0;
        s_pwrite = 0; s_paddr = 0; s_pwdata = 0;

        @(posedge rst_n);
        #20;

        $display("STEP 1: Chèn dữ liệu mẫu vào RAM nguồn (Backdoor)");
        // FIX 6: Tên array nội bộ là 'ram' không phải 'mem'
        //        memory_model.sv: logic [31:0] ram [0:RAM_SIZE-1]
        ram.ram[32'h1000 >> 2] = 32'hDEADBEEF;
        ram.ram[32'h1004 >> 2] = 32'hCAFEBABE;
        ram.ram[32'h1008 >> 2] = 32'h12345678;
        ram.ram[32'h100C >> 2] = 32'h87654321;

        $display("STEP 2: CPU cấu hình DMA");
        cpu_write(32'h00, 32'h0000_1000); // SRC = 0x1000
        // FIX 7: DST 0x2000>>2 = index 2048 = OUT OF RANGE (RAM_SIZE=2048, max=2047)
        //         Dùng 0x1800 (index 1536..1539, an toàn)
        cpu_write(32'h04, 32'h0000_1800); // DST = 0x1800
        cpu_write(32'h08, 32'h0000_0004); // LEN = 4 words
        cpu_write(32'h0C, 32'h0000_0001); // START = 1

        $display("STEP 3: Đợi DMA hoàn thành");
        wait(dut.dma_done);               // Hierarchical ref — hợp lệ trong simulation
        $display("DMA DONE detected!");

        $display("STEP 4: Kiểm tra dữ liệu tại vùng đích (0x1800)");
        if (ram.ram[32'h1800 >> 2] === 32'hDEADBEEF &&
            ram.ram[32'h1804 >> 2] === 32'hCAFEBABE &&
            ram.ram[32'h1808 >> 2] === 32'h12345678 &&
            ram.ram[32'h180C >> 2] === 32'h87654321) begin
            $display("===> SUCCESS: Dữ liệu copy chính xác!");
        end else begin
            $display("===> ERROR: Dữ liệu sai lệch!");
            $display("  [1800] = 0x%08X (expect 0xDEADBEEF)", ram.ram[32'h1800>>2]);
            $display("  [1804] = 0x%08X (expect 0xCAFEBABE)", ram.ram[32'h1804>>2]);
            $display("  [1808] = 0x%08X (expect 0x12345678)", ram.ram[32'h1808>>2]);
            $display("  [180C] = 0x%08X (expect 0x87654321)", ram.ram[32'h180C>>2]);
        end

        #100;
        $finish;
    end

endmodule