#!/usr/bin/env python3
"""Run the assembled host transport, fallback and completion-request paths."""

import argparse
from pathlib import Path
import struct
import unittest

from unicorn import UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import (
    UC_X86_INS_IN, UC_X86_INS_OUT, UC_X86_REG_EAX, UC_X86_REG_EBX,
    UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI,
    UC_X86_REG_EBP, UC_X86_REG_EFLAGS,
)

from vdd_image import VddImage, read_number, write_number
from generic_copy import GenericCopyFixture


GENERAL_REGISTERS = (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX,
                     UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI,
                     UC_X86_REG_EBP)


class IntegrationDevice:
    """Model only the existing indexed I/O transport's documented responses."""

    def __init__(self, machine, capability=0x57333101, status=0, push_failure=False):
        self.events = []
        self.index = 0
        self.capability = capability
        self.status = status
        self.push_failure = push_failure
        machine.hook_add(UC_HOOK_INSN, self.output, None, 1, 0, UC_X86_INS_OUT)
        machine.hook_add(UC_HOOK_INSN, self.input, None, 1, 0, UC_X86_INS_IN)

    def output(self, machine, port, size, value, unused):
        self.events.append(('out', port, size, value))
        if port == 0x28:
            self.index = value

    def input(self, machine, port, size, unused):
        self.events.append(('in', port, size))
        if port == 0x2a:
            return 2 if self.push_failure else 0
        if port == 0x29:
            return self.capability if self.index == 0x684582 else self.status
        raise AssertionError('Unexpected I/O port: ' + hex(port))

    def submissions(self):
        return self.events.count(('out', 0x28, 4, 0x684583))


class HostPublication(GenericCopyFixture, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.configure_image(IMAGE)
        client = IMAGE.function('VDD_HostPublish', 160)
        comparisons = [instruction for instruction in client
                       if instruction.mnemonic == 'cmp']
        cls.opt_in = comparisons[0].operands[0].mem.disp
        cls.pixel_bytes = comparisons[1].operands[0].mem.disp
        cls.used = next(instruction for instruction in client
                        if instruction.mnemonic == 'mov'
                        and instruction.op_str.startswith('dword ptr [')).operands[0].mem.disp
        swap = IMAGE.function('VDD_SwapBuffers', 64)
        cls.active = next(instruction for instruction in swap
                          if instruction.mnemonic == 'cmp').operands[0].mem.disp
        cls.shared = cls.active - 16402
        cls.pending = cls.shared + 16406
        completion = IMAGE.function('VDD_DblBuf_Complete', 80)
        cls.running = [instruction for instruction in completion
                       if instruction.mnemonic == 'cmp'][2].operands[0].mem.disp
        cls.timer_pending = cls.shared + 16408
        invalidate = IMAGE.function('VDD_InvalidateFront', 256)
        cls.front = next(instruction for instruction in invalidate
                         if instruction.mnemonic == 'mov'
                         and instruction.op_str.startswith('es,')).operands[1].mem.disp
        cls.back = next(instruction for instruction in invalidate
                        if instruction.mnemonic == 'mov'
                        and instruction.op_str.startswith('fs,')).operands[1].mem.disp
        cls.size = next(instruction for instruction in invalidate
                        if instruction.mnemonic == 'mov'
                        and instruction.op_str.startswith('ecx,')).operands[1].mem.disp
        cls.stride = next(instruction for instruction in invalidate
                          if instruction.mnemonic == 'movzx'
                          and instruction.op_str.startswith('eax, word ptr [')).operands[1].mem.disp

    def host_machine(self, opted_in=1, used=1, running=1):
        machine, unused = GenericCopyFixture.configured_machine(self, b"ABCD")
        write_number(machine, self.opt_in, opted_in)
        write_number(machine, self.pixel_bytes, 1)
        write_number(machine, self.used, used, 4)
        write_number(machine, self.running, running, 4)
        return machine

    def call_preserving_registers(self, machine, name):
        for index, register in enumerate(GENERAL_REGISTERS):
            machine.reg_write(register, 0xabc000 + index)
        expected = [machine.reg_read(register) for register in GENERAL_REGISTERS]
        IMAGE.call(machine, name)
        self.assertEqual([machine.reg_read(register) for register in GENERAL_REGISTERS],
                         expected)

    def test_negotiation_and_transport_state(self):
        cases = (
            (0, 1, 0x57333101, 0, False),
            (1, 2, 0x57333101, 0, False),
            (1, 1, 0xaabbccdd, 0, False),
            (1, 1, 0x57333101, 0, True),
            (1, 1, 0x57333101, 2, False),
            (1, 1, 0x57333101, 0, False),
        )
        for opt_in, pixel_bytes, capability, status, push_failure in cases:
            with self.subTest(opt_in=opt_in, pixel_bytes=pixel_bytes,
                              capability=hex(capability), status=status,
                              push_failure=push_failure):
                machine = self.host_machine(opted_in=opt_in, used=0)
                write_number(machine, self.pixel_bytes, pixel_bytes)
                device = IntegrationDevice(machine, capability, status, push_failure)
                self.call_preserving_registers(machine, 'VDD_HostPublish')
                accepted = bool(opt_in and pixel_bytes == 1
                                and capability == 0x57333101 and status == 0
                                and not push_failure)
                self.assertEqual(bool(machine.reg_read(UC_X86_REG_EFLAGS) & 1), accepted)
                self.assertEqual(read_number(machine, self.used, 4), int(accepted))
                pops = device.events.count(('out', 0x2a, 1, 0x21))
                self.assertEqual(pops, int(bool(opt_in and pixel_bytes == 1
                                               and not push_failure)))
                if not opt_in or pixel_bytes != 1:
                    self.assertEqual(device.events, [])
                if push_failure:
                    self.assertEqual(len(device.events), 2)
                if accepted:
                    self.assertEqual(device.submissions(), 1)
                    device.events.clear()
                    self.call_preserving_registers(machine, 'VDD_HostCancel')
                    self.assertIn(('out', 0x28, 4, 0x684584), device.events)
                    self.assertIn(('out', 0x29, 4, 0), device.events)

    def test_completion_is_deferred_or_consumed_once(self):
        for pending, active, running, status in (
                (0, 0, 1, 0), (1, 1, 1, 0), (1, 2, 1, 0),
                (1, 0, 0, 0), (1, 0, 1, 0), (1, 0, 1, 2)):
            with self.subTest(pending=pending, active=active, running=running, status=status):
                machine = self.host_machine(running=running)
                write_number(machine, self.pending, pending)
                write_number(machine, self.active, active)
                device = IntegrationDevice(machine, status=status)
                self.call_preserving_registers(machine, 'VDD_DblBuf_Complete')
                attempted = bool(pending and not active and running)
                self.assertEqual(device.submissions(), int(attempted))
                self.assertEqual(read_number(machine, self.pending),
                                 int(bool(pending and active)))
                if attempted:
                    device.events.clear()
                    IMAGE.call(machine, 'VDD_DblBuf_Complete')
                    self.assertEqual(device.events, [])

    def test_blocked_timer_and_stop_boundaries(self):
        machine = self.host_machine()
        write_number(machine, self.active, 1)
        scheduled = []

        def scheduled_boundary(cpu, address, size, unused):
            if address == IMAGE.symbols['VDD_Schedule_SwapBuffers']:
                scheduled.append(address)
                cpu.emu_stop()

        machine.hook_add(UC_HOOK_CODE, scheduled_boundary)
        IMAGE.call(machine, 'VDD_SwapBuffers')
        self.assertEqual(len(scheduled), 1)
        self.assertEqual(read_number(machine, self.pending), 1)

        def stop_boundary(cpu, address, size, unused):
            if address == IMAGE.symbols['VDD_HostCancel']:
                cpu.emu_stop()

        machine.hook_add(UC_HOOK_CODE, stop_boundary)
        IMAGE.call(machine, 'VDD_DblBuf_Stop')
        self.assertEqual(read_number(machine, self.pending), 0)

    def test_front_cache_resynchronization(self):
        for length in (0, 1, 2, 3, 4, 5, 31, 32, 1280 * 720):
            for cursor in (False, True):
                if cursor and length < 32:
                    continue
                with self.subTest(length=length, cursor=cursor):
                    machine = IMAGE.machine()
                    back = bytes((index * 73 + 51) & 255 for index in range(max(length, 32)))
                    machine.mem_write(IMAGE.BACK_BASE, back)
                    write_number(machine, self.front, 16)
                    write_number(machine, self.back, 24)
                    write_number(machine, self.size, length, 4)
                    expected = bytearray(value ^ 255 for value in back[:length])
                    if cursor:
                        write_number(machine, self.stride, 8)
                        # Two pixels from the lower right of the cursor data:
                        # clipped/inverting first pixel and opaque second pixel.
                        machine.mem_write(self.shared + 4,
                                          struct.pack('<HHHHI', 2, 1, 30, 31, 30))
                        write_number(machine, self.shared + 16400, 4)
                        machine.mem_write(self.shared + 16 + (31 * 32 + 30) * 2,
                                          b'\xff\xff\x00\x42')
                        expected[30] = back[30]
                        expected[31] = 0x42 ^ 255
                    self.call_preserving_registers(machine, 'VDD_InvalidateFront')
                    self.assertEqual(bytes(machine.mem_read(IMAGE.FRONT_BASE, length)),
                                     bytes(expected))

    def test_only_outer_begin_revokes_timer_owned_snapshot(self):
        for owned, depth, opted_in, used, running in (
                (0, 1, 1, 1, 1), (1, 0, 1, 1, 1), (1, 2, 1, 1, 1),
                (1, 1, 0, 1, 1), (1, 1, 1, 0, 1), (1, 1, 1, 1, 0),
                (1, 1, 1, 1, 1), (2, 0, 1, 1, 1), (2, 2, 1, 1, 1),
                (2, 1, 0, 1, 1), (2, 1, 1, 0, 1), (2, 1, 1, 1, 0),
                (2, 1, 1, 1, 1)):
            with self.subTest(owned=owned, depth=depth, opted_in=opted_in,
                              used=used, running=running):
                machine = self.host_machine(opted_in, used, running)
                write_number(machine, self.timer_pending, owned)
                write_number(machine, self.active, depth)
                device = IntegrationDevice(machine)
                self.call_preserving_registers(machine, 'VDD_DblBuf_BeginDraw')
                outer_begin = bool(depth == 1 and opted_in and used and running)
                cancelled = owned == 1 and outer_begin
                self.assertEqual(('out', 0x28, 4, 0x684584) in device.events, cancelled)
                self.assertEqual(device.submissions(), 0)
                self.assertEqual(read_number(machine, self.timer_pending),
                                 0 if outer_begin else owned)
                self.assertEqual(read_number(machine, self.pending), int(cancelled))
                self.assertEqual(read_number(machine, self.used, 4), used)

    def test_timer_and_text_snapshot_ownership(self):
        machine = self.host_machine()
        device = IntegrationDevice(machine)

        def scheduler_boundary(cpu, address, size, unused):
            if address == IMAGE.symbols['VDD_Schedule_SwapBuffers']:
                cpu.emu_stop()

        hook = machine.hook_add(UC_HOOK_CODE, scheduler_boundary)
        IMAGE.call(machine, 'VDD_SwapBuffers')
        self.assertEqual(device.submissions(), 1)
        self.assertEqual(read_number(machine, self.timer_pending), 1)
        machine.hook_del(hook)
        write_number(machine, self.active, 1)
        IMAGE.call(machine, 'VDD_DblBuf_BeginDraw')
        self.assertEqual(read_number(machine, self.timer_pending), 0)
        self.assertEqual(read_number(machine, self.pending), 1)
        write_number(machine, self.active, 0)
        IMAGE.call(machine, 'VDD_DblBuf_Complete')
        self.assertEqual(device.submissions(), 2)
        self.assertEqual(read_number(machine, self.timer_pending), 2)
        device.events.clear()
        write_number(machine, self.active, 1)
        IMAGE.call(machine, 'VDD_DblBuf_BeginDraw')
        self.assertEqual(device.events, [], 'completed-text snapshot survives next begin')
        # The first begin consumes completion ownership. A subsequent periodic
        # snapshot belongs to the new drawing cycle and remains revocable.
        write_number(machine, self.active, 0)
        hook = machine.hook_add(UC_HOOK_CODE, scheduler_boundary)
        IMAGE.call(machine, 'VDD_SwapBuffers')
        machine.hook_del(hook)
        self.assertEqual(device.submissions(), 1)
        self.assertEqual(read_number(machine, self.timer_pending), 1)
        write_number(machine, self.active, 1)
        IMAGE.call(machine, 'VDD_DblBuf_BeginDraw')
        self.assertEqual(read_number(machine, self.timer_pending), 0)
        self.assertEqual(read_number(machine, self.pending), 1)
        write_number(machine, self.active, 0)
        IMAGE.call(machine, 'VDD_DblBuf_Complete')
        self.assertEqual(device.submissions(), 2)
        self.assertEqual(read_number(machine, self.timer_pending), 2)

    def test_timer_refresh_does_not_revoke_completed_text(self):
        machine = self.host_machine()
        device = IntegrationDevice(machine)
        write_number(machine, self.pending, 1)
        IMAGE.call(machine, 'VDD_DblBuf_Complete')

        def scheduler_boundary(cpu, address, size, unused):
            if address == IMAGE.symbols['VDD_Schedule_SwapBuffers']:
                cpu.emu_stop()

        # Before presentation, periodic refreshes contain the same completed
        # pixels. They must not make that completed position revocable again.
        for unused in range(3):
            hook = machine.hook_add(UC_HOOK_CODE, scheduler_boundary)
            IMAGE.call(machine, 'VDD_SwapBuffers')
            machine.hook_del(hook)
        self.assertEqual(device.submissions(), 4)
        device.events.clear()
        write_number(machine, self.active, 1)
        self.call_preserving_registers(machine, 'VDD_DblBuf_BeginDraw')
        self.assertEqual(device.events, [], 'timer refresh must preserve completed text')
        self.assertEqual(read_number(machine, self.timer_pending), 0)
        self.assertEqual(read_number(machine, self.pending), 0)

        # After that first begin, a fresh timer snapshot is revocable normally.
        write_number(machine, self.active, 0)
        hook = machine.hook_add(UC_HOOK_CODE, scheduler_boundary)
        IMAGE.call(machine, 'VDD_SwapBuffers')
        machine.hook_del(hook)
        self.assertEqual(read_number(machine, self.timer_pending), 1)
        device.events.clear()
        write_number(machine, self.active, 1)
        self.call_preserving_registers(machine, 'VDD_DblBuf_BeginDraw')
        self.assertIn(('out', 0x28, 4, 0x684584), device.events)
        self.assertEqual(read_number(machine, self.pending), 1)

    def test_failed_cancellation_retains_ownership_until_replacement(self):
        for push_failure, status in ((True, 0), (False, 2), (False, 0)):
            with self.subTest(push_failure=push_failure, status=status):
                machine = self.host_machine()
                write_number(machine, self.timer_pending, 1)
                write_number(machine, self.active, 1)
                device = IntegrationDevice(machine, status=status, push_failure=push_failure)
                IMAGE.call(machine, 'VDD_DblBuf_BeginDraw')
                failed = push_failure or status != 0
                self.assertEqual(read_number(machine, self.timer_pending), int(failed))
                self.assertEqual(read_number(machine, self.pending), 1)
                self.assertEqual(device.events.count(('out', 0x2a, 1, 0x21)),
                                 int(not push_failure))
                # A complete-frame replacement is a bounded normal recovery
                # path even when the earlier cancellation could not complete.
                device.push_failure = False
                device.status = 0
                write_number(machine, self.active, 0)
                IMAGE.call(machine, 'VDD_DblBuf_Complete')
                self.assertEqual(read_number(machine, self.timer_pending), 2)
                self.assertEqual(read_number(machine, self.pending), 0)
                self.assertEqual(device.submissions(), 1)

    def test_unresolved_fallback_rechecks_front_after_late_host_commit(self):
        machine = self.host_machine()
        write_number(machine, self.timer_pending, 1)
        device = IntegrationDevice(machine, push_failure=True)
        for attempt in range(2):
            # Simulate an old accepted snapshot reaching VRAM after generic
            # fallback. Cached equality must not leave that late frame stuck.
            machine.mem_write(0x300000, b'\0' * 4)
            IMAGE.call(machine, 'VDD_PublishFrame')
            self.assertEqual(bytes(machine.mem_read(0x300000, 4)), b'ABCD')
            self.assertEqual(read_number(machine, self.used, 4), 1)
            self.assertEqual(read_number(machine, self.timer_pending), 1)
        device.push_failure = False
        device.capability = 0xaabbccdd  # host unavailable, cancellation succeeds
        IMAGE.call(machine, 'VDD_PublishFrame')
        self.assertEqual(read_number(machine, self.used, 4), 0)
        self.assertEqual(read_number(machine, self.timer_pending), 0)

    def test_stop_and_setup_cancel_without_losing_failed_ownership(self):
        for function in ('VDD_DblBuf_Stop', 'VDD_DblBuf_Setup'):
            for owned, push_failure in ((1, False), (1, True), (2, False), (2, True)):
                with self.subTest(function=function, owned=owned, push_failure=push_failure):
                    machine = self.host_machine()
                    write_number(machine, self.timer_pending, owned)
                    write_number(machine, self.pending, 1)
                    device = IntegrationDevice(machine, push_failure=push_failure)
                    instructions = IMAGE.function(function, 40)
                    call = next(instruction for instruction in instructions
                                if instruction.mnemonic == 'call')
                    self.assertEqual(call.operands[0].imm, IMAGE.symbols['VDD_HostCancel'])

                    def boundary(cpu, address, size, unused):
                        if address == call.address + call.size:
                            cpu.emu_stop()

                    machine.hook_add(UC_HOOK_CODE, boundary)
                    IMAGE.call(machine, function)
                    self.assertEqual(read_number(machine, self.timer_pending),
                                     owned if push_failure else 0)
                    if function == 'VDD_DblBuf_Stop':
                        self.assertEqual(read_number(machine, self.pending), 0)
                    self.assertEqual(device.events.count(('out', 0x2a, 1, 0x21)),
                                     int(not push_failure))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True, help='built VDDVBE.386')
    parser.add_argument('--map', type=Path, required=True, help='matching VDDVGA.MAP')
    args, remaining = parser.parse_known_args()
    IMAGE = VddImage(args.binary, args.map)
    unittest.main(argv=[__file__, *remaining])
