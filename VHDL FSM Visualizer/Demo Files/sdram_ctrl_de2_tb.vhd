----------------------------------------------------------------------------------
-- Company: KTH Department of Electronics
-- Engineer: Lefteris Kyriakakis
-- 
-- Create Date: 01/22/2016 08:26:19 PM
-- Design Name: SDRAM SDR Controller
-- Module Name: sdram_ctrl_de2_tb - Behavioral
-- Project Name: SUED
-- Target Devices:
-- 	Boards: Artix-7, DE2-115
--		Memories: IS42/45R86400D/16320D/32160D, IS42/45S86400D/16320D/32160D, IS42/45SM/RM/VM16160K 
-- Comments:
-- 	Currently supports only single r/w accesses, no burst mode has been implemented.
--		Recommended frequency of r/w requests is REQUEST_DELAY_CYCLES=20
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.aconvenientpackage.all;

entity sdram_ctrl_de2_tb is
  generic(
        DATA_WIDTH : Integer := 32;
        DQM_WIDTH : Integer := 4;
        ROW_WIDTH : Integer := 13;
		COLS_WIDTH : Integer := 10;
        BANK_WIDTH : Integer := 2;
        NOP_BOOT_CYCLES : Integer := 10000; --at 50MHz covers 200us
        REF_PERIOD : Integer := 390; --refresh command every to 7.8125 microseconds
		REF_COMMAND_COUNT : Integer := 2; --How many refresh commands should be issued during initialization
		REF_COMMAND_PERIOD : Integer := 8; -- at 50MHz covers 60ns (tRC Command Period)
		PRECH_COMMAND_PERIOD : Integer := 2; -- tRP Command Period PRECHARGE TO ACTIVATE/REFRESH
		ACT_TO_RW_CYCLES : Integer := 2; --tRCD Active Command To Read/Write Command Delay Time
		IN_DATA_TO_PRE : Integer := 2; --tDPL Input Data To Precharge Command Delay
        CAS_LAT_CYCLES  : Integer := 2; --based on CAS Latency setting
		MODE_REG_CYCLES : Integer := 2; --tMRD (Mode Register Set To Command Delay Time 2 cycle)
		BURST_LENGTH : Integer := 1; --SEUD implementation requires a single access mode
        RAM_COLS : Integer := 1024; --A full page is 512 columns
        RAM_ROWS : Integer := 8192;
        RAM_BANKS : Integer := 4;
		REQUEST_DELAY_CYCLES : Integer := 0 --make a request every 0.05 ms @ 50MHz
    ); 
	PORT (
		HEX7,HEX6,HEX5,HEX4,HEX3,HEX2,HEX1,HEX0 : OUT std_logic_vector(6 downto 0);
		LEDG : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		SW : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		KEY : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		CLOCK_50 : IN STD_LOGIC;
		OP_DONE_LED : OUT STD_LOGIC;
		LEDR : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		
		FULL_READ_LED : OUT STD_LOGIC;
		CHECK_DATA_LED : OUT STD_LOGIC;
		
		DRAM_CLK, DRAM_CKE : OUT STD_LOGIC;
		DRAM_ADDR : OUT STD_LOGIC_VECTOR(ROW_WIDTH-1 DOWNTO 0);
		DRAM_BA_0, DRAM_BA_1 : OUT STD_LOGIC;
		DRAM_CS_N, DRAM_CAS_N, DRAM_RAS_N, DRAM_WE_N : OUT STD_LOGIC;
		DRAM_DQ : INOUT STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
		DRAM_DQM : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
	);
end sdram_ctrl_de2_tb;

architecture behave of sdram_ctrl_de2_tb is
--instantiate components
component sdram_ctrl_tmr_top
    generic(
        DATA_WIDTH : Integer;
        DQM_WIDTH : Integer;
        ROW_WIDTH : Integer;
		COLS_WIDTH : Integer;
        BANK_WIDTH : Integer;
        NOP_BOOT_CYCLES : Integer; --at 50MHz covers 100us
        REF_PERIOD : Integer; --refresh command every to 7.8125 microseconds
		REF_COMMAND_COUNT : Integer; --How many refresh commands should be issued during initialization
		REF_COMMAND_PERIOD : Integer; -- at 50MHz covers 60ns (tRC Command Period)
		PRECH_COMMAND_PERIOD : Integer; -- tRP Command Period PRECHARGE TO ACTIVATE/REFRESH
		ACT_TO_RW_CYCLES : Integer; --tRCD Active Command To Read/Write Command Delay Time
		IN_DATA_TO_PRE : Integer; --tDPL Input Data To Precharge Command Delay
        CAS_LAT_CYCLES  : Integer; --based on CAS Latency setting
		MODE_REG_CYCLES : Integer; --tMRD (Mode Register Set To Command Delay Time 2 cycle)
		BURST_LENGTH : Integer; --NOT USED! SEUD implementation requires a single access mode
        RAM_COLS : Integer; --A full page is 512 columns
        RAM_ROWS : Integer;
        RAM_BANKS : Integer
    );
    port(
        --SDRAM Interface
        clk_o : out std_logic;
        cke_o : out std_logic;
        bank_o : out std_logic_vector(BANK_WIDTH-1 downto 0);
        addr_o : out std_logic_vector(ROW_WIDTH-1 downto 0);
        cs_o : out std_logic;
        ras_o : out std_logic;
        cas_o : out std_logic;
        we_o : out std_logic;
        dqm_o : out std_logic_vector (DQM_WIDTH-1 DOWNTO 0);
        dataQ_io : inout std_logic_vector(DATA_WIDTH-1 downto 0);
        --Testing interface
        en_err_test_i : in std_logic;
        err_counter_o : out std_logic_vector(DATA_WIDTH-1 downto 0);
        --Controller Interface
        hold_i : in std_logic;
        rst_i : in std_logic;
        clk_i : in std_logic;
        wr_req_i : in std_logic;
        wr_grnt_o : out std_logic;
        wr_data_i : in std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_data_o : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_req_i : in std_logic;
        rd_grnt_o : out std_logic;
        rd_op_done_o : out std_logic;
        wr_op_done_o : out std_logic;
        rw_addr_i : in std_logic_vector((COLS_WIDTH+ROW_WIDTH+BANK_WIDTH)-1 downto 0);
        mem_ready_o : out std_logic;
		err_detected_o : out std_logic;
        ctrl_state_o : out std_logic_vector(20 downto 0)
    );
end component sdram_ctrl_tmr_top;

component sdram_ctrl is
    generic(
        DATA_WIDTH : Integer := 32;
        DQM_WIDTH : Integer := 4;
        ROW_WIDTH : Integer := 13;
		COLS_WIDTH : Integer := 10;
        BANK_WIDTH : Integer := 2;
        NOP_BOOT_CYCLES : Integer := 10000; --at 50MHz covers 100us
        REF_PERIOD : Integer := 390; --refresh command every to 7.8125 microseconds
		REF_COMMAND_COUNT : Integer := 8; --How many refresh commands should be issued during initialization
		REF_COMMAND_PERIOD : Integer := 8; -- at 50MHz covers 60ns (tRC Command Period)
		PRECH_COMMAND_PERIOD : Integer := 2; -- tRP Command Period PRECHARGE TO ACTIVATE/REFRESH
		ACT_TO_RW_CYCLES : Integer := 2; --tRCD Active Command To Read/Write Command Delay Time
		IN_DATA_TO_PRE : Integer := 2; --tDPL Input Data To Precharge Command Delay
        CAS_LAT_CYCLES  : Integer := 2; --based on CAS Latency setting
		MODE_REG_CYCLES : Integer := 2; --tMRD (Mode Register Set To Command Delay Time 2 cycle)
		BURST_LENGTH : Integer := 1; --NOT USED! SEUD implementation requires a single access mode
        RAM_COLS : Integer := 512; --A full page is 512 columns
        RAM_ROWS : Integer := 8192;
        RAM_BANKS : Integer := 4
    );
    port(
        --SDRAM Interface
        clk_o : out std_logic;
        cke_o : out std_logic;
        bank_o : out std_logic_vector(BANK_WIDTH-1 downto 0);
        addr_o : out std_logic_vector(ROW_WIDTH-1 downto 0);
        cs_o : out std_logic;
        ras_o : out std_logic;
        cas_o : out std_logic;
        we_o : out std_logic;
        dqm_o : out std_logic_vector (DQM_WIDTH-1 DOWNTO 0);
        dataQ_io : inout std_logic_vector(DATA_WIDTH-1 downto 0);
        
        --Controller Interface
        hold_i : in std_logic;
        rst_i : in std_logic;
        clk_i : in std_logic;
        wr_req_i : in std_logic;
        wr_grnt_o : out std_logic;
        wr_data_i : in std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_data_o : out std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
        rd_req_i : in std_logic;
        rd_grnt_o : out std_logic;
		wr_op_done_o : out std_logic;
        rd_op_done_o : out std_logic;
        rw_addr_i : in std_logic_vector((COLS_WIDTH+ROW_WIDTH+BANK_WIDTH)-1 downto 0);
        mem_ready_o : out std_logic;
        ctrl_state_o : out std_logic_vector(20 downto 0)
    );
end component sdram_ctrl;

component sdram_pll
port(
	inclk0		: IN STD_LOGIC  := '0';
	c0		: OUT STD_LOGIC
);
end component;
 
component binary_bcd_converter
generic(N: positive := 16);
port(
	clk, reset: in std_logic;
   binary_in: in std_logic_vector(N-1 downto 0);
   bcd0, bcd1, bcd2, bcd3, bcd4: out std_logic_vector(3 downto 0)
);
end component;

component sevensegmentdecoder
port(
   bcdin : IN std_logic_vector(3 downto 0);
   sys_clk : IN std_logic;
	reset : IN std_logic;
	output : OUT std_logic_vector(6 downto 0)
);
end component;
 
--control the controller signals
signal PLLCLOCK : std_logic := '0';
signal hold_int : std_logic := '0';
signal rst_int : std_logic := '0';
signal wr_req_int : std_logic := '0';
signal wr_grnt_int : std_logic := '0';
signal wr_data_int : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
signal rd_data_int : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
signal rd_req_int : std_logic := '0';
signal rd_grnt_int : std_logic := '0';
signal wr_done_int, rd_done_int : std_logic := '0';
signal rw_addr_int : std_logic_vector((COLS_WIDTH+ROW_WIDTH+BANK_WIDTH)-1 downto 0) := (others=>'Z');
signal mem_ready_int : std_logic := '0';
signal err_detected_int : std_logic := '0';
signal ba : std_logic_vector(BANK_WIDTH-1 downto 0);

--SDRAM controller states.
type fsm_state_type is (ST_MOVE, ST_REQ_WRITE, ST_WRITE, ST_REQ_READ, ST_READ, ST_WAIT);
signal state : fsm_state_type := ST_WAIT;
-- Attribute "safe" implements a safe state machine.
-- This is a state machine that can recover from an
-- illegal state (by returning to the reset state).
attribute syn_encoding : string;
attribute syn_encoding of fsm_state_type : type is "safe";

--internal logic
signal bank_index, rows_index, cols_index : Integer := 0;
signal received_data : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
signal hex_7_bcd, hex_6_bcd, hex_5_bcd, hex_4_bcd, hex_3_bcd, hex_2_bcd, hex_1_bcd, hex_0_bcd : std_logic_vector(3 downto 0) := (others=>'0');
signal test1_complete, test2_complete, full_read_complete, full_write_complete : std_logic := '0';
signal delay_clock_count : integer := 0;
signal delayed_clock : std_logic := '0';
signal data_check : std_logic := '0';
signal error_detected : std_logic := '0';
signal error_count : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'0');
signal test_pass : std_logic := '0';	--a 0 represents first pass, 1 represents second pass
signal delayed_clock_limit : std_logic_vector(5 downto 0) := (others=>'0');
--various constants
constant prescaler_limit : integer := 25000000;
constant update_hex_limit : integer := 1000000;
constant demo_number : std_logic_vector(31 downto 0) := X"12B9B0A1"; --pi up to 28-bit resolution
constant odd_demo_number : std_logic_vector(31 downto 0) := X"AAAAAAAA";
constant even_demo_number : std_logic_vector(31 downto 0) := X"55555555";

begin

seq_write_read: process(CLOCK_50, KEY, SW,  rd_done_int, wr_done_int, rd_data_int, delayed_clock)
	variable test_data : std_logic_vector(DATA_WIDTH-1 downto 0) := demo_number;
	variable i, pos : integer := 0;
	variable err_var : std_logic_vector(DATA_WIDTH-1 downto 0);
begin
	if KEY(0) = '0' then
		state <= ST_WAIT;
		received_data <= (others=>'0');
		LEDR <= received_data(15 downto 0);
		cols_index <= 0;
		rows_index <= 0;
		bank_index <= 0;
		test1_complete <= '0';
		rw_addr_int <= (others => 'Z');
		data_check <= '0';
		error_detected <= '0';
		test_pass <= '0';
	elsif rising_edge(CLOCK_50) and error_detected ='0' and err_detected_int='0' then
		error_detected <= '0';
		case state is
		when ST_WAIT=>
			if delayed_clock = '1' then
				if test_pass = '0' then
					test_data := "0000000" & std_logic_vector(to_unsigned(bank_index, BANK_WIDTH)) & std_logic_vector(to_unsigned(cols_index, COLS_WIDTH)) & std_logic_vector(to_unsigned(rows_index, ROW_WIDTH));
				else
					test_data := "0000000" & not(std_logic_vector(to_unsigned(bank_index, BANK_WIDTH)) & std_logic_vector(to_unsigned(cols_index, COLS_WIDTH)) & std_logic_vector(to_unsigned(rows_index, ROW_WIDTH)));
				end if;
				state <= ST_REQ_WRITE;
				wr_req_int <= '1';
				rw_addr_int <= std_logic_vector(to_unsigned(bank_index, BANK_WIDTH)) & std_logic_vector(to_unsigned(rows_index, ROW_WIDTH)) & std_logic_vector(to_unsigned(cols_index, COLS_WIDTH));
				wr_data_int <= test_data;
			end if;
		when ST_MOVE=>
			state <= ST_WAIT;
			if cols_index = RAM_COLS then
				cols_index <= 0;
				if rows_index = RAM_ROWS then
					rows_index <= 0;
					if bank_index = RAM_BANKS then
						bank_index <= 0;
						if test_pass = '0' then
							test_pass <= not(test_pass);
						else
							test1_complete <= '1';
						end if;
					else
						bank_index <= bank_index + 1;
						test1_complete <= '0';
					end if;
				else
					rows_index <= rows_index + 1;
					test1_complete <= '0';
				end if;
			else
				cols_index <= cols_index + 1;
				test1_complete <= '0';
			end if;
		when ST_REQ_WRITE=>
			if wr_grnt_int = '1' then
				state <= ST_WRITE;
				wr_req_int <= '0';
				rw_addr_int <= (others => 'Z');
			end if;
		when ST_WRITE=>
			if wr_done_int ='1' then
				state <= ST_REQ_READ;
				wr_req_int <= '0';
				wr_data_int <= (others=>'Z');
				rd_req_int <= '1';
				rw_addr_int <= std_logic_vector(to_unsigned(bank_index, BANK_WIDTH)) & std_logic_vector(to_unsigned(rows_index, ROW_WIDTH)) & std_logic_vector(to_unsigned(cols_index, COLS_WIDTH));
				received_data <= (others=>'0');
			end if;
			data_check <= '0';
		when ST_REQ_READ=>
			if rd_grnt_int = '1' then
				state <= ST_READ;
				rd_req_int <= '0';
				rw_addr_int <= (others => 'Z');
			end if;
		when ST_READ=>
			if rd_done_int ='1' then
				state <= ST_MOVE;
				rd_req_int <= '0';
				received_data <= rd_data_int;
				if (rd_data_int = test_data) then
				  data_check <= '1';
					LEDR <= (others=>'0');--rd_data_int(15 downto 0);
				else
				  data_check <= '0';
				  --error_detected <= '1';
					err_var := rd_data_int xor test_data;
					for i in DATA_WIDTH-1 downto 0 loop
						pos := i;
						exit when err_var(i) = '1' ;
					end loop;
					if pos >= 16 then
						LEDR <= rd_data_int(DATA_WIDTH-1 downto 16);
					else
						LEDR <= rd_data_int(15 downto 0);
					end if;
				end if;
			end if;
		end case;
	end if;
end process;


-- first_write_then_read: process(CLOCK_50, KEY, SW)
 -- variable test_data : std_logic_vector(DATA_WIDTH-1 downto 0) := demo_number;
	-- variable i, pos : integer := 0;
	-- variable err_var : std_logic_vector(DATA_WIDTH-1 downto 0);
-- begin
	-- if KEY(0) = '0' then
		-- state <= ST_WAIT;
		-- received_data <= (others=>'0');
		-- LEDR <= (others=>'0');
		-- cols_index <= 0;
		-- rows_index <= 0;
		-- bank_index <= 0;
		-- full_read_complete <= '0';
		-- full_write_complete <= '0';
		-- test2_complete <= '0';
		-- rw_addr_int <= (others => 'Z');
		-- data_check <= '0';
		-- error_detected <= '0';
	-- elsif rising_edge(CLOCK_50) and error_detected ='0' then
		-- error_detected <= '0';
		-- case state is
		-- when ST_WAIT=>
			-- if delayed_clock = '1' then
				-- --LEDR <= (others=>'0');
				-- if(rows_index mod 2)=0 then
					-- test_data := even_demo_number;
				-- else
					-- test_data := odd_demo_number;
				-- end if;
				-- if full_write_complete ='0' and SW(1) = '0' then
					-- state <= ST_WRITE;
				-- else
					-- state <= ST_READ;
				-- end if;
			-- end if;
		-- when ST_MOVE=>
			-- state <= ST_WAIT;
			-- if cols_index = RAM_COLS then
				-- cols_index <= 0;
				-- if rows_index = RAM_ROWS then
					-- rows_index <= 0;
					-- if bank_index = RAM_BANKS then
						-- bank_index <= 0;
						-- if full_write_complete = '0' and full_read_complete ='0' and SW(1) = '0' then
							-- full_write_complete <= '1';
							-- full_read_complete <= '0';
						-- elsif (full_read_complete = '0' and full_write_complete ='1') or SW(1)='1' then
							-- full_read_complete <= '1';
							-- test2_complete <= '1';
						-- end if;
					-- else
						-- bank_index <= bank_index + 1;
					-- end if;
				-- else
					-- rows_index <= rows_index + 1;
				-- end if;
			-- else
				-- cols_index <= cols_index + 1;
			-- end if;
		-- when ST_WRITE=>
			-- if wr_grnt_int = '1' then
				-- state <= ST_WRITE;
				-- wr_req_int <= '0';
				-- rw_addr_int <= (others => 'Z');
			-- else
				-- state <= ST_WRITE;
				-- wr_req_int <= '1';
				-- rw_addr_int <= std_logic_vector(to_unsigned(bank_index, BANK_WIDTH)) & std_logic_vector(to_unsigned(cols_index, COLS_WIDTH)) & std_logic_vector(to_unsigned(rows_index, ROW_WIDTH));
				-- wr_data_int <= test_data;
			-- end if;
			-- if done_int ='1' then
				-- state <= ST_MOVE;
				-- wr_req_int <= '0';
				-- wr_data_int <= (others=>'Z');
				-- rw_addr_int <= (others=>'Z');
			-- end if;
			-- data_check <= '0';
		-- when ST_READ=>
			-- if rd_grnt_int = '1' then
				-- state <= ST_READ;
				-- rd_req_int <= '0';
				-- rw_addr_int <= (others => 'Z');
			-- else
				-- state <= ST_READ;
				-- rd_req_int <= '1';
				-- rw_addr_int <= std_logic_vector(to_unsigned(bank_index, BANK_WIDTH)) & std_logic_vector(to_unsigned(cols_index, COLS_WIDTH)) & std_logic_vector(to_unsigned(rows_index, ROW_WIDTH));
				-- received_data <= (others=>'Z');
			-- end if;
			-- if done_int ='1' then
				-- state <= ST_MOVE;
				-- rd_req_int <= '0';
				-- received_data <= rd_data_int;
				-- --if ((rows_index mod 2)=0 and rd_data_int=even_demo_number) or ((rows_index mod 2)/=0 and rd_data_int=odd_demo_number) then
				-- if rd_data_int=test_data then
					-- data_check <= '1';
					-- LEDR <= rd_data_int(DATA_WIDTH-1 downto 16);
				-- else
					-- data_check <= '0';
					-- --error_detected <= '1';
					-- err_var := rd_data_int xor test_data;
					-- for i in DATA_WIDTH-1 downto 0 loop
						-- pos := i;
						-- exit when err_var(i) = '1' ;
					-- end loop;
					-- if pos >= 16 then
						-- LEDR <= rd_data_int(DATA_WIDTH-1 downto 16);
					-- else
						-- LEDR <= rd_data_int(15 downto 0);
					-- end if;
				-- end if;	
			-- end if;
				
		-- when others=>
			-- state <= ST_WAIT;
			-- received_data <= (others=>'0');
			-- LEDR <= (others=>'0');
			-- cols_index <= 0;
			-- rows_index <= 0;
			-- bank_index <= 0;
			-- full_read_complete <= '0';
			-- full_write_complete <= '0';
			-- test2_complete <= '0';
			-- rw_addr_int <= (others => 'Z');
			-- data_check <= '0';
			-- error_detected <= '0';
		-- end case;
	-- end if;
-- end process;

delay_clock: process(CLOCK_50, KEY(0), full_read_complete, rd_done_int, wr_done_int)
begin
  if KEY(0) = '0' then
    delay_clock_count <= 0;
    delayed_clock <= '0';
	 delayed_clock_limit <= SW(7 downto 2);
  elsif rising_edge(CLOCK_50) and mem_ready_int = '1' then
    if delay_clock_count = to_integer(unsigned(delayed_clock_limit)) then
		delayed_clock_limit <= SW(7 downto 2);
		delay_clock_count <= 0;
		delayed_clock <= SW(0) and not(test1_complete or test2_complete);
    else
		delayed_clock <= '0';
		delay_clock_count <= delay_clock_count + 1;
    end if;
  end if;
end process;

--sdram pins
DRAM_BA_0 <= ba(0);
DRAM_BA_1 <= ba(1);

hold_int <= '1'; --never auto precharge

--Pll drives the clock for the SDRAM -3 ns phase shift
-- synthesis read_comments_as_HDL on
--sdram_pll_inst : sdram_pll port map(inclk0 => CLOCK_50, c0 => DRAM_CLK);
-- synthesis read_comments_as_HDL off

--instantiate components
-- sdram_ctrl_inst : sdram_ctrl
-- generic map(
  -- DATA_WIDTH => DATA_WIDTH,
  -- DQM_WIDTH => DQM_WIDTH,
  -- ROW_WIDTH => ROW_WIDTH,
	-- COLS_WIDTH => COLS_WIDTH,
  -- BANK_WIDTH => BANK_WIDTH,
  -- NOP_BOOT_CYCLES => NOP_BOOT_CYCLES, --at 10MHz covers 100us
  -- REF_PERIOD => REF_PERIOD, --refresh command every to 7.8125 microseconds
  -- REF_COMMAND_COUNT => REF_COMMAND_COUNT, --How many refresh commands should be issued during initialization
  -- REF_COMMAND_PERIOD => REF_COMMAND_PERIOD, -- at 50MHz covers 60ns (tRC Command Period)
		-- PRECH_COMMAND_PERIOD => PRECH_COMMAND_PERIOD, -- tRP Command Period PRECHARGE TO ACTIVATE/REFRESH
		-- ACT_TO_RW_CYCLES => ACT_TO_RW_CYCLES,
		-- IN_DATA_TO_PRE => IN_DATA_TO_PRE,
  -- CAS_LAT_CYCLES => CAS_LAT_CYCLES, --based on CAS Latency setting
  -- MODE_REG_CYCLES => MODE_REG_CYCLES,
	-- BURST_LENGTH => BURST_LENGTH,
  -- RAM_COLS => RAM_COLS, --A full page is 512 columns
  -- RAM_ROWS => RAM_ROWS,
  -- RAM_BANKS => RAM_BANKS
-- )
-- port map(
  -- --SDRAM Interface
  -- clk_o => open,
  -- cke_o => DRAM_CKE,
  -- bank_o => ba,
  -- addr_o => DRAM_ADDR,
  -- cs_o => DRAM_CS_N,
  -- ras_o => DRAM_RAS_N,
  -- cas_o => DRAM_CAS_N,
  -- we_o => DRAM_WE_N,
  -- dqm_o => DRAM_DQM,
  -- dataQ_io => DRAM_DQ,
  -- --Controller Interface
  -- hold_i => hold_int,
  -- rst_i => KEY(0),
  -- clk_i => CLOCK_50,
  -- wr_req_i => wr_req_int,
  -- wr_grnt_o => wr_grnt_int,
  -- wr_data_i => wr_data_int,
  -- rd_data_o => rd_data_int,
  -- rd_req_i => rd_req_int,
  -- rd_grnt_o => rd_grnt_int,
  -- wr_op_done_o => wr_done_int,
  -- rd_op_done_o => rd_done_int,
  -- rw_addr_i => rw_addr_int,
  -- mem_ready_o => mem_ready_int,
  -- ctrl_state_o => open
  -- );
  
sdram_ctrl_inst : sdram_ctrl_tmr_top
generic map(
  DATA_WIDTH => DATA_WIDTH,
  DQM_WIDTH => DQM_WIDTH,
  ROW_WIDTH => ROW_WIDTH,
	COLS_WIDTH => COLS_WIDTH,
  BANK_WIDTH => BANK_WIDTH,
  NOP_BOOT_CYCLES => NOP_BOOT_CYCLES, --at 10MHz covers 100us
  REF_PERIOD => REF_PERIOD, --refresh command every to 7.8125 microseconds
  REF_COMMAND_COUNT => REF_COMMAND_COUNT, --How many refresh commands should be issued during initialization
  REF_COMMAND_PERIOD => REF_COMMAND_PERIOD, -- at 50MHz covers 60ns (tRC Command Period)
		PRECH_COMMAND_PERIOD => PRECH_COMMAND_PERIOD, -- tRP Command Period PRECHARGE TO ACTIVATE/REFRESH
		ACT_TO_RW_CYCLES => ACT_TO_RW_CYCLES,
		IN_DATA_TO_PRE => IN_DATA_TO_PRE,
  CAS_LAT_CYCLES => CAS_LAT_CYCLES, --based on CAS Latency setting
  MODE_REG_CYCLES => MODE_REG_CYCLES,
	BURST_LENGTH => BURST_LENGTH,
  RAM_COLS => RAM_COLS, --A full page is 512 columns
  RAM_ROWS => RAM_ROWS,
  RAM_BANKS => RAM_BANKS
)
port map(
  --SDRAM Interface
  clk_o => open,
  cke_o => DRAM_CKE,
  bank_o => ba,
  addr_o => DRAM_ADDR,
  cs_o => DRAM_CS_N,
  ras_o => DRAM_RAS_N,
  cas_o => DRAM_CAS_N,
  we_o => DRAM_WE_N,
  dqm_o => DRAM_DQM,
  dataQ_io => DRAM_DQ,      
  --Testing interface
  en_err_test_i=> '0',
  err_counter_o=> error_count,   
  --Controller Interface
  hold_i => hold_int,
  rst_i => KEY(0),
  clk_i => CLOCK_50,
  wr_req_i => wr_req_int,
  wr_grnt_o => wr_grnt_int,
  wr_data_i => wr_data_int,
  rd_data_o => rd_data_int,
  rd_req_i => rd_req_int,
  rd_grnt_o => rd_grnt_int,
  wr_op_done_o => wr_done_int,
  rd_op_done_o => rd_done_int,
  rw_addr_i => rw_addr_int,
  mem_ready_o => mem_ready_int,
  err_detected_o => err_detected_int,
  ctrl_state_o => open
  );
  
--status leds
OP_DONE_LED <= wr_done_int or rd_done_int;
CHECK_DATA_LED <= data_check;
FULL_READ_LED <= test1_complete OR test2_complete ;
LEDG(7) <= mem_ready_int;


-- synthesis read_comments_as_HDL on
--bin2bcd_rows : binary_bcd_converter generic map(N=>16) port map(clk=>CLOCK_50, reset=>not KEY(0), binary_in=>std_logic_vector(to_unsigned(rows_index, 16)), bcd0=>hex_0_bcd, bcd1=>hex_1_bcd, bcd2=>hex_2_bcd, bcd3=>hex_3_bcd);
--bin2bcd_cols : binary_bcd_converter generic map(N=>16) port map(clk=>CLOCK_50, reset=>not KEY(0), binary_in=>std_logic_vector(to_unsigned(cols_index, 16)), bcd0=>hex_4_bcd, bcd1=>hex_5_bcd, bcd2=>hex_6_bcd);
--bin2bcd_bank : binary_bcd_converter generic map(N=>16) port map(clk=>CLOCK_50, reset=>not KEY(0), binary_in=>std_logic_vector(to_unsigned(bank_index, 16)), bcd0=>hex_7_bcd);
--dig0 : sevensegmentdecoder port map(bcdin=>hex_0_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX0);
--dig1 : sevensegmentdecoder port map(bcdin=>hex_1_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX1);
--dig2 : sevensegmentdecoder port map(bcdin=>hex_2_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX2);
--dig3 : sevensegmentdecoder port map(bcdin=>hex_3_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX3);
--dig4 : sevensegmentdecoder port map(bcdin=>hex_4_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX4);
--dig5 : sevensegmentdecoder port map(bcdin=>hex_5_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX5);
--dig6 : sevensegmentdecoder port map(bcdin=>hex_6_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX6);
--dig7 : sevensegmentdecoder port map(bcdin=>hex_7_bcd, reset=>KEY(0), sys_clk=>CLOCK_50, output=>HEX7);
-- synthesis read_comments_as_HDL off
end behave;