library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity memory is
port (
	CLK2X 		: in std_logic;
	CLKX	   	: in std_logic;
	CLK_CPU 		: in std_logic;
	
	enable_divmmc : in std_logic := '0';
	enable_zcontroller : in std_logic := '0';

	loader_act 	: in std_logic := '0';
	loader_ram_a: in std_logic_vector(20 downto 0);
	loader_ram_do: in std_logic_vector(7 downto 0);
	loader_ram_wr: in std_logic := '0';
	
	A           : in std_logic_vector(15 downto 0); -- address bus
	D 				: in std_logic_vector(7 downto 0);
	N_MREQ		: in std_logic;
	N_IORQ 		: in std_logic;
	N_WR 			: in std_logic;
	N_RD 			: in std_logic;
	N_M1 			: in std_logic;
	
	DO 			: out std_logic_vector(7 downto 0);
	N_OE 			: out std_logic;
	
	MA 			: out std_logic_vector(20 downto 0);
	MDI 			: in std_logic_vector(7 downto 0);
	MDO 			: out std_logic_vector(7 downto 0);
	N_MRD 		: out std_logic;
	N_MWR 		: out std_logic;
	
	RAM_BANK		: in std_logic_vector(2 downto 0);
	RAM_EXT 		: in std_logic_vector(2 downto 0);
	
	DIVMMC_A 	  : in std_logic_vector(5 downto 0);
	IS_DIVMMC_RAM : in std_logic;
	IS_DIVMMC_ROM : in std_logic;
	
	TRDOS 		: in std_logic;
	
	VA				: in std_logic_vector(13 downto 0);
	VID_PAGE 	: in std_logic := '0';
	VID_DO 		: out std_logic_vector(7 downto 0);
	
	ROM_BANK : in std_logic := '0';
	EXT_ROM_BANK : in std_logic_vector(2 downto 0) := "000"
);
end memory;

architecture RTL of memory is

	signal is_rom : std_logic := '0';
	signal is_ram : std_logic := '0';
	
	signal rom_page : std_logic_vector(1 downto 0) := "00";
	signal ram_page : std_logic_vector(6 downto 0) := "0000000";

	signal vid_wr 		: std_logic;
	signal vid_scr 	: std_logic;

begin

	U_VRAM: entity work.altram1
	port map(
		clock_a => CLK2X,
		clock_b => CLK2X,
		address_a => vid_scr & A(12 downto 0),
		address_b => vid_page & VA(12 downto 0),
		data_a => D,
		data_b => "11111111",
		q_a => open,
		q_b => VID_DO,
		wren_a => vid_wr,
		wren_b => '0'
	);
	
	is_rom <= '1' when N_MREQ = '0' and ((A(15 downto 14)  = "00" and (enable_divmmc = '0' or (IS_DIVMMC_ROM = '0' and IS_DIVMMC_RAM = '0'))) or (enable_divmmc = '1' and IS_DIVMMC_ROM = '1')) else '0';
	is_ram <= '1' when N_MREQ = '0' and ((A(15 downto 14) /= "00" and (enable_divmmc = '0' or (IS_DIVMMC_ROM = '0' and IS_DIVMMC_RAM = '0'))) or (enable_divmmc = '1' and IS_DIVMMC_RAM = '1')) else '0';
	
	vid_wr <= '1' when N_MREQ = '0' and N_WR = '0' and (ram_page = "0000101" or ram_page = "0000111" ) and A(13) = '0' else '0';
	vid_scr <= '1' when ram_page = "0000111" and A(13) = '0' else '0';
	
	-- 00 - bank 0, ESXDOS 0.8.7 or GLUK
	-- 01 - bank 1, empty or TRDOS
	-- 10 - bank 2, Basic-128
	-- 11 - bank 3, Basic-48
	rom_page <= "00" when enable_divmmc = '1' and IS_DIVMMC_ROM = '1' else 
		(not(TRDOS)) & ROM_BANK when enable_zcontroller = '1' else
		'1' & ROM_BANK;
		
	N_MRD <= '1' when loader_act = '1' else 
				'0' when (is_rom = '1' and N_RD = '0') or 
							(N_RD = '0' and N_MREQ = '0') 
					 else '1';  
				
	N_MWR <= not loader_ram_wr when loader_act = '1' else 
				'0' when is_ram = '1' and N_WR = '0'
				 else '1';

	DO <= MDI;
	N_OE <= '0' when (is_ram = '1' or is_rom = '1') and N_RD = '0' else '1';
		
	ram_page <=	
				"11" & DIVMMC_A(5 downto 1) when IS_DIVMMC_RAM = '1' and enable_divmmc = '1' else -- 512k divmmc ram
				"10" & EXT_ROM_BANK(2 downto 0) & rom_page(1 downto 0) when is_rom = '1' else -- 8x64k roms
				"0000000" when A(15) = '0' and A(14) = '0' else
				"0000101" when A(15) = '0' and A(14) = '1' else
				"0000010" when A(15) = '1' and A(14) = '0' else
				"0" & RAM_EXT(2 downto 0) & RAM_BANK(2 downto 0);

	MA(20 downto 0) <= loader_ram_a(20 downto 0) when loader_act = '1' else -- loader ram
		ram_page(6 downto 0) & DIVMMC_A(0) & A(12 downto 0) when enable_divmmc = '1' and (IS_DIVMMC_RAM = '1' or IS_DIVMMC_ROM = '1') else -- divmmc ram
		ram_page(6 downto 0) & A(13 downto 0) when IS_DIVMMC_RAM = '0' and IS_DIVMMC_ROM = '0'; -- spectrum ram 
	
	MDO(7 downto 0) <= 
		loader_ram_do when loader_act = '1' else -- loader DO
		D(7 downto 0) when is_ram = '1' and N_WR = '0' else -- cpu DO
		(others => 'Z');
	
end RTL;

