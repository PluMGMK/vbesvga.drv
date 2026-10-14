#!/usr/bin/env python3
"""Execute generic completed-text publication and timer ownership paths."""

import argparse
from pathlib import Path
import struct
import unittest

from unicorn import UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import (
    UC_X86_REG_GDTR, UC_X86_REG_GS, UC_X86_REG_EAX, UC_X86_REG_EBX,
    UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI,
    UC_X86_REG_EBP, UC_X86_INS_IN, UC_X86_INS_OUT,
)

from vdd_image import VddImage, read_number, write_number
from generic_copy import GenericCopyFixture


REGISTERS = (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
             UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP)


class GenericCompletion(GenericCopyFixture, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.configure_image(IMAGE)
        cls.active = cls.shared + 16402
        cls.pending = cls.shared + 16406
        completion = IMAGE.function('VDD_DblBuf_Complete', 80)
        cls.running = [instruction for instruction in completion
                       if instruction.mnemonic == 'cmp'][2].operands[0].mem.disp

    def test_periodic_blocked_request_and_one_scheduler(self):
        for depth, running in ((0, 1), (1, 1), (2, 1), (1, 0)):
            with self.subTest(depth=depth, running=running):
                machine, expected = self.configured_machine(b'abcd')
                write_number(machine, self.active, depth)
                write_number(machine, self.running, running, 4)
                copies, schedules = [], []

                def boundary(cpu, address, size, unused):
                    if address == IMAGE.symbols['VDD_CopyBuffers']:
                        copies.append(address)
                    elif address == IMAGE.symbols['VDD_Schedule_SwapBuffers']:
                        schedules.append(address)
                        cpu.emu_stop()

                machine.hook_add(UC_HOOK_CODE, boundary)
                IMAGE.call(machine, 'VDD_SwapBuffers')
                self.assertEqual(len(schedules), 1)
                self.assertEqual(len(copies), int(depth == 0))
                self.assertEqual(read_number(machine, self.pending), int(bool(depth and running)))

    def test_completion_once_without_scheduling_or_host_io(self):
        for pending, depth, running in ((0, 0, 1), (1, 1, 1), (1, 2, 1),
                                        (1, 0, 0), (1, 0, 1)):
            with self.subTest(pending=pending, depth=depth, running=running):
                machine, expected = self.configured_machine(b'abcd')
                write_number(machine, self.pending, pending)
                write_number(machine, self.active, depth)
                write_number(machine, self.running, running, 4)
                write_number(machine, self.shared + 16404, 0xa55a)
                copies = []

                def boundary(cpu, address, size, unused):
                    self.assertNotEqual(address, IMAGE.symbols['VDD_Schedule_SwapBuffers'])
                    if address == IMAGE.symbols['VDD_CopyBuffers']:
                        copies.append(address)

                def output(cpu, port, size, value, unused):
                    self.fail('Generic completion issued host I/O')

                def input(cpu, port, size, unused):
                    self.fail('Generic completion issued host I/O')
                    return 0

                machine.hook_add(UC_HOOK_CODE, boundary)
                machine.hook_add(UC_HOOK_INSN, output, None, 1, 0, UC_X86_INS_OUT)
                machine.hook_add(UC_HOOK_INSN, input, None, 1, 0, UC_X86_INS_IN)
                IMAGE.call(machine, 'VDD_DblBuf_Complete')
                should_copy = bool(pending and not depth and running)
                self.assertEqual(len(copies), int(should_copy))
                self.assertEqual(read_number(machine, self.pending), int(bool(pending and depth)))
                self.assertEqual(read_number(machine, self.shared + 16404), 0xa55a)
                if should_copy:
                    self.assertEqual(bytes(machine.mem_read(0x300000, 4)), expected)
                    IMAGE.call(machine, 'VDD_DblBuf_Complete')
                    self.assertEqual(len(copies), 1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--map', type=Path, required=True)
    args, remaining = parser.parse_known_args()
    IMAGE = VddImage(args.binary, args.map)
    unittest.main(argv=[__file__, *remaining])
