const std = @import("std");
const Cpu = @import("m68k").Cpu;

// Importer les sous-modules
pub const bloc0 = @import("decode/bloc0.zig");
pub const bloc1 = @import("decode/bloc1.zig");
pub const bloc2 = @import("decode/bloc2.zig");
pub const bloc3 = @import("decode/bloc3.zig");
pub const bloc6 = @import("decode/bloc6.zig");
pub const bloc7 = @import("decode/bloc7.zig");
pub const bloc10 = @import("decode/bloc10.zig");
pub const bloc11 = @import("decode/bloc11.zig");
pub const bloc13 = @import("decode/bloc13.zig");
pub const bloc8 = @import("decode/bloc8.zig"); // OR
pub const blocC = @import("decode/blocC.zig"); // AND
pub const execORI = bloc0.execORI;
pub const execANDI = bloc0.execANDI;
pub const execSUBI = bloc0.execSUBI;
pub const execADDI = bloc0.execADDI;
pub const execEORI = bloc0.execEORI;
pub const execCMPI = bloc0.execCMPI;
pub const execBitOp = bloc0.execBitOp;
pub const execBTST = bloc0.execBitOp;
pub const execBCHG = bloc0.execBitOp;
pub const execBCLR = bloc0.execBitOp;
pub const execBSET = bloc0.execBitOp;
pub const execMOVEP = bloc0.execMOVEP;
pub const execMOVEA = bloc0.execMOVEA;
pub const execMOVE = bloc0.execMOVE;
pub const execTST = bloc1.execTST;
pub const execLEA = bloc1.execLEA;
pub const execADDQ = bloc2.execADDQ;
pub const execSUB = bloc6.execSUB;
pub const execMOVEQ = bloc7.execMOVEQ;
pub const execADD = bloc13.execADD;
pub const execNOP = bloc1.execNOP;
pub const execJMP = bloc1.execJMP;
pub const execJSR = bloc1.execJSR;
pub const execRTS = bloc1.execRTS;
pub const execRTR = bloc1.execRTR;
pub const execRESET = bloc1.execRESET;
pub const execTRAPV = bloc1.execTRAPV;
pub const execMOVEtoSR = bloc1.execMOVEtoSR;
pub const execMOVEfromSR = bloc1.execMOVEfromSR;
pub const execNEGX = bloc1.execNEGX;
pub const execCLR = bloc1.execCLR;
pub const execNEG = bloc1.execNEG;
pub const execNOT = bloc1.execNOT;
pub const execEXT = bloc1.execEXT;
pub const execTRAP = bloc1.execTRAP;
pub const execRTE = bloc1.execRTE;
pub const execLINK = bloc1.execLINK;
pub const execUNLK = bloc1.execUNLK;
pub const execMOVEUSP = bloc1.execMOVEUSP;
pub const execOR = bloc8.execOR;
pub const execAND = blocC.execAND;
pub const execMULU = blocC.execMULU;
pub const execMULS = blocC.execMULS;
pub const execShiftRotate = bloc10.exec;
pub const execCMP = bloc11.execCMP;
pub const execSUBQ = bloc2.execSUBQ;
pub const execDBcc = bloc2.execDBcc;

// ============================================
// PUBLIC TYPES
// ============================================

pub const Size = enum { byte, word, long };
pub const EA = struct { mode: u3, reg: u3 };

// ============================================
// Routeur
// ============================================

/// Fonction principale d'exécution des instructions
/// Lit l'opcode au PC et dispatch vers le bon bloc
pub fn step(cpu: *Cpu, bus: anytype) u32 {
    // ── Vérifier les interruptions ───────────────────────────
    const irq = bus.getInterruptLevel();
    var vector = cpu.checkInterrupt(bus);
    // suppress VBlank during Soleil decompressor (0x363FC-0x366B0) to
    // prevent stack/output-buffer overlap (decompressor writes to 0xFFF900+,
    // VBlank pushes stack at A7 ~0xFFFFxx).
    const suppressed = (vector != 0 and cpu.pc >= 0x363FC and cpu.pc <= 0x366B0);
    if (suppressed) {
        vector = 0;
    }
    if (vector != 0) {
        const saved_sr = cpu.sr.get();

        enterSupervisor(cpu);
        cpu.sr.s = true;
        cpu.sr.t = false;
        cpu.sr.ipl = irq;

        cpu.a[7] -%= 6;
        bus.write32(cpu.a[7] + 2, cpu.pc);
        bus.write16(cpu.a[7], saved_sr);

        const vec_addr = (@as(u32, 24) + @as(u32, irq)) * 4;
        cpu.pc = bus.read32(vec_addr);
        cpu.halted = false;
        return 44;
    }

    // ── Si CPU est en arrêt (STOP/bus error), ne rien faire ──
    if (cpu.halted or cpu.stopped) {
        return 4;
    }

    // RAM addresses 0xFF0000-0xFFFFFF are valid execution targets
    if (cpu.pc >= 0x400000 and cpu.pc < 0xFF0000) {
        if (comptime @hasField(@TypeOf(bus.*), "unrestricted_pc")) {
            if (!bus.unrestricted_pc) {
                cpu.pc +%= 2;
                return 4;
            }
        } else {
            cpu.pc +%= 2;
            return 4;
        }
    }

    bus.debug_pc = cpu.pc;

    const opcode = bus.read16(cpu.pc);
    cpu.pc += 2;

    const nibble: u4 = @truncate(opcode >> 12);

    const cycles = switch (nibble) {
        0x0 => bloc0.exec(cpu, bus, opcode),
        0x1 => bloc0.exec(cpu, bus, opcode), // MOVE.B
        0x2 => bloc0.exec(cpu, bus, opcode), // MOVE.L
        0x3 => bloc0.exec(cpu, bus, opcode), // MOVE.W
        0x4 => bloc1.exec(cpu, bus, opcode),
        0x5 => bloc2.exec(cpu, bus, opcode),
        0x6 => bloc3.exec(cpu, bus, opcode), // Branches Bcc
        0x7 => bloc7.exec(cpu, bus, opcode), // MOVEQ
        0x8 => bloc8.exec(cpu, bus, opcode), // OR / DIVU/DIVS
        0x9 => bloc6.exec(cpu, bus, opcode), // SUB / SUBA / SUBX
        0xA => {
            return exception(cpu, bus, 0x0A, opcode, "Line-A");
        },
        0xB => bloc11.exec(cpu, bus, opcode), // CMP / EOR
        0xC => blocC.exec(cpu, bus, opcode), // AND / MULU/MULS
        0xD => bloc13.exec(cpu, bus, opcode), // ADD / ADDA / ADDX
        0xE => bloc10.exec(cpu, bus, opcode), // Shifts/Rotates
        0xF => {
            return exception(cpu, bus, 0x0B, opcode, "Line-F");
        },
    };

    if ((cpu.pc & 1) != 0) {
        cpu.pc &= 0xFFFFFFFE;
        return 4;
    }

    return cycles;
}

pub fn illegalInstruction(cpu: *Cpu, bus: anytype, opcode: u16, name: []const u8) u32 {
    return exception(cpu, bus, 0x04, opcode, name);
}

pub fn isDataAlterableEA(ea: EA) bool {
    return switch (ea.mode) {
        0b000 => true, // Dn
        0b001 => false, // An is not data-alterable
        0b010, 0b011, 0b100, 0b101, 0b110 => true,
        0b111 => ea.reg == 0b000 or ea.reg == 0b001, // absolute short/long only
    };
}

pub fn enterSupervisor(cpu: *Cpu) void {
    if (!cpu.sr.s) {
        cpu.usp = cpu.a[7];
        cpu.a[7] = cpu.ssp;
    }
}

pub fn leaveSupervisor(cpu: *Cpu) void {
    if (!cpu.sr.s) {
        cpu.ssp = cpu.a[7];
        cpu.a[7] = cpu.usp;
    }
}

pub fn exception(cpu: *Cpu, bus: anytype, vector: u32, opcode: u16, name: []const u8) u32 {
    _ = opcode;
    _ = name;
    const saved_pc = cpu.pc - 2;
    const saved_sr = cpu.sr.get();
    enterSupervisor(cpu);
    cpu.a[7] -%= 6;
    bus.write16(cpu.a[7], saved_sr);
    bus.write32(cpu.a[7] + 2, saved_pc);
    cpu.sr.s = true;
    cpu.sr.t = false;

    cpu.pc = bus.read32(vector * 4);
    return 34;
}

pub fn addressErrorException(cpu: *Cpu, bus: anytype, opcode: u16, access_addr: u32, saved_pc: u32) void {
    const saved_sr = cpu.sr.get();
    const s_bit: u1 = @truncate(saved_sr >> 13);
    const fc: u3 = if (s_bit == 1) 5 else 1;
    const size_bits: u2 = @truncate(opcode >> 6);
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const is_pc_relative = mode == 0b111 and (reg == 0b010 or reg == 0b011);
    const has_ext_word = switch (mode) {
        0b100, 0b101, 0b110 => true,
        0b111 => reg == 0 or reg == 1 or reg == 2 or reg == 3,
        else => false,
    };
    const cycle_bits: u2 = if (has_ext_word) 3 else 1;
    const cycle_fc: u3 = if (is_pc_relative) if (s_bit == 1) 6 else 2 else fc;
    const status_byte: u8 = (@as(u8, size_bits) << 6) | (@as(u8, cycle_bits) << 4) | @as(u8, cycle_fc);
    const ssw: u16 = (@as(u16, opcode >> 8) << 8) | status_byte;

    enterSupervisor(cpu);
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

// ============================================
// SIZE HELPERS
// ============================================

pub fn decodeSize(bits: u2) Size {
    return switch (bits) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        0b11 => .long,
    };
}

pub fn maskSize(val: u32, size: Size) u32 {
    return switch (size) {
        .byte => val & 0xFF,
        .word => val & 0xFFFF,
        .long => val,
    };
}

pub fn signBit(size: Size) u32 {
    return switch (size) {
        .byte => 0x80,
        .word => 0x8000,
        .long => 0x8000_0000,
    };
}

// ============================================
// ARITHMETIC HELPERS
// ============================================

pub fn addSigned(base: u32, disp: i32) u32 {
    return @bitCast(@as(i32, @bitCast(base)) +% disp);
}

pub fn signExtend8(v: u8) i32 {
    return @as(i8, @bitCast(v));
}

pub fn signExtend16(v: u16) i32 {
    return @as(i16, @bitCast(v));
}

pub fn isNegative(value: u32, size: Size) bool {
    return switch (size) {
        .byte => (value & 0x80) != 0,
        .word => (value & 0x8000) != 0,
        .long => (value & 0x80000000) != 0,
    };
}

// ============================================
// MEMORY ACCESS HELPERS
// ============================================

pub fn readMem(bus: anytype, addr: u32, size: Size) u32 {
    const masked = addr & 0x00FFFFFF;
    return switch (size) {
        .byte => bus.read8(masked),
        .word => bus.read16(masked),
        .long => bus.read32(masked),
    };
}

pub fn writeMem(bus: anytype, addr: u32, size: Size, val: u32) void {
    const masked = addr & 0x00FFFFFF;
    switch (size) {
        .byte => bus.write8(masked, @truncate(val)),
        .word => bus.write16(masked, @truncate(val)),
        .long => bus.write32(masked, val),
    }
}

pub fn mergeValue(old: u32, val: u32, size: Size) u32 {
    return switch (size) {
        .byte => (old & 0xFFFFFF00) | (val & 0xFF),
        .word => (old & 0xFFFF0000) | (val & 0xFFFF),
        .long => val,
    };
}

// ============================================
// EFFECTIVE ADDRESS (EA) OPERATIONS
// ============================================

pub const EAMode = enum(u8) {
    Dn,
    An,
    Indirect,
    PostInc,
    PreDec,
    Displ,
    Index,
    AbsW,
    AbsL,
    PcDispl,
    PcIndex,
    Imm,
};

pub fn decodeEAType(mode: u3, reg: u3) EAMode {
    return switch (mode) {
        0b000 => .Dn,
        0b001 => .An,
        0b010 => .Indirect,
        0b011 => .PostInc,
        0b100 => .PreDec,
        0b101 => .Displ,
        0b110 => .Index,
        0b111 => switch (reg) {
            0b000 => .AbsW,
            0b001 => .AbsL,
            0b010 => .PcDispl,
            0b011 => .PcIndex,
            0b100 => .Imm,
            else => .AbsW,
        },
    };
}

/// Les cycles possédant + signifie « plus le temps EA du mode d'adressage »
/// Cette fonction définit ces cycles utlisés par tous les opcodes
pub fn eaCycleCost(mode: u3, reg: u3, size: Size) u32 {
    const bw: u32 = switch (mode) {
        0b000, 0b001 => 0,
        0b010 => 4,
        0b011 => 4,
        0b100 => 6,
        0b101 => 8,
        0b110 => 10,
        0b111 => switch (reg) {
            0b000 => 8,
            0b001 => 12,
            0b010 => 8,
            0b011 => 10,
            else => 8,
        },
    };
    return if (size == .long) bw + 4 else bw;
}

/// Compute cycles for compare-type operations (CMP, CMPA, CMPI, CMPM) matching Motorola manual.
/// base: 4 for byte/word, 6 for long. EA cost covers any memory read/write cycles.
pub fn unaryOpCycles(size: Size, mode: u3, reg: u3) u32 {
    const base: u32 = if (size == .long) 6 else 4;
    return base + eaCycleCost(mode, reg, size);
}

/// Compute cycles for binary operations (ADD, SUB, AND, OR, EOR) matching jgenesis model.
/// source_mr = mode/reg of source EA, dest_mr = mode/reg of dest EA, dest_is_mem = true if result written to memory.
pub fn binaryOpCycles(size: Size, source_mode: u3, source_reg: u3, dest_mode: u3, dest_reg: u3, dest_is_mem: bool) u32 {
    const base: u32 = if (size == .long) 8 else 4;
    const src_ea = eaCycleCost(source_mode, source_reg, size);
    const dst_ea = if (dest_is_mem) eaCycleCost(dest_mode, dest_reg, size) else 0;
    var cycles = base + src_ea + dst_ea;
    // .w operation on address register destination costs 4 extra
    if (size == .word and dest_mode == 0b001) cycles += 4;
    // .l memory→register saves 2 cycles
    if (size == .long and (source_mode != 0b000 and source_mode != 0b001) and (dest_mode == 0b000 or dest_mode == 0b001)) {
        if (cycles >= 2) cycles -= 2;
    }
    if (dest_is_mem) cycles += 4; // write-back penalty
    return cycles;
}

/// Lecture depuis une adresse effective
/// Gère tous les modes d'adressage du 68000
/// Délègue le calcul d'adresse mémoire à resolveEA
pub fn readEA(cpu: *Cpu, bus: anytype, ea: EA, size: Size) u32 {
    const mode = ea.mode;
    const reg = ea.reg;

    switch (mode) {

        // Dn
        0b000 => {
            return maskSize(cpu.d[reg], size);
        },

        // An
        0b001 => {
            if (size == .byte) unreachable;
            return maskSize(cpu.a[reg], size);
        },

        // Immédiat (mode 111, reg 100)
        0b111 => switch (reg) {
            0b100 => {
                return switch (size) {
                    .byte => {
                        const word = bus.read16(cpu.pc);
                        cpu.pc += 2;
                        return word & 0xFF;
                    },
                    .word => {
                        const val = bus.read16(cpu.pc);
                        cpu.pc += 2;
                        return val;
                    },
                    .long => {
                        const val = bus.read32(cpu.pc);
                        cpu.pc += 4;
                        return val;
                    },
                };
            },
            else => {
                const addr = resolveEA(cpu, bus, ea, size);
                return readMem(bus, addr, size);
            },
        },

        // Modes mémoire : déléguer à resolveEA + readMem
        else => {
            const addr = resolveEA(cpu, bus, ea, size);
            return readMem(bus, addr, size);
        },
    }
}

/// Résout une EA mémoire en adresse (consomme les mots d'extension UNE SEULE FOIS)
/// Ne gère que les modes mémoire (pas Dn/An). N'inclut PAS la lecture/écriture mémoire.
pub fn resolveEA(cpu: *Cpu, bus: anytype, ea: EA, size: Size) u32 {
    const mode = ea.mode;
    const reg = ea.reg;

    return switch (decodeEAType(mode, reg)) {
        .Indirect => cpu.a[reg],
        .PostInc => blk: {
            const addr = cpu.a[reg];
            cpu.a[reg] +%= switch (size) {
                .byte => if (reg == 7) @as(u32, 2) else 1,
                .word => 2,
                .long => 4,
            };
            break :blk addr;
        },
        .PreDec => blk: {
            cpu.a[reg] -%= switch (size) {
                .byte => if (reg == 7) @as(u32, 2) else 1,
                .word => 2,
                .long => 4,
            };
            break :blk cpu.a[reg];
        },
        .Displ => blk: {
            const disp = signExtend16(bus.read16(cpu.pc));
            cpu.pc += 2;
            break :blk addSigned(cpu.a[reg], disp);
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
            break :blk addSigned(addSigned(cpu.a[reg], disp), @as(i32, @bitCast(index_val)));
        },
        .AbsW => blk: {
            const addr = signExtend16(bus.read16(cpu.pc));
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
            const index_is_addr = ((ext >> 15) & 1) == 1;
            const index_size_long = ((ext >> 11) & 1) == 1;
            var index_val: u32 = if (index_is_addr)
                cpu.a[index_reg]
            else
                cpu.d[index_reg];
            if (!index_size_long) {
                index_val = @as(u32, @bitCast(signExtend16(@truncate(index_val))));
            }
            break :blk addSigned(addSigned(pc_at_ext, disp), @as(i32, @bitCast(index_val)));
        },
        .Dn, .An, .Imm => blk: {
            std.log.warn("[CPU] resolveEA appelé sur mode registre {}", .{mode});
            break :blk 0;
        },
    };
}

/// Écriture vers une adresse effective
/// Délègue le calcul d'adresse mémoire à resolveEA
pub fn writeEA(cpu: *Cpu, bus: anytype, ea: EA, size: Size, val: u32) void {
    const mode = ea.mode;
    const reg = ea.reg;

    switch (mode) {

        // Dn
        0b000 => {
            cpu.d[reg] = mergeValue(cpu.d[reg], val, size);
        },

        // An — byte write illegal sur 68000, skip proprement
        0b001 => {
            if (size == .byte) {
                std.log.warn("[CPU] [ILLEGAL] byte write to An{} at PC=0x{X:0>6}", .{ reg, cpu.pc });
                return;
            }
            cpu.a[reg] = switch (size) {
                .byte => unreachable,
                .word => @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))),
                .long => val,
            };
        },

        // PC-relative et immediate — destinations illégales en écriture
        0b111 => switch (reg) {
            0b010, 0b011, 0b100 => {
                std.log.warn("[CPU] [writeEA] BAD DEST mode=7 reg=4 (immediate) at PC=0x{X:0>6}", .{cpu.pc});
            },
            else => {
                const addr = resolveEA(cpu, bus, ea, size);
                writeMem(bus, addr, size, val);
            },
        },

        // Modes mémoire : déléguer à resolveEA + writeMem
        else => {
            const addr = resolveEA(cpu, bus, ea, size);
            writeMem(bus, addr, size, val);
        },
    }
}

/// Met à jour les flags N et Z selon la taille
pub fn updateNZ(cpu: *Cpu, val: u32, size: Size) void {
    switch (size) {
        .byte => {
            cpu.sr.n = (val & 0x80) != 0;
            cpu.sr.z = (val & 0xFF) == 0;
        },
        .word => {
            cpu.sr.n = (val & 0x8000) != 0;
            cpu.sr.z = (val & 0xFFFF) == 0;
        },
        .long => {
            cpu.sr.n = (val & 0x80000000) != 0;
            cpu.sr.z = val == 0;
        },
    }
}
