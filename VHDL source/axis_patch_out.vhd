library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.types_pkg.all;

entity axis_patch_out is
    generic (
        PX_BITS : positive := ENC_BITS
    );
    port (
        clk              : in  STD_LOGIC;
        reset            : in  STD_LOGIC;
        
        patch_x_pos_in   : in  STD_LOGIC_VECTOR(0 to POS_BITS-1);
        patch_y_pos_in   : in  STD_LOGIC_VECTOR(0 to POS_BITS-1);
        patch_c0_data_in : in  STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS - 1 downto 0);
        patch_c1_data_in : in  STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS - 1 downto 0);
        patch_c2_data_in : in  STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS - 1 downto 0);
        patch_valid_in   : in  STD_LOGIC;
        patch_ready_out  : out STD_LOGIC;
        patch_last_in    : in  STD_LOGIC;
        
        m_axis_tdata     : out STD_LOGIC_VECTOR(31 downto 0);
        m_axis_tvalid    : out STD_LOGIC;
        m_axis_tready    : in  STD_LOGIC;
        m_axis_tlast     : out STD_LOGIC
    );
end axis_patch_out;

architecture rtl of axis_patch_out is

    constant TOTAL_PATCH_BITS : natural := 2*POS_BITS + 3*PS3*PS3*PX_BITS; -- 1087
    constant NUM_WORDS        : natural := 34;  -- ceil(1087/32)

    signal word_cntr : unsigned(5 downto 0);
    signal busy      : STD_LOGIC;

    -- Registered patch data, captured on the accepted handshake cycle
    signal x_pos_r      : STD_LOGIC_VECTOR(0 to POS_BITS - 1);
    signal y_pos_r      : STD_LOGIC_VECTOR(0 to POS_BITS - 1);
    signal c0_r         : STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS - 1 downto 0);
    signal c1_r         : STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS - 1 downto 0);
    signal c2_r         : STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS - 1 downto 0);
    signal patch_last_r : STD_LOGIC;

    -- Flat payload built combinatorially from registered data (pure wiring)
    signal payload : STD_LOGIC_VECTOR(NUM_WORDS * 32 - 1 downto 0);

begin

    patch_ready_out <= not busy;

    ---------------------------------------------------------------------------
    -- Payload packing: MSB-first, row-major
    --   y_pos | x_pos | (c0,c1,c2 for each pixel in row-major order)
    ---------------------------------------------------------------------------
    process (y_pos_r, x_pos_r, c0_r, c1_r, c2_r)
        variable bit_idx : integer;
        variable px_idx  : integer;
    begin
        payload  <= (others => '0');
        bit_idx  := NUM_WORDS * 32;

        payload(bit_idx - 1 downto bit_idx - POS_BITS) <= y_pos_r;
        bit_idx := bit_idx - POS_BITS;

        payload(bit_idx - 1 downto bit_idx - POS_BITS) <= x_pos_r;
        bit_idx := bit_idx - POS_BITS;

        for row in 0 to PS3 - 1 loop
            for col in 0 to PS3 - 1 loop
                px_idx := (row * PS3 + col) * PX_BITS;

                payload(bit_idx - 1 downto bit_idx - PX_BITS) <=
                    c0_r(PS3*PS3*PX_BITS - 1 - px_idx downto
                         PS3*PS3*PX_BITS - px_idx - PX_BITS);
                bit_idx := bit_idx - PX_BITS;

                payload(bit_idx - 1 downto bit_idx - PX_BITS) <=
                    c1_r(PS3*PS3*PX_BITS - 1 - px_idx downto
                         PS3*PS3*PX_BITS - px_idx - PX_BITS);
                bit_idx := bit_idx - PX_BITS;

                payload(bit_idx - 1 downto bit_idx - PX_BITS) <=
                    c2_r(PS3*PS3*PX_BITS - 1 - px_idx downto
                         PS3*PS3*PX_BITS - px_idx - PX_BITS);
                bit_idx := bit_idx - PX_BITS;
            end loop;
        end loop;
    end process;

    ---------------------------------------------------------------------------
    -- Capture registers and word counter FSM
    ---------------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                busy            <= '0';
                word_cntr       <= (others => '0');       
                patch_last_r    <= '0';           

            -- Accept new patch only when idle
            elsif busy = '0' and patch_valid_in = '1' then
                x_pos_r      <= patch_x_pos_in;
                y_pos_r      <= patch_y_pos_in;
                c0_r         <= patch_c0_data_in;
                c1_r         <= patch_c1_data_in;
                c2_r         <= patch_c2_data_in;
                patch_last_r <= patch_last_in;
                word_cntr    <= (others => '0');
                busy         <= '1';

            -- Advance through the serialised words when downstream is ready
            elsif busy = '1' and m_axis_tready = '1' then
                if word_cntr = NUM_WORDS - 1 then
                    busy      <= '0';
                    word_cntr <= (others => '0');
                else
                    word_cntr <= word_cntr + 1;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Output assignments
    ---------------------------------------------------------------------------

    -- Select the current 32-bit word from payload (MSB-first)
    m_axis_tdata  <= payload((NUM_WORDS - to_integer(word_cntr)) * 32 - 1
                              downto
                              (NUM_WORDS - to_integer(word_cntr) - 1) * 32);
    m_axis_tvalid <= busy;
    m_axis_tlast  <= '1' when busy = '1' and word_cntr = NUM_WORDS - 1 and patch_last_r = '1'
                         else '0';

end architecture rtl;