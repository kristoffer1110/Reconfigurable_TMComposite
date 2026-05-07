----------------------------------------------------------------------------------
-- Testbench: inference_module_tb
--
-- Tests the full inference pipeline:
--   pixel_encoding -> patches_v5 -> clauses
--
-- Sequence:
--   1. Reset
--   2. Wait for gpio_request_out (both ps_request and spclst_request high)
--   3. Send specialist/patch-size selection via gpio
--   4. Stream a DATA_WIDTH x DATA_WIDTH ramp image pixel by pixel,
--      respecting px_ready_out backpressure
--   5. Wait for class_sums_valid_out
--   6. Acknowledge with class_sums_ready_in
--   7. Print all class sums to transcript
--   8. Repeat for a second specialist to verify reset and re-accumulation
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.math_pkg.all;
use work.types_pkg.all;
use work.functions_pkg.all;

entity inference_module_tb is
end inference_module_tb;

architecture sim of inference_module_tb is

    ---------------------------------------------------------------------------
    -- Constants matching types_pkg and inference_module defaults
    ---------------------------------------------------------------------------
    constant CLK_PERIOD      : time     := 10 ns;

    constant C_NUM_PS        : positive := 4;
    constant C_PS0           : positive := 3;
    constant C_PS1           : positive := 4;
    constant C_PS2           : positive := 5;
    constant C_PS3           : positive := 7;
    constant C_DATA_WIDTH    : positive := 32;
    constant C_PX_BITS       : positive := 8;
    constant C_POS_BITS      : positive := 29;
    constant C_ENC_BITS      : positive := 7;
    constant C_NUM_SPEC      : positive := NUM_SPECIALISTS;  -- 4
    constant C_NUM_CLAUSES   : positive := NUM_CLAUSES;       -- 10
    constant C_NUM_CLASSES   : positive := NUM_CLASSES;       -- 10
    constant C_MAX_WEIGHT    : positive := MAX_WEIGHT;         -- 4
    constant C_SUM_BITS      : positive := clog2(C_MAX_WEIGHT * C_NUM_CLAUSES) + 1;
    constant C_SUMS_WIDTH    : positive := C_NUM_CLASSES * C_SUM_BITS;

    ---------------------------------------------------------------------------
    -- DUT ports
    ---------------------------------------------------------------------------
    signal clk                  : STD_LOGIC := '0';
    signal reset                : STD_LOGIC := '1';

    signal dma_intr             : STD_LOGIC;

    signal gpio_data_in         : STD_LOGIC_VECTOR(C_NUM_PS - 1 downto 0) := (others => '0');
    signal gpio_valid_in        : STD_LOGIC := '0';
    signal gpio_request_out     : STD_LOGIC;

    signal px_c0_data_in        : STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0) := (others => '0');
    signal px_c1_data_in        : STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0) := (others => '0');
    signal px_c2_data_in        : STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0) := (others => '0');
    signal px_valid_in          : STD_LOGIC := '0';
    signal px_ready_out         : STD_LOGIC;

    signal class_sums_data_out  : STD_LOGIC_VECTOR(C_SUMS_WIDTH - 1 downto 0);
    signal class_sums_valid_out : STD_LOGIC;
    signal class_sums_ready_in  : STD_LOGIC := '0';

    ---------------------------------------------------------------------------
    -- Helper: send one pixel, respecting px_ready_out backpressure
    ---------------------------------------------------------------------------
    procedure send_pixel (
        constant c0_val  : in natural;
        constant c1_val  : in natural;
        constant c2_val  : in natural;
        signal   clk     : in  STD_LOGIC;
        signal   ready   : in  STD_LOGIC;
        signal   valid   : out STD_LOGIC;
        signal   c0      : out STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0);
        signal   c1      : out STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0);
        signal   c2      : out STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0)
    ) is begin
        -- Wait until downstream is ready
        if ready = '0' then
            wait until ready = '1';
        end if;
        wait until rising_edge(clk);
        valid <= '1';
        c0    <= std_logic_vector(to_unsigned(c0_val mod 256, C_PX_BITS));
        c1    <= std_logic_vector(to_unsigned(c1_val mod 256, C_PX_BITS));
        c2    <= std_logic_vector(to_unsigned(c2_val mod 256, C_PX_BITS));
        wait until rising_edge(clk);
        valid <= '0';
        c0    <= (others => '0');
        c1    <= (others => '0');
        c2    <= (others => '0');
    end procedure;

    ---------------------------------------------------------------------------
    -- Helper: stream a full DATA_WIDTH x DATA_WIDTH image
    ---------------------------------------------------------------------------
    procedure stream_image (
        signal clk    : in  STD_LOGIC;
        signal ready  : in  STD_LOGIC;
        signal valid  : out STD_LOGIC;
        signal c0     : out STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0);
        signal c1     : out STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0);
        signal c2     : out STD_LOGIC_VECTOR(C_PX_BITS - 1 downto 0)
    ) is begin
        for row in 0 to C_DATA_WIDTH - 1 loop
            for col in 0 to C_DATA_WIDTH - 1 loop
                send_pixel(col, row, (col + row), clk, ready, valid, c0, c1, c2);
            end loop;
        end loop;
        report "Image stream complete (" &
               integer'image(C_DATA_WIDTH) & "x" &
               integer'image(C_DATA_WIDTH) & " pixels)" severity note;
    end procedure;

    ---------------------------------------------------------------------------
    -- Helper: send a specialist/patch-size selection
    -- Waits for gpio_request_out before asserting valid
    ---------------------------------------------------------------------------
    procedure send_specialist (
        constant one_hot    : in  STD_LOGIC_VECTOR(C_NUM_PS - 1 downto 0);
        constant lbl        : in  string;
        signal   clk        : in  STD_LOGIC;
        signal   req        : in  STD_LOGIC;
        signal   data       : out STD_LOGIC_VECTOR(C_NUM_PS - 1 downto 0);
        signal   valid      : out STD_LOGIC
    ) is begin
        if req = '0' then
            wait until req = '1';
        end if;
        wait until rising_edge(clk);
        report "Sending specialist: " & lbl severity note;
        data  <= one_hot;
        valid <= '1';
        wait until rising_edge(clk);
        valid <= '0';
        data  <= (others => '0');
    end procedure;

    ---------------------------------------------------------------------------
    -- Helper: print all class sums from the output bus
    ---------------------------------------------------------------------------
    procedure print_class_sums (
        constant sums : in STD_LOGIC_VECTOR(C_SUMS_WIDTH - 1 downto 0);
        constant lbl: in string
    ) is
        variable s : signed(C_SUM_BITS - 1 downto 0);
    begin
        report "=== Class sums after " & lbl & " ===" severity note;
        for i in 0 to C_NUM_CLASSES - 1 loop
            s := signed(sums((i + 1) * C_SUM_BITS - 1 downto i * C_SUM_BITS));
            report "  class_sums(" & integer'image(i) & ") = " &
                   integer'image(to_integer(s)) severity note;
        end loop;
    end procedure;

begin

    ---------------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT instantiation
    ---------------------------------------------------------------------------
    dut : entity work.inference_module
        generic map (
            NUM_PS          => C_NUM_PS,
            PS0             => C_PS0,
            PS1             => C_PS1,
            PS2             => C_PS2,
            PS3             => C_PS3,
            DATA_WIDTH      => C_DATA_WIDTH,
            PX_BITS         => C_PX_BITS,
            POS_BITS        => C_POS_BITS,
            ENC_BITS        => C_ENC_BITS,
            NUM_SPECIALISTS => C_NUM_SPEC,
            NUM_CLAUSES     => C_NUM_CLAUSES,
            NUM_CLASSES     => C_NUM_CLASSES,
            MAX_WEIGHT      => C_MAX_WEIGHT
        )
        port map (
            clk                  => clk,
            reset                => reset,
            dma_intr             => dma_intr,
            gpio_data_in         => gpio_data_in,
            gpio_valid_in        => gpio_valid_in,
            gpio_request_out     => gpio_request_out,
            px_c0_data_in        => px_c0_data_in,
            px_c1_data_in        => px_c1_data_in,
            px_c2_data_in        => px_c2_data_in,
            px_valid_in          => px_valid_in,
            px_ready_out         => px_ready_out,
            class_sums_data_out  => class_sums_data_out,
            class_sums_valid_out => class_sums_valid_out,
            class_sums_ready_in  => class_sums_ready_in
        );

    ---------------------------------------------------------------------------
    -- Stimulus process
    ---------------------------------------------------------------------------
    stim : process
    begin

        -----------------------------------------------------------------------
        -- 1. Reset for 10 cycles
        -----------------------------------------------------------------------
        report "Applying reset..." severity note;
        reset <= '1';
        wait for CLK_PERIOD * 10;
        wait until rising_edge(clk);
        reset <= '0';
        report "Reset released." severity note;

        -----------------------------------------------------------------------
        -- 2. First inference pass: PS0 = 3x3 specialist ("0001")
        -----------------------------------------------------------------------
        send_specialist("0001", "PS0 3x3", clk, gpio_request_out,
                        gpio_data_in, gpio_valid_in);

        stream_image(clk, px_ready_out, px_valid_in,
                     px_c0_data_in, px_c1_data_in, px_c2_data_in);

        -- Wait for valid class sums
        report "Waiting for class_sums_valid_out..." severity note;
        if class_sums_valid_out = '0' then
            wait until class_sums_valid_out = '1';
        end if;
        wait until rising_edge(clk);

        print_class_sums(class_sums_data_out, "PS0 3x3");

        -- Acknowledge: hold ready for one cycle
        class_sums_ready_in <= '1';
        wait until rising_edge(clk);
        class_sums_ready_in <= '0';

        -----------------------------------------------------------------------
        -- 3. Second inference pass: PS1 = 4x4 specialist ("0010")
        --    gpio_request_out will go high again once clauses is ready
        -----------------------------------------------------------------------
        send_specialist("0010", "PS1 4x4", clk, gpio_request_out,
                        gpio_data_in, gpio_valid_in);

        stream_image(clk, px_ready_out, px_valid_in,
                     px_c0_data_in, px_c1_data_in, px_c2_data_in);

        report "Waiting for class_sums_valid_out..." severity note;
        if class_sums_valid_out = '0' then
            wait until class_sums_valid_out = '1';
        end if;
        wait until rising_edge(clk);

        print_class_sums(class_sums_data_out, "PS1 4x4");

        class_sums_ready_in <= '1';
        wait until rising_edge(clk);
        class_sums_ready_in <= '0';

        -----------------------------------------------------------------------
        -- 4. Test reset mid-stream: apply reset while streaming third image
        -----------------------------------------------------------------------
        report "Starting PS2 5x5, will reset mid-stream..." severity note;
        send_specialist("0100", "PS2 5x5", clk, gpio_request_out,
                        gpio_data_in, gpio_valid_in);

        -- Stream only half the image then reset
        for row in 0 to (C_DATA_WIDTH / 2) - 1 loop
            for col in 0 to C_DATA_WIDTH - 1 loop
                send_pixel(col, row, col, clk, px_ready_out, px_valid_in,
                           px_c0_data_in, px_c1_data_in, px_c2_data_in);
            end loop;
        end loop;

        report "Applying mid-stream reset..." severity note;
        reset <= '1';
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk);
        reset <= '0';
        report "Reset released, verifying recovery..." severity note;

        -- System should request a new specialist after reset
        send_specialist("0001", "PS0 3x3 (post-reset)", clk, gpio_request_out,
                        gpio_data_in, gpio_valid_in);

        stream_image(clk, px_ready_out, px_valid_in,
                     px_c0_data_in, px_c1_data_in, px_c2_data_in);

        report "Waiting for class_sums_valid_out after reset recovery..." severity note;
        if class_sums_valid_out = '0' then
            wait until class_sums_valid_out = '1';
        end if;
        wait until rising_edge(clk);

        print_class_sums(class_sums_data_out, "PS0 3x3 (post-reset)");

        class_sums_ready_in <= '1';
        wait until rising_edge(clk);
        class_sums_ready_in <= '0';

        -----------------------------------------------------------------------
        -- 5. Done
        -----------------------------------------------------------------------
        report "==============================" severity note;
        report "Simulation complete." severity note;
        report "==============================" severity note;
        wait;

    end process stim;

    ---------------------------------------------------------------------------
    -- Timeout watchdog: fail if simulation stalls for 2ms
    ---------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 2 ms;
        report "WATCHDOG: Simulation timed out!" severity failure;
    end process watchdog;

end sim;