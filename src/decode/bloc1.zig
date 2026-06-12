const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const writeEA = parent.writeEA;
pub const resolveEA = parent.resolveEA;
pub const updateNZ = parent.updateNZ;
pub const isNegative = parent.isNegative;
pub const maskSize = parent.maskSize;
pub const signBit = parent.signBit;
pub const mergeValue = parent.mergeValue;

const signExtend8 = parent.signExtend8;
const signExtend16 = parent.signExtend16;
const addSigned = parent.addSigned;
const readMem = parent.readMem;
const writeMem = parent.writeMem;
const decodeEAType = parent.decodeEAType;

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const type_instruction: u8 = @truncate(opcode >> 8);

    if ((opcode & 0xFFF8) == 0x4840) {
        return execSWAP(cpu, opcode);
    }

    // MOVE <ea>, SR (opcode & 0xFFC0 == 0x46C0)
    if ((opcode & 0xFFC0) == 0x46C0 and type_instruction == 0x46) {
        return execMOVEtoSR(cpu, bus, opcode);
    }

    // MOVE SR, <ea> (opcode & 0xFFC0 == 0x40C0)
    if ((opcode & 0xFFC0) == 0x40C0 and type_instruction == 0x40) {
        return execMOVEfromSR(cpu, bus, opcode);
    }

    // --- MOVEM detection (must come before TST, JMP/JSR) ---

    // MOVEM (all): opcode pattern 0100 1drx 00mm mrrr where x=bit8
    // Match: (opcode & 0xFB80) == 0x4880
    // Catches $48/$49/$4B/$4D/$4F variants (dr=dir, sz=word/long)
    if ((opcode & 0xFB80) == 0x4880) {
        // EXT.W/L at 0x48C0-0x48CF/Dn-only have priority
        if ((opcode & 0xFFF0) == 0x48C0) return execEXT(cpu, opcode);
        return execMOVEM(cpu, bus, opcode);
    }

    switch (type_instruction) {
        0x40 => return execNEGX(cpu, bus, opcode),
        0x42 => return execCLR(cpu, bus, opcode),
        0x44 => return execNEG(cpu, bus, opcode),
        0x46 => return execNOT(cpu, bus, opcode),
        0x48 => {
            if ((opcode & 0xFFF0) == 0x48C0) return execEXT(cpu, opcode);
            if ((opcode & 0x00C0) == 0x0000) return execNBCD(cpu, bus, opcode);
            if ((opcode & 0x01C0) == 0x0040) return execPEA(cpu, bus, opcode);
            return parent.exception(cpu, bus, 0x10, opcode, "bloc1");
        },
        0x4A => {
            // ILLEGAL instruction (0x4AFC) — vector 0x10 (4)
            if (opcode == 0x4AFC) return parent.exception(cpu, bus, 4, opcode, "ILLEGAL");
            const size_bits: u2 = @truncate(opcode >> 6);
            if (size_bits == 0b11) return execTAS(cpu, bus, opcode);
            return execTST(cpu, bus, opcode);
        },
        0x41, 0x43, 0x45, 0x47, 0x49, 0x4B, 0x4D, 0x4F => {
            // Distinguish LEA (bits 8-6=111) from CHK (bits 8-6=110)
            if ((opcode & 0x01C0) == 0x01C0) return execLEA(cpu, bus, opcode);
            if ((opcode & 0x01C0) == 0x0180) return execCHK(cpu, bus, opcode);
            return parent.exception(cpu, bus, 0x10, opcode, "bloc1");
        },
        0x4E => {
            const low_byte: u8 = @truncate(opcode);
            if (opcode == 0x4E70) return execRESET(cpu, bus);
            if (opcode == 0x4E71) return execNOP(cpu, bus);
            if (opcode == 0x4E72) return execSTOP(cpu, bus);
            if (opcode == 0x4E73) return execRTE(cpu, bus);
            if (opcode == 0x4E75) return execRTS(cpu, bus);
            if (opcode == 0x4E76) return execTRAPV(cpu, bus);
            if (opcode == 0x4E77) return execRTR(cpu, bus);
            if (low_byte & 0x80 != 0) {
                if (low_byte & 0x40 != 0) {
                    return execJMP(cpu, bus, opcode);
                } else {
                    return execJSR(cpu, bus, opcode);
                }
            }
            if ((opcode & 0xFFF0) == 0x4E40) return execTRAP(cpu, bus, opcode);
            if ((opcode & 0xFFF8) == 0x4E50) return execLINK(cpu, bus, opcode);
            if ((opcode & 0xFFF8) == 0x4E58) return execUNLK(cpu, bus, opcode);
            if ((opcode & 0xFFF8) == 0x4E60) return execMOVEUSP(cpu, bus, opcode);
            if ((opcode & 0xFFF8) == 0x4E68) return execMOVEUSP(cpu, bus, opcode);
            return parent.exception(cpu, bus, 0x10, opcode, "bloc1");
        },
        else => {
            return parent.exception(cpu, bus, 0x10, opcode, "bloc1");
        },
    }
}

/// NEGX - Negate with Extend
/// NEGX <ea>
/// dst = 0 - dst - X
pub fn execNEGX(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };

    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    const mask = maskSize(0xFFFFFFFF, size);
    const x_val: u32 = if (cpu.sr.x) 1 else 0;

    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const result = (0 -% old -% x_val) & mask;
        if (result != 0) cpu.sr.z = false;
        cpu.sr.n = isNegative(result, size);
        cpu.sr.v = (old & result & signBit(size)) != 0;
        cpu.sr.c = (old != 0) or cpu.sr.x;
        cpu.sr.x = cpu.sr.c;
        writeEA(cpu, bus, ea, size, result);
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const result = (0 -% old -% x_val) & mask;
        if (result != 0) cpu.sr.z = false;
        cpu.sr.n = isNegative(result, size);
        cpu.sr.v = (old & result & signBit(size)) != 0;
        cpu.sr.c = (old != 0) or cpu.sr.x;
        cpu.sr.x = cpu.sr.c;
        writeMem(bus, addr, size, result);
    }

    return switch (mode) {
        0b000 => if (size == .long) 6 else 4,
        0b001 => 4,
        0b010 => if (size == .long) 12 else 8,
        0b011 => if (size == .long) 12 else 8,
        0b100 => if (size == .long) 14 else 10,
        0b101 => if (size == .long) 16 else 12,
        0b110 => if (size == .long) 18 else 14,
        0b111 => switch (reg) {
            0b000 => if (size == .long) 16 else 12,
            0b001 => if (size == .long) 20 else 16,
            0b010 => if (size == .long) 16 else 12,
            0b011 => if (size == .long) 18 else 14,
            else => 12,
        },
    };
}

/// CLR - Clear operand
/// CLR <ea>
pub fn execCLR(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    writeEA(cpu, bus, ea, size, 0);

    cpu.sr.n = false;
    cpu.sr.z = true;
    cpu.sr.v = false;
    cpu.sr.c = false;

    return switch (mode) {
        0b000 => if (size == .long) 6 else 4,
        0b001 => 4,
        0b010 => if (size == .long) 12 else 8,
        0b011 => if (size == .long) 12 else 8,
        0b100 => if (size == .long) 14 else 10,
        0b101 => if (size == .long) 16 else 12,
        0b110 => if (size == .long) 18 else 14,
        0b111 => switch (reg) {
            0b000 => if (size == .long) 16 else 12,
            0b001 => if (size == .long) 20 else 16,
            0b010 => if (size == .long) 16 else 12,
            0b011 => if (size == .long) 18 else 14,
            else => 12,
        },
    };
}

/// NEG - Negate
/// NEG <ea>
/// dst = 0 - dst
pub fn execNEG(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    const mask = maskSize(0xFFFFFFFF, size);

    if (mode == 0b000 or mode == 0b001) {
        const old = readEA(cpu, bus, ea, size);
        const result = (0 -% old) & mask;
        updateNZ(cpu, result, size);
        cpu.sr.v = (old != 0) and ((old & signBit(size)) != 0);
        cpu.sr.c = (old != 0);
        cpu.sr.x = cpu.sr.c;
        writeEA(cpu, bus, ea, size, result);
    } else {
        const addr = resolveEA(cpu, bus, ea, size);
        const old = readMem(bus, addr, size);
        const result = (0 -% old) & mask;
        updateNZ(cpu, result, size);
        cpu.sr.v = (old != 0) and ((old & signBit(size)) != 0);
        cpu.sr.c = (old != 0);
        cpu.sr.x = cpu.sr.c;
        writeMem(bus, addr, size, result);
    }

    return switch (mode) {
        0b000 => if (size == .long) 6 else 4,
        0b001 => 4,
        0b010 => if (size == .long) 12 else 8,
        0b011 => if (size == .long) 12 else 8,
        0b100 => if (size == .long) 14 else 10,
        0b101 => if (size == .long) 16 else 12,
        0b110 => if (size == .long) 18 else 14,
        0b111 => switch (reg) {
            0b000 => if (size == .long) 16 else 12,
            0b001 => if (size == .long) 20 else 16,
            0b010 => if (size == .long) 16 else 12,
            0b011 => if (size == .long) 18 else 14,
            else => 12,
        },
    };
}

/// NOT - Logical Not
/// NOT <ea>
/// dst = ~dst
/// p 253
/// note: Le 68000 a une queue de prefetch de 3 mots.
/// Pendant qu'il exécute l'opcode, il lit le mot suivant sur le bus en parallèle si le bus est libre.
/// Ça avance le PC même si l'instruction n'a pas encore « demandé » ce mot.
/// Donc si une instruction fait 2 mots (opcode + extension) :
/// 1. Fetch opcode → PC += 2 (bus occupé)
/// 2. Prefetch → PC += 2 (bus libre pendant que le CPU décode)
/// 3. L'instruction consomme l'extension depuis la queue → PC ne bouge pas
pub fn execNOT(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const size_bits: u2 = @truncate(opcode >> 6);
    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        else => unreachable, // selon la doc off pas de 11
    };
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    const mask = maskSize(0xFFFFFFFF, size);

    // mode Dn donc pas besoin de passer par resolveEA
    if (mode == 0b000) {
        const old = readEA(cpu, bus, ea, size);
        const result = (~old) & mask;
        updateNZ(cpu, result, size);
        cpu.sr.v = false;
        cpu.sr.c = false;
        writeEA(cpu, bus, ea, size, result);
    } else {
        const saved_pc = cpu.pc;
        const addr = resolveEA(cpu, bus, ea, size);
        const exception_pc: u32 = if (mode == 0b111)
            cpu.pc
        else if (mode == 0b100 and size == .word)
            saved_pc + 2
        else
            saved_pc;
        if (size != .byte and (addr & 1) != 0) {
            if (mode == 0b011 and size == .long) {
                cpu.a[reg] -%= 4;
            }
            parent.addressErrorException(cpu, bus, opcode, addr, exception_pc);
            return 50;
        }
        const old = readMem(bus, addr, size);
        const result = (~old) & mask;
        updateNZ(cpu, result, size);
        cpu.sr.v = false;
        cpu.sr.c = false;
        writeMem(bus, addr, size, result);
    }

    //  cycle p117
    // cette base sera à normaliser car utile pour les opcodes ayant 12/16/24 colonne mémoire
    const not_base: u32 = switch (size) {
        .byte => 12,
        .word => 16,
        .long => 24,
    };
    return switch (mode) {
        0b000 => switch (size) {
            .byte => 8,
            .word => 8,
            .long => 10,
        },
        0b010, 0b011, 0b100, 0b101, 0b110, 0b111 => not_base + parent.eaCycleCost(mode, reg, size),
        else => unreachable,
    };
}

/// EXT.W/L Dn — sign-extend byte→word or word→long
pub fn execEXT(cpu: *Cpu, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const is_long = (opcode & 0x0008) != 0;

    if (is_long) {
        const w: u16 = @truncate(cpu.d[reg]);
        cpu.d[reg] = @as(u32, @bitCast(signExtend16(w)));
        updateNZ(cpu, cpu.d[reg], .long);
    } else {
        const b: u8 = @truncate(cpu.d[reg]);
        const w: u16 = @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(b)))));
        cpu.d[reg] = (cpu.d[reg] & 0xFFFF0000) | w;
        updateNZ(cpu, cpu.d[reg], .word);
    }
    cpu.sr.v = false;
    cpu.sr.c = false;
    return 4;
}

/// TRAP #n — software trap, push PC/SR and jump to vector
pub fn execTRAP(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const trap_num: u4 = @truncate(opcode);
    const vector: u32 = 0x80 + @as(u32, trap_num) * 4;

    const saved_pc = cpu.pc;
    const saved_sr = cpu.sr.get();

    parent.enterSupervisor(cpu);

    cpu.a[7] -%= 6;
    bus.write16(cpu.a[7], saved_sr);
    bus.write32(cpu.a[7] + 2, saved_pc);

    cpu.sr.s = true;
    cpu.sr.t = false;

    cpu.pc = bus.read32(vector);
    return 34;
}

/// RTE — return from exception: pop SR then PC
pub fn execRTE(cpu: *Cpu, bus: anytype) u32 {
    const old_sr = bus.read16(cpu.a[7]) & 0xE07F;
    cpu.a[7] +%= 2;
    const ret_pc = bus.read32(cpu.a[7]);
    cpu.pc = ret_pc;
    cpu.a[7] +%= 4;
    cpu.sr.set(old_sr);
    parent.leaveSupervisor(cpu);
    return 20;
}

/// STOP — load immediate into SR and halt
pub fn execSTOP(cpu: *Cpu, bus: anytype) u32 {
    if (!cpu.sr.s) {
        return parent.exception(cpu, bus, 0x08, 0x4E72, "STOP");
    }
    const imm = bus.read16(cpu.pc);
    const old_s = cpu.sr.s;
    cpu.sr.set(imm & 0xA71F);
    const new_s = cpu.sr.s;
    if (old_s and !new_s) {
        cpu.ssp = cpu.a[7];
        cpu.a[7] = cpu.usp;
    } else if (!old_s and new_s) {
        cpu.usp = cpu.a[7];
        cpu.a[7] = cpu.ssp;
    }
    cpu.halted = true;
    cpu.pc -= 2;
    return 4;
}

/// LINK An, #disp — push An, set An=SP, decrement SP by disp
pub fn execLINK(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const an: u3 = @truncate(opcode);
    const disp = signExtend16(bus.read16(cpu.pc));
    cpu.pc += 2;

    cpu.a[7] -%= 4;
    bus.write32(cpu.a[7], cpu.a[an]);
    cpu.a[an] = cpu.a[7];
    cpu.a[7] = addSigned(cpu.a[7], disp);
    return 16;
}

/// UNLK An — set SP=An, pop An from stack
pub fn execUNLK(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const an: u3 = @truncate(opcode);

    cpu.a[7] = cpu.a[an];
    cpu.a[an] = bus.read32(cpu.a[7]);
    cpu.a[7] +%= 4;
    return 12;
}

/// MOVE USP, An / MOVE An, USP — transfer between USP and An
pub fn execMOVEUSP(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    _ = bus;
    const an: u3 = @truncate(opcode);
    const to_usp = (opcode & 0x0008) != 0;

    if (to_usp) {
        cpu.usp = cpu.a[an];
    } else {
        cpu.a[an] = cpu.usp;
    }
    return 4;
}

/// SWAP Dn
/// Échange les mots haut et bas du registre donnée.
pub fn execSWAP(cpu: *Cpu, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const value = cpu.d[reg];
    const result = (value << 16) | (value >> 16);

    cpu.d[reg] = result;
    cpu.sr.n = (result & 0x8000_0000) != 0;
    cpu.sr.z = result == 0;
    cpu.sr.v = false;
    cpu.sr.c = false;

    return 4;
}

/// NBCD - Negate Decimal with Extend
/// NBCD <ea> (byte only, BCD)
/// 0 - dst - X (in BCD decimal)
pub fn execNBCD(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);

    const x_val: u32 = if (cpu.sr.x) 1 else 0;

    if (mode == 0b000) {
        // Data register (byte)
        const val: u8 = @truncate(cpu.d[reg]);
        const res = bcdNegate(val, x_val);
        cpu.d[reg] = (cpu.d[reg] & 0xFFFFFF00) | res.result;
        setFlagsBCD(cpu, res.carry, res.v, res.result);
        return 6;
    }

    // Memory EA (byte only)
    const ea = EA{ .mode = mode, .reg = reg };
    const addr = resolveEA(cpu, bus, ea, .byte);
    const val: u8 = @truncate(readMem(bus, addr, .byte));
    const res = bcdNegate(val, x_val);
    writeMem(bus, addr, .byte, res.result);
    setFlagsBCD(cpu, res.carry, res.v, res.result);

    return switch (mode) {
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

fn bcdNegate(val: u8, x_val: u32) struct { result: u8, carry: bool, v: bool } {
    const lo: u32 = val & 0x0F;
    const hi: u32 = val >> 4;
    const x: u32 = x_val;

    var result: u8 = @truncate((-% val) -% @as(u8, @truncate(x)));

    const lo_borrow: bool = (lo + x > 0);
    if (lo_borrow) {
        result -%= 6;
    }

    const hi_borrow: bool = (hi + @as(u32, @intFromBool(lo_borrow)) > 0);
    if (hi_borrow) {
        result -%= 0x60;
    }

    const bin_result: u8 = @as(u8, @truncate((-% val) -% x));
    const v: bool = ((result ^ bin_result) & bin_result & 0x80) != 0;
    return .{ .result = result, .carry = hi_borrow, .v = v };
}

fn setFlagsBCD(cpu: *Cpu, carry: bool, v: bool, result: u8) void {
    cpu.sr.n = (result & 0x80) != 0;
    if (result != 0) cpu.sr.z = false;
    cpu.sr.v = v;
    cpu.sr.c = carry;
    cpu.sr.x = carry;
}

/// PEA - Push Effective Address
/// PEA <ea>: push 32-bit effective address onto stack
/// Valid EA modes: (An), (d16,An), (d8,An,Xn), abs.W, abs.L, (d16,PC), (d8,PC,Xn)
pub fn execPEA(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const ea = EA{
        .mode = @truncate((opcode >> 3) & 0x7),
        .reg = @truncate(opcode & 0x7),
    };

    const addr = getEAAddress(cpu, bus, ea);
    cpu.a[7] -%= 4;
    bus.write32(cpu.a[7], addr);

    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Indirect => 12,
        .Displ => 12,
        .Index => 14,
        .AbsW, .PcDispl => 12,
        .AbsL => 16,
        .PcIndex => 16,
        else => 12,
    };
}

/// TST - Test instruction
/// TST <ea>
/// Teste la valeur à l'adresse effective et met à jour les flags N, Z, V, C
pub fn execTST(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const size_bits: u2 = @truncate(opcode >> 6);

    const size: Size = switch (size_bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .word,
    };

    const ea = EA{ .mode = mode, .reg = reg };
    const valeur = readEA(cpu, bus, ea, size);

    cpu.sr.n = isNegative(valeur, size);
    cpu.sr.z = (valeur == 0);
    cpu.sr.v = false;
    cpu.sr.c = false;

    const cycles: u32 = switch (decodeEAType(ea.mode, ea.reg)) {
        .Dn, .An => 4,
        .Indirect, .PostInc => if (size == .long) 12 else 8,
        .PreDec => if (size == .long) 14 else 10,
        .Displ => if (size == .long) 16 else 12,
        .Index => if (size == .long) 18 else 14,
        .AbsW, .PcDispl => if (size == .long) 16 else 12,
        .AbsL => if (size == .long) 20 else 16,
        .PcIndex => if (size == .long) 18 else 14,
        else => 12,
    };

    return cycles;
}

/// TAS - Test and Set
/// TAS <ea> (byte only): test byte, set bit 7, write back
pub fn execTAS(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b000) {
        const valeur: u8 = @truncate(cpu.d[reg]);
        cpu.sr.n = (valeur & 0x80) != 0;
        cpu.sr.z = valeur == 0;
        cpu.sr.v = false;
        cpu.sr.c = false;
        cpu.d[reg] = (cpu.d[reg] & 0xFFFFFF00) | @as(u32, valeur | 0x80);
    } else {
        const addr = resolveEA(cpu, bus, ea, .byte);
        const valeur: u8 = @truncate(readMem(bus, addr, .byte));
        cpu.sr.n = (valeur & 0x80) != 0;
        cpu.sr.z = valeur == 0;
        cpu.sr.v = false;
        cpu.sr.c = false;
        writeMem(bus, addr, .byte, @as(u32, valeur | 0x80));
    }

    return switch (mode) {
        0b000 => 6,
        0b010 => 14,
        0b011 => 14,
        0b100 => 16,
        0b101 => 18,
        0b110 => 22,
        0b111 => switch (reg) {
            0b000 => 16,
            0b001 => 20,
            else => 12,
        },
        else => 12,
    };
}

/// CHK - Check Register Against Bounds
/// CHK <ea>, Dn: if Dn(word) < 0 or Dn(word) > <ea>(word) → exception vector 0x18
pub fn execCHK(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const dn: u3 = @truncate(opcode >> 9);
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const ea = EA{ .mode = mode, .reg = reg };

    const eatype = parent.decodeEAType(mode, reg);
    const is_mem = eatype != .Dn and eatype != .An;
    const is_imm = mode == 0b111 and reg == 0b100;

    var bound: u16 = 0;
    var exception_pc: u32 = 0;
    if (is_imm) {
        bound = @truncate(readEA(cpu, bus, ea, .word));
    } else if (is_mem) {
        const saved_pc = cpu.pc;
        const addr = resolveEA(cpu, bus, ea, .word);
        exception_pc = if (mode == 0b100)
            saved_pc +% 2
        else if (mode == 0b111)
            if (reg == 0b010 or reg == 0b011) saved_pc else cpu.pc
        else
            saved_pc;
        if ((addr & 1) != 0) {
            parent.addressErrorException(cpu, bus, opcode, addr, exception_pc);
            return 50;
        }
        bound = @truncate(readMem(bus, addr, .word));
    } else {
        bound = @truncate(readEA(cpu, bus, ea, .word));
    }

    const test_u16: u16 = @truncate(cpu.d[dn]);
    const test_s16: i16 = @bitCast(test_u16);
    const bound_s16: i16 = @bitCast(bound);

    if (test_s16 < 0 or test_s16 > bound_s16) {
        cpu.sr.n = test_s16 < 0;
        cpu.sr.z = false;
        cpu.sr.v = false;
        cpu.sr.c = false;

        const saved_pc = cpu.pc;
        const saved_sr = cpu.sr.get();

        parent.enterSupervisor(cpu);

        cpu.a[7] -%= 6;
        bus.write16(cpu.a[7], saved_sr);
        bus.write32(cpu.a[7] + 2, saved_pc);

        cpu.sr.s = true;
        cpu.sr.t = false;

        cpu.pc = bus.read32(0x18);
        return 40;
    }

    return switch (mode) {
        0b000 => 10,
        0b001 => 10,
        0b010 => 14,
        0b011 => 14,
        0b100 => 16,
        0b101 => 18,
        0b110 => 22,
        0b111 => switch (reg) {
            0b000 => 16,
            0b001 => 20,
            0b010 => 16,
            0b011 => 20,
            0b100 => 14,
            0b101, 0b110, 0b111 => 14,
        },
    };
}

/// LEA — Load Effective Address
/// Format : 0100 nnn1 11 mmm rrr
/// Charge l'adresse effective (pas la valeur) dans An
pub fn execLEA(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const an: u3 = @truncate((opcode >> 9) & 0x7); // registre destination
    const ea = EA{
        .mode = @truncate((opcode >> 3) & 0x7),
        .reg = @truncate(opcode & 0x7),
    };

    // LEA calcule l'adresse, pas la valeur pointée
    // On utilise getEAAddress() et non readEA()
    const addr = getEAAddress(cpu, bus, ea);
    cpu.a[an] = addr;

    // Cycles selon le mode EA (valeurs 68000)
    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Indirect => 4,
        .Displ => 8,
        .Index => 12,
        .AbsW, .PcDispl => 8,
        .AbsL, .PcIndex => 12,
        else => 4,
    };
}

fn getEAAddress(cpu: *Cpu, bus: anytype, ea: EA) u32 {
    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Indirect, .PostInc => cpu.a[ea.reg],

        .Displ => blk: {
            const disp = signExtend16(bus.read16(cpu.pc));
            cpu.pc += 2;
            break :blk addSigned(cpu.a[ea.reg], disp);
        },

        .Index => blk: {
            const ext = bus.read16(cpu.pc);
            cpu.pc += 2;
            const disp = signExtend8(@truncate(ext));
            const index_reg = (ext >> 12) & 0x7;
            const is_addr = ((ext >> 15) & 1) == 1;
            const is_long = ((ext >> 11) & 1) == 1;
            var index_val: u32 = if (is_addr) cpu.a[index_reg] else cpu.d[index_reg];
            if (!is_long) {
                index_val = @bitCast(signExtend16(@truncate(index_val)));
            }
            break :blk addSigned(addSigned(cpu.a[ea.reg], disp), @bitCast(index_val));
        },

        .AbsW => blk: {
            const addr: i32 = signExtend16(bus.read16(cpu.pc));
            cpu.pc += 2;
            break :blk @bitCast(addr);
        },

        .AbsL => blk: {
            const addr = bus.read32(cpu.pc);
            cpu.pc += 4;
            break :blk addr;
        },

        .PcDispl => blk: {
            const pc_at_ext = cpu.pc;
            const disp = signExtend16(bus.read16(cpu.pc));
            cpu.pc += 2;
            break :blk addSigned(pc_at_ext, disp);
        },

        .PcIndex => blk: {
            const pc_at_ext = cpu.pc;
            const ext = bus.read16(cpu.pc);
            cpu.pc += 2;
            const disp = signExtend8(@truncate(ext));
            const index_reg = (ext >> 12) & 0x7;
            const is_addr = ((ext >> 15) & 1) == 1;
            const is_long = ((ext >> 11) & 1) == 1;
            var index_val: u32 = if (is_addr) cpu.a[index_reg] else cpu.d[index_reg];
            if (!is_long) {
                index_val = @bitCast(signExtend16(@truncate(index_val)));
            }
            break :blk addSigned(addSigned(pc_at_ext, disp), @bitCast(index_val));
        },

        else => inval: {
            std.log.err("[CPU] getEAAddress: invalid EA mode={b:0>3} reg={b:0>3} @ PC=0x{X:0>6}", .{ ea.mode, ea.reg, cpu.pc });
            break :inval cpu.pc;
        },
    };
}

pub fn execNOP(cpu: *Cpu, bus: anytype) u32 {
    _ = cpu;
    _ = bus;
    return 4;
}

/// JMP — Jump
/// Saute à l'adresse effective (sans sauvegarder PC)
pub fn execJMP(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const ea = EA{
        .mode = @truncate((opcode >> 3) & 0x7),
        .reg = @truncate(opcode & 0x7),
    };
    const target = getEAAddress(cpu, bus, ea);
    cpu.pc = target;

    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Indirect => 8,
        .Displ => 10,
        .Index => 14,
        .AbsW, .PcDispl => 10,
        .AbsL => 12,
        .PcIndex => 14,
        else => 8,
    };
}

/// JSR — Jump to Subroutine
/// Pousse PC (retour) sur la pile, puis saute à l'adresse effective
pub fn execJSR(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const ea = EA{
        .mode = @truncate((opcode >> 3) & 0x7),
        .reg = @truncate(opcode & 0x7),
    };
    const target = getEAAddress(cpu, bus, ea);

    // cpu.pc pointe maintenant sur l'instruction suivante (après les mots d'extension)
    cpu.a[7] -%= 4;
    bus.write32(cpu.a[7], cpu.pc);
    cpu.pc = target;

    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Indirect => 16,
        .Displ => 18,
        .Index => 22,
        .AbsW, .PcDispl => 18,
        .AbsL => 20,
        .PcIndex => 22,
        else => 16,
    };
}

/// RTS — Return from Subroutine
/// Pop PC depuis la pile
pub fn execRTS(cpu: *Cpu, bus: anytype) u32 {
    const return_addr = bus.read32(cpu.a[7]);
    cpu.a[7] +%= 4;

    if ((return_addr & 1) != 0) {
        return parent.exception(cpu, bus, 0x03, 0x4E75, "RTS Address Error");
    }

    cpu.pc = return_addr;
    return 16;
}

/// RESET — Reset external peripherals
pub fn execRESET(cpu: *Cpu, bus: anytype) u32 {
    _ = cpu;
    _ = bus;
    return 132;
}

/// RTR — Return and Restore CCR
pub fn execRTR(cpu: *Cpu, bus: anytype) u32 {
    const ccr_val = bus.read16(cpu.a[7]) & 0x00FF;
    cpu.a[7] +%= 2;
    const return_addr = bus.read32(cpu.a[7]);
    cpu.a[7] +%= 4;
    cpu.sr.set((cpu.sr.get() & 0xFF00) | ccr_val);
    cpu.pc = return_addr;
    return 14;
}

/// TRAPV — Trap if Overflow
pub fn execTRAPV(cpu: *Cpu, bus: anytype) u32 {
    if (cpu.sr.v) {
        const saved_pc = cpu.pc;
        const saved_sr = cpu.sr.get();
        parent.enterSupervisor(cpu);
        cpu.a[7] -%= 6;
        bus.write16(cpu.a[7], saved_sr);
        bus.write32(cpu.a[7] + 2, saved_pc);
        cpu.sr.s = true;
        cpu.sr.t = false;
        cpu.pc = bus.read32(0x1C);
        return 34;
    }
    return 4;
}

/// MOVE <ea>, SR — Move to Status Register
/// Écrit la valeur lue depuis l'EA dans le Status Register
pub fn execMOVEtoSR(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const ea = EA{
        .mode = @truncate((opcode >> 3) & 0x7),
        .reg = @truncate(opcode & 0x7),
    };
    const value = readEA(cpu, bus, ea, .word);
    const old_s = cpu.sr.s;
    cpu.sr.set(@truncate(value));
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

    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Dn, .An => 12,
        .Indirect, .PostInc, .PreDec, .AbsW, .PcDispl, .Imm => 16,
        .Displ => 18,
        .AbsL => 20,
        .Index, .PcIndex => 22,
    };
}

/// MOVE SR, <ea> — Move from Status Register
/// Lit le Status Register et l'écrit dans l'EA destination (mot)
pub fn execMOVEfromSR(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const ea = EA{
        .mode = @truncate((opcode >> 3) & 0x7),
        .reg = @truncate(opcode & 0x7),
    };
    const sr_value = cpu.sr.get();
    writeEA(cpu, bus, ea, .word, sr_value);

    return switch (decodeEAType(ea.mode, ea.reg)) {
        .Dn, .An => 6,
        .Indirect => 8,
        .PostInc, .PreDec => 10,
        .Displ, .AbsW => 12,
        .Index => 14,
        .AbsL => 16,
        else => 12,
    };
}

/// MOVEM — Move Multiple Registers
/// Encoding: 0100 1d s 0 01 MMM RRR + register mask (16-bit) [+ EA extension]
///   d=0: regs→mem, d=1: mem→regs
///   s=0: word (sign-extend to 32b for mem→regs), s=1: long
pub fn execMOVEM(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const to_mem = (opcode & 0x0400) == 0;
    const is_long = (opcode & 0x0040) != 0; // bit 6 = 1 → long, 0 → word
    const ea_mode: u3 = @truncate(opcode >> 3);
    const ea_reg: u3 = @truncate(opcode);

    const mask = bus.read16(cpu.pc);
    cpu.pc += 2;
    const saved_pc = cpu.pc + 2; // account for post-instruction prefetch read (MAME advances PC past next word)
    const n = @popCount(mask);

    if (to_mem) {
        return execMOVEMtoMem(cpu, bus, mask, n, is_long, ea_mode, ea_reg, opcode, saved_pc);
    } else {
        return execMOVEMfromMem(cpu, bus, mask, n, is_long, ea_mode, ea_reg, opcode, saved_pc);
    }
}

fn checkAddrError(cpu: *Cpu, bus: anytype, addr: u32, size: Size, opcode: u16, saved_pc: u32) bool {
    _ = cpu;
    _ = bus;
    _ = addr;
    _ = size;
    _ = opcode;
    _ = saved_pc;
    return false;
}

fn execMOVEMtoMem(cpu: *Cpu, bus: anytype, mask: u16, n: u32, is_long: bool, ea_mode: u3, ea_reg: u3, opcode: u16, saved_pc: u32) u32 {
    const size: Size = if (is_long) .long else .word;
    const dec = if (is_long) @as(u32, 4) else @as(u32, 2);

    if (ea_mode == 0b100) {
        // -(An): per 68000 spec, bit i selects register i (bits 0-7=D0-D7, 8-15=A0-A7)
        // Scan MSB-first (15→0) so A7 is stored first at highest address, D0 last at lowest
        const original_an = cpu.a[ea_reg];
        var i: u4 = 15;
        while (true) {
            if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
                cpu.a[ea_reg] -%= dec;
                if (checkAddrError(cpu, bus, cpu.a[ea_reg], size, opcode, saved_pc)) return 8 + 8 * n;
                const val: u32 = if (i >= 8)
                    (if (i - 8 == ea_reg) original_an else cpu.a[i - 8])
                else
                    cpu.d[i];
                writeMem(bus, cpu.a[ea_reg], size, val);
            }
            if (i == 0) break;
            i -= 1;
        }
    } else {
        // Tous les autres modes : adresse croissante, scan bit 0→15
        const ea = EA{ .mode = ea_mode, .reg = ea_reg };
        var addr = getEAAddress(cpu, bus, ea);
        for (0..16) |i| {
            if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
                if (checkAddrError(cpu, bus, addr, size, opcode, saved_pc)) return 8 + 8 * n;
                const val: u32 = if (i >= 8) cpu.a[i - 8] else cpu.d[i];
                writeMem(bus, addr, size, val);
                addr += dec;
            }
        }
        if (ea_mode == 0b011) cpu.a[ea_reg] = addr;
    }

    const base_cycles: u32 = switch (decodeEAType(ea_mode, ea_reg)) {
        .Indirect, .PreDec => 8,
        .Displ => 12,
        .Index => 14,
        .AbsL => 16,
        else => 12,
    };
    const per_reg: u32 = if (is_long) 8 else 4;
    return base_cycles + per_reg * n;
}

fn execMOVEMfromMem(cpu: *Cpu, bus: anytype, mask: u16, n: u32, is_long: bool, ea_mode: u3, ea_reg: u3, opcode: u16, saved_pc: u32) u32 {
    const size: Size = if (is_long) .long else .word;
    const inc: u32 = if (is_long) 4 else 2;
    // Standard 68000 mapping: bit 0=D0, bit 1=D1, ..., bit 7=D7, bit 8=A0, ..., bit 15=A7

    if (ea_mode == 0b100) {
        // -(An): scan MSB-first (15→0), decrement An before each load
        var i: u4 = 15;
        while (true) {
            if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
                cpu.a[ea_reg] -%= inc;
                if (checkAddrError(cpu, bus, cpu.a[ea_reg], size, opcode, saved_pc)) return 10 + 4 * n;
                const raw = readMem(bus, cpu.a[ea_reg], size);
                const val: u32 = if (is_long) raw else @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(raw)))))));
                const ptr: *u32 = if (i >= 8) &cpu.a[i - 8] else &cpu.d[i];
                ptr.* = val;
            }
            if (i == 0) break;
            i -= 1;
        }
    } else if (ea_mode == 0b011) {
        // (An)+: scan LSB-first (0→15), load from addr, increment An after each load
        var addr = cpu.a[ea_reg];
        for (0..16) |i| {
            if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
                if (checkAddrError(cpu, bus, addr, size, opcode, saved_pc)) return 12 + 4 * n;
                const raw = readMem(bus, addr, size);
                const val: u32 = if (is_long) raw else @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(raw)))))));
                const is_addr = i >= 8;
                const target_reg: u3 = if (is_addr) @truncate(i - 8) else @truncate(i);
                const ptr: *u32 = if (is_addr) &cpu.a[target_reg] else &cpu.d[target_reg];
                ptr.* = val;
                addr +%= inc;
            }
        }
        cpu.a[ea_reg] = addr;
    } else {
        // All other modes: compute base address, scan bit 0→15
        const ea = EA{ .mode = ea_mode, .reg = ea_reg };
        var addr = getEAAddress(cpu, bus, ea);
        for (0..16) |i| {
            if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
                if (checkAddrError(cpu, bus, addr, size, opcode, saved_pc)) return 12 + 4 * n;
                const raw = readMem(bus, addr, size);
                const val: u32 = if (is_long) raw else @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(raw)))))));
                const ptr: *u32 = if (i >= 8) &cpu.a[i - 8] else &cpu.d[i];
                ptr.* = val;
                addr +%= inc;
            }
        }
    }

    const base_cycles: u32 = switch (decodeEAType(ea_mode, ea_reg)) {
        .Indirect, .PostInc => 12,
        .PreDec => 10,
        .Displ => 16,
        .Index => 18,
        .AbsW => 16,
        .AbsL => 20,
        .PcDispl => 14,
        .PcIndex => 16,
        else => 16,
    };
    const per_reg: u32 = if (is_long) 8 else 4;
    return base_cycles + per_reg * n;
}
