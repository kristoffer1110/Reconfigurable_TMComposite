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
               
        IMG_SIZE        : positive := 32;        
        PS0             : positive := 3; -- PS0 should be smallest patch size
        PS1             : positive := 4;
        PS2             : positive := 5;
        PS3             : positive := 7; -- PS3 should be largest patch size 
        PX_BITS         : positive := 8;
        POS_BITS        : positive := 29;
        ENC_BITS        : positive := 7
    );
    
    Port (
        clk                 : in STD_LOGIC;
        reset               : in STD_LOGIC;
        
        wr_ready_intr       : out STD_LOGIC;
        cs_valid_intr       : out STD_LOGIC;
        
        gpio_in             : in STD_LOGIC_VECTOR(NUM_SPECIALISTS downto 0);
        gpio_out            : out STD_LOGIC_VECTOR(0 downto 0);
        
        s_axis_tdata        : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axis_tvalid       : in  STD_LOGIC;
        s_axis_tready       : out STD_LOGIC;
        s_axis_tlast        : in  STD_LOGIC;
        
        cs_data_out         : out STD_LOGIC_VECTOR(NUM_CLASSES * (clog2(MAX_WEIGHT * NUM_CLAUSES) + 1) - 1 downto 0)
                            
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
    
begin
    
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
            DATA_WIDTH => IMG_SIZE  ,
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
            cs_data_out         => cs_data_out   ,
            cs_valid_intr       => cs_valid_intr               
        );

end rtl;
