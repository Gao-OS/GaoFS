pub const BlockDev = struct {
    pub const Error = error{
        IoError,
        InvalidOffset,
        ReadOnly,
    };

    read: *const fn (ctx: *anyopaque, offset: u64, buf: []u8) Error!void,
    write: *const fn (ctx: *anyopaque, offset: u64, buf: []const u8) Error!void,
    flush: *const fn (ctx: *anyopaque) Error!void,
    size: *const fn (ctx: *anyopaque) u64,
    close: *const fn (ctx: *anyopaque) void,

    ctx: *anyopaque,
};
