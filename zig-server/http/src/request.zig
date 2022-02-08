const std = @import("std");
const Allocator = std.mem.Allocator;

const Request = @This();

pub const HttpVersion = enum {
    http_11,
    http_2,
    http_3,

    pub fn fromString(text: []const u8) !HttpVersion {
        const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
        if (eqlIgnoreCase(text, "HTTP/1.1")) return .http_11;
        if (eqlIgnoreCase(text, "HTTP/2")) return .http_2;
        if (eqlIgnoreCase(text, "HTTP/3")) return .http_3;
        return error.UnknownVersion;
    }

    pub fn toString(http_version: HttpVersion) []const u8 {
        return switch (http_version) {
            .http_11 => "HTTP/1.1",
            .http_2 => "HTTP/2",
            .http_3 => "HTTP/3",
        };
    }
};

pub const HttpMethod = enum {
    get,
    post,
    put,
    delete,
    head,
    options,

    pub fn fromString(text: []const u8) !HttpMethod {
        const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
        if (eqlIgnoreCase(text, "get")) return .get;
        if (eqlIgnoreCase(text, "post")) return .post;
        if (eqlIgnoreCase(text, "put")) return .put;
        if (eqlIgnoreCase(text, "delete")) return .delete;
        if (eqlIgnoreCase(text, "head")) return .head;
        if (eqlIgnoreCase(text, "options")) return .options;
        return error.UnknownMethod;
    }
};

data: []const u8,

pub fn method(request: Request) ?HttpMethod {
    var iter = std.mem.split(u8, request.data, " ");
    const method_str = iter.next() orelse return null;
    return HttpMethod.fromString(method_str) catch return null;
}

pub fn uri(request: Request) ?[]const u8 {
    var iter = std.mem.split(u8, request.data, " ");
    _ = iter.next() orelse return null;
    return iter.next();
}

pub fn version(request: Request) ?HttpVersion {
    var iter = std.mem.split(u8, request.data, " ");
    _ = iter.next() orelse return null;
    _ = iter.next() orelse return null;
    const version_str = iter.next() orelse return null;
    return HttpVersion.fromString(version_str) catch return null;
}

pub fn header(request: Request, header_name: []const u8) ?std.mem.SplitIterator(u8) {
    // @todo Multiple header values
    var line_iter = std.mem.split(u8, request.data, "\r\n");
    _ = line_iter.next() orelse return null;

    while (line_iter.next()) |header_line| {
        if (std.mem.startsWith(u8, header_line, header_name)) {
            const delim_index = std.mem.indexOf(u8, header_line, ":") orelse return null;
            const header_value = header_line[delim_index + 1..];
            const trimmed = std.mem.trim(u8, header_value, " ");
            return std.mem.split(u8, trimmed, ",");
        }
    }

    return null;
}

pub fn body(request: Request) ?[]const u8 {
    var line_iter = std.mem.split(u8, request.data, "\r\n");
    while (line_iter.next()) |line| {
        if (std.mem.trim(u8, line, " ").len == 0) {
            // Two line breaks in a row, signalling the end of the headers and the start of the body
            const body_start_index = line_iter.index orelse unreachable;
            if (request.header("Content-Length")) |content_length| {
                const length = std.fmt.parseInt(content_length) catch 0;
                return request.data[body_start_index..body_start_index + length];
            } else {
                return request.data[body_start_index..];
            }
        }
    }

    return null;
}

pub fn uriMatches(request: Request, test_uri: []const u8) bool {
    if (request.uri()) |req_uri| {
        return std.mem.eql(u8, req_uri, test_uri);
    } else {
        return false;
    }
}