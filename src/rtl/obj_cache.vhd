-- 128 sprite attributes, synchronous read, independent byte write enables.
-- Bind to the same pair of Gowin DPBs in the simulator and FPGA builds.
library ieee;
use ieee.std_logic_1164.all;

entity obj_cache is
    port (
        rdaddress, wraddress : in std_logic_vector(6 downto 0);
        byteena_a : in std_logic_vector(3 downto 0);
        clock, wren : in std_logic;
        data : in std_logic_vector(31 downto 0);
        q : out std_logic_vector(31 downto 0)
    );
end entity;

architecture gowin of obj_cache is
    component dpram32_block is
        port (
            clka, clkb, we_a, we_b : in std_logic;
            addr_a, addr_b : in std_logic_vector(9 downto 0);
            be_a, be_b : in std_logic_vector(3 downto 0);
            datain_a, datain_b : in std_logic_vector(31 downto 0);
            dataout_a, dataout_b : out std_logic_vector(31 downto 0)
        );
    end component;
begin
    store : dpram32_block port map (
        clka => clock, clkb => clock, we_a => '0', we_b => wren,
        addr_a => "000" & rdaddress, addr_b => "000" & wraddress,
        be_a => "1111", be_b => byteena_a,
        datain_a => (others => '0'), datain_b => data,
        dataout_a => q, dataout_b => open
    );
end architecture;
