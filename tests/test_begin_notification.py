#!/usr/bin/env python3
"""Execute the negotiated outer-draw notification and actual VDD peer."""

import argparse
from pathlib import Path
import unittest

from unicorn import UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import (
    UC_X86_INS_IN, UC_X86_INS_OUT, UC_X86_REG_EAX, UC_X86_REG_EBX,
    UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI,
    UC_X86_REG_EBP, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_FS,
    UC_X86_REG_GS, UC_X86_REG_AX, UC_X86_REG_DX, UC_X86_REG_IP,
    UC_X86_REG_EFLAGS,
)

from driver_image import DriverImage
from vdd_image import VddImage, read_number, write_number


REGISTERS = (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
             UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP, UC_X86_REG_DS,
             UC_X86_REG_ES, UC_X86_REG_FS, UC_X86_REG_GS)


class BeginNotification(unittest.TestCase):
    def setUp(self):
        helper = DRIVER.function('dblbuf_revoke_timer', 100)
        self.selector = next(instruction for instruction in helper
                             if instruction.mnemonic == 'mov').operands[1].mem.disp & 0xffff
        self.far_call = next(instruction for instruction in helper
                             if instruction.mnemonic == 'lcall')

    def test_old_vdd_absent_pending_and_full_client_state(self):
        for supported, pending in ((False, 0), (False, 1), (True, 0), (True, 1), (True, 2)):
            with self.subTest(supported=supported, timer_owned=pending):
                machine = DRIVER.machine()
                for index, register in enumerate(REGISTERS):
                    machine.reg_write(register, 0x12340000 + index if index < 7
                                      else 0x2000 + index * 0x100)
                machine.reg_write(UC_X86_REG_DS, 0x2000)
                machine.reg_write(UC_X86_REG_EFLAGS, 0xad7)
                write_number(machine, DRIVER.DATA_BASE + self.selector,
                             0x3000 if supported else 0)
                write_number(machine, DRIVER.SHARED_BASE + 16408, pending)
                if not supported:
                    machine.mem_unmap(DRIVER.SHARED_BASE, 0x10000)
                expected = [machine.reg_read(register) for register in REGISTERS]
                flags = machine.reg_read(UC_X86_REG_EFLAGS)
                calls = []

                def callback(cpu, address, size, unused):
                    if address == DRIVER.CODE_BASE + self.far_call.address:
                        self.assertEqual(cpu.reg_read(UC_X86_REG_AX), 4)
                        calls.append(address)
                        for register in REGISTERS:
                            cpu.reg_write(register, 0x5678)
                        cpu.reg_write(UC_X86_REG_EFLAGS, 2)
                        cpu.reg_write(UC_X86_REG_IP,
                                      self.far_call.address + self.far_call.size)

                machine.hook_add(UC_HOOK_CODE, callback)
                DRIVER.call(machine, 'dblbuf_revoke_timer')
                self.assertEqual([machine.reg_read(register) for register in REGISTERS], expected)
                self.assertEqual(machine.reg_read(UC_X86_REG_EFLAGS), flags)
                self.assertEqual(len(calls), int(bool(supported and pending)))

    def test_setup_negotiates_opt_in_and_begin_independently(self):
        setup = DRIVER.function('setup_double_buf', 500)
        first_lsl = next(index for index, instruction in enumerate(setup)
                         if instruction.mnemonic == 'lsl')
        push_flags = max(index for index in range(first_lsl)
                         if setup[index].mnemonic == 'pushf')
        start = setup[push_flags - 2]
        end = next(instruction for instruction in setup[first_lsl:]
                   if instruction.mnemonic == 'popf')
        instructions = {instruction.address: instruction for instruction in setup}
        option = next(instruction for instruction in setup[first_lsl:]
                      if instruction.mnemonic == 'mov'
                      and instruction.op_str.startswith('bx, word ptr [')).operands[1].mem.disp & 0xffff
        for limit in (16401, 16403, 16405, 16407, 16408, 16409):
            for enabled in (0, 1):
                with self.subTest(limit=limit, opted_in=enabled):
                    machine = DRIVER.machine(DRIVER.symbols['setup_double_buf'][0])
                    machine.reg_write(UC_X86_REG_AX, 0x3000)
                    write_number(machine, DRIVER.DATA_BASE + option, enabled)
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
                                     0x3000 if limit >= 16409 else 0)
                    self.assertEqual(read_number(machine, DRIVER.SHARED_BASE + 16404),
                                     enabled if limit >= 16405 else 0xaaaa)

    def test_outer_begin_nested_text_and_completed_snapshot_bridge(self):
        begin = DRIVER.function('dblbuf_begin_draw', 40)
        setter = next(instruction for instruction in begin
                      if instruction.mnemonic == 'call').operands[0].imm
        setter_code = list(DRIVER.decoder.disasm(
            DRIVER.segments[1][setter:setter + 40], setter))
        state_selector = next(instruction for instruction in setter_code
                              if instruction.mnemonic == 'mov'
                              and instruction.op_str.startswith('dx,')).operands[1].mem.disp & 0xffff
        completion = DRIVER.function('dblbuf_complete_pending', 100)
        complete_selector = next(instruction for instruction in completion
                                 if instruction.mnemonic == 'mov').operands[1].mem.disp & 0xffff
        complete_call = next(instruction for instruction in completion
                             if instruction.mnemonic == 'lcall')
        active = next(instruction for instruction in VDD.function('VDD_SwapBuffers', 80)
                      if instruction.mnemonic == 'cmp').operands[0].mem.disp
        client = VDD.function('VDD_HostPublish', 160)
        comparisons = [instruction for instruction in client if instruction.mnemonic == 'cmp']
        opted_in, pixel_bytes = [instruction.operands[0].mem.disp
                                for instruction in comparisons[:2]]
        used = next(instruction for instruction in client
                    if instruction.mnemonic == 'mov'
                    and instruction.op_str.startswith('dword ptr [')).operands[0].mem.disp
        complete = VDD.function('VDD_DblBuf_Complete', 80)
        running = [instruction for instruction in complete
                   if instruction.mnemonic == 'cmp'][2].operands[0].mem.disp
        vdd = VDD.machine()
        for address, value, size in ((opted_in, 1, 2), (pixel_bytes, 1, 2),
                                     (used, 1, 4), (running, 1, 4), (active + 6, 1, 2)):
            write_number(vdd, address, value, size)
        events, index = [], [0]

        def output(cpu, port, size, value, unused):
            events.append((port, size, value))
            if port == 0x28:
                index[0] = value

        def input(cpu, port, size, unused):
            return 0 if port == 0x2a else (0x57333101 if index[0] == 0x684582 else 0)

        vdd.hook_add(UC_HOOK_INSN, output, None, 1, 0, UC_X86_INS_OUT)
        vdd.hook_add(UC_HOOK_INSN, input, None, 1, 0, UC_X86_INS_IN)
        driver = DRIVER.machine()
        for selector in (state_selector, complete_selector, self.selector):
            write_number(driver, DRIVER.DATA_BASE + selector, 0x3000)
        write_number(driver, DRIVER.SHARED_BASE + 16408, 1)
        calls = []

        def bridge(cpu, address, size, unused):
            if address in (DRIVER.CODE_BASE + self.far_call.address,
                           DRIVER.CODE_BASE + complete_call.address):
                service = cpu.reg_read(UC_X86_REG_AX)
                calls.append(service)
                write_number(vdd, active, read_number(cpu, DRIVER.SHARED_BASE + 16402))
                VDD.call(vdd, 'VDD_DblBuf_BeginDraw' if service == 4 else 'VDD_DblBuf_Complete')
                write_number(cpu, DRIVER.SHARED_BASE + 16406, read_number(vdd, active + 4))
                write_number(cpu, DRIVER.SHARED_BASE + 16408, read_number(vdd, active + 6))
                instruction = self.far_call if service == 4 else complete_call
                cpu.reg_write(UC_X86_REG_IP, instruction.address + instruction.size)

        driver.hook_add(UC_HOOK_CODE, bridge)
        DRIVER.call(driver, 'dblbuf_begin_draw')
        self.assertEqual(calls, [4])
        self.assertEqual(events.count((0x28, 4, 0x684584)), 1)
        DRIVER.call(driver, 'dblbuf_begin_draw')
        DRIVER.call(driver, 'dblbuf_end_draw')
        DRIVER.call(driver, 'dblbuf_complete_pending')
        self.assertEqual(calls, [4, 3])
        self.assertEqual(events.count((0x28, 4, 0x684583)), 0)
        DRIVER.call(driver, 'dblbuf_end_draw')
        DRIVER.call(driver, 'dblbuf_complete_pending')
        self.assertEqual(events.count((0x28, 4, 0x684583)), 1)
        DRIVER.call(driver, 'dblbuf_begin_draw')
        self.assertEqual(calls, [4, 3, 3, 4], 'next begin consumes completed ownership')
        self.assertEqual(events.count((0x28, 4, 0x684584)), 1,
                         'completed snapshot survives the next begin')


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
