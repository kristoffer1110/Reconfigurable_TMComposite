# Implementing `top_wo_clause` on the PYNQ-Z1

---

## 1. How PS and PL Talk to Each Other

The PYNQ-Z1 is a Zynq-7000 SoC. It has two tightly coupled halves:

- **PS (Processing System)** — a dual-core ARM Cortex-A9 running Linux. This is where your Jupyter notebooks run.
- **PL (Programmable Logic)** — the FPGA fabric where your VHDL runs.

They communicate through several standard interfaces:

| Interface | What it's for |
|-----------|--------------|
| **AXI4-Lite** | Slow control registers (reset, ps_in, status flags). The PS writes/reads single 32-bit words over a memory-mapped address. |
| **AXI4-Stream + DMA** | High-throughput streaming data. The DMA controller moves blocks of data between PS DRAM and a stream-based PL IP. Your pixel input and patch output will use this. |
| **AXI4 (Full)** | High-bandwidth memory-mapped access. Not needed here. |

The PS accesses all PL peripherals through a memory-mapped address space. From Python, `pynq.Overlay` loads your bitstream and exposes these peripherals as Python objects (`overlay.axi_dma_0`, `overlay.axi_gpio_0`, etc.).

---

## 2. Solution Architecture

Your design cannot be connected directly to the PS because it has a custom handshake interface, not AXI. The plan is:

```
PS DRAM
  │
  ├─── [AXI DMA MM2S] ──► [axis_pixel_in wrapper] ──► top_wo_clause ──► [axis_patch_out wrapper] ──► [AXI DMA S2MM] ───► PS DRAM
  │
  └─── [AXI GPIO] ──────────────────────────────────► ps_in / ps_valid_in / reset / ps_request_out / done
```

**Two HDL wrapper modules** bridge your existing ports to AXI-Stream:

- **`axis_pixel_in`**: receives 32-bit AXI-Stream words (one pixel per word, three channels packed), drives `c0_px_in`, `c1_px_in`, `c2_px_in` and the valid signals.
- **`axis_patch_out`**: serialises the 1087-bit patch output (x_pos + y_pos + 3×7×7 encoded pixels) into 35 × 32-bit AXI-Stream words, with TLAST on the last word.

Control signals (reset, ps_in, ps_valid_in, ps_request_out, done) go through **AXI GPIO**, which the PS writes/reads like memory.

---

## 3. Word Packing Definitions

### Input stream (PS → PL), 32 bits per pixel

```
bits [31:24] = 0 (unused)
bits [23:16] = C2 pixel (8-bit raw)
bits [15:8]  = C1 pixel (8-bit raw)
bits  [7:0]  = C0 pixel (8-bit raw)
```

Send 1024 words (one per pixel) per image. The DMA transfer length is `1024 × 4 = 4096 bytes`.

### Output stream (PL → PS), 35 × 32-bit words per patch

| Word | Content |
|------|---------|
| 0 | `{3'b000, y_pos_out[28:0]}` |
| 1 | `{3'b000, x_pos_out[28:0]}` |
| 2–34 | 1029 bits of patch data, packed MSB-first, last word zero-padded |

Patch data bit order (matching the testbench hex format):
for row i = 6 downto 0, for col j = 0 to 6: `C0(i)(j)[6:0]`, `C1(i)(j)[6:0]`, `C2(i)(j)[6:0]`

TLAST is asserted on word 34. One DMA receive buffer needs `35 × 4 = 140 bytes`. For a 7×7 image (676 patches) allocate `676 × 140 = 94640 bytes` and let the DMA run to completion.

---

## 4. HDL Wrappers

Create these two new VHDL files in your Vivado project alongside your existing sources.

### 4.1 `axis_pixel_in.vhd`

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity axis_pixel_in is
    Generic (PX_BITS : positive := 8);
    Port (
        clk             : in  STD_LOGIC;
        reset           : in  STD_LOGIC;
        -- AXI4-Stream slave (from DMA MM2S)
        s_axis_tdata    : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axis_tvalid   : in  STD_LOGIC;
        s_axis_tready   : out STD_LOGIC;
        s_axis_tlast    : in  STD_LOGIC;
        -- Pixel outputs to top_wo_clause
        c0_px_out       : out STD_LOGIC_VECTOR(PX_BITS-1 downto 0);
        c1_px_out       : out STD_LOGIC_VECTOR(PX_BITS-1 downto 0);
        c2_px_out       : out STD_LOGIC_VECTOR(PX_BITS-1 downto 0);
        c0_valid_out    : out STD_LOGIC;
        c1_valid_out    : out STD_LOGIC;
        c2_valid_out    : out STD_LOGIC;
        -- Ready back from top_wo_clause (all three channels ANDed)
        px_ready_in     : in  STD_LOGIC
    );
end axis_pixel_in;

architecture rtl of axis_pixel_in is
begin
    c0_px_out    <= s_axis_tdata(7  downto  0);
    c1_px_out    <= s_axis_tdata(15 downto  8);
    c2_px_out    <= s_axis_tdata(23 downto 16);

    c0_valid_out  <= s_axis_tvalid;
    c1_valid_out  <= s_axis_tvalid;
    c2_valid_out  <= s_axis_tvalid;

    -- Back-pressure: stall DMA when the design is not ready
    s_axis_tready <= px_ready_in;
end rtl;
```

> **Note on ready**: `px_ready_in` should be `c0_ready_out AND c1_ready_out AND c2_ready_out` from `top_wo_clause`. Wire this externally in the block design or in a small top-level wrapper.

### 4.2 `axis_patch_out.vhd`

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity axis_patch_out is
    Generic (
        PS3      : positive := 7;
        ENC_BITS : positive := 7;
        POS_BITS : positive := 29   -- DATA_WIDTH - PS0 = 32 - 3
    );
    Port (
        clk             : in  STD_LOGIC;
        reset           : in  STD_LOGIC;
        -- Inputs from top_wo_clause
        x_pos_in        : in  STD_LOGIC_VECTOR(0 to POS_BITS-1);
        y_pos_in        : in  STD_LOGIC_VECTOR(0 to POS_BITS-1);
        c0_patch_in     : in  pixel_row_arr(PS3-1 downto 0)(PS3-1 downto 0)(ENC_BITS-1 downto 0);
        c1_patch_in     : in  pixel_row_arr(PS3-1 downto 0)(PS3-1 downto 0)(ENC_BITS-1 downto 0);
        c2_patch_in     : in  pixel_row_arr(PS3-1 downto 0)(PS3-1 downto 0)(ENC_BITS-1 downto 0);
        s_valid_in      : in  STD_LOGIC;
        s_ready_out     : out STD_LOGIC;
        -- AXI4-Stream master (to DMA S2MM)
        m_axis_tdata    : out STD_LOGIC_VECTOR(31 downto 0);
        m_axis_tvalid   : out STD_LOGIC;
        m_axis_tready   : in  STD_LOGIC;
        m_axis_tlast    : out STD_LOGIC
    );
end axis_patch_out;

architecture rtl of axis_patch_out is

    -- 1087 bits total: 29 y + 29 x + 49*21 pixels
    -- Packed into 35 words of 32 bits (last word uses 7 bits, 25 bits padding)
    constant TOTAL_PATCH_BITS : natural := 2*POS_BITS + PS3*PS3*3*ENC_BITS; -- 1087
    constant NUM_WORDS        : natural := 35;  -- ceil(1087/32)

    -- Flat serialisation register
    signal shift_reg   : STD_LOGIC_VECTOR(NUM_WORDS*32-1 downto 0);
    signal word_cntr   : unsigned(5 downto 0);  -- 0 to 34
    signal busy        : STD_LOGIC;

begin

    -- Accept a new patch only when idle
    s_ready_out <= not busy;

    -- Load and shift process
    process(clk)
        variable flat : STD_LOGIC_VECTOR(TOTAL_PATCH_BITS-1 downto 0);
        variable padded : STD_LOGIC_VECTOR(NUM_WORDS*32-1 downto 0);
        variable bit_idx : natural;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                busy       <= '0';
                word_cntr  <= (others => '0');
                shift_reg  <= (others => '0');

            elsif busy = '0' and s_valid_in = '1' then
                -- Pack everything into flat vector, MSB first
                -- y_pos first, then x_pos, then pixels row-major C0,C1,C2 per pixel
                flat(TOTAL_PATCH_BITS-1 downto TOTAL_PATCH_BITS-POS_BITS)
                    := y_pos_in;
                flat(TOTAL_PATCH_BITS-POS_BITS-1 downto TOTAL_PATCH_BITS-2*POS_BITS)
                    := x_pos_in;
                bit_idx := TOTAL_PATCH_BITS - 2*POS_BITS - 1;
                for row in PS3-1 downto 0 loop
                    for col in 0 to PS3-1 loop
                        flat(bit_idx downto bit_idx-ENC_BITS+1)
                            := c0_patch_in(row)(col);
                        bit_idx := bit_idx - ENC_BITS;
                        flat(bit_idx downto bit_idx-ENC_BITS+1)
                            := c1_patch_in(row)(col);
                        bit_idx := bit_idx - ENC_BITS;
                        flat(bit_idx downto bit_idx-ENC_BITS+1)
                            := c2_patch_in(row)(col);
                        bit_idx := bit_idx - ENC_BITS;
                    end loop;
                end loop;
                -- Zero-pad to fill shift register
                padded := (others => '0');
                padded(NUM_WORDS*32-1 downto NUM_WORDS*32-TOTAL_PATCH_BITS) := flat;
                shift_reg  <= padded;
                word_cntr  <= (others => '0');
                busy       <= '1';

            elsif busy = '1' and m_axis_tready = '1' then
                if word_cntr = NUM_WORDS-1 then
                    busy      <= '0';
                    word_cntr <= (others => '0');
                else
                    -- Shift out one word
                    shift_reg  <= shift_reg(NUM_WORDS*32-33 downto 0) & x"00000000";
                    word_cntr  <= word_cntr + 1;
                end if;
            end if;
        end if;
    end process;

    m_axis_tdata  <= shift_reg(NUM_WORDS*32-1 downto NUM_WORDS*32-32);
    m_axis_tvalid <= busy;
    m_axis_tlast  <= '1' when (busy = '1' and word_cntr = NUM_WORDS-1) else '0';

end rtl;
```

---

## 5. Top-Level PL Wrapper

Create one more file `pl_top.vhd` that instantiates everything and presents clean AXI ports to Vivado's block design:

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.types_pkg.all;

entity pl_top is
    Port (
        clk              : in  STD_LOGIC;
        -- AXI-Stream pixel input (from DMA MM2S)
        s_axis_tdata     : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axis_tvalid    : in  STD_LOGIC;
        s_axis_tready    : out STD_LOGIC;
        s_axis_tlast     : in  STD_LOGIC;
        -- AXI-Stream patch output (to DMA S2MM)
        m_axis_tdata     : out STD_LOGIC_VECTOR(31 downto 0);
        m_axis_tvalid    : out STD_LOGIC;
        m_axis_tready    : in  STD_LOGIC;
        m_axis_tlast     : out STD_LOGIC;
        -- GPIO control (driven from AXI GPIO on PS side)
        reset            : in  STD_LOGIC;
        ps_in            : in  STD_LOGIC_VECTOR(3 downto 0);
        ps_valid_in      : in  STD_LOGIC;
        ps_request_out   : out STD_LOGIC;
        done_out         : out STD_LOGIC
    );
end pl_top;

architecture rtl of pl_top is
    signal c0_px, c1_px, c2_px        : STD_LOGIC_VECTOR(7 downto 0);
    signal c0_valid, c1_valid, c2_valid: STD_LOGIC;
    signal c0_ready, c1_ready, c2_ready: STD_LOGIC;
    signal x_pos  : STD_LOGIC_VECTOR(0 to 28);
    signal y_pos  : STD_LOGIC_VECTOR(0 to 28);
    signal c0_patch : pixel_row_arr(6 downto 0)(6 downto 0)(6 downto 0);
    signal c1_patch : pixel_row_arr(6 downto 0)(6 downto 0)(6 downto 0);
    signal c2_patch : pixel_row_arr(6 downto 0)(6 downto 0)(6 downto 0);
    signal patch_valid, patch_ready_s  : STD_LOGIC;
begin

    u_pix_in : entity work.axis_pixel_in
        port map (
            clk => clk, reset => reset,
            s_axis_tdata  => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,
            c0_px_out => c0_px, c1_px_out => c1_px, c2_px_out => c2_px,
            c0_valid_out => c0_valid, c1_valid_out => c1_valid, c2_valid_out => c2_valid,
            px_ready_in => c0_ready and c1_ready and c2_ready
        );

    u_top : entity work.top_wo_clause
        port map (
            clk => clk, reset => reset,
            ps_in => ps_in, ps_valid_in => ps_valid_in,
            ps_request_out => ps_request_out,
            c0_px_in => c0_px, c0_valid_in => c0_valid, c0_ready_out => c0_ready,
            c1_px_in => c1_px, c1_valid_in => c1_valid, c1_ready_out => c1_ready,
            c2_px_in => c2_px, c2_valid_in => c2_valid, c2_ready_out => c2_ready,
            x_pos_out => x_pos, y_pos_out => y_pos,
            c0_patches_out => c0_patch, c1_patches_out => c1_patch, c2_patches_out => c2_patch,
            s_valid_out => patch_valid, s_ready_in => patch_ready_s,
            done => done_out
        );

    u_patch_out : entity work.axis_patch_out
        port map (
            clk => clk, reset => reset,
            x_pos_in => x_pos, y_pos_in => y_pos,
            c0_patch_in => c0_patch, c1_patch_in => c1_patch, c2_patch_in => c2_patch,
            s_valid_in  => patch_valid,
            s_ready_out => patch_ready_s,
            m_axis_tdata  => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast  => m_axis_tlast
        );

end rtl;
```

---

## 6. Packaging as a Vivado IP

You need to package `pl_top` (and all its dependencies) as a reusable IP so it can be dropped into the block design.

1. In Vivado: **Tools → Create and Package New IP**
2. Choose **Package a specified directory**, point it at the folder containing all your VHDL source files
3. Set the IP name to `patch_generator`, version `1.0`
4. On the **Ports and Interfaces** page, Vivado will auto-detect the `s_axis_*` and `m_axis_*` signals and offer to infer AXI4-Stream interfaces — accept this for both
5. The remaining ports (reset, ps_in, etc.) stay as plain ports
6. Click **Package IP** and **Finish**

---

## 7. Building the Vivado Block Design

### 7.1 Create a new project

- Part: **xc7z020clg400-1** (PYNQ-Z1)
- Add all your source files plus the two new wrappers
- Do **not** set a top-level module yet (the block design will be the top)

### 7.2 Add the block design

**IP Integrator → Create Block Design**, name it `design_1`.

Add the following IPs (use the **+** button and search by name):

| IP | Notes |
|----|-------|
| ZYNQ7 Processing System | The PS |
| AXI Direct Memory Access | Pixel input + patch output |
| AXI GPIO | Control signals |
| patch_generator (your custom IP) | The PL design |
| Processor System Reset | Clean reset synchronisation |

### 7.3 Configure the ZYNQ7 PS

Double-click it and run **Run Block Automation**. This configures DDR and fixed IO for the PYNQ-Z1. Then:

- **PS-PL Configuration → AXI Non-Secure Enablement → GP Master AXI Interface**: enable `M AXI GP0` (for AXI-Lite to DMA and GPIO)
- **Clock Configuration → PL Fabric Clocks**: set FCLK_CLK0 to **100 MHz** — this is the clock for your entire PL design

### 7.4 Configure AXI DMA

Double-click the DMA:

| Setting | Value |
|---------|-------|
| Enable Scatter Gather Engine | **No** (simple DMA is enough) |
| Width of Buffer Length Register | **26** (supports transfers up to 64 MB) |
| MM2S Data Width | 32 |
| S2MM Data Width | 32 |
| MM2S Burst Size | 16 |
| S2MM Burst Size | 16 |

### 7.5 Configure AXI GPIO

Double-click it:

- **GPIO Width**: 6 (carries `{done, ps_request_out, ps_valid_in, ps_in[3:0]}` — 6 bits)
- Enable **GPIO2** for the second direction: width 2, for output signals you read back (`ps_request_out`, `done`)

A simpler split: use two separate AXI GPIO IPs, one 6-bit output (reset + ps_in + ps_valid_in) and one 2-bit input (ps_request_out + done). That avoids direction confusion.

### 7.6 Connect everything

Click **Run Connection Automation** and let Vivado wire the AXI-Lite control bus (M_AXI_GP0 → DMA S_AXI_LITE and GPIO S_AXI). Then manually complete:

- `FCLK_CLK0` → `clk` on your IP, DMA, GPIO, and Proc System Reset
- `FCLK_RESET0_N` → `ext_reset_in` on Proc System Reset
- `peripheral_reset[0]` from Proc System Reset → `reset` on your IP
- DMA `M_AXIS_MM2S` → your IP `s_axis_*` (pixel input)
- Your IP `m_axis_*` → DMA `S_AXIS_S2MM` (patch output)
- GPIO output bits → your IP `reset`, `ps_in`, `ps_valid_in`
- Your IP `ps_request_out`, `done_out` → GPIO input bits
- DMA interrupt signals → ZYNQ PS `IRQ_F2P` (optional but useful — allows Python to block until DMA finishes)

### 7.7 Generate the bitstream

- **Validate Design** (wrench icon) — fix any errors
- **Create HDL Wrapper** on the block design (right-click in Sources)
- Set the wrapper as the top module
- **Generate Bitstream**

This takes 5–15 minutes. When done, go to **File → Export → Export Hardware** (include bitstream), save the `.xsa` file.

---

## 8. Transferring to the PYNQ-Z1

You need two files on the board:

- `patch_generator.bit` — the bitstream
- `patch_generator.hwh` — the hardware handoff file (describes addresses of all AXI peripherals)

Both are found in your Vivado project under:
```
<project>.runs/impl_1/design_1_wrapper.bit   → rename to patch_generator.bit
<project>.gen/sources_1/bd/design_1/hw_handoff/design_1.hwh → rename to patch_generator.hwh
```

They must share the same base name and be in the same directory. Transfer them to the board over SCP or by copying to an SD card:

```bash
scp patch_generator.bit patch_generator.hwh xilinx@<board_ip>:/home/xilinx/
# default password: xilinx
```

Also transfer your image hex file:
```bash
scp images/test_image_32x32_rgb_thermo_hex.txt xilinx@<board_ip>:/home/xilinx/
```

---

## 9. Jupyter Notebook on the PYNQ

Open a browser to `http://<board_ip>:9090`, password `xilinx`. Create a new notebook in `/home/xilinx/`.

```python
import numpy as np
from pynq import Overlay, allocate

# ── 1. Load the bitstream ────────────────────────────────────────────────────
ol = Overlay("/home/xilinx/patch_generator.bit")

# Single AXI GPIO block with two channels:
#   Channel 1 (output): reset, ps_in, ps_valid_in
#   Channel 2 (input):  ps_request_out, done
gpio = ol.axi_gpio_0

# AXI GPIO register offsets
GPIO_CH1_DATA = 0x000   # Channel 1 data (output: reset, ps_in, ps_valid_in)
GPIO_CH2_DATA = 0x008   # Channel 2 data (input:  ps_request_out, done)

# ── 2. Define constants ──────────────────────────────────────────────────────
IMG_SIZE    = 32
NUM_PIXELS  = IMG_SIZE * IMG_SIZE   # 1024
PS          = 7                     # patch size selected
NUM_PATCHES = (IMG_SIZE - PS + 1) ** 2  # 676 for 7x7 on 32x32
WORDS_PER_PATCH = 35
BYTES_PER_PATCH = WORDS_PER_PATCH * 4   # 140

# GPIO channel 1 bit layout (output):
#   bit 0     = ps_valid_in
#   bits 4:1  = ps_in[3:0]
#   bit 5     = reset
PS_SELECT = {"3": 0b0001, "4": 0b0010, "5": 0b0100, "7": 0b1000}

def gpio_write(reset, ps_in_bits, ps_valid):
    val = int(ps_valid) | (ps_in_bits << 1) | (int(reset) << 5)
    gpio.write(GPIO_CH1_DATA, val)

def gpio_read_request():
    return (gpio.read(GPIO_CH2_DATA) >> 0) & 1   # ps_request_out at bit 0

def gpio_read_done():
    return (gpio.read(GPIO_CH2_DATA) >> 1) & 1   # done at bit 1

# ── 3. Load and pack pixel data ──────────────────────────────────────────────
# Read the thermometer-encoded hex file (channel-separated: 1024 R, 1024 G, 1024 B)
with open("/home/xilinx/test_image_32x32_rgb_thermo_hex.txt") as f:
    lines = [l.strip() for l in f if l.strip() and not l.startswith('#')]

values = [int(l, 16) for l in lines]
c0 = values[0          : NUM_PIXELS]
c1 = values[NUM_PIXELS : 2*NUM_PIXELS]
c2 = values[2*NUM_PIXELS : 3*NUM_PIXELS]

# Pack into 32-bit words: {0x00, C2, C1, C0}
pixel_words = np.array(
    [(c2[i] << 16) | (c1[i] << 8) | c0[i] for i in range(NUM_PIXELS)],
    dtype=np.uint32
)

# ── 4. Allocate DMA buffers ──────────────────────────────────────────────────
in_buf  = allocate(shape=(NUM_PIXELS,),              dtype=np.uint32)
out_buf = allocate(shape=(NUM_PATCHES * WORDS_PER_PATCH,), dtype=np.uint32)

in_buf[:] = pixel_words

# ── 5. Reset the PL design ───────────────────────────────────────────────────
gpio_write(reset=1, ps_in_bits=0, ps_valid=0)
import time; time.sleep(0.01)
gpio_write(reset=0, ps_in_bits=0, ps_valid=0)

# ── 6. Wait for ps_request_out, then send patch size ────────────────────────
timeout = 1000
for _ in range(timeout):
    if gpio_read_request():
        break
    time.sleep(0.001)

gpio_write(reset=0, ps_in_bits=PS_SELECT[str(PS)], ps_valid=1)
time.sleep(0.001)
gpio_write(reset=0, ps_in_bits=0, ps_valid=0)

# ── 7. Start DMA transfers ───────────────────────────────────────────────────
dma.recvchannel.transfer(out_buf)   # S2MM: PL → PS (start first to avoid stall)
dma.sendchannel.transfer(in_buf)    # MM2S: PS → PL

# Block until both complete (uses DMA interrupt if wired, otherwise polls)
dma.sendchannel.wait()
dma.recvchannel.wait()

print("DMA transfers complete")

# ── 8. Parse output buffer ───────────────────────────────────────────────────
ENC_BITS = 7
POS_BITS = 29
patches = []

for p in range(NUM_PATCHES):
    base = p * WORDS_PER_PATCH
    words = out_buf[base : base + WORDS_PER_PATCH]

    y_pos = int(words[0]) & 0x1FFFFFFF
    x_pos = int(words[1]) & 0x1FFFFFFF

    # Reassemble 1029 patch bits from words 2-34
    raw_bits = 0
    for w in words[2:]:
        raw_bits = (raw_bits << 32) | int(w)
    # raw_bits is 33*32=1056 bits; take the top 1029
    raw_bits >>= (33 * 32 - 7 * 7 * 3 * ENC_BITS)

    c0_p, c1_p, c2_p = [], [], []
    total_bits = 7 * 7 * 3 * ENC_BITS  # 1029
    for i in range(7 * 7):
        shift = total_bits - (i + 1) * 3 * ENC_BITS
        pixel_bits = (raw_bits >> shift) & ((1 << (3 * ENC_BITS)) - 1)
        c0_val = (pixel_bits >> (2 * ENC_BITS)) & 0x7F
        c1_val = (pixel_bits >>      ENC_BITS)  & 0x7F
        c2_val =  pixel_bits                    & 0x7F
        c0_p.append(c0_val)
        c1_p.append(c1_val)
        c2_p.append(c2_val)

    patches.append({'y': y_pos, 'x': x_pos, 'c0': c0_p, 'c1': c1_p, 'c2': c2_p})

print(f"Parsed {len(patches)} patches")
print(f"Patch 0: x={patches[0]['x']}, y={patches[0]['y']}")
print(f"  C0 top row: {patches[0]['c0'][:7]}")
print(f"  C1 top row: {patches[0]['c1'][:7]}")
print(f"  C2 top row: {patches[0]['c2'][:7]}")

# ── 9. Visualise a patch ─────────────────────────────────────────────────────
from PIL import Image

def patch_to_image(patch, enc_bits=7):
    scale = 255.0 / ((1 << enc_bits) - 1)
    img = Image.new("RGB", (7, 7))
    pixels = [(min(255, int(round(patch['c0'][i] * scale))),
               min(255, int(round(patch['c1'][i] * scale))),
               min(255, int(round(patch['c2'][i] * scale))))
              for i in range(49)]
    img.putdata(pixels)
    return img

patch_to_image(patches[0]).resize((140, 140), Image.NEAREST)
```

---

## 10. Checklist Before Running

- [ ] Bitstream generates cleanly with no timing failures in Vivado
- [ ] `.bit` and `.hwh` share the same base name in the same directory on the board
- [ ] The DMA is configured for **simple mode** (no scatter-gather)
- [ ] `out_buf` is large enough: `NUM_PATCHES × 35 × 4` bytes
- [ ] S2MM DMA transfer is started **before** MM2S to avoid the output FIFO overflowing while the receive side is not listening
- [ ] After `reset=1`, wait at least a few clock cycles before deasserting — `time.sleep(0.01)` is fine

---

## 11. Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| `dma.recvchannel.wait()` hangs | TLAST is never asserted — check `axis_patch_out` word counter |
| All patch values are zero | DMA S2MM not started before MM2S — reverse the order |
| `ps_request_out` never goes high | Reset not reaching the PL — check GPIO wiring |
| Vivado AXI interface not inferred | Rename ports to exactly `s_axis_tdata`, `s_axis_tvalid`, etc. |
| Timing failures in implementation | Add a pipelined register stage at the output of `axis_patch_out` |
