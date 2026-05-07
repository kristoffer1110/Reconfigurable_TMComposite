----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.04.2026 16:28:47
-- Design Name: 
-- Module Name: clause_logic - rtl
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
use work.types_pkg.all;
use work.functions_pkg.all;

entity clause_logic is
    generic (
        LIT_BITS    : positive := 2174;
        POS_BITS    : positive := 29
    );
    
    port (
        clk             : in STD_LOGIC;
        reset           : in STD_LOGIC;
        n_empty_in      : in STD_LOGIC;
        
        lit_in          : in STD_LOGIC_VECTOR(LIT_BITS -1 downto 0);
        n_inc_in        : in STD_LOGIC_VECTOR(LIT_BITS -1 downto 0);
        
        clause_val_out  : out STD_LOGIC
     );
     
end clause_logic;

architecture rtl of clause_logic is
    signal inc_lit              : STD_LOGIC_VECTOR(LIT_BITS -1 downto 0);
    signal clause_val           : STD_LOGIC;
    signal clause_fb            : STD_LOGIC;

begin
    
    clause_val_out <= clause_fb;
    
    process(all)
    begin
        inc_lit     <= ( lit_in or n_inc_in or (LIT_BITS -1 downto 0 => clause_fb));
        clause_val  <= (( and inc_lit) and n_empty_in) or clause_fb;
    end process;
    
    process(clk, reset)  
    begin
        if rising_edge(clk) then
            if reset = '1' then
                clause_fb <= '0';
            else
                clause_fb <= clause_val;
            end if;
        end if;
    end process;
end rtl;
