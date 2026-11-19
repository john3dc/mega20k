#!/usr/bin/env python3
"""Source-checked Apycula fixes for GW2A-18C PLLs and mixed LVDS/GPIO banks.

The bundled GW2A.get_pll_bels omits the left-hand 'else: offx = 1'.
The same inward four-tile layout is already implemented by its GW1N peer.
Also retain each SNES pin's LVCMOS33 type alongside the LVDS HDMI clock.
The installed tool remains unchanged; corrections apply only in this process.
Run with .tools/oss-cad-suite/bin/tabbypy3.
"""

import copy
import hashlib
import inspect
import json
from pathlib import Path
from apycula import gowin_pack

original = gowin_pack.GW2A.get_pll_bels
source = inspect.getsource(original)
expected = '''    def get_pll_bels(self, bel: BelDesc) -> Iterator[tuple[int, int]]:
        """ PLL can occupy several cells """
        if bel.x > 27:
            offx = -1
        for off in range(4):
            yield (bel.x + offx * off, bel.y)
'''
assert (
    source == expected
), "Packer changed: review whether the left-PLL workaround is still needed"


def nano_pll_bels(self, bel):
    assert bel.x in (0, 55) and bel.y == 45, (bel.x, bel.y)
    direction = -1 if bel.x > 27 else 1
    yield from ((bel.x + direction * i, bel.y) for i in range(4))


gowin_pack.GW2A_18C.get_pll_bels = nano_pll_bels
check_banks = gowin_pack.Device.check_io_banks


def checked_banks(self):
    check_banks(self)
    report = {
        str(k): {"attributes": v.attrs, "ports": [b.cell.name for b in v.bels]}
        for k, v in self.io_banks.items()
        if v.is_used
    }
    for bank in report.values():
        if any("snes_clock1" in name for name in bank["ports"]):
            assert (
                bank["attributes"]["BANK_VCCIO"] == "3.3"
            ), "SNES bank must use the board 3.3 V supply, including with HDMI enabled"
    Path("io-banks.json").write_text(json.dumps(report, indent=2) + "\n")


gowin_pack.Device.check_io_banks = checked_banks
# The bundled packer applies the bank's LVDS25 type to ordinary GPIO too.
# Bank 5 mixes a true-LVDS HDMI clock with LVCMOS33 SNES pins. Preserve each
# GPIO's explicit type while retaining the shared bank voltage/LVDS settings.
io_fixes = []


def preserve_gpio_type(method):
    def fixed(self, bank, bel):
        local_type = bel.cell.attrs.get("IO_TYPE")
        if bank.has_true_lvds_outputs and local_type == "LVCMOS33":
            assert bank.bank_vccio == "3.3", bel.cell.name
            local_bank = copy.copy(bank)
            local_bank.attrs = dict(bank.attrs, IO_TYPE=local_type)
            io_fixes.append(
                {
                    "port": bel.cell.name,
                    "io_type": local_type,
                    "bank_vccio": bank.bank_vccio,
                }
            )
            return method(self, local_bank, bel)
        return method(self, bank, bel)

    return fixed


for name, sha in {
    "process_OBUF": "4faac4cb1bcf3db6f05f8d0ae9ab046cde1e62a2a4d31a67019a3a2fb404932f",
    "process_IBUF": "77d03f552630f9eaa37e36f358c5d1ebabe76340110820a5d863e95916320f87",
}.items():
    method = getattr(gowin_pack.Device, name)
    assert (
        hashlib.sha256(inspect.getsource(method).encode()).hexdigest() == sha
    ), "Packer I/O handling changed: review the mixed-bank correction"
    setattr(gowin_pack.GW2A_18C, name, preserve_gpio_type(method))
print("Applying source-checked GW2A-18C left-PLL enumeration fix.", flush=True)
gowin_pack.main()
Path("io-port-fixes.json").write_text(json.dumps(io_fixes, indent=2) + "\n")
