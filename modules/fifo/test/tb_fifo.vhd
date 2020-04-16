-- -----------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
-- -----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
use vunit_lib.random_pkg.all;
context vunit_lib.vunit_context;
context vunit_lib.data_types_context;

library osvvm;
use osvvm.RandomPkg.all;


entity tb_fifo is
  generic (
    depth : integer;
    almost_full_level : integer;
    almost_empty_level : integer;
    runner_cfg : string
  );
end entity;

architecture tb of tb_fifo is

  constant width : integer := 8;

  signal clk : std_logic := '0';

  signal read_ready, read_valid, almost_empty : std_logic := '0';
  signal write_ready, write_valid, almost_full : std_logic := '0';
  signal read_data, write_data : std_logic_vector(width - 1 downto 0) := (others => '0');
  signal queue : queue_t := new_queue;

  signal read_num, read_max_jitter, write_num, write_max_jitter : integer := 0;
  signal read_start, read_done, write_start, write_done : boolean := false;

  signal has_gone_full_times, has_gone_empty_times : integer := 0;

  signal data_queue : queue_t := new_queue;
  shared variable rnd : RandomPType;

begin

  test_runner_watchdog(runner, 20 ms);
  clk <= not clk after 2 ns;


  ------------------------------------------------------------------------------
  main : process

    procedure run_test(read_count, write_count : natural) is
    begin
      read_num <= read_count;
      write_num <= write_count;

      read_start <= true;
      write_start <= true;

      wait until rising_edge(clk);
      read_start <= false;
      write_start <= false;

      wait until read_done and write_done and rising_edge(clk);
    end procedure;

    procedure run_read(count : natural) is
    begin
      run_test(count, 0);
    end procedure;

    procedure run_write(count : natural) is
    begin
      run_test(0, count);
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);
    rnd.InitSeed(rnd'instance_name);

    if run("test_write_faster_than_read") then
      write_max_jitter <= 2;
      read_max_jitter <= 4;

      run_test(100 * depth, 100 * depth);
      check_true(is_empty(data_queue));
      check_relation(has_gone_full_times > 200, "Got " & to_string(has_gone_full_times));

    elsif run("test_read_faster_than_write") then
      write_max_jitter <= 4;
      read_max_jitter <= 2;

      run_test(100 * depth, 100 * depth);
      check_true(is_empty(data_queue));
      check_relation(has_gone_empty_times > 200, "Got " & to_string(has_gone_empty_times));

    elsif run("test_almost_full") then
      check_equal(almost_full, '0');

      run_write(almost_full_level - 1);
      check_equal(almost_full, '0');

      run_write(1);
      check_equal(almost_full, '1');

      run_read(1);
      check_equal(almost_full, '0');

    elsif run("test_almost_empty") then
      check_equal(almost_empty, '1');

      run_write(almost_empty_level);
      check_equal(almost_empty, '1');

      run_write(1);
      if almost_empty_level = 0 then
        -- almost_empty is updated one cycle later, since write must propagate into RAM before
        -- read data is valid
        wait until rising_edge(clk);
      end if;
      check_equal(almost_empty, '0');

      run_read(1);
      check_equal(almost_empty, '1');
    end if;

    test_runner_cleanup(runner);
  end process;


  ------------------------------------------------------------------------------
  write : process
    variable data : std_logic_vector(write_data'range);
  begin
    wait until write_start and rising_edge(clk);
    write_done <= false;

    for data_idx in 0 to write_num - 1 loop
      data := rnd.RandSLV(data'length);
      push(data_queue, data);

      write_data <= data;
      write_valid <= '1';
      wait until (write_ready and write_valid) = '1' and rising_edge(clk);

      write_valid <= '0';
      for wait_cycle in 1 to rnd.FavorSmall(0, write_max_jitter) loop
        wait until rising_edge(clk);
      end loop;
    end loop;

    write_done <= true;
  end process;


  ------------------------------------------------------------------------------
  read : process
  begin
    wait until read_start and rising_edge(clk);
    read_done <= false;

    for data_idx in 0 to read_num - 1 loop
      read_ready <= '1';
      wait until (read_ready and read_valid) = '1' and rising_edge(clk);

      check_equal(read_data, pop_std_ulogic_vector(data_queue), "data_idx " & to_string(data_idx));

      read_ready <= '0';
      for wait_cycle in 1 to rnd.FavorSmall(0, read_max_jitter) loop
        wait until rising_edge(clk);
      end loop;
    end loop;

    read_done <= true;
  end process;


  ------------------------------------------------------------------------------
  status_tracking : process
    variable read_transaction, write_transaction : std_logic := '0';
  begin
    wait until rising_edge(clk);

    -- If there was a read transaction last clock cycle, and we now want to read but there is no data available.
    if read_transaction and read_ready and not read_valid then
      has_gone_empty_times <= has_gone_empty_times + 1;
    end if;

    -- If there was a write transaction last clock cycle, and we now want to write but the fifo is full.
    if write_transaction and write_valid and not write_ready then
      has_gone_full_times <= has_gone_full_times + 1;
    end if;

    read_transaction := read_ready and read_valid;
    write_transaction := write_ready and write_valid;
  end process;


  ------------------------------------------------------------------------------
  dut : entity work.fifo
    generic map (
      width => width,
      depth => depth,
      include_level_counter => false,
      almost_full_level => almost_full_level,
      almost_empty_level => almost_empty_level
    )
    port map (
      clk => clk,

      read_ready => read_ready,
      read_valid => read_valid,
      read_data => read_data,
      almost_empty => almost_empty,

      write_ready => write_ready,
      write_valid => write_valid,
      write_data => write_data,
      almost_full => almost_full
    );

end architecture;
