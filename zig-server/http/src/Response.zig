const std = @import("std");
const Allocator = std.mem.Allocator;

const HttpVersion = @import("Request.zig").HttpVersion;

const Response = @This();

pub const ResponseStatus = enum(u32) {
    // 100 information responses
    @"continue"                     = 100,
    switching_protocol              = 101,
    processing                      = 102,
    early_hints                     = 103,
    // 200 successful responses
    ok                              = 200,
    created                         = 201,
    accepted                        = 202,
    non_authoritative_information   = 203,
    no_content                      = 204,
    reset_content                   = 205,
    partial_content                 = 206,
    multi_status                    = 207,
    already_reported                = 208,
    im_used                         = 226,
    // 300 redirect responses
    multiple_choice                 = 300,
    moved_permanently               = 301,
    found                           = 302,
    see_other                       = 303,
    not_modified                    = 304,
    temporary_redirect              = 307,
    permanent_redirect              = 308,
    // 400 client error responses
    bad_request                     = 400,
    unauthorized                    = 401,
    payment_required                = 402,
    forbidden                       = 403,
    not_found                       = 404,
    method_not_allowed              = 405,
    not_acceptable                  = 406,
    proxy_authentication_required   = 407,
    request_timeout                 = 408,
    conflict                        = 409,
    gone                            = 410,
    length_required                 = 411,
    precondition_failed             = 412,
    payload_too_large               = 413,
    uri_too_long                    = 414,
    unsupported_media_type          = 415,
    range_not_satisfiable           = 416,
    expectation_failed              = 417,
    im_a_teapot                     = 418,
    misdirected_request             = 421,
    unprocessable_entity            = 422,
    locked                          = 423,
    failed_dependency               = 424,
    too_early                       = 425,
    upgrade_required                = 426,
    precondition_required           = 428,
    too_many_requests               = 429,
    request_header_field_too_large  = 431,
    unavailable_for_legal_reasons   = 451,
    // 500 server error responses
    internal_server_error           = 500,
    not_implemented                 = 501,
    bad_gateway                     = 502,
    service_unavailable             = 503,
    gateway_timeout                 = 504,
    http_version_not_supported      = 505,
    variant_also_negotiates         = 506,
    insufficient_storage            = 507,
    loop_detected                   = 508,
    not_extended                    = 510,
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

version: HttpVersion = .http_11,
status: ResponseStatus = .ok,
headers: std.StringHashMap([]const u8),
body: ?[]const u8 = null,

allocator: Allocator,

pub fn init(allocator: Allocator) Response {
    return Response{
        .headers = std.StringHashMap([]const u8).init(allocator),
        .allocator = allocator,
    };
}

pub fn initStatus(allocator: Allocator, status: ResponseStatus) Response {
    return Response{
        .headers = std.StringHashMap([]const u8).init(allocator),
        .status = status,
        .allocator = allocator,
    };
}

pub fn deinit(response: *Response) void {
    response.headers.deinit();
}

pub fn header(response: *Response, header_name: []const u8, header_value: anytype) !void {
    const header_str_value = if (comptime std.meta.trait.isZigString(@TypeOf(header_value))) 
            header_value
        else 
            try std.fmt.allocPrint(response.allocator, "{}", .{header_value});
    
    var entry = try response.headers.getOrPut(header_name);
    if (entry.found_existing) {
        // This header has already been set, so append the new value to it instead of overwriting it
        const concat_header_vals = try std.fmt.allocPrint(response.allocator, "{s}, {s}", .{entry.value_ptr.*, header_str_value});
        entry.value_ptr.* = concat_header_vals;
    } else {
        // This header has not been set, so initialize it
        entry.value_ptr.* = header_str_value;
    }
}

pub fn write(response: *const Response, writer: anytype) !void {
    const status_code = @enumToInt(response.status);
    const status_reason_phrase = response.status.getMessage();

    try writer.print("{s} {} {s}\r\n", .{response.version.toString(), status_code, status_reason_phrase});

    var header_iter = response.headers.iterator();
    while (header_iter.next()) |entry| {
        try writer.print("{s}: {s}\r\n", .{entry.key_ptr.*, entry.value_ptr.*});
    }

    try writer.writeAll("\r\n");

    if (response.body) |body| {
        if (response.headers.get("Transfer-Encoding")) |transfer_encoding| {
            if (std.ascii.eqlIgnoreCase(transfer_encoding, "chunked")) {
                // Size of the chunk, in bytes
                const chunk_size: usize = 200;
                var transferred_size: usize = 0;
                while (transferred_size < body.len) : (transferred_size += chunk_size) {
                    const next_chunk_end = if (transferred_size + chunk_size >= body.len) body.len else transferred_size + chunk_size;
                    const next_chunk_size = next_chunk_end - transferred_size;
                    try writer.print("{x}\r\n{s}\r\n", .{ next_chunk_size, body[transferred_size..next_chunk_end]});
                }
                return;
            }
        }
        try writer.writeAll(body);
    }
}

pub fn writeAlloc(response: *const Response, allocator: Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    try response.write(buffer.writer());
    return buffer.toOwnedSlice();
}