-- --------------------------------------------------------------------
-- Buriak-Pi 2021 firmware
-- v1.0
-- (c) 2021 Andy Karpov
-- --------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

entity firmware_top is
	generic(
		use_turbosound : boolean := false;
		use_psram : boolean := false
	);
	port(
		-- Clock
		CLK_50MHZ		: in std_logic;
		
		-- Flash 
		DATA0				: in std_logic;  			-- MISO
		NCSO				: out std_logic := '1'; -- /CS 
		DCLK				: out std_logic; 			-- SCK
		ASDO				: out std_logic; 			-- MOSI
		
		-- SD card
		SD_DI 			: out std_logic;			-- MOSI
		SD_NCS 			: out std_logic := '1'; -- /CS
		SD_NDET			: in std_logic;			-- /SD_DETECT

		-- CPU signals
		CPU_CLK			: out std_logic := '1';
		N_RESET			: inout std_logic := 'Z';
		N_INT				: out std_logic := '1';
		N_RD				: in std_logic;
		N_WR				: in std_logic;
		N_IORQ			: in std_logic;
		N_MREQ			: in std_logic;
		N_M1				: in std_logic;
		A					: in std_logic_vector(15 downto 0);
		D 					: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_NMI 			: out std_logic := 'Z';
		N_WAIT 			: out std_logic := 'Z';
		
		-- RAM 
		MA 				: inout std_logic_vector(20 downto 0);
		MD 				: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_MRD				: out std_logic := '1';
		N_MWR				: out std_logic := '1';
		
		-- VGA
		VGA_VSYNC    		: out std_logic := '1';
		VGA_HSYNC 			: out std_logic := '1';
		VGA_R       		: out std_logic_vector(1 downto 0) := "ZZ";
		VGA_G       		: out std_logic_vector(1 downto 0) := "ZZ";
		VGA_B       		: out std_logic_vector(1 downto 0) := "ZZ";

		-- Interfaces 
		BEEPER_L			: out std_logic := '0';
		BEEPER_R 		: out std_logic := '0';
		TAPE_IN 			: in std_logic;
		TAPE_OUT 		: buffer std_logic := '0';

		-- AY
		AY_BC1			: out std_logic;
		AY_BDIR			: out std_logic;
		
		-- Keyboard Atmega
		AVR_SCK 			: in std_logic;
		AVR_NCS 			: in std_logic;
		AVR_MOSI 		: in std_logic;
		AVR_MISO 		: out std_logic
		
	);
end firmware_top;

architecture rtl of firmware_top is

	signal clk_28 		: std_logic := '0';
	signal clk_14 		: std_logic := '0';
	signal clk_7 		: std_logic := '0';
	signal clk_8 		: std_logic := '0';
	signal clkcpu 		: std_logic := '1';
	signal clk_21 		: std_logic := '0';
	
	signal ena_div2	: std_logic := '0';
	signal ena_div4	: std_logic := '0';
	signal ena_div8	: std_logic := '0';
	signal ena_div16	: std_logic := '0';
	signal ena_div32	: std_logic := '0';
	signal ena_cnt		: std_logic_vector(5 downto 0) := "000000";

	signal attr_r   	: std_logic_vector(7 downto 0);
	signal vid_a 		: std_logic_vector(13 downto 0);
	signal video_do_bus: std_logic_vector(7 downto 0);
	
	signal video_r 	: std_logic_vector(1 downto 0);
	signal video_g 	: std_logic_vector(1 downto 0);
	signal video_b 	: std_logic_vector(1 downto 0);
	signal blink 		: std_logic := '0';
	
	signal border_attr: std_logic_vector(2 downto 0) := "000";

	signal port_7ffd	: std_logic_vector(7 downto 0); -- D0-D2 - RAM page from address #C000
																	  -- D3 - video RAM page: 0 - bank5, 1 - bank7 
																	  -- D4 - ROM page A14: 0 - basic 128, 1 - basic48
																	  -- D5 - 48k RAM lock, 1 - locked, 0 - extended memory enabled
																	  -- D6 - not used
																	  -- D7 - not used

	signal port_dffd : std_logic_vector(2 downto 0); -- D0-D2 ram ext
																	  
	signal ram_ext_std : std_logic_vector(1 downto 0) := "11";  -- 0 - pentagon-512 via 6,7 bits of the #7FFD port (bit 5 is for 48k lock)
																					-- 1 - pentagon-1024 via 5,6,7 bits of the #7FFD port (no 48k lock)
																					-- 2 - profi-1024 via 0,1,2 bits of the #DFFD port
																					-- 3 - pentagon-128
	
	signal ram_ext : std_logic_vector(2 downto 0) := "000";
	signal ram_do : std_logic_vector(7 downto 0);
	signal ram_oe_n : std_logic := '1';
	
	signal fd_port : std_logic;
	signal fd_sel : std_logic;	
																	  
	signal ay_port		: std_logic := '0';
			
	signal hsync     	: std_logic := '1';
	signal vsync     	: std_logic := '1';
	
	signal hcnt 		: std_logic_vector(9 downto 0);
	signal vcnt 		: std_logic_vector(8 downto 0);	

	signal sound_out 	: std_logic := '0';
	signal port_read	: std_logic := '0';
	signal port_write	: std_logic := '0';
	
	signal divmmc_enable : std_logic := '0';
	signal divmmc_do	: std_logic_vector(7 downto 0);
	
	signal divmmc_ram : std_logic;
	signal divmmc_rom : std_logic;
	
	signal divmmc_disable_zxrom : std_logic;
	signal divmmc_eeprom_cs_n : std_logic;
	signal divmmc_eeprom_we_n : std_logic;
	signal divmmc_sram_cs_n : std_logic;
	signal divmmc_sram_we_n : std_logic;
	signal divmmc_sram_hiaddr : std_logic_vector(5 downto 0);
	signal divmmc_sd_cs_n : std_logic;
	signal divmmc_wr : std_logic;
	signal divmmc_sd_di: std_logic;
	signal divmmc_sd_clk: std_logic;
	
	signal zc_enable : std_logic := '0';
	signal zc_do_bus	: std_logic_vector(7 downto 0);
	signal zc_wr 		: std_logic :='0';
	signal zc_rd		: std_logic :='0';
	signal zc_sd_cs_n: std_logic;
	signal zc_sd_di: std_logic;
	signal zc_sd_clk: std_logic;
	
	signal trdos	: std_logic :='1';
	
	signal kb : std_logic_vector(4 downto 0) := "11111";
	signal joy : std_logic_vector(7 downto 0) := "00000000";
	signal nmi : std_logic;
	signal areset : std_logic;
	signal locked : std_logic;
	signal reset : std_logic;
	signal turbo : std_logic_vector(1 downto 0) := "00";
	
	signal vga_red: std_logic_vector(1 downto 0);
	signal vga_green: std_logic_vector(1 downto 0);
	signal vga_blue: std_logic_vector(1 downto 0);	
	signal hsync_vga : std_logic;
	signal vsync_vga : std_logic;
	
	signal cs_dffd : std_logic := '0';
	signal cs_7ffd : std_logic := '0';
	signal cs_xxfd : std_logic := '0';
	signal cs_fe   : std_logic := '0';
	
	-- Loader
	signal loader_act		: std_logic := '1';
	signal loader_reset 	: std_logic := '0';
	signal loader_done 	: std_logic := '0';
	signal loader_ram_di	: std_logic_vector(7 downto 0);
	signal loader_ram_do	: std_logic_vector(7 downto 0);
	signal loader_ram_a	: std_logic_vector(20 downto 0);
	signal loader_ram_wr : std_logic;
	signal loader_flash_di : std_logic_vector(7 downto 0);
	signal loader_flash_do : std_logic_vector(7 downto 0);
	signal loader_flash_a : std_logic_vector(23 downto 0);
	signal loader_flash_rd_n : std_logic;
	signal loader_flash_wr_n : std_logic;
	signal loader_flash_busy : std_logic;
	signal loader_flash_rdy : std_logic;

	-- Parallel flash interface
	signal flash_a_bus: std_logic_vector(23 downto 0);
	signal flash_di_bus : std_logic_vector(7 downto 0);
	signal flash_do_bus: std_logic_vector(7 downto 0);
	signal flash_wr_n : std_logic := '1';
	signal flash_rd_n : std_logic := '1';
	signal flash_er_n : std_logic := '1';
	signal flash_busy : std_logic := '1';
	signal flash_rdy : std_logic := '0';
	signal fw_update_mode : std_logic := '0';
	
	-- SPI flash / SD
	signal flash_ncs 		: std_logic;
	signal flash_clk 		: std_logic;
	signal flash_do 		: std_logic;
	signal sd_clk 			: std_logic;
	signal sd_si 			: std_logic;

	signal host_flash_a_bus : std_logic_vector(23 downto 0);
	signal host_flash_di_bus : std_logic_vector(7 downto 0);
	signal host_flash_rd_n : std_logic := '1';
	signal host_flash_wr_n : std_logic := '1';
	signal host_flash_er_n : std_logic := '1';
	
	signal ext_rombank : std_logic_vector(2 downto 0) := "000";
	
	signal audio_l		: std_logic_vector(15 downto 0);
	signal audio_r		: std_logic_vector(15 downto 0);

	-- Soundrive
	signal covox_a		: std_logic_vector(7 downto 0);
	signal covox_b		: std_logic_vector(7 downto 0);
	signal covox_c		: std_logic_vector(7 downto 0);
	signal covox_d		: std_logic_vector(7 downto 0);
	
	-- TurboSound	
	signal ssg_sel		: std_logic;	
	signal ssg0_do_bus	: std_logic_vector(7 downto 0);	
	signal ssg0_a		: std_logic_vector(7 downto 0);	
	signal ssg0_b		: std_logic_vector(7 downto 0);	
	signal ssg0_c		: std_logic_vector(7 downto 0);	
	signal ssg1_do_bus	: std_logic_vector(7 downto 0);	
	signal ssg1_a		: std_logic_vector(7 downto 0);	
	signal ssg1_b		: std_logic_vector(7 downto 0);	
	signal ssg1_c		: std_logic_vector(7 downto 0);

	-- SAA1099
	signal saa_wr_n		: std_logic;
	signal saa_out_l	: std_logic_vector(7 downto 0);
	signal saa_out_r	: std_logic_vector(7 downto 0);
	
	signal ram_a_bus 	: std_logic_vector(20 downto 0);
	signal ram_di_bus : std_logic_vector(7 downto 0);
	signal ram_do_bus : std_logic_vector(7 downto 0);
	signal ram_rd_n 	: std_logic := '1';
	signal ram_wr_n 	: std_logic := '1';
	
	component saa1099
	port (
		clk_sys		: in std_logic;
		ce		: in std_logic;		--8 MHz
		rst_n		: in std_logic;
		cs_n		: in std_logic;
		a0		: in std_logic;		--0=data, 1=address
		wr_n		: in std_logic;
		din		: in std_logic_vector(7 downto 0);
		out_l		: out std_logic_vector(7 downto 0);
		out_r		: out std_logic_vector(7 downto 0));
	end component;

begin

	-- PLL1
	U1: entity work.altpll0
	port map (
		inclk0			=> CLK_50MHZ,
		locked			=> locked,
		c0 				=> clk_28,
		c1 				=> clk_8,
		c2 				=> clk_21
	);
	
	-- memory arbiter
	U2: entity work.memory
	port map (
		CLK2X => CLK_28,
		CLKX => CLK_14,
		CLK_CPU  => clkcpu,
		
		enable_divmmc => divmmc_enable,
		enable_zcontroller => zc_enable,
		
		-- loader signals
		loader_act 		=> loader_act,
		loader_ram_a 	=> loader_ram_a,
		loader_ram_do 	=> loader_ram_do,
		loader_ram_wr 	=> loader_ram_wr,
		
		-- cpu signals
		A => A,
		D => D,
		N_MREQ => N_MREQ,
		N_IORQ => N_IORQ,
		N_WR => N_WR,
		N_RD => N_RD,
		N_M1 => N_M1,

		-- ram 
		MA => ram_a_bus,
		MDI => ram_di_bus,
		MDO => ram_do_bus,
		N_MRD => ram_rd_n,
		N_MWR => ram_wr_n,
		
		-- ram out to cpu
		DO => ram_do,
		N_OE => ram_oe_n,
		
		-- ram pages
		RAM_BANK => port_7ffd(2 downto 0),
		RAM_EXT => ram_ext,

		-- divmmc
		DIVMMC_A => divmmc_sram_hiaddr,
		IS_DIVMMC_RAM => divmmc_ram,
		IS_DIVMMC_ROM => divmmc_rom,

		-- video
		VA => vid_a,
		VID_PAGE => port_7ffd(3),
		VID_DO => video_do_bus,
		
		-- TRDOS 
		TRDOS => trdos,
		
		-- rom
		ROM_BANK => port_7ffd(4),
		EXT_ROM_BANK => ext_rombank
	);
	
	-- PSRAM64
	G_PSRAM: if use_psram generate
	UPSRAM: entity work.psram 
	port map (
		CLK_QSPI => CLK_50MHZ,
		CLK_BUS  => CLK_28,
		
		A => ram_a_bus,
		DI => ram_di_bus,
		DO => ram_do_bus,
		N_RD => ram_rd_n,
		N_WR => ram_wr_n,
		
		SPI_SCLK => MA(10),
		SPI_N_CS => MA(19),
		SPI_SIO(3)  => MA(8),
		SPI_SIO(2)  => MA(11),
		SPI_SIO(1)  => MA(9),
		SPI_SIO(0)  => MA(12)
	);	
	end generate G_PSRAM;
	
	-- parallel ram pin mapping
	G_PRAM: if not(use_psram) generate 
		MA <= ram_a_bus;
		MD <= ram_do_bus when ram_wr_n = '0' else "ZZZZZZZZ";
		ram_di_bus <= MD;
		N_MWR <= ram_wr_n;
		N_MRD <= ram_rd_n;
	end generate G_PRAM;
	
	-- divmmc interface
	U3: entity work.divmmc
	port map (
		I_CLK		=> CLK_28,
		I_CS		=> divmmc_enable,
		I_RESET		=> not(reset), -- not(N_RESET),
		I_ADDR		=> A,
		I_DATA		=> D,
		O_DATA		=> divmmc_do,
		I_WR_N		=> N_WR,
		I_RD_N		=> N_RD,
		I_IORQ_N		=> N_IORQ,
		I_MREQ_N		=> N_MREQ,
		I_M1_N		=> N_M1,
		
		O_WR 				 => divmmc_wr,
		O_DISABLE_ZXROM => divmmc_disable_zxrom,
		O_EEPROM_CS_N 	 => divmmc_eeprom_cs_n,
		O_EEPROM_WE_N 	 => divmmc_eeprom_we_n,
		O_SRAM_CS_N 	 => divmmc_sram_cs_n,
		O_SRAM_WE_N 	 => divmmc_sram_we_n,
		O_SRAM_HIADDR	 => divmmc_sram_hiaddr,
		
		O_CS_N		=> divmmc_sd_cs_n,
		O_SCLK		=> divmmc_sd_clk,
		O_MOSI		=> divmmc_sd_di,
		I_MISO		=> DATA0
	);
		
	-- Z-Controller	
	U4: entity work.zcontroller 
	port map(
		RESET => not(N_RESET),
		CLK => clkcpu,
		A => A(5),
		DI => D,
		DO => zc_do_bus,
		RD => zc_rd,
		WR => zc_wr,
		SDDET => '0',
		SDPROT => '0',
		CS_n => zc_sd_cs_n,
		SCLK => zc_sd_clk,
		MOSI => zc_sd_di,
		MISO => DATA0
	);

	-- keyboard
	U5: entity work.cpld_kbd 
	port map (
		CLK => CLK_28,
		A => A(15 downto 8),
		KB => kb,
		AVR_SCK => AVR_SCK,
		AVR_MOSI => AVR_MOSI,
		AVR_MISO => AVR_MISO,
		AVR_SS => AVR_NCS,
		
		O_RESET => reset,
		O_TURBO => turbo,
		O_MAGICK => nmi,
		O_JOY => joy,
		O_BANK => ext_rombank,
		O_WAIT => N_WAIT
	);
	
	-- video module
	U6: entity work.video 
	port map (
		CLK2x => CLK_28,
		CLK => CLK_14,
		ENA => CLK_7,
		RESET => not(reset),
		
		BORDER => border_attr,
		DI => video_do_bus,
		TURBO => turbo,
		INTA => N_IORQ or N_M1,
		MODE60 => '0',
		INT => N_INT,
		ATTR_O => attr_r, 
		pFF_CS => open,
		A => vid_a,
		
		VIDEO_R => video_r,
		VIDEO_G => video_g,
		VIDEO_B => video_b,

		HSYNC => hsync,
		VSYNC => vsync,

		HCNT => hcnt,
		VCNT => vcnt,
		
		BLINK => blink
	);
	
	-- Scandoubler	
	U7: entity work.vga_pal 
	port map (
		RGB_IN 			=> video_r(0) & video_r(1) & video_g(0) & video_g(1) & video_b(0) & video_b(1),
		KSI_IN 			=> vsync,
		SSI_IN 			=> hsync,
		CLK 				=> CLK_14,
		CLK2 				=> CLK_28,
		EN 				=> '1',
		DS80				=> '0',
		RGB_O(5 downto 4)	=> VGA_R,
		RGB_O(3 downto 2)	=> VGA_G,
		RGB_O(1 downto 0)	=> VGA_B,
		VSYNC_VGA		=> VGA_VSYNC,
		HSYNC_VGA		=> VGA_HSYNC
	);	
	
	-- osd (debug)
--	U8: entity work.osd
--	port map (
--		CLK 				=> clk_28,
--		CLK2 				=> clk_14,
--		RGB_I 			=> vid_rgb,
--		RGB_O 			=> vid_rgb_osd,
--		HCNT_I 			=> vid_hcnt,
--		VCNT_I 			=> vid_vcnt,
--		BLINK 			=> blink,
--		
--		-- sensors
--		TURBO 			=> kb_turbo,
--		SCANDOUBLER_EN => vid_scandoubler_enable,
--		MODE60 			=> soft_sw(2),
--		ROM_BANK 		=> ext_rom_bank,
--		KB_MODE 			=> kb_mode,
--		KB_WAIT 			=> kb_wait,
--		SSG_MODE 		=> soft_sw(8),
--		SSG_STEREO 		=> soft_sw(7)
--	);

-- SPI flash parallel interface
U9: entity work.flash
port map(
	CLK 				=> clk_28,
	RESET 			=> areset,
	
	A 					=> flash_a_bus,
	DI 				=> flash_di_bus,
	DO 				=> flash_do_bus,
	WR_N 				=> flash_wr_n,
	RD_N 				=> flash_rd_n,
	ER_N 				=> flash_er_n,

	DATA0				=> DATA0,
	NCSO				=> flash_ncs,
	DCLK				=> flash_clk,
	ASDO				=> flash_do,

	BUSY 				=> flash_busy,
	DATA_READY 		=> flash_rdy
);

-- Loader
U10: entity work.loader
port map(
	CLK 				=> clk_28,
	RESET 			=> areset,
	
	RAM_A 			=> loader_ram_a,
	RAM_DO 			=> loader_ram_do,
	RAM_WR 			=> loader_ram_wr,
	
	FLASH_A 			=> loader_flash_a,
	FLASH_DO 		=> flash_do_bus,
	FLASH_RD_N 		=> loader_flash_rd_n,	
	FLASH_BUSY 		=> flash_busy,
	FLASH_READY 	=> flash_rdy,
	
	LOADER_ACTIVE 	=> loader_act,
	LOADER_RESET 	=> loader_reset
);	

-- Soundrive
U11: entity work.soundrive
port map (
	I_RESET		=> not N_RESET,
	I_CLK		=> clk_28,
	I_CS		=> '1',
	I_WR_N		=> N_WR,
	I_ADDR		=> A(7 downto 0),
	I_DATA		=> D,
	I_IORQ_N	=> N_IORQ,
	I_DOS		=> trdos,
	O_COVOX_A	=> covox_a,
	O_COVOX_B	=> covox_b,
	O_COVOX_C	=> covox_c,
	O_COVOX_D	=> covox_d);
	
-- TurboSound	
G_TURBOSOUND: if use_turbosound generate 
U12: entity work.turbosound	
port map (	
	I_CLK		=> clk_28,	
	I_ENA		=> ena_div16,	
	I_ADDR		=> A,	
	I_DATA		=> D,	
	I_WR_N		=> N_WR,	
	I_IORQ_N	=> N_IORQ,	
	I_M1_N		=> N_M1,	
	I_RESET_N	=> N_RESET,	
	I_MODE   => '1', -- AY	
	O_SEL		=> ssg_sel,	
	-- ssg0	
	O_SSG0_DA	=> ssg0_do_bus,	
	O_SSG0_AUDIO_A	=> ssg0_a,	
	O_SSG0_AUDIO_B	=> ssg0_b,	
	O_SSG0_AUDIO_C	=> ssg0_c,	
	-- ssg1	
	O_SSG1_DA	=> ssg1_do_bus,	
	O_SSG1_AUDIO_A	=> ssg1_a,	
	O_SSG1_AUDIO_B	=> ssg1_b,	
	O_SSG1_AUDIO_C	=> ssg1_c);
end generate G_TURBOSOUND;

-- saa
U13: saa1099
port map(
	clk_sys		=> clk_8,
	ce		=> '1',			-- 8 MHz
	rst_n		=> N_RESET,
	cs_n		=> '0',
	a0		=> A(8),		-- 0=data, 1=address
	wr_n		=> saa_wr_n,
	din		=> D,
	out_l		=> saa_out_l,
	out_r		=> saa_out_r);

	
-- Delta-Sigma
U14: entity work.dac
generic map (
	msbi_g		=> 15)
port map (
	I_CLK		=> clk_28,
	I_RESET		=> not N_RESET,
	I_DATA		=> audio_l,
	O_DAC		=> BEEPER_L);

U15: entity work.dac
generic map (
	msbi_g		=> 15)
port map (
	I_CLK		=> clk_28,
	I_RESET		=> not N_RESET,
	I_DATA		=> audio_r,
	O_DAC		=> BEEPER_R);
	
-- --------------------------------------------------------------------------------------------------------------------------------

SD_NCS	<= '1' when loader_act = '1' else divmmc_sd_cs_n 	when divmmc_enable = '1' else zc_sd_cs_n 		when zc_enable = '1' else '1';
sd_clk 	<= '1' when loader_act = '1' else divmmc_sd_clk 	when divmmc_enable = '1' else zc_sd_clk	 	when zc_enable = '1' else '1';
sd_si 	<= '1' when loader_act = '1' else divmmc_sd_di 		when divmmc_enable = '1' else zc_sd_di 		when zc_enable = '1' else '1';

-- share SPI between flash and SD
DCLK <= flash_clk when loader_act = '1' else sd_clk;
ASDO <= flash_do when loader_act = '1' else sd_si;
NCSO <= flash_ncs when loader_act = '1' else '1';
SD_DI <= sd_si;

-- share flash between loader and host
flash_a_bus <= loader_flash_a;
flash_di_bus <= "00000000";
flash_wr_n <= '1'; -- write
flash_rd_n <= loader_flash_rd_n when loader_act = '1' else '1';
flash_er_n <= '1'; -- erase

divmmc_rom <= '1' when (divmmc_disable_zxrom = '1' and divmmc_eeprom_cs_n = '0' and divmmc_enable = '1') else '0';
divmmc_ram <= '1' when (divmmc_disable_zxrom = '1' and divmmc_sram_cs_n = '0' and divmmc_enable = '1') else '0';

ay_port <= '1' when A(7 downto 0) = x"FD" and A(15)='1' and fd_port = '1' else '0';
AY_BC1 <= '1' when ay_port = '1' and A(14) = '1' and N_IORQ = '0' and (N_WR='0' or N_RD='0') else '0';
AY_BDIR <= '1' when ay_port = '1' and N_IORQ = '0' and N_WR = '0' else '0';

N_NMI <= '0' when nmi = '0' else '1';
areset <= not locked;
N_RESET <= '0' when areset = '1' or reset = '0' or loader_reset = '1' or loader_act = '1' else 'Z';

--N_NMI <= '0' when nmi = '0' else '1';
--N_RESET <= '0' when reset = '0' else 'Z';

 -- #FD port correction
 fd_sel <= '0' when D(7 downto 4) = "1101" and D(2 downto 0) = "011" else '1'; -- IN, OUT Z80 Command Latch

 process(fd_sel, N_M1, N_RESET)
 begin
		if N_RESET='0' then
			  fd_port <= '1';
		elsif rising_edge(N_M1) then 
			  fd_port <= fd_sel;
		end if;
 end process;
 
 -- dividers
process (clk_28)
begin
	if clk_28'event and clk_28 = '0' then
		ena_cnt <= ena_cnt + 1;
	end if;
end process;

ena_div2 <= ena_cnt(0);
ena_div4 <= ena_cnt(1) and ena_cnt(0);
ena_div8 <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
ena_div16 <= ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
ena_div32 <= ena_cnt(5) and ena_cnt(4) and ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);

-- CPU clock 
clkcpu <= clk_28 and ena_div2 when turbo = "10" else -- 14
			 clk_28 and ena_div4 when turbo = "01" else -- 7
			 clk_28 and ena_div8; -- 3.5
CPU_CLK <= clkcpu;

port_write <= '1' when N_IORQ = '0' and N_WR = '0' and N_M1 = '1' else '0';
port_read <= '1' when N_IORQ = '0' and N_RD = '0' and N_M1 = '1' else '0';

-- read ports by CPU
D(7 downto 0) <= 
	ram_do when ram_oe_n = '0' else -- #memory
	port_7ffd when port_read = '1' and A = X"7FFD" else  -- #7FFD - system port 
	"00000" & ram_ext when port_read = '1' and A = X"DFFD" and ram_ext_std = "10" else  -- #DFFD - system port 
	'1' & TAPE_IN & '1' & kb(4 downto 0) when port_read = '1' and A(0) = '0' else -- #FE - keyboard 
	joy when port_read = '1' and A(7 downto 0) = X"1F" else -- #1F - kempston joy
	divmmc_do when divmmc_wr = '1' and divmmc_enable = '1' else 									 -- divMMC	
	zc_do_bus when port_read = '1' and A(7 downto 6) = "01" and A(4 downto 0) = "10111" and zc_enable = '1' else -- Z-controller
	ssg0_do_bus when use_turbosound and port_read = '1' and A = X"FFFD" and ssg_sel = '0' else -- Turbosound 	
	ssg1_do_bus when use_turbosound and port_read = '1' and A = X"FFFD" and ssg_sel = '1' else
	attr_r when port_read = '1' and A(7 downto 0) = x"FF" else -- #FF - attributes
	"ZZZZZZZZ";

divmmc_enable <= '1' when ext_rombank = "000" and SD_NDET = '0' else '0';
zc_enable <= '1' when ext_rombank = "001" else '0';
ram_ext_std <= "10" when ext_rombank = "000" or ext_rombank = "001" else "11";

-- z-controller 
zc_wr <= '1' when (zc_enable = '1' and N_IORQ = '0' and N_WR = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
zc_rd <= '1' when (zc_enable = '1' and N_IORQ = '0' and N_RD = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';

-- clocks
process (CLK_28)
begin 
	if (CLK_28'event and CLK_28 = '1') then 
		clk_14 <= not(clk_14);
	end if;
end process;

process (clk_14)
begin 
	if (clk_14'event and clk_14 = '1') then 
		clk_7 <= not(clk_7);
	end if;
end process;

cs_dffd <= '1' when N_IORQ = '0' and N_M1 = '1' and A = X"DFFD" and fd_port = '1' else '0';
cs_7ffd <= '1' when N_IORQ = '0' and N_M1 = '1' and A = X"7FFD" else '0';
cs_xxfd <= '1' when N_IORQ = '0' and N_M1 = '1' and A(15) = '0' and A(1) = '0' and fd_port = '0' else '0';

ram_ext <= '0' & port_7ffd(6) & port_7ffd(7) when ram_ext_std = "00" else 
			  port_7ffd(5) & port_7ffd(6) & port_7ffd(7) when ram_ext_std = "01" else
			  port_dffd(2 downto 0) when ram_ext_std = "10" else 
			  "000";	
			  
-- ports, write by CPU
process( clk_28, clk_14, clk_7, N_RESET, A, D, port_write, port_7ffd, N_M1, N_MREQ )
begin
	if N_RESET = '0' then
		port_7ffd <= "00000000";
		--sound_out <= '0';
		if (zc_enable = '1') then 
			trdos <= '1'; -- 1 - boot into service rom, 0 - boot into 128 menu
		else 
			trdos <= '0';
		end if;
	elsif clk_28'event and clk_28 = '1' then 
--			if clk_14 = '1' and (TURBO = '1' or clk_7 = '1') then
			if port_write = '1' then

				 -- port #7FFD  
				if cs_7ffd = '1' and port_7ffd(5) = '0' then 
					port_7ffd <= D;
				elsif cs_xxfd = '1' and port_7ffd(5) = '0' then 
					port_7ffd <= D;
				end if;
				 
				-- port #DFFD (profi ram ext)
				if cs_dffd = '1' and port_7ffd(5) = '0' and fd_port='1' then
						port_dffd <= D(2 downto 0);
				end if;
				
				-- port #FE
				if A(0) = '0' then
					border_attr <= D(2 downto 0); -- border attr
					TAPE_OUT <= D(3);
					sound_out <= D(4); -- BEEPER
				end if;				
				
			end if;
			
			-- trdos flag
			if zc_enable = '1' and N_M1 = '0' and N_MREQ = '0' and A(15 downto 8) = X"3D" and port_7ffd(4) = '1' then 
				trdos <= '1';
			elsif zc_enable = '1' and N_M1 = '0' and N_MREQ = '0' and A(15 downto 14) /= "00" then 
				trdos <= '0'; 
			end if;
			
--			end if;
	end if;
end process;	
	
	
saa_wr_n <= '0' when (N_IORQ = '0' and N_WR = '0' and A(7 downto 0) = "11111111" and trdos = '0') else '1';

audio_l	<= ("000" & sound_out & "000000000000") + 
				("0000" & TAPE_IN &   "00000000000") +
				("0000" & TAPE_OUT &  "00000000000") +
				("000" & ssg0_a & "00000") + 	
				("0000" & ssg0_b & "0000") + 	
				("000" & ssg1_a & "00000") + 	
				("0000" & ssg1_b & "0000") + 
				("000" & covox_a & "00000") + 
				("000" & covox_b & "00000") + 
				("000" & saa_out_l & "00000");
audio_r	<= ("000" & sound_out & "000000000000") + 
				("0000" & TAPE_IN &   "00000000000") +
				("0000" & TAPE_OUT &  "00000000000") +
				("000" & ssg0_c & "00000") + 	
				("0000" & ssg0_b & "0000") + 	
				("000" & ssg1_c & "00000") + 	
				("0000" & ssg1_b & "0000") + 
				("000" & covox_c & "00000") + 
				("000" & covox_d & "00000") + 
				("000" & saa_out_r & "00000");
end;
