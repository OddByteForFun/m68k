const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");

pub const Size = parent.Size;
pub const EA = parent.EA;
pub const readEA = parent.readEA;
pub const writeEA = parent.writeEA;
pub const updateNZ = parent.updateNZ;
pub const isNegative = parent.isNegative;

const signExtend8 = parent.signExtend8;
const signExtend16 = parent.signExtend16;
const addSigned = parent.addSigned;
const signBit = parent.signBit;
const maskSize = parent.maskSize;

inline fn bitCount(size: Size) u6 {
    return switch (size) {
        .byte => 8,
        .word => 16,
        .long => 32,
    };
}

inline fn shiftCycles(count: u32) u32 {
    return 6 + 2 * count;
}

pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const type_instruction: u8 = @truncate(opcode >> 8);
    switch (type_instruction) {
        0xE0...0xEF => return execShiftRotate(cpu, bus, opcode),
        else => {
            return parent.exception(cpu, bus, 0x10, opcode, "bloc10");
        },
    }
}

fn execShiftRotate(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    if (((opcode >> 6) & 0b11) == 0b11) {
        return execShiftRotateMem(cpu, bus, opcode);
    }
    const size: Size = switch ((opcode >> 6) & 0b11) {
        0b00 => .byte,
        0b01 => .word,
        else => .long,
    };
    const dr: u1 = @truncate((opcode >> 8) & 0x1);
    const ir: u1 = @truncate((opcode >> 5) & 0x1);
    const kind: u2 = @truncate((opcode >> 3) & 0x3);
    const reg: u3 = @truncate(opcode & 0x7);

    const count_raw: u32 = (opcode >> 9) & 0x7;
    const count: u32 = if (ir == 1)
        cpu.d[@as(u3, @truncate(count_raw))] & 0x3F
    else if (count_raw == 0)
        8
    else
        count_raw;

    return switch (kind) {
        0b00 => execAS(cpu, dr, size, reg, count),
        0b01 => execLS(cpu, dr, size, reg, count),
        0b10 => execROX(cpu, dr, size, reg, count),
        0b11 => execRO(cpu, dr, size, reg, count),
    };
}

fn execAS(cpu: *Cpu, dr: u1, size: parent.Size, reg: u3, count: u32) u32 {
    const msb = signBit(size);
    var val = parent.maskSize(cpu.d[reg], size);

    if (dr == 1) {
        // ASL
        var overflow = false;
        var last_out = false;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            last_out = (val & msb) != 0;
            // overflow : le bit de signe change (bit N-1 != bit N-2 après shift)
            // on compare le MSB actuel avec le bit qui va devenir MSB
            const next_msb = (val << 1) & msb;
            overflow = overflow or ((val & msb) != next_msb);
            val = parent.maskSize(val << 1, size);
        }
        cpu.sr.c = if (count > 0) last_out else false;
        cpu.sr.x = cpu.sr.c;
        cpu.sr.v = overflow;
    } else {
        // ASR — extension de signe
        var last_out = false;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            last_out = (val & 1) != 0;
            // maskSize après pour éviter que le MSB propagé dépasse la taille
            val = parent.maskSize((val >> 1) | (val & msb), size);
        }
        cpu.sr.c = if (count > 0) last_out else false;
        cpu.sr.x = cpu.sr.c;
        cpu.sr.v = false; // ASR ne peut jamais déborder
    }

    parent.updateNZ(cpu, val, size);
    cpu.d[reg] = parent.mergeValue(cpu.d[reg], val, size);
    return shiftCycles(count);
}

// ─── LSR / LSL ──────────────────────────────────────────────────────────────

fn execLS(cpu: *Cpu, dr: u1, size: Size, reg: u3, count: u32) u32 {
    const msb = signBit(size);
    var val = parent.maskSize(cpu.d[reg], size);
    var last_out = false;

    if (dr == 1) {
        // LSL
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            last_out = (val & msb) != 0;
            val = parent.maskSize(val << 1, size);
        }
    } else {
        // LSR
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            last_out = (val & 1) != 0;
            val = val >> 1; // pas besoin de mask, on perd les bits hauts
        }
    }

    cpu.sr.c = if (count > 0) last_out else false;
    cpu.sr.x = cpu.sr.c;
    cpu.sr.v = false;
    parent.updateNZ(cpu, val, size);
    cpu.d[reg] = parent.mergeValue(cpu.d[reg], val, size);
    return shiftCycles(count);
}

// ─── ROXR / ROXL ────────────────────────────────────────────────────────────

fn execROX(cpu: *Cpu, dr: u1, size: Size, reg: u3, count: u32) u32 {
    const bits: u6 = bitCount(size);
    const msb = signBit(size);
    var val = parent.maskSize(cpu.d[reg], size);
    var x_bit = cpu.sr.x; // X participe à la rotation

    if (dr == 1) {
        // ROXL : val << 1, X entre en LSB, MSB sort vers X
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const new_lsb = x_bit;
            x_bit = (val & msb) != 0;
            val = parent.maskSize((val << 1) | @intFromBool(new_lsb), size);
        }
    } else {
        // ROXR : val >> 1, X entre en MSB, LSB sort vers X
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const new_msb = x_bit;
            x_bit = (val & 1) != 0;
            val = (val >> 1) | (@as(u32, @intFromBool(new_msb)) << @as(u5, @truncate(bits - 1)));
            val = parent.maskSize(val, size);
        }
    }

    // count == 0 : C prend la valeur de X, X inchangé
    cpu.sr.c = if (count > 0) x_bit else cpu.sr.x;
    cpu.sr.x = if (count > 0) x_bit else cpu.sr.x;
    cpu.sr.v = false;
    parent.updateNZ(cpu, val, size);
    cpu.d[reg] = parent.mergeValue(cpu.d[reg], val, size);
    return shiftCycles(count);
}

// ─── ROR / ROL ──────────────────────────────────────────────────────────────

fn execRO(cpu: *Cpu, dr: u1, size: Size, reg: u3, count: u32) u32 {
    const bits: u6 = bitCount(size);
    const msb = signBit(size);
    var val = parent.maskSize(cpu.d[reg], size);
    var last_out = false;

    if (dr == 1) {
        // ROL : MSB sort et rentre en LSB
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            last_out = (val & msb) != 0;
            val = parent.maskSize((val << 1) | @intFromBool(last_out), size);
        }
    } else {
        // ROR : LSB sort et rentre en MSB
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            last_out = (val & 1) != 0;
            val = (val >> 1) | (@as(u32, @intFromBool(last_out)) << @as(u5, @truncate(bits - 1)));
            val = parent.maskSize(val, size);
        }
    }

    cpu.sr.c = if (count > 0) last_out else false;
    cpu.sr.v = false;
    parent.updateNZ(cpu, val, size);
    cpu.d[reg] = parent.mergeValue(cpu.d[reg], val, size);
    return shiftCycles(count);
}

fn execShiftRotateMem(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const dr: u1 = @truncate((opcode >> 8) & 0x1);
    const kind: u2 = @truncate((opcode >> 9) & 0x3);
    const mode: u3 = @truncate((opcode >> 3) & 0x7);
    const reg: u3 = @truncate(opcode & 0x7);
    const ea = EA{ .mode = mode, .reg = reg };

    if (mode == 0b000 or mode == 0b001) {
        // Register modes — safe to use readEA/writeEA (no resolveEA called)
        const val: u16 = @truncate(readEA(cpu, bus, ea, .word));
        const result: u16 = switch (kind) {
            0b00 => memAS(cpu, dr, val),
            0b01 => memLS(cpu, dr, val),
            0b10 => memROX(cpu, dr, val),
            0b11 => memRO(cpu, dr, val),
        };
        writeEA(cpu, bus, ea, .word, result);
    } else {
        // Memory modes — resolve EA ONCE, then read + compute + write
        const addr = parent.resolveEA(cpu, bus, ea, .word);
        const val: u16 = @truncate(parent.readMem(bus, addr, .word));
        const result: u16 = switch (kind) {
            0b00 => memAS(cpu, dr, val),
            0b01 => memLS(cpu, dr, val),
            0b10 => memROX(cpu, dr, val),
            0b11 => memRO(cpu, dr, val),
        };
        parent.writeMem(bus, addr, .word, result);
    }

    return switch (mode) {
        0b010 => 8,
        0b011 => 8,
        0b100 => 10,
        0b101 => 12,
        0b110 => 14,
        0b111 => switch (reg) {
            0b000 => 12,
            0b001 => 16,
            0b010 => 12,
            0b011 => 14,
            else => 12,
        },
        else => 8,
    };
}

fn memAS(cpu: *Cpu, dr: u1, val: u16) u16 {
    if (dr == 1) {
        const c = (val & 0x8000) != 0;
        const r = val << 1;
        cpu.sr.c = c;
        cpu.sr.x = c;
        cpu.sr.v = ((r ^ @as(u16, @bitCast(val))) & 0x8000) != 0;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    } else {
        const c = (val & 1) != 0;
        const sign = val & 0x8000;
        const sign_ext: u16 = if (sign != 0) @as(u16, 0x8000) else 0;
        const r = (val >> 1) | sign_ext;
        cpu.sr.c = c;
        cpu.sr.x = c;
        cpu.sr.v = false;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    }
}

fn memLS(cpu: *Cpu, dr: u1, val: u16) u16 {
    if (dr == 1) {
        const c = (val & 0x8000) != 0;
        const r = val << 1;
        cpu.sr.c = c;
        cpu.sr.x = c;
        cpu.sr.v = false;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    } else {
        const c = (val & 1) != 0;
        const r = val >> 1;
        cpu.sr.c = c;
        cpu.sr.x = c;
        cpu.sr.v = false;
        cpu.sr.n = false;
        cpu.sr.z = r == 0;
        return r;
    }
}

fn memROX(cpu: *Cpu, dr: u1, val: u16) u16 {
    const x: u16 = if (cpu.sr.x) 1 else 0;
    if (dr == 1) {
        const c = (val & 0x8000) != 0;
        const r = (val << 1) | @as(u16, x);
        cpu.sr.c = c;
        cpu.sr.x = c;
        cpu.sr.v = false;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    } else {
        // ROXR: rotate right through X
        const c = (val & 1) != 0;
        const r = (val >> 1) | @as(u16, x) << 15;
        cpu.sr.c = c;
        cpu.sr.x = c;
        cpu.sr.v = false;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    }
}

fn memRO(cpu: *Cpu, dr: u1, val: u16) u16 {
    if (dr == 1) {
        const c = (val & 0x8000) != 0;
        const r = (val << 1) | @as(u16, @intFromBool(c));
        cpu.sr.c = c;
        cpu.sr.v = false;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    } else {
        // ROR: rotate right
        const c = (val & 1) != 0;
        const r = (val >> 1) | @as(u16, @intFromBool(c)) << 15;
        cpu.sr.c = c;
        cpu.sr.v = false;
        cpu.sr.n = (r & 0x8000) != 0;
        cpu.sr.z = r == 0;
        return r;
    }
}

