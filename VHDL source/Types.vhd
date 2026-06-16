library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.math_pkg.all;

package types_pkg is
    
    -- PATCH SIZES
    constant PS0            : positive := 3;
    constant PS1            : positive := 4;
    constant PS2            : positive := 5;
    constant PS3            : positive := 7;
        
    -- DATA PARAMS
    constant IMG_SIZE       : positive := 32;            
    constant PX_BITS        : positive := 8;
    constant POS_BITS       : positive := IMG_SIZE - PS0;
    constant ENC_BITS       : positive := 7;       
    
    -- BRAM PARAMS
    constant BRAM_ADDR_WIDTH    : positive := 32;
    constant BRAM_DATA_WIDTH    : positive := 32;
    
    -- TSETLIN MACHINE PARAMS
    constant NUM_SPECIALISTS    : positive := 4;
    constant NUM_CLAUSES        : positive := 8;
    constant NUM_CLASSES        : positive := 10;
    constant MAX_WEIGHT         : signed   := 7;

    constant CS_WORD_WIDTH      : positive := 32;    
    constant CS_NUM_WORDS       : positive := 3;
    
    type pixel_row is array (natural range <>) of STD_LOGIC_VECTOR;
    type pixel_row_arr is array (natural range <>) of pixel_row;
    type enc_enable_arr is array (natural range <>) of STD_LOGIC_VECTOR;
    
    type weight_arr is array (natural range NUM_CLASSES -1 downto 0) of signed(clog2(MAX_WEIGHT) downto 0);
    type weight_matrix is array (natural range NUM_CLAUSES -1 downto 0) of weight_arr;
    
    type class_sums_arr is array (natural range NUM_CLASSES -1 downto 0) of signed(7 downto 0);
    
end package;