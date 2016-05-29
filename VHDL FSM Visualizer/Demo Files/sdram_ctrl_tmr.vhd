----------------------------------------------------------------------------------
-- Company: KTH Department of Electronics
-- Engineer: Lefteris Kyriakakis
-- 
-- Create Date: 01/22/2016 08:26:19 PM
-- Design Name: SDRAM SDR Controller
-- Module Name: sdram_ctrl_tmr - Behavioral
-- Project Name: SUED
-- Target Devices:
-- 	Boards: Artix-7, DE2-115
--		Memories: IS42/45R86400D/16320D/32160D, IS42/45S86400D/16320D/32160D, IS42/45SM/RM/VM16160K 
-- Comments:
-- 	Currently supports only single r/w accesses, no burst mode has been implemented. 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_ctrl_tmr is
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
        RAM_COLS : Integer := 1024; --A full page is 512 columns
        RAM_ROWS : Integer := 8192;
        RAM_BANKS : Integer := 4;
		  EXT_MODE_REG_EN : Boolean := FALSE
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
        rd_data_o_1 : out std_logic_vector(DATA_WIDTH-1 downto 0);
		rd_data_o_2 : out std_logic_vector(DATA_WIDTH-1 downto 0);
		rd_data_o_3 : out std_logic_vector(DATA_WIDTH-1 downto 0);
		rw_addr_feedback_o : out std_logic_vector((COLS_WIDTH+ROW_WIDTH+BANK_WIDTH)-1 downto 0);
        rd_req_i : in std_logic;
        rd_grnt_o : out std_logic;
        wr_op_done_o : out std_logic;
		rd_op_done_o : out std_logic;
        rw_addr_i : in std_logic_vector((COLS_WIDTH+ROW_WIDTH+BANK_WIDTH)-1 downto 0);
        mem_ready_o : out std_logic;
        ctrl_state_o : out std_logic_vector(20 downto 0)
    );
end sdram_ctrl_tmr;

architecture behave of sdram_ctrl_tmr is
--Controller types.
type tmr_std_logic_buffer is array (0 to 2) of std_logic_vector(DATA_WIDTH-1 downto 0);
 
--Controller states.
type fsm_state_type is 
(
	ST_BOOTING, 
	ST_INIT_NOP, 
	ST_REF1, 
	ST_REF1_NOP, 
	ST_REF2, 
	ST_REF2_NOP, 
	ST_PRECHARGE, 
	ST_MRS, 
	ST_MRS_NOP, 
	ST_EMRS, 
	ST_EMRS_NOP, 
	ST_IDLE, 
	ST_ACTIVATE, 
	ST_ACTIVATE_NOP,
	ST_READ, 
	ST_READ_NOP,
	ST_WRITE, 
	ST_WRITE_NOP,
	ST_AUTO_PRECHARGE_NOP, 
	ST_RESET
);
attribute enum_encoding : string;
attribute enum_encoding of fsm_state_type : type is "safe";
signal current_state : fsm_state_type := ST_BOOTING;
signal next_state : fsm_state_type;
   
--TMR Function
function tmr_column_access(column: std_logic_vector(COLS_WIDTH-1 downto 0);tmr_pos: std_logic_vector(1 downto 0); tmr_step: std_logic_vector(COLS_WIDTH-1 downto 0)) return std_logic_vector is
begin
	case(tmr_pos) is
		when "00"=>
			return column; 
		when "01"=>
			return std_logic_vector(unsigned(column)+unsigned(tmr_step));
		when "10"=>
			return std_logic_vector(unsigned(column)+unsigned(not(tmr_step)));
		when others=>
			return column;
	end case;
end tmr_column_access;
	
--Counters
signal current_nop_boot_count, next_nop_boot_count : integer range 0 to NOP_BOOT_CYCLES+1 := 0;
signal current_auto_ref_count, next_auto_ref_count : integer range 0 to REF_COMMAND_PERIOD+1 := 0;
signal current_precharge_count, next_precharge_count : integer range 0 to PRECH_COMMAND_PERIOD+1 := 0;
signal current_act_to_rw_count, next_act_to_rw_count : integer range 0 to ACT_TO_RW_CYCLES+1 := 0;
signal current_cas_rd_count, next_cas_rd_count : integer range 0 to CAS_LAT_CYCLES+1 := 0;
signal current_nop_wr_count, next_nop_wr_count : integer range 0 to IN_DATA_TO_PRE+1 := 0;
signal current_pend_ref_count, next_pend_ref_count : integer range 0 to REF_PERIOD+1 := 0;
signal current_ref_cmd_count, next_ref_cmd_count : integer range 0 to REF_COMMAND_COUNT+1 := 0;
signal current_tmr_op_count, next_tmr_op_count : integer range 0 to 4 := 0;
--Internal logic signals
signal current_pending_refresh, next_pending_refresh : std_logic := '0';
signal current_first_access,  next_first_access: std_logic := '1';
--SDRAM
signal current_cke, next_cke : std_logic := '1';
signal current_address_bus, next_address_bus : std_logic_vector((ROW_WIDTH+BANK_WIDTH)-1 downto 0) := (others=>'Z');
signal current_cs, next_cs : std_logic := '0';
signal current_ras, next_ras : std_logic := '0';
signal current_cas, next_cas : std_logic := '0';
signal current_we, next_we : std_logic := '0';
signal current_dqm, next_dqm : std_logic_vector(DQM_WIDTH-1 downto 0) := (others=>'1');
--HOST
signal current_mem_ready, next_mem_ready : std_logic := '0';
signal current_wr_op_done, next_wr_op_done, current_rd_op_done, next_rd_op_done : std_logic := '0';
signal current_rw_addr, next_rw_addr : std_logic_vector((COLS_WIDTH+ROW_WIDTH+BANK_WIDTH)-1 downto 0) := (others=>'0');
signal current_rd_req, next_rd_req : std_logic := '0';
signal current_rd_grnt, next_rd_grnt : std_logic := '0';
signal current_wr_req, next_wr_req : std_logic := '0';
signal current_wr_grnt, next_wr_grnt : std_logic := '0';
signal current_hold, next_hold : std_logic := '0';
signal current_rd_buffer, next_rd_buffer : tmr_std_logic_buffer := (others=>(others=>'0'));
signal current_wr_buffer, next_wr_buffer : std_logic_vector(DATA_WIDTH-1 downto 0) := (others=>'Z');

--SDRAM commands
constant NOP_CMD : std_logic_vector(3 downto 0) := "0111";   --/CS/RAS/CAS/WE
constant MRS_EMRS_CMD : std_logic_vector(3 downto 0) := "0000";   --/CS/RAS/CAS/WE
constant MRS_OPCODE : std_logic_vector(14 downto 0) := "00000"&"1"&"00"&std_logic_vector(to_unsigned(CAS_LAT_CYCLES, 3))&"0"&"000";
constant EMRS_OPCODE : std_logic_vector(14 downto 0) := "1000000"&"000"&"00"&"000";
constant AUTO_REF_CMD : std_logic_vector(3 downto 0) := "0001";  --/CS/RAS/CAS/WE
constant PRECH_ALL_CMD : std_logic_vector(3 downto 0) := "0010";  --/CS/RAS/CAS/WE
constant ACTIVATE_CMD : std_logic_vector(3 downto 0) := "0011"; --CS/RAS/CAS/WE
constant READ_CMD : std_logic_vector(3 downto 0) := "0101";  --/CS/RAS/CAS/WE
constant WRITE_CMD : std_logic_vector(3 downto 0) := "0100";  --/CS/RAS/CAS/WE
--HOST TMR
constant TMR_COLS : std_logic_vector(COLS_WIDTH-1 downto 0) := std_logic_vector(to_unsigned(RAM_COLS/3, 10));

--easy aliases
alias rw_addr_i_column:std_logic_vector(COLS_WIDTH-1 downto 0) is rw_addr_i(COLS_WIDTH-1 downto 0);
alias rw_addr_i_row:std_logic_vector(ROW_WIDTH-1 downto 0) is rw_addr_i(ROW_WIDTH+COLS_WIDTH-1 downto COLS_WIDTH);
alias rw_addr_i_bank:std_logic_vector(BANK_WIDTH-1 downto 0) is rw_addr_i(COLS_WIDTH+ROW_WIDTH+BANK_WIDTH-1 downto COLS_WIDTH+ROW_WIDTH);

alias current_rw_addr_column:std_logic_vector(COLS_WIDTH-1 downto 0) is current_rw_addr(COLS_WIDTH-1 downto 0);
alias current_rw_addr_row:std_logic_vector(ROW_WIDTH-1 downto 0) is current_rw_addr(ROW_WIDTH+COLS_WIDTH-1 downto COLS_WIDTH);
alias current_rw_addr_bank:std_logic_vector(BANK_WIDTH-1 downto 0) is current_rw_addr(COLS_WIDTH+ROW_WIDTH+BANK_WIDTH-1 downto COLS_WIDTH+ROW_WIDTH);
alias next_rw_addr_column:std_logic_vector(COLS_WIDTH-1 downto 0) is next_rw_addr(COLS_WIDTH-1 downto 0);
alias next_rw_addr_row:std_logic_vector(ROW_WIDTH-1 downto 0) is next_rw_addr(ROW_WIDTH+COLS_WIDTH-1 downto COLS_WIDTH);
alias next_rw_addr_bank:std_logic_vector(BANK_WIDTH-1 downto 0) is next_rw_addr(COLS_WIDTH+ROW_WIDTH+BANK_WIDTH-1 downto COLS_WIDTH+ROW_WIDTH);


begin
--Register signals	
regs: process(clk_i, rst_i)
begin
	if rst_i = '0' then
		current_state <= ST_RESET;
		--internal
		current_pending_refresh <= '0';
		--counters
		current_nop_boot_count <= 0;
		current_auto_ref_count <= 0;
		current_cas_rd_count <= 0;
		current_nop_wr_count <= 0;
		current_act_to_rw_count <= 0;
		current_pend_ref_count<=0;
		current_ref_cmd_count <=0;
		current_tmr_op_count <=0;
		--sdram
		current_cke <= '1';
		current_address_bus <= (others=>'Z');
		current_cs <= NOP_CMD(3);
		current_ras <= NOP_CMD(2);
		current_cas <= NOP_CMD(1);
		current_we <= NOP_CMD(0);
		current_dqm <= (others=>'1');
		--host
		current_wr_op_done <= '0';
		current_rd_op_done <= '0';
		current_rw_addr <= (others=>'0');
		current_rd_req <= '0';
		current_rd_grnt <= '0';
		current_wr_req <= '0';
		current_wr_grnt <= '0';
		current_hold <= '0';
		current_rd_buffer <= (others=>(others=>'0'));
		current_wr_buffer <= (others=>'Z');
	elsif rising_edge(clk_i) then
		current_state <= next_state;
		--counters
		current_nop_boot_count <= next_nop_boot_count;
		current_auto_ref_count <= next_auto_ref_count;
		current_precharge_count <= next_precharge_count;
		current_act_to_rw_count <= next_act_to_rw_count;
		current_cas_rd_count <= next_cas_rd_count;
		current_nop_wr_count <= next_nop_wr_count;
		current_pend_ref_count <= next_pend_ref_count;
		current_ref_cmd_count <= next_ref_cmd_count;
		current_tmr_op_count <= next_tmr_op_count;
		--internal
		current_pending_refresh <= next_pending_refresh;
		current_first_access <= next_first_access;
		--sdram
		current_cke <= next_cke;
		current_address_bus <= next_address_bus;
		current_cs <= next_cs;
		current_ras <= next_ras;
		current_cas <= next_cas;
		current_we <= next_we;
		current_dqm <= next_dqm;
		--host
		current_mem_ready <= next_mem_ready;
		current_wr_op_done <= next_wr_op_done;
		current_rd_op_done <= next_rd_op_done;
		current_rw_addr <= next_rw_addr;
		current_rd_req <= next_rd_req;
		current_rd_grnt <= next_rd_grnt;
		current_wr_req <= next_wr_req;
		current_wr_grnt <= next_wr_grnt;
		current_hold <= next_hold;
		current_rd_buffer <= next_rd_buffer;
		current_wr_buffer <= next_wr_buffer;
	end if;
end process;



--Drive next state
logic: process(current_state, rw_addr_i, rd_req_i, wr_req_i, wr_data_i, hold_i, 
		current_pending_refresh, current_nop_boot_count, current_auto_ref_count, current_precharge_count,
		current_act_to_rw_count, current_ref_cmd_count, current_nop_wr_count, current_cas_rd_count, current_pend_ref_count, current_mem_ready, current_rd_req, current_wr_req,
		current_hold, current_cke, current_address_bus, current_cs, current_ras, current_cas, current_we, current_dqm, current_rd_op_done, current_wr_op_done, current_rw_addr, current_rd_grnt, current_first_access,
		current_wr_grnt, current_rd_buffer, current_wr_buffer, dataQ_io, current_tmr_op_count)
begin
	--avoid latches
	next_state <= current_state;
	--counters
	next_nop_boot_count <= current_nop_boot_count;
	next_auto_ref_count <= current_auto_ref_count;
	next_precharge_count <= current_precharge_count;
	next_act_to_rw_count <= current_act_to_rw_count;
	next_cas_rd_count <= current_cas_rd_count;
	next_nop_wr_count <= current_nop_wr_count;
	next_ref_cmd_count <= current_ref_cmd_count;
	next_tmr_op_count <= current_tmr_op_count;
	--internal
	if current_mem_ready = '1' and current_pending_refresh = '0' then
		if current_pend_ref_count = REF_PERIOD then
			next_pend_ref_count <= 0;
			next_pending_refresh <= '1';
		else
			next_pend_ref_count <= current_pend_ref_count + 1;
			next_pending_refresh <= current_pending_refresh;
		end if;
	else
		next_pend_ref_count <= current_pend_ref_count;
		next_pending_refresh <= current_pending_refresh;
	end if;
	next_first_access <= current_first_access;
	--sdram
	next_cke <= current_cke;
	next_address_bus <= current_address_bus;
	next_cs <= current_cs;
	next_ras <= current_ras;
	next_cas <= current_cas;
	next_we <= current_we;
	next_dqm <= current_dqm;
	--host
	next_mem_ready <= current_mem_ready;
	next_wr_op_done <= current_wr_op_done;
	next_rd_op_done <= current_rd_op_done;
	next_rw_addr <= current_rw_addr;
	next_rd_req <= current_rd_req;
	next_rd_grnt <= current_rd_grnt;
	next_wr_req <= current_wr_req;
	next_wr_grnt <= current_wr_grnt;
	next_hold <= current_hold;
	next_rd_buffer <= current_rd_buffer;
	next_wr_buffer <= current_wr_buffer;
	--drive the logic
	case current_state is
--Reset FSM
		when ST_RESET=>
			if current_mem_ready = '0' then
				next_state <= ST_BOOTING;
			else
				next_state <= ST_IDLE;
			end if;
			
--Init FSM Start
		when ST_BOOTING=>
			next_state <= ST_INIT_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			--host
			next_rd_buffer <= (others=>(others=>'0'));
			next_wr_buffer <= (others=>'0');
			next_mem_ready <= '0';
			next_rd_grnt <= '0';
			next_wr_grnt <= '0';
			next_wr_op_done <= '0';
			next_rd_op_done <= '0';
			--internal
			next_first_access <= '1';
			
		when ST_INIT_NOP=>
			if current_nop_boot_count = NOP_BOOT_CYCLES-1 then
				next_nop_boot_count <= 0;
				next_state <= ST_PRECHARGE;
				--sdram
				next_cke <= '1';
				next_we <= PRECH_ALL_CMD(0);
				next_cas <= PRECH_ALL_CMD(1);
				next_ras <= PRECH_ALL_CMD(2);
				next_cs <= PRECH_ALL_CMD(3);
				next_dqm <= (others=>'1');
				next_address_bus <= (others=>'0');
				next_address_bus(10) <= '1';
			else
				next_nop_boot_count <= current_nop_boot_count + 1;
			end if;
			
		when ST_PRECHARGE=>
			next_first_access <= '1';
			if current_precharge_count = PRECH_COMMAND_PERIOD-1 then
				next_precharge_count <= 0;
				if current_mem_ready = '0' then
					next_state <= ST_REF1;
					--sdram
					next_cke <= '1';
					next_we <= AUTO_REF_CMD(0);
					next_cas <= AUTO_REF_CMD(1);
					next_ras <= AUTO_REF_CMD(2);
					next_cs <= AUTO_REF_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus <= (others => 'Z');
				else
					next_state <= ST_IDLE;
					--sdram
					next_cke <= '1';
					next_we <= NOP_CMD(0);
					next_cas <= NOP_CMD(1);
					next_ras <= NOP_CMD(2);
					next_cs <= NOP_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus <= (others=>'Z');
				end if;
			else
				next_precharge_count <= current_precharge_count + 1;
			end if;
			
		when ST_REF1=>
			next_first_access <= '1';
			next_state <= ST_REF1_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			
		when ST_REF1_NOP=>
			if current_auto_ref_count = REF_COMMAND_PERIOD-1 then
				next_auto_ref_count <= 0;
				if current_mem_ready = '0' then
					next_state <= ST_REF2;
					--sdram
					next_cke <= '1';
					next_we <= AUTO_REF_CMD(0);
					next_cas <= AUTO_REF_CMD(1);
					next_ras <= AUTO_REF_CMD(2);
					next_cs <= AUTO_REF_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus <= (others => 'Z');
				else
					next_pending_refresh <= '0';
					next_state <= ST_IDLE;
					--sdram
					next_cke <= '1';
					next_we <= NOP_CMD(0);
					next_cas <= NOP_CMD(1);
					next_ras <= NOP_CMD(2);
					next_cs <= NOP_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus <= (others=>'Z');
				end if;
			else
				next_auto_ref_count <= current_auto_ref_count + 1;
			end if;
			
		when ST_REF2=>
			next_state <= ST_REF2_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			
		when ST_REF2_NOP=>
			if current_auto_ref_count = REF_COMMAND_PERIOD-1 then
				next_auto_ref_count <= 0;
				if current_ref_cmd_count = (REF_COMMAND_COUNT/2)-1 then
					next_ref_cmd_count <= 0;
					next_state <= ST_MRS;
					--sdram
					next_cke <= '1';
					next_we <= MRS_EMRS_CMD(0);
					next_cas <= MRS_EMRS_CMD(1);
					next_ras <= MRS_EMRS_CMD(2);
					next_cs <= MRS_EMRS_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus <= MRS_OPCODE;
				else
					next_ref_cmd_count <= current_ref_cmd_count + 1;
					next_state <= ST_REF1;
					--sdram
					next_cke <= '1';
					next_we <= AUTO_REF_CMD(0);
					next_cas <= AUTO_REF_CMD(1);
					next_ras <= AUTO_REF_CMD(2);
					next_cs <= AUTO_REF_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus <= (others => 'Z');
				end if;
			else
				next_auto_ref_count <= current_auto_ref_count + 1;
			end if;
			
		when ST_MRS=>
			next_state <= ST_MRS_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			
		when ST_MRS_NOP=> --MRS needs 2 cycles tMRD
			if EXT_MODE_REG_EN then
				next_state <= ST_EMRS;
				--sdram
				next_cke <= '1';
				next_we <= MRS_EMRS_CMD(0);
				next_cas <= MRS_EMRS_CMD(1);
				next_ras <= MRS_EMRS_CMD(2);
				next_cs <= MRS_EMRS_CMD(3);
				next_dqm <= (others=>'1');
				next_address_bus <= EMRS_OPCODE;
			else
				next_state <= ST_IDLE; 
				--sdram
				next_cke <= '1';
				next_we <= NOP_CMD(0);
				next_cas <= NOP_CMD(1);
				next_ras <= NOP_CMD(2);
				next_cs <= NOP_CMD(3);
				next_dqm <= (others=>'1');
				next_address_bus <= (others=>'Z');
				--host
				next_mem_ready <= '1';
			end if;
			
			
		when ST_EMRS=>
			next_state <= ST_EMRS_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			
		when ST_EMRS_NOP=> --EMRS needs 2 cycles tMRD
			next_state <= ST_IDLE; 
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			--host
			next_mem_ready <= '1';
			
--Init FSM End
--Main FSM Start
		when ST_IDLE=>
			next_rd_op_done <= '0';
			next_wr_op_done <= '0';
			next_rd_grnt <= '0';
			next_wr_grnt <= '0';
			if current_pending_refresh = '1' then
				next_state <= ST_REF1;
				next_cke <= '1';
				next_we <= AUTO_REF_CMD(0);
				next_cas <= AUTO_REF_CMD(1);
				next_ras <= AUTO_REF_CMD(2);
				next_cs <= AUTO_REF_CMD(3);
				next_dqm <= (others=>'1');
				next_address_bus <= (others => 'Z');
			elsif rd_req_i = '1' OR wr_req_i = '1' then
				next_state <= ST_ACTIVATE;
				--sdram
				next_cke <= '1';
				next_we <= ACTIVATE_CMD(0);
				next_cas <= ACTIVATE_CMD(1);
				next_ras <= ACTIVATE_CMD(2);
				next_cs <= ACTIVATE_CMD(3);
				next_dqm <= (others=>'1');
				next_address_bus(ROW_WIDTH-1 downto 0) <= rw_addr_i_row; --select row
				next_address_bus(BANK_WIDTH+ROW_WIDTH-1 downto ROW_WIDTH) <= rw_addr_i_bank; --select bank
				--host
				next_rd_grnt <= rd_req_i;
				next_wr_grnt <= wr_req_i;
				next_rw_addr <= rw_addr_i;
				next_rd_req <= rd_req_i;
				next_wr_req <= wr_req_i;
				next_hold <= hold_i;
				if wr_req_i = '1' then
					next_wr_buffer <= wr_data_i;
				else
					next_wr_buffer <= (others=>'Z');
				end if;
			end if;
			
		when ST_ACTIVATE=>
			next_state <= ST_ACTIVATE_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			--internal
			if current_first_access='1' then
				next_first_access <= '0';
			end if;
			
		when ST_ACTIVATE_NOP=>
			if current_act_to_rw_count = ACT_TO_RW_CYCLES-1 then
				next_act_to_rw_count <= 0;
				if current_rd_grnt = '1' then
						next_state <= ST_READ;
						--sdram
						next_cke <= '1';
						next_we <= READ_CMD(0);
						next_cas <= READ_CMD(1);
						next_ras <= READ_CMD(2);
						next_cs <= READ_CMD(3);
						next_dqm <= (others=>'0');
						next_address_bus <= (others=>'0');
						next_address_bus(COLS_WIDTH-1 downto 0) <= tmr_column_access(current_rw_addr_column, std_logic_vector(to_unsigned(current_tmr_op_count, 2)), TMR_COLS); --select column
						next_address_bus(10) <= '1'; --auto-precharche cmd
						next_address_bus(BANK_WIDTH+ROW_WIDTH-1 downto ROW_WIDTH) <= current_rw_addr_bank; --select bank
				elsif current_wr_grnt = '1' then
						next_state <= ST_WRITE;
						--sdram
						next_cke <= '1';
						next_we <= WRITE_CMD(0);
						next_cas <= WRITE_CMD(1);
						next_ras <= WRITE_CMD(2);
						next_cs <= WRITE_CMD(3);
						next_dqm <= (others=>'0');
						next_address_bus <= (others=>'0');
						next_address_bus(COLS_WIDTH-1 downto 0) <= tmr_column_access(current_rw_addr_column, std_logic_vector(to_unsigned(current_tmr_op_count, 2)), TMR_COLS); --select column
						next_address_bus(10) <= '1'; --auto-precharche cmd
						next_address_bus(BANK_WIDTH+ROW_WIDTH-1 downto ROW_WIDTH) <= current_rw_addr_bank; --select bank
				end if;
			else
				next_act_to_rw_count <= current_act_to_rw_count + 1;
			end if;
			
		when ST_READ=>
			next_state <= ST_READ_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			
		when ST_READ_NOP=>
			if current_cas_rd_count = CAS_LAT_CYCLES-1 then
				next_cas_rd_count <= 0;
				next_state <= ST_AUTO_PRECHARGE_NOP;
				--sdram
				next_cke <= '1';
				next_we <= NOP_CMD(0);
				next_cas <= NOP_CMD(1);
				next_ras <= NOP_CMD(2);
				next_cs <= NOP_CMD(3);
				next_dqm <= (others=>'1');
				--host
				-- synthesis read_comments_as_HDL on
				-- next_rd_buffer(current_tmr_op_count) <= dataQ_io;
				-- synthesis read_comments_as_HDL off
				-- synthesis translate_off
				next_rd_buffer(current_tmr_op_count) <= "01010100010001010101001101010100";
				-- synthesis translate_on
			else
				next_cas_rd_count <= current_cas_rd_count + 1;
			end if;
			
		when ST_WRITE=>
			next_state <= ST_WRITE_NOP;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			next_address_bus <= (others=>'Z');
			
		when ST_WRITE_NOP=>	
			if current_nop_wr_count = IN_DATA_TO_PRE-1 then
				next_nop_wr_count <= 0;
				next_state <= ST_AUTO_PRECHARGE_NOP;
			else
				next_nop_wr_count <= current_nop_wr_count + 1;
			end if;
			--sdram
			next_cke <= '1';
			next_we <= NOP_CMD(0);
			next_cas <= NOP_CMD(1);
			next_ras <= NOP_CMD(2);
			next_cs <= NOP_CMD(3);
			next_dqm <= (others=>'1');
			
		when ST_AUTO_PRECHARGE_NOP=>
			if current_tmr_op_count = 2 then
				next_precharge_count <= 0;
				next_tmr_op_count <= 0;
				next_state <= ST_IDLE;
				--sdram
				next_cke <= '1';
				next_we <= NOP_CMD(0);
				next_cas <= NOP_CMD(1);
				next_ras <= NOP_CMD(2);
				next_cs <= NOP_CMD(3);
				next_dqm <= (others=>'1');
				next_address_bus <= (others=>'Z');
				--host
				next_rd_op_done <= current_rd_grnt;
				next_wr_op_done <= current_wr_grnt;
			else
				if current_precharge_count = PRECH_COMMAND_PERIOD-1 then
					next_precharge_count <= 0;
					next_tmr_op_count <= current_tmr_op_count + 1; --increase tmr col access;
					next_state <= ST_ACTIVATE;
					--sdram
					next_cke <= '1';
					next_we <= ACTIVATE_CMD(0);
					next_cas <= ACTIVATE_CMD(1);
					next_ras <= ACTIVATE_CMD(2);
					next_cs <= ACTIVATE_CMD(3);
					next_dqm <= (others=>'1');
					next_address_bus(ROW_WIDTH-1 downto 0) <= current_rw_addr_row; --select row
					next_address_bus(BANK_WIDTH+ROW_WIDTH-1 downto ROW_WIDTH) <= current_rw_addr_bank; --select bank
				else
					next_precharge_count <= current_precharge_count + 1;
				end if;
			end if;
		
	--Main FSM End
		when others=>
			next_state <= ST_RESET;
	end case;
end process;


--Drive Output pins
--memory Interface
clk_o <= clk_i;
cke_o <= current_cke;
bank_o <= current_address_bus(14 downto 13);
addr_o <= current_address_bus(12 downto 0);
cs_o <= current_cs;
ras_o <= current_ras;
cas_o <= current_cas;
we_o <= current_we;
dqm_o <= current_dqm;
dataQ_io <= current_wr_buffer; 
--host Interface
wr_grnt_o <= current_wr_grnt;
rd_data_o_1 <= current_rd_buffer(0);
rd_data_o_2 <= current_rd_buffer(1);
rd_data_o_3 <= current_rd_buffer(2);
rw_addr_feedback_o <= current_rw_addr;
rd_grnt_o <= current_rd_grnt;
wr_op_done_o <= current_wr_op_done;
rd_op_done_o <= current_rd_op_done;
mem_ready_o <= current_mem_ready;
ctrl_state_o <= std_logic_vector(to_unsigned(fsm_state_type'pos(current_state), 21));
end behave;
