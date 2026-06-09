const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const updateNZ = parent.updateNZ;
pub const isNegative = parent.isNegative;

const signExtend8 = parent.signExtend8;
const signExtend16 = parent.signExtend16;
const addSigned = parent.addSigned;
const readMem = parent.readMem;
const writeMem = parent.writeMem;

pub const writeEA = parent.writeEA;
pub const resolveEA = parent.resolveEA;
pub const maskSize = parent.maskSize;
pub const mergeValue = parent.mergeValue;
pub const signBit = parent.signBit;

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const opmode: u3 = @truncate(opcode >> 6);
    const mode: u3 = @truncate(opcode >> 3);

    // SUBA : opmode 011 (word) ou 111 (long)
    if (opmode == 0b011 or opmode == 0b111) {
        return execSUBA(cpu, bus, opcode);
    }

    // SUBX : opmode 100/101/110 ET source est Dn (mode=000) ou -(An) (mode=001)
    if ((opmode == 0b100 or opmode == 0b101 or opmode == 0b110) and
        (mode == 0b000 or mode == 0b001))
    {
        return execSUBX(cpu, bus, opcode);
    }

    // SUB normal
    return execSUB(cpu, bus, opcode);
}

/// SUBA - Subtract Address
/// SUBA.W <ea>, An: An - sign-ext(<ea>.W) → An
/// SUBA.L <ea>, An: An - <ea>.L → An
pub fn execSUBA(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const an: u3 = @truncate(opcode >> 9);
    const mode: u3 = @truncate(opcode >> 3);
    const reg: u3 = @truncate(opcode);
    const is_long = ((opcode >> 8) & 1) == 1;
    const size: Size = if (is_long) .long else .word;
    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b000 or mode == 0b001 or (mode == 0b111 and reg == 0b100)) {
        const src = readEA(cpu, bus, ea, size);
        if (is_long) {
            cpu.a[an] -%= src;
        } else {
            cpu.a[an] -%= @as(u32, @bitCast(signExtend16(@truncate(src))));
        }
    } else {
        const saved_pc = cpu.pc;
        const addr = resolveEA(cpu, bus, ea, size);
        const exception_pc: u32 = if (mode == 0b100 and !is_long)
            saved_pc +% 2
        else if (mode == 0b111)
            if (reg == 0b010 or reg == 0b011) saved_pc else cpu.pc
        else
            saved_pc;
        if ((addr & 1) != 0) {
            if (is_long and mode == 0b011) cpu.a[reg] -%= 4;
            parent.addressErrorException(cpu, bus, opcode, addr, exception_pc);
            return 50;
        }
        const src = readMem(bus, addr, size);
        if (is_long) {
            cpu.a[an] -%= src;
        } else {
            cpu.a[an] -%= @as(u32, @bitCast(signExtend16(@truncate(src))));
        }
    }

    const base: u32 = if (is_long) 6 else 8;
    return base + parent.eaCycleCost(mode, reg, size);
}

/// SUBX - Subtract with Extend
/// SUBX Dm,Dn (register): 1001 ddd 1 oo 000 mmm
/// SUBX -(Am),-(An) (memory): 1001 ddd 1 oo 001 mmm
/// Operation: dst - src - X → dst
/// Z flag is sticky: Z = Z ∧ (result == 0)
pub fn execSUBX(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const mode: u3 = @truncate(opcode >> 3);
    const opmode: u3 = @truncate(opcode >> 6);
    const reg_dst: u3 = @truncate(opcode >> 9);
    const reg_src: u3 = @truncate(opcode);

    const size: Size = switch (opmode & 0b011) {
        0b00 => .byte,
        0b01 => .word,
        0b10 => .long,
        else => .word,
    };

    const x_val: u32 = if (cpu.sr.x) 1 else 0;

    if (mode == 0b000) {
        // Register mode: SUBX Dm,Dn
        const src: u32 = maskSize(cpu.d[reg_src], size);
        const dst: u32 = maskSize(cpu.d[reg_dst], size);
        const result = dst -% src -% x_val;
        const masked = maskSize(result, size);

        cpu.d[reg_dst] = mergeValue(cpu.d[reg_dst], masked, size);
        setFlagsSUBX(cpu, size, dst, src, x_val, masked);
        return if (size == .long) 8 else 4;
    } else {
        // Memory mode: SUBX -(Am),-(An)
        const size_inc: u32 = switch (size) {
            .byte => if (reg_src == 7 or reg_dst == 7) 2 else 1,
            .word => 2,
            .long => 4,
        };

        const addr_src = cpu.a[reg_src] -% size_inc;
        cpu.a[reg_src] = addr_src;
        const addr_dst = cpu.a[reg_dst] -% size_inc;
        cpu.a[reg_dst] = addr_dst;

        const src: u32 = readMem(bus, addr_src, size);
        const dst: u32 = readMem(bus, addr_dst, size);
        const result = dst -% src -% x_val;
        const masked = maskSize(result, size);

        writeMem(bus, addr_dst, size, masked);
        setFlagsSUBX(cpu, size, dst, src, x_val, masked);

        return switch (size) {
            .byte => 18,
            .word => 18,
            .long => 30,
        };
    }
}

fn setFlagsSUBX(cpu: *Cpu, size: Size, dst: u32, src: u32, x_val: u32, result: u32) void {
    const bit = signBit(size);
    const mask = maskSize(0xFFFF_FFFF, size);
    const d = dst & mask;
    const s = src & mask;
    const r = result & mask;

    cpu.sr.n = isNegative(r, size);
    if (r != 0) cpu.sr.z = false;
    cpu.sr.v = (((d ^ s) & (d ^ r)) & bit) != 0;
    cpu.sr.c = (d < s) or ((d == s) and x_val != 0);
    cpu.sr.x = cpu.sr.c;
}

/// Fonction qui va gérer les 3 SUB (SUB, SUBX SUBA)
/// SUB < ea > ,Dn
/// SUB Dn, < ea >
/// Size = (Byte, Word, Long)
/// X — Set to the value of the carry bit.
/// N — Set if the result is negative; cleared otherwise.
/// Z — Set if the result is zero; cleared otherwise.
/// V — Set if an overflow is generated; cleared otherwise.
/// C — Set if a borrow is generated; cleared otherwise.
///
/// Note : Les registres D sont sur 32 bits, sub.b ne modifie que 8 bits et sub.w 16 bits.
/// Il faut donc garder les 16 bits de poids forts et modifier les 16 bits de poids faibles
/// Exemple cpu.d[1] = 0x12345678 et result = 0xABCD => 0w1234ABCD
/// cpu.d[1] & 0xFFFF0000 | result
///
pub fn execSUB(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const reg: u3 = @truncate(opcode);
    const mode: u3 = @truncate(opcode >> 3);
    const opmode: u3 = @truncate(opcode >> 6); // 000 001 010 Dn – < ea > → Dn et 100 101 110 < ea > – Dn → < ea >
    const dn: u3 = @truncate(opcode >> 9); // registre data D0 - D7

    //std.debug.print("execSUB opcode=0x{X:0>4} dn={} mode={} reg={} opmode={b:0>3}\n", .{ opcode, dn, mode, reg, opmode });
    //std.debug.print("  D[{}]={} D[{}]={}\n", .{ dn, cpu.d[dn], reg, cpu.d[reg] });

    const ea = EA{ .mode = mode, .reg = reg };

    if ((opmode == 0b100 or opmode == 0b101 or opmode == 0b110) and !parent.isDataAlterableEA(ea)) {
        return parent.illegalInstruction(cpu, bus, opcode, "SUB destination");
    }

    switch (opmode) {
        0b000 => {
            const src: u8 = @truncate(readEA(cpu, bus, ea, .byte));
            const dst: u8 = @truncate(cpu.d[dn]);
            const result = dst -% src;
            cpu.d[dn] = (cpu.d[dn] & 0xFFFFFF00) | result;
            setFlagsSUB(cpu, u8, dst, src, result);
            //std.debug.print("  après: D[{d}]=0x{X:08}\n", .{ dn, cpu.d[dn] });
        },
        // Word: Dn - <ea> → Dn
        0b001 => {
            const src: u16 = @truncate(readEA(cpu, bus, ea, .word));
            const dst: u16 = @truncate(cpu.d[dn]);
            const result = dst -% src;
            cpu.d[dn] = (cpu.d[dn] & 0xFFFF0000) | result;
            setFlagsSUB(cpu, u16, dst, src, result);
        },
        // Long: Dn - <ea> → Dn
        0b010 => {
            const src: u32 = readEA(cpu, bus, ea, .long);
            const dst: u32 = cpu.d[dn];
            const result = dst -% src;
            cpu.d[dn] = result;
            setFlagsSUB(cpu, u32, dst, src, result);
        },
        // Byte: <ea> - Dn → <ea>
        0b100 => {
            const src: u8 = @truncate(cpu.d[dn]);
            if (mode == 0b000 or mode == 0b001) {
                const dst: u8 = @truncate(readEA(cpu, bus, ea, .byte));
                const result = dst -% src;
                writeEA(cpu, bus, ea, .byte, result);
                setFlagsSUB(cpu, u8, dst, src, result);
            } else {
                const addr = resolveEA(cpu, bus, ea, .byte);
                const dst: u8 = @truncate(readMem(bus, addr, .byte));
                const result = dst -% src;
                writeMem(bus, addr, .byte, result);
                setFlagsSUB(cpu, u8, dst, src, result);
            }
        },
        // Word: <ea> - Dn → <ea>
        0b101 => {
            const src: u16 = @truncate(cpu.d[dn]);
            if (mode == 0b000 or mode == 0b001) {
                const dst: u16 = @truncate(readEA(cpu, bus, ea, .word));
                const result = dst -% src;
                writeEA(cpu, bus, ea, .word, result);
                setFlagsSUB(cpu, u16, dst, src, result);
            } else {
                const addr = resolveEA(cpu, bus, ea, .word);
                const dst: u16 = @truncate(readMem(bus, addr, .word));
                const result = dst -% src;
                writeMem(bus, addr, .word, result);
                setFlagsSUB(cpu, u16, dst, src, result);
            }
        },
        // Long: <ea> - Dn → <ea>
        0b110 => {
            const src = cpu.d[dn];
            if (mode == 0b000 or mode == 0b001) {
                const dst = readEA(cpu, bus, ea, .long);
                const result = dst -% src;
                writeEA(cpu, bus, ea, .long, result);
                setFlagsSUB(cpu, u32, dst, src, result);
            } else {
                const addr = resolveEA(cpu, bus, ea, .long);
                const dst = readMem(bus, addr, .long);
                const result = dst -% src;
                writeMem(bus, addr, .long, result);
                setFlagsSUB(cpu, u32, dst, src, result);
            }
        },
        else => {
            std.log.warn("[CPU] [SUB] unknown opmode=0x{X:0>4} at PC=0x{X:0>6}", .{ opmode, cpu.pc });
            return parent.illegalInstruction(cpu, bus, opcode, "SUB");
        },
    }

    const size: Size = if (opmode == 0b000 or opmode == 0b100) .byte else if (opmode == 0b001 or opmode == 0b101) .word else .long;
    const dest_is_mem = (opmode == 0b100 or opmode == 0b101 or opmode == 0b110);
    return if (dest_is_mem)
        parent.binaryOpCycles(size, 0b000, dn, mode, reg, true)
    else
        parent.binaryOpCycles(size, mode, reg, 0b000, dn, false);
}

/// Note : T est un type connu à la compilation donc la fonction est générique
fn setFlagsSUB(cpu: *Cpu, comptime T: type, dst: T, src: T, result: T) void {
    const bits = @bitSizeOf(T);
    const msb_mask = @as(T, 1) << (bits - 1);

    cpu.sr.n = (result & msb_mask) != 0;
    cpu.sr.z = result == 0;
    cpu.sr.v = ((dst ^ src) & (dst ^ result) & msb_mask) != 0;
    cpu.sr.c = result > dst;
    cpu.sr.x = cpu.sr.c;
}
