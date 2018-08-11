-- @brief Convert AXI transfers to AXI-Lite transfers, along with some checks.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library math;
use math.math_pkg.all;

use work.axi_pkg.all;
use work.axil_pkg.all;


entity axi_to_axil is
  generic (
    data_width : integer
  );
  port (
    clk : in std_logic;

    axi_m2s : in axi_m2s_t := axi_m2s_init;
    axi_s2m : out axi_s2m_t := axi_s2m_init;

    axil_m2s : out axil_m2s_t := axil_m2s_init;
    axil_s2m : in axil_s2m_t := axil_s2m_init
  );
end entity;

architecture a of axi_to_axil is

  constant len : integer := 0;
  constant size : integer := log2(data_width / 8);

  subtype data_rng is integer range data_width - 1 downto 0;
  subtype strb_rng is integer range data_width / 8 - 1 downto 0;

  signal read_error, write_error : boolean := false;

begin

  ------------------------------------------------------------------------------
  axil_m2s.read.ar.valid <= axi_m2s.read.ar.valid;
  axil_m2s.read.ar.addr <= axi_m2s.read.ar.addr;

  axi_s2m.read.ar.ready <= axil_s2m.read.ar.ready;

  axil_m2s.read.r.ready <= axi_m2s.read.r.ready;

  axi_s2m.read.r.valid <= axil_s2m.read.r.valid;
  axi_s2m.read.r.data(data_rng) <= axil_s2m.read.r.data(data_rng);
  axi_s2m.read.r.resp <= axi_resp_slverr when read_error else axil_s2m.read.r.resp;
  axi_s2m.read.r.last <= '1';


  ------------------------------------------------------------------------------
  axil_m2s.write.aw.valid <= axi_m2s.write.aw.valid;
  axil_m2s.write.aw.addr <= axi_m2s.write.aw.addr;

  axi_s2m.write.aw.ready <= axil_s2m.write.aw.ready;

  axil_m2s.write.w.valid <= axi_m2s.write.w.valid;
  axil_m2s.write.w.data(data_rng) <= axi_m2s.write.w.data(data_rng);
  axil_m2s.write.w.strb(strb_rng) <= axi_m2s.write.w.strb(strb_rng);

  axi_s2m.write.w.ready <= axil_s2m.write.w.ready;


  ------------------------------------------------------------------------------
  axil_m2s.write.b.ready <= axi_m2s.write.b.ready;

  axi_s2m.write.b.valid <= axil_s2m.write.b.valid;
  axi_s2m.write.b.resp <= axi_resp_slverr when write_error else axil_s2m.write.b.resp;


  ------------------------------------------------------------------------------
  check_for_bus_error : process
  begin
    wait until rising_edge(clk);

    -- If an error occurs the bus will return an error not only for the offending transaction, but for all upcoming transactions as well.
    -- The software making the memory access will usually hard crash with "Bus error" message if the AXI bus returns an error.
    -- Hence it should not be a problem to block the bus forever.

    if (axi_m2s.write.aw.valid and axi_s2m.write.aw.ready) = '1' then
      if to_integer(unsigned(axi_m2s.write.aw.len)) /= len or to_integer(unsigned(axi_m2s.write.aw.size)) /= size then
        write_error <= true;
      end if;
    end if;

    if (axi_m2s.read.ar.valid and axi_s2m.read.ar.ready) = '1' then
      if to_integer(unsigned(axi_m2s.read.ar.len)) /= len or to_integer(unsigned(axi_m2s.read.ar.size)) /= size then
        read_error <= true;
      end if;
    end if;
  end process;

end architecture;