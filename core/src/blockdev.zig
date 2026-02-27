pub const BlockDev = struct {
    pub const Error = error{
        IoError,
        InvalidOffset,
    };

    read: fn (ctx: *anyopaque, offset: u64, buf: []u8) Error!void,
    write: fn (ctx: *anyopaque, offset: u64, buf: []const u8) Error!void,
    flush: fn (ctx: *anyopaque) Error!void,

    ctx: *anyopaque,
};
