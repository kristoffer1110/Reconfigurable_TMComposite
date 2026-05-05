// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
// Date        : Tue May  5 22:39:26 2026
// Host        : Kristoffers-PC running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/Xilinx/projects/patch_reconstruction/patch_reconstruction.gen/sources_1/bd/design_1/ip/design_1_patch_gen_stream_0_1/design_1_patch_gen_stream_0_1_stub.v
// Design      : design_1_patch_gen_stream_0_1
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z020clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "top,Vivado 2024.1" *)
module design_1_patch_gen_stream_0_1(clk, n_reset, dma_intr, gpio_in, gpio_out, 
  s_axis_tdata, s_axis_tvalid, s_axis_tready, s_axis_tlast, m_axis_tdata, m_axis_tvalid, 
  m_axis_tready, m_axis_tlast)
/* synthesis syn_black_box black_box_pad_pin="n_reset,dma_intr,gpio_in[4:0],gpio_out[0:0],s_axis_tdata[31:0],s_axis_tvalid,s_axis_tready,s_axis_tlast,m_axis_tdata[31:0],m_axis_tvalid,m_axis_tready,m_axis_tlast" */
/* synthesis syn_force_seq_prim="clk" */;
  input clk /* synthesis syn_isclock = 1 */;
  input n_reset;
  output dma_intr;
  input [4:0]gpio_in;
  output [0:0]gpio_out;
  input [31:0]s_axis_tdata;
  input s_axis_tvalid;
  output s_axis_tready;
  input s_axis_tlast;
  output [31:0]m_axis_tdata;
  output m_axis_tvalid;
  input m_axis_tready;
  output m_axis_tlast;
endmodule
