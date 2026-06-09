const std = @import("std");

pub const CpuError = error{
    IllegalInstruction,
    BusError,
    AddressError,
};

/// Status Register : T . S . . I2 I1 I0 . . . X N Z V C
pub const StatusRegister = packed struct(u16) {
    c: bool = false, // Carry        bit 0
    v: bool = false, // oVerflow     bit 1
    z: bool = false, // Zero         bit 2
    n: bool = false, // Negative     bit 3
    x: bool = false, // eXtend       bit 4
    _pad0: u3 = 0, // bits 5-7
    ipl: u3 = 0, // Interrupt Priority Level  bits 8-10
    _pad1: u2 = 0, // bits 11-12
    s: bool = true, // Supervisor mode  bit 13
    _pad2: u1 = 0, // bit 14
    t: bool = false, // Trace        bit 15

    pub fn get(self: StatusRegister) u16 {
        return @bitCast(self);
    }

    // Setter : écrit tout le registre depuis u16
    pub fn set(self: *StatusRegister, val: u16) void {
        self.* = @bitCast(val);
    }
};

pub const Cpu = struct {
    /// Registres de données D0..D7
    d: [8]u32 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    /// Registres d'adresses A0..A7 (A7 = USP ou SSP selon mode)
    a: [8]u32 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    /// Program Counter
    pc: u32 = 0,
    /// Status Register
    sr: StatusRegister = .{},
    /// Cycles consommés depuis le dernier reset
    cycles: u64 = 0,
    /// Superviseur Stack Pointer (sauvegardé lors du switch user<->super)
    ssp: u32 = 0,
    /// User Stack Pointer (sauvegardé lors du switch super<->user)
    usp: u32 = 0,
    /// Halted (instruction STOP — can be resumed by interrupt)
    halted: bool = false,
    /// Stopped (bus error halt — needs reset)
    stopped: bool = false,

    pub fn init() Cpu {
        return .{};
    }

    /// Vérifie si une interruption est en attente.
    /// Retourne le niveau IRQ si elle doit être traitée, ou 0.
    pub fn checkInterrupt(self: *const Cpu, bus: anytype) u3 {
        const irq = bus.getInterruptLevel();
        if (irq == 0) return 0;
        if (irq == 7 or irq > self.sr.ipl) {
            return irq;
        }
        return 0;
    }

    /// Retourne l'adresse du vecteur d'interruption auto-vectorisé pour un niveau donné.
    /// Le vecteur est lu en mémoire à l'adresse (24 + level) * 4.
    pub fn interruptVectorAddr(_: *const Cpu, irq: u3) u32 {
        // Vecteurs auto-vectorisés : niveau 1 → 0x64, niveau 2 → 0x68, ..., niveau 7 → 0x7C
        return @as(u32, 24 + @as(u32, irq)) * 4;
    }

    /// Acquitte l'interruption : empile PC+SR, met à jour SR.ipl, saute au handler.
    /// Retourne le nouveau PC (adresse du handler).
    /// Doit être appelé depuis decode.step() quand checkInterrupt() retourne != 0.
    pub fn dispatchInterrupt(self: *Cpu, bus: anytype, irq: u3) u32 {
        // 1. Sauvegarder le contexte sur la stack superviseur
        const saved_pc = self.pc;
        const saved_sr = self.sr.get();

        // 2. Passer en mode superviseur (si pas déjà)
        self.sr.s = true;

        // 3. Mettre à jour le niveau d'interruption masqué
        self.sr.ipl = irq;

        // 4. Empiler PC puis SR (ordre M68K : SP-=6, [SP]=SR, [SP+2]=PC)
        self.a[7] -%= 6;
        bus.write16(self.a[7], saved_sr);
        bus.write32(self.a[7] + 2, saved_pc);

        // 5. Lire l'adresse du handler depuis le vecteur en mémoire
        const vec_addr = self.interruptVectorAddr(irq);
        const handler_pc = bus.read32(vec_addr);

        // 6. Clear l'IRQ dans le VDP
        //bus.vdp.irq_level = 0;

        return handler_pc;
    }

    /// Accès direct au CCR (octet bas du SR)
    pub fn getCcr(self: *const Cpu) u8 {
        return @truncate(@as(u16, @bitCast(self.sr)));
    }

    pub fn setCcr(self: *Cpu, val: u8) void {
        const current: u16 = @bitCast(self.sr);
        self.sr = @bitCast((current & 0xFF00) | val);
    }

    /// Reset hardware : lit SSP et PC depuis les vecteurs ROM
    /// 68000 reset sets SR = 0x2700 (Supervisor, IPL=7, all flags clear)
    pub fn reset(self: *Cpu, bus: anytype) void {
        self.ssp = bus.read32(0x000000);
        self.a[7] = self.ssp;
        self.pc = bus.read32(0x000004);
        self.sr = StatusRegister{ .s = true, .ipl = 7, .t = false };
        self.halted = false;
        self.stopped = false;
        self.cycles = 0;
    }
};
