----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.04.2026 11:29:03
-- Design Name: 
-- Module Name: axis_pixel_in - rtl
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

entity axis_pixel_in is
    Generic (
        PX_BITS : positive := 8
    );
    Port (
    
        s_axis_tdata    : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axis_tvalid   : in  STD_LOGIC;
        s_axis_tready   : out STD_LOGIC;
        s_axis_tlast    : in  STD_LOGIC;
        
        px_c0_data_out  : out STD_LOGIC_VECTOR(PX_BITS-1 downto 0);
        px_c1_data_out  : out STD_LOGIC_VECTOR(PX_BITS-1 downto 0);
        px_c2_data_out  : out STD_LOGIC_VECTOR(PX_BITS-1 downto 0);
        px_valid_out    : out STD_LOGIC;
        px_ready_in     : in  STD_LOGIC
    );
end axis_pixel_in;

architecture rtl of axis_pixel_in is
begin
    px_c0_data_out  <= s_axis_tdata(23 downto 16);
    px_c1_data_out  <= s_axis_tdata(15 downto  8);
    px_c2_data_out  <= s_axis_tdata(7 downto 0);

    px_valid_out    <= s_axis_tvalid;
    
    s_axis_tready <= px_ready_in;
    
end rtl;
