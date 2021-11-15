const std = @import("std");
const Allocator = std.mem.Allocator;

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

    pub fn toString(version: HttpVersion) []const u8 {
        return switch (version) {
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

pub const HttpRequest = struct {
    data: []const u8,

    pub fn method(request: HttpRequest) ?HttpMethod {
        var iter = std.mem.split(u8, request.data, " ");
        const method_str = iter.next() orelse return null;
        return HttpMethod.fromString(method_str) catch return null;
    }

    pub fn uri(request: HttpRequest) ?[]const u8 {
        var iter = std.mem.split(u8, request.data, " ");
        _ = iter.next() orelse return null;
        return iter.next();
    }

    pub fn version(request: HttpRequest) ?HttpVersion {
        var iter = std.mem.split(u8, request.data, " ");
        _ = iter.next() orelse return null;
        _ = iter.next() orelse return null;
        const version_str = iter.next() orelse return null;
        return HttpVersion.fromString(version_str) catch return null;
    }

    pub fn header(request: HttpRequest, header_name: []const u8) ?[]const u8 {
        // @todo Multiple header values
        var line_iter = std.mem.split(u8, request.data, "\r\n");
        _ = line_iter.next() orelse return null;

        while (line_iter.next()) |header_line| {
            if (std.mem.startsWith(u8, header_line, header_name)) {
                const delim_index = std.mem.indexOf(u8, header_line, ":") orelse return null;
                const header_value = header_line[delim_index + 1..];
                return std.mem.trim(u8, header_value, " ");
            }
        }

        return null;
    }

    pub fn body(request: HttpRequest) ?[]const u8 {
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

    pub fn uriMatches(request: HttpRequest, test_uri: []const u8) bool {
        if (request.uri()) |req_uri| {
            return std.mem.eql(u8, req_uri, test_uri);
        } else {
            return false;
        }
    }
};

// pub const HttpRequest = struct {
//     version: HttpVersion = .http_11,
//     method: HttpMethod,
//     uri: []const u8,
//     headers: std.StringHashMap([]const u8),
//     body: []const u8,

//     pub fn parse(allocator: *Allocator, data: []const u8) !HttpRequest {
//         if (data.len == 0) return error.NotEnoughData;

//         var request: HttpRequest = undefined;

//         var end_of_line = std.mem.indexOf(u8, data, "\r\n") orelse data.len;
//         if (end_of_line >= data.len - 2) return error.BadFormat;

//         var status_split_iter = std.mem.split(u8, data[0..end_of_line], " ");
//         var status_part_index: usize = 0;
//         while (status_split_iter.next()) |part| {
//             if (part.len == 0) continue;

//             if (status_part_index == 0) {
//                 request.method = try HttpMethod.fromString(part);
//             } else if (status_part_index == 1) {
//                 request.uri = part;
//             } else if (status_part_index == 2) {
//                 request.version = try HttpVersion.fromString(part);
//                 if (request.version != .http_11) {
//                     return error.UnsupportedVersion;
//                 }
//             } else {
//                 return error.BadFormat;
//             }

//             status_part_index += 1;
//         }

//         request.headers = std.StringHashMap([]const u8).init(allocator);
//         errdefer request.headers.deinit();

//         var line_iter = std.mem.split(u8, data[end_of_line + 2..], "\r\n");
//         var current_index: usize = end_of_line + 2;
//         while (line_iter.next()) |line| : (end_of_line += line.len) {
//             const trimmed_line = std.mem.trim(u8, line, " ");
//             if (std.mem.eql(u8, trimmed_line, "")) break;

//             var split_header = std.mem.split(u8, trimmed_line, ":");
//             const header_name = split_header.next() orelse return error.BadFormat;
//             const header_value = split_header.next() orelse return error.BadFormat;

//             try request.headers.put(std.mem.trim(u8, header_name, " "), std.mem.trim(u8, header_value, " "));
//         }

//         request.body = data[current_index..];

//         return request;
//     }

//     pub fn deinit(request: *HttpRequest) void {
//         request.headers.deinit();
//     }
// };
