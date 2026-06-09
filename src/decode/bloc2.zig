const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const readMem = parent.readMem;
pub const updateNZ = parent.updateNZ;
pub const isNegative = parent.isNegative;

const signExtend8 = parent.signExtend8;
const signExtend16 = parent.signExtend16;
const addSigned = parent.addSigned;

pub const writeEA = parent.writeEA;
pub const writeMem = parent.writeMem;
pub const maskSize = parent.maskSize;
const signBit = parent.signBit;
const decodeEAType = parent.decodeEAType;
const eaCycleCost = parent.eaCycleCost;

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);

    if (size_bits == 0b11 and ((opcode >> 3) & 0x7) == 0b001) {
        return execDBcc(cpu, bus, opcode);
    }

    // size_bits == 0b11 correspond aussi a Scc, pas a ADDQ/SUBQ.
    if (size_bits == 0b11) {
        return execScc(cpu, bus, opcode);
    }

    return if ((opcode & 0x0100) == 0)
        execADDQ(cpu, bus, opcode)
    else
        execSUBQ(cpu, bus, opcode);
}

/// ADD Quick (p115)
/// ADDQ # < data > , < ea >
/// Size = (Byte, Word, Long)
/// X — Set the same as the carry bit.
/// N — Set if the result is negative; cleared otherwise.
/// Z — Set if the result is zero; cleared otherwise.
/// V — Set if an overflow occurs; cleared otherwise.
/// C — Set if a carry occurs; cleared otherwise.
///
///
pub fn execADDQ(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        else => .word,
    };
    const data: u3 = @truncate(opcode >> 9);
    const imm: u32 = if (data == 0) 8 else @as(u32, data);

    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b001) {
        const old = cpu.a[reg];
        cpu.a[reg] = old +% imm;
        return 8;
    }

    if (mode == 0b000) {
        const old = maskSize(cpu.d[reg], size);
        const result = old +% imm;
        const res = maskSize(result, size);
        const src = maskSize(imm, size);

        setFlagsADD(cpu, size, old, src, res);
        writeEA(cpu, bus, ea, size, res);

        return if (size == .long) 8 else 4;
    }

    const addr = effectiveAddress(cpu, bus, ea, size) orelse return 4;
    const old = readMem(bus, addr, size);
    const result = old +% imm;

    const src = imm;
    const dst = maskSize(old, size);
    const res = maskSize(result, size);

    setFlagsADD(cpu, size, dst, src, res);
    writeMem(bus, addr, size, res);

    if (mode == 0b000) return if (size == .long) 8 else 4;
    if (mode == 0b001) return 8;
    const base_mem: u32 = if (size == .long) 12 else 8;
    return base_mem + eaCycleCost(mode, reg, size);
}

/// SUBQ # < data > , < ea >
/// Size = (Byte, Word, Long)
/// 0101 sss 1 dd mmm rrr
/// Subtracts the immediate data (1 – 8) from the destination operand. The size
/// of the operation is specified as byte, word, or long. Only word and long operations can
/// be used with address registers, and the condition codes are not affected. When
/// subtracting from address registers, the entire destination address register is used,
/// despite the operation size.
/// X —Set to the value of the carry bit.
/// N —Set if the result is negative; cleared otherwise.
/// Z —Set if the result is zero; cleared otherwise.
/// V —Set if an overflow occurs; cleared otherwise.
/// C —Set if a borrow occurs; cleared otherwise.
pub fn execSUBQ(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        else => .word,
    };
    const ea = EA{ .mode = mode, .reg = reg };
    // Valeur immédiate encodée dans les bits 11-9, 0 = 8
    const imm_raw: u32 = (opcode >> 9) & 0x7;
    const imm: u32 = if (imm_raw == 0) 8 else imm_raw;

    // SUBQ sur registre d'adresse : pas de mise à jour des flags, toujours .long
    if (mode == 0b001) {
        const result = cpu.a[reg] -% imm;
        cpu.a[reg] = result;
        return 8;
    }
    if (mode == 0b000) {
        // Registre donnée : opérer sur la taille, préserver le reste
        const old_full = cpu.d[reg];
        const old_masked = maskSize(old_full, size);
        const result_masked = old_masked -% imm;

        // Merge : garder les bits hauts, remplacer les bits bas
        const mask = maskSize(0xFFFFFFFF, size);
        const new_full = (old_full & ~mask) | (result_masked & mask);
        cpu.d[reg] = new_full;

        setFlagsSUB(cpu, size, old_masked, maskSize(imm, size), result_masked & mask);

        return if (size == .long) 8 else 4;
    }

    const addr = effectiveAddress(cpu, bus, ea, size) orelse return 4;
    const dst = readMem(bus, addr, size);
    const result = dst -% imm;
    const masked = maskSize(result, size);

    setFlagsSUB(cpu, size, maskSize(dst, size), maskSize(imm, size), masked);
    writeMem(bus, addr, size, masked);

    if (mode == 0b000) return if (size == .long) 8 else 4;
    if (mode == 0b001) return 8;
    const base_mem_subq: u32 = if (size == .long) 12 else 8;
    return base_mem_subq + eaCycleCost(mode, reg, size);
}

/// DBcc Dn,<disp16>
/// Si la condition est fausse, décrémente le word bas de Dn et branche tant qu'il ne vaut pas -1.
pub fn execDBcc(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const condition: u4 = @truncate(opcode >> 8);
    const reg: u3 = @truncate(opcode);
    const extension_pc = cpu.pc;
    const displacement = signExtend16(bus.read16(cpu.pc));
    cpu.pc += 2;

    if (evalCondition(cpu, condition)) {
        return 12;
    }

    const old_word: u16 = @truncate(cpu.d[reg]);
    const new_word = old_word -% 1;
    cpu.d[reg] = (cpu.d[reg] & 0xFFFF_0000) | new_word;

    if (new_word != 0xFFFF) {
        cpu.pc = addSigned(extension_pc, displacement);
        return 10;
    }

    return 14;
}

/// Scc - Set Conditionally
/// Scc Dn: 0101 cccc 11 000 rrr
/// Scc <ea>: 0101 cccc 11 mmm rrr
/// Si la condition est vraie, écrit 0xFF (byte) à l'EA; sinon 0x00.
pub fn execScc(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const condition: u4 = @truncate(opcode >> 8);
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const cond_true = evalCondition(cpu, condition);

    const value: u8 = if (cond_true) 0xFF else 0x00;

    if (mode == 0b000) {
        // Data register
        cpu.d[reg] = (cpu.d[reg] & 0xFFFFFF00) | value;
        return if (cond_true) 6 else 4;
    }

    // Memory EA (byte only)
    const ea = EA{ .mode = mode, .reg = reg };
    writeEA(cpu, bus, ea, .byte, value);
    return if (cond_true) switch (mode) {
        0b010 => 8,
        0b011 => 8,
        0b100 => 10,
        0b101 => 12,
        0b110 => 14,
        0b111 => switch (reg) {
            0b000 => 12,
            0b001 => 16,
            else => 8,
        },
        else => 8,
    } else switch (mode) {
        0b010, 0b011 => 8,
        0b100 => 10,
        0b101 => 12,
        0b110 => 14,
        0b111 => switch (reg) {
            0b000 => 12,
            0b001 => 16,
            else => 8,
        },
        else => 8,
    };
}

fn setFlagsADD(cpu: *Cpu, size: Size, dst: u32, src: u32, result: u32) void {
    const bit = signBit(size);
    const mask = maskSize(0xFFFF_FFFF, size);
    const d = dst & mask;
    const s = src & mask;
    const r = result & mask;

    cpu.sr.n = isNegative(r, size);
    cpu.sr.z = r == 0;
    cpu.sr.v = ((~(d ^ s) & (d ^ r)) & bit) != 0;
    cpu.sr.c = switch (size) {
        .byte => d + s > 0xFF,
        .word => d + s > 0xFFFF,
        .long => @as(u64, d) + @as(u64, s) > 0xFFFF_FFFF,
    };
    cpu.sr.x = cpu.sr.c;
}

fn setFlagsSUB(cpu: *Cpu, size: Size, dst: u32, src: u32, result: u32) void {
    const bit = signBit(size);
    const mask = maskSize(0xFFFF_FFFF, size);
    const d = dst & mask;
    const s = src & mask;
    const r = result & mask;

    cpu.sr.n = isNegative(r, size);
    cpu.sr.z = r == 0;
    cpu.sr.v = (((d ^ s) & (d ^ r)) & bit) != 0;
    cpu.sr.c = d < s;
    cpu.sr.x = cpu.sr.c;
}

fn effectiveAddress(cpu: *Cpu, bus: anytype, ea: EA, size: Size) ?u32 {
    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Indirect => cpu.a[ea.reg],
        .PostInc => blk: {
            const addr = cpu.a[ea.reg];
            cpu.a[ea.reg] += switch (size) {
                .byte => if (ea.reg == 7) @as(u32, 2) else @as(u32, 1),
                .word => 2,
                .long => 4,
            };
            break :blk addr;
        },
        .PreDec => blk: {
            cpu.a[ea.reg] -= switch (size) {
                .byte => if (ea.reg == 7) @as(u32, 2) else @as(u32, 1),
                .word => 2,
                .long => 4,
            };
            break :blk cpu.a[ea.reg];
        },
        .Displ => blk: {
            const addr = addSigned(cpu.a[ea.reg], signExtend16(bus.read16(cpu.pc)));
            cpu.pc += 2;
            break :blk addr;
        },
        .Index => blk: {
            const ext = bus.read16(cpu.pc);
            cpu.pc += 2;

            const disp = signExtend8(@truncate(ext));
            const index_reg = (ext >> 12) & 0x7;
            const index_is_addr = ((ext >> 15) & 1) == 1;
            const index_size_long = ((ext >> 11) & 1) == 1;

            var index_val: u32 = if (index_is_addr)
                cpu.a[index_reg]
            else
                cpu.d[index_reg];

            if (!index_size_long) {
                index_val = @as(u32, @bitCast(signExtend16(@truncate(index_val))));
            }

            break :blk addSigned(addSigned(cpu.a[ea.reg], disp), @as(i32, @bitCast(index_val)));
        },
        .AbsW => blk: {
            const addr = signExtend16(bus.read16(cpu.pc));
            cpu.pc += 2;
            break :blk @as(u32, @bitCast(addr));
        },
        .AbsL => blk: {
            const addr = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk addr;
        },
        else => null,
    };
}

fn evalCondition(cpu: *const Cpu, cond: u4) bool {
    return switch (cond) {
        0x0 => true, // T
        0x1 => false, // F / DBRA
        0x2 => !cpu.sr.c and !cpu.sr.z, // HI
        0x3 => cpu.sr.c or cpu.sr.z, // LS
        0x4 => !cpu.sr.c, // CC/HS
        0x5 => cpu.sr.c, // CS/LO
        0x6 => !cpu.sr.z, // NE
        0x7 => cpu.sr.z, // EQ
        0x8 => !cpu.sr.v, // VC
        0x9 => cpu.sr.v, // VS
        0xA => !cpu.sr.n, // PL
        0xB => cpu.sr.n, // MI
        0xC => cpu.sr.n == cpu.sr.v, // GE
        0xD => cpu.sr.n != cpu.sr.v, // LT
        0xE => !cpu.sr.z and (cpu.sr.n == cpu.sr.v), // GT
        0xF => cpu.sr.z or (cpu.sr.n != cpu.sr.v), // LE
    };
}
