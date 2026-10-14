"""Read the NE display-driver image and symbol map produced by the DDK build."""

from pathlib import Path
import re
import struct

from capstone import Cs, CS_ARCH_X86, CS_MODE_16
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16
from unicorn.x86_const import (
    UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_SS, UC_X86_REG_SP,
)


class DriverImage:
    CODE_BASE = 0x10000
    DATA_BASE = 0x20000
    SHARED_BASE = 0x30000
    STACK_BASE = 0x60000
    RETURN = 0x1ff00

    def __init__(self, binary, map_file):
        self.blob = Path(binary).read_bytes()
        header = struct.unpack_from('<I', self.blob, 0x3c)[0]
        assert self.blob[header:header + 2] == b'NE'
        table = header + struct.unpack_from('<H', self.blob, header + 0x22)[0]
        alignment = struct.unpack_from('<H', self.blob, header + 0x32)[0]
        count = struct.unpack_from('<H', self.blob, header + 0x1c)[0]
        self.segments = {}
        for segment in range(1, count + 1):
            sector, length, _, _ = struct.unpack_from(
                '<4H', self.blob, table + (segment - 1) * 8)
            start = sector << alignment
            self.segments[segment] = self.blob[start:start + (length or 0x10000)]
        self.symbols = {
            name: (int(segment, 16), int(offset, 16))
            for segment, offset, name in re.findall(
                r'([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})\s+(\w+)',
                Path(map_file).read_text())
        }
        # Exported API names may use different capitalization in linker maps.
        self.symbols.update({name.upper(): value
                             for name, value in list(self.symbols.items())})
        self.decoder = Cs(CS_ARCH_X86, CS_MODE_16)
        self.decoder.detail = True

    def function(self, name, length=256):
        segment, offset = self.symbols[name]
        return list(self.decoder.disasm(
            self.segments[segment][offset:offset + length], offset))

    def machine(self, segment=1):
        machine = Uc(UC_ARCH_X86, UC_MODE_16)
        machine.mem_map(self.CODE_BASE, 0x60000)
        machine.mem_write(self.CODE_BASE, self.segments[segment])
        for register, value in (
                (UC_X86_REG_CS, 0x1000), (UC_X86_REG_DS, 0x2000),
                (UC_X86_REG_SS, 0x6000)):
            machine.reg_write(register, value)
        self.prepare_call(machine)
        return machine

    def prepare_call(self, machine):
        machine.reg_write(UC_X86_REG_SP, 0xff00)
        machine.mem_write(self.STACK_BASE + 0xff00, b'\x00\xff')

    def call(self, machine, name):
        self.prepare_call(machine)
        machine.emu_start(self.CODE_BASE + self.symbols[name][1],
                          self.RETURN, count=10000)
