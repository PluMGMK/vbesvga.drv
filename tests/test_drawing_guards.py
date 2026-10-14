#!/usr/bin/env python3
"""Run nested GDI, DCI and periodic-publication guards in assembled binaries."""

import argparse
from pathlib import Path
import struct
import unittest

from unicorn import UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.x86_const import UC_X86_REG_AX, UC_X86_REG_DX, UC_X86_REG_IP, UC_X86_REG_EFLAGS

from driver_image import DriverImage
from vdd_image import VddImage, read_number, write_number


class DrawingGuards(unittest.TestCase):
    def setUp(self):
        begin = DRIVER.function('dblbuf_begin_draw', 20)
        self.depth = next(instruction for instruction in begin
                          if instruction.mnemonic == 'mov').operands[1].mem.disp
        setter = next(instruction for instruction in begin
                      if instruction.mnemonic == 'call').operands[0].imm
        instructions = list(DRIVER.decoder.disasm(
            DRIVER.segments[1][setter:setter + 40], setter))
        self.selector = next(instruction for instruction in instructions
                             if instruction.mnemonic == 'mov'
                             and instruction.op_str.startswith('dx,')).operands[1].mem.disp & 0xffff
        # Eight metadata WORDs, 32x32 cursor AND/XOR bytes, and cursor flags.
        self.shared_depth = DRIVER.SHARED_BASE + 16402

    def test_setup_negotiates_actual_selector_limit(self):
        instructions = DRIVER.function('setup_double_buf', 500)
        by_address = {instruction.address: instruction for instruction in instructions}
        first_lsl = next(index for index, instruction in enumerate(instructions)
                         if instruction.mnemonic == 'lsl')
        save_flags = max(index for index in range(first_lsl)
                         if instructions[index].mnemonic == 'pushf')
        start = instructions[save_flags - 2]
        self.assertEqual(start.mnemonic, 'test')
        self.assertEqual(start.op_str, 'ax, ax')
        restore_flags = next(instruction for instruction in instructions[first_lsl:]
                             if instruction.mnemonic == 'popf')
        for limit, valid in ((16401, True), (16402, True), (16403, True),
                             (16405, True), (16407, True), (16407, False)):
            with self.subTest(limit=limit, selector_valid=valid):
                machine = DRIVER.machine(DRIVER.symbols['setup_double_buf'][0])
                machine.reg_write(UC_X86_REG_AX, 0x3000)
                writes = []

                def model_lsl(cpu, address, size, unused):
                    instruction = by_address[address - DRIVER.CODE_BASE]
                    if instruction.mnemonic == 'lsl':
                        # LDT lookup belongs to the OS, not the drawing driver.
                        # Supply its limit/ZF, then execute the real comparisons,
                        # selector stores and branches following that boundary.
                        cpu.reg_write(UC_X86_REG_DX, limit)
                        flags = cpu.reg_read(UC_X86_REG_EFLAGS) & ~0x40
                        cpu.reg_write(UC_X86_REG_EFLAGS, flags | (0x40 if valid else 0))
                        cpu.reg_write(UC_X86_REG_IP, instruction.address + instruction.size)

                def check_shared_write(cpu, access, address, size, value, unused):
                    if DRIVER.SHARED_BASE <= address < DRIVER.SHARED_BASE + 0x10000:
                        writes.append((address - DRIVER.SHARED_BASE, size))
                        self.assertLessEqual(address + size - 1 - DRIVER.SHARED_BASE, limit)

                machine.hook_add(UC_HOOK_CODE, model_lsl)
                machine.hook_add(UC_HOOK_MEM_WRITE, check_shared_write)
                machine.emu_start(DRIVER.CODE_BASE + start.address,
                                  DRIVER.CODE_BASE + restore_flags.address + restore_flags.size,
                                  count=100)
                self.assertEqual(read_number(machine, DRIVER.DATA_BASE + self.selector),
                                 0x3000 if valid and limit >= 16403 else 0)
                # TEST AX initially cleared ZF; descriptor probing must preserve
                # that setup success/fallback decision through its PUSHF/POPF.
                self.assertFalse(machine.reg_read(UC_X86_REG_EFLAGS) & 0x40)
                if limit < 16403 or not valid:
                    self.assertEqual(writes, [])

    def test_nested_drawing_and_older_vdd(self):
        for shared in (False, True):
            with self.subTest(shared_selector=shared):
                machine = DRIVER.machine()
                write_number(machine, DRIVER.DATA_BASE + self.selector,
                             0x3000 if shared else 0)
                if not shared:
                    machine.mem_unmap(DRIVER.SHARED_BASE, 0x10000)
                for function, expected in (
                        ('dblbuf_begin_draw', 1), ('dblbuf_begin_draw', 2),
                        ('dblbuf_end_draw', 1), ('dblbuf_end_draw', 0),
                        ('dblbuf_end_draw', 0)):
                    machine.reg_write(UC_X86_REG_AX, 0x5a5a)
                    DRIVER.call(machine, function)
                    self.assertEqual(machine.reg_read(UC_X86_REG_AX), 0x5a5a)
                    self.assertEqual(read_number(machine, DRIVER.DATA_BASE + self.depth),
                                     expected)
                    if shared:
                        self.assertEqual(read_number(machine, self.shared_depth), expected)

    def test_standard_mode_swap_skips_incomplete_primitive(self):
        # The periodic Standard Mode callback is a private symbol. Locate its
        # unique assembled guard, using the depth address resolved above.
        prefix = b'\x83\x3e' + struct.pack('<H', self.depth) + b'\x00\x74\x01\xc3'
        code = DRIVER.segments[1]
        self.assertEqual(code.count(prefix), 1)
        offset = code.index(prefix)
        instructions = list(DRIVER.decoder.disasm(code[offset:offset + 16], offset))
        body = next(instruction for instruction in instructions
                    if instruction.mnemonic == 'pushal')
        for depth in (0, 1, 2):
            machine = DRIVER.machine()
            write_number(machine, DRIVER.DATA_BASE + self.depth, depth)
            entered = []

            def boundary(cpu, address, size, unused):
                if address == DRIVER.CODE_BASE + body.address:
                    entered.append(address)
                    cpu.emu_stop()

            machine.hook_add(UC_HOOK_CODE, boundary)
            DRIVER.prepare_call(machine)
            machine.emu_start(DRIVER.CODE_BASE + offset, DRIVER.RETURN, count=30)
            self.assertEqual(bool(entered), depth == 0)

    def test_dci_cursor_exclusion_does_not_own_gdi_guard(self):
        machine = DRIVER.machine()
        write_number(machine, DRIVER.DATA_BASE + self.selector, 0x3000)
        # Both cursor-only helpers share their implementation with GDI entry
        # points, and are selected by the real DCI wrapper near calls.
        for wrapper in ('exclude_rect', 'unexclude_rect'):
            instructions = DRIVER.function(wrapper, 80)
            helper = next(instruction for instruction in instructions
                          if instruction.mnemonic == 'call').operands[0].imm
            helper_instructions = list(DRIVER.decoder.disasm(
                DRIVER.segments[1][helper:helper + 40], helper))
            cstods = next(instruction for instruction in helper_instructions
                          if instruction.mnemonic == 'mov'
                          and instruction.op_str.startswith('ax,')).operands[1].mem.disp
            write_number(machine, DRIVER.CODE_BASE + cstods, 0x2000)
            DRIVER.prepare_call(machine)
            machine.emu_start(DRIVER.CODE_BASE + helper, DRIVER.RETURN, count=1000)
            self.assertEqual(read_number(machine, DRIVER.DATA_BASE + self.depth), 0)
            self.assertEqual(read_number(machine, self.shared_depth), 0)

    def test_enhanced_mode_busy_guard_reaches_existing_scheduler(self):
        instructions = VDD.function('VDD_SwapBuffers', 60)
        comparison = next(instruction for instruction in instructions
                          if instruction.mnemonic == 'cmp')
        shared_depth = comparison.operands[0].mem.disp
        for depth in (1, 2):
            machine = VDD.machine()
            write_number(machine, shared_depth, depth)
            scheduled = []

            def boundary(cpu, address, size, unused):
                if address == VDD.symbols['VDD_Schedule_SwapBuffers']:
                    scheduled.append(address)
                    cpu.emu_stop()

            machine.hook_add(UC_HOOK_CODE, boundary)
            VDD.call(machine, 'VDD_SwapBuffers')
            self.assertEqual(len(scheduled), 1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--driver', type=Path, required=True)
    parser.add_argument('--driver-map', type=Path, required=True)
    parser.add_argument('--vdd', type=Path, required=True)
    parser.add_argument('--vdd-map', type=Path, required=True)
    args, remaining = parser.parse_known_args()
    DRIVER = DriverImage(args.driver, args.driver_map)
    VDD = VddImage(args.vdd, args.vdd_map)
    unittest.main(argv=[__file__, *remaining])
