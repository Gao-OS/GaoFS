const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("gaofs-core", .{
        .source_file = .{ .path = "core/src/lib.zig" },
    });

    const mkfs = b.addExecutable(.{
        .name = "mkfs.gaofs",
        .root_source_file = .{ .path = "tools/mkfs/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    mkfs.addModule("gaofs-core", core);
    b.installArtifact(mkfs);

    const fsck = b.addExecutable(.{
        .name = "fsck.gaofs",
        .root_source_file = .{ .path = "tools/fsck/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    fsck.addModule("gaofs-core", core);
    b.installArtifact(fsck);

    const server = b.addExecutable(.{
        .name = "gaofs-server",
        .root_source_file = .{ .path = "server/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    server.addModule("gaofs-core", core);
    b.installArtifact(server);
}
