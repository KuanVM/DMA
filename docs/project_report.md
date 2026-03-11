# Báo cáo Thiết kế: APB DMA Controller

> Ngày: 11/03/2026 | Công cụ: Vivado XSim | Ngôn ngữ: Verilog / SystemVerilog

---

## 1. Tổng quan

### 1.1 Mục tiêu

Thiết kế một DMA (Direct Memory Access) Controller đơn giản theo chuẩn bus **APB3 (AMBA Peripheral Bus v3)**. DMA thực hiện chức năng copy dữ liệu từ vùng nhớ nguồn đến vùng nhớ đích mà không cần CPU can thiệp vào từng giao dịch.

### 1.2 Tính năng

- Hoạt động như **APB Slave** để CPU cấu hình
- Hoạt động như **APB Master** để truy cập bộ nhớ/peripheral
- Hỗ trợ **wait states** (PREADY deassert) từ phía bộ nhớ
- Báo lỗi địa chỉ qua **PSLVERR**
- **W1C** (Write-1-to-Clear) cho bit DONE của STAT register
- Ngăn CPU ghi config khi DMA đang bận (**wait_request**)

---

## 2. Kiến trúc hệ thống

```
          CPU (APB Master)
               │
    ┌──────────▼──────────┐
    │     apb_slave_if    │  APB3 FSM: IDLE → SETUP → ACCESS
    │                     │  Sinh: pready, pslverr, reg_write_en, reg_read_en
    └──────────┬──────────┘
               │ reg_write_en / reg_read_en / reg_rdata
    ┌──────────▼──────────┐
    │    dma_reg_file     │  Register bank 5 thanh ghi
    │                     │  Error detection, Wait request logic
    └──────────┬──────────┘
               │ dma_start / cfg_src / cfg_dst / cfg_len
    ┌──────────▼──────────┐
    │ dma_master_engine   │  APB Master FSM 7 trạng thái
    │                     │  Thực hiện copy word-by-word
    └──────────┬──────────┘
               │ m_paddr / m_psel / m_penable / m_pwrite / m_pwdata
               ▼
          RAM / Peripheral
```

---

## 3. Mô tả chi tiết từng module

### 3.1 `apb_slave_if` — APB Slave Interface

**FSM 3 trạng thái (chuẩn APB3):**

| State | Điều kiện vào | Hành động |
|---|---|---|
| `IDLE` | Mặc định | Chờ PSEL |
| `SETUP` | `psel=1` | Latch địa chỉ/hướng truyền |
| `ACCESS` | Từ SETUP | Assert `penable`, chờ slave `pready` |

**Tín hiệu quan trọng:**
- `pready = !wait_request` khi ở trạng thái ACCESS
- `pslverr = error_trigger` (chỉ hợp lệ khi pready=1)
- `reg_write_en = ACCESS && pready && pwrite`
- `reg_read_en = ACCESS && pready && !pwrite`

---

### 3.2 `dma_reg_file` — Register File

**Bản đồ địa chỉ:**

| Địa chỉ | Tên | Bit | Quyền truy cập |
|---|---|---|---|
| `0x00` | SRC_ADDR | [31:0] | RW |
| `0x04` | DST_ADDR | [31:0] | RW |
| `0x08` | LEN | [31:0] | RW |
| `0x0C` | CTRL | [0]=START, [1]=IE | RW |
| `0x10` | STAT | [0]=BUSY (RO), [1]=DONE (W1C) | R/W1C |

**Logic đặc biệt:**
- **Error detection**: Lỗi nếu địa chỉ ngoài `[0x00..0x10]` hoặc ghi vào bit BUSY
- **Wait request**: Chặn ghi SRC/DST/LEN khi DMA đang `busy`
- **dma_start**: Pulse 1 chu kỳ khi CPU ghi `CTRL[0]=1`
- **W1C DONE**: Ghi `STAT[1]=1` để xóa cờ DONE

---

### 3.3 `dma_master_engine` — DMA Execution Engine

**FSM 7 trạng thái:**

```
         dma_start
  IDLE ──────────► RD_SETUP ──► RD_ACCESS ──(pready)──► WR_SETUP ──► WR_ACCESS
                                                                           │(pready)
                                                         DONE ◄─ UPDATE ◄─┘
                                                          │(len≤1)  │(len>1: src+4, dst+4, len-1)
                                                          ▼          └──► RD_SETUP
                                                         IDLE
```

| State | Mô tả |
|---|---|
| `IDLE` | Chờ `dma_start`, nạp config |
| `RD_SETUP` | Set `m_paddr=curr_src`, `m_pwrite=0`, `m_psel=1` |
| `RD_ACCESS` | Assert `m_penable`, chờ `m_pready`, latch data |
| `WR_SETUP` | Set `m_paddr=curr_dst`, `m_pwdata=buffer`, `m_pwrite=1` |
| `WR_ACCESS` | Assert `m_penable`, chờ `m_pready` |
| `UPDATE` | Tăng địa chỉ +4, giảm len-1, lặp hoặc kết thúc |
| `DONE` | Set `dma_done=1`, `dma_busy=0`, về IDLE |

---

## 4. Kết quả Simulation

### 4.1 Môi trường

| Mục | Chi tiết |
|---|---|
| Tool | Vivado XSim Behavioral Simulation |
| Testbench | `tb_simple_dma..sv` |
| Memory model | Ideal: `m_pready = m_psel & m_penable` |
| Clock | 100 MHz (10ns period) |
| Transfer | 4 words (16 bytes): `0x1000 → 0x1800` |

### 4.2 Kịch bản test

| Bước | Hành động | Kỳ vọng |
|---|---|---|
| TC1 | Ghi SRC=`0x1000`, DST=`0x1800`, LEN=4 | Config latch vào reg |
| TC2 | Ghi CTRL=`0x01` (START) | DMA bắt đầu, BUSY=1 |
| TC3 | Poll STAT đợi DONE=1 | `DMA DONE detected` |
| TC4 | So sánh dữ liệu đích với nguồn | `SUCCESS` |

### 4.3 Kết quả

```
STEP 1: Chèn dữ liệu mẫu vào RAM nguồn (Backdoor)
STEP 2: CPU cấu hình DMA
STEP 3: Đợi DMA hoàn thành
DMA DONE detected!
STEP 4: Kiểm tra dữ liệu tại vùng đích (0x1800)
===> SUCCESS: Dữ liệu copy chính xác!
$finish called at time : 715 ns
```

**Dữ liệu copy đúng hoàn toàn:**

| Word | Source | Destination | Match |
|---|---|---|---|
| 0 | `0xDEADBEEF` | `0xDEADBEEF` | ✅ |
| 1 | `0xCAFEBABE` | `0xCAFEBABE` | ✅ |
| 2 | `0x12345678` | `0x12345678` | ✅ |
| 3 | `0x87654321` | `0x87654321` | ✅ |

---

## 5. Các vấn đề đã phát hiện & khắc phục

| # | Vấn đề | File | Giải pháp |
|---|---|---|---|
| 1 | `prdata` không được gán trong `apb_slave_if` | `apb_slave_if.v` | Thêm port `reg_rdata`, `assign prdata = reg_rdata` |
| 2 | `stat_reg[1]` bị multi-driver (2 always block) | `dma_reg_file.v` | Gộp thành 1 always block duy nhất |
| 3 | `always_comb` dùng `<=` | `memory_model.sv` | Đổi thành `=` (blocking) |
| 4 | `begin/end` mất cân bằng | `memory_model.sv` | Viết lại FSM wait state |
| 5 | `m_paddr`, `m_pwrite`, `m_pwdata` không reset | `dma_master_engine.v` | Thêm vào reset block |
| 6 | `cpu_write` deassert psel quá sớm | `tb_simple_dma..sv` | Giữ thêm 1 posedge để reg_file kịp latch |

---

## 6. Hướng phát triển tiếp theo

- [ ] Tích hợp `memory_model.sv` random wait states vào simulation
- [ ] Thêm test: transfer liên tiếp, overlap address, LEN=1
- [ ] Thêm cơ chế ngắt (interrupt) khi DONE
- [ ] Hỗ trợ burst transfer thay vì từng word
- [ ] FPGA implementation & timing closure (Artix-7)
