const std = @import("std");

pub const ResponseStatus = enum(u32) {
    // 100 information responses
    @"continue" = 100,
    switching_protocol = 101,
    processing = 102,
    early_hints = 103,
    // 200 successful responses
    ok = 200,
    created = 201,
    accepted = 202,
    non_authoritative_information = 203,
    no_content = 204,
    reset_content = 205,
    partial_content = 206,
    multi_status = 207,
    already_reported = 208,
    im_used = 226,
    // 300 redirect responses
    multiple_choice = 300,
    moved_permanently = 301,
    found = 302,
    see_other = 303,
    not_modified = 304,
    temporary_redirect = 307,
    permanent_redirect = 308,
    // 400 client error responses
    bad_request = 400,
    unauthorized = 401,
    payment_required = 402,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    not_acceptable = 406,
    proxy_authentication_required = 407,
    request_timeout = 408,
    conflict = 409,
    gone = 410,
    length_required = 411,
    precondition_failed = 412,
    payload_too_large = 413,
    uri_too_long = 414,
    unsupported_media_type = 415,
    range_not_satisfiable = 416,
    expectation_failed = 417,
    im_a_teapot = 418,
    misdirected_request = 421,
    unprocessable_entity = 422,
    locked = 423,
    failed_dependency = 424,
    too_early = 425,
    upgrade_required = 426,
    precondition_required = 428,
    too_many_requests = 429,
    request_header_field_too_large = 431,
    unavailable_for_legal_reasons = 451,
    // 500 server error responses
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,
    http_version_not_supported = 505,
    variant_also_negotiates = 506,
    insufficient_storage = 507,
    loop_detected = 508,
    not_extended = 510,
    network_authentication_required = 511,

    pub fn getMessage(status: ResponseStatus) []const u8 {
        return switch (status) {
            .@"continue" => "Continue",
            .switching_protocol => "Switching Protocol",
            .processing => "Processing",
            .early_hints => "Early Hints",
            .ok => "OK",
            .created => "Created",
            .accepted => "Accepted",
            .non_authoritative_information => "Non Authoritative Information",
            .no_content => "No Content",
            .reset_content => "Reset Content",
            .partial_content => "Partial Content",
            .multi_status => "Multi Status",
            .already_reported => "Already Reported",
            .im_used => "IM Used",
            .multiple_choice => "Multiple Choice",
            .moved_permanently => "Moved Permanently",
            .found => "Found",
            .see_other => "See Other",
            .not_modified => "Not Modified",
            .temporary_redirect => "Temporary Redirect",
            .permanent_redirect => "Permanent Redirect",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .payment_required => "Payment Required",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .not_acceptable => "Not Acceptable",
            .proxy_authentication_required => "Proxy Authentication Required",
            .request_timeout => "Request Timeout",
            .conflict => "Conflict",
            .gone => "Gone",
            .length_required => "Length Required",
            .precondition_failed => "Precondition Failed",
            .payload_too_large => "Payload Too Large",
            .uri_too_long => "URI Too Long",
            .unsupported_media_type => "Unsupported Media Type",
            .range_not_satisfiable => "Range Not Satisfiable",
            .expectation_failed => "Expectation Failed",
            .im_a_teapot => "I'm a Teapot",
            .misdirected_request => "Misdirected Request",
            .unprocessable_entity => "Unprocessable Entity",
            .locked => "Locked",
            .failed_dependency => "Failed Dependency",
            .too_early => "Too Early",
            .upgrade_required => "Upgrade Required",
            .precondition_required => "Precondition Required",
            .too_many_requests => "Too Many Requests",
            .request_header_field_too_large => "Request Header Field Too Large",
            .unavailable_for_legal_reasons => "Unavailable For Legal Reasons",
            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .bad_gateway => "Bad Gateway",
            .service_unavailable => "Service Unavailable",
            .gateway_timeout => "Gateway Timeout",
            .http_version_not_supported => "HTTP Version Not Supported",
            .variant_also_negotiates => "Variant Also Negotiates",
            .insufficient_storage => "Insufficient Storage",
            .loop_detected => "Loop Detected",
            .not_extended => "Not Extended",
            .network_authentication_required => "Network Authentication Required",
        };
    }
};

const Response = @This();

pub const FixedBufferWriter = Writer(std.io.FixedBufferStream([]u8).Writer);

pub fn Writer(comptime W: type) type {
    return struct {
        const Self = @This();

        body_started: bool = false,

        writer: W,

        pub fn writeStatus(self: Self, status: ResponseStatus) !void {
            try self.writer.print("HTTP/1.1 {} {s}\r\n", .{ @intFromEnum(status), status.getMessage() });
        }

        pub fn printHeader(self: Self, comptime header_format_string: []const u8, header_values: anytype) !void {
            const format_string = header_format_string ++ "\r\n";
            try self.writer.print(format_string, header_values);
        }

        pub fn writeHeader(self: Self, header: []const u8) !void {
            try self.writer.print("{s}\r\n", .{header});
        }

        pub fn writeBody(self: *Self, body: []const u8) !void {
            if (!self.body_started) {
                try self.writer.writeAll("\r\n");
                self.body_started = true;
            }
            try self.writer.writeAll(body);
        }

        pub fn complete(self: Self) !void {
            try self.writer.writeAll("\r\n");
        }
    };
}

data: []const u8,

pub fn getStatus(response: Response) !ResponseStatus {
    for (response.data, 0..) |c, index| {
        if (c == ' ') {
            const status_end_index = std.mem.indexOfPos(u8, response.data, index + 1, " ") orelse return error.InvalidStatus;
            const status_val = std.fmt.parseInt(u32, response.data[index + 1 .. status_end_index], 10) catch return error.InvalidStatus;
            return std.meta.intToEnum(ResponseStatus, status_val) catch return error.InvalidStatus;
        }
    }
    return error.InvalidStatus;
}

pub fn findHeader(response: Response, header_name: []const u8) ?[]const u8 {
    var line_iter = std.mem.split(u8, response.data, "\r\n");
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

pub fn getBody(response: Response) []const u8 {
    var line_iter = std.mem.split(u8, response.data, "\r\n");

    var index: usize = 0;
    while (line_iter.next()) |line| : (index += line.len + 2) {
        if (line.len == 0) break;
    }

    var end_index = response.data.len;
    if (std.mem.endsWith(u8, response.data, "\r\n")) {
        end_index -= 2;
    }

    return response.data[index + 2 .. end_index];
}

pub fn writer(inner_writer: anytype) Writer(@TypeOf(inner_writer)) {
    return Writer(@TypeOf(inner_writer)){ .writer = inner_writer };
}

test "parse status code" {
    const response_data = "HTTP/1.1 302 Found\r\nBogus: Value\r\n\r\nbody\r\n";

    var response = Response{ .data = response_data };

    const status = try response.getStatus();
    try std.testing.expectEqual(ResponseStatus.found, status);
}

test "find header value" {
    const response_data = "HTTP/1.1 200 OK\r\nBogus: Value\r\nAnother: Val, val2\r\nSomething-Else: XX\r\n\r\nbody\r\n";

    var response = Response{ .data = response_data };

    const header_val = response.findHeader("another").?;
    try std.testing.expectEqualStrings("Val, val2", header_val);
}

test "get body content" {
    const response_data = "HTTP/1.1 200 OK\r\nBogus: Value\r\nAnother: Val, val2\r\nSomething-Else: XX\r\n\r\nbody\ntext\r\n";

    var response = Response{ .data = response_data };

    const body = response.getBody();
    try std.testing.expectEqualStrings("body\ntext", body);
}
