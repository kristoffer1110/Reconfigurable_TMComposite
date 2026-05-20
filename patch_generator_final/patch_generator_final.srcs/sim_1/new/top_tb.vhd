----------------------------------------------------------------------------------
-- Testbench: top_tb
--
-- Drives the top-level patch generator IP exactly the way the PYNQ PS does:
--   - reset / GPIO handshake to select the patch size
--   - streams 1024 pixels via AXI-Stream (mimicking MM2S DMA)
--   - captures the AXI-Stream patch output (mimicking S2MM DMA)
--   - writes captured words to tb_output.txt for the Python parser
--
-- Input file  : pixel_input.txt   (one pixel per line, "C0 C1 C2" hex,
--                                  top-row major; produced by
--                                  scripts/1_generate_pixel_input.py)
-- Output file : tb_output.txt     (consumed by scripts/2_parse_tb_output.py)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

entity top_tb is
end top_tb;

architecture sim of top_tb is

    ---------------------------------------------------------------------------
    -- Constants - must match the IP's generics
    ---------------------------------------------------------------------------
    constant NUM_GPIO_IN     : positive := 5;
    constant NUM_GPIO_OUT    : positive := 1;
    constant NUM_PS          : positive := 4;
    constant PS0             : positive := 3;
    constant PS1             : positive := 4;
    constant PS2             : positive := 5;
    constant PS3             : positive := 7;
    constant IMG_SIZE        : positive := 32;
    constant PX_BITS         : positive := 8;
    constant ENC_BITS        : positive := PX_BITS - 1;            -- 7
    constant POS_BITS        : positive := IMG_SIZE - PS0;          -- 29

    constant NUM_PIXELS      : positive := IMG_SIZE * IMG_SIZE;     -- 1024

    -- Patch size to select (change to PS0..PS3 to test different sizes)
    constant PS              : positive := PS3;
    constant NUM_PATCHES     : positive := (IMG_SIZE - PS + 1) *
                                            (IMG_SIZE - PS + 1);

    -- WORDS_PER_PATCH must match axis_patch_out.vhd:
    --   ceil((2*POS_BITS + 3*PS3*PS3*ENC_BITS) / 32) = ceil(1087/32) = 34
    constant WORDS_PER_PATCH : positive := 34;

    constant CLK_PERIOD      : time := 10 ns;

    -- PS one-hot select (matches case in patches_v5.vhd)
    constant PS_SEL_3        : std_logic_vector(NUM_PS-1 downto 0) := "0001";
    constant PS_SEL_4        : std_logic_vector(NUM_PS-1 downto 0) := "0010";
    constant PS_SEL_5        : std_logic_vector(NUM_PS-1 downto 0) := "0100";
    constant PS_SEL_7        : std_logic_vector(NUM_PS-1 downto 0) := "1000";

    -- Choose PS_SEL value matching the PS constant above
    function ps_select(ps_in : positive)
        return std_logic_vector is
    begin
        case ps_in is
            when PS0    => return PS_SEL_3;
            when PS1    => return PS_SEL_4;
            when PS2    => return PS_SEL_5;
            when others => return PS_SEL_7;
        end case;
    end function;

    constant PS_SEL          : std_logic_vector(NUM_PS-1 downto 0)
                                    := ps_select(PS);

    -- GPIO bit layout (must match gpio_mapper.vhd):
    --   gpio_in[NUM_PS]      = ps_valid_in       (= bit 0 of an N-bit word)
    --   Wait - look more carefully:
    --     ps_data_out  <= gpio_in(NUM_IN-1 downto NUM_IN-NUM_PS);  -- bits 4..1
    --     ps_valid_out <= gpio_in(NUM_IN-NUM_PS-1);                -- bit 0
    --   So gpio_in is concatenated as PS_SEL & "1" (bit 0 = ps_valid).

    ---------------------------------------------------------------------------
    -- DUT signals
    ---------------------------------------------------------------------------
    signal clk            : std_logic := '0';
    signal n_reset        : std_logic := '0';                  -- start in reset
    signal wr_ready_intr  : std_logic;

    signal gpio_in        : std_logic_vector(4 downto 0) := (others => '0');
    signal gpio_out       : std_logic_vector(0 downto 0);

    -- AXI-Stream pixel input (DMA -> IP)
    signal s_axis_tdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tvalid  : std_logic := '0';
    signal s_axis_tready  : std_logic;
    signal s_axis_tlast   : std_logic := '0';

    -- AXI-Stream patch output (IP -> DMA)
    signal m_axis_tdata   : std_logic_vector(31 downto 0);
    signal m_axis_tvalid  : std_logic;
    signal m_axis_tready  : std_logic := '1';                  -- always ready
    signal m_axis_tlast   : std_logic;

    ---------------------------------------------------------------------------
    -- Pixel buffer types (kept simple; loaded by stim_proc on startup)
    ---------------------------------------------------------------------------
    type pixel_channel is array (0 to NUM_PIXELS-1) of integer range 0 to 255;
    signal capture_done  : boolean := false;

begin

    ---------------------------------------------------------------------------
    -- Clock
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------------
    DUT : entity work.top
        port map (
            clk           => clk,
            n_reset       => n_reset,
            wr_ready_intr => wr_ready_intr,
            gpio_in       => gpio_in,
            gpio_out      => gpio_out,
            s_axis_tdata  => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,
            m_axis_tdata  => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast  => m_axis_tlast
        );

    ---------------------------------------------------------------------------
    -- OUTPUT CAPTURE
    --
    -- Captures every accepted AXI-Stream word and writes:
    --      PATCH <n> WORD <w> DATA <8-hex> [TLAST]
    --
    -- Stops once NUM_PATCHES complete patches have been captured.
    ---------------------------------------------------------------------------
    capture_proc : process
        file     out_file    : text open write_mode is 
                                "C:\Users\kgab\OneDrive - NTNU\master\testbench\sim\tb_enc_output" & to_string(PS) & "x" & to_string(PS) & ".txt";
        variable l           : line;
        variable word_count  : integer := 0;
        variable patch_count : integer := 0;
    begin
        write(l, string'("# top_tb output (PS=" & integer'image(PS) & ")"));
        writeline(out_file, l);
        write(l, string'("# Format: PATCH <n> WORD <w> DATA <hex> [TLAST]"));
        writeline(out_file, l);

        loop
            wait until rising_edge(clk);

            if m_axis_tvalid = '1' and m_axis_tready = '1' then
                write(l, string'("PATCH "));
                write(l, patch_count);
                write(l, string'(" WORD "));
                write(l, word_count);
                write(l, string'(" DATA "));
                hwrite(l, m_axis_tdata);
                if m_axis_tlast = '1' then
                    write(l, string'(" TLAST"));
                    writeline(out_file, l);
                    -- Sanity check: tlast must coincide with last word
                    assert word_count = WORDS_PER_PATCH - 1
                        report "TLAST asserted at WORD " &
                               integer'image(word_count) & " but expected " &
                               integer'image(WORDS_PER_PATCH - 1)
                        severity warning;
                    patch_count := patch_count + 1;
                    word_count  := 0;
                else
                    writeline(out_file, l);
                    word_count := word_count + 1;
                end if;
            end if;

            if patch_count = NUM_PATCHES then
                write(l, string'("# Done: "));
                write(l, patch_count);
                write(l, string'(" patches, "));
                write(l, patch_count * WORDS_PER_PATCH);
                write(l, string'(" words"));
                writeline(out_file, l);
                report "Capture complete: " & integer'image(patch_count) &
                       " patches received" severity note;
                capture_done <= true;
                wait;
            end if;
        end loop;
    end process;

    ---------------------------------------------------------------------------
    -- STIMULUS
    ---------------------------------------------------------------------------
    stim_proc : process
        file     in_file   : text open read_mode is "C:\Users\kgab\OneDrive - NTNU\master\testbench\sim\pixel_input.txt";
        variable l         : line;
        variable good      : boolean;
        variable hex_c0    : std_logic_vector(7 downto 0);
        variable hex_c1    : std_logic_vector(7 downto 0);
        variable hex_c2    : std_logic_vector(7 downto 0);
        variable buf_c0    : pixel_channel;
        variable buf_c1    : pixel_channel;
        variable buf_c2    : pixel_channel;
        variable pix       : integer := 0;
        variable n_loaded  : integer := 0;
        variable word_val  : std_logic_vector(31 downto 0);
    begin
        -----------------------------------------------------------------------
        -- Load pixel file: one pixel per line, "C0 C1 C2" hex, top-row major.
        -- Lines starting with '#' or empty lines are skipped.
        -----------------------------------------------------------------------
        while not endfile(in_file) and n_loaded < NUM_PIXELS loop
            readline(in_file, l);
            if l'length = 0 then next; end if;
            if l(l'left) = '#' then next; end if;

            hread(l, hex_c0, good); if not good then next; end if;
            hread(l, hex_c1, good); if not good then next; end if;
            hread(l, hex_c2, good); if not good then next; end if;

            buf_c0(n_loaded) := to_integer(unsigned(hex_c0));
            buf_c1(n_loaded) := to_integer(unsigned(hex_c1));
            buf_c2(n_loaded) := to_integer(unsigned(hex_c2));
            n_loaded := n_loaded + 1;
        end loop;

        assert n_loaded = NUM_PIXELS
            report "Loaded " & integer'image(n_loaded) & " pixels, expected " &
                   integer'image(NUM_PIXELS)
            severity failure;
        report "Pixel buffers loaded (" & integer'image(NUM_PIXELS) &
               " pixels)" severity note;

        -----------------------------------------------------------------------
        -- Step 1: Hold reset for a few cycles, then release
        -----------------------------------------------------------------------
        n_reset <= '0';
        wait for 10 * CLK_PERIOD;
        n_reset <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- Step 2: Wait for ps_request, then send patch size + ps_valid pulse
        -----------------------------------------------------------------------
        report "Waiting for ps_request..." severity note;
        if gpio_out(0) = '0' then
            wait until gpio_out(0) = '1';
        end if;
        wait until rising_edge(clk);
        report "ps_request asserted; sending PS=" & integer'image(PS)
            severity note;

        gpio_in <= PS_SEL & "1";       -- ps_in & ps_valid
        wait until rising_edge(clk);
        if gpio_out(0) = '1' then
            wait until gpio_out(0) = '0';   -- IP acknowledged
        end if;
        gpio_in <= (others => '0');
        wait until rising_edge(clk);

        report "PS handshake done; streaming pixels..." severity note;

        -----------------------------------------------------------------------
        -- Step 3: Stream pixels as 32-bit AXI words
        --
        -- Word layout matches axis_pixel_in.vhd:
        --      [31:24] = 0x00 (unused)
        --      [23:16] = C0
        --      [15: 8] = C1
        --      [ 7: 0] = C2
        -----------------------------------------------------------------------
        pix := 0;
        while pix < NUM_PIXELS loop
            word_val := x"00"
                      & std_logic_vector(to_unsigned(buf_c0(pix), 8))
                      & std_logic_vector(to_unsigned(buf_c1(pix), 8))
                      & std_logic_vector(to_unsigned(buf_c2(pix), 8));

            s_axis_tdata  <= word_val;
            s_axis_tvalid <= '1';
            if pix = NUM_PIXELS - 1 then
                s_axis_tlast <= '1';
            else
                s_axis_tlast <= '0';
            end if;

            -- Hold tdata/tvalid until handshake completes (tvalid & tready
            -- both high on a rising edge).
            loop
                wait until rising_edge(clk);
                exit when s_axis_tready = '1';
            end loop;

            pix := pix + 1;
        end loop;

        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';

        report "All pixels sent; waiting for capture to finish..."
            severity note;

        -- Wait for capture process to indicate completion (or timeout)
        for i in 0 to 1_000_000 loop
            wait until rising_edge(clk);
            exit when capture_done;
        end loop;

        wait for 100 * CLK_PERIOD;
        report "Simulation finished cleanly." severity note;
        std.env.finish;
    end process;

end sim;