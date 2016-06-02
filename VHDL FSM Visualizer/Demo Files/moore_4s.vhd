-- A Moore machine's outputs are dependent only on the current state.
-- The output is written only when the state changes.  (State
-- transitions are synchronous.)

library ieee;
use ieee.std_logic_1164.all;

entity moore_4s is

	port(
		clk		 : in	std_logic;
		data_in	 : in	std_logic;
		reset	 : in	std_logic;
		data_out	 : out	std_logic_vector(1 downto 0)
	);
	
end entity;

architecture rtl of moore_4s is

	-- Build an enumerated type for the state machine
	type state_type is (s0, s1, s2, s3);
	
	-- Register to hold the current state
	signal state   : state_type;

begin
	-- Logic to advance to the next state
	process (clk, reset)
	begin
		if reset = '1' then
			state <= s0;
		elsif (rising_edge(clk)) then
			case state is
				when s0=>
					if data_in = '1' then
						state <= s1;
					else
						state <= s3;
					end if;
				when s1=>
					if data_in = '1' then
						state <= s2;
					else
						state <= s1;
					end if;
				when s2=>
					if data_in = '1' then
						state <= s3;
					else
						state <= s2;
					end if;
				when s3 =>
					if data_in = '1' then
						state <= s0;
					else
						state <= s3;
					end if;
			end case;
		end if;
	end process;
	
	-- Output depends solely on the current state
	process (state)
	begin
	
		case state is
			when s0 =>
				data_out <= "00";
			when s1 =>
				data_out <= "01";
			when s2 =>
				data_out <= "10";
			when s3 =>
				data_out <= "11";
		end case;
	end process;
	
end rtl;
