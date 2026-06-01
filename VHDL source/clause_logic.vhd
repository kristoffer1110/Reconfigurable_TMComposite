library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.math_pkg.all;
use work.types_pkg.all;
use work.functions_pkg.all;

entity clause_logic is

    Port ( 
        clk                 : in STD_LOGIC;
        reset               : in STD_LOGIC;
        
        bram_addr_out       : out STD_LOGIC_VECTOR(BRAM_ADDR_WIDTH -1 downto 0);
        bram_en_out         : out STD_LOGIC;
        bram_data_in        : in STD_LOGIC_VECTOR(BRAM_DATA_WIDTH -1 downto 0);        
                
        spclst_data_in      : in STD_LOGIC_VECTOR(NUM_SPECIALISTS -1 downto 0);
        spclst_valid_in     : in STD_LOGIC;
        spclst_request_out  : out STD_LOGIC;
        
        patch_x_pos_in      : in STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_y_pos_in      : in STD_LOGIC_VECTOR(0 to POS_BITS -1);
        patch_c0_data_in    : in STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
        patch_c1_data_in    : in STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
        patch_c2_data_in    : in STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
        patch_valid_in      : in STD_LOGIC;
        patch_ready_out     : out STD_LOGIC;
        patch_last_in       : in STD_LOGIC;
        
        m_axis_tdata        : out STD_LOGIC_VECTOR(CS_WORD_WIDTH - 1 downto 0);
        m_axis_tvalid       : out STD_LOGIC;
        m_axis_tready       : in STD_LOGIC;
        m_axis_tlast        : out STD_LOGIC
    
    );
end clause_logic;

architecture rtl of clause_logic is
    
    -- BIT WIDTH CONSTANTS
    constant SUM_BITS   : positive := clog2(MAX_WEIGHT * NUM_CLAUSES) + 1;
    constant WGHT_BITS  : positive := clog2(MAX_WEIGHT) +2;
    constant FEAT_BITS  : positive := 2*POS_BITS + 3*PS3*PS3*ENC_BITS;
    constant LIT_BITS   : positive := 2*FEAT_BITS;
    
    -- BRAM LAYOUT CONSTANTS
    constant WGHT_WORDS     : positive := NUM_CLAUSES * NUM_CLASSES;
    constant INC_WORDS      : positive := (LIT_BITS +31) / 32;
    constant SPCLST_WORDS   : positive := WGHT_WORDS + NUM_CLAUSES*INC_WORDS;
    constant LOAD_WORDS     : positive := SPCLST_WORDS;
    
    -- START CONTROL
    signal spclst_valid_prev    : STD_LOGIC;
    
    type inc_set_t is array(0 to NUM_CLAUSES -1) of STD_LOGIC_VECTOR(LIT_BITS -1 downto 0);
    
    -- PARAMETER STORAGE
    signal w_mtx        : weight_matrix;
    signal n_inc_set    : inc_set_t;
    
    -- BRAM LOAD CONTROL
    signal bram_base        : unsigned(BRAM_ADDR_WIDTH -1 downto 0);
    signal load_cntr         : integer range 0 to LOAD_WORDS + 1;    
    signal clause_i_cntr     : integer range 0 to NUM_CLAUSES - 1;
    signal class_j_cntr      : integer range 0 to NUM_CLASSES - 1;
    signal word_in_cl_cntr   : integer range 0 to INC_WORDS - 1;
    signal in_inc_region    : boolean;    
    
    -- CLAUSE LOGIC PIPELINE    
    signal features     : STD_LOGIC_VECTOR(2*POS_BITS + 3*PS3*PS3*ENC_BITS -1 downto 0);
    signal literals     : STD_LOGIC_VECTOR(2*features'length -1 downto 0);
    signal clause_vals  : STD_LOGIC_VECTOR(NUM_CLAUSES -1 downto 0);    
    
    -- REGISTERED PATCH INPUT
    signal x_pos_r      : STD_LOGIC_VECTOR(POS_BITS -1 downto 0);                  
    signal y_pos_r      : STD_LOGIC_VECTOR(POS_BITS -1 downto 0);                  
    signal c0_data_r    : STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
    signal c1_data_r    : STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
    signal c2_data_r    : STD_LOGIC_VECTOR(PS3 * PS3 * ENC_BITS -1 downto 0);
    
    -- CLAUSE OUTPUT CONTROL
    signal clause_rst   : STD_LOGIC;
    signal cs_data      : class_sums_arr;
    signal cs_data_flat : STD_LOGIC_VECTOR(CS_NUM_WORDS*CS_WORD_WIDTH -1 downto 0);
    signal stream_word  : STD_LOGIC;
    
    type state_t is (S_RESET, S_IDLE, S_LOAD, S_ACCUMULATE, S_STREAM);
    signal state : state_t;
    
begin
    
    output_assignments : process(all)
    begin
    
        patch_ready_out <= '1' when state = S_ACCUMULATE else '0';
        
        bram_addr_out <= STD_LOGIC_VECTOR(
            shift_left(resize(bram_base + to_unsigned(load_cntr, BRAM_ADDR_WIDTH), BRAM_ADDR_WIDTH), 2)
        );
        bram_en_out     <= '1' when state = S_LOAD else '0';
                
        cs_data_flat <= (others => '0');
        for i in 0 to NUM_CLASSES-1 loop
            cs_data_flat((i+1)*SUM_BITS - 1 downto i*SUM_BITS) <= STD_LOGIC_VECTOR(cs_data(i));
        end loop;
        
        m_axis_tvalid   <= '1' when state = S_STREAM else '0';
        m_axis_tlast    <= '1' when state = S_STREAM and stream_word = '1' else '0';
        
        if state = S_STREAM then
            if stream_word = '0' then
                m_axis_tdata <= cs_data_flat(CS_WORD_WIDTH -1 downto 0);
            else
                m_axis_tdata <= cs_data_flat(2*CS_WORD_WIDTH -1 downto CS_WORD_WIDTH);
            end if;
        else
            m_axis_tdata     <= (others => '0');
        end if;
        
        spclst_request_out  <= '1' when state = S_IDLE else '0';
        clause_rst          <= '0' when state = S_ACCUMULATE else '1';        
        
    end process;

    fsm : process(clk)
        variable sums       : class_sums_arr;
        
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state               <= S_RESET;
                spclst_valid_prev   <= '0';
                bram_base           <= (others => '0');
                load_cntr            <= 0;
                w_mtx               <= (others => (others => (others => '0')));                
                class_j_cntr         <= 0;
                clause_i_cntr        <= 0;
                in_inc_region       <= false;
                n_inc_set           <= (others => (others => '0'));
                word_in_cl_cntr      <= 0;                
                cs_data             <= (others => (others => '0'));
                stream_word         <= '0';
                                                                        
            else

                case state is
                    
                    when S_RESET =>
                        state               <= S_IDLE;
                        spclst_valid_prev   <= '1';
                    
                    when S_IDLE =>
                        
                        spclst_valid_prev   <= spclst_valid_in;
                        
                        if (spclst_valid_prev = '0') and (spclst_valid_in = '1') then
                            state               <= S_LOAD;
                            
                            case spclst_data_in is
                                when "0001" => bram_base <= to_unsigned(0 * SPCLST_WORDS, BRAM_ADDR_WIDTH);
                                when "0010" => bram_base <= to_unsigned(1 * SPCLST_WORDS, BRAM_ADDR_WIDTH);
                                when "0100" => bram_base <= to_unsigned(2 * SPCLST_WORDS, BRAM_ADDR_WIDTH);
                                when "1000" => bram_base <= to_unsigned(3 * SPCLST_WORDS, BRAM_ADDR_WIDTH);
                                when others => 
                                    state               <= S_IDLE;
                                    
                            end case;                                                   
                        end if;
                        
                    when S_LOAD =>
                        load_cntr    <= load_cntr + 1;
                        
                        if load_cntr /= 0 then
                            if not in_inc_region then
                                -- Weight region: clause_i_cntr/class_j_cntr step through w_mtx
                                w_mtx(clause_i_cntr)(class_j_cntr) 
                                    <= signed(bram_data_in(WGHT_BITS - 1 downto 0));
                                
                                if class_j_cntr = NUM_CLASSES - 1 then
                                    class_j_cntr  <= 0;
                                    if clause_i_cntr = NUM_CLAUSES - 1 then
                                        -- Entering include region next cycle
                                        clause_i_cntr  <= 0;
                                        in_inc_region <= true;
                                    else
                                        clause_i_cntr <= clause_i_cntr + 1;
                                    end if;
                                else
                                    class_j_cntr <= class_j_cntr + 1;
                                end if;
                                
                            else
                                -- Include region: clause_i_cntr/word_in_cl_cntr step through n_inc_set
                                for b in 0 to 31 loop
                                    if word_in_cl_cntr * 32 + b < LIT_BITS then
                                        n_inc_set(clause_i_cntr)(word_in_cl_cntr * 32 + b)
                                            <= bram_data_in(b);
                                    end if;
                                end loop;
                                
                                if word_in_cl_cntr = INC_WORDS - 1 then
                                    word_in_cl_cntr <= 0;
                                    if clause_i_cntr = NUM_CLAUSES - 1 then
                                        clause_i_cntr <= 0;  -- done
                                    else
                                        clause_i_cntr <= clause_i_cntr + 1;
                                    end if;
                                else
                                    word_in_cl_cntr <= word_in_cl_cntr + 1;
                                end if;
                            end if;
                        end if;
                        
                        if load_cntr = LOAD_WORDS then
                            state           <= S_ACCUMULATE;
                            load_cntr        <= 0;
                            clause_i_cntr    <= 0;
                            class_j_cntr     <= 0;
                            word_in_cl_cntr  <= 0;
                            in_inc_region   <= false;                            
                        end if;
                        
                    when S_ACCUMULATE =>
                        -- absorb patches until last arrives, then calculate class sums
                        if patch_valid_in = '1' and patch_last_in = '1' then
                            state           <= S_STREAM;
                            
                            sums := (others => (others => '0'));
                            for i in 0 to NUM_CLAUSES-1 loop
                                for j in 0 to NUM_CLASSES-1 loop
                                    if clause_vals(i) = '1' then
                                        sums(j) := sums(j) + w_mtx(i)(j);
                                    end if;
                                end loop;
                            end loop;
                            
                            cs_data         <= sums;
                        end if;
                    
                    when S_STREAM =>
                        
                        if m_axis_tready = '1' then
                            if stream_word = '0' and m_axis_tready = '1' then
                                stream_word <= '1';
                            else
                                state               <= S_IDLE;
                                stream_word         <= '0';
                            end if;
                        end if;

                    when others =>
                        state               <= S_RESET;
                        spclst_valid_prev   <= '0';
                        cs_data             <= (others => (others => '0'));
                        stream_word         <= '0';
                        w_mtx               <= (others => (others => (others => '0')));
                        n_inc_set           <= (others => (others => '0'));
                        bram_base           <= (others => '0');                
                        load_cntr            <= 0;
                        clause_i_cntr        <= 0;
                        class_j_cntr         <= 0;
                        word_in_cl_cntr      <= 0;
                        in_inc_region       <= false;                                                                  

                end case;
            end if;
        end if;
    end process;
    
    -- CLOCKING PATCH DATA
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
    
    clause_gen : for i in 0 to NUM_CLAUSES -1 generate
        clause : entity work.clause_circuit
            
            port map (
                clk             => clk,
                reset           => reset or clause_rst,
                lit_in          => literals,
                n_inc_in        => n_inc_set(i),
                clause_val_out  => clause_vals(i)
            );
    end generate clause_gen;
    
end rtl;