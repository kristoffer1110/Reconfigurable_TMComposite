----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 27.04.2026 13:43:25
-- Design Name: 
-- Module Name: 3ch_pixel_encoding - rtl
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

entity pixel_encoding is
    
    Port (
        clk             : in STD_LOGIC;
        reset           : in STD_LOGIC;
     
        px_c0_data_in   : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_c1_data_in   : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_c2_data_in   : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_valid_in     : in STD_LOGIC;
        px_ready_out    : out STD_LOGIC;
        
        enc_c0_data_out : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        enc_c1_data_out : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        enc_c2_data_out : out STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
        enc_valid_out   : out STD_LOGIC;
        enc_ready_in    : in STD_LOGIC
    );
end pixel_encoding;

architecture rtl of pixel_encoding is
    
    signal px_valid     : STD_LOGIC;
    
    signal px_c0_ready  : STD_LOGIC;
    signal px_c1_ready  : STD_LOGIC;
    signal px_c2_ready  : STD_LOGIC;
       
    signal enc_c0_valid : STD_LOGIC;
    signal enc_c1_valid : STD_LOGIC;
    signal enc_c2_valid : STD_LOGIC;    
    
begin

    process(all)
    begin
        px_ready_out    <= px_c0_ready and px_c1_ready and px_c2_ready;
        enc_valid_out   <= enc_c0_valid and enc_c1_valid and enc_c2_valid;
    end process;

    c0_px_enc : entity work.pixel_encoder
        
        port map (
            clk             => clk       ,
            reset           => reset     ,
            px_data_in      => px_c0_data_in ,
            px_valid_in     => px_valid_in,
            px_ready_out    => px_c0_ready,
            enc_data_out    => enc_c0_data_out,
            enc_valid_out   => enc_c0_valid,
            enc_ready_in    => enc_ready_in
        );
        
    c1_px_enc : entity work.pixel_encoder
        
        port map (
            clk             => clk       ,
            reset           => reset     ,
            px_data_in      => px_c1_data_in ,
            px_valid_in     => px_valid_in,
            px_ready_out    => px_c1_ready,
            enc_data_out    => enc_c1_data_out,
            enc_valid_out   => enc_c1_valid,
            enc_ready_in    => enc_ready_in
        );

    c2_px_enc : entity work.pixel_encoder
        
        port map (
            clk             => clk       ,
            reset           => reset     ,
            px_data_in      => px_c2_data_in ,
            px_valid_in     => px_valid_in,
            px_ready_out    => px_c2_ready,
            enc_data_out    => enc_c2_data_out,
            enc_valid_out   => enc_c2_valid,
            enc_ready_in    => enc_ready_in
        );          

end rtl;
