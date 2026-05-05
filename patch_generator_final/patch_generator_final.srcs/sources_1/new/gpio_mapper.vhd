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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity gpio_mapper is
    Generic (
        NUM_IN  : positive := 5;
        NUM_OUT : positive := 1;
        NUM_PS  : positive := 4
    );
    
    Port (
        gpio_in         : in STD_LOGIC_VECTOR (NUM_IN -1 downto 0);
        gpio_out        : out STD_LOGIC_VECTOR (NUM_OUT -1 downto 0);
        
        ps_data_out     : out STD_LOGIC_VECTOR(NUM_PS -1 downto 0);
        ps_valid_out    : out STD_LOGIC;
        ps_request_in   : in STD_LOGIC
    );
end gpio_mapper;

architecture rtl of gpio_mapper is

begin

    ps_data_out             <= gpio_in(NUM_IN -1 downto NUM_IN - NUM_PS);
    ps_valid_out            <= gpio_in(NUM_IN - NUM_PS -1);
    gpio_out(NUM_OUT -1)    <= ps_request_in; 

end rtl;
