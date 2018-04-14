from hdl_reuse.module import BaseModule


class Module(BaseModule):

    def setup_simulations(self, vunit_proj, **kwargs):
        tb = vunit_proj.library(self.library_name).test_bench("tb_fifo")
        for width in [8, 24]:
            for depth in [16, 1024]:
                name = "width_%i.depth_%i" % (width, depth)
                tb.add_config(name=name, generics=dict(width=width, depth=depth))
