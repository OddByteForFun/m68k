const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const readMem = parent.readMem;
pub const writeEA = parent.writeEA;
pub const writeMem = parent.writeMem;
pub const resolveEA = parent.resolveEA;
pub const maskSize = parent.maskSize;
pub const updateNZ = parent.updateNZ;
pub const signExtend16 = parent.signExtend16;

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const opmode: u3 = @truncate(opcode >> 6);
    const mode: u3 = @truncate(opcode >> 3);

    switch (opmode) {
        0b000, 0b001, 0b010 => return execCMP(cpu, bus, opcode),
        0b011 => return execCMPA(cpu, bus, opcode, .word),
        0b100, 0b101, 0b110 => {
            if (mode == 0b011) return execCMPM(cpu, bus, opcode);
            return execEOR(cpu, bus, opcode);
        },
        0b111 => return execCMPA(cpu, bus, opcode, .long),
    }
}

/// CMP <ea>,Dn
pub fn execCMP(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const opmode: u3 = @truncate(opcode >> 6);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    switch (opmode) {
        0b000 => {
            const src: u8 = @truncate(readEA(cpu, bus, ea, .byte));
            const dst: u8 = @truncate(cpu.d[dn]);
            setFlagsCMP(cpu, u8, dst, src, dst -% src);
        },
        0b001 => {
            const src: u16 = @truncate(readEA(cpu, bus, ea, .word));
            const dst: u16 = @truncate(cpu.d[dn]);
            setFlagsCMP(cpu, u16, dst, src, dst -% src);
        },
        0b010 => {
            const src = readEA(cpu, bus, ea, .long);
            const dst = cpu.d[dn];
            setFlagsCMP(cpu, u32, dst, src, dst -% src);
        },
        else => {
            std.log.warn("[CPU] [CMP] unknown opmode=0x{X:0>4} at PC=0x{X:0>6}", .{ opmode, cpu.pc });
            return parent.illegalInstruction(cpu, bus, opcode, "CMP");
        },
    }

    const size: Size = switch (opmode) {
        0b000 => .byte,
        0b001 => .word,
        0b010 => .long,
        else => .word,
    };
    return parent.unaryOpCycles(size, mode, reg);
}

fn setFlagsCMP(cpu: *Cpu, comptime T: type, dst: T, src: T, result: T) void {
    const bits = @bitSizeOf(T);
    const msb_mask = @as(T, 1) << (bits - 1);

    cpu.sr.n = (result & msb_mask) != 0;
    cpu.sr.z = result == 0;
    cpu.sr.v = ((dst ^ src) & (dst ^ result) & msb_mask) != 0;
    cpu.sr.c = dst < src;
}

/// CMPA - Compare Address
/// CMPA.W <ea>, An: An - sign-ext(<ea>.W) → flags
/// CMPA.L <ea>, An: An - <ea>.L → flags
pub fn execCMPA(cpu: *Cpu, bus: anytype, opcode: u16, size: Size) u32 {
    const an: u3 = @truncate(opcode >> 9);
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    if (size == .word) {
        const src_raw = readEA(cpu, bus, ea, .word);
        const src: u32 = @as(u32, @bitCast(signExtend16(@truncate(src_raw))));
        const dst = cpu.a[an];
        setFlagsCMP(cpu, u32, dst, src, dst -% src);
    } else {
        const src = readEA(cpu, bus, ea, .long);
        const dst = cpu.a[an];
        setFlagsCMP(cpu, u32, dst, src, dst -% src);
    }

    return parent.unaryOpCycles(size, mode, reg);
}

/// CMPM - Compare Memory
/// CMPM (Ay)+, (Ax)+: (Ax)+ - (Ay)+ → flags
pub fn execCMPM(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => unreachable,
    };
    const reg_dst: u3 = @truncate(opcode >> 9);
    const reg_src: u3 = @truncate(opcode);

    const addr_src = cpu.a[reg_src];
    const addr_dst = cpu.a[reg_dst];

    const inc: u32 = switch (size) {
        .byte => if (reg_src == 7 or reg_dst == 7) 2 else 1,
        .word => 2,
        .long => 4,
    };

    cpu.a[reg_src] = addr_src +% inc;
    cpu.a[reg_dst] = addr_dst +% inc;

    const src = readMem(bus, addr_src, size);
    const dst = readMem(bus, addr_dst, size);

    switch (size) {
        .byte => {
            const ds: u8 = @truncate(dst);
            const ss: u8 = @truncate(src);
            setFlagsCMP(cpu, u8, ds, ss, ds -% ss);
        },
        .word => {
            const ds: u16 = @truncate(dst);
            const ss: u16 = @truncate(src);
            setFlagsCMP(cpu, u16, ds, ss, ds -% ss);
        },
        .long => setFlagsCMP(cpu, u32, dst, src, dst -% src),
    }

    return switch (size) {
        .byte, .word => 12,
        .long => 24,
    };
}

/// EOR Dn, <ea> — Exclusive OR
/// Encoding: 1011 ddd 1 oo mmm rrr
pub fn execEOR(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const dn: u3 = @truncate(opcode >> 9);
    const size_bits: u2 = @truncate(opcode >> 6);
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => unreachable,
    };
    const ea = EA{ .mode = mode, .reg = reg };

    if (!parent.isDataAlterableEA(ea)) {
        return parent.illegalInstruction(cpu, bus, opcode, "EOR destination");
    }

    const src = parent.maskSize(cpu.d[dn], size);

    if (mode == 0b000 or mode == 0b001) {
        const dst = readEA(cpu, bus, ea, size);
        const result = (src ^ dst) & parent.maskSize(0xFFFFFFFF, size);
        writeEA(cpu, bus, ea, size, result);
        parent.updateNZ(cpu, result, size);
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const dst = readMem(bus, addr, size);
        const result = (src ^ dst) & parent.maskSize(0xFFFFFFFF, size);
        writeMem(bus, addr, size, result);
        parent.updateNZ(cpu, result, size);
    }

    cpu.sr.v = false;
    cpu.sr.c = false;

    return parent.binaryOpCycles(size, 0b000, dn, mode, reg, mode != 0b000 and mode != 0b001);
}
