const std = @import("std");
const math = std.math;
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
const signExtend8 = parent.signExtend8;
const signExtend16 = parent.signExtend16;
const addSigned = parent.addSigned;
const maskSize = parent.maskSize;
const signBit = parent.signBit;
const isNegative = parent.isNegative;

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const opmode: u3 = @truncate(opcode >> 6);
    const mode: u3 = @truncate(opcode >> 3);

    if (opmode == 0b011) return execDIVU(cpu, bus, opcode);
    if (opmode == 0b111) return execDIVS(cpu, bus, opcode);
    if (opmode == 0b100 and mode <= 0b001) return execSBCD(cpu, bus, opcode);

    return execOR(cpu, bus, opcode);
}

/// page 254
/// OR <ea>,Dn / OR Dn,<ea>
pub fn execOR(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const opmode: u3 = @truncate(opcode >> 6);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    if ((opmode == 0b100 or opmode == 0b101 or opmode == 0b110) and !parent.isDataAlterableEA(ea)) {
        return parent.illegalInstruction(cpu, bus, opcode, "OR destination");
    }

    switch (opmode) {
        0b000 => {
            const src: u8 = @truncate(readEA(cpu, bus, ea, .byte));
            const dst: u8 = @truncate(cpu.d[dn]);
            const result = dst | src;
            cpu.d[dn] = (cpu.d[dn] & 0xFFFFFF00) | result;
            updateNZ(cpu, result, .byte);
        },
        0b001 => {
            const src: u16 = @truncate(readEA(cpu, bus, ea, .word));
            const dst: u16 = @truncate(cpu.d[dn]);
            const result = dst | src;
            cpu.d[dn] = (cpu.d[dn] & 0xFFFF0000) | result;
            updateNZ(cpu, result, .word);
        },
        0b010 => {
            const src = readEA(cpu, bus, ea, .long);
            const dst = cpu.d[dn];
            const result = dst | src;
            cpu.d[dn] = result;
            updateNZ(cpu, result, .long);
        },
        0b100 => {
            const src: u8 = @truncate(cpu.d[dn]);
            if (mode == 0b000 or mode == 0b001) {
                const dst: u8 = @truncate(readEA(cpu, bus, ea, .byte));
                const result = dst | src;
                writeEA(cpu, bus, ea, .byte, result);
                updateNZ(cpu, result, .byte);
            } else {
                const addr = resolveEA(cpu, bus, ea, .byte);
                const dst: u8 = @truncate(readMem(bus, addr, .byte));
                const result = dst | src;
                writeMem(bus, addr, .byte, result);
                updateNZ(cpu, result, .byte);
            }
        },
        0b101 => {
            const src: u16 = @truncate(cpu.d[dn]);
            if (mode == 0b000 or mode == 0b001) {
                const dst: u16 = @truncate(readEA(cpu, bus, ea, .word));
                const result = dst | src;
                writeEA(cpu, bus, ea, .word, result);
                updateNZ(cpu, result, .word);
            } else {
                const addr = resolveEA(cpu, bus, ea, .word);
                const dst: u16 = @truncate(readMem(bus, addr, .word));
                const result = dst | src;
                writeMem(bus, addr, .word, result);
                updateNZ(cpu, result, .word);
            }
        },
        0b110 => {
            const src = cpu.d[dn];
            if (mode == 0b000 or mode == 0b001) {
                const dst = readEA(cpu, bus, ea, .long);
                const result = dst | src;
                writeEA(cpu, bus, ea, .long, result);
                updateNZ(cpu, result, .long);
            } else {
                const addr = resolveEA(cpu, bus, ea, .long);
                const dst = readMem(bus, addr, .long);
                const result = dst | src;
                writeMem(bus, addr, .long, result);
                updateNZ(cpu, result, .long);
            }
        },
        else => {
            return parent.illegalInstruction(cpu, bus, opcode, "OR");
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

fn divException(cpu: *Cpu, bus: anytype, vector: u32, origin_pc: u32) u32 {
    cpu.a[7] -%= 4;
    bus.write32(cpu.a[7], origin_pc);
    cpu.a[7] -%= 2;
    bus.write16(cpu.a[7], cpu.sr.get());
    cpu.sr.s = true;
    cpu.sr.t = false;
    cpu.pc = bus.read32(vector);
    return 34;
}

fn divuCycles(dividend: u32) u32 {
    const upper: u16 = @truncate(dividend >> 16);
    const leading: u32 = @clz(upper | 1);
    return 76 + 4 * leading;
}

/// DIVU.W <ea>, Dn — unsigned divide (32-bit / 16-bit → 16-bit quo + 16-bit rem)
pub fn execDIVU(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    const divisor: u32 = readEA(cpu, bus, ea, .word);
    if (divisor == 0) return divException(cpu, bus, 0x14, cpu.pc - 2);

    const dividend = cpu.d[dn];
    const quotient = dividend / divisor;
    const remainder = dividend % divisor;

    const ea_cycles = parent.eaCycleCost(ea.mode, ea.reg, .word);

    if (quotient > 0xFFFF) {
        // Overflow: V=1, Dn unchanged
        cpu.sr.v = true;
        return divuCycles(dividend) + ea_cycles;
    }

    cpu.d[dn] = (remainder << 16) | quotient;
    cpu.sr.n = (quotient & 0x8000) != 0;
    cpu.sr.z = quotient == 0;
    cpu.sr.v = false;
    cpu.sr.c = false;
    return divuCycles(dividend) + ea_cycles;
}

fn divsBaseCycles(dividend: i32) u32 {
    return if (dividend >= 0) 120 else 122;
}

fn divsAddedCycles(quotient: i32) u32 {
    const abs_q = @abs(quotient);
    const upper: u16 = @truncate(@as(u32, @bitCast(abs_q)) >> 16);
    const leading = @as(u32, @clz(upper));
    return 2 * @as(u32, @min(leading, 15));
}

/// DIVS.W <ea>, Dn — signed divide (32-bit / 16-bit → 16-bit quo + 16-bit rem)
pub fn execDIVS(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const dn: u3 = @truncate(opcode >> 9);
    const ea = EA{ .mode = mode, .reg = reg };

    const divisor_raw: u16 = @truncate(readEA(cpu, bus, ea, .word));
    if (divisor_raw == 0) return divException(cpu, bus, 0x14, cpu.pc - 2);

    const dividend: i32 = @bitCast(cpu.d[dn]);
    const divisor: i16 = @bitCast(divisor_raw);

    const ea_cycles = parent.eaCycleCost(ea.mode, ea.reg, .word);

    // Overflow si MIN_INT / -1 (quotient dépasse i32)
    if (dividend == std.math.minInt(i32) and divisor == -1) {
        cpu.sr.v = true;
        return divsBaseCycles(dividend) + ea_cycles;
    }

    const quotient: i32 = @divTrunc(dividend, divisor);
    const remainder: i32 = @rem(dividend, divisor);

    // Check if quotient fits in signed 16 bits
    if (quotient > 32767 or quotient < -32768) {
        cpu.sr.v = true;
        return divsBaseCycles(dividend) + ea_cycles;
    }

    const quo16: u16 = @bitCast(@as(i16, @truncate(quotient)));
    const rem16: u16 = @bitCast(@as(i16, @truncate(remainder)));
    cpu.d[dn] = (@as(u32, rem16) << 16) | quo16;
    cpu.sr.n = (quo16 & 0x8000) != 0;
    cpu.sr.z = quo16 == 0;
    cpu.sr.v = false;
    cpu.sr.c = false;
    return divsBaseCycles(dividend) + divsAddedCycles(quotient) + ea_cycles;
}

/// SBCD - Subtract Decimal with Extend
/// SBCD Dm, Dn (register): 1000 ddd 1000 000 mmm
/// SBCD -(Am), -(An) (memory): 1000 ddd 1000 001 mmm
/// Operation: Dn = Dn - Dm - X (BCD), Z flag is sticky
pub fn execSBCD(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const mode: u3 = @truncate(opcode >> 3);
    const reg_dst: u3 = @truncate(opcode >> 9);
    const reg_src: u3 = @truncate(opcode);
    const x_val: u32 = if (cpu.sr.x) 1 else 0;

    if (mode == 0b000) {
        const a: u8 = @truncate(cpu.d[reg_dst]);
        const b: u8 = @truncate(cpu.d[reg_src]);
        const res = bcdSub(a, b, x_val);
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
    const res = bcdSub(a, b, x_val);
    writeMem(bus, addr_dst, .byte, res.result);
    setFlagsBCD(cpu, res.carry, res.v, res.result);

    return 18;
}

fn bcdSub(a: u8, b: u8, x_val: u32) struct { result: u8, carry: bool, v: bool } {
    const a_lo: u32 = a & 0x0F;
    const a_hi: u32 = a >> 4;
    const b_lo: u32 = b & 0x0F;
    const b_hi: u32 = b >> 4;
    const x: u32 = x_val;

    var result: u8 = @truncate(a -% b -% @as(u8, @truncate(x)));

    const lo_borrow: bool = (a_lo < b_lo + x);
    if (lo_borrow) {
        result -%= 6;
    }

    const hi_borrow: bool = (a_hi < b_hi + @as(u32, @intFromBool(lo_borrow)));
    if (hi_borrow) {
        result -%= 0x60;
    }

    const bin_result: u8 = @as(u8, @truncate(a -% b -% x));
    const diff: u8 = (if (lo_borrow) @as(u8, 6) else 0) + (if (hi_borrow) @as(u8, 0x60) else 0);
    const corrected_borrow = bin_result < diff;
    const carry: bool = (a < b + x) or corrected_borrow;
    const v: bool = ((result ^ bin_result) & bin_result & 0x80) != 0;
    return .{ .result = result, .carry = carry, .v = v };
}

fn setFlagsBCD(cpu: *Cpu, carry: bool, v: bool, result: u8) void {
    cpu.sr.n = (result & 0x80) != 0;
    if (result != 0) cpu.sr.z = false;
    cpu.sr.v = v;
    cpu.sr.c = carry;
    cpu.sr.x = carry;
}
