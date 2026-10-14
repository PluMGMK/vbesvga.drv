#!/usr/bin/env python3
"""Execute the assembled text-completion client and its generic VDD peer."""

import argparse
from pathlib import Path
import struct
import unittest

from unicorn import UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import (
    UC_X86_INS_IN, UC_X86_INS_OUT, UC_X86_REG_EAX, UC_X86_REG_EBX,
    UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI,
    UC_X86_REG_EBP, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_FS,
    UC_X86_REG_GS, UC_X86_REG_AX, UC_X86_REG_IP, UC_X86_REG_BP,
    UC_X86_REG_EFLAGS, UC_X86_REG_DX, UC_X86_REG_GDTR,
)

from driver_image import DriverImage
from vdd_image import VddImage, read_number, write_number


REGISTERS = (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
             UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP, UC_X86_REG_DS,
             UC_X86_REG_ES, UC_X86_REG_FS, UC_X86_REG_GS)


class TextCompletion(unittest.TestCase):
    def setUp(self):
        helper = DRIVER.function('dblbuf_complete_pending', 100)
        self.selector = next(instruction for instruction in helper
                             if instruction.mnemonic == 'mov').operands[1].mem.disp & 0xffff
        self.far_call = next(instruction for instruction in helper
                             if instruction.mnemonic == 'lcall')

    def test_completion_client_preserves_entire_state(self):
        for supported, pending in ((False, 0), (False, 1), (True, 0), (True, 1)):
            with self.subTest(supported=supported, pending=pending):
                machine = DRIVER.machine()
                for index, register in enumerate(REGISTERS):
                    machine.reg_write(register, 0x12340000 + index if index < 7
                                      else 0x2000 + index * 0x100)
                machine.reg_write(UC_X86_REG_DS, 0x2000)
                machine.reg_write(UC_X86_REG_EFLAGS, 0xad7)
                write_number(machine, DRIVER.DATA_BASE + self.selector,
                             0x3000 if supported else 0)
                write_number(machine, DRIVER.SHARED_BASE + 16406, pending)
                if not supported:
                    machine.mem_unmap(DRIVER.SHARED_BASE, 0x10000)
                expected = [machine.reg_read(register) for register in REGISTERS]
                expected_flags = machine.reg_read(UC_X86_REG_EFLAGS)
                calls = []

                def callback(cpu, address, size, unused):
                    if address == DRIVER.CODE_BASE + self.far_call.address:
                        self.assertEqual(cpu.reg_read(UC_X86_REG_AX), 3)
                        calls.append(address)
                        # Model an uncooperative protected VDD entry to prove
                        # the client wrapper restores all caller-visible state.
                        for register in REGISTERS:
                            cpu.reg_write(register, 0x5678)
                        cpu.reg_write(UC_X86_REG_EFLAGS, 2)
                        cpu.reg_write(UC_X86_REG_IP,
                                      self.far_call.address + self.far_call.size)

                machine.hook_add(UC_HOOK_CODE, callback)
                DRIVER.call(machine, 'dblbuf_complete_pending')
                self.assertEqual([machine.reg_read(register) for register in REGISTERS],
                                 expected)
                self.assertEqual(machine.reg_read(UC_X86_REG_EFLAGS), expected_flags)
                self.assertEqual(len(calls), int(supported and pending))

    def test_setup_negotiates_generic_completion(self):
        setup = DRIVER.function('setup_double_buf', 500)
        first_lsl = next(index for index, instruction in enumerate(setup)
                         if instruction.mnemonic == 'lsl')
        push_flags = max(index for index in range(first_lsl)
                         if setup[index].mnemonic == 'pushf')
        start = setup[push_flags - 2]
        end = next(instruction for instruction in setup[first_lsl:]
                   if instruction.mnemonic == 'popf')
        instructions = {instruction.address: instruction for instruction in setup}
        for limit in (16401, 16403, 16404, 16405, 16406, 16407):
            with self.subTest(limit=limit):
                machine = DRIVER.machine(DRIVER.symbols['setup_double_buf'][0])
                machine.reg_write(UC_X86_REG_AX, 0x3000)
                write_number(machine, DRIVER.SHARED_BASE + 16404, 0xaaaa)

                def model_lsl(cpu, address, size, unused):
                    instruction = instructions[address - DRIVER.CODE_BASE]
                    if instruction.mnemonic == 'lsl':
                        cpu.reg_write(UC_X86_REG_DX, limit)
                        cpu.reg_write(UC_X86_REG_EFLAGS,
                                      cpu.reg_read(UC_X86_REG_EFLAGS) | 0x40)
                        cpu.reg_write(UC_X86_REG_IP, instruction.address + instruction.size)

                machine.hook_add(UC_HOOK_CODE, model_lsl)
                machine.emu_start(DRIVER.CODE_BASE + start.address,
                                  DRIVER.CODE_BASE + end.address + end.size, count=100)
                self.assertEqual(read_number(machine, DRIVER.DATA_BASE + self.selector),
                                 0x3000 if limit >= 16407 else 0)
                self.assertEqual(read_number(machine, DRIVER.SHARED_BASE + 16404),
                                 0 if limit >= 16405 else 0xaaaa)

    def test_only_text_surviving_quick_clipping_reaches_completion(self):
        segment, wrapper = DRIVER.symbols['complete_text_draw']
        code = DRIVER.segments[segment]
        calls = [offset for offset in range(len(code) - 3)
                 if code[offset] == 0xe8
                 and (offset + 3 + struct.unpack_from('<h', code, offset + 1)[0])
                 & 0xffff == wrapper]
        self.assertEqual(len(calls), 1)
        call = calls[0]
        gate = list(DRIVER.decoder.disasm(code[call - 6:call + 3], call - 6))
        self.assertEqual([instruction.mnemonic for instruction in gate], ['test', 'je', 'call'])
        self.assertEqual(gate[0].operands[1].imm, 2)  # TEXT_VISIBLE
        displacement = gate[0].operands[0].mem.disp
        destination = gate[1].operands[0].imm
        for text_flags in (0, 8, 2, 10):
            machine = DRIVER.machine(segment)
            machine.reg_write(UC_X86_REG_DS, 0x4000)
            machine.reg_write(UC_X86_REG_BP, 0x8000)
            write_number(machine, DRIVER.STACK_BASE + 0x8000 + displacement, text_flags, 1)
            reached = []

            def boundary(cpu, address, size, unused):
                if address == DRIVER.CODE_BASE + call:
                    reached.append(address)
                    cpu.emu_stop()
                elif address == DRIVER.CODE_BASE + destination:
                    cpu.emu_stop()

            machine.hook_add(UC_HOOK_CODE, boundary)
            machine.emu_start(DRIVER.CODE_BASE + gate[0].address, DRIVER.RETURN, count=20)
            self.assertEqual(bool(reached), bool(text_flags & 2))

    def test_text_wrapper_loads_driver_data_segment(self):
        wrapper = DRIVER.function('complete_text_draw', 32)
        cstods = next(instruction for instruction in wrapper
                      if instruction.mnemonic == 'mov').operands[1].mem.disp & 0xffff
        machine = DRIVER.machine()
        write_number(machine, DRIVER.CODE_BASE + cstods, 0x2000)
        write_number(machine, DRIVER.DATA_BASE + self.selector, 0)
        machine.reg_write(UC_X86_REG_DS, 0x4000)
        machine.reg_write(UC_X86_REG_EFLAGS, 0xad7)
        before = [machine.reg_read(register) for register in REGISTERS]
        flags = machine.reg_read(UC_X86_REG_EFLAGS)
        DRIVER.call(machine, 'complete_text_draw')
        self.assertEqual([machine.reg_read(register) for register in REGISTERS], before)
        self.assertEqual(machine.reg_read(UC_X86_REG_EFLAGS), flags)

    def test_nested_driver_to_generic_copy_bridge(self):
        begin = DRIVER.function('dblbuf_begin_draw', 20)
        setter = next(instruction for instruction in begin
                      if instruction.mnemonic == 'call').operands[0].imm
        setter_code = list(DRIVER.decoder.disasm(
            DRIVER.segments[1][setter:setter + 40], setter))
        state_selector = next(instruction for instruction in setter_code
                              if instruction.mnemonic == 'mov'
                              and instruction.op_str.startswith('dx,')).operands[1].mem.disp & 0xffff
        active = next(instruction for instruction in VDD.function('VDD_SwapBuffers', 64)
                      if instruction.mnemonic == 'cmp').operands[0].mem.disp
        copy = VDD.function('VDD_CopyBuffers', 100)
        selectors = [instruction.operands[1].mem.disp for instruction in copy
                     if instruction.mnemonic == 'mov'
                     and instruction.op_str.startswith(('es,', 'fs,', 'gs,'))][:3]
        size_address = next(instruction for instruction in copy
                            if instruction.mnemonic == 'mov'
                            and instruction.op_str.startswith('edx,')).operands[1].mem.disp
        completion = VDD.function('VDD_DblBuf_Complete', 80)
        running = [instruction for instruction in completion
                   if instruction.mnemonic == 'cmp'][2].operands[0].mem.disp
        vdd = VDD.machine()
        vdd.mem_map(0x300000, 0x100000)
        vdd.mem_write(0x1d020, VDD.descriptor(0x300000))
        vdd.reg_write(UC_X86_REG_GDTR, (0, 0x1d000, 39, 0))
        vdd.reg_write(UC_X86_REG_GS, 8)
        for address, value in zip(selectors, (16, 24, 32)):
            write_number(vdd, address, value)
        vdd.mem_write(VDD.BACK_BASE, b'ABCD')
        write_number(vdd, size_address, 4, 4)
        write_number(vdd, running, 1, 4)
        write_number(vdd, active + 4, 1)
        copies = []

        def copy_boundary(cpu, address, size, unused):
            self.assertNotEqual(address, VDD.symbols['VDD_Schedule_SwapBuffers'])
            if address == VDD.symbols['VDD_CopyBuffers']:
                copies.append(address)

        vdd.hook_add(UC_HOOK_CODE, copy_boundary)
        driver = DRIVER.machine()
        write_number(driver, DRIVER.DATA_BASE + state_selector, 0x3000)
        write_number(driver, DRIVER.DATA_BASE + self.selector, 0x3000)
        write_number(driver, DRIVER.SHARED_BASE + 16406, 1)

        def bridge(cpu, address, size, unused):
            if address == DRIVER.CODE_BASE + self.far_call.address:
                write_number(vdd, active, read_number(cpu, DRIVER.SHARED_BASE + 16402))
                VDD.call(vdd, 'VDD_DblBuf_Complete')
                write_number(cpu, DRIVER.SHARED_BASE + 16406, read_number(vdd, active + 4))
                cpu.reg_write(UC_X86_REG_IP, self.far_call.address + self.far_call.size)

        driver.hook_add(UC_HOOK_CODE, bridge)
        for function in ('dblbuf_begin_draw', 'dblbuf_begin_draw', 'dblbuf_end_draw',
                         'dblbuf_complete_pending'):
            DRIVER.call(driver, function)
        self.assertEqual(copies, [])
        self.assertEqual(read_number(vdd, active + 4), 1)
        DRIVER.call(driver, 'dblbuf_end_draw')
        DRIVER.call(driver, 'dblbuf_complete_pending')
        self.assertEqual(len(copies), 1)
        self.assertEqual(read_number(vdd, active + 4), 0)
        self.assertEqual(bytes(vdd.mem_read(0x300000, 4)), b'ABCD')


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
