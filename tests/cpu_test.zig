const std = @import("std");
const testing = std.testing;
const Cpu = @import("m68k").Cpu;
const decode = @import("decode");

const TestBus = struct {
    mem: [0x1000]u8 = @splat(0),
    debug_pc: u32 = 0,

    pub fn write16at(self: *TestBus, addr: u32, val: u16) void {
        self.mem[addr] = @truncate(val >> 8);
        self.mem[addr + 1] = @truncate(val);
    }
    pub fn write32at(self: *TestBus, addr: u32, val: u32) void {
        self.write16at(addr, @truncate(val >> 16));
        self.write16at(addr + 2, @truncate(val));
    }

    pub fn read8(self: *const TestBus, addr: u32) u8 {
        return self.mem[addr & 0xFFF];
    }
    pub fn read16(self: *const TestBus, addr: u32) u16 {
        return (@as(u16, self.mem[addr & 0xFFF]) << 8) | self.mem[(addr + 1) & 0xFFF];
    }
    pub fn read32(self: *const TestBus, addr: u32) u32 {
        return (@as(u32, self.read16(addr)) << 16) | self.read16(addr + 2);
    }
    pub fn write8(self: *TestBus, addr: u32, v: u8) void {
        self.mem[addr & 0xFFF] = v;
    }
    pub fn write16(self: *TestBus, addr: u32, v: u16) void {
        self.write16at(addr, v);
    }
    pub fn write32(self: *TestBus, addr: u32, v: u32) void {
        self.write32at(addr, v);
    }
    pub fn getInterruptLevel(self: *const TestBus) u3 {
        _ = self;
        return 0;
    }
};

fn makeCpu(bus: *TestBus, opcodes: []const u16) Cpu {
    // SSP = 0x0800, PC = 0x0100 dans les vecteurs
    bus.write32at(0x000000, 0x00000800); // SSP
    bus.write32at(0x000004, 0x00000100); // PC
    for (opcodes, 0..) |op, i| {
        bus.write16at(0x0100 + @as(u32, @intCast(i)) * 2, op);
    }
    var cpu = Cpu.init();
    cpu.reset(bus);
    return cpu;
}

test "ORI EA / CCR / SR" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TEST ORI EA (ORI.B #0x12, D0)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0000}); // reset propre via vecteurs

    cpu.d[0] = 0x10;
    cpu.pc = 0x0102; // après l'opcode déjà lu, pointe sur l'immédiat
    bus.write16at(0x0102, 0x0012); // imm = 0x12

    const opcode_ea: u16 = 0x0000;
    _ = decode.execORI(&cpu, &bus, opcode_ea);

    try testing.expectEqual(@as(u32, 0x12), cpu.d[0]);

    // =========================================================
    // 2. TEST ORI CCR (ORI #0x0F, CCR)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x003C});

    cpu.sr.c = false;
    cpu.sr.z = true;
    cpu.sr.n = false;
    cpu.sr.v = false;
    cpu.sr.x = false;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x001F); //0x1F = 0001 1111 → active X(4) N(3) Z(2) V(1) C(0)

    const opcode_ccr: u16 = 0x003C;
    //std.debug.print("pc={x} mem[pc]={x} mem[pc+1]={x}\n", .{
    //    cpu.pc,
    //    bus.mem[cpu.pc & 0xFFF],
    //    bus.mem[(cpu.pc + 1) & 0xFFF],
    //});
    _ = decode.execORI(&cpu, &bus, opcode_ccr);
    //std.debug.print("sr.x={} sr.n={} sr.z={} sr.v={} sr.c={}\n", .{
    //    cpu.sr.x, cpu.sr.n, cpu.sr.z, cpu.sr.v, cpu.sr.c,
    //});
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.x == true);

    // =========================================================
    // 3. TEST ORI SR (ORI #0x0700, SR)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x007C});

    cpu.sr.set(0x2000);
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0700); // imm = 0x0700

    const opcode_sr: u16 = 0x007C;
    _ = decode.execORI(&cpu, &bus, opcode_sr);

    try testing.expectEqual(@as(u16, 0x2700), cpu.sr.get());
    try testing.expect((cpu.sr.get() & 0x2000) != 0);
    try testing.expect((cpu.sr.get() & 0x0700) == 0x0700);
}

test "Line-A and Line-F opcodes dispatch to dedicated exception vectors" {
    var bus: TestBus = .{};
    bus.write32at(0x000000, 0x00000800);
    bus.write32at(0x000004, 0x00000100);
    bus.write32at(0x000028, 0x00000200); // Line-A vector 10
    bus.write32at(0x00002C, 0x00000240); // Line-F vector 11

    bus.write16at(0x0100, 0xA123);
    var cpu = Cpu.init();
    cpu.reset(&bus);

    _ = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00000200), cpu.pc);

    bus = .{};
    bus.write32at(0x000000, 0x00000800);
    bus.write32at(0x000004, 0x00000100);
    bus.write32at(0x00002C, 0x00000240);
    bus.write16at(0x0100, 0xF123);
    cpu = Cpu.init();
    cpu.reset(&bus);

    _ = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00000240), cpu.pc);
}

test "ANDI EA / CCR / SR" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TEST ANDI EA (ANDI.B #0x12, D0)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0200}); // ANDI opcode

    cpu.d[0] = 0x1F; // D0 = 0x1F (0001 1111)
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0012); // imm = 0x12 (0001 0010)

    const opcode_ea: u16 = 0x0200; // ANDI.B #imm, D0
    _ = decode.execANDI(&cpu, &bus, opcode_ea);

    // 0x1F & 0x12 = 0x12 (0001 1111 & 0001 0010 = 0001 0010)
    try testing.expectEqual(@as(u32, 0x12), cpu.d[0]);

    // =========================================================
    // 2. TEST ANDI CCR (ANDI #0x1F, CCR)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x023C}); // ANDI to CCR

    // CCR initial : X=1 N=1 Z=1 V=1 C=1 (tous à 1, valeur = 0x1F)
    cpu.sr.c = true;
    cpu.sr.v = true;
    cpu.sr.z = true;
    cpu.sr.n = true;
    cpu.sr.x = true;
    cpu.pc = 0x0102;

    // imm = 0x0A (0000 1010) → conserve V(1) et Z(2), reset X(4) N(3) C(0)
    bus.write16at(0x0102, 0x000A);

    const opcode_ccr: u16 = 0x023C; // ANDI to CCR
    _ = decode.execANDI(&cpu, &bus, opcode_ccr);

    // Résultat attendu : C=0, V=1, Z=1, N=0, X=0
    try testing.expect(cpu.sr.c == false); // 1 & 0 = 0
    try testing.expect(cpu.sr.v == true); // 1 & 1 = 1
    try testing.expect(cpu.sr.z == false); // 1 & 1 = 1
    try testing.expect(cpu.sr.n == true); // 1 & 0 = 0
    try testing.expect(cpu.sr.x == false); // 1 & 0 = 0

    // =========================================================
    // 3. TEST ANDI SR (ANDI #0x0700, SR)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x027C}); // ANDI to SR

    // SR initial : S=1, IPL=7, CCR=0x1F → 0x270F
    cpu.sr.set(0x270F);
    cpu.pc = 0x0102;

    // imm = 0x0700 → conserve IPL, reset S et CCR
    bus.write16at(0x0102, 0x0700);

    const opcode_sr: u16 = 0x027C; // ANDI to SR
    _ = decode.execANDI(&cpu, &bus, opcode_sr);

    // 0x270F & 0x0700 = 0x0700 (IPL conservé, S et CCR reset)
    try testing.expectEqual(@as(u16, 0x0700), cpu.sr.get());
    try testing.expect((cpu.sr.get() & 0x2000) == 0); // S = 0
    try testing.expect((cpu.sr.get() & 0x0700) == 0x0700); // IPL = 7
}

test "SUBI" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TEST SUBI.B (Resultat > 0)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0400}); // SUBI opcode

    cpu.d[0] = 0x10;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0005);

    const opcode_ea: u16 = 0x0400; // SUBI.B
    _ = decode.execSUBI(&cpu, &bus, opcode_ea);

    // 0x10 - 0x05 - Premier cas, pas de C, Overflow
    try testing.expectEqual(@as(u32, 0x0B), cpu.d[0]);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);

    // =========================================================
    // 1. TEST SUBI.B #0x01, D0  (résultat = 0, flag Z)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0400});
    cpu.d[0] = 0x01;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0001); // imm = 0x01

    _ = decode.execSUBI(&cpu, &bus, opcode_ea);

    // 0x01 - 0x01 = 0x00
    try testing.expectEqual(@as(u32, 0x00), cpu.d[0]);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.n == false);

    // =========================================================
    // 3. TEST SUBI.B #0x10, D0  (carry : imm > old)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0400});
    cpu.d[0] = 0x05;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0010);

    _ = decode.execSUBI(&cpu, &bus, opcode_ea);

    // 0x05 - 0x10 = 0xF5 (wrapping), emprunt → C=1, X=1
    try testing.expectEqual(@as(u32, 0xF5), cpu.d[0]);
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.x == true);
    try testing.expect(cpu.sr.n == true);

    // =========================================================
    // 4. TEST SUBI.B overflow signé : 0x80 - 0x01 = 0x7F
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0400});
    cpu.d[0] = 0x80; // D0 = -128 en signé
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0001); // imm = 1

    _ = decode.execSUBI(&cpu, &bus, opcode_ea);

    // -128 - 1 = +127 → overflow signé
    try testing.expectEqual(@as(u32, 0x7F), cpu.d[0]);
    try testing.expect(cpu.sr.v == true); // overflow signé
    try testing.expect(cpu.sr.c == false); // pas d'emprunt unsigned
    try testing.expect(cpu.sr.n == false); // résultat positif (0x7F)

    // =========================================================
    // 5. TEST SUBI.W #0x0100, D0  (word)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0440}); // SUBI.W opcode
    cpu.d[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0100); // imm = 0x0100

    const opcode_w: u16 = 0x0440; // SUBI.W #imm, D0
    _ = decode.execSUBI(&cpu, &bus, opcode_w);

    // 0x0200 - 0x0100 = 0x0100
    try testing.expectEqual(@as(u32, 0x0100), cpu.d[0]);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.n == false);
}

test "ADDI EA" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TEST ADDI.B #0x05, D0  (résultat normal, pas de carry)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0600}); // ADDI.B opcode
    cpu.d[0] = 0x10; // D0 = 0x10
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0005); // imm = 0x05

    const opcode_b: u16 = 0x0600; // ADDI.B #imm, D0
    _ = decode.execADDI(&cpu, &bus, opcode_b);

    // 0x10 + 0x05 = 0x15
    try testing.expectEqual(@as(u32, 0x15), cpu.d[0]);
    try testing.expect(cpu.sr.c == false); // pas de carry
    try testing.expect(cpu.sr.x == false);
    try testing.expect(cpu.sr.v == false); // pas d'overflow signé
    try testing.expect(cpu.sr.n == false); // résultat positif
    try testing.expect(cpu.sr.z == false); // résultat non nul

    // =========================================================
    // 2. TEST ADDI.B #0xFF, D0  (résultat = 0, flag Z + carry)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0600});
    cpu.d[0] = 0x01;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x00FF); // imm = 0xFF

    _ = decode.execADDI(&cpu, &bus, opcode_b);

    // 0x01 + 0xFF = 0x100 → résultat byte = 0x00, carry = 1
    try testing.expectEqual(@as(u32, 0x00), cpu.d[0]);
    try testing.expect(cpu.sr.z == true); // résultat nul
    try testing.expect(cpu.sr.c == true); // carry
    try testing.expect(cpu.sr.x == true); // X suit C
    try testing.expect(cpu.sr.n == false);

    // =========================================================
    // 3. TEST ADDI.B #0x10, D0  (carry : résultat > 0xFF)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0600});
    cpu.d[0] = 0xF0; // D0 = 0xF0
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0020); // imm = 0x20

    _ = decode.execADDI(&cpu, &bus, opcode_b);

    // 0xF0 + 0x20 = 0x110 → résultat byte = 0x10, carry = 1
    try testing.expectEqual(@as(u32, 0x10), cpu.d[0]);
    try testing.expect(cpu.sr.c == true); // carry
    try testing.expect(cpu.sr.x == true); // X suit C
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);

    // =========================================================
    // 4. TEST ADDI.B overflow signé : 0x7F + 0x01 = 0x80
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0600});
    cpu.d[0] = 0x7F; // D0 = +127 en signé
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0001); // imm = 1

    _ = decode.execADDI(&cpu, &bus, opcode_b);

    // +127 + 1 = -128 → overflow signé
    try testing.expectEqual(@as(u32, 0x80), cpu.d[0]);
    try testing.expect(cpu.sr.v == true); // overflow signé
    try testing.expect(cpu.sr.c == false); // pas de carry unsigned
    try testing.expect(cpu.sr.n == true); // bit 7 à 1 (résultat négatif)
    try testing.expect(cpu.sr.z == false);

    // =========================================================
    // 5. TEST ADDI.B overflow signé négatif : 0x80 + 0x80 = 0x00
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0600});
    cpu.d[0] = 0x80; // D0 = -128 en signé
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0080); // imm = 0x80 (-128)

    _ = decode.execADDI(&cpu, &bus, opcode_b);

    // -128 + -128 = 0x100 → résultat byte = 0x00, carry=1, overflow=1
    try testing.expectEqual(@as(u32, 0x00), cpu.d[0]);
    try testing.expect(cpu.sr.v == true); // overflow : négatif + négatif = positif
    try testing.expect(cpu.sr.c == true); // carry
    try testing.expect(cpu.sr.x == true);
    try testing.expect(cpu.sr.z == true); // résultat nul

    // =========================================================
    // 6. TEST ADDI.W #0x0100, D0  (word)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0640}); // ADDI.W opcode
    cpu.d[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0100); // imm = 0x0100

    const opcode_w: u16 = 0x0640; // ADDI.W #imm, D0
    _ = decode.execADDI(&cpu, &bus, opcode_w);

    // 0x0200 + 0x0100 = 0x0300
    try testing.expectEqual(@as(u32, 0x0300), cpu.d[0]);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.v == false);
}

test "EORI EA / CCR / SR" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TEST EORI.B #0x0F, D0 (XOR normal registre)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0A00}); // EORI.B
    cpu.d[0] = 0xFF;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x000F); // imm = 0x0F

    const opcode_b: u16 = 0x0A00;
    _ = decode.execEORI(&cpu, &bus, opcode_b);

    // 0xFF ^ 0x0F = 0xF0
    try testing.expectEqual(@as(u32, 0xF0), cpu.d[0]);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.n == true); // bit 7 = 1
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);

    // =========================================================
    // 2. TEST EORI.B #0xFF, D0 (résultat zéro)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0A00});
    cpu.d[0] = 0xFF;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x00FF);

    _ = decode.execEORI(&cpu, &bus, opcode_b);

    // 0xFF ^ 0xFF = 0x00
    try testing.expectEqual(@as(u32, 0x00), cpu.d[0]);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == false);

    // =========================================================
    // 3. TEST EORI CCR (0x0A3C)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0A3C});
    cpu.pc = 0x0102;

    cpu.sr.set((cpu.sr.get() & 0xFFE0) | 0x1F);

    bus.write16at(0x0102, 0x000F); // imm = 0000 1111

    const opcode_ccr: u16 = 0x0A3C;
    _ = decode.execEORI(&cpu, &bus, opcode_ccr);

    // 0x1F ^ 0x0F = 0x10
    try testing.expectEqual(@as(u32, 0x10), cpu.sr.get() & 0x1F);

    // =========================================================
    // 4. TEST EORI SR (0x0A7C)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0A7C});
    cpu.pc = 0x0102;

    cpu.sr.set(0x2700); // état initial SR Mode user, pas de trace et masque d'interruption simple
    bus.write16at(0x0102, 0x1234);

    const opcode_sr: u16 = 0x0A7C;
    _ = decode.execEORI(&cpu, &bus, opcode_sr);

    // 0x2700 ^ 0x1234 = résultat attendu
    try testing.expectEqual(@as(u32, 0x2700 ^ 0x1234), cpu.sr.get());
}

test "CMPI EA" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TEST CMPI.B #0x10, D0  Egalite
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0600}); // ADDI.B opcode
    cpu.d[0] = 0x10; // D0 = 0x10
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0010);

    const opcode_b: u16 = 0x0C00;
    _ = decode.execCMPI(&cpu, &bus, opcode_b);

    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == true);

    // =========================================================
    // 2. CMPI.B #0x20, D0  (borrow → C=1, résultat négatif)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0C00});
    cpu.d[0] = 0x10;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0020);

    _ = decode.execCMPI(&cpu, &bus, opcode_b);

    // 0x10 - 0x20 = 0xF0 (byte)
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.z == false);

    // =========================================================
    // 3. CMPI.B #0x01, D0  (résultat positif)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0C00});
    cpu.d[0] = 0x10;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0001);

    _ = decode.execCMPI(&cpu, &bus, opcode_b);

    // 0x10 - 0x01 = 0x0F
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.z == false);

    // =========================================================
    // 4. CMPI.B overflow signé : 0x80 - 0x01
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0C00});
    cpu.d[0] = 0x80; // -128
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0001);

    _ = decode.execCMPI(&cpu, &bus, opcode_b);

    // -128 - 1 = +127 → overflow signé
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.c == false);

    // =========================================================
    // 5. CMPI.B overflow signé : 0x7F - 0xFF
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0C00});
    cpu.d[0] = 0x7F; // +127
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x00FF); // -1

    _ = decode.execCMPI(&cpu, &bus, opcode_b);

    // 127 - (-1) = 128 → overflow
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.n == true);

    // =========================================================
    // 6. CMPI.W #0x0100, D0 (word)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0C40}); // CMPI.W
    cpu.d[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0100);

    const opcode_w: u16 = 0x0C40;
    _ = decode.execCMPI(&cpu, &bus, opcode_w);

    // 0x0200 - 0x0100 = 0x0100
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.v == false);
}
test "BTST" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. BTST #2, D0 — bit 2 de D0 = 1 → Z=0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0800});
    cpu.d[0] = 0x04; // bit 2 = 1
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0002); // imm = 2

    const opcode_imm: u16 = 0x0800; // BTST #n, D0
    _ = decode.execBitOp(&cpu, &bus, opcode_imm, .btst);

    try testing.expect(cpu.sr.z == false); // bit présent → Z=0

    // =========================================================
    // 2. BTST #3, D0 — bit 3 de D0 = 0 → Z=1
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0800});
    cpu.d[0] = 0x04; // bit 3 = 0
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0003); // imm = 3

    _ = decode.execBitOp(&cpu, &bus, opcode_imm, .btst);

    try testing.expect(cpu.sr.z == true); // bit absent → Z=1

    // =========================================================
    // 3. BTST Dn, D0 — registre source
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0900}); // BTST D4, D0
    cpu.d[0] = 0x10; // bit 4 = 1
    cpu.d[4] = 4; // numéro de bit = 4
    cpu.pc = 0x0102;

    const opcode_reg: u16 = 0x0900; // BTST D4, D0 (src=D4, dst=D0)
    _ = decode.execBitOp(&cpu, &bus, opcode_reg, .btst);

    try testing.expect(cpu.sr.z == false); // bit 4 présent → Z=0

    // =========================================================
    // 4. BTST modulo 32 sur registre : bit 34 = bit 2
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0900});
    cpu.d[0] = 0x04; // bit 2 = 1
    cpu.d[4] = 34; // 34 & 0x1F = 2
    cpu.pc = 0x0102;

    _ = decode.execBitOp(&cpu, &bus, opcode_reg, .btst);

    try testing.expect(cpu.sr.z == false); // bit 2 présent → Z=0

    // =========================================================
    // 5. BTST #1, (mem) — mémoire, modulo 8
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0810}); // BTST #n, (A0)
    cpu.a[0] = 0x0200;
    bus.write16at(0x0200, 0x0200); // mem[0x0200] = 0x02 (bit 1 = 1)
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0001); // imm = 1

    const opcode_mem: u16 = 0x0810; // BTST #n, (A0)
    _ = decode.execBitOp(&cpu, &bus, opcode_mem, .btst);

    try testing.expect(cpu.sr.z == false); // bit 1 présent → Z=0
}

test "MOVEP" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. MOVEP.W Dn → mémoire (opmode=00) : D0=0x1234, (0x10, A0)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0008});
    cpu.d[0] = 0x1234;
    cpu.a[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0010); // displacement = 0x10
    const opcode_w_to_mem: u16 = 0x0008;
    _ = decode.execMOVEP(&cpu, &bus, opcode_w_to_mem);
    // addr = 0x0200 + 0x10 = 0x0210
    try testing.expectEqual(@as(u8, 0x12), bus.mem[0x0210]); // octet haut
    try testing.expectEqual(@as(u8, 0x00), bus.mem[0x0211]); // non écrit
    try testing.expectEqual(@as(u8, 0x34), bus.mem[0x0212]); // octet bas

    // =========================================================
    // 2. MOVEP.L Dn → mémoire (opmode=01) : D0=0x12345678, (0x00, A0)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0048});
    cpu.d[0] = 0x12345678;
    cpu.a[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0000); // displacement = 0
    const opcode_l_to_mem: u16 = 0x0048;
    _ = decode.execMOVEP(&cpu, &bus, opcode_l_to_mem);
    try testing.expectEqual(@as(u8, 0x12), bus.mem[0x0200]);
    try testing.expectEqual(@as(u8, 0x00), bus.mem[0x0201]); // non écrit
    try testing.expectEqual(@as(u8, 0x34), bus.mem[0x0202]);
    try testing.expectEqual(@as(u8, 0x00), bus.mem[0x0203]); // non écrit
    try testing.expectEqual(@as(u8, 0x56), bus.mem[0x0204]);
    try testing.expectEqual(@as(u8, 0x00), bus.mem[0x0205]); // non écrit
    try testing.expectEqual(@as(u8, 0x78), bus.mem[0x0206]);

    // =========================================================
    // 3. MOVEP.W mémoire → Dn (opmode=10) : mem → D0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0088});
    cpu.d[0] = 0xFFFFFFFF; // valeur initiale pour vérifier l'écrasement word bas
    cpu.a[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0010); // displacement = 0x10
    bus.mem[0x0210] = 0xAB;
    bus.mem[0x0212] = 0xCD;
    const opcode_w_from_mem: u16 = 0x0088;
    _ = decode.execMOVEP(&cpu, &bus, opcode_w_from_mem);
    // opmode 10 écrase tout D0 (pas juste le word bas)
    try testing.expectEqual(@as(u32, 0x0000ABCD), cpu.d[0]);

    // =========================================================
    // 4. MOVEP.L mémoire → Dn (opmode=11) : mem → D0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x00C8});
    cpu.d[0] = 0x00000000;
    cpu.a[0] = 0x0200;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0x0000); // displacement = 0
    bus.mem[0x0200] = 0xDE;
    bus.mem[0x0202] = 0xAD;
    bus.mem[0x0204] = 0xBE;
    bus.mem[0x0206] = 0xEF;
    const opcode_l_from_mem: u16 = 0x00C8;
    _ = decode.execMOVEP(&cpu, &bus, opcode_l_from_mem);
    try testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.d[0]);

    // =========================================================
    // 5. MOVEP.W Dn → mémoire avec displacement négatif
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x0008});
    cpu.d[0] = 0xCAFE;
    cpu.a[0] = 0x0210;
    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0xFFF0); // displacement = -0x10
    _ = decode.execMOVEP(&cpu, &bus, opcode_w_to_mem);
    // addr = 0x0210 + (-0x10) = 0x0200
    try testing.expectEqual(@as(u8, 0xCA), bus.mem[0x0200]);
    try testing.expectEqual(@as(u8, 0xFE), bus.mem[0x0202]);
}

test "MOVEA" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. MOVEA.W D0, A0 — registre données vers adresse (word, sign-extend)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3040}); // MOVEA.W D0, A0

    cpu.d[0] = 0x00008000; // D0 = 0x00008000 (bit 15 = 1)
    cpu.a[0] = 0xFFFFFFFF; // A0 initialisé à une valeur connue

    const opcode_w_dn: u16 = 0x3040; // MOVEA.W D0, A0
    const cycles1 = decode.execMOVEA(&cpu, &bus, opcode_w_dn);

    // Sign-extend : 0x8000 (bit 15=1) → 0xFFFF8000
    try testing.expectEqual(@as(u32, 0xFFFF8000), cpu.a[0]);
    try testing.expectEqual(@as(u32, 4), cycles1);

    // =========================================================
    // 2. MOVEA.W D1, A1 — valeur positive, pas d'extension
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3241}); // MOVEA.W D1, A1

    cpu.d[1] = 0x00001234; // D1 = 0x1234 (positif)
    cpu.a[1] = 0xFFFFFFFF;

    //("Test: d[1]=0x{X:08} a[1]=0x{X:08}\n", .{ cpu.d[1], cpu.a[1] });

    const opcode_w_pos: u16 = 0x3241; // MOVEA.W D1, A1
    _ = decode.execMOVEA(&cpu, &bus, opcode_w_pos);

    //std.debug.print("Result: a[1]=0x{X:08}\n", .{cpu.a[1]});

    // Pas de sign-extend : 0x1234 → 0x00001234
    try testing.expectEqual(@as(u32, 0x00001234), cpu.a[1]);

    // =========================================================
    // 3. MOVEA.L D2, A2 — long, pas d'extension
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x2442}); // MOVEA.L D2, A2

    cpu.d[2] = 0xDEADBEEF; // D2 = 0xDEADBEEF
    cpu.a[2] = 0x00000000;

    const opcode_l_dn: u16 = 0x2442; // MOVEA.L D2, A2
    const cycles3 = decode.execMOVEA(&cpu, &bus, opcode_l_dn);

    try testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.a[2]);
    try testing.expectEqual(@as(u32, 4), cycles3);

    // =========================================================
    // 4. MOVEA.W (A0), A1 — adressage indirect
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3250}); // MOVEA.W (A0), A1

    cpu.a[0] = 0x0200; // A0 pointe sur la mémoire
    cpu.a[1] = 0xFFFFFFFF;

    // Préparer la mémoire : valeur 0x8765 à l'adresse 0x0200
    bus.write16at(0x0200, 0x8765);

    const opcode_w_ind: u16 = 0x3250; // MOVEA.W (A0), A1
    const cycles4 = decode.execMOVEA(&cpu, &bus, opcode_w_ind);

    // Sign-extend : 0x8765 (bit 15=1) → 0xFFFF8765
    try testing.expectEqual(@as(u32, 0xFFFF8765), cpu.a[1]);
    try testing.expectEqual(@as(u32, 8), cycles4);

    // =========================================================
    // 5. MOVEA.L (A0)+, A2 — adressage indirect avec post-incrément
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x2458}); // MOVEA.L (A0)+, A2

    cpu.a[0] = 0x0300; // A0 pointe sur la mémoire
    cpu.a[2] = 0x00000000;

    // Préparer la mémoire : valeur 0x12345678 à l'adresse 0x0300
    bus.write32at(0x0300, 0x12345678);

    const opcode_l_postinc: u16 = 0x2458; // MOVEA.L (A0)+, A2
    const cycles5 = decode.execMOVEA(&cpu, &bus, opcode_l_postinc);

    try testing.expectEqual(@as(u32, 0x12345678), cpu.a[2]);
    try testing.expectEqual(@as(u32, 0x0304), cpu.a[0]); // A0 incrémenté de 4 (long)
    try testing.expectEqual(@as(u32, 12), cycles5);

    // =========================================================
    // 6. MOVEA.W #imm, A0 — adressage immédiat
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x307C}); // MOVEA.W #imm, A0

    cpu.pc = 0x0102;
    bus.write16at(0x0102, 0xFF00); // immédiat = 0xFF00 (négatif)

    const opcode_w_imm: u16 = 0x307C; // MOVEA.W #imm, A0
    const cycles6 = decode.execMOVEA(&cpu, &bus, opcode_w_imm);

    // Sign-extend : 0xFF00 → 0xFFFFFF00
    try testing.expectEqual(@as(u32, 0xFFFFFF00), cpu.a[0]);
    try testing.expectEqual(@as(u32, 8), cycles6);

    // =========================================================
    // 7. MOVEA.L Abs.L, A0 — adressage absolu long
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x2079}); // MOVEA.L Abs.L, A0

    cpu.pc = 0x0102;
    bus.write32at(0x0102, 0x00000400); // adresse absolue = 0x00000400

    // Préparer la mémoire à l'adresse absolue
    bus.write32at(0x0400, 0xCAFEBABE);

    const opcode_l_abs: u16 = 0x2079; // MOVEA.L Abs.L, A0
    const cycles7 = decode.execMOVEA(&cpu, &bus, opcode_l_abs);

    try testing.expectEqual(@as(u32, 0xCAFEBABE), cpu.a[0]);
    try testing.expectEqual(@as(u32, 20), cycles7);

    // =========================================================
    // 8. Vérification : MOVEA ne modifie pas les flags
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3200}); // MOVEA.W D0, A0

    cpu.d[0] = 0x00000000;
    cpu.a[0] = 0x12345678;

    // Mettre tous les flags à 1
    cpu.sr.c = true;
    cpu.sr.v = true;
    cpu.sr.z = true;
    cpu.sr.n = true;
    cpu.sr.x = true;

    _ = decode.execMOVEA(&cpu, &bus, 0x3200);

    // Vérifier que les flags ne sont PAS modifiés
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.x == true);
}

test "MOVE" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. MOVE.B D0, D1 — registre vers registre byte
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x1200});
    cpu.d[0] = 0x000000FF;
    cpu.d[1] = 0x00000000;
    // 0x1200 = 0001 001 000 000 000
    // size=byte, dst=D1 (mode=000,reg=001), src=D0 (mode=000,reg=000)
    const opcode_b_dn: u16 = 0x1200;
    const cycles1 = decode.execMOVE(&cpu, &bus, opcode_b_dn);
    try testing.expectEqual(@as(u32, 0x000000FF), cpu.d[1]);
    try testing.expect(cpu.sr.n == true); // bit 7 = 1
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expectEqual(@as(u32, 4), cycles1);

    // =========================================================
    // 2. MOVE.W D0, D1 — word, flag Z
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3200});
    cpu.d[0] = 0x00000000;
    cpu.d[1] = 0xFFFFFFFF;
    // 0x3200 = 0011 001 000 000 000
    // size=word, dst=D1 (mode=000,reg=001), src=D0 (mode=000,reg=000)
    const opcode_w_dn: u16 = 0x3200;
    const cycles2 = decode.execMOVE(&cpu, &bus, opcode_w_dn);
    try testing.expectEqual(@as(u32, 0xFFFF0000), cpu.d[1]); // word bas écrasé
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == false);
    try testing.expectEqual(@as(u32, 4), cycles2);

    // =========================================================
    // 3. MOVE.L D0, D1 — long
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x2200});
    cpu.d[0] = 0xDEADBEEF;
    cpu.d[1] = 0x00000000;
    // 0x2200 = 0010 001 000 000 000
    // size=long, dst=D1 (mode=000,reg=001), src=D0 (mode=000,reg=000)
    const opcode_l_dn: u16 = 0x2200;
    const cycles3 = decode.execMOVE(&cpu, &bus, opcode_l_dn);
    try testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.d[1]);
    try testing.expect(cpu.sr.n == true); // bit 31 = 1
    try testing.expect(cpu.sr.z == false);
    try testing.expectEqual(@as(u32, 4), cycles3);

    // =========================================================
    // 4. MOVE.W D0, (A0) — registre vers mémoire indirecte
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3080});
    cpu.d[0] = 0x00001234;
    cpu.a[0] = 0x0300;
    // 0x3080 = 0011 000 010 000 000
    // size=word, dst=(A0) (mode=010,reg=000), src=D0 (mode=000,reg=000)
    const opcode_w_mem: u16 = 0x3080;
    //std.debug.print("AVANT: d0=0x{X} a0=0x{X}\n", .{ cpu.d[0], cpu.a[0] });
    const cycles4 = decode.execMOVE(&cpu, &bus, opcode_w_mem);

    try testing.expectEqual(@as(u16, 0x1234), bus.read16(0x0300));
    try testing.expectEqual(@as(u32, 8), cycles4); // 4(dst An) + 8(dst mem)

    // =========================================================
    // 5. MOVE.W (A0), D1 — mémoire indirecte vers registre
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x3050});
    cpu.a[0] = 0x0300;
    cpu.d[1] = 0x00000000;
    bus.write16at(0x0300, 0x8000); // valeur négative
    // 0x3210 = 0011 001 000 010 000
    // size=word, dst=D1 (mode=000,reg=001), src=(A0) (mode=010,reg=000)
    const opcode_w_ind: u16 = 0x3210;
    const cycles5 = decode.execMOVE(&cpu, &bus, opcode_w_ind);
    try testing.expectEqual(@as(u32, 0x00008000), cpu.d[1]);
    try testing.expect(cpu.sr.n == true); // bit 15 = 1
    try testing.expectEqual(@as(u32, 8), cycles5); // 4(dst Dn) + 4(src An ind)

    // =========================================================
    // 6. MOVE.W (A0)+, (A1)+ — post-incrément vers post-incrément
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x32D8});
    cpu.a[0] = 0x0300;
    cpu.a[1] = 0x0400;
    bus.write16at(0x0300, 0x5A5A);
    // 0x32D8 = 0011 001 011 011 000
    // size=word, dst=(A1)+ (mode=011,reg=001), src=(A0)+ (mode=011,reg=000)
    const opcode_w_postinc: u16 = 0x32D8;
    const cycles6 = decode.execMOVE(&cpu, &bus, opcode_w_postinc);
    try testing.expectEqual(@as(u16, 0x5A5A), bus.read16(0x0400));
    try testing.expectEqual(@as(u32, 0x0302), cpu.a[0]); // +2 word
    try testing.expectEqual(@as(u32, 0x0402), cpu.a[1]); // +2 word
    try testing.expectEqual(@as(u32, 12), cycles6); // 4(src An+) + 8(dst An+)

    // =========================================================
    // 7. MOVE.L #imm, D0 — immédiat vers registre
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x203C});
    cpu.pc = 0x0102;
    bus.write32at(0x0102, 0x12345678);
    // 0x203C = 0010 000 000 111 100
    // size=long, dst=D0, src=#imm(mode=111,reg=100)
    const opcode_l_imm: u16 = 0x203C;
    const cycles7 = decode.execMOVE(&cpu, &bus, opcode_l_imm);
    try testing.expectEqual(@as(u32, 0x12345678), cpu.d[0]);
    try testing.expectEqual(@as(u32, 12), cycles7); // MOVE.L #imm, Dn = 12 cycles

    // =========================================================
    // 8. MOVE ne modifie pas X
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x1200});
    cpu.d[0] = 0x42;
    cpu.sr.x = true;
    _ = decode.execMOVE(&cpu, &bus, opcode_b_dn);
    try testing.expect(cpu.sr.x == true); // X inchangé
}

test "TST" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. TST.B D0 — byte positif
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A00});
    cpu.d[0] = 0x0000007F;
    // 0x4A00 = 0100 1010 0000 0000
    // size=byte, mode=000 (Dn), reg=D0
    const cycles1 = decode.execTST(&cpu, &bus, 0x4A00);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expectEqual(@as(u32, 4), cycles1);

    // =========================================================
    // 2. TST.B D0 — byte négatif (bit 7 = 1)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A00});
    cpu.d[0] = 0x00000080;
    const cycles2 = decode.execTST(&cpu, &bus, 0x4A00);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expectEqual(@as(u32, 4), cycles2);

    // =========================================================
    // 3. TST.B D0 — zéro
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A00});
    cpu.d[0] = 0x00000000;
    const cycles3 = decode.execTST(&cpu, &bus, 0x4A00);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == false);
    try testing.expectEqual(@as(u32, 4), cycles3);

    // =========================================================
    // 4. TST.W D0 — word négatif (bit 15 = 1)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A40});
    cpu.d[0] = 0x00008000;
    // 0x4A40 = 0100 1010 0100 0000
    // size=word, mode=000, reg=D0
    const cycles4 = decode.execTST(&cpu, &bus, 0x4A40);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expectEqual(@as(u32, 4), cycles4);

    // =========================================================
    // 5. TST.L D0 — long négatif (bit 31 = 1)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A80});
    cpu.d[0] = 0x80000000;
    // 0x4A80 = 0100 1010 1000 0000
    // size=long, mode=000, reg=D0
    const cycles5 = decode.execTST(&cpu, &bus, 0x4A80);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expectEqual(@as(u32, 4), cycles5);

    // =========================================================
    // 6. TST.W (A0) — mémoire indirecte
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A50});
    cpu.a[0] = 0x0300;
    bus.write16at(0x0300, 0x0000);
    // 0x4A50 = 0100 1010 0101 0000
    // size=word, mode=010 (An), reg=A0
    const cycles6 = decode.execTST(&cpu, &bus, 0x4A50);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == false);
    try testing.expectEqual(@as(u32, 8), cycles6);

    // =========================================================
    // 7. TST ne modifie pas X
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A00});
    cpu.d[0] = 0x42;
    cpu.sr.x = true;
    _ = decode.execTST(&cpu, &bus, 0x4A00);
    try testing.expect(cpu.sr.x == true); // X inchangé

    // =========================================================
    // 8. TST.B D0 — V et C forcés à 0 même si set avant
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4A00});
    cpu.d[0] = 0xFF;
    cpu.sr.v = true;
    cpu.sr.c = true;
    _ = decode.execTST(&cpu, &bus, 0x4A00);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.n == true); // 0xFF → bit 7 = 1
}

test "LEA" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. LEA $1000.W, A0 — absolute short positif
    // =========================================================
    // 0x41F8 = 0100 0001 1111 1000 → LEA, An=A0, mode=111, reg=000
    // mot suivant = 0x1000 (adresse)
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x41F8, 0x1000 });
    cpu.pc += 2;
    const cycles1 = decode.execLEA(&cpu, &bus, 0x41F8);
    try testing.expectEqual(@as(u32, 0x00001000), cpu.a[0]);
    try testing.expectEqual(@as(u32, 8), cycles1);

    // =========================================================
    // 2. LEA $C000.W, A1 — absolute short, sign-extension
    // $C000 = 0xC000 → sign-étendu sur 32 bits = 0xFFFFC000
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x43F8, 0xC000 });
    // 0x43F8 = 0100 0011 1111 1000 → An=A1
    cpu.pc += 2;
    const cycles2 = decode.execLEA(&cpu, &bus, 0x43F8);
    try testing.expectEqual(@as(u32, 0xFFFFC000), cpu.a[1]);
    try testing.expectEqual(@as(u32, 8), cycles2);

    // =========================================================
    // 3. LEA $00FF0000.L, A2 — absolute long
    // 0x45F9 = 0100 0101 1111 1001 → An=A2, mode=111, reg=001
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x45F9, 0x00FF, 0x0000 });
    cpu.pc += 2;
    const cycles3 = decode.execLEA(&cpu, &bus, 0x45F9);
    try testing.expectEqual(@as(u32, 0x00FF0000), cpu.a[2]);
    try testing.expectEqual(@as(u32, 12), cycles3);

    // =========================================================
    // 4. LEA (A3), A4 — indirect register
    // 0x49D3 = 0100 1001 1101 0011 → An=A4, mode=010, reg=A3
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x49D3});
    cpu.a[3] = 0x00002000;
    const cycles4 = decode.execLEA(&cpu, &bus, 0x49D3);
    try testing.expectEqual(@as(u32, 0x00002000), cpu.a[4]);
    try testing.expectEqual(@as(u32, 4), cycles4);

    // =========================================================
    // 5. LEA (d16, A0), A1 — indirect avec déplacement
    // 0x43E8 = 0100 0011 1110 1000 → An=A1, mode=101, reg=A0
    // mot suivant = 0x0010 (disp = +16)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x43E8, 0x0010 });
    cpu.pc += 2;
    cpu.a[0] = 0x00003000;
    //std.debug.print("AVANT execLEA: pc=0x{X} a[0]=0x{X}\n", .{ cpu.pc, cpu.a[0] });
    const cycles5 = decode.execLEA(&cpu, &bus, 0x43E8);
    //std.debug.print("APRÈS execLEA: a[1]=0x{X}\n", .{cpu.a[1]});
    try testing.expectEqual(@as(u32, 8), cycles5);

    // =========================================================
    // 6. LEA (d16, A0), A1 — déplacement négatif
    // mot suivant = 0xFFF0 (disp = -16)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x43E8, 0xFFF0 });
    cpu.pc += 2;
    cpu.a[0] = 0x00003000;
    const cycles6 = decode.execLEA(&cpu, &bus, 0x43E8);
    try testing.expectEqual(@as(u32, 0x00002FF0), cpu.a[1]);
    try testing.expectEqual(@as(u32, 8), cycles6);

    // =========================================================
    // 7. LEA ne modifie pas les flags SR
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x41F8, 0x1000 });
    cpu.sr.n = true;
    cpu.sr.z = true;
    cpu.sr.v = true;
    cpu.sr.c = true;
    cpu.sr.x = true;
    _ = decode.execLEA(&cpu, &bus, 0x41F8);
    try testing.expect(cpu.sr.n == true); // inchangé
    try testing.expect(cpu.sr.z == true); // inchangé
    try testing.expect(cpu.sr.v == true); // inchangé
    try testing.expect(cpu.sr.c == true); // inchangé
    try testing.expect(cpu.sr.x == true); // inchangé

    // =========================================================
    // 8. LEA ne modifie pas les autres registres An
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{ 0x41F8, 0x5000 });
    cpu.pc += 2;
    cpu.a[1] = 0xDEADBEEF;
    cpu.a[2] = 0xCAFEBABE;
    _ = decode.execLEA(&cpu, &bus, 0x41F8);
    try testing.expectEqual(@as(u32, 0x00005000), cpu.a[0]); // destination
    try testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.a[1]); // intact
    try testing.expectEqual(@as(u32, 0xCAFEBABE), cpu.a[2]); // intact
}
test "ADDQ" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 1. ADDQ.B #1, D0 — byte, immédiat 1
    // 0x5200 = 0101 0010 0000 0000 → data=1, size=byte, mode=Dn, reg=D0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5200});
    cpu.d[0] = 0x00000010;
    const cycles1 = decode.execADDQ(&cpu, &bus, 0x5200);
    try testing.expectEqual(@as(u32, 0x00000011), cpu.d[0]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expectEqual(@as(u32, 4), cycles1);

    // =========================================================
    // 2. ADDQ.B #8, D0 — data=0 → imm=8
    // 0x5000 = 0101 0000 0000 0000 → data=0 (=8), size=byte, Dn, D0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5000});
    cpu.d[0] = 0x00000001;
    const cycles2 = decode.execADDQ(&cpu, &bus, 0x5000);
    try testing.expectEqual(@as(u32, 0x00000009), cpu.d[0]);
    try testing.expectEqual(@as(u32, 4), cycles2);

    // =========================================================
    // 3. ADDQ.B #1, D0 — résultat zéro (0xFF + 1 = 0x00)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5200});
    cpu.d[0] = 0x000000FF;
    _ = decode.execADDQ(&cpu, &bus, 0x5200);
    try testing.expectEqual(@as(u32, 0x00000000), cpu.d[0] & 0xFF);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.c == true); // carry : débordement non signé
    try testing.expect(cpu.sr.x == true); // X = C

    // =========================================================
    // 4. ADDQ.B #1, D0 — résultat négatif (bit 7 = 1)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5200});
    cpu.d[0] = 0x0000007F; // 0x7F + 1 = 0x80 → overflow signé
    _ = decode.execADDQ(&cpu, &bus, 0x5200);
    try testing.expectEqual(@as(u32, 0x80), cpu.d[0] & 0xFF);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.v == true); // overflow signé
    try testing.expect(cpu.sr.c == false); // pas de carry non signé

    // =========================================================
    // 5. ADDQ.W #4, D1 — word
    // 0x5841 = 0101 1000 0100 0001 → data=4, size=word, Dn, D1
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5841});
    cpu.d[1] = 0x00001000;
    const cycles5 = decode.execADDQ(&cpu, &bus, 0x5841);
    try testing.expectEqual(@as(u32, 0x00001004), cpu.d[1]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expectEqual(@as(u32, 4), cycles5);

    // =========================================================
    // 6. ADDQ.L #2, D2 — long
    // 0x5482 = 0101 0100 1000 0010 → data=2, size=long, Dn, D2
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5482});
    cpu.d[2] = 0x00000100;
    const cycles6 = decode.execADDQ(&cpu, &bus, 0x5482);
    try testing.expectEqual(@as(u32, 0x00000102), cpu.d[2]);
    try testing.expectEqual(@as(u32, 8), cycles6);

    // =========================================================
    // 7. ADDQ.W #1, A0 — sur An : pas de flags, toujours long
    // 0x5248 = 0101 0010 0100 1000 → data=1, size=word, An, A0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5248});
    cpu.a[0] = 0x00003000;
    cpu.sr.n = true; // flags ne doivent pas changer
    cpu.sr.z = true;
    const cycles7 = decode.execADDQ(&cpu, &bus, 0x5248);
    try testing.expectEqual(@as(u32, 0x00003001), cpu.a[0]);
    try testing.expect(cpu.sr.n == true); // inchangé
    try testing.expect(cpu.sr.z == true); // inchangé
    try testing.expectEqual(@as(u32, 8), cycles7);

    // =========================================================
    // 8. ADDQ.W #3, (A0) — mémoire indirecte
    // 0x5650 = 0101 0110 0101 0000 → data=3, size=word, (An), A0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5650});
    cpu.a[0] = 0x0300;
    bus.write16at(0x0300, 0x0010);
    const cycles8 = decode.execADDQ(&cpu, &bus, 0x5650);
    try testing.expectEqual(@as(u16, 0x0013), bus.read16(0x0300));
    try testing.expectEqual(@as(u32, 12), cycles8);

    // =========================================================
    // 9. ADDQ.B #1, D0 — X est mis à jour comme C
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5200});
    cpu.d[0] = 0x00000010;
    cpu.sr.x = true; // X avant = true
    _ = decode.execADDQ(&cpu, &bus, 0x5200);
    try testing.expect(cpu.sr.x == false); // pas de carry → X = false

    // =========================================================
    // 10. ADDQ.B #1, D0 — V et C forcés à 0 si pas de débordement
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5200});
    cpu.d[0] = 0x00000001;
    cpu.sr.v = true;
    cpu.sr.c = true;
    _ = decode.execADDQ(&cpu, &bus, 0x5200);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
}

test "SUB.B Dn - <ea> -> Dn" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // SUB.B D0,D1
    // D1 = 0x20 - 0x05 = 0x1B
    // =========================================================

    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x9200});

    cpu.d[0] = 0x05;
    cpu.d[1] = 0x20;

    const opcode: u16 = 0x9200;

    _ = decode.execSUB(&cpu, &bus, opcode);

    try testing.expectEqual(@as(u32, 0x1B), cpu.d[1] & 0xFF);

    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
}

test "SUB.B with borrow" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 0x03 - 0x05 = 0xFE
    // Borrow => Carry = 1
    // =========================================================

    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x9200});

    cpu.d[0] = 0x05;
    cpu.d[1] = 0x03;

    const opcode: u16 = 0x9200;

    _ = decode.execSUB(&cpu, &bus, opcode);

    try testing.expectEqual(@as(u32, 0xFE), cpu.d[1] & 0xFF);

    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.x == true);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
}

test "SUB.B result zero" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 0x10 - 0x10 = 0
    // =========================================================

    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x9200});

    cpu.d[0] = 0x10;
    cpu.d[1] = 0x10;

    const opcode: u16 = 0x9200;

    _ = decode.execSUB(&cpu, &bus, opcode);

    try testing.expectEqual(@as(u32, 0x00), cpu.d[1] & 0xFF);

    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.c == false);
}

test "SUB.B signed overflow" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 0x80 - 0x01 = 0x7F
    //
    // -128 - 1 = +127
    // overflow signé
    // =========================================================

    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x9200});

    cpu.d[0] = 0x01;
    cpu.d[1] = 0x80;

    const opcode: u16 = 0x9200;

    _ = decode.execSUB(&cpu, &bus, opcode);

    try testing.expectEqual(@as(u32, 0x7F), cpu.d[1] & 0xFF);

    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.c == false);
}

test "SUB.W basic" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 0x1234 - 0x0020 = 0x1214
    // =========================================================

    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x9240});

    cpu.d[0] = 0x0020;
    cpu.d[1] = 0x1234;

    const opcode: u16 = 0x9240;

    _ = decode.execSUB(&cpu, &bus, opcode);

    try testing.expectEqual(@as(u32, 0x1214), cpu.d[1] & 0xFFFF);

    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.z == false);
}

test "SUB.L basic" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // 0x10000000 - 1 = 0x0FFFFFFF
    // =========================================================

    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x9280});

    cpu.d[0] = 1;
    cpu.d[1] = 0x10000000;

    const opcode: u16 = 0x9280;

    _ = decode.execSUB(&cpu, &bus, opcode);

    try testing.expectEqual(@as(u32, 0x0FFFFFFF), cpu.d[1]);

    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.n == false);
}
test "NOP" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // NOP — 0x4E71
    // Vérifie que :
    //   - aucun registre n'est modifié
    //   - aucun flag n'est modifié
    //   - retourne 4 cycles
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x4E71});

    // État initial connu
    cpu.d[0] = 0xDEADBEEF;
    cpu.d[7] = 0x12345678;
    cpu.a[0] = 0x00003000;
    cpu.a[7] = 0x00000800;
    cpu.sr.n = true;
    cpu.sr.z = false;
    cpu.sr.v = true;
    cpu.sr.c = false;
    cpu.sr.x = true;

    const cycles = decode.execNOP(&cpu, &bus);

    // Aucun registre de données modifié
    try testing.expectEqual(@as(u32, 0xDEADBEEF), cpu.d[0]);
    try testing.expectEqual(@as(u32, 0x12345678), cpu.d[7]);

    // Aucun registre d'adresses modifié
    try testing.expectEqual(@as(u32, 0x00003000), cpu.a[0]);
    try testing.expectEqual(@as(u32, 0x00000800), cpu.a[7]);

    // Aucun flag modifié
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == true);

    // 4 cycles exactement
    try testing.expectEqual(@as(u32, 4), cycles);
}
test "ASR - décalage arithmétique droite (immédiat, word)" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;
    // =========================================================
    // ASR.W #2, D0  — 0xE440
    // Décale 0x8004 de 2 bits à droite arithmétiquement
    // Extension de signe : 0x8004 >> 2 = 0xE001
    // C = dernier bit sorti = bit1 de 0x8004 = 0 → en fait bit0 après 1er shift
    // Vérifie : N=1, Z=0, V=0, C=dernier bit sorti, X=C
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0xE440});
    cpu.d[0] = 0x0000_8004;
    cpu.sr.n = false;
    cpu.sr.z = true;
    cpu.sr.v = true;
    cpu.sr.c = false;
    cpu.sr.x = false;
    const cycles_asr = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0000_E001), cpu.d[0]); // signe propagé
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false); // ASR ne peut pas déborder
    try testing.expect(cpu.sr.c == false); // dernier bit sorti = bit0 après 1er shift = 0
    try testing.expect(cpu.sr.x == false);
    try testing.expectEqual(@as(u32, 10), cycles_asr); // 6 + 2*2
}
test "ASR - préserve les bits hauts du registre (byte)" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;
    // =========================================================
    // ASR.B #1, D1  — 0xE201
    // 0xFF223381 → opère sur octet bas 0x81
    // 0x81 >> 1 arithmétique = 0xC0 (signe propagé), C=1
    // Les bits hauts du registre doivent être inchangés
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0xE201});
    cpu.d[1] = 0xFF2233_81;
    cpu.sr.x = false;
    const cycles_asr2 = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0xFF2233_C0), cpu.d[1]);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 8), cycles_asr2); // 6 + 2*1
}

test "ASL - décalage arithmétique gauche avec overflow" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;
    // =========================================================
    // ASL.W #2, D0  — 0xE540
    // 0x2001 << 2 = 0x8004 ; le bit de signe change → V=1
    // C = dernier MSB sorti = bit15 après 1er shift = 0
    //   = bit15 de 0x4002 = 0 (après 2e shift bit15 de 0x8004=1, donc C=0 au 1er, 1 au 2e? non)
    // Détail : iter1 : val=0x2001, MSB(bit15)=0 → last_out=0, val=0x4002
    //          iter2 : val=0x4002, MSB(bit15)=0 → last_out=0, val=0x8004
    // C=0, mais overflow car signe a changé (0x4002→0x8004 change bit15)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0xE540});
    cpu.d[0] = 0x0000_2001;
    cpu.sr.v = false;
    const cycles_asl = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0000_8004), cpu.d[0]);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == true); // changement de signe détecté
    try testing.expect(cpu.sr.c == false);
    try testing.expectEqual(@as(u32, 10), cycles_asl);
}
test "LSR - décalage logique droite (immédiat, long)" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;
    // =========================================================
    // LSR.L #4, D2  — 0xE88A
    // 0x8000_00F0 >> 4 = 0x0800_000F, pas d'extension de signe
    // C = dernier bit sorti = bit3 de 0x8000_00F0 = 0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0xE88A});
    cpu.d[2] = 0x8000_00F0;
    cpu.sr.n = true;
    cpu.sr.x = true;
    const cycles_lsr = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0800_000F), cpu.d[2]);
    try testing.expect(cpu.sr.n == false); // bit31 = 0
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false); // bit sorti = 0
    try testing.expect(cpu.sr.x == false);
    try testing.expectEqual(@as(u32, 14), cycles_lsr); // 6 + 2*4
}
test "LSL - décalage logique gauche, C=1" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;
    // =========================================================
    // LSL.W #1, D3  — 0xE34B  (à vérifier selon encodage)
    // 0x0000_8001 → opère sur word bas 0x8001
    // 0x8001 << 1 = 0x0002, C = bit15 sorti = 1
    // V toujours 0 pour LSL
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0xE34B});
    cpu.d[3] = 0xABCD_8001;
    cpu.sr.v = true;
    const cycles_lsl = decode.step(&cpu, &bus);
    //std.debug.print("\n[TEST]  LSL - decalage logique gauche, C=1", .{});
    try testing.expectEqual(@as(u32, 0xABCD_0002), cpu.d[3]); // bits hauts préservés
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 8), cycles_lsl);
    //std.debug.print(" OK\n", .{});
}
test "SUBQ - soustraction immédiate rapide, borrow et flags" {
    var bus: TestBus = .{};
    var cpu: Cpu = undefined;

    // =========================================================
    // SUBQ.W #1, D2  — opcode 0x5342
    // D2 = 0x0000_8000 → opère sur word bas
    // 0x8000 - 1 = 0x7FFF
    // N = 0 (résultat positif), Z = 0, V = 1 (overflow signé: négatif → positif)
    // C = 0 (pas de borrow: 0x8000 >= 1), X = 0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5342});
    cpu.d[2] = 0x1234_8000; // word bas = 0x8000 (négatif en signé)
    cpu.sr.v = false;
    cpu.sr.c = true;
    cpu.sr.x = true;
    const cycles_subq1 = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x1234_7FFF), cpu.d[2]); // bits hauts préservés
    try testing.expect(cpu.sr.n == false); // 0x7FFF = positif
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == true); // overflow: -32768 → +32767
    try testing.expect(cpu.sr.c == false); // pas de borrow
    try testing.expect(cpu.sr.x == false);
    try testing.expectEqual(@as(u32, 4), cycles_subq1);

    // =========================================================
    // SUBQ.B #8, D0  — opcode 0x5100 (imm=0 → 8, size=byte, D0)
    // D0 = 0x0000_0007 → 7 - 8 = 0xFFFFFFFF (masqué byte = 0xFF)
    // N = 1, Z = 0, V = 0, C = 1 (borrow: 7 < 8), X = 1
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5100});
    cpu.d[0] = 0xFFFF_FF07; // byte bas = 0x07
    const cycles_subq2 = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), cpu.d[0]); // byte bas = 0xFF
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == true); // borrow !
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 4), cycles_subq2);

    // =========================================================
    // SUBQ.W #1, D1  — résultat zéro
    // D1 = 0x0000_0001 → 1 - 1 = 0
    // N = 0, Z = 1, V = 0, C = 0, X = 0
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x5341});
    cpu.d[1] = 0xAAAA_0001;
    const cycles_subq3 = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xAAAA_0000), cpu.d[1]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == true); // zéro !
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == false);
    try testing.expectEqual(@as(u32, 4), cycles_subq3);

    // =========================================================
    // SUBQ.L #8, A3  — mode adresse (mode=001), pas de flags
    // A3 = 0x0000_0010 → 0x10 - 8 = 0x08
    // Flags doivent rester inchangés (sauf pour Areg, pas de maj flags)
    // =========================================================
    bus = .{};
    cpu = makeCpu(&bus, &[_]u16{0x518B}); // size=10(long), mode=001(A3), imm=000(8)
    // Attendu: 0101 0001 1000 1011
    // bits 11-9 = 000 (imm=8), bit 8 = 1 (SUBQ), bits 7-6 = 10 (long)
    // bits 5-3 = 001 (An), bits 2-0 = 011 (A3)
    // Opcode: 0101 0001 1000 1011 = 0x518B
    cpu.a[3] = 0x0000_0010;
    cpu.sr.n = true;
    cpu.sr.z = true;
    cpu.sr.v = true;
    cpu.sr.c = true;
    cpu.sr.x = true;
    const cycles_subq4 = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x0000_0008), cpu.a[3]);
    try testing.expect(cpu.sr.n == true); // flags inchangés !
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 8), cycles_subq4);
}

test "SWAP - échange les mots d'un registre donnée" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x4840}); // SWAP D0

    cpu.d[0] = 0x1234_ABCD;
    cpu.sr.x = true;
    cpu.sr.v = true;
    cpu.sr.c = true;

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xABCD_1234), cpu.d[0]);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 4), cycles);
}

test "SWAP - résultat zéro" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x4847}); // SWAP D7

    cpu.d[7] = 0;
    cpu.sr.n = true;
    cpu.sr.z = false;
    cpu.sr.x = true;

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0), cpu.d[7]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 4), cycles);
}

test "MOVEQ - charge immédiat zéro dans D1" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x7200}); // MOVEQ #0,D1

    cpu.d[1] = 0xFFFF_FFFF;
    cpu.sr.n = true;
    cpu.sr.z = false;
    cpu.sr.v = true;
    cpu.sr.c = true;
    cpu.sr.x = true;

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0), cpu.d[1]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 4), cycles);
}

test "MOVEQ - sign-extension immédiat négatif" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x70FF}); // MOVEQ #-1,D0

    cpu.d[0] = 0;
    cpu.sr.x = true;

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), cpu.d[0]);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 4), cycles);
}

test "ADD.W (A0)+,D1 - opcode 0xD258" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0xD258});

    cpu.a[0] = 0x0200;
    cpu.d[1] = 0xABCD_0003;
    bus.write16at(0x0200, 0x0002);
    cpu.sr.x = true;
    cpu.sr.v = true;
    cpu.sr.c = true;

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xABCD_0005), cpu.d[1]);
    try testing.expectEqual(@as(u32, 0x0202), cpu.a[0]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == false);
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "ADD.W (A0)+,D1 - overflow signé" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0xD258});

    cpu.a[0] = 0x0200;
    cpu.d[1] = 0x1234_7FFF;
    bus.write16at(0x0200, 0x0001);

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x1234_8000), cpu.d[1]);
    try testing.expectEqual(@as(u32, 0x0202), cpu.a[0]);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == false);
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "DBF D2 - opcode 0x51CA branche tant que compteur non -1" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x51CA, 0xFFFE }); // DBF D2,-2

    cpu.d[2] = 0x1234_0002;
    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x1234_0001), cpu.d[2]);
    try testing.expectEqual(@as(u32, 0x0100), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "DBF D2 - fin de boucle quand word devient 0xFFFF" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x51CA, 0xFFFE }); // DBF D2,-2

    cpu.d[2] = 0x1234_0000;
    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x1234_FFFF), cpu.d[2]);
    try testing.expectEqual(@as(u32, 0x0104), cpu.pc);
    try testing.expectEqual(@as(u32, 14), cycles);
}

test "DBEQ D2 - condition vraie ne décrémente pas" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x57CA, 0xFFFE }); // DBEQ D2,-2

    cpu.d[2] = 0x1234_0002;
    cpu.sr.z = true;
    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x1234_0002), cpu.d[2]);
    try testing.expectEqual(@as(u32, 0x0104), cpu.pc);
    try testing.expectEqual(@as(u32, 12), cycles);
}

test "CMP.W (A0),D1 - opcode 0xB250 égalité" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0xB250});

    cpu.a[0] = 0x0200;
    cpu.d[1] = 0x1234_0042;
    bus.write16at(0x0200, 0x0042);
    cpu.sr.x = true;
    cpu.sr.c = true;
    cpu.sr.v = true;

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x1234_0042), cpu.d[1]);
    try testing.expectEqual(@as(u32, 0x0200), cpu.a[0]);
    try testing.expect(cpu.sr.n == false);
    try testing.expect(cpu.sr.z == true);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == false);
    try testing.expect(cpu.sr.x == true);
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "CMP.W (A0),D1 - opcode 0xB250 borrow" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0xB250});

    cpu.a[0] = 0x0200;
    cpu.d[1] = 0xAAAA_0001;
    bus.write16at(0x0200, 0x0002);

    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xAAAA_0001), cpu.d[1]);
    try testing.expect(cpu.sr.n == true);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.v == false);
    try testing.expect(cpu.sr.c == true);
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "BTST D0,-(A4) - opcode 0x0124" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x0124});

    cpu.d[0] = 2;
    cpu.a[4] = 0x0201;
    bus.write8(0x0200, 0b0000_0100);
    cpu.sr.z = true;
    cpu.sr.x = true;
    cpu.sr.c = true;
    cpu.sr.v = true;
    cpu.sr.n = true;

    _ = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x0200), cpu.a[4]);
    try testing.expect(cpu.sr.z == false);
    try testing.expect(cpu.sr.x == true);
    try testing.expect(cpu.sr.c == true);
    try testing.expect(cpu.sr.v == true);
    try testing.expect(cpu.sr.n == true);
}

test "BTST D0,-(A4) - opcode 0x0124 bit absent" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x0124});

    cpu.d[0] = 9; // modulo 8 => bit 1 en mémoire
    cpu.a[4] = 0x0201;
    bus.write8(0x0200, 0b0000_0100);

    _ = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0x0200), cpu.a[4]);
    try testing.expect(cpu.sr.z == true);
}

test "writeEA (An)+ wrappe sur overflow 32 bits" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{});

    cpu.a[0] = 0xFFFF_FFFF;
    decode.writeEA(&cpu, &bus, .{ .mode = 0b011, .reg = 0 }, .byte, 0x12);

    try testing.expectEqual(@as(u32, 0), cpu.a[0]);
}

test "readEA -(An) wrappe sur underflow 32 bits" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{});

    cpu.a[0] = 0;
    _ = decode.readEA(&cpu, &bus, .{ .mode = 0b100, .reg = 0 }, .word);

    try testing.expectEqual(@as(u32, 0xFFFF_FFFE), cpu.a[0]);
}

test "MOVE.L opcode 0x2200 est dispatché comme MOVE.L D0, D1" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x2200}); // MOVE.L D0, D1

    cpu.d[0] = 0xCAFE_BABE;
    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xCAFE_BABE), cpu.d[1]);
    try testing.expectEqual(@as(u32, 4), cycles);
}

test "MOVEA.L opcode 0x2040 est dispatché comme MOVEA.L D0, A0" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{0x2040}); // MOVEA.L D0, A0

    cpu.d[0] = 0xCAFE_BABE;
    const cycles = decode.step(&cpu, &bus);

    try testing.expectEqual(@as(u32, 0xCAFE_BABE), cpu.a[0]);
    try testing.expectEqual(@as(u32, 4), cycles);
}

// ── Tests BRA/Bcc (branches) ─────────────────────────────────────────────

test "BRA.S forward — saut court 8-bit" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6006 }); // BRA.S +6
    // PC après opcode = 0x0102, target = 0x0102 + 6 = 0x0108
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0108), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BRA.S backward — saut court arrière 8-bit" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x60FC }); // BRA.S -4
    // PC après opcode = 0x0102, target = 0x0102 - 4 = 0x00FE
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00FE), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BRA.W forward — saut 16-bit avec déplacement $00" {
    var bus: TestBus = .{};
    // BRA.W: opcode 0x6000, extension word = 0x0042
    var cpu = makeCpu(&bus, &[_]u16{ 0x6000, 0x0042 });
    // PC après opcode = 0x0102, lit extension 0x0042
    // target = 0x0102 + 0x0042 = 0x0144
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0144), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BRA.W backward — saut 16-bit négatif" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6000, 0xFFCE }); // BRA.W -50
    // PC après opcode = 0x0102, lit extension 0xFFCE
    // target = 0x0102 + (-50) = 0x0102 - 50 = 0x00D0
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00D0), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BEQ taken — condition Z=1" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6704 }); // BEQ +4
    cpu.sr.z = true;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0106), cpu.pc); // 0x0102 + 4
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BEQ not taken — condition Z=0" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6704 }); // BEQ +4
    cpu.sr.z = false;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0102), cpu.pc); // fall through
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "BEQ.W not taken — saute le mot d'extension" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6700, 0x0100 }); // BEQ.W +256
    cpu.sr.z = false;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0104), cpu.pc); // skip opcode + extension word
    try testing.expectEqual(@as(u32, 12), cycles);
}

test "BEQ.W taken — déplacement 16-bit" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6700, 0x0100 }); // BEQ.W +256
    cpu.sr.z = true;
    const cycles = decode.step(&cpu, &bus);
    // PC après opcode = 0x0102, lit extension 0x0100
    // target = 0x0102 + 256 = 0x0202
    try testing.expectEqual(@as(u32, 0x0202), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BGT taken — N==V et Z=0" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6E08 }); // BGT +8
    cpu.sr.n = false;
    cpu.sr.v = false;
    cpu.sr.z = false;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x010A), cpu.pc); // 0x0102 + 8
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BGT not taken — Z=1" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6E08 }); // BGT +8
    cpu.sr.z = true;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0102), cpu.pc); // fall through
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "BPL taken — N=0" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6A04 }); // BPL +4
    cpu.sr.n = false;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0106), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "BMI taken — N=1" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6B04 }); // BMI +4
    cpu.sr.n = true;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0106), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

// ── Tests BSR (Branch to Subroutine) ──────────────────────────────────────

test "BSR.S forward — push PC et saute" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x6106 }); // BSR.S +6
    cpu.a[7] = 0x00000800; // stack pointer
    const cycles = decode.step(&cpu, &bus);
    // Return address pushed at 0x0800 - 4 = 0x07FC
    try testing.expectEqual(@as(u32, 0x07FC), cpu.a[7]);
    try testing.expectEqual(@as(u32, 0x0102), bus.read32(0x07FC)); // PC après opcode
    try testing.expectEqual(@as(u32, 0x0108), cpu.pc); // target = 0x0102 + 6
    try testing.expectEqual(@as(u32, 18), cycles);
}

test "BSR.W — push PC avec déplacement 16-bit" {
    var bus: TestBus = .{};
    // BSR.W: opcode 0x6100, extension = 0x0100 (+256)
    var cpu = makeCpu(&bus, &[_]u16{ 0x6100, 0x0100 });
    cpu.a[7] = 0x00000800;
    const cycles = decode.step(&cpu, &bus);
    // Return address = 0x0104 (PC after opcode + extension)
    try testing.expectEqual(@as(u32, 0x07FC), cpu.a[7]); // 0x0800 - 4
    try testing.expectEqual(@as(u32, 0x0104), bus.read32(0x07FC));
    try testing.expectEqual(@as(u32, 0x0202), cpu.pc); // 0x0102 + 256
    try testing.expectEqual(@as(u32, 18), cycles);
}

test "BSR backward — push PC et saute en arrière" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x61FC }); // BSR.S -4
    cpu.a[7] = 0x00001000;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0FFC), cpu.a[7]);
    try testing.expectEqual(@as(u32, 0x0102), bus.read32(0x0FFC));
    try testing.expectEqual(@as(u32, 0x00FE), cpu.pc); // 0x0102 - 4
    try testing.expectEqual(@as(u32, 18), cycles);
}

// ── Tests JMP (Jump) ──────────────────────────────────────────────────────

test "JMP (A0) — saut par registre d'adresse" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x4ED0 }); // JMP (A0), bit 7=1, bit 6=1
    cpu.a[0] = 0x00003000;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00003000), cpu.pc);
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "JMP abs.W — saut absolu court" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x4EF8, 0x2000 }); // JMP ($2000).W
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00002000), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "JMP abs.L — saut absolu long" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x4EF9, 0x00FF, 0x0000 }); // JMP ($00FF0000).L
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00FF0000), cpu.pc);
    try testing.expectEqual(@as(u32, 12), cycles);
}

test "JMP (d16, A0) — saut avec déplacement" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x4EE8, 0x0010 }); // JMP (16, A0)
    cpu.a[0] = 0x00001000;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00001010), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

test "JMP (d16, PC) — saut relatif au PC" {
    var bus: TestBus = .{};
    // JMP (d16, PC): mode=111, reg=010, low_byte & 0xC0 = 0xC0 → JMP
    // Après opcode + extension, PC = 0x0104, disp = 0x0020
    var cpu = makeCpu(&bus, &[_]u16{ 0x4EFA, 0x0020 }); // JMP ($0020, PC)
    const cycles = decode.step(&cpu, &bus);
    // getEAAddress pour (d16, PC): pc_at_ext = cpu.pc (0x0102 après opcode)
    // disp = 0x0020, addr = 0x0102 + 0x0020 = 0x0122
    try testing.expectEqual(@as(u32, 0x0122), cpu.pc);
    try testing.expectEqual(@as(u32, 10), cycles);
}

// ── Tests JSR (Jump to Subroutine) ────────────────────────────────────────

test "JSR (A0) — push PC et saute" {
    var bus: TestBus = .{};
    // JSR (A0): opcode 0x4E90 (bit 7=1, bit 6=0, mode=010, reg=000)
    var cpu = makeCpu(&bus, &[_]u16{ 0x4E90 });
    cpu.a[0] = 0x00003000;
    cpu.a[7] = 0x00001000;
    const cycles = decode.step(&cpu, &bus);
    // Return address pushed at 0x1000 - 4 = 0x0FFC
    try testing.expectEqual(@as(u32, 0x0FFC), cpu.a[7]);
    // Return address = PC après instruction = 0x0102
    try testing.expectEqual(@as(u32, 0x0102), bus.read32(0x0FFC));
    // PC = target address
    try testing.expectEqual(@as(u32, 0x00003000), cpu.pc);
    try testing.expectEqual(@as(u32, 16), cycles);
}

test "JSR abs.L — saut absolu long avec push" {
    var bus: TestBus = .{};
    // JSR ($12345678).L: opcode 0x4EB9
    var cpu = makeCpu(&bus, &[_]u16{ 0x4EB9, 0x1234, 0x5678 });
    cpu.a[7] = 0x00001000;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00001000), cpu.a[7] +% 4);
    try testing.expectEqual(@as(u32, 0x0106), bus.read32(0x0FFC)); // PC après opcode + 2 extensions
    try testing.expectEqual(@as(u32, 0x12345678), cpu.pc);
    try testing.expectEqual(@as(u32, 20), cycles);
}

test "JSR abs.W — push et saut absolu court" {
    var bus: TestBus = .{};
    // JSR ($3000).W: opcode 0x4EB8, extension = 0x3000
    var cpu = makeCpu(&bus, &[_]u16{ 0x4EB8, 0x3000 });
    cpu.a[7] = 0x00001000; // SP dans les limites du TestBus (4096 bytes)
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00003000), cpu.pc);
    try testing.expectEqual(@as(u32, 0x0FFC), cpu.a[7]);
    try testing.expectEqual(@as(u32, 0x0104), bus.read32(0x0FFC)); // PC après opcode + extension
    try testing.expectEqual(@as(u32, 18), cycles);
}

// ── Tests RTS (Return from Subroutine) ────────────────────────────────────

test "RTS — pop PC depuis la pile et retourne" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x4E75 }); // RTS
    // Pré-remplit la pile à une adresse valide (dans les 4096 bytes du TestBus)
    bus.write32at(0x0FFC, 0x00003000); // return address
    cpu.a[7] = 0x0FFC; // SP pointe sur l'adresse de retour
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x00003000), cpu.pc);
    try testing.expectEqual(@as(u32, 0x1000), cpu.a[7]);
    try testing.expectEqual(@as(u32, 16), cycles);
}

// ── Tests intégrés JSR + RTS (appel/retour) ──────────────────────────────

test "JSR puis RTS — cycle appel/retour complet" {
    var bus: TestBus = .{};

    // Setup: SSP initial = 0x00000800 (via makeCpu)
    // On place les opcodes en mémoire :
    //   0x0100: JSR ($0120).W  → 0x4EB8, 0x0120
    //   0x0120: MOVEQ #42, D0  → 0x103C, 0x002A
    //   0x0124: RTS            → 0x4E75
    //   0x0106: (retour) MOVEQ #0, D0 → 0x7000
    //
    // ATTENTION: makeCpu écrit les opcodes à partir de 0x0100.
    // On doit réécrire la mémoire pour notre scénario.

    bus = .{};
    // Réinitialiser les vecteurs (SSP + PC)
    bus.write32at(0x000000, 0x00000800); // SSP
    bus.write32at(0x000004, 0x00000100); // PC

    // Sequence complète:
    // 0x0100: JSR ($0120).W  (4EB8 0120)
    // 0x0104: MOVEQ #0, D0  (7000)    ← instruction de retour
    // 0x0120: MOVEQ #42, D0 (103C 002A) ← subroutine
    // 0x0124: RTS            (4E75)
    bus.write16at(0x0100, 0x4EB8);
    bus.write16at(0x0102, 0x0120);
    bus.write16at(0x0104, 0x7000);  // MOVEQ #0, D0
    bus.write16at(0x0120, 0x103C);
    bus.write16at(0x0122, 0x002A);
    bus.write16at(0x0124, 0x4E75);  // RTS

    var cpu = Cpu.init();
    cpu.reset(&bus);
    cpu.a[7] = 0x00000800;
    cpu.d[0] = 0;

    // Step 1: JSR ($0120).W
    var cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0120), cpu.pc);
    try testing.expectEqual(@as(u32, 0x07FC), cpu.a[7]); // SP -= 4
    try testing.expectEqual(@as(u32, 0x0104), bus.read32(0x07FC)); // return addr
    try testing.expectEqual(@as(u32, 18), cycles);

    // Step 2: MOVEQ #42, D0 (dans la subroutine)
    cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 42), cpu.d[0]);
    try testing.expectEqual(@as(u32, 0x0124), cpu.pc);

    // Step 3: RTS (retour)
    cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0104), cpu.pc); // retour après JSR
    try testing.expectEqual(@as(u32, 0x0800), cpu.a[7]); // SP restauré
    try testing.expectEqual(@as(u32, 16), cycles);

    // Step 4: MOVEQ #0, D0 (instruction après JSR)
    cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0), cpu.d[0]); // écrasé par 0
    try testing.expectEqual(@as(u32, 0x0106), cpu.pc);
}

test "BSR puis RTS — cycle branchement subroutine" {
    var bus: TestBus = .{};

    // Setup mémoire pour test BSR + RTS
    bus.write32at(0x000000, 0x00000800); // SSP
    bus.write32at(0x000004, 0x00000100); // PC

    // 0x0100: BSR.S $0108  (6106)  → saute à 0x0108
    // 0x0102: MOVEQ #0, D0 (7000)  ← retour
    // 0x0108: MOVEQ #99, D1  (723C ? non, MOVEQ c'est 7xxx)
    // 0x0108: MOVEQ #99, D1 (723C non... MOVEQ #99, D1 = 0x7263)
    // MOVEQ #99, D1: 0111 0010 0110 0011 = 0x7263
    // 0x010A: RTS (4E75)

    bus.write16at(0x0100, 0x6106);   // BSR.S +6 → target = 0x0102+6 = 0x0108
    bus.write16at(0x0102, 0x7000);   // MOVEQ #0, D0
    bus.write16at(0x0108, 0x7263);   // MOVEQ #99, D1
    bus.write16at(0x010A, 0x4E75);   // RTS

    var cpu = Cpu.init();
    cpu.reset(&bus);
    cpu.a[7] = 0x00000800;
    cpu.d[0] = 0;
    cpu.d[1] = 0;

    // Step 1: BSR.S +6
    var cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0108), cpu.pc); // target
    try testing.expectEqual(@as(u32, 0x07FC), cpu.a[7]); // SP -= 4
    try testing.expectEqual(@as(u32, 0x0102), bus.read32(0x07FC)); // return addr
    try testing.expectEqual(@as(u32, 18), cycles);

    // Step 2: MOVEQ #99, D1
    cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 99), cpu.d[1]);
    try testing.expectEqual(@as(u32, 0x010A), cpu.pc);

    // Step 3: RTS
    cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x0102), cpu.pc);
    try testing.expectEqual(@as(u32, 0x0800), cpu.a[7]);
    try testing.expectEqual(@as(u32, 16), cycles);

    // Step 4: MOVEQ #0, D0
    cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0), cpu.d[0]);
}

// ── Tests MOVE to/from SR ──────────────────────────────────────────────

test "MOVE.W #$2700, SR — 0x46FC écrit immédiat dans SR" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x46FC, 0x2700 }); // MOVE.W #$2700, SR
    cpu.sr.set(0); // SR = 0
    const cycles = decode.step(&cpu, &bus);
    // $2700 = bit 12 (S) + IPL=7 (bits 10-8) → Supervisor, IPL=7
    try testing.expectEqual(@as(u16, 0x2700), cpu.sr.get());
    try testing.expectEqual(@as(u32, 16), cycles);
}

test "MOVE.W D0, SR — depuis registre données" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x46C0 }); // MOVE.W D0, SR (mode=000, reg=000)
    cpu.d[0] = 0x00002700;
    cpu.sr.set(0);
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u16, 0x2700), cpu.sr.get());
    try testing.expectEqual(@as(u32, 12), cycles);
}

test "MOVE.W SR, D0 — sauvegarde SR dans registre" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x40C0 }); // MOVE.W SR, D0 (mode=000, reg=000)
    cpu.sr.set(0x2700);
    cpu.d[0] = 0;
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u32, 0x2700), cpu.d[0]);
    try testing.expectEqual(@as(u32, 8), cycles);
}

test "MOVE.W SR, (A7)+ — sauvegarde SR sur pile" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x40DF }); // MOVE.W SR, (A7)+ (mode=011, reg=111)
    cpu.sr.set(0x2700);
    cpu.a[7] = 0x00000FFE; // dans les limites du TestBus (4096 bytes)
    const cycles = decode.step(&cpu, &bus);
    try testing.expectEqual(@as(u16, 0x2700), bus.read16(0x0FFE));
    try testing.expectEqual(@as(u32, 0x1000), cpu.a[7]); // A7 incrémenté de 2 (word)
    try testing.expectEqual(@as(u32, 12), cycles);
}

test "MOVE.W #$2000, SR puis SR, D0 — cycle écriture/lecture SR" {
    var bus: TestBus = .{};
    var cpu = makeCpu(&bus, &[_]u16{ 0x46FC, 0x2000, 0x40C0 });
    cpu.sr.set(0);
    cpu.d[0] = 0;
    _ = decode.step(&cpu, &bus); // MOVE.W #$2000, SR
    try testing.expectEqual(@as(u16, 0x2000), cpu.sr.get()); // S=0, IPL=4
    const cycles = decode.step(&cpu, &bus); // MOVE.W SR, D0
    try testing.expectEqual(@as(u32, 0x2000), cpu.d[0]);
    try testing.expectEqual(@as(u32, 8), cycles);
}

