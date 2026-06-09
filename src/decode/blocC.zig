const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const readMem = parent.readMem;
pub const writeMem = parent.writeMem;
pub const writeEA = parent.writeEA;
pub const updateNZ = parent.updateNZ;
pub const resolveEA = parent.resolveEA;
const signExtend16 = parent.signExtend16;

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const opmode: u3 = @truncate(opcode >> 6);
    const mode: u3 = @truncate(opcode >> 3);

    // EXG Dx, Dy: opmode=101, mode=000
    if (opmode == 0b101 and mode == 0b000) return execEXGDD(cpu, opcode);
    // EXG Ax, Ay: opmode=110, mode=001
    if (opmode == 0b110 and mode == 0b001) return execEXGAA(cpu, opcode);
    // EXG Dx, Ay: opmode=111, mode=001 (must come before MULS)
    if (opmode == 0b111 and mode == 0b001) return execEXGDA(cpu, opcode);

    if (opmode == 0b011) return execMULU(cpu, bus, opcode);
    if (opmode == 0b111) return execMULS(cpu, bus, opcode);
    if (opmode == 0b100 and mode <= 0b001) return execABCD(cpu, bus, opcode);

    return execAND(cpu, bus, opcode);
}

/// EXG Dx, Dy — Exchange Data Registers
fn execEXGDD(cpu: *Cpu, opcode: u16) u32 {
    const reg1: u3 = @truncate(opcode >> 9);
    const reg2: u3 = @truncate(opcode);
    const tmp = cpu.d[reg1];
    cpu.d[reg1] = cpu.d[reg2];
    cpu.d[reg2] = tmp;
    return 6;
}

/// EXG Ax, Ay — Exchange Address Registers
fn execEXGAA(cpu: *Cpu, opcode: u16) u32 {
    const reg1: u3 = @truncate(opcode >> 9);
    const reg2: u3 = @truncate(opcode);
    const tmp = cpu.a[reg1];
    cpu.a[reg1] = cpu.a[reg2];
    cpu.a[reg2] = tmp;
    return 6;
}

/// EXG Dx, Ay — Exchange Data Register with Address Register
fn execEXGDA(cpu: *Cpu, opcode: u16) u32 {
    const reg_d: u3 = @truncate(opcode >> 9);
    const reg_a: u3 = @truncate(opcode);
    const tmp = cpu.d[reg_d];
    cpu.d[reg_d] = cpu.a[reg_a];
    cpu.a[reg_a] = tmp;
    return 6;
}

/// AND <ea>,Dn / AND Dn,<ea>
pub fn execAND(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const opmode: u3 = @truncate(opcode >> 6);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    if ((opmode == 0b100 or opmode == 0b101 or opmode == 0b110) and !parent.isDataAlterableEA(ea)) {
        return parent.illegalInstruction(cpu, bus, opcode, "AND destination");
    }

    switch (opmode) {
        0b000 => {
            const src: u8 = @truncate(readEA(cpu, bus, ea, .byte));
            const dst: u8 = @truncate(cpu.d[dn]);
            const result = dst & src;
            cpu.d[dn] = (cpu.d[dn] & 0xFFFFFF00) | result;
            updateNZ(cpu, result, .byte);
        },
        0b001 => {
            const src: u16 = @truncate(readEA(cpu, bus, ea, .word));
            const dst: u16 = @truncate(cpu.d[dn]);
            const result = dst & src;
            cpu.d[dn] = (cpu.d[dn] & 0xFFFF0000) | result;
            updateNZ(cpu, result, .word);
        },
        0b010 => {
            const src = readEA(cpu, bus, ea, .long);
            const dst = cpu.d[dn];
            const result = dst & src;
            cpu.d[dn] = result;
            updateNZ(cpu, result, .long);
        },
        0b100 => {
            const src: u8 = @truncate(cpu.d[dn]);
            if (mode == 0b000 or mode == 0b001) {
                const dst: u8 = @truncate(readEA(cpu, bus, ea, .byte));
                const result = dst & src;
                writeEA(cpu, bus, ea, .byte, result);
                updateNZ(cpu, result, .byte);
            } else {
                const addr = resolveEA(cpu, bus, ea, .byte);
                const dst: u8 = @truncate(readMem(bus, addr, .byte));
                const result = dst & src;
                writeMem(bus, addr, .byte, result);
                updateNZ(cpu, result, .byte);
            }
        },
        0b101 => {
            const src: u16 = @truncate(cpu.d[dn]);
            if (mode == 0b000 or mode == 0b001) {
                const dst: u16 = @truncate(readEA(cpu, bus, ea, .word));
                const result = dst & src;
                writeEA(cpu, bus, ea, .word, result);
                updateNZ(cpu, result, .word);
            } else {
                const addr = resolveEA(cpu, bus, ea, .word);
                const dst: u16 = @truncate(readMem(bus, addr, .word));
                const result = dst & src;
                writeMem(bus, addr, .word, result);
                updateNZ(cpu, result, .word);
            }
        },
        0b110 => {
            const src = cpu.d[dn];
            if (mode == 0b000 or mode == 0b001) {
                const dst = readEA(cpu, bus, ea, .long);
                const result = dst & src;
                writeEA(cpu, bus, ea, .long, result);
                updateNZ(cpu, result, .long);
            } else {
                const addr = resolveEA(cpu, bus, ea, .long);
                const dst = readMem(bus, addr, .long);
                const result = dst & src;
                writeMem(bus, addr, .long, result);
                updateNZ(cpu, result, .long);
            }
        },
        else => {
            std.log.warn("[CPU] [AND] unknown opmode=0x{X:0>4} at PC=0x{X:0>6}", .{ opmode, cpu.pc });
            return parent.illegalInstruction(cpu, bus, opcode, "AND");
        },
    }

    cpu.sr.v = false;
    cpu.sr.c = false;

    const size: Size = if (opmode == 0b000 or opmode == 0b100) .byte else if (opmode == 0b001 or opmode == 0b101) .word else .long;
    const dest_is_mem = (opmode == 0b100 or opmode == 0b101 or opmode == 0b110);
    return if (dest_is_mem)
        parent.binaryOpCycles(size, 0b000, dn, mode, reg, true)
    else
        parent.binaryOpCycles(size, mode, reg, 0b000, dn, false);
}

/// MULU.W <ea>, Dn — unsigned multiply (16×16→32)
pub fn execMULU(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    const src: u16 = @truncate(readEA(cpu, bus, ea, .word));
    const dst: u16 = @truncate(cpu.d[dn]);
    const result = @as(u32, dst) * @as(u32, src);

    cpu.d[dn] = result;
    updateNZ(cpu, result, .long);
    const overflow = (result >> 16) != 0;
    cpu.sr.v = overflow;
    cpu.sr.c = overflow;

    const ea_cycles = parent.eaCycleCost(mode, reg, .word);
    return 38 + 2 * @as(u32, @popCount(src)) + ea_cycles;
}

/// MULS.W <ea>, Dn — signed multiply (16×16→32)
pub fn execMULS(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    const src: u16 = @truncate(readEA(cpu, bus, ea, .word));
    const dst: u16 = @truncate(cpu.d[dn]);
    const result = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(dst))) * @as(i32, @as(i16, @bitCast(src)))));

    cpu.d[dn] = result;
    updateNZ(cpu, result, .long);
    const lower: u16 = @truncate(result);
    const upper: u16 = @truncate(result >> 16);
    const sign_ext: u16 = if ((lower & 0x8000) != 0) 0xFFFF else 0x0000;
    const overflow = upper != sign_ext;
    cpu.sr.v = overflow;
    cpu.sr.c = overflow;

    // MULS cycles = 38 + 2 * alternating_bits(src) + ea_cycles
    // alternating_bits = number of transitions between 0 and 1 in the 16-bit multiplier
    var alt: u32 = 0;
    var prev = src & 1;
    var remaining = src;
    while (remaining != 0) {
        remaining >>= 1;
        const cur = remaining & 1;
        if (cur != prev) alt += 1;
        prev = cur;
    }
    const ea_cycles = parent.eaCycleCost(mode, reg, .word);
    return 38 + 2 * alt + ea_cycles;
}

/// ABCD - Add Decimal with Extend
/// ABCD Dm, Dn (register): 1100 ddd 1000 000 mmm
/// ABCD -(Am), -(An) (memory): 1100 ddd 1000 001 mmm
/// Operation: Dn = Dn + Dm + X (BCD), Z flag is sticky
pub fn execABCD(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const mode: u1 = @truncate(opcode >> 3);
    const reg_dst: u3 = @truncate(opcode >> 9);
    const reg_src: u3 = @truncate(opcode);
    const x_val: u32 = if (cpu.sr.x) 1 else 0;

    if (mode == 0b000) {
        const a: u8 = @truncate(cpu.d[reg_dst]);
        const b: u8 = @truncate(cpu.d[reg_src]);
        const res = bcdAdd(a, b, x_val);
        cpu.d[reg_dst] = (cpu.d[reg_dst] & 0xFFFFFF00) | res.result;
        setFlagsBCD(cpu, res.carry, res.v, res.result);
        return 6;
    }

    const dec_src: u32 = if (reg_src == 7) 2 else 1;
    const addr_src = cpu.a[reg_src] -% dec_src;
    cpu.a[reg_src] = addr_src;
    const dec_dst: u32 = if (reg_dst == 7) 2 else 1;
    const addr_dst = cpu.a[reg_dst] -% dec_dst;
    cpu.a[reg_dst] = addr_dst;

    const b: u8 = @truncate(readMem(bus, addr_src, .byte));
    const a: u8 = @truncate(readMem(bus, addr_dst, .byte));
    const res = bcdAdd(a, b, x_val);
    writeMem(bus, addr_dst, .byte, res.result);
    setFlagsBCD(cpu, res.carry, res.v, res.result);

    return 18;
}

fn bcdAdd(a: u8, b: u8, x_val: u32) struct { result: u8, carry: bool, v: bool } {
    const a_lo: u32 = a & 0x0F;
    const a_hi: u32 = a >> 4;
    const b_lo: u32 = b & 0x0F;
    const b_hi: u32 = b >> 4;

    var lo_sum: u32 = a_lo + b_lo + x_val;
    const lo_correct: u32 = if (lo_sum > 9) 6 else 0;
    lo_sum += lo_correct;
    const lo_carry: u32 = lo_sum >> 4;
    const lo_nibble: u32 = lo_sum & 0x0F;

    var hi_sum: u32 = a_hi + b_hi + lo_carry;
    const hi_correct: u32 = if (hi_sum > 9) 6 else 0;
    hi_sum += hi_correct;
    const hi_carry: u32 = hi_sum >> 4;
    const hi_nibble: u32 = hi_sum & 0x0F;

    const result: u8 = @as(u8, @truncate((hi_nibble << 4) | lo_nibble));
    const bin_result: u8 = @as(u8, @truncate(a +% b +% x_val));
    const v: bool = ((result ^ bin_result) & result & 0x80) != 0;
    return .{ .result = result, .carry = hi_carry != 0, .v = v };
}

fn setFlagsBCD(cpu: *Cpu, carry: bool, v: bool, result: u8) void {
    cpu.sr.n = (result & 0x80) != 0;
    if (result != 0) cpu.sr.z = false;
    cpu.sr.v = v;
    cpu.sr.c = carry;
    cpu.sr.x = carry;
}
