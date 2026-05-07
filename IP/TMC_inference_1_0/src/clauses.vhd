----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06.05.2026 11:50:37
-- Design Name: 
-- Module Name: clauses - rtl
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity clauses is
    Generic (
        MAX_PS          : positive := 7; 
        ENC_BITS        : positive := 7;
        POS_BITS        : positive := 29;
        NUM_SPECIALISTS : positive := NUM_SPECIALISTS;
        NUM_CLAUSES     : positive := NUM_CLAUSES;
        NUM_CLASSES     : positive := NUM_CLASSES;
        MAX_WEIGHT      : positive := MAX_WEIGHT
        
    );
    
    Port ( 
        clk                 : in STD_LOGIC;
        reset               : in STD_LOGIC;
                
        spclst_data_in      : in STD_LOGIC_VECTOR(NUM_SPECIALISTS -1 downto 0);
        spclst_valid_in     : in STD_LOGIC;
        spclst_request_out  : out STD_LOGIC;
        
        patch_x_pos_in      : in STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_y_pos_in      : in STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_c0_data_in    : in STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
        patch_c1_data_in    : in STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
        patch_c2_data_in    : in STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
        patch_valid_in      : in STD_LOGIC;
        patch_ready_out     : out STD_LOGIC;
        patch_last_in       : in STD_LOGIC;
        
        cs_data_out         : out STD_LOGIC_VECTOR(NUM_CLASSES * (clog2(MAX_WEIGHT * NUM_CLAUSES) + 1) - 1 downto 0);
        cs_valid_intr       : out STD_LOGIC
    
    );
end clauses;

architecture rtl of clauses is
    constant SUM_BITS : positive := clog2(MAX_WEIGHT * NUM_CLAUSES) + 1;

    constant w_mtx_0    : weight_matrix := (others => (others => to_signed(MAX_WEIGHT   , clog2(MAX_WEIGHT) +2)));
    constant w_mtx_1    : weight_matrix := (others => (others => to_signed(MAX_WEIGHT -1, clog2(MAX_WEIGHT) +2)));
    constant w_mtx_2    : weight_matrix := (others => (others => to_signed(MAX_WEIGHT -2, clog2(MAX_WEIGHT) +2)));
    constant w_mtx_3    : weight_matrix := (others => (others => to_signed(MAX_WEIGHT -3, clog2(MAX_WEIGHT) +2)));
    signal w_mtx        : weight_matrix;    
    
    signal clause_vals  : STD_LOGIC_VECTOR(NUM_CLAUSES -1 downto 0);
    signal features     : STD_LOGIC_VECTOR(2*POS_BITS + 3*MAX_PS*MAX_PS*ENC_BITS -1 downto 0);
    signal literals     : STD_LOGIC_VECTOR(2*features'length -1 downto 0);
    
    signal x_pos_r      : STD_LOGIC_VECTOR(POS_BITS -1 downto 0);                  
    signal y_pos_r      : STD_LOGIC_VECTOR(POS_BITS -1 downto 0);                  
    signal c0_data_r    : STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
    signal c1_data_r    : STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
    signal c2_data_r    : STD_LOGIC_VECTOR(MAX_PS * MAX_PS * ENC_BITS -1 downto 0);
    signal last_r       : STD_LOGIC;
    
    signal clause_rst   : STD_LOGIC;
    signal cs_data      : class_sums_arr;

    type state_t is (S_RESET, S_SETUP, S_ACCUMULATE, S_CALCULATE, S_RESET_CLAUSES);
    signal state : state_t;
    
begin

    output_flattening : process(all)
    begin
    
        for i in 0 to NUM_CLASSES-1 loop
            cs_data_out(
                (i+1)*SUM_BITS - 1 downto i*SUM_BITS
            ) <= STD_LOGIC_VECTOR(cs_data(i));
        end loop;
        
    end process;

    fsm : process(clk)
        variable sums : class_sums_arr;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state               <= S_RESET;
                cs_data             <= (others => (others => '0'));
                cs_valid_intr       <= '0';
                clause_rst          <= '0';
                w_mtx               <= (others => (others => (others => '0')));
                spclst_request_out  <= '0';
                patch_ready_out     <= '0';
            
            else
                clause_rst <= '0'; -- default

                case state is
                    
                    when S_RESET =>
                        spclst_request_out <= '1';
                        state <= S_SETUP;
                    
                    when S_SETUP =>
                        if spclst_valid_in = '1' then
                            state               <= S_ACCUMULATE;                        
                            spclst_request_out  <= '0';
                            patch_ready_out     <= '1';
                            
                            case spclst_data_in is
                                when "0001" => w_mtx <= w_mtx_0;
                                when "0010" => w_mtx <= w_mtx_1;
                                when "0100" => w_mtx <= w_mtx_2;
                                when "1000" => w_mtx <= w_mtx_3;
                                when others => 
                                    w_mtx               <= (others => (others => (others => '0')));
                                    state               <= S_SETUP;
                                    spclst_request_out  <= '1';
                                    patch_ready_out     <= '0';
                            end case;
                        end if;
                            
                    when S_ACCUMULATE =>
                        -- absorb patches; when last arrives, calculate class sums
                        if patch_valid_in = '1' and patch_last_in = '1' then
                            patch_ready_out <= '0';
                            state <= S_CALCULATE;
                        end if;
                            
                    when S_CALCULATE =>
                        sums := (others => (others => '0'));
                        for i in 0 to NUM_CLAUSES-1 loop
                            for j in 0 to NUM_CLASSES-1 loop
                                if clause_vals(i) = '1' then
                                    sums(j) := sums(j) + w_mtx(i)(j);
                                end if;
                            end loop;
                        end loop;
                        
                        state           <= S_RESET_CLAUSES;
                        cs_data         <= sums;                        
                        cs_valid_intr   <= '1';
                        clause_rst      <= '1';

                    when S_RESET_CLAUSES =>
                        state               <= S_SETUP;
                        spclst_request_out  <= '1';
                        clause_rst          <= '0';
                        cs_valid_intr       <= '0';

                    when others =>
                        state <= S_RESET;
                        cs_data             <= (others => (others => '0'));
                        cs_valid_intr       <= '0';
                        clause_rst          <= '0';
                        w_mtx               <= (others => (others => (others => '0')));
                        spclst_request_out  <= '0';
                        patch_ready_out     <= '0';                        

                end case;
            end if;
        end if;
    end process;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                x_pos_r     <= (others => '0');
                y_pos_r     <= (others => '0');
                c0_data_r   <= (others => '0');
                c1_data_r   <= (others => '0');
                c2_data_r   <= (others => '0');
                
            elsif patch_valid_in = '1' then
                x_pos_r     <= patch_x_pos_in;
                y_pos_r     <= patch_y_pos_in;
                c0_data_r   <= patch_c0_data_in;
                c1_data_r   <= patch_c1_data_in;
                c2_data_r   <= patch_c2_data_in;
                
           end if;
       end if;   
    end process;
    
    process(all)
    begin
        features <= y_pos_r & 
                    x_pos_r & 
                    c0_data_r & 
                    c1_data_r & 
                    c2_data_r ;
                    
        literals <= features & not features;
    end process;
    
    clauses : for i in 0 to NUM_CLAUSES -1 generate
        clause : entity work.clause_logic
            generic map (
                LIT_BITS => literals'length,
                POS_BITS => POS_BITS
            )
            
            port map (
                clk             => clk,
                reset           => reset or clause_rst,
                n_empty_in      => '1',
                lit_in          => literals,
                n_inc_in        => (others => '1'),
                clause_val_out  => clause_vals(i)
            );
    end generate clauses;
    
end rtl;
