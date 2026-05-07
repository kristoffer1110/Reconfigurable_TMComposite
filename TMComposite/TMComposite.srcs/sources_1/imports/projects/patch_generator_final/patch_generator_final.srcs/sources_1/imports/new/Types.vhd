----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.03.2026 14:07:51
-- Design Name: 
-- Module Name: Types - Behavioral
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
use IEEE.numeric_std.all;
use work.math_pkg.all;

package types_pkg is

    constant NUM_SPECIALISTS : positive := 4;
    constant NUM_CLAUSES     : positive := 10;
    constant NUM_CLASSES     : positive := 10;
    constant MAX_WEIGHT      : positive := 4;
    
    type pixel_row is array (natural range <>) of STD_LOGIC_VECTOR;
    type pixel_row_arr is array (natural range <>) of pixel_row;
    type enc_enable_arr is array (natural range <>) of STD_LOGIC_VECTOR;
    
    type weight_arr is array (natural range NUM_CLASSES -1 downto 0) of signed(clog2(MAX_WEIGHT) +1 downto 0);
    type weight_matrix is array (natural range NUM_CLAUSES -1 downto 0) of weight_arr;
    
    type class_sums_arr is array (natural range NUM_CLASSES -1 downto 0) of signed(clog2(MAX_WEIGHT*NUM_CLAUSES) downto 0);
    
end package;