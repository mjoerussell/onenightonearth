const std = @import("std");

const Request = @This();

pub const GeneralError = error{ParseError};

pub const HttpMethod = enum {
    get,
    post,
    put,
    delete,
    head,
    options,

    pub fn fromString(text: []const u8) !HttpMethod {
        inline for (std.meta.fields(HttpMethod)) |field| {
            if (std.ascii.endsWithIgnoreCase(text, field.name)) {
                return comptime std.meta.stringToEnum(HttpMethod, field.name) orelse unreachable;
            }
        }
        return error.UnknownMethod;
    }

    pub fn toString(method: HttpMethod) []const u8 {
        return switch (method) {
            .get => "GET",
            .post => "POST",
            .put => "PUT",
            .delete => "DELETE",
            .head => "HEAD",
            .options => "OPTION",
        };
    }
};

pub const FixedBufferWriter = Writer(std.io.FixedBufferStream([]u8).Writer);

pub fn Writer(comptime W: type) type {
    return struct {
        const Self = @This();

        writer: W,

        pub fn writeStatus(self: Self, method: HttpMethod, uri: []const u8) !void {
            try self.writer.print("{s} {s} HTTP/1.1\r\n", .{ method.toString(), uri });
        }

        pub fn writeHeader(self: Self, header_name: []const u8, header_value: anytype) !void {
            const format_string = comptime if (std.meta.trait.isZigString(@TypeOf(header_value)))
                "{s}: {s}\r\n"
            else
                "{s}: {}\r\n";

            try self.writer.print(format_string, .{ header_name, header_value });
        }

        pub fn writeBody(self: Self, body: []const u8) !void {
            try self.writer.writeAll("\r\n");
            try self.writer.writeAll(body);
        }

        pub fn complete(self: Self) !void {
            try self.writer.writeAll("\r\n");
        }
    };
}

data: []const u8,

pub fn getMethod(request: Request) GeneralError!HttpMethod {
    const method_end_index = std.mem.indexOf(u8, request.data, " ") orelse return error.ParseError;
    return HttpMethod.fromString(request.data[0..method_end_index]) catch return error.ParseError;
}

pub fn getPath(request: Request) GeneralError![]const u8 {
    for (request.data, 0..) |c, index| {
        if (c == ' ') {
            const path_end_index = std.mem.indexOfPos(u8, request.data, index + 1, " ") orelse return error.ParseError;
            return request.data[index + 1 .. path_end_index];
        }
    }
    return error.ParseError;
}

pub fn findHeader(request: Request, header_name: []const u8) ?[]const u8 {
    var line_iter = std.mem.split(u8, request.data, "\r\n");
    _ = line_iter.next();

    while (line_iter.next()) |line| {
        // Blank line signals the end of the header section, when this is reached we can abort the search.
        if (line.len == 0) return null;
        const header_name_end = std.mem.indexOf(u8, line, ":") orelse continue;
        if (std.ascii.eqlIgnoreCase(header_name, line[0..header_name_end])) {
            return std.mem.trim(u8, line[header_name_end + 1 ..], " \r\n");
        }
    }

    return null;
}

pub fn getBody(request: Request) []const u8 {
    var line_iter = std.mem.split(u8, request.data, "\r\n");

    var index: usize = 0;
    while (line_iter.next()) |line| : (index += line.len + 2) {
        if (line.len == 0) break;
    }

    var end_index = request.data.len;
    if (std.mem.endsWith(u8, request.data, "\r\n")) {
        end_index -= 2;
    }

    return request.data[index + 2 .. end_index];
}

pub fn writer(inner_writer: anytype) Writer(@TypeOf(inner_writer)) {
    return Writer(@TypeOf(inner_writer)){ .writer = inner_writer };
}

test "parse request method" {
    const request_data = "GET /path HTTP/1.1\r\nBogus: Value\r\n\r\nbody\r\n";

    var request = Request{ .data = request_data };

    const method = try request.getMethod();
    try std.testing.expectEqual(HttpMethod.get, method);
}

test "parse request path" {
    const request_data = "GET /path/abc HTTP/1.1\r\nBogus: Value\r\n\r\nbody\r\n";

    var request = Request{ .data = request_data };

    const path = try request.getPath();
    try std.testing.expectEqualStrings("/path/abc", path);
}

test "find header value" {
    const request_data = "GET /path HTTP/1.1\r\nBogus: Value\r\nAnother: Val, val2\r\nSomething-Else: XX\r\n\r\nbody\r\n";

    var request = Request{ .data = request_data };

    const header_val = request.findHeader("another").?;
    try std.testing.expectEqualStrings("Val, val2", header_val);
}

test "get body content" {
    const request_data = "HTTP/1.1 200 OK\r\nBogus: Value\r\nAnother: Val, val2\r\nSomething-Else: XX\r\n\r\nbody\ntext\r\n";

    var request = Request{ .data = request_data };

    const body = request.getBody();
    try std.testing.expectEqualStrings("body\ntext", body);
}
