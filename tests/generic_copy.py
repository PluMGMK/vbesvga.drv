"""Set up the generic copier's protected-mode selectors and frame fixtures."""

import struct
from unicorn.x86_const import UC_X86_REG_GDTR, UC_X86_REG_GS
from vdd_image import write_number


class GenericCopyFixture:
    @classmethod
    def configure_image(cls, image):
        cls.image = image
        copy = image.function('VDD_CopyBuffers', 700)
        cls.selectors = [instruction.operands[1].mem.disp for instruction in copy
                         if instruction.mnemonic == 'mov'
                         and instruction.op_str.startswith(('es,', 'fs,', 'gs,'))][:3]
        cls.size = next(instruction for instruction in copy
                        if instruction.mnemonic == 'mov'
                        and instruction.op_str.startswith('edx,')).operands[1].mem.disp
        cls.shared = next(instruction for instruction in copy
                          if instruction.mnemonic == 'test'
                          and instruction.op_str.startswith('word ptr [')).operands[0].mem.disp - 16400
        cls.pixel_bytes = next(instruction for instruction in copy
                               if instruction.mnemonic == 'imul'
                               and len(instruction.operands) == 2
                               and instruction.op_str.startswith('bx, word ptr [')).operands[1].mem.disp
        cls.stride = next(instruction for instruction in copy
                          if instruction.mnemonic == 'mov'
                          and instruction.op_str.startswith('ax, word ptr [')).operands[1].mem.disp

    def configured_machine(self, data, cursor=False, pixel_bytes=1):
        machine = self.image.machine()
        machine.mem_map(0x300000, 0x100000)
        machine.mem_write(0x1d020, self.image.descriptor(0x300000))
        machine.reg_write(UC_X86_REG_GDTR, (0, 0x1d000, 39, 0))
        machine.reg_write(UC_X86_REG_GS, 8)
        for address, value in zip(self.selectors, (16, 24, 32)):
            write_number(machine, address, value)
        machine.mem_write(self.image.BACK_BASE, data or b'\0')
        machine.mem_write(self.image.FRONT_BASE, b'\xa5' * max(len(data), 1))
        machine.mem_write(0x300000, b'\xa5' * max(len(data), 1))
        write_number(machine, self.size, len(data), 4)
        write_number(machine, self.pixel_bytes, pixel_bytes)
        write_number(machine, self.stride, min(len(data), 1280))
        expected = bytearray(data)
        if cursor:
            write_number(machine, self.shared + 16400, 4)
            position = len(data) - 2 * pixel_bytes
            machine.mem_write(self.shared + 4,
                              struct.pack('<HHHHI', 2, 1, 30, 31, position))
            pairs = b'\xff\xff' * pixel_bytes + b'\x00\x42' * pixel_bytes
            machine.mem_write(self.shared + 16 + (31 * 32 + 30) * pixel_bytes * 2,
                              pairs)
            expected[position:position + pixel_bytes] = bytes(
                value ^ 255 for value in data[position:position + pixel_bytes])
            expected[position + pixel_bytes:] = b'\x42' * pixel_bytes
        return machine, bytes(expected)
