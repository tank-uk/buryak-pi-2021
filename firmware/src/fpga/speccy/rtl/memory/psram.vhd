library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity psram is
port (
	CLK_QSPI 	: in std_logic; -- high speed qspi clk
	CLK_BUS 		: in std_logic; -- low speed spi clk

	-- parallel interface
	A           : in std_logic_vector(20 downto 0); -- address bus
	DI 			: in std_logic_vector(7 downto 0);
	DO 			: out std_logic_vector(7 downto 0);
	N_WR 			: in std_logic := '1';
	N_RD 			: in std_logic := '1';

	-- PSRAM interface
	SPI_SCLK 	: out std_logic;
	SPI_N_CS 	: out std_logic;
	SPI_SIO 		: inout std_logic_vector(3 downto 0) := "1111"
	
);
end psram;

architecture RTL of psram is

component llqspi 
port (
	i_clk : in std_logic;
	i_wr : in std_logic;
	i_hold : in std_logic;
	i_word : in std_logic_vector(31 downto 0);
	i_len  : in std_logic_vector(1 downto 0);
	i_spd  : in std_logic;
	i_dir  : in std_logic;
	o_word : out std_logic_vector(31 downto 0);
	o_valid : out std_logic;
	o_busy : out std_logic;
	o_sck : out std_logic;
	o_cs_n : out std_logic;
	o_mod : out std_logic_vector(1 downto 0);
	o_dat : out std_logic_vector(3 downto 0);
	i_dat : in std_logic_vector(3 downto 0));
end component;
	
begin

-- TODO
	
end RTL;

