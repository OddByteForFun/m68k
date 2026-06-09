const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cpu_mod = b.createModule(.{
        .root_source_file = b.path("./src/m68k.zig"),
    });

    const decode_mod = b.createModule(.{
        .root_source_file = b.path("./src/decode.zig"),
        .imports = &.{
            .{ .name = "m68k", .module = cpu_mod },
        },
    });

    const cpu_test = b.addTest(.{
        .name = "cpu-opcode-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./tests/cpu_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "m68k", .module = cpu_mod },
                .{ .name = "decode", .module = decode_mod },
            },
        }),
    });
    const run_cpu = b.addRunArtifact(cpu_test);
    const cpu_step = b.step("test-cpu-opcodes", "Lance les tests fonctionnels des opcodes 68000");
    cpu_step.dependOn(&run_cpu.step);

    const cpu_json_test = b.addTest(.{
        .name = "cpu-json-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./tests/cpu_json_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "m68k", .module = cpu_mod },
                .{ .name = "decode", .module = decode_mod },
            },
        }),
    });
    const run_cpu_json = b.addRunArtifact(cpu_json_test);
    const cpu_json_step = b.step("test-cpu-json", "Lance les tests CPU depuis les fichiers JSON MAME");
    cpu_json_step.dependOn(&run_cpu_json.step);

    const cpu_timing_test = b.addTest(.{
        .name = "cpu-timing-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./tests/cpu_timing_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "m68k", .module = cpu_mod },
                .{ .name = "decode", .module = decode_mod },
            },
        }),
    });
    const run_cpu_timing = b.addRunArtifact(cpu_timing_test);
    const cpu_timing_step = b.step("test-cpu-timing", "Lance les tests de timing des opcodes 68000");
    cpu_timing_step.dependOn(&run_cpu_timing.step);
}
