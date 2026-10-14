#!/usr/bin/env python3
"""Execute the factored generic copier, including cursor and byte tails."""

import argparse
from pathlib import Path
import unittest
from unicorn.x86_const import (
    UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
    UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP,
)
from vdd_image import VddImage
from generic_copy import GenericCopyFixture

REGISTERS = (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
             UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP)


class CopyBuffers(GenericCopyFixture, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.configure_image(IMAGE)

    def test_factored_copy_pixels_and_registers(self):
        for length in (0, 1, 2, 3, 4, 5, 31, 32, 64, 1280 * 720):
            for cursor in (False, True):
                for pixel_bytes in ((1, 2, 3, 4) if cursor else (1,)):
                    if cursor and length < 8:
                        continue
                    with self.subTest(length=length, cursor=cursor, pixel_bytes=pixel_bytes):
                        data = bytes((index * 73 + 51) & 255 for index in range(length))
                        machine, expected = self.configured_machine(data, cursor, pixel_bytes)
                        for index, register in enumerate(REGISTERS):
                            machine.reg_write(register, 0xabc000 + index)
                        registers = [machine.reg_read(register) for register in REGISTERS]
                        self.image.call(machine, 'VDD_CopyBuffers')
                        self.assertEqual(bytes(machine.mem_read(self.image.FRONT_BASE, length)), expected)
                        self.assertEqual(bytes(machine.mem_read(0x300000, length)), expected)
                        self.assertEqual([machine.reg_read(register) for register in REGISTERS], registers)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--map', type=Path, required=True)
    args, remaining = parser.parse_known_args()
    IMAGE = VddImage(args.binary, args.map)
    unittest.main(argv=[__file__, *remaining])
