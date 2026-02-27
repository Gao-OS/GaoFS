const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("gaofs-core", .{
        .root_source_file = b.path("core/src/lib.zig"),
    });

    const mkfs = b.addExecutable(.{
        .name = "mkfs.gaofs",
        .root_source_file = b.path("tools/mkfs/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mkfs.root_module.addImport("gaofs-core", core);
    b.installArtifact(mkfs);

    const fsck = b.addExecutable(.{
        .name = "fsck.gaofs",
        .root_source_file = b.path("tools/fsck/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    fsck.root_module.addImport("gaofs-core", core);
    b.installArtifact(fsck);

    const dump = b.addExecutable(.{
        .name = "dump.gaofs",
        .root_source_file = b.path("tools/dump/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    dump.root_module.addImport("gaofs-core", core);
    b.installArtifact(dump);

    const server = b.addExecutable(.{
        .name = "gaofs-server",
        .root_source_file = b.path("server/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    server.root_module.addImport("gaofs-core", core);
    b.installArtifact(server);
}
