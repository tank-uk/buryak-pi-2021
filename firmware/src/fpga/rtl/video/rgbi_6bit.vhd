-------------------------------------------------------------------[16.07.2019]
-- RGBI to 2:2:2 converter
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity rgbi_6bit is
	port (
	   I_CLK 	: in std_logic;
		I_RED		: in std_logic;
		I_GREEN	: in std_logic;
		I_BLUE	: in std_logic;
		I_BRIGHT : in std_logic;
		I_BLANK 	: in std_logic;
		O_RGB		: out std_logic_vector(5 downto 0)	-- RRGGBB
	);
end entity;

architecture rtl of rgbi_6bit is

signal irgb: std_logic_vector(3 downto 0);

begin

	irgb <= I_BRIGHT & I_RED & I_GREEN & I_BLUE;

	process(I_CLK, irgb, I_BLANK)
	begin
		if I_BLANK = '1' then 
			O_RGB <= (others => '0');
		elsif rising_edge(I_CLK) then
			case irgb(3 downto 0) is
				when "0000" | "1000" => O_RGB <= "000000";
				when "0001" => O_RGB <= "000010";
				when "0010" => O_RGB <= "001000";
				when "0011" => O_RGB <= "001010";
				when "0100" => O_RGB <= "100000";
				when "0101" => O_RGB <= "100010";
				when "0110" => O_RGB <= "101000";
				when "0111" => O_RGB <= "101010";				
				when "1001" => O_RGB <= "000011";
				when "1010" => O_RGB <= "001100";
				when "1011" => O_RGB <= "001111";
				when "1100" => O_RGB <= "110000";
				when "1101" => O_RGB <= "110011";
				when "1110" => O_RGB <= "111100";
				when "1111" => O_RGB <= "111111";
				when others => O_RGB <= "000000";
			end case;
		end if;
	end process;

end architecture;
