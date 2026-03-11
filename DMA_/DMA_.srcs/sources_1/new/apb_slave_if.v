module apb_slave_if (
    input  wire        clk,    
    input  wire        rst_n, 
    
    // Tín hiệu từ Master (CPU)
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    
    // Phản hồi ra bus APB
    output reg         pready,
    output wire [31:0] prdata,   // Lấy thẳng từ reg_rdata của RegFile
    output reg         pslverr,
    
    // Tín hiệu từ logic nội bộ (RegFile)
    input  wire        wait_request,  // =1 khi Slave chưa sẵn sàng
    input  wire        error_trigger, // =1 khi phát hiện truy cập sai
    input  wire [31:0] reg_rdata,     // Dữ liệu đọc từ RegFile → trả về CPU

    // Giao diện nội bộ
    output wire        reg_write_en,
    output wire        reg_read_en
);

    // Trạng thái FSM [cite: 662-671]
    localparam IDLE   = 2'b00;
    localparam SETUP  = 2'b01;
    localparam ACCESS = 2'b10;

    reg [1:0] current_state, next_state;

    // 1. Cập nhật trạng thái (Sequential)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // 2. Tính toán trạng thái tiếp theo [cite: 672-674, 686-688]
    always @(*) begin
        case (current_state)
            IDLE:   next_state = psel ? SETUP : IDLE;
            SETUP:  next_state = ACCESS; 
            ACCESS: begin
                // Chỉ thoát khỏi ACCESS khi PREADY = 1 [cite: 688]
                if (pready)
                    next_state = psel ? SETUP : IDLE;
                else
                    next_state = ACCESS;
            end
            default: next_state = IDLE;
        endcase
    end

    // 3. Logic điều khiển PREADY và PSLVERR
    always @(*) begin
        pready  = 1'b0;
        pslverr = 1'b0;
        
        if (current_state == ACCESS) begin
            // Nếu không có yêu cầu đợi, ta kéo PREADY lên cao [cite: 363]
            pready  = !wait_request;
            
            // PSLVERR chỉ được coi là hợp lệ khi PREADY, PSEL, PENABLE đều HIGH 
            if (pready) begin
                pslverr = error_trigger;
            end
        end
    end

    // Chỉ thực hiện ghi/đọc khi hoàn tất giai đoạn ACCESS
    assign reg_write_en = (current_state == ACCESS) && pready && pwrite;
    assign reg_read_en  = (current_state == ACCESS) && pready && !pwrite;

    // Dữ liệu đọc: lấy thẳng từ RegFile, luôn hợp lệ khi reg_read_en
    assign prdata = reg_rdata;

endmodule