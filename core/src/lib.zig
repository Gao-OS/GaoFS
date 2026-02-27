pub const blockdev = @import("blockdev.zig");

pub const Version = struct {
    // Library version (not on-disk format version).
    pub const major = 0;
    pub const minor = 1;
};

pub const FormatVersion = struct {
    // On-disk format version for GaoFS v1.
    pub const major = 1;
    pub const minor = 0;
};
