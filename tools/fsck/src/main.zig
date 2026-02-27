const std = @import("std");
const core = @import("gaofs-core");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("fsck.gaofs v{d}.{d}\n", .{ core.Version.major, core.Version.minor });
}
