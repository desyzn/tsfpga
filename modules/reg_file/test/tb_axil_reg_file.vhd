library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
use vunit_lib.bus_master_pkg.all;
use vunit_lib.axi_slave_pkg.all;
context vunit_lib.vunit_context;
context vunit_lib.com_context;

library osvvm;
use osvvm.RandomPkg.all;

library bfm;

library common;
use common.addr_pkg.all;

library axi;
use axi.axil_pkg.all;

use work.reg_file_pkg.all;


entity tb_axil_reg_file is
  generic (
    runner_cfg : string
  );
end entity;

architecture tb of tb_axil_reg_file is

  constant data_width : integer := 32;
  constant bytes_per_word : integer := data_width / 8;

  constant regs : reg_definition_vec_t(0 to 15 - 1) := (
    (idx => 0, reg_type => r),
    (idx => 1, reg_type => r),
    (idx => 2, reg_type => r),
    (idx => 3, reg_type => w),
    (idx => 4, reg_type => w),
    (idx => 5, reg_type => w),
    (idx => 6, reg_type => r_w),
    (idx => 7, reg_type => r_w),
    (idx => 8, reg_type => r_w),
    (idx => 9, reg_type => wpulse),
    (idx => 10, reg_type => wpulse),
    (idx => 11, reg_type => wpulse),
    (idx => 12, reg_type => r_wpulse),
    (idx => 13, reg_type => r_wpulse),
    (idx => 14, reg_type => r_wpulse)
  );

  signal clk : std_logic := '0';

  signal axil_m2s : axil_m2s_t;
  signal axil_s2m : axil_s2m_t;

  signal reg_values_in : reg_vec_t(regs'range) := (others => (others => '0'));
  signal reg_values_out : reg_vec_t(regs'range);
  signal reg_was_written : std_logic_vector(regs'range);

  constant axi_master : bus_master_t := new_bus(data_length => data_width, address_length => axil_m2s.read.ar.addr'length);

  type memory_data_t is array(0 to regs'length - 1) of std_logic_vector(data_width - 1 downto 0);

  constant reg_zero : std_logic_vector(data_width - 1 downto 0) := (others => '0');
  constant reg_was_written_zero : std_logic_vector(reg_was_written'range) := (others => '0');

begin

  test_runner_watchdog(runner, 2 ms);
  clk <= not clk after 2 ns;


  ------------------------------------------------------------------------------
  main : process
    variable rnd : RandomPType;
    variable fabric_data, bus_data : memory_data_t;

    procedure reg_stimuli(reg : reg_definition_t) is
    begin
      if is_write_type(reg.reg_type) then
        write_bus(net, axi_master, 4 * reg.idx, bus_data(reg.idx));
      end if;

      if is_fabric_gives_value_type(reg.reg_type) then
        reg_values_in(reg.idx) <= fabric_data(reg.idx);
      end if;
    end procedure;

    procedure reg_data_check(reg : reg_definition_t) is
      variable reg_was_written_expected : std_logic_vector(reg_was_written'range) := (others => '0');
    begin
      if is_write_type(reg.reg_type) then
        reg_was_written_expected(reg.idx) := '1';

        wait_for_write_to_go_through : while true loop
          if is_write_pulse_type(reg.reg_type) then
            -- The value that fabric gets should be zero all cycles except the one where the write happens
            check_equal(reg_values_out(reg.idx), reg_zero);
          end if;

          wait until rising_edge(clk);
          if reg_was_written /= reg_was_written_zero then
            check_equal(reg_was_written, reg_was_written_expected);
            exit wait_for_write_to_go_through;
          end if;
        end loop;

        check_equal(reg_values_out(reg.idx), bus_data(reg.idx));
      end if;

      if is_write_pulse_type(reg.reg_type) then
        wait until rising_edge(clk);
        -- The value that fabric gets should be zero all cycles except the one where the write happens
        check_equal(reg_values_out(reg.idx), reg_zero);
      end if;

      if is_read_type(reg.reg_type) then
        if is_fabric_gives_value_type(reg.reg_type) then
          check_bus(net, axi_master, 4 * reg.idx, fabric_data(reg.idx));
        else
          check_bus(net, axi_master, 4 * reg.idx, bus_data(reg.idx));
        end if;
      end if;
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);
    rnd.InitSeed(rnd'instance_name);

    for list_idx in regs'range loop
      fabric_data(list_idx) := rnd.RandSLV(data_width);
      bus_data(list_idx) := rnd.RandSLV(data_width);
    end loop;

    for list_idx in regs'range loop
      reg_stimuli(regs(list_idx));
      reg_data_check(regs(list_idx));
    end loop;

    test_runner_cleanup(runner);
  end process;


  ------------------------------------------------------------------------------
  axil_master_inst : entity bfm.axil_master
    generic map (
      bus_handle => axi_master
    )
    port map (
      clk => clk,

      axil_m2s => axil_m2s,
      axil_s2m => axil_s2m
    );


  ------------------------------------------------------------------------------
  dut : entity work.axil_reg_file
  generic map (
    regs => regs
  )
  port map (
    clk => clk,

    axil_m2s => axil_m2s,
    axil_s2m => axil_s2m,

    reg_values_in => reg_values_in,
    reg_values_out => reg_values_out,
    reg_was_written => reg_was_written
  );

end architecture;