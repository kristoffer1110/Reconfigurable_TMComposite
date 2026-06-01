library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.types_pkg.all;

entity pixel_encoding is
    Port (
        clk                 : in STD_LOGIC;
        reset               : in STD_LOGIC;
     
        s_axis_tdata_c0_in  : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        s_axis_tdata_c1_in  : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        s_axis_tdata_c2_in  : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        s_axis_tvalid_in    : in STD_LOGIC;
        s_axis_tready_out   : out STD_LOGIC;
        
        px_c0_data_out     : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        px_c1_data_out     : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        px_c2_data_out     : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        px_valid_out       : out STD_LOGIC;
        px_ready_in        : in STD_LOGIC
    );
end pixel_encoding;

architecture rtl of pixel_encoding is
        
    signal c0_ready : STD_LOGIC;
    signal c1_ready : STD_LOGIC;
    signal c2_ready : STD_LOGIC;
       
    signal c0_valid : STD_LOGIC;
    signal c1_valid : STD_LOGIC;
    signal c2_valid : STD_LOGIC;    
    
begin

    process(all)
    begin
        s_axis_tready_out   <= c0_ready and c1_ready and c2_ready;
        px_valid_out        <= c0_valid and c1_valid and c2_valid;
    end process;

    c0_px_enc : entity work.pixel_encoder
        
        port map (
            clk         => clk       ,
            reset       => reset     ,
            data_in     => s_axis_tdata_c0_in ,
            valid_in    => s_axis_tvalid_in,
            ready_out   => c0_ready,
            data_out    => px_c0_data_out,
            valid_out   => c0_valid,
            ready_in    => px_ready_in
        );
        
    c1_px_enc : entity work.pixel_encoder
        
        port map (
            clk         => clk       ,
            reset       => reset     ,
            data_in     => s_axis_tdata_c1_in ,
            valid_in    => s_axis_tvalid_in,
            ready_out   => c1_ready,
            data_out    => px_c1_data_out,
            valid_out   => c1_valid,
            ready_in    => px_ready_in
        );

    c2_px_enc : entity work.pixel_encoder
        
        port map (
            clk         => clk       ,
            reset       => reset     ,
            data_in     => s_axis_tdata_c2_in ,
            valid_in    => s_axis_tvalid_in,
            ready_out   => c2_ready,
            data_out    => px_c2_data_out,
            valid_out   => c2_valid,
            ready_in    => px_ready_in
        );     

end rtl;
