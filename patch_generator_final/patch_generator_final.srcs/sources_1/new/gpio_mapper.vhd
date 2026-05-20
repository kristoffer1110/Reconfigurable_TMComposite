----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.05.2026 11:40:05
-- Design Name: 
-- Module Name: gpio_mapper - rtl
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
use work.types_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity gpio_mapper is
    
    Port (
        gpio_in         : in STD_LOGIC_VECTOR (4 downto 0);
        gpio_out        : out STD_LOGIC_VECTOR (0 downto 0);
        
        ps_data_out     : out STD_LOGIC_VECTOR(NUM_SPECIALISTS -1 downto 0);
        ps_valid_out    : out STD_LOGIC;
        ps_request_in   : in STD_LOGIC
    );
end gpio_mapper;

architecture rtl of gpio_mapper is

begin

    ps_data_out     <= gpio_in(4 downto 1);
    ps_valid_out    <= gpio_in(0);
    gpio_out(0)     <= ps_request_in; 

end rtl;
