----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.03.2026 13:47:51
-- Design Name: 
-- Module Name: line_buffer - rtl
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
use work.math_pkg.all;

entity line_buffer_v5 is
    Generic (
        PX_BITS     : positive := PX_BITS   ;
        MAX_PS      : positive := PS0       ;
        MIN_PS      : positive := PS3       ;
        DATA_DEPTH  : positive := IMG_SIZE
    );
    
    Port (
        clk             : in STD_LOGIC;
        reset           : in STD_LOGIC;
        wr_en           : in STD_LOGIC;        
        rd_en           : in STD_LOGIC;
        
        output_mask     : in pixel_row(MAX_PS - MIN_PS -1 downto 0)(PX_BITS -1 downto 0);

        px_data_in      : in STD_LOGIC_VECTOR (PX_BITS - 1 downto 0);
        px_valid_in     : in STD_LOGIC;
        
        px_row_data_out : out pixel_row(MAX_PS -1 downto 0)(PX_BITS -1 downto 0);
        px_row_ready_in : in STD_LOGIC
     );
     
end line_buffer_v5;

architecture rtl of line_buffer_v5 is
    
    signal wr_pntr          : unsigned (clog2(DATA_DEPTH) -1 downto 0);
    signal rd_pntr          : unsigned (clog2(DATA_DEPTH) -1 downto 0);
    
    signal ln_buff          : pixel_row (DATA_DEPTH -1 + MAX_PS -1 downto 0)(PX_BITS -1 downto 0);
    signal ln_buff_out      : pixel_row (MAX_PS -1 downto 0)(PX_BITS -1 downto 0);

    
begin
    
    process(clk)
    begin
        if rising_edge(clk)then
            if reset = '1' then
                ln_buff <= (others => (others => '0'));
                
            elsif px_valid_in = '1' and wr_en = '1' then
                ln_buff(to_integer(wr_pntr)) <= px_data_in;
            end if;
        end if;
    end process;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wr_pntr <= (others => '0');
                
            elsif px_valid_in = '1' and wr_en = '1' then
                wr_pntr <= wr_pntr + 1;
            end if;
        end if;
    end process;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                rd_pntr <= (others => '0');
            elsif px_row_ready_in = '1' and rd_en = '1' then
                rd_pntr <= rd_pntr +1;
            end if;
        end if;
    end process;
    
    process(all)
    begin
        if rd_en = '1' then
            for i in MAX_PS -1 downto 0 loop
                ln_buff_out(i) <= ln_buff(to_integer(rd_pntr) + i);
            end loop;
        else
            ln_buff_out <= (others => (others => '1'));
        end if;               
    end process;                        

    process(all)
    begin
        for i in MAX_PS -1 downto MIN_PS  loop                    
            px_row_data_out(i)  <= (ln_buff_out(i) or output_mask(i - MIN_PS));
        end loop;
        px_row_data_out(MIN_PS -1 downto 0) <= ln_buff_out(MIN_PS -1 downto 0);
    end process;                        

end rtl;
