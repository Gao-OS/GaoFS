pub const BlockDev = struct {
    pub const Error = error{
        IoError,
        InvalidOffset,
        ReadOnly,
    };

    read: fn (ctx: *anyopaque, offset: u64, buf: []u8) Error!void,
    write: fn (ctx: *anyopaque, offset: u64, buf: []const u8) Error!void,
    flush: fn (ctx: *anyopaque) Error!void,
    size: fn (ctx: *anyopaque) u64,

    ctx: *anyopaque,
};
