-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
-- Date        : Tue May  5 21:42:52 2026
-- Host        : Kristoffers-PC running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               c:/Xilinx/projects/patch_reconstruction/patch_reconstruction.gen/sources_1/bd/design_1/ip/design_1_patch_gen_stream_0_1/design_1_patch_gen_stream_0_1_stub.vhdl
-- Design      : design_1_patch_gen_stream_0_1
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z020clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity design_1_patch_gen_stream_0_1 is
  Port ( 
    clk : in STD_LOGIC;
    n_reset : in STD_LOGIC;
    dma_intr : out STD_LOGIC;
    gpio_in : in STD_LOGIC_VECTOR ( 4 downto 0 );
    gpio_out : out STD_LOGIC_VECTOR ( 0 to 0 );
    s_axis_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axis_tvalid : in STD_LOGIC;
    s_axis_tready : out STD_LOGIC;
    s_axis_tlast : in STD_LOGIC;
    m_axis_tdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    m_axis_tvalid : out STD_LOGIC;
    m_axis_tready : in STD_LOGIC;
    m_axis_tlast : out STD_LOGIC
  );

end design_1_patch_gen_stream_0_1;

architecture stub of design_1_patch_gen_stream_0_1 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "clk,n_reset,dma_intr,gpio_in[4:0],gpio_out[0:0],s_axis_tdata[31:0],s_axis_tvalid,s_axis_tready,s_axis_tlast,m_axis_tdata[31:0],m_axis_tvalid,m_axis_tready,m_axis_tlast";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "top,Vivado 2024.1";
begin
end;
