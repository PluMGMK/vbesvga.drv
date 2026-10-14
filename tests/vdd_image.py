"""Load the zero-based LE VDD image produced by the documented DDK build."""

from pathlib import Path
import re
import struct

from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
from unicorn.x86_const import (
    UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_FS, UC_X86_REG_SS,
    UC_X86_REG_ESP, UC_X86_REG_GDTR,
)


class VddImage:
    RETURN = 0x1ff00
    FRONT_BASE = 0x200000
    BACK_BASE = 0x100000

    def __init__(self, binary, map_file):
        blob = Path(binary).read_bytes()
        header = struct.unpack_from('<I', blob, 0x3c)[0]
        assert blob[header:header + 2] == b'LE'
        data = struct.unpack_from('<I', blob, header + 128)[0]
        objects = header + struct.unpack_from('<I', blob, header + 64)[0]
        pages = header + struct.unpack_from('<I', blob, header + 72)[0]
        self.image = bytearray(0x20000)
        for number in range(struct.unpack_from('<I', blob, header + 68)[0]):
            _, base, _, first, count, _ = struct.unpack_from(
                '<6I', blob, objects + number * 24)
            for index in range(count):
                entry = pages + (first - 1 + index) * 4
                page = int.from_bytes(blob[entry:entry + 3], 'big')
                if page:
                    chunk = blob[data + (page - 1) * 4096:data + page * 4096]
                    start = base + index * 4096
                    self.image[start:start + len(chunk)] = chunk
        self.symbols = {name: int(offset, 16) for offset, name in re.findall(
            r'0001:([0-9A-Fa-f]{8})\s+(VDD_\w+)', Path(map_file).read_text())}
        self.decoder = Cs(CS_ARCH_X86, CS_MODE_32)
        self.decoder.detail = True

    def function(self, name, length=256):
        offset = self.symbols[name]
        return list(self.decoder.disasm(bytes(self.image[offset:offset + length]), offset))

    @staticmethod
    def descriptor(base):
        limit = 0xfffff
        return struct.pack('<II', (limit & 0xffff) | ((base & 0xffff) << 16),
                           ((base >> 16) & 255) | (0x92 << 8) | (0xc << 20)
                           | (((limit >> 16) & 15) << 16) | (base & 0xff000000))

    def machine(self):
        machine = Uc(UC_ARCH_X86, UC_MODE_32)
        machine.mem_map(0, 0x20000)
        machine.mem_write(0, bytes(self.image))
        for base in (self.BACK_BASE, self.FRONT_BASE):
            machine.mem_map(base, 0x100000)
        machine.mem_write(0x1d000, b'\0' * 8 + self.descriptor(0)
                          + self.descriptor(self.FRONT_BASE)
                          + self.descriptor(self.BACK_BASE))
        machine.reg_write(UC_X86_REG_GDTR, (0, 0x1d000, 31, 0))
        for register in (UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_FS, UC_X86_REG_SS):
            machine.reg_write(register, 8)
        self.prepare_call(machine)
        return machine

    def prepare_call(self, machine):
        machine.reg_write(UC_X86_REG_ESP, 0x1c000)
        machine.mem_write(0x1c000, struct.pack('<I', self.RETURN))

    def call(self, machine, name):
        self.prepare_call(machine)
        machine.emu_start(self.symbols[name], self.RETURN, count=4000000)


def write_number(machine, address, value, size=2):
    machine.mem_write(address, value.to_bytes(size, 'little'))


def read_number(machine, address, size=2):
    return int.from_bytes(machine.mem_read(address, size), 'little')
