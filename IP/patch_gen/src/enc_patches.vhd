----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02.05.2026 14:09:08
-- Design Name: 
-- Module Name: enc_patches - rtl
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

entity enc_patches is
    Generic (
        NUM_PS          : positive := 4; -- PS0 should be smallest patch size
        PS0             : positive := 3;
        PS1             : positive := 4;
        PS2             : positive := 5;
        PS3             : positive := 7; -- PS3 should be largest patch size 
        DATA_WIDTH      : positive := 32;
        PX_BITS         : positive := 8;
        POS_BITS        : positive := 29;
        ENC_BITS        : positive := 7        
    );
    
    Port (
        clk                 : in STD_LOGIC;
        reset               : in STD_LOGIC;
        
        dma_intr            : out STD_LOGIC;
        
        ps_data_in          : in STD_LOGIC_VECTOR(NUM_PS -1 downto 0);
        ps_valid_in         : in STD_LOGIC;
        ps_request_out      : out STD_LOGIC;
             
        px_c2_data_in       : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_c1_data_in       : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_c0_data_in       : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_valid_in         : in STD_LOGIC;
        px_ready_out        : out STD_LOGIC;
        
        patch_x_pos_out     : out STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_y_pos_out     : out STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_c2_data_out   : out STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
        patch_c1_data_out   : out STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
        patch_c0_data_out   : out STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);        
        patch_valid_out     : out STD_LOGIC;
        patch_ready_in      : in STD_LOGIC;
        patch_last_out      : out STD_LOGIC             
    );
end enc_patches;

architecture rtl of enc_patches is

    signal enc_c2_data  : STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
    signal enc_c1_data  : STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
    signal enc_c0_data  : STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
    signal enc_valid    : STD_LOGIC;
    signal enc_ready    : STD_LOGIC;
    
begin

    pixel_encoding : entity work.pixel_encoding
        generic map (
            PX_BITS     => PX_BITS,
            ENC_BITS    => ENC_BITS
        )
    
        port map (
            clk             => clk            ,
            reset           => reset          ,      
            px_c2_data_in   => px_c2_data_in  ,
            px_c1_data_in   => px_c1_data_in  ,
            px_c0_data_in   => px_c0_data_in  ,
            px_valid_in     => px_valid_in   ,
            px_ready_out    => px_ready_out  ,
            enc_c2_data_out => enc_c2_data,
            enc_c1_data_out => enc_c1_data,
            enc_c0_data_out => enc_c0_data,
            enc_valid_out   => enc_valid,
            enc_ready_in    => enc_ready
        );
    
    patches : entity work.patches_v5
        generic map (
            NUM_PS     => NUM_PS    ,
            PS0        => PS0       ,
            PS1        => PS1       ,
            PS2        => PS2       ,
            PS3        => PS3       ,
            DATA_WIDTH => DATA_WIDTH,
            PX_BITS    => ENC_BITS  ,        
            POS_BITS   => POS_BITS
        )
        
        port map (
            clk                 => clk ,            
            reset               => reset,   
            dma_intr            => dma_intr,
            ps_data_in          => ps_data_in,
            ps_valid_in         => ps_valid_in   ,
            ps_request_out      => ps_request_out,
            px_c2_data_in       => enc_c2_data,
            px_c1_data_in       => enc_c1_data,
            px_c0_data_in       => enc_c0_data,
            px_valid_in         => enc_valid,
            px_ready_out        => enc_ready,
            patch_x_pos_out     => patch_x_pos_out  ,
            patch_y_pos_out     => patch_y_pos_out  ,
            patch_c2_data_out   => patch_c2_data_out,
            patch_c1_data_out   => patch_c1_data_out,
            patch_c0_data_out   => patch_c0_data_out,
            patch_valid_out     => patch_valid_out  ,
            patch_ready_in      => patch_ready_in,
            patch_last_out      => patch_last_out
        );
            
end rtl;    
            