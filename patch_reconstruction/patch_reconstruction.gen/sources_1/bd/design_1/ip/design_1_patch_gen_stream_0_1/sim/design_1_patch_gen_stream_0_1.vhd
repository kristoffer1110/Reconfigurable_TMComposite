-- (c) Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- (c) Copyright 2022-2026 Advanced Micro Devices, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
-- DO NOT MODIFY THIS FILE.

-- IP VLNV: xilinx.com:user:patch_gen_stream:1.0
-- IP Revision: 1

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY design_1_patch_gen_stream_0_1 IS
  PORT (
    clk : IN STD_LOGIC;
    n_reset : IN STD_LOGIC;
    dma_intr : OUT STD_LOGIC;
    gpio_in : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
    gpio_out : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    s_axis_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    s_axis_tvalid : IN STD_LOGIC;
    s_axis_tready : OUT STD_LOGIC;
    s_axis_tlast : IN STD_LOGIC;
    m_axis_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axis_tvalid : OUT STD_LOGIC;
    m_axis_tready : IN STD_LOGIC;
    m_axis_tlast : OUT STD_LOGIC
  );
END design_1_patch_gen_stream_0_1;

ARCHITECTURE design_1_patch_gen_stream_0_1_arch OF design_1_patch_gen_stream_0_1 IS
  ATTRIBUTE DowngradeIPIdentifiedWarnings : STRING;
  ATTRIBUTE DowngradeIPIdentifiedWarnings OF design_1_patch_gen_stream_0_1_arch: ARCHITECTURE IS "yes";
  COMPONENT top IS
    GENERIC (
      NUM_GPIO_IN : INTEGER;
      NUM_GPIO_OUT : INTEGER;
      NUM_PS : INTEGER;
      PS0 : INTEGER;
      PS1 : INTEGER;
      PS2 : INTEGER;
      PS3 : INTEGER;
      IMG_SIZE : INTEGER;
      PX_BITS : INTEGER
    );
    PORT (
      clk : IN STD_LOGIC;
      n_reset : IN STD_LOGIC;
      dma_intr : OUT STD_LOGIC;
      gpio_in : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
      gpio_out : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
      s_axis_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      s_axis_tvalid : IN STD_LOGIC;
      s_axis_tready : OUT STD_LOGIC;
      s_axis_tlast : IN STD_LOGIC;
      m_axis_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      m_axis_tvalid : OUT STD_LOGIC;
      m_axis_tready : IN STD_LOGIC;
      m_axis_tlast : OUT STD_LOGIC
    );
  END COMPONENT top;
  ATTRIBUTE X_INTERFACE_INFO : STRING;
  ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
  ATTRIBUTE X_INTERFACE_PARAMETER OF clk: SIGNAL IS "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF m_axis:s_axis, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, INSERT_VIP 0";
  ATTRIBUTE X_INTERFACE_INFO OF clk: SIGNAL IS "xilinx.com:signal:clock:1.0 clk CLK";
  ATTRIBUTE X_INTERFACE_PARAMETER OF dma_intr: SIGNAL IS "XIL_INTERFACENAME dma_intr, SENSITIVITY LEVEL_HIGH, PortWidth 1";
  ATTRIBUTE X_INTERFACE_INFO OF dma_intr: SIGNAL IS "xilinx.com:signal:interrupt:1.0 dma_intr INTERRUPT";
  ATTRIBUTE X_INTERFACE_PARAMETER OF m_axis_tdata: SIGNAL IS "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  ATTRIBUTE X_INTERFACE_INFO OF m_axis_tdata: SIGNAL IS "xilinx.com:interface:axis:1.0 m_axis TDATA";
  ATTRIBUTE X_INTERFACE_INFO OF m_axis_tlast: SIGNAL IS "xilinx.com:interface:axis:1.0 m_axis TLAST";
  ATTRIBUTE X_INTERFACE_INFO OF m_axis_tready: SIGNAL IS "xilinx.com:interface:axis:1.0 m_axis TREADY";
  ATTRIBUTE X_INTERFACE_INFO OF m_axis_tvalid: SIGNAL IS "xilinx.com:interface:axis:1.0 m_axis TVALID";
  ATTRIBUTE X_INTERFACE_PARAMETER OF n_reset: SIGNAL IS "XIL_INTERFACENAME n_reset, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  ATTRIBUTE X_INTERFACE_INFO OF n_reset: SIGNAL IS "xilinx.com:signal:reset:1.0 n_reset RST";
  ATTRIBUTE X_INTERFACE_PARAMETER OF s_axis_tdata: SIGNAL IS "XIL_INTERFACENAME s_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, PHASE 0.0, CLK_DOMAIN design_1_processing_system7_0_0_FCLK_CLK0, LAYERED_METADATA undef, INSERT_VIP 0";
  ATTRIBUTE X_INTERFACE_INFO OF s_axis_tdata: SIGNAL IS "xilinx.com:interface:axis:1.0 s_axis TDATA";
  ATTRIBUTE X_INTERFACE_INFO OF s_axis_tlast: SIGNAL IS "xilinx.com:interface:axis:1.0 s_axis TLAST";
  ATTRIBUTE X_INTERFACE_INFO OF s_axis_tready: SIGNAL IS "xilinx.com:interface:axis:1.0 s_axis TREADY";
  ATTRIBUTE X_INTERFACE_INFO OF s_axis_tvalid: SIGNAL IS "xilinx.com:interface:axis:1.0 s_axis TVALID";
BEGIN
  U0 : top
    GENERIC MAP (
      NUM_GPIO_IN => 5,
      NUM_GPIO_OUT => 1,
      NUM_PS => 4,
      PS0 => 3,
      PS1 => 4,
      PS2 => 5,
      PS3 => 7,
      IMG_SIZE => 32,
      PX_BITS => 8
    )
    PORT MAP (
      clk => clk,
      n_reset => n_reset,
      dma_intr => dma_intr,
      gpio_in => gpio_in,
      gpio_out => gpio_out,
      s_axis_tdata => s_axis_tdata,
      s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      s_axis_tlast => s_axis_tlast,
      m_axis_tdata => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast => m_axis_tlast
    );
END design_1_patch_gen_stream_0_1_arch;
