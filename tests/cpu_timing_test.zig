const std = @import("std");
const testing = std.testing;
const Cpu = @import("m68k").Cpu;
const decode = @import("decode");

const TimingBus = struct {
    mem: [0x20000]u8 = @splat(0),
    debug_pc: u32 = 0,

    pub fn read8(self: *const TimingBus, addr: u32) u8 {
        return self.mem[addr & 0x1FFFF];
    }
    pub fn read16(self: *const TimingBus, addr: u32) u16 {
        return (@as(u16, self.mem[addr & 0x1FFFF]) << 8) | self.mem[(addr + 1) & 0x1FFFF];
    }
    pub fn read32(self: *const TimingBus, addr: u32) u32 {
        return (@as(u32, self.read16(addr)) << 16) | self.read16(addr + 2);
    }
    pub fn write8(self: *TimingBus, addr: u32, v: u8) void {
        self.mem[addr & 0x1FFFF] = v;
    }
    pub fn write16(self: *TimingBus, addr: u32, v: u16) void {
        self.write8(addr, @truncate(v >> 8));
        self.write8(addr + 1, @truncate(v));
    }
    pub fn write32(self: *TimingBus, addr: u32, v: u32) void {
        self.write16(addr, @truncate(v >> 16));
        self.write16(addr + 2, @truncate(v));
    }
    pub fn getInterruptLevel(self: *const TimingBus) u3 {
        _ = self;
        return 0;
    }
};

const Result = struct { name: []const u8, expected: u32, actual: u32 };

fn setupBusAndCpu(bus: *TimingBus) Cpu {
    bus.write32(0x000000, 0x00000800);
    bus.write32(0x000004, 0x00000100);
    var cpu = Cpu.init();
    cpu.reset(bus);
    return cpu;
}

fn run(comptime opcode: u16, expected: u32, setup_fn: *const fn (*Cpu, *TimingBus) void) Result {
    var cpu: Cpu = undefined;
    var bus: TimingBus = .{};
    cpu = setupBusAndCpu(&bus);
    bus.write16(0x0100, opcode);
    setup_fn(&cpu, &bus);
    const cycles = decode.step(&cpu, &bus);
    const name = comptime brk: {
        var buf: [128]u8 = undefined;
        _ = &buf;
        break :brk @typeName(@TypeOf(opcode));
    };
    return .{ .name = name, .expected = expected, .actual = cycles };
}

// ── Setup functions ──

fn setupNone(_: *Cpu, _: *TimingBus) void {}
fn setupSWAP(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x12345678; }
fn setupEXTw(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x000000AB; }
fn setupEXTl(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x00007FFF; }
fn setupRTS(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x07FC; bus.write32(0x07FC, 0x00000200); }
fn setupRTE(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x07F8; bus.write16(0x07F8, 0x2700); bus.write32(0x07FA, 0x00000200); }
fn setupRTR(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x07F8; bus.write16(0x07F8, 0x0000); bus.write32(0x07FA, 0x00000200); }
fn setupSTOP(_: *Cpu, bus: *TimingBus) void { bus.write16(0x0102, 0x2700); }
fn setupTRAP(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x0800; bus.write32(0x000080, 0x00000200); }
fn setupILLEGAL(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x0800; bus.write32(0x000010, 0x00000200); }
fn setupTRAPV_taken(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x0800; bus.write32(0x00004C, 0x00000200); cpu.sr.v = true; }
fn setupTRAPV_not(_: *Cpu, _: *TimingBus) void {}
fn setupLINK(cpu: *Cpu, bus: *TimingBus) void { cpu.a[0] = 0x1000; cpu.a[7] = 0x2000; bus.write16(0x0102, 0xFFF0); }
fn setupUNLK(cpu: *Cpu, bus: *TimingBus) void { cpu.a[0] = 0x0800; cpu.a[7] = 0x07F0; bus.write32(0x0800, 0x1000); }
fn setupNBCD_Dn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x00000099; }
fn setupTAS_Dn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x00000080; }
fn setupPEA_AbsW(cpu: *Cpu, bus: *TimingBus) void { cpu.a[7] = 0x0800; bus.write16(0x0102, 0x2000); }
fn setupANDItoCCR(_: *Cpu, bus: *TimingBus) void { bus.write16(0x0102, 0x00FF); }
fn setupMOVE_W_DnDn(cpu: *Cpu, _: *TimingBus) void { cpu.d[1] = 0x1234; }
fn setupMOVE_L_AnDn(cpu: *Cpu, _: *TimingBus) void { cpu.a[0] = 0x12345678; }
fn setupMOVEA_W_DnAn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x12345678; }
fn setupMOVEA_L_DnAn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x12345678; }
fn setupLEA_AbsW(_: *Cpu, bus: *TimingBus) void { bus.write16(0x0102, 0x2000); }
fn setupLEA_d16An(cpu: *Cpu, bus: *TimingBus) void { cpu.a[0] = 0x1000; bus.write16(0x0102, 0x0010); }
fn setupJMP_An(cpu: *Cpu, _: *TimingBus) void { cpu.a[0] = 0x0200; }
fn setupJMP_AbsW(_: *Cpu, bus: *TimingBus) void { bus.write16(0x0102, 0x0200); }
fn setupJMP_AbsL(_: *Cpu, bus: *TimingBus) void { bus.write32(0x0102, 0x00000200); }
fn setupJSR_An(cpu: *Cpu, _: *TimingBus) void { cpu.a[0] = 0x0200; cpu.a[7] = 0x0800; }
fn setupJSR_AbsW(cpu: *Cpu, bus: *TimingBus) void { bus.write16(0x0102, 0x0200); cpu.a[7] = 0x0800; }
fn setupMULU(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 3; cpu.d[1] = 7; }
fn setupDIVU(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 100; cpu.d[1] = 10; }
fn setupDIVS(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 100; cpu.d[1] = 0xFFFFFFF6; }
fn setupCHK_taken(cpu: *Cpu, bus: *TimingBus) void { cpu.d[0] = 0x00000100; cpu.d[1] = 0x00000050; bus.write32(0x000018, 0x00000200); }
fn setupANDItoSR(cpu: *Cpu, bus: *TimingBus) void { cpu.sr.s = true; bus.write16(0x0102, 0x2700); }
fn setupMOVEtoSR(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x2700; cpu.sr.s = true; }
fn setupMOVEfromSR(_: *Cpu, _: *TimingBus) void {}
fn setupADDX_reg(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 5; cpu.d[1] = 10; }
fn setupNEG_Dn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x00000001; }
fn setupNOT_Dn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x00000001; }
fn setupCLR_Dn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x12345678; }
fn setupTST_Dn(cpu: *Cpu, _: *TimingBus) void { cpu.d[0] = 0x00000001; }

const TestDef = struct { opcode: u16, expected: u32, setup_fn: *const fn (*Cpu, *TimingBus) void };

const tests = [_]TestDef{
    .{ .opcode = 0x4E71, .expected = 4,   .setup_fn = setupNone },
    .{ .opcode = 0x4E70, .expected = 132, .setup_fn = setupNone },
    .{ .opcode = 0x4840, .expected = 4,   .setup_fn = setupSWAP },
    .{ .opcode = 0x48C0, .expected = 4,   .setup_fn = setupEXTw },
    .{ .opcode = 0x48C8, .expected = 4,   .setup_fn = setupEXTl },
    .{ .opcode = 0x4E75, .expected = 16,  .setup_fn = setupRTS },
    .{ .opcode = 0x4E73, .expected = 20,  .setup_fn = setupRTE },
    .{ .opcode = 0x4E77, .expected = 14,  .setup_fn = setupRTR },
    .{ .opcode = 0x4E72, .expected = 4,   .setup_fn = setupSTOP },
    .{ .opcode = 0x4E40, .expected = 34,  .setup_fn = setupTRAP },
    .{ .opcode = 0x4E76, .expected = 34,  .setup_fn = setupTRAPV_taken },
    .{ .opcode = 0x4E76, .expected = 4,   .setup_fn = setupTRAPV_not },
    .{ .opcode = 0x4AFC, .expected = 34,  .setup_fn = setupILLEGAL },
    .{ .opcode = 0x4E50, .expected = 16,  .setup_fn = setupLINK },
    .{ .opcode = 0x4E58, .expected = 12,  .setup_fn = setupUNLK },
    .{ .opcode = 0x4800, .expected = 6,   .setup_fn = setupNBCD_Dn },
    .{ .opcode = 0x4AC0, .expected = 6,   .setup_fn = setupTAS_Dn },
    .{ .opcode = 0x4878, .expected = 12,  .setup_fn = setupPEA_AbsW },
    .{ .opcode = 0x023C, .expected = 20,  .setup_fn = setupANDItoCCR },
    .{ .opcode = 0x003C, .expected = 20,  .setup_fn = setupNone },
    .{ .opcode = 0x0A3C, .expected = 20,  .setup_fn = setupNone },
    .{ .opcode = 0x027C, .expected = 20,  .setup_fn = setupANDItoSR },
    .{ .opcode = 0x007C, .expected = 20,  .setup_fn = setupANDItoSR },
    .{ .opcode = 0x0A7C, .expected = 20,  .setup_fn = setupANDItoSR },
    .{ .opcode = 0x3001, .expected = 4,   .setup_fn = setupMOVE_W_DnDn },
    .{ .opcode = 0x2008, .expected = 4,   .setup_fn = setupMOVE_L_AnDn },
    .{ .opcode = 0x3040, .expected = 4,   .setup_fn = setupMOVEA_W_DnAn },
    .{ .opcode = 0x2040, .expected = 4,   .setup_fn = setupMOVEA_L_DnAn },
    .{ .opcode = 0x7000, .expected = 4,   .setup_fn = setupNone },
    .{ .opcode = 0x40C0, .expected = 6,   .setup_fn = setupMOVEfromSR },
    .{ .opcode = 0x46C0, .expected = 12,  .setup_fn = setupMOVEtoSR },
    .{ .opcode = 0x41F8, .expected = 8,   .setup_fn = setupLEA_AbsW },
    .{ .opcode = 0x41E8, .expected = 8,   .setup_fn = setupLEA_d16An },
    .{ .opcode = 0x4ED0, .expected = 8,   .setup_fn = setupJMP_An },
    .{ .opcode = 0x4EF8, .expected = 10,  .setup_fn = setupJMP_AbsW },
    .{ .opcode = 0x4EF9, .expected = 12,  .setup_fn = setupJMP_AbsL },
    .{ .opcode = 0x4E90, .expected = 16,  .setup_fn = setupJSR_An },
    .{ .opcode = 0x4EB8, .expected = 18,  .setup_fn = setupJSR_AbsW },
    .{ .opcode = 0xD041, .expected = 4,   .setup_fn = setupMULU },
    .{ .opcode = 0x9041, .expected = 4,   .setup_fn = setupMULU },
    .{ .opcode = 0xB041, .expected = 4,   .setup_fn = setupMULU },
    .{ .opcode = 0xD140, .expected = 4,   .setup_fn = setupADDX_reg },
    .{ .opcode = 0x9140, .expected = 4,   .setup_fn = setupADDX_reg },
    .{ .opcode = 0x4440, .expected = 4,   .setup_fn = setupNEG_Dn },
    .{ .opcode = 0x4640, .expected = 4,   .setup_fn = setupNOT_Dn },
    .{ .opcode = 0x4240, .expected = 4,   .setup_fn = setupCLR_Dn },
    .{ .opcode = 0x4A40, .expected = 4,   .setup_fn = setupTST_Dn },
    .{ .opcode = 0xC0C1, .expected = 44,  .setup_fn = setupMULU },
    .{ .opcode = 0x80C1, .expected = 136, .setup_fn = setupDIVU },
    .{ .opcode = 0x81C1, .expected = 150, .setup_fn = setupDIVS },
    .{ .opcode = 0x4181, .expected = 40,  .setup_fn = setupCHK_taken },
};

const names = [_][]const u8{
    "NOP",
    "RESET",
    "SWAP D0",
    "EXT.W D0",
    "EXT.L D0",
    "RTS",
    "RTE",
    "RTR",
    "STOP",
    "TRAP #0",
    "TRAPV (V=1)",
    "TRAPV (V=0)",
    "ILLEGAL 0x4AFC",
    "LINK A0,#-16",
    "UNLK A0",
    "NBCD D0",
    "TAS D0",
    "PEA (Abs.W)",
    "ANDItoCCR",
    "ORItoCCR",
    "EORItoCCR",
    "ANDItoSR",
    "ORItoSR",
    "EORItoSR",
    "MOVE.W D1,D0",
    "MOVE.L A0,D0",
    "MOVEA.W D0,A0",
    "MOVEA.L D0,A0",
    "MOVEQ #0,D0",
    "MOVE.W SR,D0",
    "MOVE.W D0,SR",
    "LEA (Abs.W),A0",
    "LEA d16(A0),A0",
    "JMP (A0)",
    "JMP (Abs.W)",
    "JMP (Abs.L)",
    "JSR (A0)",
    "JSR (Abs.W)",
    "ADD.W D1,D0 (reg)",
    "SUB.W D1,D0 (reg)",
    "CMP.W D1,D0 (reg)",
    "ADDX.L D1,D0",
    "SUBX.L D1,D0",
    "NEG.W D0",
    "NOT.W D0",
    "CLR.W D0",
    "TST.W D0",
    "MULU D1,D0 (3*7)",
    "DIVU D1,D0 (100/10)",
    "DIVS D1,D0 (100/-10)",
    "CHK D1,D0 (taken)",
};

test "CPU timing" {
    var results: [names.len]Result = undefined;
    for (tests, names, &results) |t, n, *r| {
        var bus: TimingBus = .{};
        var cpu = setupBusAndCpu(&bus);
        bus.write16(0x0100, t.opcode);
        t.setup_fn(&cpu, &bus);
        const cycles = decode.step(&cpu, &bus);
        r.* = .{ .name = n, .expected = t.expected, .actual = cycles };
    }

    std.debug.print("\n## Résultats des tests de timing CPU 68000\n\n", .{});
    std.debug.print("| Opcode | Attendu | Obtenu | Statut |\n", .{});
    std.debug.print("|--------|--------:|------:|:------|\n", .{});

    var pass: u32 = 0;
    var fail: u32 = 0;
    for (results) |r| {
        const ok = r.expected == r.actual;
        const status = if (ok) "✅" else "❌";
        if (ok) pass += 1 else fail += 1;
        std.debug.print("| {s} | {d} | {d} | {s} |\n", .{ r.name, r.expected, r.actual, status });
    }

    std.debug.print("\n**Total :** {d} passé(s), {d} échec(s)\n", .{ pass, fail });
    try testing.expectEqual(@as(u32, 0), fail);
}
