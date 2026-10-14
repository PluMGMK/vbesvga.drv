#!/usr/bin/env python3
"""Check acquired/unacquired cleanup in the built display driver."""

import argparse
from pathlib import Path
import unittest

from unicorn import UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_BP, UC_X86_REG_EFLAGS, UC_X86_REG_AX

from driver_image import DriverImage


class ExclusionCleanup(unittest.TestCase):
    def test_cleanup_requires_own_acquisition(self):
        for function in ('BITBLT', 'do_polylines', 'Pixel'):
            with self.subTest(function=function):
                instructions = IMAGE.function(function, 2000)
                gates = []
                for index, instruction in enumerate(instructions[:-2]):
                    following = instructions[index + 1:index + 3]
                    if (instruction.mnemonic == 'cmp'
                            and instruction.op_str.startswith('byte ptr [bp - ')
                            and instruction.op_str.endswith(', 0')
                            and following[0].mnemonic == 'je'
                            and following[1].mnemonic in ('call', 'lcall')):
                        gates.append((instruction, *following))
                self.assertEqual(len(gates), 1, 'one acquisition cleanup gate')
                gate, branch, release = gates[0]
                displacement = gate.operands[0].mem.disp
                flag_stores = [
                    instruction for instruction in instructions
                    if instruction.mnemonic == 'mov'
                    and instruction.operands[0].type == 3
                    and instruction.operands[0].mem.disp == displacement
                    and instruction.op_str.startswith('byte ptr [bp - ')
                ]
                initialize = next(store for store in flag_stores
                                  if store.operands[1].imm == 0)
                acquire = next(store for store in flag_stores
                               if store.operands[1].imm == 1)
                previous = instructions[instructions.index(acquire) - 1]
                self.assertIn(previous.mnemonic, ('call', 'lcall'))
                self.assertLess(initialize.address, previous.address)

                for owned, store in ((False, initialize), (True, acquire)):
                    with self.subTest(acquired=owned):
                        machine = IMAGE.machine(IMAGE.symbols[function][0])
                        machine.reg_write(UC_X86_REG_BP, 0x8000)
                        # Execute the real initialization/acquisition store,
                        # then the real cleanup branch. OS drawing callbacks
                        # and primitive setup are outside this focused test.
                        machine.emu_start(IMAGE.CODE_BASE + store.address,
                                          IMAGE.CODE_BASE + store.address + store.size,
                                          count=1)
                        self.assertEqual(bytes(machine.mem_read(
                            IMAGE.STACK_BASE + 0x8000 + displacement, 1)),
                            bytes([owned]))
                        calls = []
                        destination = branch.operands[0].imm

                        def boundary(cpu, address, size, unused):
                            if address == IMAGE.CODE_BASE + release.address:
                                calls.append(address)
                                cpu.emu_stop()
                            elif address == IMAGE.CODE_BASE + destination:
                                cpu.emu_stop()

                        machine.hook_add(UC_HOOK_CODE, boundary)
                        machine.emu_start(IMAGE.CODE_BASE + gate.address,
                                          IMAGE.RETURN, count=20)
                        self.assertEqual(len(calls), int(owned))

    def test_polyline_stack_failure_bypasses_locals_and_cleanup(self):
        instructions = IMAGE.function('do_polylines', 2000)
        branch = next(instruction for instruction in instructions
                      if instruction.mnemonic == 'jae')
        machine = IMAGE.machine(IMAGE.symbols['do_polylines'][0])
        machine.reg_write(UC_X86_REG_EFLAGS, 3)  # carry: failed stack check
        machine.reg_write(UC_X86_REG_AX, 0xbeef)
        visited = []

        def boundary(cpu, address, size, unused):
            instruction = next(IMAGE.decoder.disasm(bytes(cpu.mem_read(address, 8)),
                                                    address - IMAGE.CODE_BASE))
            visited.append(instruction)
            # Stop at the first epilogue instruction, before its restored
            # registers would require a DDK-generated caller stack frame.
            if instruction.mnemonic == 'xor' and instruction.op_str == 'ax, ax':
                return
            if len(visited) > 2 and visited[-2].mnemonic == 'xor':
                cpu.emu_stop()

        machine.hook_add(UC_HOOK_CODE, boundary)
        machine.emu_start(IMAGE.CODE_BASE + branch.address, IMAGE.RETURN, count=20)
        self.assertEqual(machine.reg_read(UC_X86_REG_AX), 0)
        self.assertFalse(any(instruction.mnemonic in ('call', 'lcall')
                             or '[bp' in instruction.op_str for instruction in visited))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True, help='built VBESVGA.DRV')
    parser.add_argument('--map', type=Path, required=True, help='matching VBESVGA.MAP')
    args, remaining = parser.parse_known_args()
    IMAGE = DriverImage(args.binary, args.map)
    unittest.main(argv=[__file__, *remaining])
