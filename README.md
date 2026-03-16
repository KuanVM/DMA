# APB DMA Controller — Verilog Implementation

Thiết kế **APB DMA Controller** theo chuẩn **APB3 (AMBA)**, được mô tả bằng Verilog RTL và mô phỏng bằng Vivado XSim. DMA thực hiện copy bộ nhớ từ vùng nguồn sang vùng đích thông qua bus APB.

## Kiến trúc

```
          CPU (APB Master)
               │ paddr/psel/penable/pwrite/pwdata
               ▼
       ┌────────────────┐
       │  apb_slave_if  │  ← FSM APB3: IDLE→SETUP→ACCESS
       └───────┬────────┘     reg_write_en / reg_read_en
               │
       ┌───────▼────────┐
       │  dma_reg_file  │  ← Config + Status registers
       └───────┬────────┘     dma_start / busy / done
               │
       ┌───────▼────────────┐
       │ dma_master_engine  │  ← APB Master FSM: 7 states
       └───────┬────────────┘
               │ m_paddr/m_psel/m_penable/...
               ▼
          RAM / Peripheral
```

## Thành phần RTL

| File | Module | Chức năng |
|---|---|---|
| `apb_slave_if.v` | `apb_slave_if` | APB Slave interface, FSM 3-state |
| `dma_reg_file.v` | `dma_reg_file` | Register file: SRC/DST/LEN/CTRL/STAT |
| `dma_master_engine.v` | `dma_master_engine` | DMA engine, APB Master, FSM 7-state |
| `apb_dma_top.v` | `apb_dma_top` | Top-level wrapper |

## Register Map

| Address | Name | Mô tả |
|---|---|---|
| `0x00` | `SRC_ADDR` | Địa chỉ nguồn |
| `0x04` | `DST_ADDR` | Địa chỉ đích |
| `0x08` | `LEN` | Số word cần copy |
| `0x0C` | `CTRL` | `[0]`=START, `[1]`=IE |
| `0x10` | `STAT` | `[0]`=BUSY (RO), `[1]`=DONE (W1C) |

## DMA Master FSM

```
IDLE →(dma_start)→ RD_SETUP → RD_ACCESS →(pready)→ WR_SETUP → WR_ACCESS
                                                                      ↓
                                              DONE ←(len≤1)← UPDATE →(len>1, +4)→ RD_SETUP
```

## Simulation

### Môi trường
- **Tool**: Vivado 2024.x XSim (Behavioral Simulation)
- **Testbench**: `tb_simple_dma..sv`
- **Memory model**: Ideal (pready=1 ngay ACCESS phase)

### Chạy simulation
1. Mở Vivado project `DMA_/DMA_.xpr`
2. Set `tb_simple_dma` làm **Simulation Top**
3. **Flow Navigator → Run Simulation → Run Behavioral Simulation**
4. Xem kết quả trong Tcl Console

### Kết quả

```
STEP 1: Chèn dữ liệu mẫu vào RAM nguồn (Backdoor)
STEP 2: CPU cấu hình DMA
STEP 3: Đợi DMA hoàn thành
DMA DONE detected!
STEP 4: Kiểm tra dữ liệu tại vùng đích (0x1800)
===> SUCCESS: Dữ liệu copy chính xác!
$finish called at time : 715 ns
```

## Cấu trúc thư mục

```
DMA/
├── .gitignore
├── README.md
├── DMA.tcl                          # Vivado synthesis script
├── docs/
│   └── project_report.md            # Báo cáo thiết kế
├── DMA_/
│   └── DMA_.srcs/
│       ├── sources_1/new/           # RTL sources
│       │   ├── apb_dma_top.v
│       │   ├── apb_slave_if.v
│       │   ├── dma_master_engine.v
│       │   └── dma_reg_file.v
│       └── sim_1/new/               # Simulation files
│           ├── tb_simple_dma..sv
│           └── memory_model.sv
└── DMA_Verification/
    └── tb_top.sv                    # Alternative testbench
```

## Tác giả
Vũ Minh Quân
 - APB DMA Controller 

