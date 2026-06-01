library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package math_pkg is

    function clog2(n : natural) return natural;

end package;

package body math_pkg is

    function clog2(n : natural) return natural is
        variable v : natural := n - 1;
        variable r : natural := 0;
    begin
        while v > 0 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;
    
end package body;