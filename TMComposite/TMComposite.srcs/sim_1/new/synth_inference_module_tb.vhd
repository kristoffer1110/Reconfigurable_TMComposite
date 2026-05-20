----------------------------------------------------------------------------------
-- Testbench: inference_module_tb
--
-- Sequence per inference pass:
--   1.  Reset
--   2.  BRAM model responds to bram_en_out / bram_addr_out with trained parameters
--   3.  Wait for gpio_out(0) (spclst_request AND ps_request both high)
--   4.  Send specialist one-hot via gpio_in
--   5.  Stream a full IMG_SIZE x IMG_SIZE image respecting s_axis_tready
--   6.  Wait for cs_valid_intr, print class sums
--   7.  Repeat for a second specialist
--   8.  Mid-stream reset recovery test
--
-- BRAM layout (matches clauses.vhd):
--   [0 .. WGHT_WORDS-1]                  weight words (one per clause*class)
--   [WGHT_WORDS .. SPCLST_WORDS-1]       n_inc words  (INC_WORDS per clause)
--   Each specialist block is SPCLST_WORDS wide, base = specialist_index * SPCLST_WORDS
--
-- Test values:
--   Specialist s has weight = s+1 for all clause/class entries
--   n_inc = all-ones so all literals are included in every clause
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.math_pkg.all;
use work.types_pkg.all;
use work.functions_pkg.all;

entity synth_inference_module_tb is
end synth_inference_module_tb;

architecture sim of synth_inference_module_tb is

    ---------------------------------------------------------------------------
    -- Constants (mirror types_pkg)
    ---------------------------------------------------------------------------
    constant CLK_PERIOD  : time := 10 ns;

    constant C_IMG_SIZE  : positive := IMG_SIZE;
    constant C_PS0       : positive := PS0;
    constant C_PS1       : positive := PS1;
    constant C_PS2       : positive := PS2;
    constant C_PS3       : positive := PS3;
    constant C_PX_BITS   : positive := PX_BITS;
    constant C_POS_BITS  : positive := POS_BITS;
    constant C_ENC_BITS  : positive := ENC_BITS;
    constant C_NUM_SPEC  : positive := NUM_SPECIALISTS;
    constant C_NUM_CL    : positive := NUM_CLAUSES;
    constant C_NUM_CLS   : positive := NUM_CLASSES;
    constant C_MAX_W     : positive := MAX_WEIGHT;
    constant C_BRAM_AW   : positive := BRAM_ADDR_WIDTH;
    constant C_BRAM_DW   : positive := BRAM_DATA_WIDTH;
    constant C_AXI_RW    : positive := AXI_REG_WIDTH;
    constant C_AXI_NR    : positive := AXI_NUM_REGS;

    -- Derived, matching clauses.vhd
    constant C_SUM_BITS  : positive := clog2(C_MAX_W * C_NUM_CL) + 1;
    constant C_WGHT_BITS : positive := clog2(C_MAX_W) + 2;
    constant C_FEAT_BITS : positive := 2*C_POS_BITS + 3*C_PS3*C_PS3*C_ENC_BITS;
    constant C_LIT_BITS  : positive := 2 * C_FEAT_BITS;
    constant C_INC_WORDS : positive := (C_LIT_BITS + 31) / 32;
    constant C_WGHT_WORDS: positive := C_NUM_CL * C_NUM_CLS;
    constant C_SPCLST_W  : positive := C_WGHT_WORDS + C_NUM_CL * C_INC_WORDS;
    constant BRAM_DEPTH  : positive := 4 * C_SPCLST_W;

    ---------------------------------------------------------------------------
    -- BRAM model type and initialisation
    ---------------------------------------------------------------------------
    type bram_t is array (0 to BRAM_DEPTH - 1) of
        STD_LOGIC_VECTOR(C_BRAM_DW - 1 downto 0);

    -- Specialist s: weight = s+1, n_inc = all-ones
    function init_bram return bram_t is
        variable mem  : bram_t := (others => (others => '0'));
        variable base : integer;
    begin
        for s in 0 to 3 loop
            base := s * C_SPCLST_W;
            -- Weight words: constant value (s+1) in lower WGHT_BITS
            for w in 0 to C_WGHT_WORDS - 1 loop
                mem(base + w) :=
                    std_logic_vector(to_signed(s + 1, C_BRAM_DW));
            end loop;
            -- n_inc words: all-ones
            for w in 0 to C_NUM_CL * C_INC_WORDS - 1 loop
                mem(base + C_WGHT_WORDS + w) := (others => '1');
            end loop;
        end loop;
        return mem;
    end function;

    ---------------------------------------------------------------------------
    -- DUT signals
    ---------------------------------------------------------------------------
    signal clk           : STD_LOGIC := '0';
    signal n_reset       : STD_LOGIC := '0';

    signal wr_ready_intr : STD_LOGIC;
    signal cs_valid_intr : STD_LOGIC;

    signal bram_addr     : STD_LOGIC_VECTOR(C_BRAM_AW - 1 downto 0);
    signal bram_en       : STD_LOGIC;
    signal bram_data     : STD_LOGIC_VECTOR(C_BRAM_DW - 1 downto 0)
                             := (others => '0');

    -- gpio_in: bit 0 = spclst_valid, bits NUM_SPEC downto 1 = one-hot data
    signal gpio_in       : STD_LOGIC_VECTOR(C_NUM_SPEC downto 0) := (others => '0');
    signal gpio_out      : STD_LOGIC_VECTOR(0 downto 0);

    signal s_axis_tdata  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal s_axis_tvalid : STD_LOGIC := '0';
    signal s_axis_tready : STD_LOGIC;
    signal s_axis_tlast  : STD_LOGIC := '0';

    signal cs_data_out   : STD_LOGIC_VECTOR(C_AXI_NR * C_AXI_RW - 1 downto 0);

    ---------------------------------------------------------------------------
    -- Helpers
    ---------------------------------------------------------------------------

    -- Send one pixel (3 channels in bits 23:0), respecting tready backpressure
    procedure send_pixel (
        constant c0  : in natural;
        constant c1  : in natural;
        constant c2  : in natural;
        signal clk   : in  STD_LOGIC;
        signal rdy   : in  STD_LOGIC;
        signal vld   : out STD_LOGIC;
        signal dat   : out STD_LOGIC_VECTOR(31 downto 0)
    ) is begin
        if rdy = '0' then
            wait until rdy = '1';
        end if;
        wait until rising_edge(clk);
        vld              <= '1';
        dat(31 downto 24)<= (others => '0');
        dat(23 downto 16)<= std_logic_vector(to_unsigned(c0 mod 256, 8));
        dat(15 downto  8)<= std_logic_vector(to_unsigned(c1 mod 256, 8));
        dat( 7 downto  0)<= std_logic_vector(to_unsigned(c2 mod 256, 8));
        wait until rising_edge(clk);
        vld <= '0';
        dat <= (others => '0');
    end procedure;

    -- Stream a full IMG_SIZE x IMG_SIZE ramp image
    procedure stream_image (
        signal clk  : in  STD_LOGIC;
        signal rdy  : in  STD_LOGIC;
        signal vld  : out STD_LOGIC;
        signal dat  : out STD_LOGIC_VECTOR(31 downto 0)
    ) is begin
        for row in 0 to C_IMG_SIZE - 1 loop
            for col in 0 to C_IMG_SIZE - 1 loop
                send_pixel(col, row, (col + row) mod 256,
                           clk, rdy, vld, dat);
            end loop;
        end loop;
        report "Image stream complete (" &
               integer'image(C_IMG_SIZE) & "x" &
               integer'image(C_IMG_SIZE) & ")." severity note;
    end procedure;

    -- Wait for gpio_out(0) request then send specialist one-hot + valid pulse
    procedure send_specialist (
        constant one_hot : in  STD_LOGIC_VECTOR(C_NUM_SPEC - 1 downto 0);
        constant lbl     : in  string;
        signal clk       : in  STD_LOGIC;
        signal req       : in  STD_LOGIC_VECTOR(0 downto 0);
        signal gpio      : out STD_LOGIC_VECTOR(C_NUM_SPEC downto 0)
    ) is begin
        if req(0) = '0' then
            wait until req(0) = '1';
        end if;
        wait until rising_edge(clk);
        report "Sending specialist: " & lbl severity note;
        gpio(C_NUM_SPEC downto 1) <= one_hot;
        gpio(0)                   <= '1';   -- valid
        wait until rising_edge(clk);
        gpio <= (others => '0');
    end procedure;

    -- Print all class sums extracted from the AXI register bus
    procedure print_sums (
        constant dat : in STD_LOGIC_VECTOR(C_AXI_NR * C_AXI_RW - 1 downto 0);
        constant lbl : in string
    ) is
        variable s : signed(C_SUM_BITS - 1 downto 0);
    begin
        report "=== Class sums: " & lbl & " ===" severity note;
        for i in 0 to C_NUM_CLS - 1 loop
            s := signed(dat((i + 1) * C_SUM_BITS - 1 downto i * C_SUM_BITS));
            report "  class(" & integer'image(i) & ") = " &
                   integer'image(to_integer(s)) severity note;
        end loop;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- BRAM model: single-cycle registered read, matching Xilinx BRAM behaviour
    ---------------------------------------------------------------------------
    bram_model : process(clk)
        constant mem   : bram_t := init_bram;
        variable addr_i : integer;
    begin
        if rising_edge(clk) then
            if bram_en = '1' then
                addr_i := to_integer(unsigned(bram_addr));
                if addr_i < BRAM_DEPTH then
                    bram_data <= mem(addr_i);
                else
                    bram_data <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    dut : entity work.inference_module
        port map (
            clk             => clk,
            n_reset         => n_reset,
            wr_ready_intr   => wr_ready_intr,
            cs_valid_intr   => cs_valid_intr,
            bram_addr_out   => bram_addr,
            bram_en_out     => bram_en,
            bram_data_in    => bram_data,
            gpio_in         => gpio_in,
            gpio_out        => gpio_out,
            s_axis_tdata    => s_axis_tdata,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tready   => s_axis_tready,
            s_axis_tlast    => s_axis_tlast,
            cs_data_out     => cs_data_out
        );

    ---------------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------------
    stim : process
    begin

        -----------------------------------------------------------------------
        -- 1. Reset for 10 cycles
        -----------------------------------------------------------------------
        report "Applying reset..." severity note;
        n_reset <= '0';
        wait for CLK_PERIOD * 10;
        wait until rising_edge(clk);
        n_reset <= '1';
        report "Reset released." severity note;

        -----------------------------------------------------------------------
        -- 2. Pass 1 - specialist 0 ("0001"), w=1
        --    After reset, clauses goes S_RESET->S_SETUP and asserts
        --    spclst_request which ANDs with ps_request onto gpio_out(0).
        --    We wait for that, then send the specialist.
        --    clauses then loads from BRAM (S_LOAD), enters S_ACCUMULATE,
        --    asserts patch_ready which propagates back as wr_ready_intr
        --    once patches_v5 is also ready.
        -----------------------------------------------------------------------
        send_specialist("0001", "S0 w=1", clk, gpio_out, gpio_in);

        report "Waiting for wr_ready_intr (BRAM load + patch ready)..." severity note;
        if wr_ready_intr = '0' then
            wait until wr_ready_intr = '1';
        end if;

        stream_image(clk, s_axis_tready, s_axis_tvalid, s_axis_tdata);

        report "Waiting for cs_valid_intr..." severity note;
        if cs_valid_intr = '0' then
            wait until cs_valid_intr = '1';
        end if;
        wait until rising_edge(clk);
        print_sums(cs_data_out, "S0 w=1 - expect each class_sum <= 4");

        -----------------------------------------------------------------------
        -- 3. Pass 2 - specialist 1 ("0010"), w=2
        --    After S_RESET_CLAUSES, clauses re-enters S_SETUP and raises
        --    spclst_request_out again.
        -----------------------------------------------------------------------
        send_specialist("0010", "S1 w=2", clk, gpio_out, gpio_in);

        report "Waiting for wr_ready_intr..." severity note;
        if wr_ready_intr = '0' then
            wait until wr_ready_intr = '1';
        end if;

        stream_image(clk, s_axis_tready, s_axis_tvalid, s_axis_tdata);

        report "Waiting for cs_valid_intr..." severity note;
        if cs_valid_intr = '0' then
            wait until cs_valid_intr = '1';
        end if;
        wait until rising_edge(clk);
        print_sums(cs_data_out, "S1 w=2 - expect each class_sum <= 8");

        -----------------------------------------------------------------------
        -- 4. Mid-stream reset recovery
        -----------------------------------------------------------------------
        report "Starting S2 w=3, resetting mid-stream..." severity note;
        send_specialist("0100", "S2 w=3", clk, gpio_out, gpio_in);

        if wr_ready_intr = '0' then
            wait until wr_ready_intr = '1';
        end if;

        -- Stream only half the image then assert reset
        for row in 0 to (C_IMG_SIZE / 2) - 1 loop
            for col in 0 to C_IMG_SIZE - 1 loop
                send_pixel(col, row, col,
                           clk, s_axis_tready, s_axis_tvalid, s_axis_tdata);
            end loop;
        end loop;

        report "Asserting mid-stream reset..." severity note;
        n_reset <= '0';
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk);
        n_reset <= '1';
        report "Reset released - verifying recovery..." severity note;

        -- System must re-request a specialist from scratch
        send_specialist("0001", "S0 post-reset w=1", clk, gpio_out, gpio_in);

        if wr_ready_intr = '0' then
            wait until wr_ready_intr = '1';
        end if;

        stream_image(clk, s_axis_tready, s_axis_tvalid, s_axis_tdata);

        report "Waiting for cs_valid_intr post-reset..." severity note;
        if cs_valid_intr = '0' then
            wait until cs_valid_intr = '1';
        end if;
        wait until rising_edge(clk);
        print_sums(cs_data_out, "S0 post-reset w=1");

        -----------------------------------------------------------------------
        -- 5. Done
        -----------------------------------------------------------------------
        report "================================" severity note;
        report "Simulation complete."             severity note;
        report "================================" severity note;
        wait;

    end process stim;

    ---------------------------------------------------------------------------
    -- Watchdog: fail if simulation stalls
    ---------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 5 ms;
        report "WATCHDOG: simulation timed out!" severity failure;
    end process watchdog;

end sim;