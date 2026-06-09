const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

// Ré-exporter les types et helpers du module parent
pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const writeEA = parent.writeEA;
pub const resolveEA = parent.resolveEA;
pub const updateNZ = parent.updateNZ;
pub const maskSize = parent.maskSize;
pub const readMem = parent.readMem;
pub const writeMem = parent.writeMem;
pub const mergeValue = parent.mergeValue;
pub const addSigned = parent.addSigned;
pub const signExtend16 = parent.signExtend16;
pub const signExtend8 = parent.signExtend8;
pub const EAMode = parent.EAMode;
pub const decodeEAType = parent.decodeEAType;
pub const eaCycleCost = parent.eaCycleCost;

const move_bw = [12][12]u8{
    // dst →
    // Dn  An  (An) (An)+ -(An) d16  d8   AbsW AbsL PcD  PcI  Imm
    .{ 4, 4, 8, 8, 8, 12, 14, 12, 16, 12, 14, 8 }, // src Dn
    .{ 4, 4, 8, 8, 8, 12, 14, 12, 16, 12, 14, 8 }, // src An
    .{ 8, 8, 12, 12, 12, 16, 18, 16, 20, 16, 18, 12 }, // src (An)
    .{ 8, 8, 12, 12, 12, 16, 18, 16, 20, 16, 18, 12 },
    .{ 8, 8, 12, 12, 12, 16, 18, 16, 20, 16, 18, 12 },
    .{ 12, 12, 16, 16, 16, 20, 22, 20, 24, 20, 22, 16 },
    .{ 14, 14, 18, 18, 18, 22, 24, 22, 26, 22, 24, 18 },
    .{ 12, 12, 16, 16, 16, 20, 22, 20, 24, 20, 22, 16 },
    .{ 16, 16, 20, 20, 20, 24, 26, 24, 28, 24, 26, 20 },
    .{ 12, 12, 16, 16, 16, 20, 22, 20, 24, 20, 22, 16 },
    .{ 14, 14, 18, 18, 18, 22, 24, 22, 26, 22, 24, 18 },
    .{ 8, 8, 12, 12, 12, 16, 18, 16, 20, 16, 18, 12 },
};

const move_l = [12][12]u8{
    .{ 4, 4, 12, 12, 14, 16, 18, 16, 20, 16, 18, 12 }, // Dn
    .{ 4, 4, 12, 12, 14, 16, 18, 16, 20, 16, 18, 12 }, // An
    .{ 12, 12, 20, 20, 20, 24, 26, 24, 28, 24, 26, 20 }, // (An)
    .{ 12, 12, 20, 20, 20, 24, 26, 24, 28, 24, 26, 20 }, // (An)+
    .{ 14, 14, 20, 20, 20, 24, 26, 24, 28, 24, 26, 20 }, // -(An)
    .{ 16, 16, 24, 24, 24, 28, 30, 28, 32, 28, 30, 24 }, // d16(An)
    .{ 18, 18, 26, 26, 26, 30, 32, 30, 34, 30, 32, 26 }, // d8(An,Xn)
    .{ 16, 16, 24, 24, 24, 28, 30, 28, 32, 28, 30, 24 }, // Abs.W
    .{ 20, 20, 28, 28, 28, 32, 34, 32, 36, 32, 34, 28 }, // Abs.L
    .{ 16, 16, 24, 24, 24, 28, 30, 28, 32, 28, 30, 24 }, // PC d16
    .{ 18, 18, 26, 26, 26, 30, 32, 30, 34, 30, 32, 26 }, // PC index
    .{ 12, 12, 20, 20, 20, 24, 26, 24, 28, 24, 26, 20 }, // #imm
};

/// Bloc 0x0 - Opcodes immediat (ORI, ANDI, ADDI, SUBI, EORI, CMPI)
/// + Opérations bit (BTST, BCHG, BCLR, BSET)
/// + Special (MOVEP, MOVEA, MOVE)
pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const type_instruction: u4 = @truncate(opcode >> 8);

    // ------------------------- MOVE SECTION (priorité) -------------------------------

    // MOVEP : top nibble = 0x0, bit 8 = 1, bits 5-3 = 001
    if ((opcode & 0xF000) == 0x0000 and (opcode & 0x0100) != 0 and ((opcode >> 3) & 0x7) == 0b001) {
        return execMOVEP(cpu, bus, opcode);
    }

    // BTST/BCHG/BCLR/BSET dynamique : bit source dans Dn (bits 11-9).
    if ((opcode & 0xF000) == 0 and (opcode & 0x0100) != 0) {
        const bit_op: u2 = @truncate(opcode >> 6);
        return switch (bit_op) {
            0b00 => execBitOp(cpu, bus, opcode, .btst),
            0b01 => execBitOp(cpu, bus, opcode, .bchg),
            0b10 => execBitOp(cpu, bus, opcode, .bclr),
            0b11 => execBitOp(cpu, bus, opcode, .bset),
        };
    }

    // MOVEA <ea>, An (dst_mode = An = bits 8-6 = 001)
    if (((opcode & 0xF000) == 0x2000 or (opcode & 0xF000) == 0x3000) and
        ((opcode >> 6) & 0x7) == 0b001)
    {
        return execMOVEA(cpu, bus, opcode);
    }

    if ((opcode & 0xF000) == 0x1000 and ((opcode >> 6) & 0x7) == 0b001) {
        return parent.illegalInstruction(cpu, bus, opcode, "MOVE.B to An");
    }

    // MOVE <ea>, <ea>
    // Bits 15-12 : taille (01=byte, 10=long, 11=word)
    if (((opcode & 0xF000) == 0x1000 or
        (opcode & 0xF000) == 0x2000 or
        (opcode & 0xF000) == 0x3000) and
        ((opcode >> 6) & 0x7) != 0b001)
    {
        return execMOVE(cpu, bus, opcode);
    }

    // ------------------------- FIN MOVE SECTION -------------------------------

    // Dispatch selon le type d'instruction immediate/bit
    switch (type_instruction) {
        0x0 => return execORI(cpu, bus, opcode),
        0x2 => return execANDI(cpu, bus, opcode),
        0x4 => return execSUBI(cpu, bus, opcode),
        0x6 => return execADDI(cpu, bus, opcode),
        0xA => return execEORI(cpu, bus, opcode),
        0xC => return execCMPI(cpu, bus, opcode),
        0x8 => {
            // Bits 7-6 identifient l'opération bit
            const bit_op: u2 = @truncate(opcode >> 6);
            return switch (bit_op) {
                0b00 => execBitOp(cpu, bus, opcode, .btst),
                0b01 => execBitOp(cpu, bus, opcode, .bchg),
                0b10 => execBitOp(cpu, bus, opcode, .bclr),
                0b11 => execBitOp(cpu, bus, opcode, .bset),
            };
        },
        else => {
            return parent.exception(cpu, bus, 0x10, opcode, "bloc0");
        },
    }
}

// ============================================
// IMMEDIAT OPERATIONS
// ============================================

/// ORI - Logical OR with Immediate
/// ORI #imm, <ea>
/// ORI to CCR - 0x003C
/// ORI to SR - 0x007C
pub fn execORI(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };

    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    // ORI to CCR
    if (opcode == 0x003C) {
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        const value = @as(u8, @truncate(imm));
        const ccr = &cpu.sr;

        ccr.c = (ccr.c or ((value & 0x01) != 0));
        ccr.v = (ccr.v or ((value & 0x02) != 0));
        ccr.z = (ccr.z or ((value & 0x04) != 0));
        ccr.n = (ccr.n or ((value & 0x08) != 0));
        ccr.x = (ccr.x or ((value & 0x10) != 0));

        // p127 doc M68000
        return 20;
    }

    // ORI to SR
    if (opcode == 0x007C) {
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        const old_s = cpu.sr.s;
        cpu.sr.set(cpu.sr.get() | imm);
        const new_s = cpu.sr.s;

        // Handle supervisor/user mode transition
        if (old_s and !new_s) {
            // Transitioning from supervisor to user mode
            cpu.ssp = cpu.a[7];
            cpu.a[7] = cpu.usp;
        } else if (!old_s and new_s) {
            // Transitioning from user to supervisor mode
            cpu.usp = cpu.a[7];
            cpu.a[7] = cpu.ssp;
        }
        return 20;
    }

    // ORI generic
    const imm: u32 = switch (size) {
        .byte => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value & 0xff);
        },
        .word => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value);
        },
        .long => blk: {
            const value = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk value;
        },
    };

    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b001) return parent.illegalInstruction(cpu, bus, opcode, "ORI to An");
    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const result = old | imm;
        writeEA(cpu, bus, ea, size, result);
        updateNZ(cpu, result, size);
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const result = old | imm;
        writeMem(bus, addr, size, result);
        updateNZ(cpu, result, size);
    }

    cpu.sr.v = false;
    cpu.sr.c = false;

    return switch (mode) {
        0b000, 0b001 => 4,
        else => 8,
    };
}

/// ANDI - Logical AND with Immediate
/// ANDI #imm, <ea>
pub fn execANDI(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };

    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    // ANDI to CCR
    if (opcode == 0x023C) {
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        const value = @as(u8, @truncate(imm));
        const ccr = &cpu.sr;

        ccr.c = (ccr.c and ((value & 0x01) != 0));
        ccr.v = (ccr.v and ((value & 0x02) != 0));
        ccr.z = (ccr.z and ((value & 0x04) != 0));
        ccr.n = (ccr.n and ((value & 0x08) != 0));
        ccr.x = (ccr.x and ((value & 0x10) != 0));

        return 20;
    }

    // ANDI to SR
    if (opcode == 0x027C) {
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        const old_s = cpu.sr.s;
        cpu.sr.set(cpu.sr.get() & imm);
        const new_s = cpu.sr.s;

        // Handle supervisor/user mode transition
        if (old_s and !new_s) {
            // Transitioning from supervisor to user mode
            cpu.ssp = cpu.a[7];
            cpu.a[7] = cpu.usp;
        } else if (!old_s and new_s) {
            // Transitioning from user to supervisor mode
            cpu.usp = cpu.a[7];
            cpu.a[7] = cpu.ssp;
        }
        return 20;
    }

    // ANDI generic
    const imm: u32 = switch (size) {
        .byte => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value & 0xff);
        },
        .word => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value);
        },
        .long => blk: {
            const value = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk value;
        },
    };

    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b001) return parent.illegalInstruction(cpu, bus, opcode, "ANDI to An");
    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const result = old & imm;
        writeEA(cpu, bus, ea, size, result);
        updateNZ(cpu, result, size);
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const result = old & imm;
        writeMem(bus, addr, size, result);
        updateNZ(cpu, result, size);
    }

    cpu.sr.v = false;
    cpu.sr.c = false;

    return switch (mode) {
        0b000, 0b001 => 4,
        else => 8,
    };
}

/// SUBI - Subtract Immediate
pub fn execSUBI(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    const imm: u32 = switch (size) {
        .byte => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value & 0xff);
        },
        .word => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value);
        },
        .long => blk: {
            const value = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk value;
        },
    };

    const ea = EA{ .mode = mode, .reg = reg };

    const mask: u32 = switch (size) {
        .byte => 0xFF,
        .word => 0xFFFF,
        .long => 0xFFFFFFFF,
    };

    const sign_bit: u32 = switch (size) {
        .byte => 0x80,
        .word => 0x8000,
        .long => 0x80000000,
    };

    if (mode == 0b001) return parent.illegalInstruction(cpu, bus, opcode, "SUBI to An");
    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const old_masked = old & mask;
        const imm_masked = imm & mask;
        const result = (old_masked -% imm_masked) & mask;
        const carry = imm_masked > old_masked;
        const overflow = ((old_masked ^ imm_masked) & (old_masked ^ result) & sign_bit) != 0;
        writeEA(cpu, bus, ea, size, result);
        updateNZ(cpu, result, size);
        cpu.sr.c = carry;
        cpu.sr.x = carry;
        cpu.sr.v = overflow;
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const old_masked = old & mask;
        const imm_masked = imm & mask;
        const result = (old_masked -% imm_masked) & mask;
        const carry = imm_masked > old_masked;
        const overflow = ((old_masked ^ imm_masked) & (old_masked ^ result) & sign_bit) != 0;
        writeMem(bus, addr, size, result);
        updateNZ(cpu, result, size);
        cpu.sr.c = carry;
        cpu.sr.x = carry;
        cpu.sr.v = overflow;
    }

    if (mode == 0b000) {
        return switch (size) {
            .byte, .word => 8,
            .long => 14,
        };
    }

    // mémoire
    const base: u32 = switch (size) {
        .byte, .word => 12,
        .long => 20,
    };

    return base + eaCycleCost(mode, reg, size);
}

/// ADDI - Add Immediate
pub fn execADDI(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };

    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    const imm: u32 = switch (size) {
        .byte => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value & 0xff);
        },
        .word => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value);
        },
        .long => blk: {
            const value = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk value;
        },
    };

    const ea = EA{ .mode = mode, .reg = reg };

    const mask: u32 = switch (size) {
        .byte => 0xFF,
        .word => 0xFFFF,
        .long => 0xFFFFFFFF,
    };

    const sign_bit: u32 = switch (size) {
        .byte => 0x80,
        .word => 0x8000,
        .long => 0x80000000,
    };

    if (mode == 0b001) return parent.illegalInstruction(cpu, bus, opcode, "ADDI to An");
    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const old_masked = old & mask;
        const imm_masked = imm & mask;
        const result = (old_masked +% imm_masked) & mask;
        const carry = (@as(u64, old_masked) + @as(u64, imm_masked)) > mask;
        const overflow = ((~(old_masked ^ imm_masked)) & (old_masked ^ result) & sign_bit) != 0;
        writeEA(cpu, bus, ea, size, result);
        updateNZ(cpu, result, size);
        cpu.sr.c = carry;
        cpu.sr.x = carry;
        cpu.sr.v = overflow;
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const old_masked = old & mask;
        const imm_masked = imm & mask;
        const result = (old_masked +% imm_masked) & mask;
        const carry = (@as(u64, old_masked) + @as(u64, imm_masked)) > mask;
        const overflow = ((~(old_masked ^ imm_masked)) & (old_masked ^ result) & sign_bit) != 0;
        writeMem(bus, addr, size, result);
        updateNZ(cpu, result, size);
        cpu.sr.c = carry;
        cpu.sr.x = carry;
        cpu.sr.v = overflow;
    }

    // Cycles

    if (mode == 0b000) {
        return switch (size) {
            .byte, .word => 8,
            .long => 14,
        };
    }

    if (mode == 0b001) {
        return parent.illegalInstruction(cpu, bus, opcode, "ADDI to An");
    }

    // mémoire
    const base: u32 = switch (size) {
        .byte, .word => 12,
        .long => 20,
    };

    return base + eaCycleCost(mode, reg, size);
}

/// EORI - Exclusive OR with Immediate
pub fn execEORI(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };

    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    // EORI to CCR
    if (opcode == 0x0A3C) {
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        const value = @as(u8, @truncate(imm));
        const ccr = @as(u8, @truncate(cpu.sr.get()));
        const new_ccr = (ccr ^ value) & 0x1F;
        cpu.sr.set((cpu.sr.get() & 0xFFE0) | new_ccr);
        return 20;
    }

    // EORI to SR
    if (opcode == 0x0A7C) {
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        const old_s = cpu.sr.s;
        cpu.sr.set(cpu.sr.get() ^ imm);
        const new_s = cpu.sr.s;

        // Handle supervisor/user mode transition
        if (old_s and !new_s) {
            // Transitioning from supervisor to user mode
            cpu.ssp = cpu.a[7];
            cpu.a[7] = cpu.usp;
        } else if (!old_s and new_s) {
            // Transitioning from user to supervisor mode
            cpu.usp = cpu.a[7];
            cpu.a[7] = cpu.ssp;
        }
        return 20;
    }

    // EORI generic
    const imm: u32 = switch (size) {
        .byte => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value & 0xff);
        },
        .word => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value);
        },
        .long => blk: {
            const value = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk value;
        },
    };

    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b001) return parent.illegalInstruction(cpu, bus, opcode, "EORI to An");
    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const result = old ^ imm;
        writeEA(cpu, bus, ea, size, result);
        updateNZ(cpu, result, size);
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const result = old ^ imm;
        writeMem(bus, addr, size, result);
        updateNZ(cpu, result, size);
    }

    cpu.sr.v = false;
    cpu.sr.c = false;

    return switch (mode) {
        0b000 => 8,
        else => 12,
    };
}

/// CMPI - Compare Immediate
pub fn execCMPI(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    const imm: u32 = switch (size) {
        .byte => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value & 0xff);
        },
        .word => blk: {
            const value = bus.read16(cpu.pc);
            cpu.pc += 2;
            break :blk @as(u32, value);
        },
        .long => blk: {
            const value = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk value;
        },
    };

    const ea = EA{ .mode = mode, .reg = reg };
    const old = readEA(cpu, bus, ea, size);

    const mask: u32 = switch (size) {
        .byte => 0xFF,
        .word => 0xFFFF,
        .long => 0xFFFFFFFF,
    };

    const sign_bit: u32 = switch (size) {
        .byte => 0x80,
        .word => 0x8000,
        .long => 0x80000000,
    };

    const result = ((old & mask) -% (imm & mask)) & mask;

    cpu.sr.z = result == 0;
    cpu.sr.n = (result & sign_bit) != 0;
    cpu.sr.c = (imm & mask) > (old & mask);
    cpu.sr.v = (((old & mask) ^ (imm & mask)) & ((old & mask) ^ result) & sign_bit) != 0;

    if (mode == 0b000) {
        return switch (size) {
            .byte, .word => 8,
            .long => 14,
        };
    }

    if (mode == 0b001) {
        return parent.illegalInstruction(cpu, bus, opcode, "ADDI to An");
    }

    // mémoire
    const base: u32 = switch (size) {
        .byte, .word => 12,
        .long => 20,
    };

    return base + eaCycleCost(mode, reg, size);
}

// ============================================
// BIT OPERATIONS
// ============================================

const BitOp = enum { btst, bchg, bclr, bset };

pub fn execBitOp(cpu: *Cpu, bus: anytype, opcode: u16, op: BitOp) u32 {
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    // Détermine le numéro du bit à tester
    const bit_num: u32 = if ((opcode & 0x0100) != 0) blk: {
        // Bit depuis registre (Dn)
        const src_reg: u3 = @truncate(opcode >> 9);
        break :blk cpu.d[src_reg];
    } else blk: {
        // Bit depuis valeur immédiate
        const imm = bus.read16(cpu.pc);
        cpu.pc += 2;
        break :blk @as(u32, imm & 0xFF);
    };

    if (mode == 0b000) {
        // Registre data (32 bits)
        const shift: u5 = @truncate(bit_num & 0x1F);
        const mask: u32 = @as(u32, 1) << shift;
        const val = cpu.d[reg];
        cpu.sr.z = (val & mask) == 0;

        switch (op) {
            .btst => {},
            .bchg => cpu.d[reg] = val ^ mask,
            .bclr => cpu.d[reg] = val & ~mask,
            .bset => cpu.d[reg] = val | mask,
        }

        return switch (op) {
            .btst => if ((opcode & 0x0100) != 0) @as(u32, 6) else 10,
            .bchg => if ((opcode & 0x0100) != 0) @as(u32, 8) else 12,
            .bclr => if ((opcode & 0x0100) != 0) @as(u32, 10) else 14,
            .bset => if ((opcode & 0x0100) != 0) @as(u32, 8) else 12,
        };
    } else if (mode == 0b001) {
        // An — BTST sur An invalide sur 68000, ignore
        std.log.warn("[CPU] BTST sur An invalide", .{});
        return 4;
    } else {
        // Mémoire (8 bits)
        const shift: u3 = @truncate(bit_num & 0x07);
        const mask: u8 = @as(u8, 1) << shift;
        const ea = EA{ .mode = mode, .reg = reg };
        const addr = resolveEA(cpu, bus, ea, .byte);
        const val: u8 = @truncate(readMem(bus, addr, .byte));
        cpu.sr.z = (val & mask) == 0;

        switch (op) {
            .btst => {},
            .bchg => writeMem(bus, addr, .byte, @as(u32, val ^ mask)),
            .bclr => writeMem(bus, addr, .byte, @as(u32, val & ~mask)),
            .bset => writeMem(bus, addr, .byte, @as(u32, val | mask)),
        }

        return switch (op) {
            .btst => if ((opcode & 0x0100) != 0) @as(u32, 4) else 8,
            .bchg => if ((opcode & 0x0100) != 0) @as(u32, 8) else 12,
            .bclr => if ((opcode & 0x0100) != 0) @as(u32, 8) else 12,
            .bset => if ((opcode & 0x0100) != 0) @as(u32, 8) else 12,
        };
    }
}

// ============================================
// MOVE OPERATIONS
// ============================================

/// MOVEP - Move Peripheral
pub fn execMOVEP(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg_d: u3 = @truncate(opcode >> 9);
    const reg_a: u3 = @truncate(opcode);
    const opmode: u2 = @truncate(opcode >> 6);
    const deplacement: i16 = @bitCast(bus.read16(cpu.pc));
    cpu.pc += 2;

    const base_addr = cpu.a[reg_a];
    const ea = addSigned(base_addr, deplacement);

    switch (opmode) {
        0b00 => {
            // MOVEP.W Dn, d16(An)
            bus.write8(ea + 0, @truncate(cpu.d[reg_d] >> 8));
            bus.write8(ea + 2, @truncate(cpu.d[reg_d]));
            return 16;
        },
        0b01 => {
            // MOVEP.L Dn, d16(An)
            bus.write8(ea + 0, @truncate(cpu.d[reg_d] >> 24));
            bus.write8(ea + 2, @truncate(cpu.d[reg_d] >> 16));
            bus.write8(ea + 4, @truncate(cpu.d[reg_d] >> 8));
            bus.write8(ea + 6, @truncate(cpu.d[reg_d]));
            return 24;
        },
        0b10 => {
            // MOVEP.W d16(An), Dn
            const a: u32 = bus.read8(ea + 0);
            const b: u32 = bus.read8(ea + 2);
            cpu.d[reg_d] = (a << 8) | b;
            return 16;
        },
        0b11 => {
            // MOVEP.L d16(An), Dn
            const b0: u32 = bus.read8(ea + 0);
            const b1: u32 = bus.read8(ea + 2);
            const b2: u32 = bus.read8(ea + 4);
            const b3: u32 = bus.read8(ea + 6);
            cpu.d[reg_d] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
            return 24;
        },
    }
}

/// MOVEA - Move to Address register
pub fn execMOVEA(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 12);

    const size: Size = switch (size_bits) {
        0b11 => .word,
        0b10 => .long,
        else => .word,
    };

    // MOVEA: destination register An is in bits 11-9, source is an EA
    const dest_reg: u3 = @truncate(opcode >> 9);
    const src_reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);

    const ea = EA{ .mode = mode, .reg = src_reg };
    const value = readEA(cpu, bus, ea, size);

    cpu.a[dest_reg] = switch (size) {
        .word => @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(value)))))),
        .long => value,
        .byte => @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(value)))))),
    };

    return switch (mode) {
        0b000 => 4,
        0b001 => 4,
        0b010 => if (size == .word) 8 else 12,
        0b011 => if (size == .word) 8 else 12,
        0b100 => if (size == .word) 10 else 14,
        0b101 => if (size == .word) 12 else 16,
        0b110 => if (size == .word) 14 else 18,
        0b111 => switch (src_reg) {
            0b000 => if (size == .word) 12 else 16,
            0b001 => if (size == .word) 16 else 20,
            0b010 => if (size == .word) 12 else 16,
            0b011 => if (size == .word) 14 else 18,
            0b100 => if (size == .word) 8 else 12,
            else => 12,
        },
    };
}

/// Compte le nombre de mots d'extension pour un mode d'adressage donné
fn extWordCount(mode: u3, reg: u3) u2 {
    return switch (mode) {
        0b101, 0b110 => 1,
        0b111 => switch (reg) {
            0b000, 0b010, 0b011, 0b100 => 1,
            0b001 => 2,
            else => 0,
        },
        else => 0,
    };
}

/// Écrit le stack frame pour une address error avec SSW explicite
fn writeAddrErrorFrame(cpu: *Cpu, bus: anytype, ssw: u16, access_addr: u32, opcode: u16, saved_pc: u32) void {
    const saved_sr = cpu.sr.get();
    parent.enterSupervisor(cpu);
    cpu.a[7] -%= 14;
    bus.write16(cpu.a[7] + 0, ssw);
    bus.write16(cpu.a[7] + 2, @truncate(access_addr >> 16));
    bus.write16(cpu.a[7] + 4, @truncate(access_addr));
    bus.write16(cpu.a[7] + 6, opcode);
    bus.write16(cpu.a[7] + 8, saved_sr);
    bus.write16(cpu.a[7] + 10, @truncate(saved_pc >> 16));
    bus.write16(cpu.a[7] + 12, @truncate(saved_pc));
    cpu.sr.s = true;
    cpu.sr.t = false;
    cpu.pc = bus.read32(4 * 3);
}

/// Calcule le SSW pour une erreur sur la destination MOVE
/// Le SSW est construit comme suit (d'après l'analyse de MAME):
///   SSW = (frame_opcode & 0xFFE0) | m_ssw
/// où m_ssw = 0x01 (S=0) ou 0x05 (S=1) pour un accès écriture données (DATA write).
/// Le frame_opcode est le mot à next_pc pour PreDec dest, sinon l'opcode réel.
/// C'est le premier mot (offset +0) du frame 16-byte empilé lors d'un address error ou bus error. Sa définition officielle (M68000UM, Figure 8-5) :
/// Bit 15: R/W     (1=lecture, 0=écriture)
/// Bit 14: I/N     (1=instruction, 0=pas instruction)
/// Bits 13-10: réservés (0)
/// Bits 9-8:  FC1, FC0  (bits 1-0 du code fonction)
/// Bits 7-6:  SZ1, SZ0  (taille de l'accès)
/// Bit 5:   TM1      (transfer modifier 1)
/// Bit 4:   TM0      (transfer modifier 0)
/// Bits 3-1:  FC2, FC1, FC0  (code fonction complet)
/// Bit 0:   AE       (address error, toujours 1)
fn moveDestSsw(frame_opcode: u16, s_set: bool) u16 {
    return (frame_opcode & 0xFFE0) | @as(u16, if (s_set) 0x05 else 0x01);
}

/// MOVE - Move Data
pub fn execMOVE(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 12);
    const size: Size = switch (size_bits) {
        0b01 => .byte,
        0b11 => .word,
        0b10 => .long,
        else => .byte,
    };

    const src_mode: u3 = @truncate(opcode >> 3);
    const src_reg: u3 = @truncate(opcode);
    const dst_reg: u3 = @truncate(opcode >> 9);
    const dst_mode: u3 = @truncate(opcode >> 6);
    const dst_ea = EA{ .mode = dst_mode, .reg = dst_reg };
    if (!parent.isDataAlterableEA(dst_ea)) {
        return parent.illegalInstruction(cpu, bus, opcode, "MOVE destination");
    }

    const src_ea = EA{ .mode = src_mode, .reg = src_reg };
    const src_type = decodeEAType(src_mode, src_reg);

    // Longueur totale de l'instruction (mots d'extension source + dest)
    const src_ext = extWordCount(src_mode, src_reg);
    const dst_ext = extWordCount(dst_mode, dst_reg);
    const total_ext_bytes: u32 = (@as(u32, src_ext) + @as(u32, dst_ext)) * 2;
    const insn_entry_pc = cpu.pc;
    const next_pc = insn_entry_pc + total_ext_bytes;

    // === SOURCE READ ===
    const value: u32 = if (src_type == .Dn or src_type == .An or src_type == .Imm) blk: {
        break :blk readEA(cpu, bus, src_ea, size);
    } else blk: {
        const addr = resolveEA(cpu, bus, src_ea, size);
        if (size != .byte and (addr & 1) != 0) {
            const src_saved_pc = if (src_type == .PreDec)
                next_pc
            else if (src_mode == 0b101 or src_mode == 0b110)
                cpu.pc - 2
            else
                cpu.pc;
            parent.addressErrorException(cpu, bus, opcode, addr, src_saved_pc);
            return 50;
        }
        break :blk readMem(bus, addr, size);
    };

    // Mise à jour des flags
    updateNZ(cpu, value, size);
    cpu.sr.v = false;
    cpu.sr.c = false;

    // === ÉCRITURE DESTINATION ===
    const dst_type = decodeEAType(dst_mode, dst_reg);

    if (dst_type == .Dn or dst_type == .An) {
        writeEA(cpu, bus, dst_ea, size, value);
    } else {
        const addr = resolveEA(cpu, bus, dst_ea, size);
        if (size != .byte and (addr & 1) != 0) {
            // Pour PreDec dest, le champ opcode du frame stocke le mot à next_pc
            // (dernier mot préfetché), pas l'opcode réel de l'instruction.
            const dest_is_predec = dst_mode == 0b100;
            const frame_opcode: u16 = if (dest_is_predec) bus.read16(next_pc) else opcode;
            const ssw = moveDestSsw(frame_opcode, cpu.sr.s);
            const dest_saved_pc = next_pc + 2;
            writeAddrErrorFrame(cpu, bus, ssw, addr, frame_opcode, dest_saved_pc);
            return 50;
        }
        writeMem(bus, addr, size, value);
    }

    // Interdire MOVE.b vers An
    if (size == .byte and dst_type == .An) {
        return parent.illegalInstruction(cpu, bus, opcode, "MOVE.b to An");
    }

    // gestion des cycles
    const cycles: u32 = switch (size) {
        .byte, .word => move_bw[@intFromEnum(src_type)][@intFromEnum(dst_type)],
        .long => move_l[@intFromEnum(src_type)][@intFromEnum(dst_type)],
    };

    return cycles;
}
