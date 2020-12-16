library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity memory is
generic (
		enable_divmmc 	    : boolean := true;
		enable_zcontroller : boolean := false
);
port (
	CLK28 		: in std_logic;
	CLK14	   	: in std_logic;
	CLK7			: in std_logic;
	HCNT0 		: in std_logic;
	TURBO 		: in std_logic;

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
	MD 			: inout std_logic_vector(7 downto 0);
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
	
	VBUS_MODE_O : out std_logic;
	VID_RD_O 	: out std_logic;
	
	ROM_BANK : in std_logic := '0';
	EXT_ROM_BANK : in std_logic_vector(2 downto 0) := "000"
);
end memory;

architecture RTL of memory is

	signal buf_md		: std_logic_vector(7 downto 0) := "11111111";
	signal is_buf_wr	: std_logic := '0';	
	
	signal is_rom : std_logic := '0';
	signal is_ram : std_logic := '0';
	
	signal rom_page : std_logic_vector(1 downto 0) := "00";
	signal ram_page : std_logic_vector(6 downto 0) := "0000000";

	signal vbus_req	: std_logic := '1';
	signal vbus_mode	: std_logic := '1';	
	signal vbus_rdy	: std_logic := '1';
	signal vid_rd 		: std_logic := '0';
	
	signal vbus_ack1 	: std_logic := '1';
	signal vbus_mode1 : std_logic := '1';
	signal vid_rd1 	: std_logic := '0';

	signal vbus_ack2 	: std_logic := '1';
	signal vbus_mode2 : std_logic := '1';
	signal vid_rd2 	: std_logic := '0';

begin

	is_rom <= '1' when N_MREQ = '0' and ((A(15 downto 14)  = "00" and IS_DIVMMC_ROM = '0' and IS_DIVMMC_RAM = '0') or IS_DIVMMC_ROM = '1') else '0';
	is_ram <= '1' when N_MREQ = '0' and ((A(15 downto 14) /= "00" and IS_DIVMMC_ROM = '0' and IS_DIVMMC_RAM = '0') or IS_DIVMMC_RAM = '1') else '0';
	
	-- 00 - bank 0, ESXDOS 0.8.7 or GLUK
	-- 01 - bank 1, empty or TRDOS
	-- 10 - bank 2, Basic-128
	-- 11 - bank 3, Basic-48
	rom_page <= "00" when enable_divmmc and IS_DIVMMC_ROM = '1' else 
		(not(TRDOS)) & ROM_BANK when enable_zcontroller else
		'1' & ROM_BANK;
		
	vbus_req <= '0' when ( N_MREQ = '0' or N_IORQ = '0' ) and ( N_WR = '0' or N_RD = '0' ) else '1';
	vbus_rdy <= '0' when (TURBO = '0' and (CLK7 = '0' or HCNT0 = '0')) or (TURBO = '1' and (CLK14 = '0' or CLK7='0'))  else '1';

	VBUS_MODE_O <= vbus_mode;
	VID_RD_O <= vid_rd;
	
	N_MRD <= '1' when loader_act = '1' else 
				'0' when (is_rom = '1' and N_RD = '0') or (vbus_mode = '1' and vbus_rdy = '0') or (vbus_mode = '0' and N_RD = '0' and N_MREQ = '0') else '1';  
				
	N_MWR <= not loader_ram_wr when loader_act = '1' else 
				'0' when vbus_mode = '0' and is_ram = '1' and N_WR = '0' and ((TURBO = '0' and HCNT0 = '0') or (TURBO = '1' AND CLK7 = '0')) else '1';

	is_buf_wr <= '1' when vbus_mode = '0' and ((TURBO = '0' and HCNT0 = '0') or (TURBO = '1' and CLK7 = '0')) else '0';
	
	DO <= buf_md;
	N_OE <= '0' when (is_ram = '1' or is_rom = '1') and N_RD = '0' else '1';
		
	ram_page <=	
				"11" & DIVMMC_A(5 downto 1) when IS_DIVMMC_RAM = '1' else -- 512k divmmc ram
				"10" & EXT_ROM_BANK(2 downto 0) & rom_page(1 downto 0) when is_rom = '1' and vbus_mode = '0' else -- 8x64k roms
				"0000000" when A(15) = '0' and A(14) = '0' else
				"0000101" when A(15) = '0' and A(14) = '1' else
				"0000010" when A(15) = '1' and A(14) = '0' else
				"0" & RAM_EXT(2 downto 0) & RAM_BANK(2 downto 0);

	MA(13 downto 0) <= 
		loader_ram_a(13 downto 0) when loader_act = '1' else -- loader ram
		DIVMMC_A(0) & A(12 downto 0) when vbus_mode = '0' and IS_DIVMMC_RAM = '1' else -- divmmc ram 
		DIVMMC_A(0) & A(12 downto 0) when vbus_mode = '0' and IS_DIVMMC_ROM = '1' else -- divmmc rom
		A(13 downto 0) when vbus_mode = '0' else -- spectrum ram 
		VA; -- video ram

	MA(20 downto 14) <= loader_ram_a(20 downto 14) when loader_act = '1' else -- loader ram
								ram_page(6 downto 0) when vbus_mode = '0' else 
								"00001" & VID_PAGE & '1';
	
	MD(7 downto 0) <= 
		loader_ram_do when loader_act = '1' else -- loader DO
		D(7 downto 0) when vbus_mode = '0' and ((is_ram = '1' or (N_IORQ = '0' and N_M1 = '1')) and N_WR = '0') else 
		(others => 'Z');
		
	-- fill memory buf
	process(is_buf_wr)
	begin 
		if (is_buf_wr'event and is_buf_wr = '0') then  -- high to low transition to lattch the MD into BUF
			buf_md(7 downto 0) <= MD(7 downto 0);
		end if;
	end process;	
	
	-- video mem
	process( CLK14, CLK7, HCNT0, vbus_mode1, vid_rd1, vbus_req, vbus_ack1, TURBO )
	begin
		-- lower edge of 7 mhz clock
		if CLK14'event and CLK14 = '1' then 
			if (HCNT0 = '1' and CLK7 = '0' and TURBO = '0') then
				if vbus_req = '0' and vbus_ack1 = '1' then
					vbus_mode1 <= '0';
				else
					vbus_mode1 <= '1';
					vid_rd1 <= not vid_rd1;
				end if;	
				vbus_ack1 <= vbus_req;
			end if;		
		end if;		
	end process;

	process( CLK28, CLK14, CLK7, HCNT0, vbus_mode2, vid_rd2, vbus_req, vbus_ack2, TURBO )
	begin
		-- lower edge of 14 mhz clock
		if CLK28'event and CLK28 = '1' then 
			if (CLK7 = '1' and CLK14 = '0' and TURBO = '1') then
				if vbus_req = '0' and vbus_ack2 = '1' then
					vbus_mode2 <= '0';
				else
					vbus_mode2 <= '1';
					vid_rd2 <= not vid_rd2;
				end if;	
				vbus_ack2 <= vbus_req;
			end if;		
		end if;		
	end process;
	
	vbus_mode <= vbus_mode1 when TURBO = '0' else vbus_mode2;
	vid_rd <= vid_rd1 when TURBO = '0' else vid_rd2;
	
end RTL;

