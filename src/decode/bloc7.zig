const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

/// Bloc 0x7 - MOVEQ
pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    if ((opcode & 0x0100) == 0) {
        return execMOVEQ(cpu, opcode);
    }

    return parent.exception(cpu, bus, 0x10, opcode, "bloc7");
}

/// MOVEQ #<data>,Dn
/// Charge un immédiat 8 bits signé dans un registre donnée long.
pub fn execMOVEQ(cpu: *Cpu, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode >> 9);
    const imm: u8 = @truncate(opcode);
    const value: u32 = @bitCast(@as(i32, @as(i8, @bitCast(imm))));

    cpu.d[reg] = value;
    cpu.sr.n = (value & 0x8000_0000) != 0;
    cpu.sr.z = value == 0;
    cpu.sr.v = false;
    cpu.sr.c = false;

    return 4;
}
