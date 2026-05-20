----------------------------------------------------------------------------------
-- Testbench : inference_module_tb
--
-- DUT pipeline:  s_axis -> pixel_encoding -> patches_v5 -> clauses -> m_axis
--
-- AXI-Stream pixel source   (s_axis, 24-bit RGB packed in a 32-bit word)
-- AXI-Stream class-sum sink (m_axis, two consecutive 32-bit words per image)
-- Block-RAM model            (registered-address, combinatorial-output:
--                             1-cycle read latency = Xilinx BRAM, no output reg)
--
-- ── Test parameters (specialist 3, PS3=7, one-hot "1000") ────────────────────
--  Weights  : w(0,0)=+1   w(1,1)=+2   w(2,2)=-1   all others = 0
--  n_inc    : 0xFFFFFFFF for every clause (all literals excluded)
--             -> every clause evaluates to '1' from the first patch,
--                regardless of pixel content
--
-- ── Expected class sums ───────────────────────────────────────────────────────
--  class[0]=+1  class[1]=+2  class[2]=-1  class[3..9]=0
--
--  Packed as SUM_BITS=6-bit signed fields from cs_data_flat LSB:
--    word 0 (cs_last='0'):
--      bits[ 5: 0] = class 0  bits[11: 6] = class 1  bits[17:12] = class 2
--      bits[23:18] = class 3  bits[29:24] = class 4  bits[31:30] = class5[1:0]
--    word 1 (cs_last='1'):
--      bits[ 3: 0] = class5[5:2]  bits[ 9: 4] = class 6  bits[15:10] = class 7
--      bits[21:16] = class 8      bits[27:22] = class 9   bits[31:28] = padding
--
--  => word 0 = 0x0003_F081      word 1 = 0x0000_0000
--
-- ── Key timing (clauses S_LOAD downtime) ─────────────────────────────────────
--  clauses spends SPCLST_WORDS_C=624 cycles in S_LOAD before asserting
--  patch_ready_out='1'.  patches_v5 runs concurrently (writing pixels) but
--  the patch bus is back-pressured for all 624 cycles.  s_axis_tready also
--  stalls when the line-buffer excess counter saturates (~after 7 rows).
--  The AXI handshake loops below handle all stalls transparently.
--
-- ── Fixed S_STREAM timing (with stream_done flag) ────────────────────────────
--  Cycle A   (last patch, S_ACCUMULATE): state -> S_STREAM, cs_data latched
--  Cycle A+1 (S_STREAM, stream_word=0): cs_valid='1', tdata=word0, cs_last='0'
--              if cs_ready='1': stream_word <= '1'
--  Cycle A+2 (S_STREAM, stream_word=1): cs_valid='1', tdata=word1, cs_last='1'
--              if cs_ready='1': stream_done <= '1'
--  Cycle A+3 (S_STREAM, stream_done=1): cs_valid='0', state -> S_IDLE
--
--  Both words appear on back-to-back rising edges with m_axis_tready='1'.
--
-- ── stream_done initialisation note ──────────────────────────────────────────
--  clauses.vhd does not assign stream_done in its synchronous reset block.
--  In simulation stream_done starts as 'U', which evaluates to false for
--  "if stream_done='1'", so the FIRST inference run is unaffected.
--  For a second run stream_done would be '1' on entry to S_STREAM and the
--  output would be skipped entirely.  Fix: add "stream_done <= '0'" to the
--  reset block and to the stream_done='1' cleanup branch.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use work.math_pkg.all;
use work.types_pkg.all;

entity inference_module_tb is
end entity inference_module_tb;

architecture sim of inference_module_tb is

    constant CLK_PERIOD : time := 10 ns;

    ---------------------------------------------------------------------------
    -- Architecture constants (mirror clauses.vhd internals so we can compute
    -- BRAM offsets and expected class-sum bit positions here)
    ---------------------------------------------------------------------------
    --  FEAT_BITS = 2*POS_BITS + 3*PS3*PS3*ENC_BITS = 2*29 + 3*343 = 1087
    --  LIT_BITS  = 2*FEAT_BITS                                      = 2174
    --  WGHT_BITS = clog2(MAX_WEIGHT)+2                              = 4
    --  SUM_BITS  = clog2(MAX_WEIGHT*NUM_CLAUSES)+1                  = 6
    --  WGHT_WORDS  = NUM_CLAUSES*NUM_CLASSES                        = 80
    --  INC_WORDS   = ceil(LIT_BITS/32)                              = 68
    --  SPCLST_WORDS= WGHT_WORDS + NUM_CLAUSES*INC_WORDS             = 624
    --  BRAM_DEPTH  = NUM_SPECIALISTS*SPCLST_WORDS                   = 2496
    constant PS0            : positive := 3; -- PS0 should be smallest patch size
    constant PS1            : positive := 4;
    constant PS2            : positive := 5;
    constant PS3            : positive := 7; -- PS3 should be largest patch size 
         
    constant FEAT_BITS_C    : positive := 2*POS_BITS + 3*PS3*PS3*ENC_BITS;
    constant LIT_BITS_C     : positive := 2 * FEAT_BITS_C;
    constant WGHT_BITS_C    : positive := clog2(MAX_WEIGHT) + 2;
    constant SUM_BITS_C     : positive := clog2(MAX_WEIGHT * NUM_CLAUSES) + 1;
    constant WGHT_WORDS_C   : positive := NUM_CLAUSES * NUM_CLASSES;
    constant INC_WORDS_C    : positive := (LIT_BITS_C + 31) / 32;
    constant SPCLST_WORDS_C : positive := WGHT_WORDS_C + NUM_CLAUSES * INC_WORDS_C;
    constant BRAM_DEPTH_C   : positive := NUM_SPECIALISTS * SPCLST_WORDS_C;
    constant NUM_PIXELS_C   : positive := IMG_SIZE * IMG_SIZE;
    constant CS_WORD_WIDTH_C: positive := 32;

    -- Specialist 3 (one-hot "1000") BRAM base word address
    constant BRAM_BASE_S3   : natural  := 3 * SPCLST_WORDS_C;   -- 1872

    ---------------------------------------------------------------------------
    -- DUT ports
    ---------------------------------------------------------------------------
    signal clk           : std_logic := '0';
    signal n_reset       : std_logic := '0';
    signal wr_ready_intr : std_logic;

    signal bram_addr     : std_logic_vector(BRAM_ADDR_WIDTH - 1 downto 0);
    signal bram_en       : std_logic;
    signal bram_data     : std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0)
                               := (others => '0');

    -- gpio_in[NUM_SPECIALISTS:1] = one-hot select;  gpio_in[0] = valid
    signal gpio_in       : std_logic_vector(NUM_SPECIALISTS downto 0)
                               := (others => '0');
    signal gpio_out      : std_logic_vector(0 downto 0);

    signal s_axis_tdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';

    signal m_axis_tdata  : std_logic_vector(CS_WORD_WIDTH_C - 1 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';   -- sink always accepts
    signal m_axis_tlast  : std_logic;

    ---------------------------------------------------------------------------
    -- BRAM memory model
    ---------------------------------------------------------------------------
    type bram_t is array(0 to BRAM_DEPTH_C - 1) of
                        std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0);

    signal bram_mem    : bram_t := (others => (others => '0'));

    -- One-cycle latency pipeline: address registered on rising_edge;
    -- bram_data driven combinatorially from the registered address.
    signal bram_addr_r : std_logic_vector(BRAM_ADDR_WIDTH - 1 downto 0)
                             := (others => '0');
    signal bram_en_r   : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Clock
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    DUT : entity work.inference_module
        port map (
            clk             => clk,
            n_reset         => n_reset,
            wr_ready_intr   => wr_ready_intr,
            bram_addr_out   => bram_addr,
            bram_en_out     => bram_en,
            bram_data_in    => bram_data,
            gpio_in         => gpio_in,
            gpio_out        => gpio_out,
            s_axis_tdata    => s_axis_tdata,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tready   => s_axis_tready,
            s_axis_tlast    => s_axis_tlast,
            m_axis_tdata    => m_axis_tdata,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => m_axis_tlast
        );

    ---------------------------------------------------------------------------
    -- BRAM initialisation (runs once at t=0)
    --
    -- Weight layout from BRAM_BASE_S3:
    --   offset = clause_i * NUM_CLASSES + class_j
    --   Stored in lower WGHT_BITS=4 bits as 4-bit signed.
    --     +1 = 0x1    +2 = 0x2    -1 = 0xF (4-bit two's complement)
    --
    -- n_inc layout from BRAM_BASE_S3 + WGHT_WORDS_C:
    --   offset = clause_i * INC_WORDS_C + word_within_clause
    --   0xFFFFFFFF = all 32 literal bits excluded.
    --   VHDL bounds check in S_LOAD prevents overflow beyond LIT_BITS=2174.
    ---------------------------------------------------------------------------
    bram_init : process
    begin
        -- Weights: specialist 3
        bram_mem(BRAM_BASE_S3 + 0*NUM_CLASSES + 0) <= x"00000001"; -- w(0,0)=+1
        bram_mem(BRAM_BASE_S3 + 1*NUM_CLASSES + 1) <= x"00000002"; -- w(1,1)=+2
        bram_mem(BRAM_BASE_S3 + 2*NUM_CLASSES + 2) <= x"0000000F"; -- w(2,2)=-1

        -- n_inc: every literal excluded in every clause
        for c in 0 to NUM_CLAUSES - 1 loop
            for w in 0 to INC_WORDS_C - 1 loop
                bram_mem(BRAM_BASE_S3 + WGHT_WORDS_C + c * INC_WORDS_C + w)
                    <= x"FFFFFFFF";
            end loop;
        end loop;
        wait;
    end process bram_init;

    ---------------------------------------------------------------------------
    -- BRAM model: registered address, combinatorial data output (1-cycle latency)
    --
    -- clauses.vhd S_LOAD accommodates this latency with the "if load_ctr/=0"
    -- guard: at load_ctr=0 bram_data is still stale; at load_ctr=1 it reflects
    -- the address driven in cycle 0, and so on for every subsequent word.
    --
    -- The ~624-cycle S_LOAD phase is where the "BRAM downtime" occurs: the
    -- entire BRAM burst must finish before patch_ready_out can go high.
    ---------------------------------------------------------------------------
    bram_pipe : process(clk)
    begin
        if rising_edge(clk) then
            bram_addr_r <= bram_addr;
            bram_en_r   <= bram_en;
        end if;
    end process bram_pipe;

    bram_data <= bram_mem(to_integer(unsigned(bram_addr_r)))
                     when (bram_en_r = '1' and
                           to_integer(unsigned(bram_addr_r)) < BRAM_DEPTH_C)
                     else (others => '0');

    ---------------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------------
    stim_proc : process
        variable c0_v     : std_logic_vector(7 downto 0);
        variable c1_v     : std_logic_vector(7 downto 0);
        variable c2_v     : std_logic_vector(7 downto 0);
        variable cs_word0 : std_logic_vector(CS_WORD_WIDTH_C - 1 downto 0);
        variable cs_word1 : std_logic_vector(CS_WORD_WIDTH_C - 1 downto 0);
        variable cs_raw   : std_logic_vector(2*CS_WORD_WIDTH_C - 1 downto 0);
        variable cs_val   : integer;
        variable l        : line;
    begin

        -----------------------------------------------------------------------
        -- 1. Reset
        -----------------------------------------------------------------------
        n_reset       <= '0';
        gpio_in       <= (others => '0');
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';
        m_axis_tready <= '1';

        wait for 15 * CLK_PERIOD;
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- 2. Release reset; wait for FSMs to reach stable S_IDLE
        --
        -- patches_v5: reset -> S_IDLE, ps_valid_prev='0'.  Ready cycle 1.
        -- clauses:    reset -> S_RESET -> S_IDLE (S_RESET sets
        --             spclst_valid_prev='1' so the first gpio pulse is not
        --             mistaken as an edge). After 2 cycles in S_IDLE,
        --             spclst_valid_prev='0' and edge detection is live.
        -- 10-cycle margin is conservative.
        -----------------------------------------------------------------------
        n_reset <= '1';
        report "Reset released." severity note;
        for i in 0 to 9 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- 3. Send PS selection (one-cycle pulse)
        --
        -- gpio_in[4:1] = one-hot specialist select
        -- gpio_in[0]   = valid (rising-edge-triggered in both FSMs)
        --
        -- PS3 = 7 -> select = "1000" -> gpio_in = "10001"
        --
        -- patches_v5 -> S_ACTIVE  (wr_en asserts 2 cycles later)
        -- clauses    -> S_LOAD    (reads 624 BRAM words; patch_ready='0'
        --                          for the entire load, i.e. ~624 cycles)
        -----------------------------------------------------------------------
        
        report "Sending PS3=7 selection (one-hot '1000', valid='1')." severity note;
        gpio_in <= "10001";
        wait until rising_edge(clk);
        gpio_in <= (others => '0');

        -----------------------------------------------------------------------
        -- 4. Stream 1024 pixels as 3-channel AXI-Stream words
        --
        -- s_axis word format (inference_module.vhd -> pixel_encoding):
        --   [31:24] = 0x00 (unused)
        --   [23:16] = C0  (red,   8-bit raw)
        --   [15: 8] = C1  (green, 8-bit raw)
        --   [ 7: 0] = C2  (blue,  8-bit raw)
        --
        -- Three distinct channel values are used per pixel; since n_inc=0xFF
        -- for every clause the encoded values do not affect the result, but
        -- the full encoder pipeline (thermometer encoding for each channel) is
        -- exercised.
        --
        -- Backpressure handled by the AXI handshake loop:
        --   s_axis_tready = patches_v5.wr_en = '0' between pixel rows and
        --   while the excess-pixel counter is saturated (roughly the first
        --   ~7 rows worth of pixels are written before clauses' S_LOAD
        --   completes and patch reads begin decrementing the counter).
        -----------------------------------------------------------------------
        report "Streaming 1024 pixels (3-channel)..." severity note;

        for px_idx in 0 to NUM_PIXELS_C - 1 loop
            -- Distinct per-channel values cycling through 0..255
            c0_v := std_logic_vector(to_unsigned( px_idx mod 256,           8));
            c1_v := std_logic_vector(to_unsigned((px_idx + 85)  mod 256,    8));
            c2_v := std_logic_vector(to_unsigned((px_idx + 171) mod 256,    8));

            s_axis_tdata  <= x"00" & c0_v & c1_v & c2_v;
            s_axis_tvalid <= '1';
            s_axis_tlast  <= '1' when px_idx = NUM_PIXELS_C - 1 else '0';

            -- AXI-Stream master: hold stable until handshake completes
            loop
                wait until rising_edge(clk);
                exit when s_axis_tready = '1';
            end loop;
        end loop;

        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';
        report "All pixels sent. Waiting for class-sum AXI stream..." severity note;

        -----------------------------------------------------------------------
        -- 5. Receive two-word class-sum AXI-Stream
        --
        -- With the fixed stream_done flag, S_STREAM drives cs_valid='1' for
        -- two consecutive cycles before cleanup:
        --
        --   Handshake 0: tvalid='1', tdata=word0, tlast='0'  -> captured first
        --   Handshake 1: tvalid='1', tdata=word1, tlast='1'  -> captured next
        --
        -- m_axis_tready='1' throughout so both words transfer without gaps.
        -- We assert cs_last to verify the protocol framing is correct.
        -----------------------------------------------------------------------

        -- Word 0 (cs_last = '0')
        wait until rising_edge(clk) and m_axis_tvalid = '1';
        cs_word0 := m_axis_tdata;

        assert m_axis_tlast = '0'
            report "PROTOCOL ERROR: cs_last should be '0' for word 0"
            severity error;

        report "m_axis word 0 = 0x" & to_hstring(cs_word0)
               & "   (expect 0x0003F081)" severity note;

        -- Word 1 (cs_last = '1') - arrives on the immediately following cycle
        wait until rising_edge(clk) and m_axis_tvalid = '1';
        cs_word1 := m_axis_tdata;

        assert m_axis_tlast = '1'
            report "PROTOCOL ERROR: cs_last should be '1' for word 1"
            severity error;

        report "m_axis word 1 = 0x" & to_hstring(cs_word1)
               & "   (expect 0x00000000)" severity note;

        -----------------------------------------------------------------------
        -- 6. Decode and print all 10 class sums
        --
        -- cs_raw[63:0]  =  word1 & word0   (word1 in the upper 32 bits)
        -- class j occupies cs_raw[(j+1)*SUM_BITS_C-1 : j*SUM_BITS_C]
        -- as a SUM_BITS_C=6-bit signed value.
        -----------------------------------------------------------------------
        cs_raw := cs_word1 & cs_word0;

        report "\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\" severity note;
        report "  Class sums  (SUM_BITS=6, signed)" severity note;
        report "////////////////////////////////" severity note;
        for j in 0 to NUM_CLASSES - 1 loop
            cs_val := to_integer(
                signed(cs_raw((j + 1)*SUM_BITS_C - 1 downto j*SUM_BITS_C))
            );
            write(l, string'("  class[") & integer'image(j)
                    & string'("] = ") & integer'image(cs_val));
            writeline(output, l);
        end loop;
        report "  Expected: [+1, +2, -1, 0 x7]" severity note;

        -----------------------------------------------------------------------
        -- 7. Assertions
        -----------------------------------------------------------------------
        assert cs_word0 = x"0003F081"
            report "FAIL word0: got 0x" & to_hstring(cs_word0)
                   & ", expected 0x0003F081" severity error;
        assert cs_word1 = x"00000000"
            report "FAIL word1: got 0x" & to_hstring(cs_word1)
                   & ", expected 0x00000000" severity error;

        assert to_integer(signed(cs_raw(1*SUM_BITS_C-1 downto 0*SUM_BITS_C))) = 1
            report "FAIL: class[0] != +1" severity error;
        assert to_integer(signed(cs_raw(2*SUM_BITS_C-1 downto 1*SUM_BITS_C))) = 2
            report "FAIL: class[1] != +2" severity error;
        assert to_integer(signed(cs_raw(3*SUM_BITS_C-1 downto 2*SUM_BITS_C))) = -1
            report "FAIL: class[2] != -1" severity error;
        for j in 3 to NUM_CLASSES - 1 loop
            assert to_integer(
                       signed(cs_raw((j+1)*SUM_BITS_C-1 downto j*SUM_BITS_C))) = 0
                report "FAIL: class[" & integer'image(j) & "] != 0" severity error;
        end loop;

        report "All assertions passed." severity note;

        wait for 20 * CLK_PERIOD;
        std.env.finish;

    end process stim_proc;

end architecture sim;