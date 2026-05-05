----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.03.2026 14:36:25
-- Design Name: 
-- Module Name: Functions - Behavioral
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
use work.types_pkg.all;

package functions_pkg is

    function clog2(n : natural) return natural;
    function flatten_patch (
        patch   : pixel_row_arr; 
        PS      : positive; 
        PX_BITS : positive
    ) return STD_LOGIC_VECTOR;
    
    function flatten_row(
        row     : pixel_row;
        PS      : positive;
        PX_BITS : positive
    ) return STD_LOGIC_VECTOR;
    
    function "and" (l, r : pixel_row) return pixel_row;
end package;

package body functions_pkg is
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
    
    -- top-row major, (0,0) at MSB
    function flatten_patch(
            patch   : pixel_row_arr;
            PS      : positive;
            PX_BITS : positive
        ) return STD_LOGIC_VECTOR is
            variable result : STD_LOGIC_VECTOR(PS * PS * PX_BITS - 1 downto 0);
            variable idx    : natural := 0;
        begin
            for row in 0 to PS - 1 loop
                for col in 0 to PS - 1 loop
                    result(
                        (PS * PS * PX_BITS - 1) - (idx * PX_BITS)
                        downto
                        (PS * PS * PX_BITS) - ((idx + 1) * PX_BITS)
                    ) := patch(row)(col);
                    idx := idx + 1;
                end loop;
            end loop;
            return result;
        end function;
    
    function flatten_row(
        row     : pixel_row;
        PS      : positive;
        PX_BITS : positive
    ) return STD_LOGIC_VECTOR is
        variable result : STD_LOGIC_VECTOR(PS * PX_BITS - 1 downto 0);   
        variable idx    : natural := 0;
    begin
        for col in 0 to PS -1 loop
            result(
                (PS * PX_BITS -1) - (idx * PX_BITS)
                downto
                (PS * PX_BITS) - ((idx + 1) * PX_BITS)
            ) := row(PS -1 -col);
            idx := idx +1;
        end loop;
        return result;
    end function; 
        
    function "and" (l, r : pixel_row) return pixel_row is
        variable result : pixel_row(l'range)(l(l'left)'range);
    begin
        for i in l'range loop
            result(i) := l(i) and r(i);
        end loop;
        return result;
    end function;    
end package body;
