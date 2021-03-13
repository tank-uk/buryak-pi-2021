-------------------------------------------------------------------------------
-- VIDEO Controller
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity video is
	port (
		CLK2X 	: in std_logic; -- 28 MHz
		CLK		: in std_logic; -- 14 MHz
		ENA		: in std_logic; -- 7 MHz 
		RESET 	: in std_logic := '0';

		BORDER	: in std_logic_vector(2 downto 0);	-- bordr color (port #xxFE)
		DI			: in std_logic_vector(7 downto 0);	-- video data from memory
		TURBO 	: in std_logic_vector := "00"; -- turbo mode
		INTA		: in std_logic := '0'; -- int request for turbo mode
		MODE60	: in std_logic := '0'; -- 
		INT		: out std_logic; -- int output
		ATTR_O	: out std_logic_vector(7 downto 0); -- attribute register output
		pFF_CS	: out std_logic; -- port FF select
		A			: out std_logic_vector(13 downto 0); -- video address

		VIDEO_R	: out std_logic_vector(1 downto 0);
		VIDEO_G	: out std_logic_vector(1 downto 0);
		VIDEO_B	: out std_logic_vector(1 downto 0);
		
		HSYNC		: out std_logic;
		VSYNC		: out std_logic;
		
		HCNT : out std_logic_vector(9 downto 0);
		VCNT : out std_logic_vector(8 downto 0);
		BLINK : out std_logic
	);
end entity;

architecture rtl of video is

	signal rgb 	 		: std_logic_vector(2 downto 0);
	signal i 			: std_logic;
	signal o_rgb 		: std_logic_vector(8 downto 0);
	
	-- spectrum videocontroller signals
	signal vid_a_spec : std_logic_vector(13 downto 0);
	signal int_spec : std_logic;
	signal rgb_spec : std_logic_vector(2 downto 0);
	signal i_spec : std_logic;
	signal hsync_spec : std_logic;
	signal vsync_spec : std_logic;
	signal pFF_CS_spec : std_logic;
	signal attr_o_spec : std_logic_vector(7 downto 0);

	signal hcnt_spec : std_logic_vector(9 downto 0);
	signal vcnt_spec : std_logic_vector(8 downto 0);

begin

	U_PENT: entity work.pentagon_video 
	port map (
		CLK => CLK, -- 14
		CLK2x => CLK2x, -- 28
		ENA => ENA, -- 7
		BORDER => BORDER(2 downto 0),
		DI => DI,
		TURBO => TURBO,
		INTA => INTA,
		INT => int_spec,
		MODE60 => MODE60,
		pFF_CS => pFF_CS_spec,
		ATTR_O => attr_o_spec, 
		A => vid_a_spec,

		RGB => rgb_spec,
		I 	 => i_spec,
		
		HSYNC => hsync_spec,
		VSYNC => vsync_spec,

		HCNT => hcnt_spec,
		VCNT => vcnt_spec,
		BLINK => BLINK
	);

	A <= vid_a_spec;
	INT <= int_spec;
	rgb <= rgb_spec;
	i <= i_spec;

	HSYNC <= hsync_spec;
	VSYNC <= vsync_spec;	
	
	HCNT <= hcnt_spec;
	VCNT <= vcnt_spec;
	
	ATTR_O <= attr_o_spec;
	pFF_CS <= pFF_CS_spec;
	
	U6BIT: entity work.rgbi_6bit
	port map (
		I_CLK   => CLK2X,
		I_BLANK => '0',
		I_RED	  => rgb(2),
		I_GREEN => rgb(1),
		I_BLUE  => rgb(0),
		I_BRIGHT => i,
		O_RGB(5 downto 4) => VIDEO_R,
		O_RGB(3 downto 2) => VIDEO_G,
		O_RGB(1 downto 0) => VIDEO_B
	);
	
end architecture;