const std = @import("std");
const m68k = @import("m68k");
const Cpu = m68k.Cpu;
const parent = @import("../decode.zig");
const signExtend8 = parent.signExtend8;
const signExtend16 = parent.signExtend16;
const addSigned = parent.addSigned;

/// Branch instructions (Bcc)
pub fn exec(cpu: *Cpu, bus: anytype, opcode: u16) u32 {
    const condition: u4 = @truncate(opcode >> 8);
    const disp_byte: u8 = @truncate(opcode);

    const extension_size: u32 = if (disp_byte == 0) 2 else if (disp_byte == 0xFF) 4 else 0;

    const displacement: i32 = if (disp_byte == 0) blk: {
        break :blk signExtend16(bus.read16(cpu.pc));
    } else if (disp_byte == 0xFF) blk: {
        break :blk @as(i32, @bitCast(bus.read32(cpu.pc)));
    } else blk: {
        break :blk signExtend8(disp_byte);
    };

    const cond_met = evalCondition(cpu, condition);

    if (cond_met) {
        // BSR: push return address before branching
        if (condition == 0x1) {
            const return_addr = cpu.pc + extension_size;
            cpu.a[7] -%= 4;
            bus.write32(cpu.a[7], return_addr);
        }

        cpu.pc = addSigned(cpu.pc, displacement);

        return if (condition == 0x1) 18 else 10;
    } else {
        cpu.pc += extension_size;
        return if (extension_size == 0) 8 else 12;
    }
}

/// Évalue la condition de branchement selon le code condition (bits 11-8)
fn evalCondition(cpu: *const Cpu, cond: u4) bool {
    return switch (cond) {
        // 0x0 = BRA - Branch Always
        0x0 => true,

        // 0x1 = BSR - Branch to Subroutine (always taken)
        0x1 => true,

        // 0x2 = BHI - Branch if HIgher (C=0 et Z=0, unsigned >)
        0x2 => !cpu.sr.c and !cpu.sr.z,

        // 0x3 = BLS - Branch if Lower or Same (C=1 ou Z=1, unsigned <=)
        0x3 => cpu.sr.c or cpu.sr.z,

        // 0x4 = BCC/BHS - Branch if Carry Clear / Branch if Higher or Same (C=0, unsigned >=)
        0x4 => !cpu.sr.c,

        // 0x5 = BCS/BLO - Branch if Carry Set / Branch if LOwer (C=1, unsigned <)
        0x5 => cpu.sr.c,

        // 0x6 = BNE - Branch if Not Equal (Z=0, !=)
        0x6 => !cpu.sr.z,

        // 0x7 = BEQ - Branch if EQual (Z=1, ==)
        0x7 => cpu.sr.z,

        // 0x8 = BVC - Branch if oVerflow Clear (V=0)
        0x8 => !cpu.sr.v,

        // 0x9 = BVS - Branch if oVerflow Set (V=1)
        0x9 => cpu.sr.v,

        // 0xA = BPL - Branch if PLus (N=0, >= 0 signé)
        0xA => !cpu.sr.n,

        // 0xB = BMI - Branch if MInus (N=1, < 0 signé)
        0xB => cpu.sr.n,

        // 0xC = BGE - Branch if Greater or Equal (N==V, signé >=)
        0xC => cpu.sr.n == cpu.sr.v,

        // 0xD = BLT - Branch if Less Than (N!=V, signé <)
        0xD => cpu.sr.n != cpu.sr.v,

        // 0xE = BGT - Branch if Greater Than (Z=0 et N==V, signé >)
        0xE => !cpu.sr.z and (cpu.sr.n == cpu.sr.v),

        // 0xF = BLE - Branch if Less or Equal (Z=1 ou N!=V, signé <=)
        0xF => cpu.sr.z or (cpu.sr.n != cpu.sr.v),
    };
}
