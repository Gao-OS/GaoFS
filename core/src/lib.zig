pub const blockdev = @import("blockdev.zig");

pub const Version = struct {
    // Library version (not on-disk format version).
    pub const major = 0;
    pub const minor = 1;
};
