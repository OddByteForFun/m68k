const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const Cpu = @import("m68k").Cpu;
const decode = @import("decode");

const JsonTestBus = struct {
    allocator: std.mem.Allocator,
    mem: std.AutoHashMap(u32, u8),
    debug_pc: u32 = 0,
    unrestricted_pc: bool = true,

    pub fn init(allocator: std.mem.Allocator) JsonTestBus {
        return .{
            .allocator = allocator,
            .mem = std.AutoHashMap(u32, u8).init(allocator),
        };
    }

    pub fn deinit(self: *JsonTestBus) void {
        self.mem.deinit();
    }

    pub fn read8(self: *const JsonTestBus, addr: u32) u8 {
        return self.mem.get(addr) orelse 0;
    }
    pub fn read16(self: *const JsonTestBus, addr: u32) u16 {
        return (@as(u16, self.read8(addr)) << 8) | self.read8(addr + 1);
    }
    pub fn read32(self: *const JsonTestBus, addr: u32) u32 {
        return (@as(u32, self.read16(addr)) << 16) | self.read16(addr + 2);
    }
    pub fn write8(self: *JsonTestBus, addr: u32, v: u8) void {
        self.mem.put(addr, v) catch {};
    }
    pub fn write16(self: *JsonTestBus, addr: u32, v: u16) void {
        self.write8(addr, @truncate(v >> 8));
        self.write8(addr + 1, @truncate(v));
    }
    pub fn write32(self: *JsonTestBus, addr: u32, v: u32) void {
        self.write16(addr, @truncate(v >> 16));
        self.write16(addr + 2, @truncate(v));
    }
    pub fn getInterruptLevel(self: *const JsonTestBus) u3 {
        _ = self;
        return 0;
    }
};

fn loadRam(bus: *JsonTestBus, ram: std.json.Array) !void {
    for (ram.items) |entry| {
        const pair = entry.array;
        const addr = @as(u32, @intCast(pair.items[0].integer));
        const val = @as(u8, @intCast(pair.items[1].integer));
        try bus.mem.put(addr, val);
    }
}

fn setCpuState(cpu: *Cpu, bus: *JsonTestBus, initial: std.json.ObjectMap) !void {
    const json_pc = @as(u32, @intCast(initial.get("pc").?.integer));
    const json_ssp = @as(u32, @intCast(initial.get("ssp").?.integer));
    const json_usp = @as(u32, @intCast(initial.get("usp").?.integer));
    const json_sr = @as(u16, @intCast(initial.get("sr").?.integer));

    inline for (0..8) |i| {
        const key = std.fmt.comptimePrint("d{d}", .{i});
        if (initial.get(key)) |v| cpu.d[i] = @as(u32, @intCast(v.integer));
    }
    inline for (0..7) |i| {
        const key = std.fmt.comptimePrint("a{d}", .{i});
        if (initial.get(key)) |v| cpu.a[i] = @as(u32, @intCast(v.integer));
    }

    cpu.ssp = json_ssp;
    cpu.usp = json_usp;
    cpu.sr.set(json_sr);

    cpu.pc = json_pc -% 4;

    cpu.a[7] = if (cpu.sr.s) cpu.ssp else cpu.usp;

    if (initial.get("prefetch")) |prefetch_val| {
        const pf = prefetch_val.array;
        if (pf.items.len >= 1) {
            const opcode = @as(u16, @intCast(pf.items[0].integer));
            bus.write16(cpu.pc, opcode);
        }
        if (pf.items.len >= 2) {
            const next = @as(u16, @intCast(pf.items[1].integer));
            bus.write16(cpu.pc + 2, next);
        }
    }
}

fn checkFinal(cpu: *Cpu, bus: *JsonTestBus, final: std.json.ObjectMap, name: []const u8) !usize {
    var failures: usize = 0;

    inline for (0..8) |i| {
        const key = std.fmt.comptimePrint("d{d}", .{i});
        if (final.get(key)) |v| {
            const expected = @as(u32, @intCast(v.integer));
            if (cpu.d[i] != expected) {
                std.debug.print("    FAIL [{s}] d{d}: expected 0x{X:08}, got 0x{X:08}\n", .{ name, i, expected, cpu.d[i] });
                failures += 1;
            }
        }
    }
    inline for (0..7) |i| {
        const key = std.fmt.comptimePrint("a{d}", .{i});
        if (final.get(key)) |v| {
            const expected = @as(u32, @intCast(v.integer));
            if (cpu.a[i] != expected) {
                std.debug.print("    FAIL [{s}] a{d}: expected 0x{X:08}, got 0x{X:08}\n", .{ name, i, expected, cpu.a[i] });
                failures += 1;
            }
        }
    }

    if (final.get("ssp")) |v| {
        const expected = @as(u32, @intCast(v.integer));
        if (cpu.ssp != expected) {
            std.debug.print("    FAIL [{s}] ssp: expected 0x{X:08}, got 0x{X:08}\n", .{ name, expected, cpu.ssp });
            failures += 1;
        }
    }
    if (final.get("usp")) |v| {
        const expected = @as(u32, @intCast(v.integer));
        if (cpu.usp != expected) {
            std.debug.print("    FAIL [{s}] usp: expected 0x{X:08}, got 0x{X:08}\n", .{ name, expected, cpu.usp });
            failures += 1;
        }
    }
    if (final.get("sr")) |v| {
        const expected = @as(u16, @intCast(v.integer));
        if (cpu.sr.get() != expected) {
            std.debug.print("    FAIL [{s}] sr: expected 0x{X:04}, got 0x{X:04}\n", .{ name, expected, cpu.sr.get() });
            failures += 1;
        }
    }

    if (final.get("pc")) |v| {
        const expected_pc = @as(u32, @intCast(v.integer));
        const actual_pc = cpu.pc;
        if (actual_pc != expected_pc -% 4) {
            std.debug.print("    FAIL [{s}] pc: expected 0x{X:08} (adjusted -4 = 0x{X:08}), got 0x{X:08}\n", .{ name, expected_pc, expected_pc -% 4, actual_pc });
            failures += 1;
        }
    }

    if (final.get("ram")) |ram_val| {
        const ram = ram_val.array;
        for (ram.items) |entry| {
            const pair = entry.array;
            const addr = @as(u32, @intCast(pair.items[0].integer));
            const expected = @as(u8, @intCast(pair.items[1].integer));
            const actual = bus.read8(addr);
            if (actual != expected) {
                std.debug.print("    FAIL [{s}] ram[0x{X:08}]: expected 0x{X:02}, got 0x{X:02}\n", .{ name, addr, expected, actual });
                if (failures >= 20) return failures;
                failures += 1;
            }
        }
    }

    return failures;
}

fn runJsonFile(io: Io, filepath: []const u8, allocator: std.mem.Allocator) !usize {
    const content = try Io.Dir.cwd().readFileAlloc(io, filepath, allocator, .unlimited);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const test_cases = root.array;

    var total_failures: usize = 0;
    var total_tests: usize = 0;
    var passed_tests: usize = 0;

    for (test_cases.items) |item| {
        const tc = item.object;
        const test_name = tc.get("name").?.string;
        const initial = tc.get("initial").?.object;
        const fin = tc.get("final").?.object;

        var bus = JsonTestBus.init(allocator);
        defer bus.deinit();

        if (initial.get("ram")) |ram_val| {
            try loadRam(&bus, ram_val.array);
        }

        var cpu = Cpu.init();
        try setCpuState(&cpu, &bus, initial);

        _ = decode.step(&cpu, &bus);

        if (cpu.sr.s) cpu.ssp = cpu.a[7] else cpu.usp = cpu.a[7];

        const file_failures = try checkFinal(&cpu, &bus, fin, test_name);
        total_tests += 1;
        if (file_failures == 0) {
            passed_tests += 1;
        } else {
            total_failures += file_failures;
        }
    }

    std.debug.print("  {s}: {d}/{d} passed, {d} failures\n", .{ filepath, passed_tests, total_tests, total_failures });

    return total_failures;
}

test "MAME JSON opcodes" {
    const io = Io.Threaded.global_single_threaded.io();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cwd = Io.Dir.cwd();
    var dir = try cwd.openDir(io, "tests/json_opcodes", .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var total_failures: usize = 0;
    var file_count: usize = 0;

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".json")) continue;

        file_count += 1;
        const full_path = try Io.Dir.path.join(allocator, &.{ "tests", "json_opcodes", entry.path });
        defer allocator.free(full_path);

        total_failures += try runJsonFile(io, full_path, allocator);
    }

    if (file_count == 0) {
        std.debug.print("No JSON test files found in tests/json_opcodes/\n", .{});
    } else {
        std.debug.print("Processed {d} JSON file(s), total failures: {d}\n", .{ file_count, total_failures });
    }

    try testing.expect(total_failures == 0);
}
