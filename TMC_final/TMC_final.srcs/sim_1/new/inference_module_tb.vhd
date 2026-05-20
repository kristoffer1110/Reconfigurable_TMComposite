----------------------------------------------------------------------------------
-- Testbench : inference_module_tb
-- DUT       : inference_module (pixel_encoding -> patches_v5 -> clauses)
--
-- Models the PYNQ Z1 block design integration accurately:
--
--   GPIO handshake
--     Mirrors the PS7 AXI-GPIO protocol exactly:
--       (1) Poll gpio_out(0) until '1'  (hardware asserts request in S_IDLE)
--       (2) Drive gpio_in = one-hot select | valid
--       (3) Poll gpio_out(0) until '0'  (hardware latched select -> S_LOAD)
--       (4) Deassert gpio_in
--     The request deasserts on the cycle after the edge is detected, matching
--     the combinatorial spclst_request / ps_request logic.
--
--   BRAM model  (byte-addressed, matching BRAM_Controller + fixed IP)
--     The patched bram_addr_out drives a BYTE address: (word_idx * 4).
--     The model registers the address (1-cycle BRAM read latency, no output
--     register, matching Xilinx BRAM primitive defaults) then decodes via /4.
--     An alignment monitor flags any address whose lower 2 bits are non-zero,
--     which indicates the shift_left fix has not been applied.
--
--   wr_ready_intr
--     Connected to IRQ_F2P[1] in the block design.  The testbench verifies
--     it pulses at least once per inference run (fires in patches_v5 WS_IDLE
--     -> WS_WRITE on the first line-buffer fill).
--
--   Multi-run correctness
--     Three consecutive runs exercise the load_ctr reset fix (Bug 2):
--       Run 1 - Specialist 3 (7x7, "1000"): w(0,0)=+1  w(1,1)=+2  w(2,2)=-1
--       Run 2 - Specialist 0 (3x3, "0001"): w(3,5)=+3  w(4,8)=-3
--       Run 3 - Specialist 3 again          (must match Run 1)
--
--   AXI-Stream protocol checks
--     * m_axis word 0 arrives with tlast='0'
--     * m_axis word 1 arrives on the immediately following cycle with tlast='1'
--     * tvalid deasserts on the cycle after the word-1 handshake
--     * No tvalid gap between the two words (m_axis_tready held '1' throughout)
--
-- ── Expected class sums ───────────────────────────────────────────────────────
--
--  Run 1 / Run 3  (Specialist 3):
--    class[0]=+1  class[1]=+2  class[2]=-1  class[3..9]=0
--    SUM_BITS=6 packing:
--      word0 = 0x0003_F081   word1 = 0x0000_0000
--
--  Run 2  (Specialist 0):
--    class[5]=+3  class[8]=-3  all others=0
--    class[5] = 0b000011 spans word0[31:30] and word1[3:0]
--    class[8] = 0b111101 (-3 in 6-bit signed) sits in word1[21:16]
--      word0 = 0xC000_0000   word1 = 0x003D_0000
--
-- ── BRAM layout (word addresses) ─────────────────────────────────────────────
--  Specialist k base  = k * SPCLST_WORDS_C    (0=0, 1=624, 2=1248, 3=1872)
--  Weight region      : base + clause*NUM_CLASSES + class   (80 words)
--  Include region     : base + WGHT_WORDS_C + clause*INC_WORDS_C + word
--                       (8 clauses * 68 words = 544 words)
--  The IP now sends BYTE addresses = word_address * 4; the model divides
--  incoming addresses by 4 to recover the word index.
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

    ---------------------------------------------------------------------------
    -- Timing
    ---------------------------------------------------------------------------
    constant CLK_PERIOD         : time    := 10 ns;
    constant HANDSHAKE_TIMEOUT  : natural := 100_000;  -- clock cycles

    ---------------------------------------------------------------------------
    -- Architecture constants (mirror clauses.vhd)
    ---------------------------------------------------------------------------
    constant FEAT_BITS_C     : positive := 2*POS_BITS + 3*PS3*PS3*ENC_BITS;
    constant LIT_BITS_C      : positive := 2 * FEAT_BITS_C;
    constant WGHT_BITS_C     : positive := clog2(MAX_WEIGHT) + 2;
    constant SUM_BITS_C      : positive := clog2(MAX_WEIGHT * NUM_CLAUSES) + 1;
    constant WGHT_WORDS_C    : positive := NUM_CLAUSES * NUM_CLASSES;
    constant INC_WORDS_C     : positive := (LIT_BITS_C + 31) / 32;
    constant SPCLST_WORDS_C  : positive := WGHT_WORDS_C + NUM_CLAUSES * INC_WORDS_C;
    constant BRAM_DEPTH_C    : positive := NUM_SPECIALISTS * SPCLST_WORDS_C;
    constant NUM_PIXELS_C    : positive := IMG_SIZE * IMG_SIZE;
    constant CS_WORDS_C      : positive := CS_NUM_WORDS;   -- 2

    ---------------------------------------------------------------------------
    -- DUT ports
    ---------------------------------------------------------------------------
    signal clk            : std_logic := '0';
    signal n_reset        : std_logic := '0';
    signal wr_ready_intr  : std_logic;

    signal bram_addr      : std_logic_vector(BRAM_ADDR_WIDTH - 1 downto 0);
    signal bram_en        : std_logic;
    signal bram_data      : std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0)
                                := (others => '0');

    -- gpio_in[4:1] = one-hot specialist select;  gpio_in[0] = valid
    signal gpio_in        : std_logic_vector(4 downto 0) := (others => '0');
    signal gpio_out       : std_logic_vector(0 downto 0);

    signal s_axis_tdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tvalid  : std_logic := '0';
    signal s_axis_tready  : std_logic;
    signal s_axis_tlast   : std_logic := '0';

    signal m_axis_tdata   : std_logic_vector(CS_WORD_WIDTH - 1 downto 0);
    signal m_axis_tvalid  : std_logic;
    signal m_axis_tready  : std_logic := '1';
    signal m_axis_tlast   : std_logic;

    ---------------------------------------------------------------------------
    -- BRAM model
    --   Word-indexed array; incoming address is a BYTE address (word*4)
    --   because clauses.vhd now applies shift_left(..., 2) after the fix.
    --   1-cycle read latency: address registered on rising edge, data driven
    --   combinatorially from the registered address (Xilinx BRAM, no output
    --   register).
    ---------------------------------------------------------------------------
    type bram_t is array (0 to BRAM_DEPTH_C - 1) of
                      std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0);

    signal bram_mem    : bram_t := (others => (others => '0'));
    signal bram_addr_r : std_logic_vector(BRAM_ADDR_WIDTH - 1 downto 0)
                             := (others => '0');
    signal bram_en_r   : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Test infrastructure
    ---------------------------------------------------------------------------
    signal bram_err_seen : boolean := false;
    
    
begin

    ---------------------------------------------------------------------------
    -- Clock
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------------
    dut : entity work.inference_module
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
    -- BRAM pipeline: registered address, combinatorial output
    -- Byte address from the IP -> divide by 4 -> word index into bram_mem
    ---------------------------------------------------------------------------
    p_bram_pipe : process (clk)
    begin
        if rising_edge(clk) then
            bram_addr_r <= bram_addr;
            bram_en_r   <= bram_en;
        end if;
    end process;

    bram_data <=
        bram_mem(to_integer(unsigned(bram_addr_r)) / 4)
            when (bram_en_r = '1' and
                  to_integer(unsigned(bram_addr_r)) / 4 < BRAM_DEPTH_C)
            else (others => '0');

    ---------------------------------------------------------------------------
    -- BRAM address monitor
    --   Fires an error if, during a BRAM read, the byte address is:
    --     (a) not 4-byte aligned  -> shift_left fix not applied
    --     (b) beyond BRAM_DEPTH_C words
    ---------------------------------------------------------------------------
    p_bram_monitor : process (clk)
        variable word_idx : natural;
    begin
        if rising_edge(clk) then
            if bram_en_r = '1' then
                if unsigned(bram_addr_r(1 downto 0)) /= 0 then
                    report "BRAM MONITOR ERROR: unaligned byte address 0x" &
                           to_hstring(bram_addr_r) &
                           " -- bram_addr_out shift_left fix not applied"
                    severity error;
                    bram_err_seen <= true;
                end if;
                word_idx := to_integer(unsigned(bram_addr_r)) / 4;
                if word_idx >= BRAM_DEPTH_C then
                    report "BRAM MONITOR ERROR: word index " &
                           integer'image(word_idx) &
                           " out of range [0, " &
                           integer'image(BRAM_DEPTH_C - 1) & "]"
                    severity error;
                    bram_err_seen <= true;
                end if;
            end if;
        end if;
    end process;


    ---------------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------------
    p_stim : process
        variable total_errors  : natural := 0;
        variable wr_ready_seen : boolean := false;
        -----------------------------------------------------------------------
        -- BRAM helpers
        -----------------------------------------------------------------------

        -- Write one weight to bram_mem using WORD indexing.
        -- spec_idx : 0-3
        -- clause_i : 0 to NUM_CLAUSES-1
        -- class_j  : 0 to NUM_CLASSES-1
        -- w        : signed value in range [-MAX_WEIGHT, MAX_WEIGHT]
        procedure set_weight (
            spec_idx : in natural;
            clause_i : in natural;
            class_j  : in natural;
            w        : in integer
        ) is
            variable word_addr : natural;
            variable word_val  : std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0);
        begin
            word_addr := spec_idx * SPCLST_WORDS_C
                       + clause_i * NUM_CLASSES
                       + class_j;
            word_val  := (others => '0');
            word_val(WGHT_BITS_C - 1 downto 0) :=
                std_logic_vector(to_signed(w, WGHT_BITS_C));
            bram_mem(word_addr) <= word_val;
        end procedure;

        -- Set every n_inc word in spec_idx's include region to 0xFFFFFFFF
        -- (all literals excluded -> every clause unconditionally fires).
        procedure set_all_excluded (spec_idx : in natural) is
            variable base : natural;
        begin
            base := spec_idx * SPCLST_WORDS_C + WGHT_WORDS_C;
            for c in 0 to NUM_CLAUSES - 1 loop
                for w in 0 to INC_WORDS_C - 1 loop
                    bram_mem(base + c * INC_WORDS_C + w) <= (others => '1');
                end loop;
            end loop;
        end procedure;

        -----------------------------------------------------------------------
        -- GPIO handshake
        --   Mirrors the exact sequence the PS7 runs via AXI-GPIO:
        --     1. Poll CH1 (gpio_out[0]) until '1'  (request asserted in S_IDLE)
        --     2. Write CH2 (gpio_in) = one-hot select | valid
        --     3. Poll CH1 until '0'  (hardware latched select, now in S_LOAD)
        --     4. Clear CH2
        --   spec_idx selects which of the 4 specialists to activate.
        -----------------------------------------------------------------------
        procedure gpio_handshake (spec_idx : in natural) is
            variable sel     : std_logic_vector(3 downto 0) := (others => '0');
            variable timeout : natural;
        begin
            sel := (others => '0');
            sel(spec_idx) := '1';

            -- Step 1: wait for request
            timeout := 0;
            while gpio_out(0) = '0' loop
                wait until rising_edge(clk);
                timeout := timeout + 1;
                assert timeout < HANDSHAKE_TIMEOUT
                    report "TIMEOUT: gpio_out request never asserted (spec " &
                           integer'image(spec_idx) & ")"
                    severity failure;
            end loop;

            -- Step 2: assert select + valid
            -- gpio_in[4:1] = one-hot select,  gpio_in[0] = valid
            gpio_in <= sel & '1';
            wait until rising_edge(clk);

            -- Step 3: wait for request to deassert
            -- In practice this happens in the same cycle as the assertion
            -- because the FSM transitions to S_LOAD combinatorially, but the
            -- loop handles any simulator delta ordering.
            timeout := 0;
            while gpio_out(0) = '1' loop
                wait until rising_edge(clk);
                timeout := timeout + 1;
                assert timeout < HANDSHAKE_TIMEOUT
                    report "TIMEOUT: gpio_out request never deasserted (spec " &
                           integer'image(spec_idx) & ")"
                    severity failure;
            end loop;

            -- Step 4: deassert
            gpio_in <= (others => '0');

            report "  GPIO handshake complete (spec " &
                   integer'image(spec_idx) & ", S_LOAD started)."
            severity note;
        end procedure;

        -----------------------------------------------------------------------
        -- Pixel streaming
        --   Models the DMA MM2S burst.  Each pixel word carries three
        --   distinct 8-bit channel values in [23:16], [15:8], [7:0] matching
        --   the inference_module port map.  Backpressure (s_axis_tready='0')
        --   is handled by the AXI handshake loop; it occurs naturally while
        --   the line-buffer excess counter is saturated and during S_LOAD.
        -----------------------------------------------------------------------
        procedure stream_pixels is
            variable c0_v    : std_logic_vector(7 downto 0);
            variable c1_v    : std_logic_vector(7 downto 0);
            variable c2_v    : std_logic_vector(7 downto 0);
            variable timeout : natural;
        begin
            for px_idx in 0 to NUM_PIXELS_C - 1 loop
                c0_v := std_logic_vector(
                    to_unsigned(  px_idx          mod 256, 8));
                c1_v := std_logic_vector(
                    to_unsigned( (px_idx +  85)   mod 256, 8));
                c2_v := std_logic_vector(
                    to_unsigned( (px_idx + 171)   mod 256, 8));

                s_axis_tdata  <= x"00" & c0_v & c1_v & c2_v;
                s_axis_tvalid <= '1';
                s_axis_tlast  <=
                    '1' when px_idx = NUM_PIXELS_C - 1 else '0';

                -- AXI handshake: hold until accepted
                timeout := 0;
                loop
                    wait until rising_edge(clk);
                    if wr_ready_intr = '1' then
                        wr_ready_seen := true;
                    end if;
                    exit when s_axis_tready = '1';
                    timeout := timeout + 1;
                    assert timeout < HANDSHAKE_TIMEOUT
                        report "TIMEOUT: s_axis_tready never asserted"
                        severity failure;
                end loop;
            end loop;

            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';
        end procedure;

        -----------------------------------------------------------------------
        -- Class-sum reception and protocol verification
        --   With m_axis_tready='1', the S_STREAM state machine drives two
        --   back-to-back words:
        --     cycle A  : tvalid='1', tdata=word0, tlast='0', tready='1'
        --     cycle A+1: tvalid='1', tdata=word1, tlast='1', tready='1'
        --     cycle A+2: tvalid='0'  (state -> S_IDLE)
        --   Any deviation from this pattern is reported as a protocol error.
        -----------------------------------------------------------------------
        procedure receive_and_check (
            run_label  : in string;
            exp_word0  : in std_logic_vector(CS_WORD_WIDTH - 1 downto 0);
            exp_word1  : in std_logic_vector(CS_WORD_WIDTH - 1 downto 0)
        ) is
            variable got_word0 : std_logic_vector(CS_WORD_WIDTH - 1 downto 0);
            variable got_word1 : std_logic_vector(CS_WORD_WIDTH - 1 downto 0);
            variable cs_raw    : std_logic_vector(2*CS_WORD_WIDTH - 1 downto 0);
            variable cs_val    : integer;
            variable timeout   : natural;
            variable l         : line;
            variable pass      : boolean := true;
        begin
            --------------------------------
            -- Word 0
            --------------------------------
            timeout := 0;
            loop
                wait until rising_edge(clk);
                if wr_ready_intr = '1' then
                    wr_ready_seen := true;
                end if;                
                exit when m_axis_tvalid = '1';
                timeout := timeout + 1;
                assert timeout < HANDSHAKE_TIMEOUT
                    report "[" & run_label & "] TIMEOUT: tvalid never asserted"
                    severity failure;
            end loop;

            got_word0 := m_axis_tdata;

            if m_axis_tlast /= '0' then
                report "[" & run_label & "] PROTOCOL: tlast='1' on word 0" severity error;
                pass := false;
            end if;

            --------------------------------
            -- Word 1 (must follow immediately)
            --------------------------------
            wait until rising_edge(clk);
            if wr_ready_intr = '1' then
                wr_ready_seen := true;
            end if;
            if m_axis_tvalid /= '1' then
                report "[" & run_label &
                       "] PROTOCOL: tvalid gap between word 0 and word 1" severity error;
                pass := false;
            end if;

            got_word1 := m_axis_tdata;

            if m_axis_tlast /= '1' then
                report "[" & run_label & "] PROTOCOL: tlast='0' on word 1" severity error;
                pass := false;
            end if;

            --------------------------------
            -- tvalid must deassert after word-1 handshake
            --------------------------------
            wait until rising_edge(clk);
            if wr_ready_intr = '1' then
                wr_ready_seen := true;
            end if;
            if m_axis_tvalid /= '0' then
                report "[" & run_label &
                       "] PROTOCOL: tvalid still '1' one cycle after tlast" severity error;
                pass := false;
            end if;

            --------------------------------
            -- Decode and print
            --------------------------------
            cs_raw := got_word1 & got_word0;
            write(l, string'("[") & run_label & string'("] Class sums:"));
            writeline(output, l);
            for j in 0 to NUM_CLASSES - 1 loop
                cs_val := to_integer(
                    signed(cs_raw((j+1)*SUM_BITS_C - 1 downto j*SUM_BITS_C)));
                write(l, string'("    class[") & integer'image(j) &
                         string'("] = ") & integer'image(cs_val));
                writeline(output, l);
            end loop;

            report "[" & run_label & "] word0 = 0x" & to_hstring(got_word0) &
                   "  (expected 0x" & to_hstring(exp_word0) & ")"
            severity note;
            report "[" & run_label & "] word1 = 0x" & to_hstring(got_word1) &
                   "  (expected 0x" & to_hstring(exp_word1) & ")"
            severity note;

            --------------------------------
            -- Value assertions
            --------------------------------
            if got_word0 /= exp_word0 then
                report "[" & run_label & "] FAIL word0: got 0x" &
                       to_hstring(got_word0) &
                       ", expected 0x" & to_hstring(exp_word0)
                severity error;
                pass := false;
            end if;

            if got_word1 /= exp_word1 then
                report "[" & run_label & "] FAIL word1: got 0x" &
                       to_hstring(got_word1) &
                       ", expected 0x" & to_hstring(exp_word1)
                severity error;
                pass := false;
            end if;

            if pass then
                report "[" & run_label & "] PASS." severity note;
            else
                total_errors := total_errors + 1;
            end if;
        end procedure;

        -----------------------------------------------------------------------
        -- Full inference run
        --   GPIO handshake -> pixel stream -> class-sum check
        --   Also verifies wr_ready_intr fired and no BRAM addressing errors.
        -----------------------------------------------------------------------
        procedure run_inference (
            run_label  : in string;
            spec_idx   : in natural;
            exp_word0  : in std_logic_vector(CS_WORD_WIDTH - 1 downto 0);
            exp_word1  : in std_logic_vector(CS_WORD_WIDTH - 1 downto 0)
        ) is
        begin
            report "" severity note;
            report "=====================================================" severity note;
            report " " & run_label &
                   " : specialist " & integer'image(spec_idx) severity note;
            report "=====================================================" severity note;

            wait until rising_edge(clk);   -- let flag settle

            -- GPIO handshake (models AXI-GPIO PS7 sequence)
            gpio_handshake(spec_idx);

            -- Brief gap: models the time between GPIO deassert and DMA arm
            -- in software (a few AXI GP0 transactions).
            for i in 0 to 3 loop
                wait until rising_edge(clk);
            end loop;

            -- Stream all pixels (DMA MM2S)
            report "  Streaming " & integer'image(NUM_PIXELS_C) &
                   " pixels..." severity note;
            stream_pixels;
            report "  All pixels sent." severity note;

            -- Receive class sums (DMA S2MM) and verify
            receive_and_check(run_label, exp_word0, exp_word1);

            -- wr_ready_intr must have fired at least once during this run
            assert wr_ready_seen
                report "[" & run_label &
                       "] FAIL: wr_ready_intr never asserted during inference"
                severity error;

            -- No BRAM address monitor errors
            assert not bram_err_seen
                report "[" & run_label & "] FAIL: BRAM address monitor flagged an error"
                severity error;

            -- Small inter-run gap (hardware returns to S_IDLE)
            for i in 0 to 4 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        ---------------------------------------------------------------------------
        -- Main test sequence
        ---------------------------------------------------------------------------

    begin

        -----------------------------------------------------------------------
        -- Initialise BRAM
        --
        -- Specialist 3  (base word 1872, one-hot "1000", 7x7 patches):
        --   w(0,0)=+1  w(1,1)=+2  w(2,2)=-1  rest=0
        --   n_inc = 0xFFFFFFFF everywhere -> all clauses always fire
        --   Expected: class[0]=+1  class[1]=+2  class[2]=-1  class[3..9]=0
        --   word0 = 0x0003_F081   word1 = 0x0000_0000
        -----------------------------------------------------------------------
        set_weight(3, 0, 0,  1);
        set_weight(3, 1, 1,  2);
        set_weight(3, 2, 2, -1);
        set_all_excluded(3);

        -----------------------------------------------------------------------
        -- Specialist 0  (base word 0, one-hot "0001", 3x3 patches):
        --   w(3,5)=+3  w(4,8)=-3  rest=0
        --   n_inc = 0xFFFFFFFF everywhere -> all clauses always fire
        --   Expected: class[5]=+3  class[8]=-3  all others=0
        --
        --   SUM_BITS=6 packing for class[5]=3 and class[8]=-3:
        --     class[5]=0b000011 occupies cs_data_flat[35:30]
        --       lower 2 bits  -> word0[31:30] = 0b11  -> word0 = 0xC000_0000
        --       upper 4 bits  -> word1[3:0]   = 0b0000
        --     class[8]=0b111101 (-3 two's complement) in cs_data_flat[53:48]
        --       -> word1[21:16] = 0b111101              -> word1 = 0x003D_0000
        -----------------------------------------------------------------------
        set_weight(0, 3, 5,  3);
        set_weight(0, 4, 8, -3);
        set_all_excluded(0);

        -----------------------------------------------------------------------
        -- Reset sequence
        -----------------------------------------------------------------------
        n_reset       <= '0';
        gpio_in       <= (others => '0');
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';
        m_axis_tready <= '1';   -- DMA S2MM always accepts

        wait for 15 * CLK_PERIOD;
        wait until rising_edge(clk);

        n_reset <= '1';
        report "Reset released." severity note;

        -- Conservative margin: let all FSMs complete their S_RESET -> S_IDLE
        -- transition and settle spclst_valid_prev / ps_valid_prev to '0'.
        for i in 0 to 9 loop
            wait until rising_edge(clk);
        end loop;

        -----------------------------------------------------------------------
        -- Run 1 : Specialist 3  (7x7 patches)
        -----------------------------------------------------------------------
        run_inference(
            run_label  => "Run1:Spec3",
            spec_idx   => 3,
            exp_word0  => x"0003F081",
            exp_word1  => x"00000000"
        );

        -----------------------------------------------------------------------
        -- Run 2 : Specialist 0  (3x3 patches, different weight pattern)
        -----------------------------------------------------------------------
        run_inference(
            run_label  => "Run2:Spec0",
            spec_idx   => 0,
            exp_word0  => x"C0000000",
            exp_word1  => x"003D0000"
        );

        -----------------------------------------------------------------------
        -- Run 3 : Specialist 3 again
        --   Specifically tests the load_ctr reset fix (Bug 2).
        --   Before the fix, load_ctr remained at SPCLST_WORDS_C=624 after
        --   Run 1, causing S_LOAD to be skipped entirely on re-entry, leaving
        --   the clause module with stale (or zero-initialised) parameters.
        --   After the fix this run must produce results identical to Run 1.
        -----------------------------------------------------------------------
        run_inference(
            run_label  => "Run3:Spec3",
            spec_idx   => 3,
            exp_word0  => x"0003F081",
            exp_word1  => x"00000000"
        );

        -----------------------------------------------------------------------
        -- Final result
        -----------------------------------------------------------------------
        wait for 20 * CLK_PERIOD;

        report "" severity note;
        report "=====================================================" severity note;
        if total_errors = 0 and not bram_err_seen then
            report " ALL TESTS PASSED." severity note;
        else
            report " TESTS FINISHED WITH " & integer'image(total_errors) &
                   " ERROR(S)." severity error;
        end if;
        report "=====================================================" severity note;

        std.env.finish;

    end process p_stim;

end architecture sim;