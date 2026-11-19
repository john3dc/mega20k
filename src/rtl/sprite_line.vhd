-- Tang Nano 20K binding of the MiST sprite composition line.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sprite_line is
    port (
        clk : in std_logic;
        rd_addr, wr_addr : in std_logic_vector(8 downto 0);
        data : in std_logic_vector(6 downto 0);
        wr_en : in std_logic;
        q : out std_logic_vector(6 downto 0)
    );
end entity;

architecture gowin of sprite_line is
    type memory_type is array(0 to 511) of std_logic_vector(6 downto 0);
    signal ram : memory_type;
    attribute ram_style : string;
    attribute ram_style of ram : signal is "distributed";
begin
    -- SP3 and the copy/clear path change their outputs only on rising edges.
    -- The falling edge reads the preceding pixel. Its concurrent write can
    -- commit at the next rising edge, before the following read. This keeps
    -- read-before-write collisions and avoids a LUT clock on block RAM.
    process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' then
                ram(to_integer(unsigned(wr_addr))) <= data;
            end if;
        end if;
    end process;
    process(clk)
    begin
        if falling_edge(clk) then
            q <= ram(to_integer(unsigned(rd_addr)));
        end if;
    end process;
end architecture;
