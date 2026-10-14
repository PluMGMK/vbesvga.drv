#!/usr/bin/env python3
"""Run the assembled VDD service dispatcher, stopping at its VMM boundaries."""

import argparse
from pathlib import Path
import re
import struct
import unittest

from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_EIP, UC_X86_REG_ESP


def load_vdd(binary, map_file):
    """Load the zero-based LE image emitted by the documented DDK build."""
    blob = binary.read_bytes()
    header = struct.unpack_from('<I', blob, 0x3c)[0]
    assert blob[header:header + 2] == b'LE'
    data = struct.unpack_from('<I', blob, header + 128)[0]
    objects = header + struct.unpack_from('<I', blob, header + 64)[0]
    pages = header + struct.unpack_from('<I', blob, header + 72)[0]
    image = bytearray(0x20000)
    for number in range(struct.unpack_from('<I', blob, header + 68)[0]):
        _, base, _, first, count, _ = struct.unpack_from(
            '<6I', blob, objects + number * 24)
        for index in range(count):
            entry = pages + (first - 1 + index) * 4
            page = int.from_bytes(blob[entry:entry + 3], 'big')
            if page:
                chunk = blob[data + (page - 1) * 4096:data + page * 4096]
                start = base + index * 4096
                image[start:start + len(chunk)] = chunk
    symbols = {name: int(offset, 16) for offset, name in re.findall(
        r'0001:([0-9A-Fa-f]{8})\s+(VDD_\w+)', map_file.read_text())}
    return bytes(image), symbols


class ServiceDispatch(unittest.TestCase):
    def test_full_service_number(self):
        image, symbols = load_vdd(ARGS.binary, ARGS.map)
        entry = symbols['VDD_DblBuf_Service']
        # Simulate_Far_Ret is the first six-byte VMM call. Its stack operation
        # is outside this ISA-level test; execute the actual dispatcher after it.
        self.assertEqual(image[entry:entry + 2], b'\xcd\x20')
        decoder = Cs(CS_ARCH_X86, CS_MODE_32)
        decoder.detail = True
        load = next(decoder.disasm(image[entry + 6:entry + 14], entry + 6))
        self.assertEqual(load.mnemonic, 'movzx')
        displacement = load.operands[1].mem.disp
        targets = [symbols[name] for name in (
            'VDD_DblBuf_Setup', 'VDD_DblBuf_Start', 'VDD_DblBuf_Stop',
            'VDD_DblBuf_Complete')]

        for service in (0, 1, 2, 3, 4, 0xff, 0x100, 0x101, 0x102, 0x103, 0x104, 0xffff):
            with self.subTest(service=hex(service)):
                machine = Uc(UC_ARCH_X86, UC_MODE_32)
                machine.mem_map(0, 0x20000)
                machine.mem_write(0, image)
                machine.reg_write(UC_X86_REG_EBP, 0x18000)
                machine.mem_write(0x18000 + displacement, struct.pack('<H', service))
                machine.reg_write(UC_X86_REG_ESP, 0x1c000)
                machine.mem_write(0x1c000, struct.pack('<I', 0x1ff00))
                reached, validations = [], []

                def boundary(cpu, address, size, unused):
                    if address in targets:
                        reached.append(address)
                        cpu.emu_stop()
                    elif bytes(cpu.mem_read(address, 2)) == b'\xcd\x20':
                        validations.append(address)
                        # Model successful Validate_VM_Handle, then run the
                        # real computed table jump rather than a Python model.
                        cpu.reg_write(UC_X86_REG_EIP, address + 6)

                machine.hook_add(UC_HOOK_CODE, boundary)
                machine.emu_start(entry + 6, 0x1ff00, count=30)
                self.assertEqual(reached, [targets[service]] if service < 4 else [])
                self.assertEqual(len(validations), int(service < 4))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True, help='built VDDVBE.386')
    parser.add_argument('--map', type=Path, required=True, help='matching VDDVGA.MAP')
    ARGS, remaining = parser.parse_known_args()
    unittest.main(argv=[__file__, *remaining])
