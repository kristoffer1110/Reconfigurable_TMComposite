----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.05.2026 10:12:51
-- Design Name: 
-- Module Name: top - rtl
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

entity top is
    Generic (
        NUM_GPIO_IN     : positive := 5;
        NUM_GPIO_OUT    : positive := 1;
        NUM_PS          : positive := 4;
        PS0             : positive := 3;
        PS1             : positive := 4;
        PS2             : positive := 5;
        PS3             : positive := 7;
        IMG_SIZE        : positive := 32;        
        PX_BITS         : positive := 8
    );
    
    Port    (
        clk             : in STD_LOGIC;
        n_reset         : in STD_LOGIC;
        dma_intr        : out STD_LOGIC;
        
        gpio_in         : in STD_LOGIC_VECTOR (NUM_GPIO_IN -1 downto 0);
        gpio_out        : out STD_LOGIC_VECTOR (NUM_GPIO_OUT -1 downto 0);
        
        s_axis_tdata    : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axis_tvalid   : in  STD_LOGIC;
        s_axis_tready   : out STD_LOGIC;
        s_axis_tlast    : in  STD_LOGIC;
                
        m_axis_tdata    : out STD_LOGIC_VECTOR(31 downto 0);
        m_axis_tvalid   : out STD_LOGIC;
        m_axis_tready   : in  STD_LOGIC;
        m_axis_tlast    : out STD_LOGIC
                
    );
end top;

architecture rtl of top is
    constant POS_BITS       : positive := IMG_SIZE - PS0;
    constant ENC_BITS       : positive := PX_BITS -1;
    
    signal reset            : STD_LOGIC;
    
    signal ps_data          : STD_LOGIC_VECTOR(NUM_PS -1 downto 0);
    signal ps_valid         : STD_LOGIC;
    signal ps_request       : STD_LOGIC;
    
    signal px_c0_data       : STD_LOGIC_VECTOR(PX_BITS -1 downto 0); 
    signal px_c1_data       : STD_LOGIC_VECTOR(PX_BITS -1 downto 0);
    signal px_c2_data       : STD_LOGIC_VECTOR(PX_BITS -1 downto 0);
    signal px_valid         : STD_LOGIC;
    signal px_ready         : STD_LOGIC;
    
    signal patch_x_pos      : STD_LOGIC_VECTOR(POS_BITS -1 downto 0);
    signal patch_y_pos      : STD_LOGIC_VECTOR(POS_BITS -1 downto 0);
    signal patch_c0_data    : STD_LOGIC_VECTOR(PS3*PS3*ENC_BITS -1 downto 0);
    signal patch_c1_data    : STD_LOGIC_VECTOR(PS3*PS3*ENC_BITS -1 downto 0);
    signal patch_c2_data    : STD_LOGIC_VECTOR(PS3*PS3*ENC_BITS -1 downto 0);
    signal patch_valid      : STD_LOGIC;
    signal patch_ready      : STD_LOGIC;
    signal patch_last       : STD_LOGIC;
    
begin
    reset <= not n_reset;
    
    gpio_if : entity work.gpio_mapper
        generic map (
            NUM_IN              => NUM_GPIO_IN,
            NUM_OUT             => NUM_GPIO_OUT,
            NUM_PS              => NUM_PS
        )
        
        port map (
            gpio_in             => gpio_in,
            gpio_out            => gpio_out,
            ps_data_out         => ps_data,
            ps_valid_out        => ps_valid,
            ps_request_in       => ps_request
        );
    
    s_axis_if : entity work.axis_pixel_in
        generic map (
            PX_BITS             => PX_BITS
        )
        
        port map (
            s_axis_tdata        => s_axis_tdata ,    
            s_axis_tvalid       => s_axis_tvalid,
            s_axis_tready       => s_axis_tready,
            s_axis_tlast        => s_axis_tlast ,
            px_c0_data_out      => px_c0_data,
            px_c1_data_out      => px_c1_data,
            px_c2_data_out      => px_c2_data,
            px_valid_out        => px_valid  ,
            px_ready_in         => px_ready   
        );
    
    encoded_patches : entity work.enc_patches
        generic map (
            DATA_WIDTH          => IMG_SIZE,
            NUM_PS              => NUM_PS    ,
            PS0                 => PS0       ,
            PS1                 => PS1       ,
            PS2                 => PS2       ,
            PS3                 => PS3       ,
            PX_BITS             => PX_BITS   ,
            ENC_BITS            => ENC_BITS  ,
            POS_BITS            => POS_BITS
        )
        
        port map (
            clk                 => clk,
            reset               => reset,
            dma_intr            => dma_intr,
            ps_data_in          => ps_data,        
            ps_valid_in         => ps_valid,   
            ps_request_out      => ps_request,
            px_c0_data_in       => px_c0_data,
            px_c1_data_in       => px_c1_data,
            px_c2_data_in       => px_c2_data,
            px_valid_in         => px_valid,
            px_ready_out        => px_ready,
            patch_x_pos_out     => patch_x_pos  ,
            patch_y_pos_out     => patch_y_pos  ,
            patch_c0_data_out   => patch_c0_data,
            patch_c1_data_out   => patch_c1_data,
            patch_c2_data_out   => patch_c2_data,
            patch_valid_out     => patch_valid  ,
            patch_ready_in      => patch_ready,
            patch_last_out      => patch_last  
        );
        
    m_axis_if : entity work.axis_patch_out
        generic map (
            MAX_PS              => PS3,
            ENC_BITS            => ENC_BITS,
            POS_BITS            => POS_BITS
        )
        
        port map (
            clk                 => clk,
            reset               => reset,
            patch_x_pos_in      => patch_x_pos,
            patch_y_pos_in      => patch_y_pos,
            patch_c0_data_in    => patch_c0_data,
            patch_c1_data_in    => patch_c1_data,
            patch_c2_data_in    => patch_c2_data,
            patch_valid_in      => patch_valid,
            patch_ready_out     => patch_ready,
            patch_last_in       => patch_last,            
            m_axis_tdata        => m_axis_tdata ,
            m_axis_tvalid       => m_axis_tvalid,
            m_axis_tready       => m_axis_tready,
            m_axis_tlast        => m_axis_tlast            
        );
        
end rtl;
