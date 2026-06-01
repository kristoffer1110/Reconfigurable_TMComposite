library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.types_pkg.all;
use work.math_pkg.all;

entity pixel_encoder is
    Port (
        clk         : in STD_LOGIC;
        reset       : in STD_LOGIC;
    
        data_in     : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        valid_in    : in STD_LOGIC;
        ready_out   : out STD_LOGIC;

        data_out    : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        valid_out   : out STD_LOGIC;
        ready_in    : in STD_LOGIC
    );
end pixel_encoder;

architecture rtl of pixel_encoder is

begin
   
    ready_out <= ready_in;

    process(clk)
        variable pixel_val   : unsigned(PX_BITS -1 downto 0);
        variable bin_idx     : unsigned(clog2(ENC_BITS +1) -1 downto 0);
        variable encoded_val : unsigned(ENC_BITS -1 downto 0);
    begin
        if rising_edge(clk) then
            valid_out <= valid_in;
                
            if reset = '1' then
                data_out    <= (others => '0');
                valid_out   <= '0';

            elsif valid_in = '1' and ready_in = '1' then
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

                data_out <= STD_LOGIC_VECTOR(encoded_val);
            end if;
        end if;
    end process;
end rtl;
