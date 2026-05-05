----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.04.2026 11:29:03
-- Design Name: 
-- Module Name: axis_patch_out - rtl
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
 
entity axis_patch_out is
    Generic (
        MAX_PS   : positive := 7;
        ENC_BITS : positive := 7;
        POS_BITS : positive := 29   -- DATA_WIDTH - PS0 = 32 - 3
    );
    Port (
        clk                 : in  STD_LOGIC;
        reset               : in  STD_LOGIC;
        
        patch_x_pos_in      : in  STD_LOGIC_VECTOR(0 to POS_BITS-1);
        patch_y_pos_in      : in  STD_LOGIC_VECTOR(0 to POS_BITS-1);
        patch_c0_data_in    : in  STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
        patch_c1_data_in    : in  STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
        patch_c2_data_in    : in  STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
        patch_valid_in      : in  STD_LOGIC;
        patch_ready_out     : out STD_LOGIC;
        patch_last_in       : in STD_LOGIC;
        
        -- AXI4-Stream master (to DMA S2MM)
        m_axis_tdata    : out STD_LOGIC_VECTOR(31 downto 0);
        m_axis_tvalid   : out STD_LOGIC;
        m_axis_tready   : in  STD_LOGIC;
        m_axis_tlast    : out STD_LOGIC
    );
end axis_patch_out;
 
architecture rtl of axis_patch_out is
 
    constant TOTAL_PATCH_BITS   : natural := 2*POS_BITS + 3*MAX_PS*MAX_PS*ENC_BITS; -- 1087
    constant NUM_WORDS          : natural := 34;  -- ceil(1087/32)
 
    signal word_cntr    : unsigned(5 downto 0);
    signal busy         : STD_LOGIC;
 
    -- Registered copies of patch data, captured when valid arrives
    signal x_pos_r      : STD_LOGIC_VECTOR(0 to POS_BITS-1);
    signal y_pos_r      : STD_LOGIC_VECTOR(0 to POS_BITS-1);
    signal c0_r         : STD_LOGIC_VECTOR(MAX_PS*MAX_PS*ENC_BITS-1 downto 0);
    signal c1_r         : STD_LOGIC_VECTOR(MAX_PS*MAX_PS*ENC_BITS-1 downto 0);
    signal c2_r         : STD_LOGIC_VECTOR(MAX_PS*MAX_PS*ENC_BITS-1 downto 0);
    signal patch_last_r : STD_LOGIC;
 
    -- Flat payload built combinatorially from registers (pure wiring, no logic)
    signal payload    : STD_LOGIC_VECTOR(NUM_WORDS*32-1 downto 0);
 
begin
 
    patch_ready_out <= not busy;
    
    -- Payload packing: top-row major
    process(y_pos_r, x_pos_r, c0_r, c1_r, c2_r)
        variable bit_idx : integer;
        variable px_idx  : integer;
    begin
        bit_idx := NUM_WORDS * 32;
        payload <= (others => '0');
    
        -- y_pos then x_pos at MSB end
        payload(bit_idx - 1 downto bit_idx - POS_BITS) <= y_pos_r;
        bit_idx := bit_idx - POS_BITS;
    
        payload(bit_idx - 1 downto bit_idx - POS_BITS) <= x_pos_r;
        bit_idx := bit_idx - POS_BITS;
    
        -- Interleave C0 C1 C2 per pixel, top-row major: (0,0) first, (MAX_PS-1, MAX_PS-1) last
        for row in 0 to MAX_PS - 1 loop
            for col in 0 to MAX_PS - 1 loop
                px_idx := (row * MAX_PS + col) * ENC_BITS;
                payload(bit_idx - 1 downto bit_idx - ENC_BITS)
                    <= c0_r(MAX_PS*MAX_PS*ENC_BITS - 1 - px_idx downto MAX_PS*MAX_PS*ENC_BITS - px_idx - ENC_BITS);
                bit_idx := bit_idx - ENC_BITS;
                payload(bit_idx - 1 downto bit_idx - ENC_BITS)
                    <= c1_r(MAX_PS*MAX_PS*ENC_BITS - 1 - px_idx downto MAX_PS*MAX_PS*ENC_BITS - px_idx - ENC_BITS);
                bit_idx := bit_idx - ENC_BITS;
                payload(bit_idx - 1 downto bit_idx - ENC_BITS)
                    <= c2_r(MAX_PS*MAX_PS*ENC_BITS - 1 - px_idx downto MAX_PS*MAX_PS*ENC_BITS - px_idx - ENC_BITS);
                bit_idx := bit_idx - ENC_BITS;
            end loop;
        end loop;
    end process;
 
    -- Capture patch registers and advance word counter
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                busy      <= '0';
                word_cntr <= (others => '0');
 
            elsif busy = '0' and patch_valid_in = '1' then
                x_pos_r         <= patch_x_pos_in;
                y_pos_r         <= patch_y_pos_in;
                c0_r            <= patch_c0_data_in;
                c1_r            <= patch_c1_data_in;
                c2_r            <= patch_c2_data_in;
                patch_last_r    <= patch_last_in;
                   
                word_cntr <= (others => '0');
                busy      <= '1';
 
            elsif busy = '1' and m_axis_tready = '1' then
                if word_cntr = NUM_WORDS-1 then
                    busy      <= '0';
                    word_cntr <= (others => '0');
                else
                    word_cntr <= word_cntr + 1;
                end if;
            end if;
        end if;
    end process;
 
    -- Select the current 32-bit word from payload using the counter
    m_axis_tdata    <= payload((NUM_WORDS - to_integer(word_cntr)) * 32 - 1
                                downto
                                (NUM_WORDS - to_integer(word_cntr) - 1) * 32);
    m_axis_tvalid   <= busy;
    m_axis_tlast    <= '1' when (busy = '1') and 
                                (word_cntr = NUM_WORDS-1) and 
                                (patch_last_r = '1') 
                                else '0';
 
end rtl;
