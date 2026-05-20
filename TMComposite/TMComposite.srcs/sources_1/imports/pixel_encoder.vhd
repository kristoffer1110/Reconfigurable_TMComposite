----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.03.2026 14:39:14
-- Design Name: 
-- Module Name: pixel_encoder - Behavioral
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
use ieee.numeric_std.all;
use work.math_pkg.all;
use work.types_pkg.all;

entity pixel_encoder is
    Generic (
        PX_BITS     : positive := PX_BITS;
        ENC_BITS    : positive := ENC_BITS
    );
    
    Port (
        clk             : in STD_LOGIC;
        reset           : in STD_LOGIC;
    
        px_data_in      : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_valid_in     : in STD_LOGIC;
        px_ready_out    : out STD_LOGIC;

        enc_data_out    : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        enc_valid_out   : out STD_LOGIC;
        enc_ready_in    : in STD_LOGIC
    );
    
end pixel_encoder;

architecture rtl of pixel_encoder is

begin
   
    -- Drive ready/last combinatorially (no pipeline delay needed)
    px_ready_out <= enc_ready_in;

    -- Single registered process for all pipelined outputs
    process(clk)
        variable pixel_val   : unsigned(PX_BITS -1 downto 0);
        variable bin_idx     : unsigned(clog2(ENC_BITS +1) -1 downto 0);
        variable encoded_val : unsigned(ENC_BITS -1 downto 0);
    begin
        if rising_edge(clk) then
            enc_valid_out <= px_valid_in;
                
            if reset = '1' then
                enc_data_out <= (others => '0');
                enc_valid_out <= '0';

    
            elsif px_valid_in = '1' and enc_ready_in = '1' then
                pixel_val := unsigned(px_data_in);

                bin_idx := resize(
                    pixel_val srl (PX_BITS - clog2(ENC_BITS + 1)),
                    bin_idx'length
                );

                if bin_idx = 0 then
                    encoded_val := (others => '0');
                else
                    encoded_val := (to_unsigned(1, ENC_BITS) sll to_integer(bin_idx)) - 1;
                end if;

                -- Assign enc output in same cycle as valid/last
                enc_data_out <= STD_LOGIC_VECTOR(encoded_val);
            end if;
        end if;
    end process;
end rtl;
