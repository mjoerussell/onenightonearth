const std = @import("std");

pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;
pub extern fn consoleWarn(message: [*]const u8, message_len: u32) void;
pub extern fn consoleError(message: [*]const u8, message_len: u32) void;

pub const LogLevel = enum {
    Debug,
    Error,
    Warn
};

pub fn log(level: LogLevel, comptime message: []const u8, args: anytype) void {
    var buffer: [message.len * 10]u8 = undefined;
    const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch |err| return;
    switch (level) {
        .Debug => consoleLog(fmt_msg.ptr, @intCast(u32, fmt_msg.len)),
        .Warn => consoleWarn(fmt_msg.ptr, @intCast(u32, fmt_msg.len)),
        .Error => consoleError(fmt_msg.ptr, @intCast(u32, fmt_msg.len)),
    }
}