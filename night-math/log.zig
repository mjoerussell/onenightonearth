const std = @import("std");
const builtin = @import("builtin");

pub extern fn consoleLog(message: [*]const u8, message_len: u32) void;
pub extern fn consoleWarn(message: [*]const u8, message_len: u32) void;
pub extern fn consoleError(message: [*]const u8, message_len: u32) void;

const LogLevel = enum { debug, err, warn };

pub fn debug(comptime message: []const u8, args: anytype) void {
    log(.debug, message, args);
}

pub fn err(comptime message: []const u8, args: anytype) void {
    log(.err, message, args);
}

pub fn warn(comptime message: []const u8, args: anytype) void {
    log(.warn, message, args);
}

fn log(level: LogLevel, comptime message: []const u8, args: anytype) void {
    if (builtin.output_mode != .Exe) {
        var buffer: [message.len * 10]u8 = undefined;
        const fmt_msg = std.fmt.bufPrint(buffer[0..], message, args) catch return;
        switch (level) {
            .debug => consoleLog(fmt_msg.ptr, @as(u32, @intCast(fmt_msg.len))),
            .warn => consoleWarn(fmt_msg.ptr, @as(u32, @intCast(fmt_msg.len))),
            .err => consoleError(fmt_msg.ptr, @as(u32, @intCast(fmt_msg.len))),
        }
    }
}
