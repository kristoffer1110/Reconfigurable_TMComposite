----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07.04.2026 10:09:34
-- Design Name: 
-- Module Name: patches_v5 - rtl
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
use work.math_pkg.all;
use work.types_pkg.all;
use work.functions_pkg.all;

entity patches_v5 is
    Generic (
        NUM_PS          : positive := 4; -- PS0 should be smallest patch size
        PS0             : positive := 3;
        PS1             : positive := 4;
        PS2             : positive := 5;
        PS3             : positive := 7; -- PS3 should be largest patch size 
        DATA_WIDTH      : positive := 32;
        PX_BITS         : positive := 8;
        POS_BITS        : positive := 29
    );
    
    Port (
        clk                 : in STD_LOGIC;
        reset               : in STD_LOGIC;
        
        wr_ready_intr       : out STD_LOGIC;
        
        ps_data_in          : in STD_LOGIC_VECTOR(NUM_PS -1 downto 0);
        ps_valid_in         : in STD_LOGIC;
        ps_request_out      : out STD_LOGIC;
        
        px_c0_data_in       : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_c1_data_in       : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);
        px_c2_data_in       : in STD_LOGIC_VECTOR (PX_BITS -1 downto 0);        
        px_valid_in         : in STD_LOGIC;
        px_ready_out        : out STD_LOGIC;
        
        patch_x_pos_out     : out STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_y_pos_out     : out STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_c0_data_out   : out STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS -1 downto 0);
        patch_c1_data_out   : out STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS -1 downto 0);
        patch_c2_data_out   : out STD_LOGIC_VECTOR(PS3 * PS3 * PX_BITS -1 downto 0);        
        patch_valid_out     : out STD_LOGIC;
        patch_ready_in      : in STD_LOGIC;
        patch_last_out      : out STD_LOGIC
        
    );
    
end patches_v5;

architecture rtl of patches_v5 is
    
    -- LINE BUFFER CONTROL
    signal ln_buff_wr_en        : STD_LOGIC_VECTOR (PS3 downto 0);
    signal ln_buff_rd_en        : STD_LOGIC_VECTOR (PS3 downto 0);
    signal ln_buff_out_mask     : pixel_row(PS3 - PS0 -1 downto 0)(PX_BITS -1 downto 0);

    -- LINE BUFFER OUTPUTS
    signal c0_px_rows           : pixel_row_arr (PS3 downto 0)(PS3 -1 downto 0)(PX_BITS -1 downto 0);
    signal c1_px_rows           : pixel_row_arr (PS3 downto 0)(PS3 -1 downto 0)(PX_BITS -1 downto 0);
    signal c2_px_rows           : pixel_row_arr (PS3 downto 0)(PS3 -1 downto 0)(PX_BITS -1 downto 0);
    
    -- ORDERED BUFFER OUTPUTS
    signal c0_patch             : pixel_row_arr (PS3 -1 downto 0)(PS3 -1 downto 0)(PX_BITS-1 downto 0);
    signal c1_patch             : pixel_row_arr (PS3 -1 downto 0)(PS3 -1 downto 0)(PX_BITS-1 downto 0);
    signal c2_patch             : pixel_row_arr (PS3 -1 downto 0)(PS3 -1 downto 0)(PX_BITS-1 downto 0);
    
    -- PIXEL EXCESS THRESHOLDS
    constant PX_EXC_THRESH_0    : natural   := PS0*DATA_WIDTH;
    constant PX_EXC_THRESH_1    : natural   := PS1*DATA_WIDTH;
    constant PX_EXC_THRESH_2    : natural   := PS2*DATA_WIDTH;
    constant PX_EXC_THRESH_3    : natural   := PS3*DATA_WIDTH;
    constant PX_EXC_MAX         : unsigned(clog2(PS3*DATA_WIDTH) -1 downto 0) := (others => '1');
    signal px_exc_thresh        : unsigned(clog2(PS3*DATA_WIDTH) -1 downto 0);
    
    -- NUMBER OF PATCHES PER ROW/COLUMN THRESHOLDS
    constant NUM_PATCHES_0      : positive := DATA_WIDTH - PS0 +1;
    constant NUM_PATCHES_1      : positive := DATA_WIDTH - PS1 +1;
    constant NUM_PATCHES_2      : positive := DATA_WIDTH - PS2 +1;
    constant NUM_PATCHES_3      : positive := DATA_WIDTH - PS3 +1;
    signal num_patches          : unsigned(clog2(NUM_PATCHES_0) -1 downto 0);
    
    -- COUNTERS
    signal wr_cntr              : unsigned(clog2(DATA_WIDTH) -1 downto 0);
    signal rd_cntr              : unsigned(clog2(DATA_WIDTH) -1 downto 0);
    signal px_exc_cntr          : unsigned(clog2((PS3 +1)*DATA_WIDTH) -1 downto 0);
    signal tot_rd_cntr          : unsigned(clog2((DATA_WIDTH - PS0 +1)*(DATA_WIDTH - PS0 +1)) -1 downto 0);
    
    -- ENABLES
    signal wr_en                : STD_LOGIC;
    signal rd_en                : STD_LOGIC;
    
    -- POINTERS
    signal top_row_pntr         : unsigned(clog2(PS3) -1 downto 0);
    signal wr_pntr              : unsigned(clog2(PS3) -1 downto 0);
    
    -- POSITION ENCODING
    signal x_pos                : STD_LOGIC_VECTOR(0 to POS_BITS -1); 
    signal y_pos                : STD_LOGIC_VECTOR(0 to POS_BITS -1);
    
    -- FSM
    constant NUM_STATES         : positive := 3;
    constant S_RESET            : STD_LOGIC_VECTOR(NUM_STATES -1 downto 0) := "001";
    constant S_SETUP            : STD_LOGIC_VECTOR(NUM_STATES -1 downto 0) := "010";
    constant S_ACTIVE           : STD_LOGIC_VECTOR(NUM_STATES -1 downto 0) := "100";
    constant WS_IDLE            : STD_LOGIC := '0';
    constant WS_WRITE           : STD_LOGIC := '1';
    constant RS_IDLE            : STD_LOGIC := '0';
    constant RS_READ            : STD_LOGIC := '1';
    signal state                : STD_LOGIC_VECTOR(NUM_STATES -1 downto 0);
    signal wr_state             : STD_LOGIC;
    signal rd_state             : STD_LOGIC;
    signal setup_fnsh           : STD_LOGIC;
    signal patch_fnsh           : STD_LOGIC;
    
begin
    
    comb_out : process(all)
    begin
    
        patch_x_pos_out     <= x_pos; 
        patch_y_pos_out     <= y_pos; 
        patch_c0_data_out   <= flatten_patch(c0_patch, PS3, PX_BITS);
        patch_c1_data_out   <= flatten_patch(c1_patch, PS3, PX_BITS);
        patch_c2_data_out   <= flatten_patch(c2_patch, PS3, PX_BITS);
        
        patch_valid_out <= '1' when rd_en = '1' and rd_cntr < num_patches else '0';
        px_ready_out    <= wr_en;
        patch_last_out  <= '1' when tot_rd_cntr = num_patches * num_patches - 1 else '0';
    
    end process;
    
    -- OUTPUT ORDERING: cx_patch(0)(0) = top left corner
    gen_ln_buff_out_ord : for i in 0 to 6 generate
    begin
        c0_patch(i) <= c0_px_rows( (to_integer(top_row_pntr) + i) mod 8 );
        c1_patch(i) <= c1_px_rows( (to_integer(top_row_pntr) + i) mod 8 );
        c2_patch(i) <= c2_px_rows( (to_integer(top_row_pntr) + i) mod 8 );
    end generate;

    -- CHANNEL 0 LINE BUFFER GENERATION
    c0_ln_buffs : for i in PS3 downto 0 generate
        ln_buff : entity work.line_buffer_v5
            generic map (
                PX_BITS     => PX_BITS ,
                MAX_PS      => PS3 ,
                MIN_PS      => PS0 ,
                DATA_WIDTH  => DATA_WIDTH     
            )
            
            port map (
                clk             => clk,               
                reset           => reset or patch_fnsh,
                wr_en           => ln_buff_wr_en(i) and wr_en,                
                rd_en           => ln_buff_rd_en(i) and rd_en,
                output_mask     => ln_buff_out_mask,                
                px_data_in      => px_c0_data_in, 
                px_valid_in     => px_valid_in,         
                px_row_data_out => c0_px_rows(i),
                px_row_ready_in => patch_ready_in         
            );
    end generate c0_ln_buffs;

    -- CHANNEL 1 LINE BUFFER GENERATION
    c1_ln_buffs : for i in PS3 downto 0 generate
        ln_buff : entity work.line_buffer_v5
            generic map (
                PX_BITS     => PX_BITS ,
                MAX_PS      => PS3 ,
                MIN_PS      => PS0 ,
                DATA_WIDTH  => DATA_WIDTH     
            )
            
            port map (
                clk             => clk,               
                reset           => reset or patch_fnsh,
                wr_en           => ln_buff_wr_en(i) and wr_en,                
                rd_en           => ln_buff_rd_en(i) and rd_en,
                output_mask     => ln_buff_out_mask,                
                px_data_in      => px_c1_data_in, 
                px_valid_in     => px_valid_in,         
                px_row_data_out => c1_px_rows(i),
                px_row_ready_in => patch_ready_in       
            );
            
    end generate c1_ln_buffs;

    -- CHANNEL 2 LINE BUFFER GENERATION
    c2_ln_buffs : for i in PS3 downto 0 generate
        ln_buff : entity work.line_buffer_v5
            generic map (
                PX_BITS     => PX_BITS ,
                MAX_PS      => PS3 ,
                MIN_PS      => PS0 ,
                DATA_WIDTH  => DATA_WIDTH     
            )
            
            port map (
                clk             => clk,               
                reset           => reset or patch_fnsh,
                wr_en           => ln_buff_wr_en(i) and wr_en,                
                rd_en           => ln_buff_rd_en(i) and rd_en,
                output_mask     => ln_buff_out_mask,
                px_data_in      => px_c2_data_in, 
                px_valid_in     => px_valid_in,         
                px_row_data_out => c2_px_rows(i),
                px_row_ready_in => patch_ready_in     
            );
            
    end generate c2_ln_buffs;
                
    -- WRITE COUNTER
    process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') or (patch_fnsh = '1') then
                wr_cntr     <= (others => '0');
            elsif (px_valid_in = '1') and (wr_en = '1') then
                wr_cntr     <= wr_cntr +1;                 
            end if;
        end if;
    end process; 
    
    -- READ COUNTER
    process(clk)
    begin
        if rising_edge(clk) then 
            if (reset = '1') or (patch_fnsh = '1') then
                rd_cntr     <= (others => '0');
            elsif (patch_ready_in = '1') and (rd_en = '1') then
                rd_cntr     <= rd_cntr +1;               
            end if;
        end if;
    end process;
    
    -- TOTAL READ COUNTER
    process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') or (patch_fnsh = '1') then
                tot_rd_cntr <= (others => '0');
            elsif patch_ready_in = '1' and rd_en = '1' and rd_cntr < num_patches then
                tot_rd_cntr <= tot_rd_cntr +1;
            end if;
        end if;
    end process;
    
    -- EXCESS PIXELS COUNTER
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                px_exc_cntr <= (others => '0');
            elsif ((px_valid_in and wr_en) = '1') and ((patch_ready_in nand rd_en) = '1') then
                px_exc_cntr <= px_exc_cntr +1;
            elsif ((px_valid_in nand wr_en) = '1') and ((patch_ready_in and rd_en) = '1') then
                px_exc_cntr <= px_exc_cntr -1;
            elsif patch_fnsh = '1' then
                px_exc_cntr <= (others => '0');             
            end if;
        end if;
    end process;
    
    -- X DIMENSION POSITION_ENCODING
    x_pos_shift : process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') or (patch_fnsh = '1') then
                x_pos <= (others => '0');
            elsif patch_ready_in = '1' and rd_en = '1' then
                if rd_cntr = DATA_WIDTH -1 then
                    x_pos <= (others => '0');
                else
                    x_pos <= '1' & x_pos(0 to POS_BITS -2);
                end if;     
            end if;
        end if;
    end process x_pos_shift;
    
    -- Y DIMENSION POSITION_ENCODING
    y_pos_shift : process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') or (patch_fnsh = '1') then
                y_pos <= (others => '0');
            elsif (patch_ready_in = '1') and (rd_en = '1') and (rd_cntr = DATA_WIDTH -1) then
                y_pos <= '1' & y_pos(0 to POS_BITS -2);                 
            end if;
        end if;
    end process y_pos_shift;      
    
    -- WRITE STATE FSM
    process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') or (patch_fnsh = '1') then
                wr_state        <= WS_IDLE;
                wr_en           <= '0';
                wr_ready_intr   <= '0';
            elsif setup_fnsh = '1' then
                case wr_state is
                    when WS_IDLE =>
                        if PX_EXC_MAX - px_exc_cntr >= DATA_WIDTH then
                            wr_state        <= WS_WRITE;
                            wr_en           <= '1';
                            wr_ready_intr   <= '1';
                        end if;
                    when WS_WRITE =>
                        wr_ready_intr   <= '0';
                        if wr_cntr = DATA_WIDTH -1 and px_valid_in = '1' then
                            wr_state    <= WS_IDLE;
                            wr_en       <= '0';
                        end if;
                    when others =>
                        wr_state        <= WS_IDLE;
                        wr_en           <= '0';
                        wr_ready_intr   <= '0';                   
                end case;
            end if;
         end if;
    end process;
    
    -- READ STATE FSM
    process(clk)
    begin
        if rising_edge(clk) then    
            if (reset = '1') or (patch_fnsh = '1') then
                rd_state    <= RS_IDLE;
                rd_en       <= '0';
            elsif (setup_fnsh = '1') then
                case rd_state is
                    when RS_IDLE => 
                        if px_exc_cntr >= px_exc_thresh then
                            rd_state    <= RS_READ;
                            rd_en       <= '1';
                        end if;
                    when RS_READ => 
                        if rd_cntr = DATA_WIDTH -1 then
                            rd_state    <= RS_IDLE;
                            rd_en       <= '0';
                        end if;
                    when others =>
                        rd_state    <= RS_IDLE;
                        rd_en       <= '0';
                end case;
            end if;
        end if;
    end process;
    
    -- FSM PROCESS
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state               <= S_RESET;
                ps_request_out      <= '0';
                px_exc_thresh       <= (others => '0');
                ln_buff_out_mask    <= (others => (others => '0'));
                ln_buff_wr_en       <= (others => '0');
                ln_buff_rd_en       <= (others => '0');
                top_row_pntr        <= (others => '0');
                setup_fnsh          <= '0';
                patch_fnsh          <= '0';                
                
            else
                case state is
                    when S_RESET =>
                        state           <= S_SETUP;
                        ps_request_out  <= '1';                        
                    
                    when S_SETUP =>
                        if (ps_valid_in = '1') then
                            state               <= S_ACTIVE;
                            ps_request_out      <= '0';
                            ln_buff_wr_en(0)    <= '1';
                            ln_buff_rd_en       <= (others => '0');                        
                            setup_fnsh          <= '1';
                            
                            case ps_data_in is
                                when "0001" => -- 3x3
                                    num_patches                             <= to_unsigned(NUM_PATCHES_0, num_patches'length);
                                    px_exc_thresh                           <= to_unsigned(PX_EXC_THRESH_0, px_exc_thresh'length);
                                    ln_buff_rd_en(PS0 -1 downto 0)          <= (PS0 -1 downto 0 => '1');                                 
                                    ln_buff_out_mask                        <= (others => (others => '1'));

                                when "0010" => -- 4x4
                                    num_patches                                         <= to_unsigned(NUM_PATCHES_1, num_patches'length);
                                    px_exc_thresh                                       <= to_unsigned(PX_EXC_THRESH_1, px_exc_thresh'length);
                                    ln_buff_rd_en(PS1 -1 downto 0)                      <= (PS1 -1 downto 0 => '1');                                    
                                    ln_buff_out_mask(PS3 - PS0 -1 downto PS1 - PS0)     <= (PS3 - PS0 -1 downto PS1 - PS0 => (others => '1'));
                                                                  
                                when "0100" => 
                                    num_patches                                         <= to_unsigned(NUM_PATCHES_2, num_patches'length);
                                    px_exc_thresh                                       <= to_unsigned(PX_EXC_THRESH_2, px_exc_thresh'length);
                                    ln_buff_rd_en(PS2 -1 downto 0)                      <= (PS2 -1 downto 0 => '1');                                                                  
                                    ln_buff_out_mask(PS3 - PS0 -1 downto PS2 - PS0)     <= (PS3 - PS0 -1 downto PS2 - PS0 => (others => '1'));

                                when "1000" => 
                                    num_patches                             <= to_unsigned(NUM_PATCHES_3, num_patches'length);
                                    px_exc_thresh                           <= to_unsigned(PX_EXC_THRESH_3, px_exc_thresh'length);
                                    ln_buff_rd_en(PS3 -1 downto 0)          <= (PS3 -1 downto 0 => '1');                                     
                                    ln_buff_out_mask                        <= (others => (others => '0'));

                                when others =>
                                    state               <= S_SETUP;
                                    ps_request_out      <= '1';
                                    top_row_pntr        <= (others => '0');
                                    ln_buff_wr_en(PS3)  <= '0';                        
                                    setup_fnsh          <= '0';                                                                       
                            end case;
                        end if;
                        
                    when S_ACTIVE =>
                        if (tot_rd_cntr = (num_patches)*(num_patches) -1) and (patch_ready_in = '1') then
                            patch_fnsh <= '1';
                        end if;
                        
                        if (px_valid_in = '1') and (wr_en = '1') and (wr_cntr = DATA_WIDTH -1) then
                            ln_buff_wr_en <= ln_buff_wr_en rol 1;
                        end if;
                        
                        if (patch_ready_in = '1') and (rd_en = '1') and (rd_cntr = DATA_WIDTH -1) then
                            ln_buff_rd_en <= ln_buff_rd_en rol 1;
                            
                            if top_row_pntr = PS3 then
                                top_row_pntr <= (others => '0');
                            else
                                top_row_pntr <= top_row_pntr +1;
                            end if;
                        end if;
                        
                        if patch_fnsh = '1' then
                            state               <= S_SETUP;
                            ps_request_out      <= '1';
                            top_row_pntr        <= (others => '0');
                            setup_fnsh          <= '0';
                            patch_fnsh          <= '0';                
                        end if;                        
                         
                    when others =>
                        state               <= S_RESET;
                        ps_request_out      <= '0';
                        px_exc_thresh       <= (others => '0');
                        ln_buff_out_mask    <= (others => (others => '0'));
                        ln_buff_wr_en       <= (others => '0');
                        ln_buff_rd_en       <= (others => '0');
                        top_row_pntr        <= (others => '0');
                        setup_fnsh          <= '0';
                        patch_fnsh          <= '0';
                        
                end case;
            end if;
        end if;
    end process;
end rtl;
         