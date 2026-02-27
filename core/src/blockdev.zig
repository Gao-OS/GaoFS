pub const BlockDev = struct {
    pub const Error = error{
        IoError,
        InvalidOffset,
        ReadOnly,
        NotSupported,
        OutOfRange,
    };

    read: *const fn (ctx: *anyopaque, offset: u64, buf: []u8) Error!void,
    write: *const fn (ctx: *anyopaque, offset: u64, buf: []const u8) Error!void,
    flush: *const fn (ctx: *anyopaque) Error!void,
    size: *const fn (ctx: *anyopaque) u64,
    block_size: *const fn (ctx: *anyopaque) u32,
    close: *const fn (ctx: *anyopaque) void,

    // `ctx` is owned by the concrete BlockDev implementation.
    // Callers must invoke `close` exactly once when finished.
    ctx: *anyopaque,
};
