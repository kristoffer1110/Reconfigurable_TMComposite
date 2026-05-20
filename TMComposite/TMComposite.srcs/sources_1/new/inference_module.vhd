----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06.05.2026 23:39:41
-- Design Name: 
-- Module Name: inference_module - rtl
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
use work.math_pkg.all;
use work.types_pkg.all;
use work.functions_pkg.all;

entity inference_module is
    Generic (
        NUM_SPECIALISTS : positive := NUM_SPECIALISTS; 
        NUM_CLAUSES     : positive := NUM_CLAUSES;
        NUM_CLASSES     : positive := NUM_CLASSES; 
        MAX_WEIGHT      : positive := MAX_WEIGHT;  
               
        IMG_SIZE        : positive := IMG_SIZE;        
        PS0             : positive := PS0     ; -- PS0 should be smallest patch size
        PS1             : positive := PS1     ;
        PS2             : positive := PS2     ;
        PS3             : positive := PS3     ; -- PS3 should be largest patch size 
        PX_BITS         : positive := PX_BITS ;
        POS_BITS        : positive := POS_BITS;
        ENC_BITS        : positive := ENC_BITS;
        
        BRAM_ADDR_WIDTH : positive := BRAM_ADDR_WIDTH;
        BRAM_DATA_WIDTH : positive := BRAM_DATA_WIDTH;
        
        CS_WORD_WIDTH   : positive := CS_WORD_WIDTH;
        CS_NUM_WORDS    : positive := CS_NUM_WORDS 
               
    );
    
    Port (
        clk                 : in STD_LOGIC;
        n_reset             : in STD_LOGIC;
        
        wr_ready_intr       : out STD_LOGIC;
        
        bram_addr_out       : out STD_LOGIC_VECTOR(BRAM_ADDR_WIDTH -1 downto 0);
        bram_en_out         : out STD_LOGIC;
        bram_data_in        : in STD_LOGIC_VECTOR(BRAM_DATA_WIDTH -1 downto 0);
        
        gpio_in             : in STD_LOGIC_VECTOR(NUM_SPECIALISTS downto 0);
        gpio_out            : out STD_LOGIC_VECTOR(0 downto 0);
                
        s_axis_tdata        : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axis_tvalid       : in  STD_LOGIC;
        s_axis_tready       : out STD_LOGIC;
        s_axis_tlast        : in  STD_LOGIC;
        
        m_axis_tdata        : out STD_LOGIC_VECTOR(CS_WORD_WIDTH - 1 downto 0);
        m_axis_tvalid       : out STD_LOGIC;
        m_axis_tready       : in STD_LOGIC;
        m_axis_tlast        : out STD_LOGIC
                            
    );
end inference_module;

architecture rtl of inference_module is
    signal enc_c2_data  : STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
    signal enc_c1_data  : STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
    signal enc_c0_data  : STD_LOGIC_VECTOR(ENC_BITS -1 downto 0);
    signal enc_valid    : STD_LOGIC;
    signal enc_ready    : STD_LOGIC;
    
    signal patch_x_pos   : STD_LOGIC_VECTOR(0 to POS_BITS -1);                 
    signal patch_y_pos   : STD_LOGIC_VECTOR(0 to POS_BITS -1);                 
    signal patch_c0_data : STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0); 
    signal patch_c1_data : STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0); 
    signal patch_c2_data : STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0); 
    signal patch_valid   : STD_LOGIC;
    signal patch_ready   : STD_LOGIC;
    signal patch_last    : STD_LOGIC;
    
    signal spclst_request   : STD_LOGIC;
    signal ps_request       : STD_LOGIC;  
    
    signal reset            : STD_LOGIC;     
    
begin
    
    reset       <= not n_reset;
    gpio_out(0) <= spclst_request and ps_request;
    
    pixel_encoding : entity work.pixel_encoding
        generic map (
            PX_BITS     => PX_BITS,
            ENC_BITS    => ENC_BITS
        )
    
        port map (
            clk             => clk            ,
            reset           => reset          ,      
            px_c0_data_in   => s_axis_tdata(3*PX_BITS -1 downto 2*PX_BITS),
            px_c1_data_in   => s_axis_tdata(2*PX_BITS -1 downto PX_BITS  ),
            px_c2_data_in   => s_axis_tdata(1*PX_BITS -1 downto 0        ),
            px_valid_in     => s_axis_tvalid   ,
            px_ready_out    => s_axis_tready  ,
            enc_c2_data_out => enc_c2_data,
            enc_c1_data_out => enc_c1_data,
            enc_c0_data_out => enc_c0_data,
            enc_valid_out   => enc_valid,
            enc_ready_in    => enc_ready
        );
    
    patches : entity work.patches_v5
        generic map (
            NUM_PS     => NUM_SPECIALISTS,
            PS0        => PS0       ,
            PS1        => PS1       ,
            PS2        => PS2       ,
            PS3        => PS3       ,
            DATA_DEPTH => IMG_SIZE  ,
            PX_BITS    => ENC_BITS  ,        
            POS_BITS   => POS_BITS
        )
        
        port map (
            clk                 => clk ,            
            reset               => reset,   
            wr_ready_intr       => wr_ready_intr,
            ps_data_in          => gpio_in(NUM_SPECIALISTS downto 1),
            ps_valid_in         => gpio_in(0),
            ps_request_out      => ps_request,
            px_c2_data_in       => enc_c2_data,
            px_c1_data_in       => enc_c1_data,
            px_c0_data_in       => enc_c0_data,
            px_valid_in         => enc_valid,
            px_ready_out        => enc_ready,
            patch_x_pos_out     => patch_x_pos,
            patch_y_pos_out     => patch_y_pos,
            patch_c2_data_out   => patch_c2_data,
            patch_c1_data_out   => patch_c1_data,
            patch_c0_data_out   => patch_c0_data,
            patch_valid_out     => patch_valid,
            patch_ready_in      => patch_ready,
            patch_last_out      => patch_last
        );
        
    clauses : entity work.clauses
        generic map (
            MAX_PS          => PS3         ,
            ENC_BITS        => ENC_BITS       ,
            POS_BITS        => POS_BITS       ,
            NUM_SPECIALISTS => NUM_SPECIALISTS,
            NUM_CLAUSES     => NUM_CLAUSES    ,
            NUM_CLASSES     => NUM_CLASSES    ,
            MAX_WEIGHT      => MAX_WEIGHT     
        )
        
        port map (
            clk                 => clk ,
            reset               => reset,
            bram_addr_out       => bram_addr_out,
            bram_en_out         => bram_en_out  ,
            bram_data_in        => bram_data_in ,
            spclst_data_in      => gpio_in(NUM_SPECIALISTS downto 1),
            spclst_valid_in     => gpio_in(0),
            spclst_request_out  => spclst_request,
            patch_x_pos_in      => patch_x_pos   ,
            patch_y_pos_in      => patch_y_pos   ,
            patch_c0_data_in    => patch_c0_data ,
            patch_c1_data_in    => patch_c1_data ,
            patch_c2_data_in    => patch_c2_data ,
            patch_valid_in      => patch_valid   ,
            patch_ready_out     => patch_ready   ,
            patch_last_in       => patch_last    ,
            cs_data_out         => m_axis_tdata ,
            cs_valid_out        => m_axis_tvalid,
            cs_ready_in         => m_axis_tready,
            cs_last_out         => m_axis_tlast              
        );

end rtl;
