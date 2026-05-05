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

package types_pkg is
    type pixel_row is array (natural range <>) of STD_LOGIC_VECTOR;
    type pixel_row_arr is array (natural range <>) of pixel_row;
    type enc_enable_arr is array (natural range <>) of STD_LOGIC_VECTOR;
end package;